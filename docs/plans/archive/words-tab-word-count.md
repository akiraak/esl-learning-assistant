# Words タブに登録単語数を表示

## 目的・背景

Words タブには登録済み単語の一覧が表示されるが、現在は総数がどこにも出ておらず、
学習の蓄積量（何語登録したか）をひと目で確認できない。登録単語数を一覧画面に表示する。

## 対応方針

- `WordsView` の単語一覧 `ForEach` を `Section` で包み、見出しに `Words (\(words.count))` を表示する
  - レッスン詳細の単語セクション見出し（`LessonsView` の `Words (N)`）と同じ表記・同じ `TappableEnglishText` パターンを使い、アプリ内の表現を揃える
  - 件数は検索絞り込みに関係なく**登録総数**（`words.count`）を出す
- 検索中（`searchText` 非空）は見出しを出さない
  - 絞り込み結果の件数と誤読されるのを避けるため。復習カードを検索中に隠すのと同じ理由
- 空状態（0語）は既存の `emptyState` が表示されるため件数表示は不要

## 影響範囲

- `ios/ESLLearningAssistant/Sources/Views/WordsView.swift` のみ（List 内のセクション構造）
- データモデル・サービス層への変更なし

## テスト方針

- UI テスト `WordsCountUITests` を新規追加
  - 正規化スタブ `canonical` で起動 → データ全削除 → Words タブへ
  - 単語を1語追加 → 見出し `Words (1)` が出る
  - もう1語追加 → `Words (2)` に更新される
  - 既存の `LessonWordAddUITests` と同じ `staticTexts["Words (N)"]` での検証パターン
- 追加ファイルは XcodeGen 管理のため `xcodegen generate` でプロジェクト再生成
