# frozen_string_literal: true

require "digest"
require "set"

module ProsopiteTodo
  class Scanner
    class << self
      def fingerprint(query:, location:)
        cleaned_location = clean_location(location)
        normalized_location = normalize_location(cleaned_location)
        content = "#{query}|#{normalized_location}"
        Digest::SHA256.hexdigest(content)[0, 16]
      end

      # Filter notifications based on TODO file
      # Supports both Prosopite format (from railtie) and internal format (from tests)
      #
      # Prosopite format: { [query1, query2, ...] => [frame1, frame2, ...] }
      # Internal format: { query => [[frame1, frame2], [frame3, frame4]] }
      def filter_notifications(notifications, todo_file)
        result = {}

        notifications.each do |query_key, locations_value|
          # Detect Prosopite format: key is array of queries, value is flat stack frames
          if query_key.is_a?(Array) && query_key.first.is_a?(String) && query_key.first.match?(/\A\s*SELECT/i)
            # Prosopite format: single notification per entry
            query = query_key.first
            call_stack = Array(locations_value)
            fp = fingerprint(query: query, location: call_stack)

            unless todo_file.ignored?(fp)
              result[query_key] = locations_value
            end
          else
            # Internal format: multiple locations per query
            query = query_key
            locations_array = locations_value
            filtered_locations = locations_array.reject do |location|
              fp = fingerprint(query: query, location: location)
              todo_file.ignored?(fp)
            end

            result[query] = filtered_locations unless filtered_locations.empty?
          end
        end

        result
      end

      def record_notifications(notifications, todo_file)
        notifications.each do |query, locations_array|
          locations_array.each do |location|
            fp = fingerprint(query: query, location: location)
            cleaned_location = clean_location(location)
            todo_file.add_entry(
              fingerprint: fp,
              query: query,
              location: normalize_location(cleaned_location)
            )
          end
        end
      end

      # Extract all fingerprints from notifications
      # @param notifications [Hash] query => locations_array
      # @return [Set] set of fingerprints
      def extract_fingerprints(notifications)
        fingerprints = Set.new
        notifications.each do |query, locations_array|
          locations_array.each do |location|
            fingerprints << fingerprint(query: query, location: location)
          end
        end
        fingerprints
      end

      private

      # Filter and limit stack frames to show only relevant application code.
      # Uses custom location_filter if configured, otherwise falls back to
      # Rails.backtrace_cleaner when available.
      def clean_location(location)
        frames = Array(location)
        return frames if frames.empty?

        config = ProsopiteTodo.configuration

        # Apply custom filter if configured
        cleaned_frames = if config.location_filter
                           apply_custom_filter(config.location_filter, frames)
                         elsif defined?(Rails) && Rails.respond_to?(:backtrace_cleaner)
                           Rails.backtrace_cleaner.clean(frames)
                         else
                           frames
                         end

        # Apply frame limit
        max_frames = config.max_location_frames
        if max_frames && max_frames.positive? && cleaned_frames.length > max_frames
          cleaned_frames = cleaned_frames.first(max_frames)
        end

        cleaned_frames
      end

      # Apply custom filter with error handling.
      # Falls back to original frames if filter raises an error or returns non-array.
      def apply_custom_filter(filter, frames)
        result = filter.call(frames)

        unless result.is_a?(Array)
          warn "[ProsopiteTodo] location_filter must return an Array, got #{result.class}. Using original frames."
          return frames
        end

        result
      rescue StandardError => e
        warn "[ProsopiteTodo] Error in location_filter: #{e.message}. Using original frames."
        frames
      end

      def normalize_location(location)
        Array(location).join(" -> ")
      end
    end
  end
end
