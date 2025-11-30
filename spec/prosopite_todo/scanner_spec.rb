# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"

RSpec.describe ProsopiteTodo::Scanner do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:todo_file_path) { File.join(tmp_dir, ".prosopite_todo.yaml") }

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  describe ".fingerprint" do
    it "generates consistent fingerprint for same query and location" do
      fp1 = described_class.fingerprint(query: "SELECT * FROM users", location: ["app/models/user.rb:10"])
      fp2 = described_class.fingerprint(query: "SELECT * FROM users", location: ["app/models/user.rb:10"])

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
  end
end
