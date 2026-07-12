# Audio 文字起こしの段落整形（見やすさ改善）

## 目的・背景

Content タブ > Audio の英文文字起こしが段落分けされず、一塊のベタ表示になることがある。

原因は2段構え:

1. backend の文字起こしプロンプト（`backend/src/transcribe.ts` の `TRANSCRIBE_PROMPT`）は
   "plain text, with … paragraph breaks" と依頼するのみで、出力の改行を保証する後処理が無い。
2. iOS の表示コンポーネント `TappableMarkdown` → `MarkdownLite.blocks()`
   （`ios/.../Support/MarkdownLite.swift`）は **空行（`\n\n`）だけ**を段落境界と見なし、
   単一改行はスペース連結で1段落に潰す。

つまり Gemini が空行を入れてくれない限り（単一改行のみ・改行ゼロの場合）画面上は1段落になる。

## 対応方針

backend のみ変更。翻訳（`translateText` は Markdown 構造を保って翻訳する）より前に整形するため、
英文と訳の段落構造が自動的に揃う。iOS 側は変更不要。

1. **プロンプト強化**: 段落を「空行区切り・2〜4文ごと・話題や話者の切れ目で改める」と明示指示する。
2. **決定的な後処理 `formatTranscriptParagraphs()`**（`transcribe.ts` に追加、`transcribeAudio` の戻り値に適用）:
   - CRLF → LF 正規化、trim
   - 改行（1個以上連続）を段落境界と見なし、各段落を trim して空行（`\n\n`）区切りで再結合
     （単一改行しか無い出力・3連以上の改行も正しい段落表示に正規化される）
   - 文が多すぎる段落（6文以上）は約3文ごとのチャンクに再分割
     （改行ゼロの「壁テキスト」出力へのフォールバックを兼ねる）
   - 文分割は `.!?` + 空白 + 大文字開始のヒューリスティック。Mr./Dr. 等の敬称略語は境界と見なさない

既存データについて: サーバ `transcription_requests` は 0 行、実本文は iOS 端末の
`AudioClip.transcriptText` にのみ保存される。既存クリップは詳細画面の Transcribe 再実行で
新フォーマットになるため、マイグレーションは行わない。

## 影響範囲

- `backend/src/transcribe.ts`: プロンプト文言 + 整形関数追加 + 戻り値への適用
- `/api/transcribe-translate` の応答（英文・訳とも段落が空行区切りになる）
- iOS 表示は既存の `MarkdownLite` がそのまま空行を段落として描画（コード変更なし）
- 写真 OCR・文書抽出のパスには触れない

## テスト方針

- 単体テスト `backend/test/transcribeFormat.test.ts`（node:test、既存テストと同型）:
  - 空行区切り出力 → そのまま維持
  - 単一改行のみの出力 → 空行区切りへ変換
  - 3連以上の改行・CRLF → 正規化
  - 改行ゼロの長文 → 約3文ごとに段落化
  - 短文（数文以内） → 1段落のまま
  - 敬称略語（Mr. 等）で文分割しない
- E2E: `say` で生成した英語音声（aiff）を `/api/transcribe-translate` に POST し、
  応答の `englishText` / `translatedText` が空行区切りの段落になることを確認

## 見送った代替案

- iOS 側で表示時に整形: 訳側（MarkdownUI 描画）にも同じ処理が必要になり二重実装になる。
  保存済みテキスト自体は直らない。backend 整形なら保存されるデータ自体が読みやすくなる
- `MarkdownLite` で単一改行を段落扱い: 写真 OCR / 文書抽出の表示（Markdown の
  行連結セマンティクスに依存）に影響するため不採用
