# Lesson画面Wordsの行頭削除ボタンをやめ、左スワイプ削除に戻す

## 目的・背景

Lesson画面（Lessonsタブ）の Words 各行の左端に常時表示している赤い「−」削除ボタンをやめ、
左スワイプで Remove を出す方式に変更する（最初に実装したスワイプ方式への回帰）。
削除の意味は変わらず「そのレッスンとのリンク（`WordOccurrence`）を外すのみ」で、
Wordsタブの単語一覧からは消えない。

Wordsタブ（スワイプ削除なし・詳細画面の Delete Word に集約）はそのまま。

## 対応方針

1. **`LessonsView`** (`Sources/Views/LessonsView.swift`) の `wordsSection`
   - 行を元の「詳細遷移ボタンのみ」に戻し、`.swipeActions(edge: .trailing)` に
     destructive の「Remove」（`minus.circle`）を追加する
   - `removeWordFromLesson(_:in:)`（明示 `modelContext.save()` 付き）はそのまま使う
2. UIテストを `LessonWordRemoveUITests`（スワイプ操作版）に置き換える
   - リンク解除・Wordsタブ残存・再起動後の永続化・再リンク・
     Wordsタブで左パンしても Delete が出ないことを確認

## 影響範囲

- `LessonsView.swift` とUIテストのみ。データモデル・backend への変更なし

## テスト方針

- UIテスト（XCUITest）で上記フローを実機同等のシミュレータで確認
