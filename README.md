# ProsopiteTodo

[日本語版 (Japanese)](./README.ja.md)

> **Note**: This gem is experimental. Testing is not yet complete. Once sufficient testing has been done, we plan to publish it to RubyGems.

A RuboCop-like TODO file for [Prosopite](https://github.com/charkost/prosopite) N+1 detection. This gem allows you to ignore known N+1 queries via `.prosopite_todo.yaml`, similar to RuboCop's TODO functionality.

## Use Case

This gem is designed for **large codebases** where you want to incrementally adopt Prosopite N+1 detection. Instead of fixing all N+1 queries at once, you can:

1. Record existing N+1 queries to a TODO file
2. Ignore known N+1 queries while developing new features
3. Gradually fix N+1 queries over time
4. Ensure no new N+1 queries are introduced

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'prosopite_todo', github: 's4na/prosopite_todo'
```

And then execute:

```bash
bundle install
```

### Specifying a version

When installing from GitHub, the gem version is determined by `lib/prosopite_todo/version.rb` in the repository. To pin to a specific version, you can use git tags, branches, or commit SHAs:

```ruby
# Pin to a specific tag (recommended)
gem 'prosopite_todo', github: 's4na/prosopite_todo', tag: 'v0.1.0'

# Pin to a specific branch
gem 'prosopite_todo', github: 's4na/prosopite_todo', branch: 'main'

# Pin to a specific commit
gem 'prosopite_todo', github: 's4na/prosopite_todo', ref: 'abc1234'
```

Version tags are automatically created when PRs are merged to main.

## Usage

### Generating a TODO file

When Prosopite detects N+1 queries, you can record them to a TODO file instead of fixing them immediately:

```bash
bundle exec rake prosopite_todo:generate
```

This creates a `.prosopite_todo.yaml` file in your project root with all current N+1 detections.

### Updating the TODO file

To add new N+1 detections without removing existing ones:

```bash
bundle exec rake prosopite_todo:update
```

### Listing TODO entries

To see all N+1 queries in your TODO file:

```bash
bundle exec rake prosopite_todo:list
```

### Cleaning the TODO file

To remove entries that are no longer detected (i.e., the N+1 has been fixed):

```bash
bundle exec rake prosopite_todo:clean
```

### RSpec Integration - Adding N+1 from a single test

When you want to run a single test and add its detected N+1 queries to the TODO file, you can use the RSpec integration helper.

**Setup:**

Add to your `spec/rails_helper.rb` (or `spec/spec_helper.rb`):

```ruby
require 'prosopite_todo/rspec'
```

**Important:** The `prosopite_todo/rspec` helper only saves detected N+1 queries to the TODO file after the test suite completes. You must also enable `Prosopite.scan` to actually detect N+1 queries. Here are two approaches:

**Option 1: Enable scanning for all tests when updating TODO (recommended)**

```ruby
# spec/rails_helper.rb
require 'prosopite_todo/rspec'

RSpec.configure do |config|
  config.around(:example) do |example|
    if ENV['PROSOPITE_TODO_UPDATE']
      original_raise = Prosopite.raise?
      Prosopite.raise = false
      Prosopite.scan do
        example.run
      end
      Prosopite.raise = original_raise
    else
      example.run
    end
  end
end
```

**Option 2: Enable scanning for specific tests**

```ruby
# spec/rails_helper.rb
require 'prosopite_todo/rspec'

RSpec.configure do |config|
  config.around(:example, prosopite_scan: true) do |example|
    Prosopite.scan do
      example.run
    end
  end
end
```

Then add the `prosopite_scan: true` tag to individual tests:

```ruby
it "loads user posts", prosopite_scan: true do
  # your test code
end
```

**Usage:**

Run your test with the `PROSOPITE_TODO_UPDATE` environment variable:

```bash
# Run a single test file
PROSOPITE_TODO_UPDATE=1 bundle exec rspec spec/models/user_spec.rb

# Run a specific test line
PROSOPITE_TODO_UPDATE=1 bundle exec rspec spec/models/user_spec.rb:42

# Run tests matching a pattern
PROSOPITE_TODO_UPDATE=1 bundle exec rspec spec/models/ --pattern "*_spec.rb"
```

This will:
1. Run the specified test(s)
2. Automatically detect N+1 queries via Prosopite
3. Add any new N+1 detections to `.prosopite_todo.yaml` after the test suite completes

**Note:** When running multiple tests, notifications are accumulated from ALL tests before being saved to the TODO file. This means you can run a batch of tests and all detected N+1 queries will be recorded together. After saving, the pending notifications are automatically cleared to prevent accidental duplicates.

This is useful for incrementally adding known N+1 queries to your TODO file as you discover them, without affecting other tests.

## How it works

1. **Fingerprinting**: Each N+1 query is identified by a fingerprint based on the SQL query and its call stack location
2. **Filtering**: When Prosopite detects N+1 queries, ProsopiteTodo filters out any that match entries in `.prosopite_todo.yaml`
3. **Persistence**: The TODO file is a human-readable YAML file that can be committed to version control

### Example `.prosopite_todo.yaml`

```yaml
---
- fingerprint: "a1b2c3d4e5f67890"
  query: SELECT "users".* FROM "users" WHERE "users"."id" = $1
  location: app/models/post.rb:10 -> app/controllers/posts_controller.rb:5
  created_at: "2024-01-15T10:30:00Z"
- fingerprint: "0987654321fedcba"
  query: SELECT "comments".* FROM "comments" WHERE "comments"."post_id" = $1
  location: app/models/comment.rb:20 -> app/views/posts/show.html.erb:15
  created_at: "2024-01-15T10:30:00Z"
```

## Configuration

ProsopiteTodo provides options to customize how stack traces are filtered and displayed in the location field.

### Location Filtering

By default, ProsopiteTodo uses `Rails.backtrace_cleaner` to filter stack traces and limits the output to 5 frames. This makes the `.prosopite_todo.yaml` file more readable and reduces file size.

```ruby
# config/initializers/prosopite_todo.rb
ProsopiteTodo.configure do |config|
  # Maximum number of stack frames to include (default: 5)
  # Set to nil to include all frames after filtering
  config.max_location_frames = 5

  # Custom filter for stack frames (default: nil, uses Rails.backtrace_cleaner)
  # Example: Only include app/ paths
  config.location_filter = ->(frames) { frames.select { |f| f.include?('/app/') } }
end
```

### Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `max_location_frames` | `5` | Maximum number of stack frames to include in location. Set to `nil` for unlimited. |
| `location_filter` | `nil` | Custom callable for filtering frames. Takes precedence over `Rails.backtrace_cleaner`. |

### Examples

**Include only application code:**
```ruby
ProsopiteTodo.configure do |config|
  config.location_filter = ->(frames) { frames.select { |f| f.include?('/app/') } }
  config.max_location_frames = 3
end
```

**Disable filtering (include full stack trace):**
```ruby
ProsopiteTodo.configure do |config|
  config.location_filter = ->(frames) { frames }
  config.max_location_frames = nil
end
```

## Integration with Prosopite

ProsopiteTodo automatically integrates with Prosopite through a Rails Railtie. When your Rails application starts, it sets up a callback that filters N+1 notifications based on your TODO file.

### Manual integration

If you need to integrate manually:

```ruby
require 'prosopite_todo'

# Filter notifications
todo_file = ProsopiteTodo::TodoFile.new
filtered = ProsopiteTodo::Scanner.filter_notifications(prosopite_notifications, todo_file)

# Record new notifications
ProsopiteTodo::Scanner.record_notifications(notifications, todo_file)
todo_file.save
```

## Development

After checking out the repo, run:

```bash
bundle install
bundle exec rspec
```

To run the integration tests:

```bash
ruby spec/integration/n_plus_one_spec.rb
```

## Releasing

Releases are automated via GitHub Actions. When a PR is merged to main:

1. The patch version is automatically incremented in `lib/prosopite_todo/version.rb`
2. A new version tag (e.g., `v0.1.1`) is created and pushed
3. A GitHub Release is created with auto-generated release notes

For major or minor version bumps, manually update `lib/prosopite_todo/version.rb` before merging.

## License

The gem is available as open source under the terms of the MIT License.
