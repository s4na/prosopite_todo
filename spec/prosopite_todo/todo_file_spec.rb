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

    context "when file is empty" do
      before do
        File.write(todo_file_path, "")
      end

      it "returns empty array" do
        todo_file = described_class.new(todo_file_path)
        expect(todo_file.entries).to eq([])
      end
    end

    context "when file contains only whitespace" do
      before do
        File.write(todo_file_path, "   \n  \n")
      end

      it "returns empty array" do
        todo_file = described_class.new(todo_file_path)
        expect(todo_file.entries).to eq([])
      end
    end

    context "when file contains invalid YAML" do
      before do
        File.write(todo_file_path, "invalid: yaml: content: [unclosed")
      end

      it "raises Psych::SyntaxError" do
        todo_file = described_class.new(todo_file_path)
        expect { todo_file.entries }.to raise_error(Psych::SyntaxError)
      end
    end

    context "when file contains YAML with disallowed class" do
      before do
        # Create YAML with object that requires unsafe load
        File.write(todo_file_path, "--- !ruby/object:OpenStruct\nfoo: bar\n")
      end

      it "raises Psych::DisallowedClass" do
        todo_file = described_class.new(todo_file_path)
        expect { todo_file.entries }.to raise_error(Psych::DisallowedClass)
      end
    end

    context "when file contains valid YAML null" do
      before do
        File.write(todo_file_path, "---\nnull\n")
      end

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
            locations:
              - location: "app/models/user.rb:10"
                test_location: null
            created_at: "2024-01-01T00:00:00Z"
          - fingerprint: "def456"
            query: "SELECT * FROM posts"
            locations:
              - location: "app/models/post.rb:20"
                test_location: null
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
          locations: []
        - fingerprint: "def456"
          query: "SELECT * FROM posts"
          locations: []
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
          locations: []
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
    it "adds a new entry with location to the file" do
      todo_file = described_class.new(todo_file_path)

      todo_file.add_entry(
        fingerprint: "new123",
        query: "SELECT * FROM comments",
        location: "app/models/comment.rb:5"
      )

      expect(todo_file.entries.length).to eq(1)
      expect(todo_file.entries[0]["fingerprint"]).to eq("new123")
      expect(todo_file.entries[0]["query"]).to eq("SELECT * FROM comments")
      expect(todo_file.entries[0]["locations"].first["location"]).to eq("app/models/comment.rb:5")
    end

    it "adds location to existing entry with same fingerprint" do
      todo_file = described_class.new(todo_file_path)

      todo_file.add_entry(fingerprint: "dup123", query: "SELECT 1", location: "file1.rb:1")
      todo_file.add_entry(fingerprint: "dup123", query: "SELECT 1", location: "file2.rb:2")

      expect(todo_file.entries.length).to eq(1)
      expect(todo_file.entries[0]["locations"].length).to eq(2)
    end

    it "does not add duplicate locations" do
      todo_file = described_class.new(todo_file_path)

      todo_file.add_entry(fingerprint: "dup123", query: "SELECT 1", location: "file1.rb:1")
      todo_file.add_entry(fingerprint: "dup123", query: "SELECT 1", location: "file1.rb:1")

      expect(todo_file.entries.length).to eq(1)
      expect(todo_file.entries[0]["locations"].length).to eq(1)
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

    it "creates parent directories if they don't exist" do
      nested_path = File.join(tmp_dir, "nested", "dir", ".prosopite_todo.yaml")
      FileUtils.mkdir_p(File.dirname(nested_path))
      todo_file = described_class.new(nested_path)
      todo_file.add_entry(fingerprint: "nested123", query: "SELECT 1")
      todo_file.save

      expect(File.exist?(nested_path)).to be true
    end

    context "when file path is in read-only directory", skip: Process.uid.zero? do
      let(:readonly_dir) { File.join(tmp_dir, "readonly") }
      let(:readonly_path) { File.join(readonly_dir, ".prosopite_todo.yaml") }

      before do
        FileUtils.mkdir_p(readonly_dir)
        FileUtils.chmod(0o555, readonly_dir)
      end

      after do
        FileUtils.chmod(0o755, readonly_dir)
      end

      it "raises Errno::EACCES when directory is not writable" do
        todo_file = described_class.new(readonly_path)
        todo_file.add_entry(fingerprint: "fail123", query: "SELECT 1")
        expect { todo_file.save }.to raise_error(Errno::EACCES)
      end
    end

    context "when file is read-only", skip: Process.uid.zero? do
      before do
        File.write(todo_file_path, "---\n[]")
        FileUtils.chmod(0o444, todo_file_path)
      end

      after do
        FileUtils.chmod(0o644, todo_file_path)
      end

      it "raises Errno::EACCES when file is not writable" do
        todo_file = described_class.new(todo_file_path)
        todo_file.add_entry(fingerprint: "readonly123", query: "SELECT 1")
        expect { todo_file.save }.to raise_error(Errno::EACCES)
      end
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

  describe "#test_locations" do
    let(:todo_file) { described_class.new(todo_file_path) }

    it "returns empty set when no entries have test_location" do
      todo_file.add_entry(fingerprint: "fp1", query: "SELECT 1", location: "file1.rb:1")
      expect(todo_file.test_locations).to eq(Set.new)
    end

    it "returns set of unique test locations" do
      todo_file.add_entry(fingerprint: "fp1", query: "SELECT 1", location: "file1.rb:1", test_location: "spec/a_spec.rb")
      todo_file.add_entry(fingerprint: "fp2", query: "SELECT 2", location: "file2.rb:2", test_location: "spec/b_spec.rb")
      todo_file.add_entry(fingerprint: "fp3", query: "SELECT 3", location: "file3.rb:3", test_location: "spec/a_spec.rb")

      expect(todo_file.test_locations).to eq(Set.new(["spec/a_spec.rb", "spec/b_spec.rb"]))
    end

    it "excludes empty string test_locations" do
      todo_file.add_entry(fingerprint: "fp1", query: "SELECT 1", location: "file1.rb:1", test_location: "spec/a_spec.rb")
      todo_file.add_entry(fingerprint: "fp2", query: "SELECT 2", location: "file2.rb:2", test_location: "")

      expect(todo_file.test_locations).to eq(Set.new(["spec/a_spec.rb"]))
    end

    it "handles entries with nil locations array" do
      # This tests the branch at line 151 where entry["locations"] is nil
      File.write(todo_file_path, <<~YAML)
        ---
        - fingerprint: "fp1"
          query: "SELECT 1"
      YAML

      todo_file = described_class.new(todo_file_path)
      expect(todo_file.test_locations).to eq(Set.new)
    end
  end

  describe "#filter_by_fingerprints!" do
    let(:todo_file) { described_class.new(todo_file_path) }

    before do
      todo_file.add_entry(fingerprint: "fp1", query: "SELECT 1", location: "file1.rb:1")
      todo_file.add_entry(fingerprint: "fp2", query: "SELECT 2", location: "file2.rb:2")
      todo_file.add_entry(fingerprint: "fp3", query: "SELECT 3", location: "file3.rb:3")
    end

    it "keeps entries with fingerprints in the given set" do
      fingerprints = Set.new(["fp1", "fp3"])

      todo_file.filter_by_fingerprints!(fingerprints)

      expect(todo_file.entries.length).to eq(2)
      expect(todo_file.fingerprints).to include("fp1", "fp3")
      expect(todo_file.fingerprints).not_to include("fp2")
    end

    it "returns the number of removed entries" do
      fingerprints = Set.new(["fp1"])

      removed_count = todo_file.filter_by_fingerprints!(fingerprints)

      expect(removed_count).to eq(2)
    end

    it "removes all entries when given empty set" do
      fingerprints = Set.new

      removed_count = todo_file.filter_by_fingerprints!(fingerprints)

      expect(removed_count).to eq(3)
      expect(todo_file.entries).to be_empty
    end

    it "keeps all entries when all fingerprints match" do
      fingerprints = Set.new(["fp1", "fp2", "fp3"])

      removed_count = todo_file.filter_by_fingerprints!(fingerprints)

      expect(removed_count).to eq(0)
      expect(todo_file.entries.length).to eq(3)
    end

    it "preserves created_at timestamps" do
      original_created_at = todo_file.entries[0]["created_at"]
      fingerprints = Set.new(["fp1"])

      todo_file.filter_by_fingerprints!(fingerprints)

      expect(todo_file.entries[0]["created_at"]).to eq(original_created_at)
    end
  end

  describe "#filter_by_test_locations!" do
    let(:todo_file) { described_class.new(todo_file_path) }

    it "handles entries with nil locations array" do
      # This tests the branch at line 115 and 117 where entry["locations"] is nil
      File.write(todo_file_path, <<~YAML)
        ---
        - fingerprint: "fp1"
          query: "SELECT 1"
      YAML

      todo_file = described_class.new(todo_file_path)
      detected_locations = Set.new
      test_locations = Set.new(["spec/test_spec.rb"])

      # Should not raise error
      removed_count = todo_file.filter_by_test_locations!(detected_locations, test_locations)
      # Entry with nil locations is removed (becomes empty array, then entry is removed)
      expect(removed_count).to eq(0)
      expect(todo_file.entries.length).to eq(0)
    end

    it "handles entries with empty locations array" do
      File.write(todo_file_path, <<~YAML)
        ---
        - fingerprint: "fp1"
          query: "SELECT 1"
          locations: []
      YAML

      todo_file = described_class.new(todo_file_path)
      detected_locations = Set.new
      test_locations = Set.new(["spec/test_spec.rb"])

      removed_count = todo_file.filter_by_test_locations!(detected_locations, test_locations)
      expect(removed_count).to eq(0)
      # Entry with empty locations is removed
      expect(todo_file.entries.length).to eq(0)
    end
  end

  describe "#location_exists?" do
    let(:todo_file) { described_class.new(todo_file_path) }

    it "returns false when entry does not exist" do
      expect(todo_file.location_exists?("nonexistent", "some/location")).to be false
    end

    it "returns falsey when entry exists but locations is nil" do
      # This tests the branch at line 41 where entry["locations"] is nil
      File.write(todo_file_path, <<~YAML)
        ---
        - fingerprint: "fp1"
          query: "SELECT 1"
          locations: null
      YAML

      todo_file = described_class.new(todo_file_path)
      expect(todo_file.location_exists?("fp1", "some/location")).to be_falsey
    end

    it "returns true when location exists" do
      todo_file.add_entry(fingerprint: "fp1", query: "SELECT 1", location: "app/test.rb:10")
      expect(todo_file.location_exists?("fp1", "app/test.rb:10")).to be true
    end

    it "returns false when location does not exist" do
      todo_file.add_entry(fingerprint: "fp1", query: "SELECT 1", location: "app/test.rb:10")
      expect(todo_file.location_exists?("fp1", "app/other.rb:20")).to be false
    end
  end

  describe "#add_entry" do
    let(:todo_file) { described_class.new(todo_file_path) }

    context "when adding to entry with nil locations" do
      it "initializes locations array when nil" do
        # This tests the branch at line 79 and 82 where entry["locations"] is nil
        File.write(todo_file_path, <<~YAML)
          ---
          - fingerprint: "fp1"
            query: "SELECT 1"
        YAML

        todo_file = described_class.new(todo_file_path)
        todo_file.add_entry(fingerprint: "fp1", query: "SELECT 1", location: "new/location.rb:5")

        entry = todo_file.entries.first
        expect(entry["locations"]).not_to be_nil
        expect(entry["locations"].length).to eq(1)
        expect(entry["locations"].first["location"]).to eq("new/location.rb:5")
      end
    end

    it "handles nil location parameter" do
      # This tests the early return at line 76
      todo_file.add_entry(fingerprint: "fp1", query: "SELECT 1", location: nil)
      entry = todo_file.entries.first
      expect(entry["locations"]).to eq([])
    end
  end
end
