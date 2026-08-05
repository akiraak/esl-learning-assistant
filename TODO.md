# TODO

## 片付け

- [ ] iOS に残っている添削（Review）の残骸を消す
  - `ios/ESLLearningAssistant/Sources/Models/Composition.swift` の `WritingFeedback` /
    `CompositionRound` / `Composition.feedback` / `latestFeedback`。
    バックエンドの `/api/writing-feedback`・`writingFeedback.ts` は 2026-08-02 に削除済みで、
    iOS 側も参照している View / Service はもう無い（SwiftData のスキーマだけが残っている）。
    消すとマイグレーションが要るかを確認してから。
