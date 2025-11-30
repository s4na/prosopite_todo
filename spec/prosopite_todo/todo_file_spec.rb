# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"

RSpec.describe ProsopiteTodo::TodoFile do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:todo_file_path) { File.join(tmp_dir, ".prosopite_todo.yaml") }

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  describe ".default_path" do
    it "returns .prosopite_todo.yaml in current directory" do
      expect(described_class.default_path).to eq(File.join(Dir.pwd, ".prosopite_todo.yaml"))
    end
  end

  describe "#initialize" do
    it "accepts custom file path" do
      todo_file = described_class.new(todo_file_path)
      expect(todo_file.path).to eq(todo_file_path)
    end

    it "uses default path when not specified" do
      todo_file = described_class.new
      expect(todo_file.path).to eq(described_class.default_path)
    end
  end

  describe "#entries" do
    context "when file does not exist" do
      it "returns empty array" do
        todo_file = described_class.new(todo_file_path)
        expect(todo_file.entries).to eq([])
      end
    end

    context "when file exists with entries" do
      before do
        File.write(todo_file_path, <<~YAML)
          ---
          - fingerprint: "abc123"
            query: "SELECT * FROM users"
            location: "app/models/user.rb:10"
            created_at: "2024-01-01T00:00:00Z"
          - fingerprint: "def456"
            query: "SELECT * FROM posts"
            location: "app/models/post.rb:20"
            created_at: "2024-01-01T00:00:00Z"
        YAML
      end

      it "returns parsed entries" do
        todo_file = described_class.new(todo_file_path)
        entries = todo_file.entries

        expect(entries.length).to eq(2)
        expect(entries[0]["fingerprint"]).to eq("abc123")
        expect(entries[0]["query"]).to eq("SELECT * FROM users")
        expect(entries[1]["fingerprint"]).to eq("def456")
      end
    end
  end

  describe "#fingerprints" do
    before do
      File.write(todo_file_path, <<~YAML)
        ---
        - fingerprint: "abc123"
          query: "SELECT * FROM users"
        - fingerprint: "def456"
          query: "SELECT * FROM posts"
      YAML
    end

    it "returns array of fingerprints" do
      todo_file = described_class.new(todo_file_path)
      expect(todo_file.fingerprints).to eq(["abc123", "def456"])
    end
  end

  describe "#ignored?" do
    before do
      File.write(todo_file_path, <<~YAML)
        ---
        - fingerprint: "abc123"
          query: "SELECT * FROM users"
      YAML
    end

    it "returns true for fingerprint in todo file" do
      todo_file = described_class.new(todo_file_path)
      expect(todo_file.ignored?("abc123")).to be true
    end

    it "returns false for fingerprint not in todo file" do
      todo_file = described_class.new(todo_file_path)
      expect(todo_file.ignored?("xyz789")).to be false
    end
  end

  describe "#add_entry" do
    it "adds a new entry to the file" do
      todo_file = described_class.new(todo_file_path)

      todo_file.add_entry(
        fingerprint: "new123",
        query: "SELECT * FROM comments",
        location: "app/models/comment.rb:5"
      )

      expect(todo_file.entries.length).to eq(1)
      expect(todo_file.entries[0]["fingerprint"]).to eq("new123")
      expect(todo_file.entries[0]["query"]).to eq("SELECT * FROM comments")
    end

    it "does not add duplicate fingerprints" do
      todo_file = described_class.new(todo_file_path)

      todo_file.add_entry(fingerprint: "dup123", query: "SELECT 1")
      todo_file.add_entry(fingerprint: "dup123", query: "SELECT 1")

      expect(todo_file.entries.length).to eq(1)
    end
  end

  describe "#save" do
    it "persists entries to file" do
      todo_file = described_class.new(todo_file_path)
      todo_file.add_entry(fingerprint: "save123", query: "SELECT * FROM users")
      todo_file.save

      reloaded = described_class.new(todo_file_path)
      expect(reloaded.entries.length).to eq(1)
      expect(reloaded.entries[0]["fingerprint"]).to eq("save123")
    end
  end

  describe "#clear" do
    before do
      File.write(todo_file_path, <<~YAML)
        ---
        - fingerprint: "abc123"
          query: "SELECT * FROM users"
      YAML
    end

    it "removes all entries" do
      todo_file = described_class.new(todo_file_path)
      todo_file.clear
      todo_file.save

      expect(todo_file.entries).to eq([])
    end
  end
end
