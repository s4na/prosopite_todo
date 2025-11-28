# frozen_string_literal: true

require "spec_helper"
require "rake"
require "tempfile"
require "fileutils"

RSpec.describe "ProsopiteTodo Rake Tasks" do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:todo_file_path) { File.join(tmp_dir, ".prosopite_todo.yaml") }

  before do
    Rake.application = Rake::Application.new
    load File.expand_path("../../lib/prosopite_todo/tasks.rb", __dir__)

    allow(ProsopiteTodo).to receive(:todo_file_path).and_return(todo_file_path)
    allow(ProsopiteTodo).to receive(:pending_notifications).and_return({})
  end

  after do
    FileUtils.rm_rf(tmp_dir)
    Rake::Task.tasks.each(&:reenable)
  end

  describe "prosopite_todo:generate" do
    it "creates a new todo file with pending notifications" do
      allow(ProsopiteTodo).to receive(:pending_notifications).and_return(
        "SELECT * FROM users" => [["app/models/user.rb:10"]]
      )

      expect { Rake.application["prosopite_todo:generate"].invoke }
        .to output(/Generated/).to_stdout

      todo_file = ProsopiteTodo::TodoFile.new(todo_file_path)
      expect(todo_file.entries.length).to eq(1)
    end

    it "clears existing entries before generating" do
      File.write(todo_file_path, <<~YAML)
        ---
        - fingerprint: "old123"
          query: "SELECT * FROM old_table"
      YAML

      allow(ProsopiteTodo).to receive(:pending_notifications).and_return(
        "SELECT * FROM users" => [["app/models/user.rb:10"]]
      )

      Rake.application["prosopite_todo:generate"].invoke

      todo_file = ProsopiteTodo::TodoFile.new(todo_file_path)
      expect(todo_file.entries.length).to eq(1)
      expect(todo_file.entries[0]["query"]).to eq("SELECT * FROM users")
    end
  end

  describe "prosopite_todo:update" do
    it "adds new notifications while keeping existing ones" do
      # Create existing entry
      todo_file = ProsopiteTodo::TodoFile.new(todo_file_path)
      todo_file.add_entry(
        fingerprint: "existing123",
        query: "SELECT * FROM posts",
        location: "app/models/post.rb:5"
      )
      todo_file.save

      allow(ProsopiteTodo).to receive(:pending_notifications).and_return(
        "SELECT * FROM users" => [["app/models/user.rb:10"]]
      )

      expect { Rake.application["prosopite_todo:update"].invoke }
        .to output(/Updated/).to_stdout

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

      allow(ProsopiteTodo).to receive(:pending_notifications).and_return(
        "SELECT * FROM users" => [["app/models/user.rb:10"]]
      )

      Rake.application["prosopite_todo:update"].invoke

      reloaded = ProsopiteTodo::TodoFile.new(todo_file_path)
      expect(reloaded.entries.length).to eq(1)
    end
  end

  describe "prosopite_todo:list" do
    it "displays all todo entries" do
      todo_file = ProsopiteTodo::TodoFile.new(todo_file_path)
      todo_file.add_entry(
        fingerprint: "abc123",
        query: "SELECT * FROM users",
        location: "app/models/user.rb:10"
      )
      todo_file.save

      expect { Rake.application["prosopite_todo:list"].invoke }
        .to output(/SELECT \* FROM users/).to_stdout
    end

    it "shows message when no entries exist" do
      expect { Rake.application["prosopite_todo:list"].invoke }
        .to output(/No entries/).to_stdout
    end
  end

  describe "prosopite_todo:clean" do
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

      allow(ProsopiteTodo).to receive(:pending_notifications).and_return(
        "SELECT * FROM users" => [["app/models/user.rb:10"]]
      )

      expect { Rake.application["prosopite_todo:clean"].invoke }
        .to output(/Cleaned/).to_stdout

      reloaded = ProsopiteTodo::TodoFile.new(todo_file_path)
      expect(reloaded.entries.length).to eq(1)
      expect(reloaded.entries[0]["query"]).to eq("SELECT * FROM users")
    end
  end
end
