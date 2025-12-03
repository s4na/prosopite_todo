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

      def update(output: $stdout, clean: clean_enabled?)
        todo_file = ProsopiteTodo::TodoFile.new(ProsopiteTodo.todo_file_path)

        notifications = ProsopiteTodo.pending_notifications

        removed_count = 0
        if clean
          current_fingerprints = ProsopiteTodo::Scanner.extract_fingerprints(notifications)
          removed_count = todo_file.filter_by_fingerprints!(current_fingerprints)
        end

        count_before_add = todo_file.entries.length
        ProsopiteTodo::Scanner.record_notifications(notifications, todo_file)
        todo_file.save

        added_count = todo_file.entries.length - count_before_add

        messages = ["Updated #{todo_file.path}"]
        messages << "added #{added_count}" if added_count.positive?
        messages << "removed #{removed_count}" if removed_count.positive?
        messages << "(#{todo_file.entries.length} total entries)"
        output.puts messages.join(", ")
      end

      def clean_enabled?
        %w[1 true yes].include?(ENV.fetch("PROSOPITE_TODO_CLEAN", nil)&.downcase)
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

        current_fingerprints = ProsopiteTodo::Scanner.extract_fingerprints(notifications)
        removed_count = todo_file.filter_by_fingerprints!(current_fingerprints)
        todo_file.save

        output.puts "Cleaned #{todo_file.path}: removed #{removed_count} entries, #{todo_file.entries.length} remaining"
      end
    end
  end
end
