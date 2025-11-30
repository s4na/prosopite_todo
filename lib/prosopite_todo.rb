# frozen_string_literal: true

require_relative "prosopite_todo/version"
require_relative "prosopite_todo/todo_file"
require_relative "prosopite_todo/scanner"
require_relative "prosopite_todo/railtie" if defined?(Rails::Railtie)

module ProsopiteTodo
  class Error < StandardError; end

  class << self
    attr_writer :todo_file_path

    def todo_file_path
      @todo_file_path || TodoFile.default_path
    end

    def pending_notifications
      @pending_notifications || {}
    end

    def pending_notifications=(notifications)
      @pending_notifications = notifications
    end

    def add_pending_notification(query:, locations:)
      @pending_notifications ||= {}
      @pending_notifications[query] ||= []
      @pending_notifications[query].concat(Array(locations))
    end

    def clear_pending_notifications
      @pending_notifications = {}
    end

    # Update TODO file with pending notifications (adds new entries without removing existing ones)
    # Returns the number of new entries added
    # Raises ProsopiteTodo::Error if file operations fail
    def update_todo!
      todo_file = TodoFile.new(todo_file_path)
      initial_count = todo_file.entries.length

      Scanner.record_notifications(pending_notifications, todo_file)
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
  end
end
