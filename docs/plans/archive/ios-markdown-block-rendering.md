# iOS: OCR結果・翻訳結果のMarkdownをブロック単位で読みやすく表示する

## 目的・背景

`backend/src/ocrTranslate.ts` はOCR結果（`ocrText`）・翻訳結果（`translatedText`）を
見出し（`#`）・箇条書き（`-`）・強調（`**`/`*`）などのMarkdown形式で返す
（[markdown-ocr-translation.md](archive/markdown-ocr-translation.md) で対応済み）。

現状の `PhotoDetailView.swift` の `markdownText(_:)` は `AttributedString(markdown:)` を
`Text` にそのまま渡しているだけで、太字・斜体・リンクなどインライン装飾は反映されるものの、
見出しの文字サイズや箇条書きの「・」表示などブロックレベルの構造は失われ、
`#`が消えて地の文と同じ見た目になってしまい読みにくい。

`PresentationIntent`（ブロック構造情報）を見て、見出しはフォントサイズを変え、
箇条書きは行頭記号と字下げを付けて表示するようにする。

## 対応方針

### Step 1: ブロック単位でMarkdownを描画する再利用可能なView `MarkdownContentView` を追加する

- `ios/ESLLearningAssistant/Sources/Views/MarkdownContentView.swift` を新規作成
- `AttributedString(markdown:, options: .init(interpretedSyntax: .full))` でパースし、
  `run.presentationIntent` が変わるごとにブロック分割する
- ブロックごとに `PresentationIntent.components` を見て以下を描画する
  - `.header(level:)` → レベルに応じたフォントサイズ（h1〜h3+）
  - `.listItem(ordinal:)` → 祖先に `.orderedList`/`.unorderedList` があるかで
    番号付き/中黒（•）を出し分け、リストのネスト数だけ字下げ
  - `.blockQuote` → secondaryカラー＋イタリック
  - それ以外（`.paragraph`など）→ 通常表示
- パース失敗時はプレーンテキストへフォールバックする

### Step 2: `PhotoDetailView.swift` を新Viewに差し替える

- OCR結果・翻訳結果の `markdownText(photo.ocrText)` / `markdownText(photo.translatedText)` を
  `MarkdownContentView(markdown:)` に置き換える
- 未使用になる `markdownText(_:)` を削除する（TTS用の `plainText(_:)` は維持）

## 影響範囲

- `ios/ESLLearningAssistant/Sources/Views/MarkdownContentView.swift`（新規）
- `ios/ESLLearningAssistant/Sources/Views/PhotoDetailView.swift`

## テスト方針

- `xcodebuild -scheme ESLLearningAssistant -destination 'generic/platform=iOS Simulator' build` でビルド確認
- 可能であればシミュレータで見出し・箇条書きを含むOCR結果を表示し、目視で確認する
