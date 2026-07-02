# Words詳細画面の下部に削除・再生成ボタンを追加

## 目的・背景

Words詳細画面（`WordDetailView`）の一番下に「AI情報の再生成」と「単語の削除」ボタンを追加する。
再生成は現状ツールバーの「…」メニュー内（生成完了時のみ）にあり見つけにくい。
削除は Words 一覧のスワイプ削除しかなく、詳細画面から直接消せない。

なお、直前に実装した Lesson画面 Words セクションの左スワイプ Remove は
ユーザー指示により取りやめ、こちらのボタン方式に置き換える（スワイプ実装は revert）。

## 対応方針

1. **Lesson画面のスワイプ削除を取り消す**
   - `LessonsView.swift` の `.swipeActions` と `removeWordFromLesson` を削除
   - `LessonWordRemoveUITests.swift` を削除し xcodegen 再生成
   - `DONE.md` の該当エントリと `docs/plans/archive/lesson-words-remove-button.md` を削除
2. **`WordDetailView`** (`Sources/Views/WordDetailView.swift`) の List 最下部にセクションを追加
   - 「Regenerate AI Info」ボタン: 生成完了時は既存の確認ダイアログを経由、
     それ以外（none/failed）は即生成。generating 中は disabled
   - 「Delete Word」ボタン（destructive）: 確認ダイアログ →
     `modelContext.delete(word)` + 明示 `save()` → `dismiss()` で一覧に戻る
     （Word の cascade で全レッスンの WordOccurrence も消える）
   - ツールバーの「…」メニュー（Regenerate のみ）はボタンに置き換えて削除

## 影響範囲

- `LessonsView.swift`（revert）、`WordDetailView.swift`、UIテスト。データモデル・backend への変更なし

## テスト方針

- `xcodebuild build` でコンパイル確認
- UIテスト（XCUITest）で: 単語作成 → 詳細画面下部の Delete Word → 確認 → 一覧から消え、
  レッスンの Words からも消えることを確認。Regenerate ボタンはタップで生成が走る
  （バックエンド未設定のため failed になる）ことを確認
