# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"

RSpec.describe ProsopiteTodo::Scanner do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:todo_file_path) { File.join(tmp_dir, ".prosopite_todo.yaml") }

  after do
    FileUtils.rm_rf(tmp_dir)
    ProsopiteTodo.reset_configuration!
  end

  describe ".normalize_query" do
    it "replaces numeric IDs with ?" do
      query = "SELECT * FROM items WHERE items.parent_id = 10465"
      expect(described_class.normalize_query(query)).to eq("SELECT * FROM items WHERE items.parent_id = ?")
    end

    it "replaces multiple numeric values" do
      query = "SELECT * FROM users WHERE id IN (1, 2, 3)"
      expect(described_class.normalize_query(query)).to eq("SELECT * FROM users WHERE id IN (?, ?, ?)")
    end

    it "replaces float values" do
      query = "SELECT * FROM products WHERE price > 99.99"
      expect(described_class.normalize_query(query)).to eq("SELECT * FROM products WHERE price > ?")
    end

    it "handles LIMIT and OFFSET" do
      query = "SELECT * FROM users LIMIT 10 OFFSET 20"
      expect(described_class.normalize_query(query)).to eq("SELECT * FROM users LIMIT ? OFFSET ?")
    end

    it "returns original query for nil" do
      expect(described_class.normalize_query(nil)).to be_nil
    end

    it "returns original query for empty string" do
      expect(described_class.normalize_query("")).to eq("")
    end

    it "preserves table and column names with numeric suffixes" do
      query = "SELECT user_id, name FROM users123"
      # Table names like "users123" are preserved because \b doesn't match
      # at the boundary between letter and digit
      expect(described_class.normalize_query(query)).to eq("SELECT user_id, name FROM users123")
    end

    it "replaces string literals as a whole" do
      query = "SELECT * FROM logs WHERE ip_address = '192.168.1.1'"
      expect(described_class.normalize_query(query)).to eq("SELECT * FROM logs WHERE ip_address = ?")
    end

    it "does not normalize numbers inside string literals" do
      query = "SELECT * FROM users WHERE name = 'User 123'"
      expect(described_class.normalize_query(query)).to eq("SELECT * FROM users WHERE name = ?")
    end

    it "preserves PostgreSQL-style placeholders" do
      query = "SELECT * FROM users WHERE id = $1 AND status = $2"
      expect(described_class.normalize_query(query)).to eq("SELECT * FROM users WHERE id = $1 AND status = $2")
    end

    it "handles mixed string literals and numeric values" do
      query = "SELECT * FROM users WHERE id = 123 AND status = 'active'"
      expect(described_class.normalize_query(query)).to eq("SELECT * FROM users WHERE id = ? AND status = ?")
    end

    it "handles multiple string literals" do
      query = "SELECT * FROM logs WHERE message = 'Error 404' AND path = '/page/123'"
      expect(described_class.normalize_query(query)).to eq("SELECT * FROM logs WHERE message = ? AND path = ?")
    end
  end

  describe ".fingerprint" do
    it "generates consistent fingerprint for same query and location" do
      fp1 = described_class.fingerprint(query: "SELECT * FROM users", location: ["app/models/user.rb:10"])
      fp2 = described_class.fingerprint(query: "SELECT * FROM users", location: ["app/models/user.rb:10"])

      expect(fp1).to eq(fp2)
    end

    it "generates same fingerprint for queries with different numeric IDs" do
      fp1 = described_class.fingerprint(query: "SELECT * FROM items WHERE parent_id = 10465", location: ["app/models/item.rb:10"])
      fp2 = described_class.fingerprint(query: "SELECT * FROM items WHERE parent_id = 10466", location: ["app/models/item.rb:10"])

      expect(fp1).to eq(fp2)
    end

    it "generates different fingerprint for different queries" do
      fp1 = described_class.fingerprint(query: "SELECT * FROM users", location: ["app/models/user.rb:10"])
      fp2 = described_class.fingerprint(query: "SELECT * FROM posts", location: ["app/models/user.rb:10"])

      expect(fp1).not_to eq(fp2)
    end

    it "generates different fingerprint for different locations" do
      fp1 = described_class.fingerprint(query: "SELECT * FROM users", location: ["app/models/user.rb:10"])
      fp2 = described_class.fingerprint(query: "SELECT * FROM users", location: ["app/models/user.rb:20"])

      expect(fp1).not_to eq(fp2)
    end

    it "returns 16 character hexadecimal string" do
      fp = described_class.fingerprint(query: "SELECT 1", location: ["test.rb:1"])
      expect(fp).to match(/\A[a-f0-9]{16}\z/)
    end

    context "with edge case inputs" do
      it "handles empty query string" do
        fp = described_class.fingerprint(query: "", location: ["test.rb:1"])
        expect(fp).to be_a(String)
        expect(fp.length).to eq(16)
      end

      it "handles empty location array" do
        fp = described_class.fingerprint(query: "SELECT 1", location: [])
        expect(fp).to be_a(String)
        expect(fp.length).to eq(16)
      end

      it "handles string location instead of array" do
        fp = described_class.fingerprint(query: "SELECT 1", location: "test.rb:1")
        expect(fp).to be_a(String)
        expect(fp.length).to eq(16)
      end

      it "handles nil location" do
        fp = described_class.fingerprint(query: "SELECT 1", location: nil)
        expect(fp).to be_a(String)
        expect(fp.length).to eq(16)
      end

      it "handles very long query string" do
        long_query = "SELECT " + ("col#{rand(1000)}, " * 1000) + "FROM very_long_table"
        fp = described_class.fingerprint(query: long_query, location: ["test.rb:1"])
        expect(fp).to be_a(String)
        expect(fp.length).to eq(16)
      end

      it "handles unicode characters in query" do
        fp = described_class.fingerprint(query: "SELECT * FROM users WHERE name = '日本語'", location: ["test.rb:1"])
        expect(fp).to be_a(String)
        expect(fp.length).to eq(16)
      end

      it "handles special characters in query" do
        fp = described_class.fingerprint(query: "SELECT * FROM users WHERE data = '{\"key\": \"value\"}'", location: ["test.rb:1"])
        expect(fp).to be_a(String)
        expect(fp.length).to eq(16)
      end

      it "handles newlines in query" do
        fp = described_class.fingerprint(query: "SELECT *\nFROM users\nWHERE id = 1", location: ["test.rb:1"])
        expect(fp).to be_a(String)
        expect(fp.length).to eq(16)
      end

      it "handles multiple locations (call stack)" do
        locations = [
          "app/models/user.rb:10",
          "app/controllers/users_controller.rb:20",
          "app/views/users/index.html.erb:5"
        ]
        fp = described_class.fingerprint(query: "SELECT 1", location: locations)
        expect(fp).to be_a(String)
        expect(fp.length).to eq(16)
      end

      it "generates different fingerprints for different location order" do
        # Use identity filter to bypass Rails.backtrace_cleaner
        ProsopiteTodo.configure do |c|
          c.location_filter = ->(frames) { frames }
          c.max_location_frames = nil
        end

        fp1 = described_class.fingerprint(query: "SELECT 1", location: ["a.rb:1", "b.rb:2"])
        fp2 = described_class.fingerprint(query: "SELECT 1", location: ["b.rb:2", "a.rb:1"])
        expect(fp1).not_to eq(fp2)
      end
    end
  end

  describe ".filter_notifications" do
    let(:todo_file) { ProsopiteTodo::TodoFile.new(todo_file_path) }

    context "when no todo file exists" do
      it "returns all notifications unchanged" do
        notifications = {
          "SELECT * FROM users" => [["app/models/user.rb:10"]]
        }

        result = described_class.filter_notifications(notifications, todo_file)
        expect(result).to eq(notifications)
      end
    end

    context "with empty notifications" do
      it "returns empty hash" do
        result = described_class.filter_notifications({}, todo_file)
        expect(result).to eq({})
      end
    end

    context "with empty locations array" do
      it "removes query from result" do
        notifications = {
          "SELECT * FROM users" => []
        }

        result = described_class.filter_notifications(notifications, todo_file)
        expect(result).to be_empty
      end
    end

    context "when todo file has matching fingerprint" do
      before do
        fp = described_class.fingerprint(query: "SELECT * FROM users", location: ["app/models/user.rb:10"])
        todo_file.add_entry(
          fingerprint: fp,
          query: "SELECT * FROM users",
          location: "app/models/user.rb:10"
        )
        todo_file.save
      end

      it "filters out matching notifications" do
        notifications = {
          "SELECT * FROM users" => [["app/models/user.rb:10"]]
        }

        result = described_class.filter_notifications(notifications, todo_file)
        expect(result).to be_empty
      end

      it "keeps non-matching notifications" do
        notifications = {
          "SELECT * FROM users" => [["app/models/user.rb:10"]],
          "SELECT * FROM posts" => [["app/models/post.rb:20"]]
        }

        result = described_class.filter_notifications(notifications, todo_file)
        expect(result.keys).to eq(["SELECT * FROM posts"])
      end
    end

    context "with multiple locations for same query" do
      before do
        fp = described_class.fingerprint(query: "SELECT * FROM users", location: ["app/models/user.rb:10"])
        todo_file.add_entry(
          fingerprint: fp,
          query: "SELECT * FROM users",
          location: "app/models/user.rb:10"
        )
        todo_file.save
      end

      it "only filters matching location combinations" do
        notifications = {
          "SELECT * FROM users" => [
            ["app/models/user.rb:10"],
            ["app/controllers/users_controller.rb:5"]
          ]
        }

        result = described_class.filter_notifications(notifications, todo_file)
        expect(result["SELECT * FROM users"]).to eq([["app/controllers/users_controller.rb:5"]])
      end
    end

    context "with Prosopite format notifications" do
      # Prosopite sends notifications as { [query1, query2, ...] => [frame1, frame2, ...] }
      # where the key is an array of similar queries and the value is a flat array of stack frames

      it "handles Prosopite format with array of queries as key" do
        notifications = {
          ["SELECT * FROM users WHERE id = ?", "SELECT * FROM users WHERE id = ?"] => [
            "app/models/user.rb:10",
            "app/controllers/users_controller.rb:20",
            "app/views/users/show.html.erb:5"
          ]
        }

        result = described_class.filter_notifications(notifications, todo_file)
        expect(result.keys.first).to eq(["SELECT * FROM users WHERE id = ?", "SELECT * FROM users WHERE id = ?"])
      end

      it "filters Prosopite format when fingerprint matches" do
        call_stack = [
          "app/models/user.rb:10",
          "app/controllers/users_controller.rb:20"
        ]
        fp = described_class.fingerprint(query: "SELECT * FROM users WHERE id = ?", location: call_stack)
        todo_file.add_entry(
          fingerprint: fp,
          query: "SELECT * FROM users WHERE id = ?",
          location: call_stack.join(" -> ")
        )
        todo_file.save

        notifications = {
          ["SELECT * FROM users WHERE id = ?"] => call_stack
        }

        result = described_class.filter_notifications(notifications, todo_file)
        expect(result).to be_empty
      end

      it "keeps Prosopite format when fingerprint does not match" do
        notifications = {
          ["SELECT * FROM posts WHERE id = ?"] => [
            "app/models/post.rb:15",
            "app/controllers/posts_controller.rb:25"
          ]
        }

        result = described_class.filter_notifications(notifications, todo_file)
        expect(result.keys.first).to eq(["SELECT * FROM posts WHERE id = ?"])
      end
    end
  end

  describe ".record_notifications" do
    let(:todo_file) { ProsopiteTodo::TodoFile.new(todo_file_path) }

    it "adds all notifications to todo file" do
      notifications = {
        "SELECT * FROM users" => [["app/models/user.rb:10"]],
        "SELECT * FROM posts" => [["app/models/post.rb:20"]]
      }

      described_class.record_notifications(notifications, todo_file)

      expect(todo_file.entries.length).to eq(2)
    end

    it "records with correct fingerprint" do
      notifications = {
        "SELECT * FROM users" => [["app/models/user.rb:10"]]
      }

      described_class.record_notifications(notifications, todo_file)

      expected_fp = described_class.fingerprint(query: "SELECT * FROM users", location: ["app/models/user.rb:10"])
      expect(todo_file.fingerprints).to include(expected_fp)
    end

    context "with empty notifications" do
      it "does not add any entries" do
        described_class.record_notifications({}, todo_file)
        expect(todo_file.entries).to be_empty
      end
    end

    context "with multiple locations for same query" do
      it "creates separate entries for each location" do
        notifications = {
          "SELECT * FROM users" => [
            ["app/models/user.rb:10"],
            ["app/controllers/users_controller.rb:20"]
          ]
        }

        described_class.record_notifications(notifications, todo_file)

        expect(todo_file.entries.length).to eq(2)
        locations = todo_file.entries.map { |e| e["location"] }
        expect(locations).to include("app/models/user.rb:10")
        expect(locations).to include("app/controllers/users_controller.rb:20")
      end
    end

    context "with call stack locations" do
      it "normalizes locations to joined string" do
        notifications = {
          "SELECT * FROM users" => [
            ["app/models/user.rb:10", "app/controllers/users_controller.rb:20"]
          ]
        }

        described_class.record_notifications(notifications, todo_file)

        entry = todo_file.entries.first
        expect(entry["location"]).to eq("app/models/user.rb:10 -> app/controllers/users_controller.rb:20")
      end
    end

    context "with duplicate notifications" do
      it "does not add duplicate entries" do
        notifications = {
          "SELECT * FROM users" => [["app/models/user.rb:10"]]
        }

        described_class.record_notifications(notifications, todo_file)
        described_class.record_notifications(notifications, todo_file)

        expect(todo_file.entries.length).to eq(1)
      end
    end

    context "with query normalization" do
      it "stores normalized query with ? instead of numeric IDs" do
        notifications = {
          "SELECT * FROM items WHERE parent_id = 10465" => [["app/models/item.rb:10"]]
        }

        described_class.record_notifications(notifications, todo_file)

        entry = todo_file.entries.first
        expect(entry["query"]).to eq("SELECT * FROM items WHERE parent_id = ?")
      end

      it "deduplicates queries with different numeric IDs to single entry" do
        notifications1 = {
          "SELECT * FROM items WHERE parent_id = 10465" => [["app/models/item.rb:10"]]
        }
        notifications2 = {
          "SELECT * FROM items WHERE parent_id = 10466" => [["app/models/item.rb:10"]]
        }

        described_class.record_notifications(notifications1, todo_file)
        described_class.record_notifications(notifications2, todo_file)

        expect(todo_file.entries.length).to eq(1)
        expect(todo_file.entries.first["query"]).to eq("SELECT * FROM items WHERE parent_id = ?")
      end
    end
  end

  describe ".extract_fingerprints" do
    before do
      ProsopiteTodo.configure do |c|
        c.location_filter = ->(frames) { frames }
      end
    end

    it "returns a Set of fingerprints from notifications" do
      notifications = {
        "SELECT * FROM users" => [["app/models/user.rb:10"], ["app/models/user.rb:20"]]
      }

      result = described_class.extract_fingerprints(notifications)

      expect(result).to be_a(Set)
      expect(result.length).to eq(2)
    end

    it "includes fingerprints for all locations" do
      notifications = {
        "SELECT * FROM users" => [["file1.rb:1"]],
        "SELECT * FROM posts" => [["file2.rb:2"]]
      }

      result = described_class.extract_fingerprints(notifications)

      fp1 = described_class.fingerprint(query: "SELECT * FROM users", location: ["file1.rb:1"])
      fp2 = described_class.fingerprint(query: "SELECT * FROM posts", location: ["file2.rb:2"])

      expect(result).to include(fp1)
      expect(result).to include(fp2)
    end

    it "returns empty Set for empty notifications" do
      result = described_class.extract_fingerprints({})

      expect(result).to be_a(Set)
      expect(result).to be_empty
    end
  end

  describe "location filtering" do
    let(:todo_file) { ProsopiteTodo::TodoFile.new(todo_file_path) }

    # Use app-relative paths to simulate Rails.backtrace_cleaner output
    let(:app_stack) do
      [
        "app/models/user.rb:42:in `some_method'",
        "app/controllers/users_controller.rb:15:in `show'",
        "app/views/users/show.html.erb:3:in `_app_views_users_show_html_erb'",
        "app/helpers/users_helper.rb:10:in `format_name'",
        "app/services/user_service.rb:25:in `process'",
        "app/jobs/user_job.rb:5:in `perform'",
        "app/mailers/user_mailer.rb:8:in `welcome'"
      ]
    end

    before do
      # Use identity filter to bypass Rails.backtrace_cleaner for consistent testing
      ProsopiteTodo.configure do |c|
        c.location_filter = ->(frames) { frames }
      end
    end

    context "with max_location_frames configuration" do
      it "limits the number of frames to configured value" do
        ProsopiteTodo.configure do |c|
          c.location_filter = ->(frames) { frames }
          c.max_location_frames = 3
        end

        notifications = { "SELECT * FROM users" => [app_stack] }
        described_class.record_notifications(notifications, todo_file)

        entry = todo_file.entries.first
        frames = entry["location"].split(" -> ")
        expect(frames.length).to eq(3)
      end

      it "includes all frames when set to nil" do
        ProsopiteTodo.configure do |c|
          c.location_filter = ->(frames) { frames }
          c.max_location_frames = nil
        end

        notifications = { "SELECT * FROM users" => [app_stack] }
        described_class.record_notifications(notifications, todo_file)

        entry = todo_file.entries.first
        frames = entry["location"].split(" -> ")
        expect(frames.length).to eq(app_stack.length)
      end

      it "defaults to 5 frames" do
        ProsopiteTodo.configure do |c|
          c.location_filter = ->(frames) { frames }
        end

        notifications = { "SELECT * FROM users" => [app_stack] }
        described_class.record_notifications(notifications, todo_file)

        entry = todo_file.entries.first
        frames = entry["location"].split(" -> ")
        expect(frames.length).to eq(5)
      end
    end

    context "when Rails.backtrace_cleaner is available and location_filter is not set" do
      let(:mixed_stack) do
        [
          "/usr/local/bundle/gems/activesupport-6.1.7/lib/active_support/notifications.rb:186:in `finish'",
          "app/models/user.rb:42:in `some_method'",
          "app/controllers/users_controller.rb:15:in `show'"
        ]
      end

      before do
        # Reset configuration to ensure location_filter is nil
        ProsopiteTodo.reset_configuration!

        # Mock Rails.backtrace_cleaner
        mock_cleaner = double("backtrace_cleaner")
        allow(mock_cleaner).to receive(:clean).and_return(["app/models/user.rb:42:in `some_method'"])

        mock_rails = Module.new
        mock_rails.define_singleton_method(:backtrace_cleaner) { mock_cleaner }
        mock_rails.define_singleton_method(:respond_to?) { |method| method == :backtrace_cleaner }
        stub_const("Rails", mock_rails)
      end

      after do
        ProsopiteTodo.reset_configuration!
      end

      it "uses Rails.backtrace_cleaner to clean frames" do
        notifications = { "SELECT * FROM users" => [mixed_stack] }
        described_class.record_notifications(notifications, todo_file)

        entry = todo_file.entries.first
        expect(entry["location"]).to eq("app/models/user.rb:42:in `some_method'")
      end
    end

    context "with custom location_filter" do
      let(:mixed_stack) do
        [
          "/usr/local/bundle/gems/activesupport-6.1.7/lib/active_support/notifications.rb:186:in `finish'",
          "app/models/user.rb:42:in `some_method'",
          "app/controllers/users_controller.rb:15:in `show'",
          "/usr/local/bundle/gems/rspec-core-3.12.0/lib/rspec/core/example.rb:263:in `run'"
        ]
      end

      it "applies custom filter to stack frames" do
        ProsopiteTodo.configure do |c|
          c.location_filter = ->(frames) { frames.select { |f| f.include?("app/") } }
          c.max_location_frames = nil
        end

        notifications = { "SELECT * FROM users" => [mixed_stack] }
        described_class.record_notifications(notifications, todo_file)

        entry = todo_file.entries.first
        frames = entry["location"].split(" -> ")
        expect(frames.length).to eq(2)
        expect(frames).to all(include("app/"))
      end

      it "applies max_location_frames after custom filter" do
        ProsopiteTodo.configure do |c|
          c.location_filter = ->(frames) { frames.select { |f| f.include?("app/") } }
          c.max_location_frames = 1
        end

        notifications = { "SELECT * FROM users" => [mixed_stack] }
        described_class.record_notifications(notifications, todo_file)

        entry = todo_file.entries.first
        frames = entry["location"].split(" -> ")
        expect(frames.length).to eq(1)
      end
    end

    context "fingerprint consistency with filtering" do
      it "generates consistent fingerprints after filtering" do
        ProsopiteTodo.configure do |c|
          c.location_filter = ->(frames) { frames }
          c.max_location_frames = 2
        end

        fp1 = described_class.fingerprint(query: "SELECT * FROM users", location: app_stack)
        fp2 = described_class.fingerprint(query: "SELECT * FROM users", location: app_stack)

        expect(fp1).to eq(fp2)
      end

      it "generates different fingerprints with different filter settings" do
        ProsopiteTodo.configure do |c|
          c.location_filter = ->(frames) { frames }
          c.max_location_frames = 2
        end
        fp1 = described_class.fingerprint(query: "SELECT * FROM users", location: app_stack)

        ProsopiteTodo.reset_configuration!
        ProsopiteTodo.configure do |c|
          c.location_filter = ->(frames) { frames }
          c.max_location_frames = 3
        end
        fp2 = described_class.fingerprint(query: "SELECT * FROM users", location: app_stack)

        expect(fp1).not_to eq(fp2)
      end
    end

    context "error handling in location_filter" do
      it "falls back to original frames when filter raises error" do
        ProsopiteTodo.configure do |c|
          c.location_filter = ->(_frames) { raise StandardError, "Filter error" }
          c.max_location_frames = nil
        end

        notifications = { "SELECT * FROM users" => [["app/test.rb:1", "app/test.rb:2"]] }

        expect { described_class.record_notifications(notifications, todo_file) }.not_to raise_error

        entry = todo_file.entries.first
        expect(entry["location"]).to eq("app/test.rb:1 -> app/test.rb:2")
      end

      it "outputs warning when filter raises error" do
        ProsopiteTodo.configure do |c|
          c.location_filter = ->(_frames) { raise StandardError, "Something went wrong" }
          c.max_location_frames = nil
        end

        notifications = { "SELECT * FROM users" => [["app/test.rb:1"]] }

        expect {
          described_class.record_notifications(notifications, todo_file)
        }.to output(/Error in location_filter: Something went wrong/).to_stderr
      end

      it "falls back to original frames when filter returns non-array" do
        ProsopiteTodo.configure do |c|
          c.location_filter = ->(_frames) { "not an array" }
          c.max_location_frames = nil
        end

        notifications = { "SELECT * FROM users" => [["app/test.rb:1", "app/test.rb:2"]] }

        expect { described_class.record_notifications(notifications, todo_file) }.not_to raise_error

        entry = todo_file.entries.first
        expect(entry["location"]).to eq("app/test.rb:1 -> app/test.rb:2")
      end

      it "outputs warning when filter returns non-array" do
        ProsopiteTodo.configure do |c|
          c.location_filter = ->(_frames) { { key: "value" } }
          c.max_location_frames = nil
        end

        notifications = { "SELECT * FROM users" => [["app/test.rb:1"]] }

        expect {
          described_class.record_notifications(notifications, todo_file)
        }.to output(/location_filter must return an Array, got Hash/).to_stderr
      end

      it "handles filter returning nil by falling back to original frames" do
        ProsopiteTodo.configure do |c|
          c.location_filter = ->(_frames) { nil }
          c.max_location_frames = nil
        end

        notifications = { "SELECT * FROM users" => [["app/test.rb:1"]] }

        expect { described_class.record_notifications(notifications, todo_file) }.not_to raise_error

        entry = todo_file.entries.first
        expect(entry["location"]).to eq("app/test.rb:1")
      end
    end
  end
end
