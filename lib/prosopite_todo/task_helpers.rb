# frozen_string_literal: true

module ProsopiteTodo
  # Task helper module containing the logic for rake tasks
  # This allows the logic to be tested independently of Rake
  module TaskHelpers
    class << self
      def generate(output: $stdout)
        todo_file = ProsopiteTodo::TodoFile.new(ProsopiteTodo.todo_file_path)
        todo_file.clear

        notifications = ProsopiteTodo.pending_notifications
        ProsopiteTodo::Scanner.record_notifications(notifications, todo_file)
        todo_file.save

        output.puts "Generated #{todo_file.path} with #{todo_file.entries.length} entries"
      end

      def update(output: $stdout)
        todo_file = ProsopiteTodo::TodoFile.new(ProsopiteTodo.todo_file_path)

        notifications = ProsopiteTodo.pending_notifications
        ProsopiteTodo::Scanner.record_notifications(notifications, todo_file)
        todo_file.save

        output.puts "Updated #{todo_file.path} with #{todo_file.entries.length} total entries"
      end

      def list(output: $stdout)
        todo_file = ProsopiteTodo::TodoFile.new(ProsopiteTodo.todo_file_path)

        if todo_file.entries.empty?
          output.puts "No entries in #{todo_file.path}"
        else
          output.puts "Entries in #{todo_file.path}:\n\n"
          todo_file.entries.each_with_index do |entry, index|
            output.puts "#{index + 1}. #{entry['query']}"
            output.puts "   Location: #{entry['location']}"
            output.puts "   Fingerprint: #{entry['fingerprint']}"
            output.puts ""
          end
        end
      end

      def clean(output: $stdout)
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
        output.puts "Cleaned #{todo_file.path}: removed #{removed_count} entries, #{todo_file.entries.length} remaining"
      end
    end
  end
end
