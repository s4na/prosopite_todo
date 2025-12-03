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

    def add_entry(fingerprint:, query:, location: nil)
      return if ignored?(fingerprint)

      entry = {
        "fingerprint" => fingerprint,
        "query" => query,
        "location" => location,
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

    private

    def load_entries
      return [] unless File.exist?(@path)

      content = YAML.safe_load(File.read(@path), permitted_classes: [Time], aliases: true)
      content || []
    end
  end
end
