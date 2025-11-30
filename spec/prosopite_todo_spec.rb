# frozen_string_literal: true

require "tempfile"
require "fileutils"

RSpec.describe ProsopiteTodo do
  it "has a version number" do
    expect(ProsopiteTodo::VERSION).not_to be_nil
  end

  describe ".todo_file_path" do
    it "returns default path" do
      expect(ProsopiteTodo.todo_file_path).to eq(ProsopiteTodo::TodoFile.default_path)
    end

    it "can be configured" do
      original = ProsopiteTodo.todo_file_path
      ProsopiteTodo.todo_file_path = "/custom/path.yaml"
      expect(ProsopiteTodo.todo_file_path).to eq("/custom/path.yaml")
      ProsopiteTodo.todo_file_path = nil
    end
  end

  describe ".pending_notifications" do
    after do
      ProsopiteTodo.clear_pending_notifications
    end

    it "returns empty hash by default" do
      expect(ProsopiteTodo.pending_notifications).to eq({})
    end

    it "can add pending notifications" do
      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM users",
        locations: [["app/models/user.rb:10"]]
      )
      expect(ProsopiteTodo.pending_notifications).to have_key("SELECT * FROM users")
    end

    it "merges locations for same query" do
      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM users",
        locations: [["app/models/user.rb:10"]]
      )
      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM users",
        locations: [["app/controllers/users_controller.rb:20"]]
      )
      expect(ProsopiteTodo.pending_notifications["SELECT * FROM users"].length).to eq(2)
    end

    it "handles single location (not wrapped in array)" do
      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM users",
        locations: ["app/models/user.rb:10"]
      )
      expect(ProsopiteTodo.pending_notifications["SELECT * FROM users"]).to include("app/models/user.rb:10")
    end
  end

  describe ".clear_pending_notifications" do
    it "clears all pending notifications" do
      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM users",
        locations: [["app/models/user.rb:10"]]
      )
      ProsopiteTodo.clear_pending_notifications
      expect(ProsopiteTodo.pending_notifications).to eq({})
    end
  end

  describe ".update_todo!" do
    let(:temp_dir) { Dir.mktmpdir }
    let(:todo_path) { File.join(temp_dir, ".prosopite_todo.yaml") }

    before do
      ProsopiteTodo.todo_file_path = todo_path
    end

    after do
      ProsopiteTodo.clear_pending_notifications
      ProsopiteTodo.todo_file_path = nil
      FileUtils.rm_rf(temp_dir)
    end

    it "creates TODO file with pending notifications" do
      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM users WHERE id = ?",
        locations: [["app/models/user.rb:10", "app/controllers/users_controller.rb:5"]]
      )

      expect { ProsopiteTodo.update_todo! }.to output(/Added 1 new N\+1 entries/).to_stderr

      todo_file = ProsopiteTodo::TodoFile.new(todo_path)
      expect(todo_file.entries.length).to eq(1)
      expect(todo_file.entries.first["query"]).to eq("SELECT * FROM users WHERE id = ?")
    end

    it "adds new entries without removing existing ones" do
      # Create initial entry
      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM users WHERE id = ?",
        locations: [["app/models/user.rb:10"]]
      )
      ProsopiteTodo.update_todo!
      # Note: pending notifications are automatically cleared after save

      # Add another entry
      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM posts WHERE user_id = ?",
        locations: [["app/models/post.rb:20"]]
      )
      ProsopiteTodo.update_todo!

      todo_file = ProsopiteTodo::TodoFile.new(todo_path)
      expect(todo_file.entries.length).to eq(2)
    end

    it "returns the number of new entries added" do
      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM users WHERE id = ?",
        locations: [["app/models/user.rb:10"]]
      )

      expect(ProsopiteTodo.update_todo!).to eq(1)
    end

    it "does not add duplicate entries" do
      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM users WHERE id = ?",
        locations: [["app/models/user.rb:10"]]
      )
      ProsopiteTodo.update_todo!

      # Add same notification again
      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM users WHERE id = ?",
        locations: [["app/models/user.rb:10"]]
      )
      new_count = ProsopiteTodo.update_todo!

      expect(new_count).to eq(0)
      todo_file = ProsopiteTodo::TodoFile.new(todo_path)
      expect(todo_file.entries.length).to eq(1)
    end

    it "returns 0 when no pending notifications" do
      expect(ProsopiteTodo.update_todo!).to eq(0)
    end

    it "does not output message when no new entries" do
      expect { ProsopiteTodo.update_todo! }.not_to output.to_stderr
    end

    it "handles multiple locations for same query" do
      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM users",
        locations: [
          ["app/models/user.rb:10"],
          ["app/controllers/users_controller.rb:20"]
        ]
      )

      expect(ProsopiteTodo.update_todo!).to eq(2)

      todo_file = ProsopiteTodo::TodoFile.new(todo_path)
      expect(todo_file.entries.length).to eq(2)
    end

    it "handles call stack locations" do
      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM users",
        locations: [["app/models/user.rb:10", "app/controllers/users_controller.rb:5"]]
      )

      ProsopiteTodo.update_todo!

      todo_file = ProsopiteTodo::TodoFile.new(todo_path)
      entry = todo_file.entries.first
      expect(entry["location"]).to include("->")
    end

    it "clears pending notifications after successful save" do
      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM users",
        locations: [["app/models/user.rb:10"]]
      )

      expect(ProsopiteTodo.pending_notifications).not_to be_empty
      ProsopiteTodo.update_todo!
      expect(ProsopiteTodo.pending_notifications).to be_empty
    end

    it "raises ProsopiteTodo::Error when file write fails" do
      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM users",
        locations: [["app/models/user.rb:10"]]
      )

      # Make directory read-only to simulate write failure
      FileUtils.chmod(0o444, temp_dir)

      expect { ProsopiteTodo.update_todo! }.to raise_error(ProsopiteTodo::Error, /Failed to update TODO file/)

      # Restore permissions for cleanup
      FileUtils.chmod(0o755, temp_dir)
    end

    it "preserves pending notifications when save fails" do
      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM users",
        locations: [["app/models/user.rb:10"]]
      )

      # Make directory read-only to simulate write failure
      FileUtils.chmod(0o444, temp_dir)

      begin
        ProsopiteTodo.update_todo!
      rescue ProsopiteTodo::Error
        # expected
      end

      # Pending notifications should still be there
      expect(ProsopiteTodo.pending_notifications).not_to be_empty

      # Restore permissions for cleanup
      FileUtils.chmod(0o755, temp_dir)
    end
  end
end
