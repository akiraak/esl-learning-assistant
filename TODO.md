# TODO


- [ ] 英文の単語をタップすると単語一覧に追加できるようにする [plan](docs/plans/ocr-tap-word-add.md)
  - [ ] Phase 1: 登録ロジックを `WordRegistrar` へ抽出し `WordAddView` をリファクタ（挙動不変）
  - [ ] Phase 2: 単語トークナイザ + `TappableOCRTextView` を実装し `PhotoDetailView` にモードトグル/`modelContext` を追加（`sourcePhoto`・`lesson` 紐付け）
  - [ ] Phase 3: 仕上げ（タップフィードバック、登録済みハイライト、トークン化エッジケース）とテスト整備
- [ ] 単語に複数品詞があった場合にアプリの単語一覧の表示にも表示する
- [ ] アプリアイコンの改善
  - 背景色をもっと薄い緑（パステルより）にする
  - 情報量を減らしてシンプルにする