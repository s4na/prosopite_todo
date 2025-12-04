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
  # Note: With test_location tracking, only N+1 entries from tests that were
  # actually run will be candidates for removal. Entries from other tests
  # are preserved, making partial test runs safe.
  #
  module RSpec
    class << self
      def setup
        return unless enabled?

        clean = clean_enabled?
        ::RSpec.configure do |config|
          # Track current test location for N+1 detection
          config.around(:each) do |example|
            # Set the current test location from the example metadata
            test_location = example.metadata[:location]
            ProsopiteTodo.current_test_location = test_location

            # Register this test as executed (for proper cleanup even when no N+1s detected)
            ProsopiteTodo.register_executed_test(test_location)

            begin
              example.run
            ensure
              ProsopiteTodo.current_test_location = nil
            end
          end

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
