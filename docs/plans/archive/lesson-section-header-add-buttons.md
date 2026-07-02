# レッスン画面: Words / Content の追加ボタンをセクションヘッダー右端へ移動

## 目的・背景

レッスン画面では現在、写真追加が独立した「Add Photo」行、単語追加が Words セクション先頭の「Add Word」行として表示されており、リストの縦スペースを消費している。両方をセクションヘッダー（`Content (XXX)` / `Words (XXX)`）右端のシンプルな「+」ボタンに移動し、リストをすっきりさせる。

## 対応方針

- `ios/ESLLearningAssistant/Sources/Views/LessonsView.swift`
  - `lessonContent(_:)`: 先頭の「Add Photo」専用 Section を削除し、Content セクションを `Section { ... } header: { HStack { Text, Spacer, +ボタン } }` 形式に変更。+ボタンで `isShowingCapture = true`
  - `wordsSection(_:)`: セクション内の「Add Word」行を削除し、ヘッダー右端の+ボタンに変更。+ボタンで `router.showAddWord(for: lesson)`
  - アクセシビリティ識別子: 単語追加は既存の `lessonWordAddButton` を維持、写真追加は `lessonPhotoAddButton` を新設

## 影響範囲

- `LessonsView.swift` の Content / Words セクションのみ
- UI テスト: `ESLLearningAssistantUITests.swift` が `app.buttons["Add Photo"]` を参照しているため `lessonPhotoAddButton` 参照に更新

## テスト方針

- ビルドが通ることを確認（`xcodebuild build`）
- 既存 UI テストの参照を新識別子へ更新
