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

    it "can be directly set via pending_notifications=" do
      ProsopiteTodo.pending_notifications = { "SELECT * FROM posts" => [["app/models/post.rb:5"]] }
      expect(ProsopiteTodo.pending_notifications).to have_key("SELECT * FROM posts")
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

      result = ProsopiteTodo.update_todo!
      expect(result[:added]).to eq(1)
      expect(result[:removed]).to eq(0)
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
      result = ProsopiteTodo.update_todo!

      expect(result[:added]).to eq(0)
      todo_file = ProsopiteTodo::TodoFile.new(todo_path)
      expect(todo_file.entries.length).to eq(1)
    end

    it "returns zero counts when no pending notifications" do
      result = ProsopiteTodo.update_todo!
      expect(result[:added]).to eq(0)
      expect(result[:removed]).to eq(0)
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

      result = ProsopiteTodo.update_todo!
      expect(result[:added]).to eq(2)

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

    context "with clean: true option" do
      before do
        # Use identity filter to prevent backtrace_cleaner from affecting fingerprints
        ProsopiteTodo.reset_configuration!
        ProsopiteTodo.configure do |c|
          c.location_filter = ->(frames) { frames }
        end
      end

      it "removes entries no longer detected" do
        # Create initial entry
        ProsopiteTodo.add_pending_notification(
          query: "SELECT * FROM users",
          locations: [["app/models/user.rb:10"]]
        )
        ProsopiteTodo.update_todo!

        # Second update with different notification (simulating N+1 was fixed)
        ProsopiteTodo.add_pending_notification(
          query: "SELECT * FROM posts",
          locations: [["app/models/post.rb:20"]]
        )
        result = ProsopiteTodo.update_todo!(clean: true)

        expect(result[:added]).to eq(1)
        expect(result[:removed]).to eq(1)

        todo_file = ProsopiteTodo::TodoFile.new(todo_path)
        expect(todo_file.entries.length).to eq(1)
        expect(todo_file.entries.first["query"]).to eq("SELECT * FROM posts")
      end

      it "removes all entries when no pending notifications" do
        # Create initial entry
        ProsopiteTodo.add_pending_notification(
          query: "SELECT * FROM users",
          locations: [["app/models/user.rb:10"]]
        )
        ProsopiteTodo.update_todo!

        # Update with clean and no pending notifications (all N+1s fixed)
        result = ProsopiteTodo.update_todo!(clean: true)

        expect(result[:removed]).to eq(1)
        expect(result[:added]).to eq(0)

        todo_file = ProsopiteTodo::TodoFile.new(todo_path)
        expect(todo_file.entries).to be_empty
      end

      it "keeps entries that are still detected" do
        # Create initial entry
        ProsopiteTodo.add_pending_notification(
          query: "SELECT * FROM users",
          locations: [["app/models/user.rb:10"]]
        )
        ProsopiteTodo.update_todo!

        # Update with same notification (N+1 still exists)
        ProsopiteTodo.add_pending_notification(
          query: "SELECT * FROM users",
          locations: [["app/models/user.rb:10"]]
        )
        result = ProsopiteTodo.update_todo!(clean: true)

        expect(result[:removed]).to eq(0)
        expect(result[:added]).to eq(0)

        todo_file = ProsopiteTodo::TodoFile.new(todo_path)
        expect(todo_file.entries.length).to eq(1)
      end

      it "outputs message for added and removed entries" do
        # Create initial entry
        ProsopiteTodo.add_pending_notification(
          query: "SELECT * FROM users",
          locations: [["app/models/user.rb:10"]]
        )
        ProsopiteTodo.update_todo!

        # Update with different notification
        ProsopiteTodo.add_pending_notification(
          query: "SELECT * FROM posts",
          locations: [["app/models/post.rb:20"]]
        )

        expect { ProsopiteTodo.update_todo!(clean: true) }
          .to output(/Added 1 new.*Removed 1 resolved/).to_stderr
      end
    end
  end

  describe "thread safety" do
    after do
      ProsopiteTodo.clear_pending_notifications
    end

    it "returns defensive copy that cannot mutate internal state" do
      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM users",
        locations: [["app/models/user.rb:10"]]
      )

      # Get notifications
      notifications = ProsopiteTodo.pending_notifications

      # Try to mutate the returned hash
      notifications["malicious"] = ["hacked"]

      # Internal state should be unchanged
      expect(ProsopiteTodo.pending_notifications).not_to have_key("malicious")
    end

    it "protects against mutation of location arrays" do
      ProsopiteTodo.add_pending_notification(
        query: "SELECT * FROM users",
        locations: [["app/models/user.rb:10"]]
      )

      notifications = ProsopiteTodo.pending_notifications
      notifications["SELECT * FROM users"] << "malicious_location"

      # Original should be unchanged
      expect(ProsopiteTodo.pending_notifications["SELECT * FROM users"].length).to eq(1)
    end

    it "handles concurrent add_pending_notification calls without data loss" do
      thread_count = 10
      iterations_per_thread = 100
      threads = []

      thread_count.times do |t|
        threads << Thread.new do
          iterations_per_thread.times do |i|
            ProsopiteTodo.add_pending_notification(
              query: "SELECT * FROM table_#{t}",
              locations: [["file_#{t}.rb:#{i}"]]
            )
          end
        end
      end

      threads.each(&:join)

      # Each thread added 100 locations to its own query
      notifications = ProsopiteTodo.pending_notifications
      expect(notifications.keys.length).to eq(thread_count)

      notifications.each do |_query, locations|
        expect(locations.length).to eq(iterations_per_thread)
      end
    end

    it "handles concurrent reads and writes without errors" do
      errors = []
      threads = []

      # Writer threads
      5.times do |t|
        threads << Thread.new do
          50.times do |i|
            ProsopiteTodo.add_pending_notification(
              query: "SELECT * FROM users_#{t}",
              locations: [["app/models/user.rb:#{i}"]]
            )
          end
        rescue StandardError => e
          errors << e
        end
      end

      # Reader threads
      5.times do
        threads << Thread.new do
          50.times do
            ProsopiteTodo.pending_notifications
          end
        rescue StandardError => e
          errors << e
        end
      end

      # Clear threads
      2.times do
        threads << Thread.new do
          10.times do
            sleep(0.001)
            ProsopiteTodo.clear_pending_notifications
          end
        rescue StandardError => e
          errors << e
        end
      end

      threads.each(&:join)

      expect(errors).to be_empty
    end
  end
end
