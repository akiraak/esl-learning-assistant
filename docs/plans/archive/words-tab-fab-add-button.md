# Wordsタブ: 右上「・・・」を削除し、追加ボタンをフローティング化

## 目的・背景

- Wordsタブの右上には「+」(Add Word) と「・・・」(secondaryAction の Generate Missing AI Info) が並んでおり、
  「・・・」の存在が分かりにくくノイズになっている
- TODO: 「Wordsタブの右上・・・を削除。追加ボタンは他にわかりやすい場所や表示のアイデアを出して」
- ユーザー確認済みの方針:
  - 追加ボタンは **右下フローティング「+」ボタン (FAB)** にする
  - Generate Missing AI Info（一括生成）は **完全に削除** する
    - 単語追加時に個別生成されるため通常は不要。必要になれば別の形で復活させる

## 対応方針

`ios/ESLLearningAssistant/Sources/Views/WordsView.swift` のみ変更する。

1. `.toolbar { ... }` を丸ごと削除（primaryAction の「+」と secondaryAction の一括生成ボタン）
   - これで右上の「・・・」が消える
2. 一括生成関連のコードを削除
   - `@State` の `isBulkGenerating` / `bulkDone` / `bulkTotal`
   - `pendingAIWords` / `generateAllPending()`
   - `safeAreaInset(edge: .bottom)` の進捗表示
3. 右下フローティング「+」ボタンを追加
   - `overlay(alignment: .bottomTrailing)` で円形の「+」ボタンを重ねる
   - `accessibilityIdentifier("wordAddButton")` を維持（UIテスト5箇所が参照）
   - 空状態（emptyState）のときは中央の Add Word ボタンがあるため、FABは一覧表示時のみで良いが、
     実装簡素化のため常時表示でも害はない → リストがあるときのみ表示にする

## 影響範囲

- `WordsView.swift` のみ
- UIテスト: `wordAddButton` 識別子を維持するため既存テストはそのまま通る想定
  （`wordBulkGenerateButton` はテスト未参照のため削除して問題なし）

## テスト方針

- `xcodebuild build` でビルド確認
- 既存UIテストのうち `wordAddButton` を使うもの（LessonWordAddUITests / ESLLearningAssistantUITests）を実行して回帰確認
