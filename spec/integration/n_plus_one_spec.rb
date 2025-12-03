# frozen_string_literal: true

# Integration test for ProsopiteTodo with real N+1 query simulation
# Using Rails bug template style: Define everything within the test file

require "bundler/inline"

gemfile(true) do
  source "https://rubygems.org"

  gem "rails"
  gem "sqlite3", ">= 2.1"
  gem "prosopite"
  gem "rspec"
end

require "active_record"
require "prosopite"
require "fileutils"
require "tempfile"
require "yaml"

# Load prosopite_todo from local lib
$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "prosopite_todo"

# Setup in-memory SQLite database
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Base.logger = nil

# Define schema
ActiveRecord::Schema.define do
  create_table :authors, force: true do |t|
    t.string :name
    t.timestamps
  end

  create_table :books, force: true do |t|
    t.string :title
    t.references :author, foreign_key: true
    t.timestamps
  end
end

# Define models
class Author < ActiveRecord::Base
  has_many :books
end

class Book < ActiveRecord::Base
  belongs_to :author
end

# Test helpers
def create_test_data
  3.times do |i|
    author = Author.create!(name: "Author #{i}")
    2.times do |j|
      Book.create!(title: "Book #{i}-#{j}", author: author)
    end
  end
end

def trigger_n_plus_one
  books = Book.all
  books.map { |book| book.author.name }
end

def trigger_n_plus_one_with_includes
  books = Book.includes(:author).all
  books.map { |book| book.author.name }
end

# Simulate Prosopite notification format
def simulate_n_plus_one_notifications
  {
    'SELECT "authors".* FROM "authors" WHERE "authors"."id" = $1' => [
      ["app/models/book.rb:10", "app/controllers/books_controller.rb:5"],
      ["app/models/book.rb:10", "app/controllers/books_controller.rb:8"]
    ]
  }
end

def simulate_different_n_plus_one_notifications
  {
    'SELECT "posts".* FROM "posts" WHERE "posts"."user_id" = $1' => [
      ["app/models/post.rb:20", "app/controllers/posts_controller.rb:10"]
    ]
  }
end

