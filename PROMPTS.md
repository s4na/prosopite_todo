# よく使うプロンプト

```
以下の手順でテストを実施してください。
## 事前準備
1. `tmp/` ディレクトリで `rails new demo_app` を実行し、新規Railsプロジェクトを作成
2. Gemfileに `prosopite` と `prosopite_todo`（path: '../'）、RSpec関連gemを追加し、Prosopiteの初期設定を行う
3. Post、Commentモデルを作成（Commentは自己参照で `replies` を持つ構造）
   - Post has_many :comments
   - Comment belongs_to :post, has_many :replies（親コメントへの返信）

## N+1検出テスト
4. N+1問題を含むサンプルコードを実装（posts→comments、comments→replies、comments→post の3パターン）
5. 各パターンに対応するテストケースをRSpecで作成
6. `rails_helper.rb` に `require 'prosopite_todo/rspec'` を追加
7. `bundle exec rspec` を実行し、N+1問題が検出されることを確認

## prosopite_todo.yaml 生成テスト
8. `PROSOPITE_TODO_UPDATE=1 bundle exec rspec` を実行し、`.prosopite_todo.yaml` が生成されることを確認
9. 出力内容が想定通りであることを確認（YAML形式、fingerprint / query / location / created_at の存在）
10. 再度 `bundle exec rspec` を実行し、登録済みのN+1問題が検出されなくなることを確認

## prosopite_todo.yaml クリーンアップテスト
11. N+1問題を修正（`includes` を追加）
12. `PROSOPITE_TODO_UPDATE=1 bundle exec rspec` を実行し、`.prosopite_todo.yaml` から修正済みのエントリが削除されることを確認

## 後片付け
13. 確認が終了したら、`demo_app` を削除

問題があれば、https://github.com/s4na/prosopite_todo/issues にイシューを作成してください。
```
