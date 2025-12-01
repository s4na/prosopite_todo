# frozen_string_literal: true

require_relative "prosopite_todo/version"
require_relative "prosopite_todo/todo_file"
require_relative "prosopite_todo/scanner"
require_relative "prosopite_todo/railtie" if defined?(Rails::Railtie)

module ProsopiteTodo
  class Error < StandardError; end

  # Mutex for thread-safe access to pending_notifications
  # Required for multi-threaded servers like Puma
  @mutex = Mutex.new

  class << self
    attr_writer :todo_file_path

    def todo_file_path
      @todo_file_path || TodoFile.default_path
    end

    def pending_notifications
      mutex.synchronize { @pending_notifications || {} }
    end

    def pending_notifications=(notifications)
      mutex.synchronize { @pending_notifications = notifications }
    end

    def add_pending_notification(query:, locations:)
      mutex.synchronize do
        @pending_notifications ||= {}
        @pending_notifications[query] ||= []
        @pending_notifications[query].concat(Array(locations))
      end
    end

    def clear_pending_notifications
      mutex.synchronize { @pending_notifications = {} }
    end

    # Update TODO file with pending notifications (adds new entries without removing existing ones)
    # Returns the number of new entries added
    # Raises ProsopiteTodo::Error if file operations fail
    # Thread-safe: uses mutex to protect pending_notifications access
    def update_todo!
      # Take a snapshot of notifications under mutex, then release for file I/O
      notifications_snapshot = mutex.synchronize do
        @pending_notifications&.dup || {}
      end

      todo_file = TodoFile.new(todo_file_path)
      initial_count = todo_file.entries.length

      Scanner.record_notifications(notifications_snapshot, todo_file)
      todo_file.save

      new_count = todo_file.entries.length - initial_count

      if new_count.positive?
        warn "[ProsopiteTodo] Added #{new_count} new N+1 entries to #{todo_file.path}"
      end

      # Clear pending notifications after successful save to prevent accidental re-saving
      clear_pending_notifications

      new_count
    rescue SystemCallError, IOError => e
      raise Error, "Failed to update TODO file: #{e.message}"
    end

    private

    def mutex
      ProsopiteTodo.instance_variable_get(:@mutex)
    end
  end
end
