# TODO

## 作文

- [ ] 相談チャットに Web 検索（web_search / web_fetch）を入れる [plan](docs/plans/writing-chat-web-search.md)
  - [ ] Phase 1: `tools` 追加 + `pause_turn` ループ + テスト
  - [ ] Phase 2: 検索方針をシステムプロンプトに追加、出典表示の要否を決めて実装
  - [ ] Phase 3: 課金ログへ検索回数を反映

## 片付け

- [ ] iOS に残っている添削（Review）の残骸を消す
  - `ios/ESLLearningAssistant/Sources/Models/Composition.swift` の `WritingFeedback` /
    `CompositionRound` / `Composition.feedback` / `latestFeedback`。
    バックエンドの `/api/writing-feedback`・`writingFeedback.ts` は 2026-08-02 に削除済みで、
    iOS 側も参照している View / Service はもう無い（SwiftData のスキーマだけが残っている）。
    消すとマイグレーションが要るかを確認してから。
