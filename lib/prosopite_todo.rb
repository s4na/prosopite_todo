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
  end
end
