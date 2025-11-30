# frozen_string_literal: true

require "digest"

module ProsopiteTodo
  class Scanner
    class << self
      def fingerprint(query:, location:)
        normalized_location = normalize_location(location)
        content = "#{query}|#{normalized_location}"
        Digest::SHA256.hexdigest(content)[0, 16]
      end

      def filter_notifications(notifications, todo_file)
        result = {}

        notifications.each do |query, locations_array|
          filtered_locations = locations_array.reject do |location|
            fp = fingerprint(query: query, location: location)
            todo_file.ignored?(fp)
          end

          result[query] = filtered_locations unless filtered_locations.empty?
        end

        result
      end

      def record_notifications(notifications, todo_file)
        notifications.each do |query, locations_array|
          locations_array.each do |location|
            fp = fingerprint(query: query, location: location)
            todo_file.add_entry(
              fingerprint: fp,
              query: query,
              location: normalize_location(location)
            )
          end
        end
      end

      private

      def normalize_location(location)
        Array(location).join(" -> ")
      end
    end
  end
end
