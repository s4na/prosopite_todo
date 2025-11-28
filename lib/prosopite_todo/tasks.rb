# frozen_string_literal: true

namespace :prosopite_todo do
  desc "Generate .prosopite_todo.yaml from current N+1 detections (overwrites existing)"
  task :generate do
    todo_file = ProsopiteTodo::TodoFile.new(ProsopiteTodo.todo_file_path)
    todo_file.clear

    notifications = ProsopiteTodo.pending_notifications
    ProsopiteTodo::Scanner.record_notifications(notifications, todo_file)
    todo_file.save

    puts "Generated #{todo_file.path} with #{todo_file.entries.length} entries"
  end

  desc "Update .prosopite_todo.yaml by adding new N+1 detections"
  task :update do
    todo_file = ProsopiteTodo::TodoFile.new(ProsopiteTodo.todo_file_path)

    notifications = ProsopiteTodo.pending_notifications
    ProsopiteTodo::Scanner.record_notifications(notifications, todo_file)
    todo_file.save

    puts "Updated #{todo_file.path} with #{todo_file.entries.length} total entries"
  end

  desc "List all entries in .prosopite_todo.yaml"
  task :list do
    todo_file = ProsopiteTodo::TodoFile.new(ProsopiteTodo.todo_file_path)

    if todo_file.entries.empty?
      puts "No entries in #{todo_file.path}"
    else
      puts "Entries in #{todo_file.path}:\n\n"
      todo_file.entries.each_with_index do |entry, index|
        puts "#{index + 1}. #{entry['query']}"
        puts "   Location: #{entry['location']}"
        puts "   Fingerprint: #{entry['fingerprint']}"
        puts ""
      end
    end
  end

  desc "Clean .prosopite_todo.yaml by removing entries no longer detected"
  task :clean do
    todo_file = ProsopiteTodo::TodoFile.new(ProsopiteTodo.todo_file_path)
    notifications = ProsopiteTodo.pending_notifications

    # Build set of current fingerprints
    current_fingerprints = Set.new
    notifications.each do |query, locations_array|
      locations_array.each do |location|
        fp = ProsopiteTodo::Scanner.fingerprint(query: query, location: location)
        current_fingerprints << fp
      end
    end

    # Filter entries to keep only those still detected
    original_count = todo_file.entries.length
    kept_entries = todo_file.entries.select do |entry|
      current_fingerprints.include?(entry["fingerprint"])
    end

    todo_file.clear
    kept_entries.each do |entry|
      todo_file.add_entry(
        fingerprint: entry["fingerprint"],
        query: entry["query"],
        location: entry["location"]
      )
    end
    todo_file.save

    removed_count = original_count - todo_file.entries.length
    puts "Cleaned #{todo_file.path}: removed #{removed_count} entries, #{todo_file.entries.length} remaining"
  end
end
