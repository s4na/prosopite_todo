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
  module RSpec
    class << self
      def setup
        return unless enabled?

        ::RSpec.configure do |config|
          config.after(:suite) do
            ProsopiteTodo.update_todo!
          end
        end
      end

      def enabled?
        %w[1 true yes].include?(ENV.fetch("PROSOPITE_TODO_UPDATE", nil)&.downcase)
      end
    end
  end
end

# Auto-setup when required
ProsopiteTodo::RSpec.setup
