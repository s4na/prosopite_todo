# frozen_string_literal: true

require_relative "lib/prosopite_todo/version"

Gem::Specification.new do |spec|
  spec.name = "prosopite_todo"
  spec.version = ProsopiteTodo::VERSION
  spec.authors = ["s4na"]
  spec.email = ["appletea.umauma@gmail.com"]

  spec.summary = "A RuboCop-like todo file for Prosopite N+1 detection"
  spec.description = "Allows ignoring known N+1 queries via .prosopite_todo.yaml, similar to RuboCop's todo functionality"
  spec.homepage = "https://github.com/s4na/prosopite_todo"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "prosopite", ">= 1.0"
  spec.add_dependency "railties", ">= 6.0"

  spec.add_development_dependency "activerecord", ">= 6.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "sqlite3"
end
