# よく使うプロンプト

```
以下の手順でテストを実施してください。
1. tmp/ ディレクトリで rails new demo_app を実行し、新規Railsプロジェクトを作成
2. Gemfileに prosopite と prosopite_todo（path: '../'）を追加し、Prosopiteの初期設定を行う
3. N+1問題を含むサンプルコードを複数パターン実装
4. 各パターンに対応するテストケースをRSpecで作成
5. rails_helper.rb に require 'prosopite_todo/rspec' を追加
6. bundle exec rspec を実行し、N+1問題が検出されることを確認
7. PROSOPITE_TODO_UPDATE=1 bundle exec rspec を実行し、.prosopite_todo.yaml が生成されることを確認
8. 出力内容が想定通りであることを確認（YAML形式、fingerprint / query / location / created_at の存在）
9. 再度 bundle exec rspec を実行し、登録済みのN+1問題が検出されなくなることを確認
10. 確認が終了したら、demo_app を削除

問題があれば、https://github.com/s4na/prosopite_todo/issuesにイシューを作成してください。
```
