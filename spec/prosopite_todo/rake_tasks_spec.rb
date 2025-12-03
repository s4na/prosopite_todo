# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"

# Load the task helpers module for testing
require_relative "../../lib/prosopite_todo/task_helpers"

RSpec.describe ProsopiteTodo::TaskHelpers do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:todo_file_path) { File.join(tmp_dir, ".prosopite_todo.yaml") }
  let(:output) { StringIO.new }

  before do
    ProsopiteTodo.todo_file_path = todo_file_path
    ProsopiteTodo.clear_pending_notifications
    # Reset configuration to avoid Rails.backtrace_cleaner affecting fingerprints
    ProsopiteTodo.reset_configuration!
    # Use identity filter to prevent backtrace_cleaner from filtering test locations
    ProsopiteTodo.configure do |c|
      c.location_filter = ->(frames) { frames }
    end
  end

  after do
    FileUtils.rm_rf(tmp_dir)
    ProsopiteTodo.todo_file_path = nil
    ProsopiteTodo.clear_pending_notifications
  end

  describe ".generate" do
    it "creates a new todo file with pending notifications" do
      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM users",
        locations: [["app/models/user.rb:10"]]
      )

      described_class.generate(output: output)

      expect(output.string).to include("Generated")
      todo_file = ProsopiteTodo::TodoFile.new(todo_file_path)
      expect(todo_file.entries.length).to eq(1)
    end

    it "clears existing entries before generating" do
      File.write(todo_file_path, <<~YAML)
        ---
        - fingerprint: "old123"
          query: "SELECT * FROM old_table"
      YAML

      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM users",
        locations: [["app/models/user.rb:10"]]
      )

      described_class.generate(output: output)

      todo_file = ProsopiteTodo::TodoFile.new(todo_file_path)
      expect(todo_file.entries.length).to eq(1)
      expect(todo_file.entries[0]["query"]).to eq("SELECT * FROM users")
    end

    it "creates empty file when no pending notifications" do
      described_class.generate(output: output)

      expect(output.string).to include("Generated")
      expect(output.string).to include("0 entries")
      todo_file = ProsopiteTodo::TodoFile.new(todo_file_path)
      expect(todo_file.entries.length).to eq(0)
    end
  end

  describe ".update" do
    it "adds new notifications while keeping existing ones" do
      # Create existing entry
      todo_file = ProsopiteTodo::TodoFile.new(todo_file_path)
      todo_file.add_entry(
        fingerprint: "existing123",
        query: "SELECT * FROM posts",
        location: "app/models/post.rb:5"
      )
      todo_file.save

      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM users",
        locations: [["app/models/user.rb:10"]]
      )

      described_class.update(output: output)

      expect(output.string).to include("Updated")
      reloaded = ProsopiteTodo::TodoFile.new(todo_file_path)
      expect(reloaded.entries.length).to eq(2)
    end

    it "does not duplicate existing entries" do
      todo_file = ProsopiteTodo::TodoFile.new(todo_file_path)
      fp = ProsopiteTodo::Scanner.fingerprint(query: "SELECT * FROM users", location: ["app/models/user.rb:10"])
      todo_file.add_entry(
        fingerprint: fp,
        query: "SELECT * FROM users",
        location: "app/models/user.rb:10"
      )
      todo_file.save

      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM users",
        locations: [["app/models/user.rb:10"]]
      )

      described_class.update(output: output)

      reloaded = ProsopiteTodo::TodoFile.new(todo_file_path)
      expect(reloaded.entries.length).to eq(1)
    end

    it "creates file when no existing file and no pending notifications" do
      described_class.update(output: output)

      expect(output.string).to include("Updated")
      expect(output.string).to include("0 total entries")
    end

    context "with clean option" do
      it "removes entries no longer detected when clean: true" do
        # Create initial entry
        todo_file = ProsopiteTodo::TodoFile.new(todo_file_path)
        fp = ProsopiteTodo::Scanner.fingerprint(query: "SELECT * FROM users", location: ["app/models/user.rb:10"])
        todo_file.add_entry(
          fingerprint: fp,
          query: "SELECT * FROM users",
          location: "app/models/user.rb:10"
        )
        todo_file.save

        # Add different notification (simulating N+1 was fixed, new one detected)
        ProsopiteTodo.add_pending_notification(
          query: "SELECT * FROM posts",
          locations: [["app/models/post.rb:20"]]
        )

        described_class.update(output: output, clean: true)

        expect(output.string).to include("removed 1")
        expect(output.string).to include("added 1")
        reloaded = ProsopiteTodo::TodoFile.new(todo_file_path)
        expect(reloaded.entries.length).to eq(1)
        expect(reloaded.entries.first["query"]).to eq("SELECT * FROM posts")
      end

      it "keeps entries when clean: false (default without env var)" do
        # Create initial entry
        todo_file = ProsopiteTodo::TodoFile.new(todo_file_path)
        fp = ProsopiteTodo::Scanner.fingerprint(query: "SELECT * FROM users", location: ["app/models/user.rb:10"])
        todo_file.add_entry(
          fingerprint: fp,
          query: "SELECT * FROM users",
          location: "app/models/user.rb:10"
        )
        todo_file.save

        # Add different notification
        ProsopiteTodo.add_pending_notification(
          query: "SELECT * FROM posts",
          locations: [["app/models/post.rb:20"]]
        )

        described_class.update(output: output, clean: false)

        reloaded = ProsopiteTodo::TodoFile.new(todo_file_path)
        expect(reloaded.entries.length).to eq(2)
      end
    end

    describe ".clean_enabled?" do
      after do
        ENV.delete("PROSOPITE_TODO_CLEAN")
      end

      it "returns false when PROSOPITE_TODO_CLEAN is not set" do
        ENV.delete("PROSOPITE_TODO_CLEAN")
        expect(described_class.clean_enabled?).to be false
      end

      it "returns true when PROSOPITE_TODO_CLEAN is '1'" do
        ENV["PROSOPITE_TODO_CLEAN"] = "1"
        expect(described_class.clean_enabled?).to be true
      end

      it "returns true when PROSOPITE_TODO_CLEAN is 'true'" do
        ENV["PROSOPITE_TODO_CLEAN"] = "true"
        expect(described_class.clean_enabled?).to be true
      end

      it "returns true when PROSOPITE_TODO_CLEAN is 'yes'" do
        ENV["PROSOPITE_TODO_CLEAN"] = "yes"
        expect(described_class.clean_enabled?).to be true
      end

      it "returns false when PROSOPITE_TODO_CLEAN is '0'" do
        ENV["PROSOPITE_TODO_CLEAN"] = "0"
        expect(described_class.clean_enabled?).to be false
      end
    end
  end

  describe ".list" do
    it "displays all todo entries with location and fingerprint" do
      todo_file = ProsopiteTodo::TodoFile.new(todo_file_path)
      todo_file.add_entry(
        fingerprint: "abc123",
        query: "SELECT * FROM users",
        location: "app/models/user.rb:10"
      )
      todo_file.save

      described_class.list(output: output)

      expect(output.string).to include("SELECT * FROM users")
      expect(output.string).to include("Location: app/models/user.rb:10")
      expect(output.string).to include("Fingerprint: abc123")
      expect(output.string).to include("Entries in")
    end

    it "displays numbered entries" do
      todo_file = ProsopiteTodo::TodoFile.new(todo_file_path)
      todo_file.add_entry(fingerprint: "abc123", query: "SELECT 1", location: "file1.rb:1")
      todo_file.add_entry(fingerprint: "def456", query: "SELECT 2", location: "file2.rb:2")
      todo_file.save

      described_class.list(output: output)

      expect(output.string).to include("1. SELECT 1")
      expect(output.string).to include("2. SELECT 2")
    end

    it "shows message when no entries exist" do
      described_class.list(output: output)

      expect(output.string).to include("No entries")
    end
  end

  describe ".clean" do
    it "removes entries not in pending notifications" do
      todo_file = ProsopiteTodo::TodoFile.new(todo_file_path)

      # Entry that should be kept (matches pending)
      keep_fp = ProsopiteTodo::Scanner.fingerprint(query: "SELECT * FROM users", location: ["app/models/user.rb:10"])
      todo_file.add_entry(
        fingerprint: keep_fp,
        query: "SELECT * FROM users",
        location: "app/models/user.rb:10"
      )

      # Entry that should be removed (no matching pending)
      todo_file.add_entry(
        fingerprint: "remove123",
        query: "SELECT * FROM old_table",
        location: "app/models/old.rb:5"
      )
      todo_file.save

      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM users",
        locations: [["app/models/user.rb:10"]]
      )

      described_class.clean(output: output)

      expect(output.string).to include("Cleaned")
      reloaded = ProsopiteTodo::TodoFile.new(todo_file_path)
      expect(reloaded.entries.length).to eq(1)
      expect(reloaded.entries[0]["query"]).to eq("SELECT * FROM users")
    end

    it "removes all entries when no pending notifications" do
      todo_file = ProsopiteTodo::TodoFile.new(todo_file_path)
      todo_file.add_entry(
        fingerprint: "remove123",
        query: "SELECT * FROM old_table",
        location: "app/models/old.rb:5"
      )
      todo_file.save

      described_class.clean(output: output)

      expect(output.string).to include("removed 1 entries")
      expect(output.string).to include("0 remaining")
      reloaded = ProsopiteTodo::TodoFile.new(todo_file_path)
      expect(reloaded.entries.length).to eq(0)
    end

    it "handles multiple matching notifications" do
      todo_file = ProsopiteTodo::TodoFile.new(todo_file_path)

      fp1 = ProsopiteTodo::Scanner.fingerprint(query: "SELECT * FROM users", location: ["file1.rb:1"])
      fp2 = ProsopiteTodo::Scanner.fingerprint(query: "SELECT * FROM users", location: ["file2.rb:2"])

      todo_file.add_entry(fingerprint: fp1, query: "SELECT * FROM users", location: "file1.rb:1")
      todo_file.add_entry(fingerprint: fp2, query: "SELECT * FROM users", location: "file2.rb:2")
      todo_file.add_entry(fingerprint: "old123", query: "SELECT * FROM old", location: "old.rb:1")
      todo_file.save

      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM users",
        locations: [["file1.rb:1"], ["file2.rb:2"]]
      )

      described_class.clean(output: output)

      reloaded = ProsopiteTodo::TodoFile.new(todo_file_path)
      expect(reloaded.entries.length).to eq(2)
    end
  end
end
