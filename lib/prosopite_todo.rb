# frozen_string_literal: true

require_relative "prosopite_todo/version"
require_relative "prosopite_todo/configuration"
require_relative "prosopite_todo/todo_file"
require_relative "prosopite_todo/scanner"
require_relative "prosopite_todo/railtie" if defined?(Rails::Railtie)

module ProsopiteTodo
  class Error < StandardError; end

  # Mutex for thread-safe access to pending_notifications
  # Required for multi-threaded servers like Puma
  @mutex = Mutex.new

  class << self
    # Note: Configuration (todo_file_path=) should be done at boot time,
    # before multi-threaded execution begins. This is standard Ruby practice.
    attr_writer :todo_file_path

    # Current test location for tracking which test detected the N+1
    # Set by RSpec/test framework integration
    attr_accessor :current_test_location

    def todo_file_path
      @todo_file_path || TodoFile.default_path
    end

    def pending_notifications
      mutex.synchronize do
        return {} unless @pending_notifications

        # Return deep copy to prevent external mutation of internal state
        @pending_notifications.transform_values do |locations|
          locations.map do |loc|
            if loc.is_a?(Hash)
              # Deep copy: also dup the hash contents
              {
                call_stack: deep_dup(loc[:call_stack]),
                test_location: loc[:test_location]&.dup
              }
            else
              deep_dup(loc)
            end
          end
        end
      end
    end

    # Deep duplicate for arrays and strings
    def deep_dup(obj)
      case obj
      when Array
        obj.map { |e| e.dup rescue e }
      when String
        obj.dup
      else
        obj
      end
    end

    def pending_notifications=(notifications)
      mutex.synchronize { @pending_notifications = notifications }
    end

    # Add a pending notification with test_location support
    # @param query [String] the SQL query
    # @param locations [Array] array of call stack locations
    # @param test_location [String, nil] the test file location (auto-detected if nil)
    def add_pending_notification(query:, locations:, test_location: nil)
      test_loc = test_location || current_test_location || detect_test_location
      mutex.synchronize do
        @pending_notifications ||= {}
        @pending_notifications[query] ||= []
        Array(locations).each do |location|
          @pending_notifications[query] << {
            call_stack: location,
            test_location: test_loc
          }
        end
      end
    end

    def clear_pending_notifications
      mutex.synchronize { @pending_notifications = {} }
    end

    # Track all executed test locations (not just those with N+1 detections)
    # This allows proper cleanup when tests run but detect no N+1s
    def executed_test_locations
      mutex.synchronize { @executed_test_locations ||= Set.new }
    end

    # Register a test location as executed
    # @param test_location [String] the test file location (e.g., "spec/models/user_spec.rb:10")
    def register_executed_test(test_location)
      return if test_location.nil? || test_location.to_s.empty?

      # Normalize: remove line number for grouping by test file
      normalized = Scanner.send(:normalize_test_location, test_location)
      return unless normalized

      mutex.synchronize do
        @executed_test_locations ||= Set.new
        @executed_test_locations << normalized
      end
    end

    def clear_executed_test_locations
      mutex.synchronize { @executed_test_locations = Set.new }
    end

    # Detect test location from caller stack
    # Looks for spec/ or test/ directories in the call stack
    # Uses stricter pattern to avoid false positives (e.g., "/users/spec/")
    def detect_test_location
      caller_locations.each do |loc|
        path = loc.path
        next unless path

        # Normalize path for cross-platform compatibility
        normalized_path = path.gsub("\\", "/")

        # Match spec/ or test/ directory at start or after a slash
        # This avoids matching paths like "/users/spec/code.rb"
        if normalized_path.match?(%r{(?:^|/)(?:spec|test)/})
          return "#{path}:#{loc.lineno}"
        end
      end
      nil
    end

    # Update TODO file with pending notifications
    # @param clean [Boolean] if true, removes entries for tests that were run but no longer detect N+1 (default: true)
    # Returns a hash with :added and :removed counts
    # Raises ProsopiteTodo::Error if file operations fail
    # Thread-safe: uses atomic swap pattern to prevent data loss
    #
    # Note: When clean is true, only entries for tests that were actually run are candidates for removal.
    # Entries from tests that were NOT run are preserved. This allows partial test runs without losing
    # N+1 entries from other tests.
    def update_todo!(clean: true)
      # Atomically swap notifications and executed_test_locations to prevent data loss
      notifications_to_save, test_locations_to_use = mutex.synchronize do
        old_notifications = @pending_notifications || {}
        old_test_locations = @executed_test_locations || Set.new
        @pending_notifications = {}
        @executed_test_locations = Set.new
        [old_notifications, old_test_locations]
      end

      todo_file = TodoFile.new(todo_file_path)

      removed_count = 0
      if clean
        detected_locations = Scanner.extract_detected_locations(notifications_to_save)
        # Use executed_test_locations (all tests that ran) instead of just those with N+1s
        # This ensures cleanup works even when all N+1s are resolved
        removed_count = todo_file.filter_by_test_locations!(detected_locations, test_locations_to_use)
      end

      count_before_add = todo_file.entries.length
      Scanner.record_notifications(notifications_to_save, todo_file)
      todo_file.save

      added_count = todo_file.entries.length - count_before_add

      if added_count.positive? || removed_count.positive?
        messages = []
        messages << "Added #{added_count} new" if added_count.positive?
        messages << "Removed #{removed_count} resolved" if removed_count.positive?
        warn "[ProsopiteTodo] #{messages.join(', ')} N+1 entries in #{todo_file.path}"
      end

      { added: added_count, removed: removed_count }
    rescue SystemCallError, IOError => e
      # On failure, restore notifications and executed_test_locations to prevent data loss.
      # Note: If Scanner.record_notifications succeeded but save failed,
      # notifications may exist in both TodoFile (in-memory) and here.
      # This is safe because TodoFile.add_entry uses fingerprint-based
      # deduplication, so the next save attempt won't create duplicates.
      mutex.synchronize do
        notifications_to_save.each do |query, locations|
          @pending_notifications ||= {}
          @pending_notifications[query] ||= []
          @pending_notifications[query].concat(locations)
        end
        # Restore executed test locations
        @executed_test_locations ||= Set.new
        @executed_test_locations.merge(test_locations_to_use)
      end
      raise Error, "Failed to update TODO file: #{e.message}"
    end

    private

    def mutex
      ProsopiteTodo.instance_variable_get(:@mutex)
    end
  end
end
