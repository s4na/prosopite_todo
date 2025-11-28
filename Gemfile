# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in prosopite_todo.gemspec
gemspec

gem "rake", "~> 13.0"
gem "rspec", "~> 3.0"

# Allow specifying Rails version via environment variable for CI matrix
rails_version = ENV.fetch("RAILS_VERSION", nil)

if rails_version
  gem "rails", "~> #{rails_version}.0"

  # sqlite3 version compatibility
  if rails_version.to_f >= 7.2
    gem "sqlite3", ">= 2.1"
  elsif rails_version.to_f >= 7.1
    gem "sqlite3", ">= 1.7"
  else
    gem "sqlite3", "~> 1.4"
  end
else
  gem "rails"
  gem "sqlite3"
end
