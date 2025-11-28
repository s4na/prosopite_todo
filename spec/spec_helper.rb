# frozen_string_literal: true

# Require active_support first, then railties for Railtie tests
require "active_support"
require "active_support/core_ext"

# Load Rails::Railtie for our Railtie to inherit from
require "rails/railtie"

require "prosopite_todo"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
