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
        Railtie.setup_prosopite_integration if defined?(Prosopite)
      end
    end

    class << self
      def setup_prosopite_integration
        return unless defined?(Prosopite)

        todo_file = ProsopiteTodo::TodoFile.new

        # Prosopite 2.x does not have finish_callback, so we use monkey patching
        # to intercept notifications before they are sent
        Prosopite.singleton_class.prepend(Railtie.ProsopiteIntegration(todo_file))

        # Add SQLite support for fingerprinting (Prosopite only supports MySQL and PostgreSQL)
        Railtie.add_sqlite_fingerprint_support
      end

      def add_sqlite_fingerprint_support
        return unless defined?(Prosopite)

        Prosopite.singleton_class.prepend(SqliteFingerprintSupport)
      end
    end

    # Module to add SQLite fingerprint support to Prosopite
    # Prosopite only supports MySQL and PostgreSQL by default
    module SqliteFingerprintSupport
      def fingerprint(query)
        db_adapter = ActiveRecord::Base.connection_db_config.adapter
        if db_adapter.include?("sqlite")
          sqlite_fingerprint(query)
        else
          super
        end
      end

      # Simple fingerprint for SQLite queries (similar to MySQL approach)
      def sqlite_fingerprint(query)
        query = query.dup

        # Remove comments
        query.gsub!(%r{/\*[^!].*?\*/}m, "")
        query.gsub!(/(?:--|#)[^\r\n]*(?=[\r\n]|\Z)/, "")

        # Normalize strings
        query.gsub!(/\\["']/, "")
        query.gsub!(/".*?"/m, "?")
        query.gsub!(/'.*?'/m, "?")

        # Normalize booleans and numbers
        query.gsub!(/\btrue\b|\bfalse\b/i, "?")
        query.gsub!(/[0-9+-][0-9a-f.x+-]*/, "?")
        query.gsub!(/[xb.+-]\?/, "?")

        # Normalize whitespace
        query.strip!
        query.gsub!(/[ \n\t\r\f]+/, " ")
        query.downcase!

        # Normalize NULL and IN clauses
        query.gsub!(/\bnull\b/i, "?")
        query.gsub!(/\b(in|values?)(?:[\s,]*\([\s?,]*\))+/, "\\1(?+)")

        query.gsub!(/\blimit \?(?:, ?\?| offset \?)/, "limit ?")

        query
      end
    end

    # Module to prepend to Prosopite for notification interception
    # Uses a class method to create a module with access to todo_file
    def self.ProsopiteIntegration(todo_file)
      Module.new do
        define_method(:create_notifications) do
          super()

          tc = Thread.current
          return unless tc[:prosopite_notifications]

          # Accumulate notifications for todo generation
          tc[:prosopite_notifications].each do |query, locations|
            ProsopiteTodo.add_pending_notification(query: query, locations: Array(locations))
          end

          # Filter out ignored notifications
          tc[:prosopite_notifications] = ProsopiteTodo::Scanner.filter_notifications(
            tc[:prosopite_notifications],
            todo_file
          )
        end
      end
    end
  end
end
