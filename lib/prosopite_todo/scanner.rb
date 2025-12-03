# frozen_string_literal: true

require "digest"

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
                           config.location_filter.call(frames)
                         elsif defined?(Rails) && Rails.respond_to?(:backtrace_cleaner)
                           Rails.backtrace_cleaner.clean(frames)
                         else
                           frames
                         end

        # Apply frame limit
        max_frames = config.max_location_frames
        if max_frames && cleaned_frames.length > max_frames
          cleaned_frames = cleaned_frames.first(max_frames)
        end

        cleaned_frames
      end

      def normalize_location(location)
        Array(location).join(" -> ")
      end
    end
  end
end
