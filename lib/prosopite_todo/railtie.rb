# frozen_string_literal: true

require "rails/railtie"

module ProsopiteTodo
  class Railtie < Rails::Railtie
    rake_tasks do
      load File.expand_path("tasks.rb", __dir__)
    end

    initializer "prosopite_todo.configure" do |app|
      # Set up Prosopite with filtering callback if prosopite is loaded
      app.config.after_initialize do
        setup_prosopite_integration if defined?(Prosopite)
      end
    end

    class << self
      def setup_prosopite_integration
        return unless defined?(Prosopite)

        todo_file = ProsopiteTodo::TodoFile.new

        # Store original finish_callback
        original_callback = Prosopite.instance_variable_get(:@finish_callback)

        Prosopite.finish_callback = proc do |notifications|
          # Filter out ignored notifications
          filtered = ProsopiteTodo::Scanner.filter_notifications(notifications, todo_file)

          # Accumulate notifications for todo generation (supports multiple test runs)
          notifications.each do |query, locations|
            ProsopiteTodo.add_pending_notification(query: query, locations: locations)
          end

          # Call original callback with filtered notifications if it exists
          original_callback&.call(filtered)

          filtered
        end
      end
    end
  end
end
