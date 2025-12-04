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
      fingerprints.include?(fingerprint) || legacy_fingerprints.include?(fingerprint)
    end

    # Legacy fingerprints for backward compatibility
    # Entries without test_location use old fingerprint format (query|location)
    # We need to check both old and new format to avoid duplicate entries
    # Note: Not memoized because entries can be modified by filter_by_test_locations! or add_entry
    def legacy_fingerprints
      entries
        .select { |e| e["test_location"].nil? || e["test_location"].to_s.strip.empty? }
        .map { |e| e["fingerprint"] }
    end

    def add_entry(fingerprint:, query:, location: nil, test_location: nil)
      return if ignored?(fingerprint)

      entry = {
        "fingerprint" => fingerprint,
        "query" => query,
        "location" => location,
        "test_location" => test_location,
        "created_at" => Time.now.utc.iso8601
      }
      entries << entry
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

    # Filter entries by test locations - only removes entries for tests that were run
    # Entries for tests that were NOT run are preserved
    # @param fingerprints [Set] set of fingerprints detected in current run
    # @param test_locations [Set] set of test locations that were run
    # @return [Integer] number of removed entries
    def filter_by_test_locations!(fingerprints, test_locations)
      original_count = entries.length
      @entries = entries.select do |entry|
        entry_test_loc = entry["test_location"]

        if entry_test_loc.nil? || entry_test_loc.to_s.empty?
          # Legacy entries without test_location - keep them (conservative)
          true
        elsif test_locations.include?(entry_test_loc)
          # This entry's test was run - keep only if still detected
          fingerprints.include?(entry["fingerprint"])
        else
          # This entry's test was NOT run - preserve it
          true
        end
      end
      original_count - @entries.length
    end

    # Get all unique test locations in the TODO file
    # @return [Set] set of test locations
    def test_locations
      Set.new(entries.map { |e| e["test_location"] }.compact.reject(&:empty?))
    end

    private

    def load_entries
      return [] unless File.exist?(@path)

      content = YAML.safe_load(File.read(@path), permitted_classes: [Time], aliases: true)
      content || []
    end
  end
end
