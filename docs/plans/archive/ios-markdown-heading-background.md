# iOS: OCR・翻訳本文中のMarkdown見出しに背景色を付けて見やすくする

## 目的・背景

`PhotoDetailView.swift` はOCR結果・翻訳結果を `MarkdownUI` の `Markdown(_:)` で表示しているが、
デフォルトテーマ（`Theme.basic`）の見出し（`#`〜`######`）はフォントの太さ・サイズが変わるだけで
背景色や区切り線が無く、本文中で目立ちにくい（画面上部の「OCR結果（英語）」「翻訳」という
セクション見出し用の`Text(.headline)`と紛らわしい）。

調査の結果、`MarkdownUI` の `Theme`／`.markdownBlockStyle(_:body:)` モディファイアで
見出しごとのビューを`BlockConfiguration`から自由に組み立てられ、`.background(...)`で
背景色を付けられることを確認した（`Theme.gitHub`は背景色ではなく下線で区切っている実装例）。

## 対応方針

### Step 1: 見出し用のブロックスタイルを追加する

- `PhotoDetailView.swift` に、見出しレベル1〜3を対象に
  `.markdownBlockStyle(\.heading1) { configuration in ... }` 等で
  `configuration.label` に `.background(Color.accentColor.opacity(...), in: RoundedRectangle(...))` と
  `relativePadding` を付けるViewの拡張（`markdownHeadingHighlight()`）を定義する
- レベルごとにフォントサイズ（`FontSize`）は`Theme.basic`と同じ比率を踏襲しつつ、
  背景色の濃さ（opacity）をレベルに応じて変える

### Step 2: OCR結果・翻訳結果の `Markdown(_:)` に適用する

- 2箇所の `Markdown(photo.ocrText ?? "")` / `Markdown(photo.translatedText ?? "")` に
  `.markdownHeadingHighlight()` を適用する

## 影響範囲

- `ios/ESLLearningAssistant/Sources/Views/PhotoDetailView.swift`

## テスト方針

- `xcodebuild -scheme ESLLearningAssistant -destination 'generic/platform=iOS Simulator' build` でビルド確認
- 可能であればシミュレータで `#`/`##`/`###` を含むOCR結果を表示し、背景色付きで見出しが
  目立って表示されることを目視確認する
