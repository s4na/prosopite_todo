# frozen_string_literal: true

require "prosopite_todo"

module ProsopiteTodo
  # RSpec integration helper for adding N+1 detections to TODO file
  #
  # Usage in spec/rails_helper.rb:
  #   require 'prosopite_todo/rspec'
  #
  # Then run:
  #   PROSOPITE_TODO_UPDATE=1 bundle exec rspec spec/models/user_spec.rb
  #
  # To disable auto-removal of resolved N+1 entries:
  #   PROSOPITE_TODO_UPDATE=1 PROSOPITE_TODO_CLEAN=0 bundle exec rspec
  #
  module RSpec
    class << self
      def setup
        return unless enabled?

        clean = clean_enabled?
        ::RSpec.configure do |config|
          config.after(:suite) do
            ProsopiteTodo.update_todo!(clean: clean)
          end
        end
      end

      def enabled?
        %w[1 true yes].include?(ENV.fetch("PROSOPITE_TODO_UPDATE", nil)&.downcase)
      end

      def clean_enabled?
        # Default to true unless explicitly disabled
        !%w[0 false no].include?(ENV.fetch("PROSOPITE_TODO_CLEAN", nil)&.downcase)
      end
    end
  end
end

# Auto-setup when required
ProsopiteTodo::RSpec.setup
