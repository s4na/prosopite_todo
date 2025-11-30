# ProsopiteTodo

[Prosopite](https://github.com/charkost/prosopite) N+1検出のための RuboCop ライクな TODO ファイル機能を提供する gem です。`.prosopite_todo.yaml` を使って既知の N+1 クエリを無視できます。

## インストール

Gemfile に以下を追加してください：

```ruby
gem 'prosopite_todo'
```

その後、以下を実行します：

```bash
bundle install
```

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

## ライセンス

この gem は MIT ライセンスの下でオープンソースとして提供されています。
