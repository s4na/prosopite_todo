# ProsopiteTodo

[English](./README.md)

> **注意**: この gem は実験的なものです。動作確認がまだ十分に取れていません。十分な動作確認が取れた後、RubyGems に公開する予定です。

[Prosopite](https://github.com/charkost/prosopite) N+1検出のための RuboCop ライクな TODO ファイル機能を提供する gem です。`.prosopite_todo.yaml` を使って既知の N+1 クエリを無視できます。

## ユースケース

この gem は、Prosopite の N+1 検出を**大規模なコードベース**に段階的に導入するために設計されています。すべての N+1 クエリを一度に修正する代わりに、以下のことができます：

1. 既存の N+1 クエリを TODO ファイルに記録する
2. 新機能の開発中は既知の N+1 クエリを無視する
3. 時間をかけて徐々に N+1 クエリを修正する
4. 新しい N+1 クエリが導入されないようにする

## インストール

Gemfile に以下を追加してください：

```ruby
gem 'prosopite_todo', github: 's4na/prosopite_todo'
```

その後、以下を実行します：

```bash
bundle install
```

### バージョンの指定

GitHub からインストールする場合、gem のバージョンはリポジトリ内の `lib/prosopite_todo/version.rb` によって決まります。特定のバージョンに固定するには、git タグ、ブランチ、またはコミット SHA を使用できます：

```ruby
# 特定のタグに固定（推奨）
gem 'prosopite_todo', github: 's4na/prosopite_todo', tag: 'v0.1.0'

# 特定のブランチに固定
gem 'prosopite_todo', github: 's4na/prosopite_todo', branch: 'main'

# 特定のコミットに固定
gem 'prosopite_todo', github: 's4na/prosopite_todo', ref: 'abc1234'
```

バージョンタグは PR が main にマージされると自動的に作成されます。

## 使い方

### TODO ファイルの生成

Prosopite が N+1 クエリを検出した際、すぐに修正する代わりに TODO ファイルに記録できます：

```bash
bundle exec rake prosopite_todo:generate
```

これにより、プロジェクトルートに現在検出されているすべての N+1 を含む `.prosopite_todo.yaml` ファイルが作成されます。

### TODO ファイルの更新

既存のエントリを削除せずに新しい N+1 検出を追加するには：

```bash
bundle exec rake prosopite_todo:update
```

### TODO エントリの一覧表示

TODO ファイル内のすべての N+1 クエリを確認するには：

```bash
bundle exec rake prosopite_todo:list
```

### TODO ファイルのクリーンアップ

検出されなくなったエントリ（N+1 が修正された）を削除するには：

```bash
bundle exec rake prosopite_todo:clean
```

### RSpec 統合 - 単一テストから N+1 を追加

単一のテストを実行して、検出された N+1 クエリを TODO ファイルに追加したい場合、RSpec 統合ヘルパーを使用できます。

**セットアップ:**

`spec/rails_helper.rb`（または `spec/spec_helper.rb`）に以下を追加してください：

```ruby
require 'prosopite_todo/rspec'
```

**重要:** `prosopite_todo/rspec` ヘルパーは、テストスイート完了後に検出された N+1 クエリを TODO ファイルに保存するだけです。実際に N+1 クエリを検出するには、`Prosopite.scan` も有効にする必要があります。以下の2つの方法があります：

**方法1: TODO 更新時にすべてのテストでスキャンを有効にする（推奨）**

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

**方法2: 特定のテストでスキャンを有効にする**

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

その後、個々のテストに `prosopite_scan: true` タグを追加します：

```ruby
it "loads user posts", prosopite_scan: true do
  # テストコード
end
```

**使い方:**

`PROSOPITE_TODO_UPDATE` 環境変数を指定してテストを実行します：

```bash
# 単一のテストファイルを実行
PROSOPITE_TODO_UPDATE=1 bundle exec rspec spec/models/user_spec.rb

# 特定の行のテストを実行
PROSOPITE_TODO_UPDATE=1 bundle exec rspec spec/models/user_spec.rb:42

# パターンに一致するテストを実行
PROSOPITE_TODO_UPDATE=1 bundle exec rspec spec/models/ --pattern "*_spec.rb"
```

これにより：
1. 指定されたテストが実行されます
2. Prosopite 経由で N+1 クエリが自動的に検出されます
3. テストスイート完了後、新しい N+1 検出が `.prosopite_todo.yaml` に追加されます

**注意:** 複数のテストを実行する場合、すべてのテストからの通知が蓄積されてから TODO ファイルに保存されます。つまり、テストをバッチ実行すると、検出されたすべての N+1 クエリがまとめて記録されます。保存後、重複を防ぐために保留中の通知は自動的にクリアされます。

これは、他のテストに影響を与えずに、発見した既知の N+1 クエリを TODO ファイルに段階的に追加する際に便利です。

## 仕組み

1. **フィンガープリント**: 各 N+1 クエリは SQL クエリとコールスタックの位置に基づくフィンガープリントで識別されます
2. **フィルタリング**: Prosopite が N+1 クエリを検出すると、ProsopiteTodo は `.prosopite_todo.yaml` 内のエントリに一致するものを除外します
3. **永続化**: TODO ファイルは人間が読める YAML ファイルで、バージョン管理にコミットできます

### `.prosopite_todo.yaml` の例

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

## 設定

ProsopiteTodo は、スタックトレースのフィルタリング方法と location フィールドでの表示方法をカスタマイズするオプションを提供します。

### ロケーションフィルタリング

デフォルトでは、ProsopiteTodo は `Rails.backtrace_cleaner` を使用してスタックトレースをフィルタリングし、出力を5フレームに制限します。これにより `.prosopite_todo.yaml` ファイルが読みやすくなり、ファイルサイズも削減されます。

```ruby
# config/initializers/prosopite_todo.rb
ProsopiteTodo.configure do |config|
  # 含めるスタックフレームの最大数（デフォルト: 5）
  # nil に設定するとフィルタリング後のすべてのフレームを含めます
  config.max_location_frames = 5

  # スタックフレームのカスタムフィルター（デフォルト: nil、Rails.backtrace_cleaner を使用）
  # 例: app/ パスのみを含める
  config.location_filter = ->(frames) { frames.select { |f| f.include?('/app/') } }
end
```

### 設定オプション

| オプション | デフォルト | 説明 |
|-----------|-----------|------|
| `max_location_frames` | `5` | location に含めるスタックフレームの最大数。`nil` で無制限。 |
| `location_filter` | `nil` | フレームフィルタリング用のカスタム callable。`Rails.backtrace_cleaner` より優先されます。 |

### 例

**アプリケーションコードのみを含める:**
```ruby
ProsopiteTodo.configure do |config|
  config.location_filter = ->(frames) { frames.select { |f| f.include?('/app/') } }
  config.max_location_frames = 3
end
```

**フィルタリングを無効化（完全なスタックトレースを含める）:**
```ruby
ProsopiteTodo.configure do |config|
  config.location_filter = ->(frames) { frames }
  config.max_location_frames = nil
end
```

## Prosopite との統合

ProsopiteTodo は Rails Railtie を通じて Prosopite と自動的に統合されます。Rails アプリケーションが起動すると、TODO ファイルに基づいて N+1 通知をフィルタリングするコールバックが設定されます。

### 手動での統合

手動で統合する必要がある場合：

```ruby
require 'prosopite_todo'

# 通知をフィルタリング
todo_file = ProsopiteTodo::TodoFile.new
filtered = ProsopiteTodo::Scanner.filter_notifications(prosopite_notifications, todo_file)

# 新しい通知を記録
ProsopiteTodo::Scanner.record_notifications(notifications, todo_file)
todo_file.save
```

## 対応バージョン

- Ruby 2.7 以上
- Rails 6.0 以上

## 開発

リポジトリをチェックアウト後、以下を実行してください：

```bash
bundle install
bundle exec rspec
```

## リリース

リリースは GitHub Actions で自動化されています。PR が main にマージされると：

1. `lib/prosopite_todo/version.rb` のパッチバージョンが自動的にインクリメントされます
2. 新しいバージョンタグ（例: `v0.1.1`）が作成されプッシュされます
3. 自動生成されたリリースノート付きの GitHub Release が作成されます

メジャーまたはマイナーバージョンのアップデートの場合は、マージ前に `lib/prosopite_todo/version.rb` を手動で更新してください。

## ライセンス

この gem は MIT ライセンスの下でオープンソースとして提供されています。
