# frozen_string_literal: true

require "digest"
require "set"

module ProsopiteTodo
  class Scanner
    class << self
      # Generate a unique fingerprint for an N+1 query detection
      # @param query [String] the SQL query
      # @param location [Array, String] the call stack location
      # @param test_location [String, nil] the test file location
      def fingerprint(query:, location:, test_location: nil)
        cleaned_location = clean_location(location)
        normalized_location = normalize_location(cleaned_location)
        normalized_query = normalize_query(query)
        normalized_test_location = normalize_test_location(test_location)
        content = "#{normalized_query}|#{normalized_location}|#{normalized_test_location}"
        Digest::SHA256.hexdigest(content)[0, 16]
      end

      # Normalize query by replacing literals with placeholders
      # This reduces duplicate entries for the same N+1 pattern with different IDs
      #
      # Strategy:
      # 1. Replace string literals first to avoid normalizing numbers inside strings
      #    e.g., "WHERE ip = '192.168.1.1'" -> "WHERE ip = ?"
      # 2. Replace numeric values while preserving PostgreSQL placeholders ($1, $2)
      #    e.g., "WHERE id = 123" -> "WHERE id = ?"
      #    but  "WHERE id = $1" -> "WHERE id = $1" (unchanged)
      #
      # @param query [String] the SQL query
      # @return [String] normalized query with numbers replaced by ?
      def normalize_query(query)
        return query if query.nil? || query.empty?

        result = query.dup

        # Replace string literals (single quotes) as a whole
        # Handle escaped quotes ('') within string literals
        result.gsub!(/'(?:[^']|'')*'/, "?")

        # Replace numeric literals but preserve $N style placeholders
        result.gsub!(/(?<!\$)\b\d+(\.\d+)?\b/, "?")

        result
      end

      # Filter notifications based on TODO file
      # Supports both Prosopite format (from railtie) and internal format
      #
      # Prosopite format: { [query1, query2, ...] => [frame1, frame2, ...] }
      # Internal format: { query => [{ call_stack: [...], test_location: "..." }, ...] }
      def filter_notifications(notifications, todo_file)
        result = {}

        notifications.each do |query_key, locations_value|
          # Detect Prosopite format: key is array of queries, value is flat stack frames
          if query_key.is_a?(Array) && query_key.first.is_a?(String) && query_key.first.match?(/\A\s*SELECT/i)
            # Prosopite format: single notification per entry
            query = query_key.first
            call_stack = Array(locations_value)
            # For Prosopite format, test_location is extracted from pending_notifications
            # This is used for filtering only, not for recording
            fp = fingerprint(query: query, location: call_stack, test_location: nil)

            unless todo_file.ignored?(fp)
              result[query_key] = locations_value
            end
          else
            # Internal format: multiple locations per query (with test_location)
            query = query_key
            locations_array = locations_value
            filtered_locations = locations_array.reject do |loc_entry|
              call_stack = extract_call_stack(loc_entry)
              test_loc = extract_test_location(loc_entry)
              fp = fingerprint(query: query, location: call_stack, test_location: test_loc)
              todo_file.ignored?(fp)
            end

            result[query] = filtered_locations unless filtered_locations.empty?
          end
        end

        result
      end

      def record_notifications(notifications, todo_file)
        notifications.each do |query, locations_array|
          locations_array.each do |loc_entry|
            call_stack = extract_call_stack(loc_entry)
            test_loc = extract_test_location(loc_entry)
            fp = fingerprint(query: query, location: call_stack, test_location: test_loc)
            cleaned_location = clean_location(call_stack)
            normalized_query = normalize_query(query)
            todo_file.add_entry(
              fingerprint: fp,
              query: normalized_query,
              location: normalize_location(cleaned_location),
              test_location: normalize_test_location(test_loc)
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
          locations_array.each do |loc_entry|
            call_stack = extract_call_stack(loc_entry)
            test_loc = extract_test_location(loc_entry)
            fingerprints << fingerprint(query: query, location: call_stack, test_location: test_loc)
          end
        end
        fingerprints
      end

      # Extract test locations from notifications
      # @param notifications [Hash] query => locations_array
      # @return [Set] set of normalized test locations
      def extract_test_locations(notifications)
        test_locations = Set.new
        notifications.each do |_query, locations_array|
          locations_array.each do |loc_entry|
            test_loc = extract_test_location(loc_entry)
            normalized = normalize_test_location(test_loc)
            test_locations << normalized if normalized
          end
        end
        test_locations
      end

      private

      # Extract call_stack from location entry
      # Supports both new format (Hash with :call_stack) and legacy format (Array)
      def extract_call_stack(loc_entry)
        if loc_entry.is_a?(Hash)
          loc_entry[:call_stack] || loc_entry["call_stack"]
        else
          loc_entry
        end
      end

      # Extract test_location from location entry
      # Returns nil for legacy format entries
      def extract_test_location(loc_entry)
        return nil unless loc_entry.is_a?(Hash)

        loc_entry[:test_location] || loc_entry["test_location"]
      end

      # Normalize test location for consistent fingerprinting
      # Removes line numbers to group by test file, not specific line
      def normalize_test_location(test_location)
        return nil if test_location.nil? || test_location.to_s.empty?

        # Remove line number suffix (e.g., "spec/models/user_spec.rb:25" -> "spec/models/user_spec.rb")
        test_location.to_s.sub(/:\d+\z/, "")
      end

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
