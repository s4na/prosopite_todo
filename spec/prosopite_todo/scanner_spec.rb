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
  end
end