RSpec.describe "ProsopiteTodo Integration" do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:todo_file_path) { File.join(tmp_dir, ".prosopite_todo.yaml") }
  let(:todo_file) { ProsopiteTodo::TodoFile.new(todo_file_path) }

  before do
    create_test_data
  end

  after do
    FileUtils.rm_rf(tmp_dir)
    Book.delete_all
    Author.delete_all
    ProsopiteTodo.clear_pending_notifications
    ProsopiteTodo.reset_configuration!
  end

  describe "verifying N+1 scenario setup" do
    it "creates test data with associations" do
      expect(Author.count).to eq(3)
      expect(Book.count).to eq(6)
      expect(Book.first.author).to be_present
    end

    it "triggers multiple queries without includes (N+1 pattern)" do
      query_count = 0
      callback = ->(*) { query_count += 1 }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        trigger_n_plus_one
      end
      # 1 query for books + N queries for authors (one per book)
      expect(query_count).to be > 1
    end

    it "triggers single query with includes (no N+1)" do
      query_count = 0
      callback = ->(*) { query_count += 1 }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        trigger_n_plus_one_with_includes
      end
      # Should be just 2 queries: one for books, one for all authors
      expect(query_count).to eq(2)
    end
  end

  describe "ignore functionality with simulated Prosopite notifications" do
    context "when no todo file exists" do
      it "returns all notifications unchanged" do
        notifications = simulate_n_plus_one_notifications
        result = ProsopiteTodo::Scanner.filter_notifications(notifications, todo_file)
        expect(result).to eq(notifications)
      end
    end

    context "when todo file has matching fingerprint" do
      before do
        notifications = simulate_n_plus_one_notifications
        ProsopiteTodo::Scanner.record_notifications(notifications, todo_file)
        todo_file.save
      end

      it "filters out matching notifications" do
        notifications = simulate_n_plus_one_notifications
        result = ProsopiteTodo::Scanner.filter_notifications(notifications, todo_file)
        expect(result).to be_empty
      end

      it "keeps non-matching notifications" do
        new_notifications = simulate_different_n_plus_one_notifications
        result = ProsopiteTodo::Scanner.filter_notifications(new_notifications, todo_file)
        expect(result).not_to be_empty
        expect(result.keys.first).to include("posts")
      end
    end

    context "with multiple locations for same query" do
      it "filters only the matching location combination" do
        # Add first location to todo
        query = 'SELECT "authors".* FROM "authors" WHERE "authors"."id" = $1'
        location1 = ["app/models/book.rb:10", "app/controllers/books_controller.rb:5"]
        location2 = ["app/models/book.rb:10", "app/controllers/books_controller.rb:8"]

        fp1 = ProsopiteTodo::Scanner.fingerprint(query: query, location: location1)
        todo_file.add_entry(fingerprint: fp1, query: query, location: location1.join(" -> "))
        todo_file.save

        notifications = { query => [location1, location2] }
        result = ProsopiteTodo::Scanner.filter_notifications(notifications, todo_file)

        # Only location1 should be filtered, location2 should remain
        expect(result[query]).to eq([location2])
      end
    end
  end

  describe "todo file generation" do
    it "records notifications to todo file" do
      notifications = simulate_n_plus_one_notifications
      ProsopiteTodo::Scanner.record_notifications(notifications, todo_file)
      todo_file.save

      expect(File.exist?(todo_file_path)).to be true

      loaded = ProsopiteTodo::TodoFile.new(todo_file_path)
      expect(loaded.entries.length).to eq(2)  # Two locations
      expect(loaded.entries.first["query"]).to include("authors")
    end

    it "generates consistent fingerprints" do
      notifications = simulate_n_plus_one_notifications
      query = notifications.keys.first
      location = notifications[query].first

      fp1 = ProsopiteTodo::Scanner.fingerprint(query: query, location: location)
      fp2 = ProsopiteTodo::Scanner.fingerprint(query: query, location: location)

      expect(fp1).to eq(fp2)
    end

    it "generates different fingerprints for different queries" do
      n1 = simulate_n_plus_one_notifications
      n2 = simulate_different_n_plus_one_notifications

      fp1 = ProsopiteTodo::Scanner.fingerprint(query: n1.keys.first, location: n1.values.first.first)
      fp2 = ProsopiteTodo::Scanner.fingerprint(query: n2.keys.first, location: n2.values.first.first)

      expect(fp1).not_to eq(fp2)
    end
  end

  describe "end-to-end workflow" do
    it "complete workflow: detect -> record -> ignore" do
      # Step 1: Simulate N+1 detection
      notifications = simulate_n_plus_one_notifications
      expect(notifications).not_to be_empty

      # Step 2: Record to todo file (simulating `prosopite_todo:generate`)
      todo_file.clear
      ProsopiteTodo::Scanner.record_notifications(notifications, todo_file)
      todo_file.save
      expect(todo_file.entries.length).to eq(2)

      # Step 3: Reload and verify ignore works
      reloaded_todo = ProsopiteTodo::TodoFile.new(todo_file_path)

      # Same notifications should be filtered
      filtered = ProsopiteTodo::Scanner.filter_notifications(notifications, reloaded_todo)
      expect(filtered).to be_empty

      # Different notifications should not be filtered
      different = simulate_different_n_plus_one_notifications
      filtered_different = ProsopiteTodo::Scanner.filter_notifications(different, reloaded_todo)
      expect(filtered_different).not_to be_empty
    end

    it "update workflow: keep existing + add new" do
      # Initial notifications
      initial = simulate_n_plus_one_notifications
      ProsopiteTodo::Scanner.record_notifications(initial, todo_file)
      todo_file.save
      initial_count = todo_file.entries.length

      # Add new notifications (simulating `prosopite_todo:update`)
      new_notifications = simulate_different_n_plus_one_notifications
      ProsopiteTodo::Scanner.record_notifications(new_notifications, todo_file)
      todo_file.save

      expect(todo_file.entries.length).to eq(initial_count + 1)

      # Both should be ignored now
      reloaded = ProsopiteTodo::TodoFile.new(todo_file_path)
      expect(ProsopiteTodo::Scanner.filter_notifications(initial, reloaded)).to be_empty
      expect(ProsopiteTodo::Scanner.filter_notifications(new_notifications, reloaded)).to be_empty
    end
  end

  describe "YAML file format" do
    it "creates human-readable YAML" do
      notifications = simulate_n_plus_one_notifications
      ProsopiteTodo::Scanner.record_notifications(notifications, todo_file)
      todo_file.save

      content = File.read(todo_file_path)

      expect(content).to include("fingerprint:")
      expect(content).to include("query:")
      expect(content).to include("location:")
      expect(content).to include("created_at:")
    end

    it "is loadable as valid YAML" do
      notifications = simulate_n_plus_one_notifications
      ProsopiteTodo::Scanner.record_notifications(notifications, todo_file)
      todo_file.save

      loaded = YAML.safe_load(File.read(todo_file_path))
      expect(loaded).to be_an(Array)
      expect(loaded.first).to have_key("fingerprint")
    end
  end
end

# Run the specs
if __FILE__ == $PROGRAM_NAME
  RSpec::Core::Runner.run([__FILE__])
end
