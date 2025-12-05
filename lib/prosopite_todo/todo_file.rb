# frozen_string_literal: true

require "yaml"
require "time"

module ProsopiteTodo
  class TodoFile
    DEFAULT_FILENAME = ".prosopite_todo.yaml"

    attr_reader :path

    def self.default_path
      File.join(Dir.pwd, DEFAULT_FILENAME)
    end

    def initialize(path = nil)
      @path = path || self.class.default_path
      @entries = nil
    end

    def entries
      @entries ||= load_entries
    end

    def fingerprints
      entries.map { |entry| entry["fingerprint"] }
    end

    def ignored?(fingerprint)
      fingerprints.include?(fingerprint)
    end

    # Check if a specific location is already in the entry for a fingerprint
    # @param fingerprint [String] the entry fingerprint
    # @param location [String] the normalized location string
    # @return [Boolean] true if location already exists
    def location_exists?(fingerprint, location)
      entry = find_entry(fingerprint)
      return false unless entry

      entry["locations"]&.any? { |loc| loc["location"] == location }
    end

    # Find entry by fingerprint
    # @param fingerprint [String] the entry fingerprint
    # @return [Hash, nil] the entry or nil
    def find_entry(fingerprint)
      entries.find { |e| e["fingerprint"] == fingerprint }
    end

    # Add a new entry or add location to existing entry
    # @param fingerprint [String] the entry fingerprint (based on query only)
    # @param query [String] the normalized SQL query
    # @param location [String] the normalized location string
    # @param test_location [String, nil] the test file location
    def add_entry(fingerprint:, query:, location: nil, test_location: nil)
      existing = find_entry(fingerprint)

      if existing
        # Add location to existing entry if not already present
        add_location_to_entry(existing, location, test_location)
      else
        # Create new entry
        entry = {
          "fingerprint" => fingerprint,
          "query" => query,
          "locations" => [],
          "created_at" => Time.now.utc.iso8601
        }
        add_location_to_entry(entry, location, test_location)
        entries << entry
      end
    end

    private def add_location_to_entry(entry, location, test_location)
      return if location.nil?

      # Check if this location already exists
      existing_loc = entry["locations"]&.find { |loc| loc["location"] == location }
      return if existing_loc

      entry["locations"] ||= []
      entry["locations"] << {
        "location" => location,
        "test_location" => test_location
      }
    end

    def save
      File.write(@path, entries.to_yaml)
    end

    def clear
      @entries = []
    end

    # Filter entries to keep only those with fingerprints in the given set
    # @param fingerprints [Set] set of fingerprints to keep
    # @return [Integer] number of removed entries
    def filter_by_fingerprints!(fingerprints)
      original_count = entries.length
      @entries = entries.select { |entry| fingerprints.include?(entry["fingerprint"]) }
      original_count - @entries.length
    end

    # Filter entries by test locations - removes locations for tests that were run but no longer detect N+1
    # Entries for tests that were NOT run are preserved
    # @param detected_locations [Set<Hash>] set of detected location hashes {fingerprint:, location:, test_location:}
    # @param test_locations [Set] set of test locations that were run
    # @return [Integer] number of removed locations (across all entries)
    def filter_by_test_locations!(detected_locations, test_locations)
      removed_count = 0

      entries.each do |entry|
        original_location_count = entry["locations"]&.length || 0

        entry["locations"] = entry["locations"]&.select do |loc|
          loc_test = loc["test_location"]

          if loc_test.nil? || loc_test.to_s.empty?
            # Locations without test_location - keep them (conservative)
            true
          elsif test_locations.include?(loc_test)
            # This location's test was run - keep only if still detected
            # Note: We intentionally match only fingerprint + location, not test_location.
            # The same location can be detected by multiple tests, and we want to keep
            # the location if it's detected by ANY test, not just the original one.
            detected_locations.any? do |det|
              det[:fingerprint] == entry["fingerprint"] &&
                det[:location] == loc["location"]
            end
          else
            # This location's test was NOT run - preserve it
            true
          end
        end || []

        removed_count += original_location_count - entry["locations"].length
      end

      # Remove entries with no locations
      @entries = entries.reject { |e| e["locations"].empty? }

      removed_count
    end

    # Get all unique test locations in the TODO file
    # @return [Set] set of test locations
    def test_locations
      locations = entries.flat_map do |entry|
        entry["locations"]&.map { |loc| loc["test_location"] } || []
      end
      Set.new(locations.compact.reject(&:empty?))
    end

    private

    def load_entries
      return [] unless File.exist?(@path)

      content = YAML.safe_load(File.read(@path), permitted_classes: [Time], aliases: true)
      content || []
    end
  end
end
