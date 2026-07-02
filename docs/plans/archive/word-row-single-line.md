# 単語一覧の行表示を1行にする

## 目的・背景

Lessons タブ（レッスン詳細の Words セクション）と Words タブの単語一覧で、
見出し語と訳語が `VStack` で2行表示になっている。一覧の密度を上げるため
1行表示に変更し、横にはみ出す場合は末尾省略（`…`）で切り詰める。

## 対応方針

- `WordsView.swift` 内の共用コンポーネント `WordRow` を修正する
  - `VStack(alignment: .leading)` → `HStack` に変更し、見出し語と訳語を横並びにする
  - 両テキストに `.lineLimit(1)` を付け、末尾省略にする（`truncationMode` はデフォルトの `.tail`）
  - 見出し語に `.layoutPriority(1)` を付け、幅が足りない場合は訳語側から先に省略する
  - 訳語が空の間は表示しない挙動は維持する

## 影響範囲

- `ios/ESLLearningAssistant/Sources/Views/WordsView.swift`（`WordRow`）
- `WordRow` を利用している画面: Words タブ一覧、Lessons タブのレッスン詳細 Words セクション

## テスト方針

- `xcodebuild build` でコンパイル確認
- 既存ユニットテストはレイアウト非依存のため影響なし
