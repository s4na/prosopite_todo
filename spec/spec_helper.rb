# frozen_string_literal: true

# SimpleCov must be started before any other code is loaded
require "simplecov"
require "simplecov-lcov"

SimpleCov::Formatter::LcovFormatter.config do |c|
  c.report_with_single_file = true
  c.single_report_path = "coverage/lcov.info"
end

SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new(
  [
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::LcovFormatter
  ]
)

SimpleCov.start do
  add_filter "/spec/"
  enable_coverage :branch
  minimum_coverage line: 80, branch: 70
end

# IMPORTANT: Require logger BEFORE active_support to fix Rails 6.x compatibility
# Rails 6.1 expects Logger constant to exist in a specific way that newer
# logger gem versions don't provide. Loading logger first resolves this.
require "logger"

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
