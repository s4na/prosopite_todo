# ProsopiteTodo

A RuboCop-like TODO file for [Prosopite](https://github.com/charkost/prosopite) N+1 detection. This gem allows you to ignore known N+1 queries via `.prosopite_todo.yaml`, similar to RuboCop's TODO functionality.

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
# Pin to a specific tag
gem 'prosopite_todo', github: 's4na/prosopite_todo', tag: 'v0.1.0'

# Pin to a specific branch
gem 'prosopite_todo', github: 's4na/prosopite_todo', branch: 'main'

# Pin to a specific commit
gem 'prosopite_todo', github: 's4na/prosopite_todo', ref: 'abc1234'
```

**Note:** This gem is not yet published to RubyGems. Once published, you will be able to install it with:

```ruby
gem 'prosopite_todo', '~> 0.1'
```

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

To release a new version:

1. Update the version number in `lib/prosopite_todo/version.rb`
2. Commit the version change: `git commit -am "Bump version to x.x.x"`
3. Create and push a tag: `git tag vx.x.x && git push origin vx.x.x`

The GitHub Actions workflow will automatically:
- Verify the tag version matches the gem version
- Run the test suite
- Build and publish the gem to RubyGems
- Create a GitHub Release with release notes

**Note:** You need to set the `RUBYGEMS_API_KEY` secret in your GitHub repository settings.

## License

The gem is available as open source under the terms of the MIT License.
