# OCR・翻訳結果のMarkdown化とadmin表示の整形

## 目的・背景

現状Claude APIから返る `ocrText`（原文の文字起こし）・`translatedText`（翻訳）はプレーンテキストで、
教科書ページの見出し・箇条書き・強調などのレイアウト情報が失われる。取り込み時点でMarkdown形式に
してレイアウトを保持し、admin画面（`backend/src/admin.ts`）ではそれをHTMLとして整形表示することで
通信ログが読みやすくなるようにする。

## 対応方針

### Step 1: Claude APIへの指示・出力スキーマをMarkdown対応にする

- `backend/src/ocrTranslate.ts` のプロンプト・`OUTPUT_SCHEMA`の`description`を、
  「見出しは#、箇条書きは-、強調は**太字**/*斜体*などMarkdown記法を使うこと」「翻訳文も
  原文と同じMarkdown構造を保つこと」を明示する内容に更新する。

### Step 2: adminのOCR結果・翻訳結果をMarkdownとしてHTMLレンダリングする

- `marked` パッケージを追加し、`backend/src/admin.ts` にMarkdown→HTML変換のヘルパーを実装する。
- Claude出力に生のHTMLタグが含まれていてもadmin画面上でスクリプト実行等が起きないよう、
  Markdownパース前に `&`, `<`, `>` をエスケープしてからmarkdownパースする
  （リンクの見出し等 `"` はほぼ使われない想定のため対象外とし、タグインジェクションのみ防ぐ）。
- テーブルセル内でmarkdown由来の見出し・箇条書き・段落が読みやすくなるよう、
  スコープしたCSS（フォントサイズ・余白・スクロール可能な最大高さ）を追加する。

### Step 3: iOS側でも生のMarkdown記号が見えないようにする（付随対応）

- `PhotoDetailView.swift` のOCR結果・翻訳結果表示を `AttributedString(markdown:)` 経由の
  `Text` に変更し、`#`や`**`などの記号がそのまま表示されないようにする
  （パース失敗時はプレーンテキストにフォールバック）。

## 影響範囲

- `backend/src/ocrTranslate.ts`
- `backend/src/admin.ts`
- `backend/package.json`（`marked` 追加）
- `ios/ESLLearningAssistant/Sources/Views/PhotoDetailView.swift`

## テスト方針

- `npm run build`（backend）でビルド確認。
- 実際にサーバーを起動し、`/api/ocr-translate` にサンプル画像を投げてMarkdown形式の
  `ocrText`/`translatedText` が返り、`/admin` で整形表示されることを確認する
  （HTMLタグを含む文字列を混ぜてエスケープが機能することも確認）。
- `xcodebuild -scheme ESLLearningAssistant -destination 'generic/platform=iOS Simulator' build` でiOS側のビルド確認。
