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
          detected_locations = ProsopiteTodo::Scanner.extract_detected_locations(notifications)
          # Use executed_test_locations if available (RSpec context), otherwise fall back to
          # test locations from notifications (Rake task context)
          test_locations_to_use = ProsopiteTodo.executed_test_locations
          if test_locations_to_use.empty?
            test_locations_to_use = ProsopiteTodo::Scanner.extract_test_locations(notifications)
          end
          removed_count = todo_file.filter_by_test_locations!(detected_locations, test_locations_to_use)
        end

        count_before_add = todo_file.entries.length
        ProsopiteTodo::Scanner.record_notifications(notifications, todo_file)
        todo_file.save

        added_count = todo_file.entries.length - count_before_add

        messages = ["Updated #{todo_file.path}"]
        messages << "added #{added_count}" if added_count.positive?
        messages << "removed #{removed_count} locations" if removed_count.positive?
        messages << "(#{todo_file.entries.length} total entries)"
        output.puts messages.join(", ")
      end

      def clean_enabled?
        # Default to true unless explicitly disabled
        !%w[0 false no].include?(ENV.fetch("PROSOPITE_TODO_CLEAN", nil)&.downcase)
      end

      def list(output: $stdout)
        todo_file = ProsopiteTodo::TodoFile.new(ProsopiteTodo.todo_file_path)

        if todo_file.entries.empty?
          output.puts "No entries in #{todo_file.path}"
        else
          output.puts "Entries in #{todo_file.path}:\n\n"
          todo_file.entries.each_with_index do |entry, index|
            output.puts "#{index + 1}. #{entry['query']}"
            output.puts "   Fingerprint: #{entry['fingerprint']}"
            entry["locations"]&.each_with_index do |loc, loc_index|
              output.puts "   Location #{loc_index + 1}: #{loc['location']}"
              output.puts "     Test: #{loc['test_location']}" if loc["test_location"]
            end
            output.puts ""
          end
        end
      end

      def clean(output: $stdout)
        todo_file = ProsopiteTodo::TodoFile.new(ProsopiteTodo.todo_file_path)
        notifications = ProsopiteTodo.pending_notifications

        detected_locations = ProsopiteTodo::Scanner.extract_detected_locations(notifications)
        # Use executed_test_locations if available (RSpec context), otherwise fall back to
        # test locations from notifications (Rake task context)
        test_locations_to_use = ProsopiteTodo.executed_test_locations
        if test_locations_to_use.empty?
          test_locations_to_use = ProsopiteTodo::Scanner.extract_test_locations(notifications)
        end
        removed_count = todo_file.filter_by_test_locations!(detected_locations, test_locations_to_use)
        todo_file.save

        output.puts "Cleaned #{todo_file.path}: removed #{removed_count} locations, #{todo_file.entries.length} entries remaining"
      end
    end
  end
end
