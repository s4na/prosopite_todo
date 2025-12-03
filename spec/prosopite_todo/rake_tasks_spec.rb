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
    let(:test_location) { "spec/models/user_spec.rb" }

    it "removes old entries and adds new ones by default (clean: true)" do
      # Create existing entry with test_location
      todo_file = ProsopiteTodo::TodoFile.new(todo_file_path)
      todo_file.add_entry(
        fingerprint: "existing123",
        query: "SELECT * FROM posts",
        location: "app/models/post.rb:5",
        test_location: test_location
      )
      todo_file.save

      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM users",
        locations: [["app/models/user.rb:10"]],
        test_location: test_location
      )

      described_class.update(output: output)

      expect(output.string).to include("Updated")
      expect(output.string).to include("removed 1")
      reloaded = ProsopiteTodo::TodoFile.new(todo_file_path)
      expect(reloaded.entries.length).to eq(1)
      expect(reloaded.entries.first["query"]).to eq("SELECT * FROM users")
    end

    it "keeps existing entries when clean: false" do
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
        locations: [["app/models/user.rb:10"]],
        test_location: test_location
      )

      described_class.update(output: output, clean: false)

      expect(output.string).to include("Updated")
      reloaded = ProsopiteTodo::TodoFile.new(todo_file_path)
      expect(reloaded.entries.length).to eq(2)
    end

    it "does not duplicate existing entries" do
      todo_file = ProsopiteTodo::TodoFile.new(todo_file_path)
      fp = ProsopiteTodo::Scanner.fingerprint(query: "SELECT * FROM users", location: ["app/models/user.rb:10"], test_location: test_location)
      todo_file.add_entry(
        fingerprint: fp,
        query: "SELECT * FROM users",
        location: "app/models/user.rb:10",
        test_location: test_location
      )
      todo_file.save

      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM users",
        locations: [["app/models/user.rb:10"]],
        test_location: test_location
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
        # Create initial entry with test_location
        todo_file = ProsopiteTodo::TodoFile.new(todo_file_path)
        fp = ProsopiteTodo::Scanner.fingerprint(query: "SELECT * FROM users", location: ["app/models/user.rb:10"], test_location: test_location)
        todo_file.add_entry(
          fingerprint: fp,
          query: "SELECT * FROM users",
          location: "app/models/user.rb:10",
          test_location: test_location
        )
        todo_file.save

        # Add different notification (simulating N+1 was fixed, new one detected)
        ProsopiteTodo.add_pending_notification(
          query: "SELECT * FROM posts",
          locations: [["app/models/post.rb:20"]],
          test_location: test_location
        )

        described_class.update(output: output, clean: true)

        expect(output.string).to include("removed 1")
        expect(output.string).to include("added 1")
        reloaded = ProsopiteTodo::TodoFile.new(todo_file_path)
        expect(reloaded.entries.length).to eq(1)
        expect(reloaded.entries.first["query"]).to eq("SELECT * FROM posts")
      end

      it "keeps entries when clean: false" do
        # Create initial entry
        todo_file = ProsopiteTodo::TodoFile.new(todo_file_path)
        fp = ProsopiteTodo::Scanner.fingerprint(query: "SELECT * FROM users", location: ["app/models/user.rb:10"], test_location: test_location)
        todo_file.add_entry(
          fingerprint: fp,
          query: "SELECT * FROM users",
          location: "app/models/user.rb:10",
          test_location: test_location
        )
        todo_file.save

        # Add different notification
        ProsopiteTodo.add_pending_notification(
          query: "SELECT * FROM posts",
          locations: [["app/models/post.rb:20"]],
          test_location: test_location
        )

        described_class.update(output: output, clean: false)

        reloaded = ProsopiteTodo::TodoFile.new(todo_file_path)
        expect(reloaded.entries.length).to eq(2)
      end

      it "preserves entries from tests that were not run" do
        # Create entries from different test files
        todo_file = ProsopiteTodo::TodoFile.new(todo_file_path)
        fp1 = ProsopiteTodo::Scanner.fingerprint(query: "SELECT * FROM users", location: ["app/models/user.rb:10"], test_location: "spec/models/user_spec.rb")
        fp2 = ProsopiteTodo::Scanner.fingerprint(query: "SELECT * FROM posts", location: ["app/models/post.rb:10"], test_location: "spec/models/post_spec.rb")
        todo_file.add_entry(
          fingerprint: fp1,
          query: "SELECT * FROM users",
          location: "app/models/user.rb:10",
          test_location: "spec/models/user_spec.rb"
        )
        todo_file.add_entry(
          fingerprint: fp2,
          query: "SELECT * FROM posts",
          location: "app/models/post.rb:10",
          test_location: "spec/models/post_spec.rb"
        )
        todo_file.save

        # Run only user_spec.rb tests (no N+1 detected = fixed)
        # post_spec.rb is NOT run, so its entries should be preserved
        ProsopiteTodo.add_pending_notification(
          query: "SELECT * FROM comments",
          locations: [["app/models/comment.rb:10"]],
          test_location: "spec/models/user_spec.rb"
        )

        described_class.update(output: output, clean: true)

        reloaded = ProsopiteTodo::TodoFile.new(todo_file_path)
        # user_spec.rb entry removed (not detected), post_spec.rb entry preserved, comment entry added
        expect(reloaded.entries.length).to eq(2)
        expect(reloaded.entries.map { |e| e["test_location"] }).to contain_exactly("spec/models/post_spec.rb", "spec/models/user_spec.rb")
      end
    end

    describe ".clean_enabled?" do
      after do
        ENV.delete("PROSOPITE_TODO_CLEAN")
      end

      it "returns true when PROSOPITE_TODO_CLEAN is not set (default)" do
        ENV.delete("PROSOPITE_TODO_CLEAN")
        expect(described_class.clean_enabled?).to be true
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

      it "returns false when PROSOPITE_TODO_CLEAN is 'false'" do
        ENV["PROSOPITE_TODO_CLEAN"] = "false"
        expect(described_class.clean_enabled?).to be false
      end

      it "returns false when PROSOPITE_TODO_CLEAN is 'no'" do
        ENV["PROSOPITE_TODO_CLEAN"] = "no"
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
    let(:test_location) { "spec/models/user_spec.rb" }

    it "removes entries not in pending notifications" do
      todo_file = ProsopiteTodo::TodoFile.new(todo_file_path)

      # Entry that should be kept (matches pending)
      keep_fp = ProsopiteTodo::Scanner.fingerprint(query: "SELECT * FROM users", location: ["app/models/user.rb:10"], test_location: test_location)
      todo_file.add_entry(
        fingerprint: keep_fp,
        query: "SELECT * FROM users",
        location: "app/models/user.rb:10",
        test_location: test_location
      )

      # Entry that should be removed (no matching pending, same test_location)
      todo_file.add_entry(
        fingerprint: "remove123",
        query: "SELECT * FROM old_table",
        location: "app/models/old.rb:5",
        test_location: test_location
      )
      todo_file.save

      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM users",
        locations: [["app/models/user.rb:10"]],
        test_location: test_location
      )

      described_class.clean(output: output)

      expect(output.string).to include("Cleaned")
      reloaded = ProsopiteTodo::TodoFile.new(todo_file_path)
      expect(reloaded.entries.length).to eq(1)
      expect(reloaded.entries[0]["query"]).to eq("SELECT * FROM users")
    end

    it "removes entries for tests that were run but detected nothing" do
      todo_file = ProsopiteTodo::TodoFile.new(todo_file_path)
      todo_file.add_entry(
        fingerprint: "remove123",
        query: "SELECT * FROM old_table",
        location: "app/models/old.rb:5",
        test_location: test_location
      )
      todo_file.save

      # Add a notification from the same test (triggering that test location was run)
      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM users",
        locations: [["app/models/user.rb:10"]],
        test_location: test_location
      )

      described_class.clean(output: output)

      expect(output.string).to include("removed 1 entries")
      reloaded = ProsopiteTodo::TodoFile.new(todo_file_path)
      # The old entry is removed, but the new one is NOT added by clean (clean only removes)
      # Wait, clean also calls record_notifications... let me check the code again
      # Actually clean just filters, doesn't add. So the entry count should be 0
      expect(reloaded.entries.length).to eq(0)
    end

    it "preserves entries without test_location (legacy entries)" do
      todo_file = ProsopiteTodo::TodoFile.new(todo_file_path)
      todo_file.add_entry(
        fingerprint: "legacy123",
        query: "SELECT * FROM legacy",
        location: "app/models/legacy.rb:5"
        # No test_location
      )
      todo_file.save

      # Run some tests
      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM users",
        locations: [["app/models/user.rb:10"]],
        test_location: test_location
      )

      described_class.clean(output: output)

      reloaded = ProsopiteTodo::TodoFile.new(todo_file_path)
      # Legacy entry should be preserved
      expect(reloaded.entries.length).to eq(1)
      expect(reloaded.entries[0]["query"]).to eq("SELECT * FROM legacy")
    end

    it "handles multiple matching notifications" do
      todo_file = ProsopiteTodo::TodoFile.new(todo_file_path)

      fp1 = ProsopiteTodo::Scanner.fingerprint(query: "SELECT * FROM users", location: ["file1.rb:1"], test_location: test_location)
      fp2 = ProsopiteTodo::Scanner.fingerprint(query: "SELECT * FROM users", location: ["file2.rb:2"], test_location: test_location)

      todo_file.add_entry(fingerprint: fp1, query: "SELECT * FROM users", location: "file1.rb:1", test_location: test_location)
      todo_file.add_entry(fingerprint: fp2, query: "SELECT * FROM users", location: "file2.rb:2", test_location: test_location)
      todo_file.add_entry(fingerprint: "old123", query: "SELECT * FROM old", location: "old.rb:1", test_location: test_location)
      todo_file.save

      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM users",
        locations: [["file1.rb:1"], ["file2.rb:2"]],
        test_location: test_location
      )

      described_class.clean(output: output)

      reloaded = ProsopiteTodo::TodoFile.new(todo_file_path)
      expect(reloaded.entries.length).to eq(2)
    end
  end
end
