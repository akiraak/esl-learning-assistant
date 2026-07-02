# Wordsタブのスワイプ削除を廃止し、Lesson画面Words各行に削除ボタンを追加

## 目的・背景

1. Wordsタブの単語一覧の左スワイプ delete（単語本体の削除）を廃止する。
   単語本体の削除は Words 詳細画面下部の「Delete Word」ボタン（確認ダイアログ付き）に集約する。
2. Lesson画面（Lessonsタブ）の Words セクションの各行に削除ボタンを常時表示する。
   押すとそのレッスンとのリンク（`WordOccurrence`）だけが消え、
   Wordsタブの単語一覧からは削除されない。

## 対応方針

1. **`WordsView`** (`Sources/Views/WordsView.swift`)
   - `.onDelete(perform: deleteWords)` と `deleteWords(at:)` を削除
2. **`LessonsView`** (`Sources/Views/LessonsView.swift`) の `wordsSection`
   - 各行を「削除ボタン（leading・赤の minus.circle.fill、`.borderless`）＋
     詳細遷移ボタン（既存、`.plain`）」の HStack に再構成する
     （iOS 編集モードの削除と同じ左端配置。ボタンスタイルを分けて当たり判定を独立させる）
   - `removeWordFromLesson(_:in:)` を追加: そのレッスン内の該当 Word の
     `WordOccurrence` をすべて `modelContext.delete` し、明示的に `modelContext.save()`
   - 識別子 `lessonWordRemoveButton` を付与

## 影響範囲

- 上記2ファイルとUIテスト。データモデル・backend への変更なし
- Word 本体の削除経路は Words 詳細画面の Delete Word のみになる

## テスト方針

- `xcodebuild build` でコンパイル確認
- UIテスト（XCUITest）で: 単語作成 → Lesson画面の行の削除ボタン → `Words (0)` になり
  Wordsタブには単語が残る。Wordsタブで行を左スワイプしても Delete が出ない。
  再起動後もリンク解除が維持される（明示 save）

## 補足（履歴）

- 2026-07-02: 一度「スワイプ削除復活・行頭ボタン取りやめ」（restore-words-swipe-delete）で
  revert されたが、ユーザーの指示ミスだったため同日中に本実装へ再度戻した。
