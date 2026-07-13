# 管理画面: Photo英文・全種別の翻訳にも印刷用表示を追加

## 目的・背景

音声文字起こしの英文には印刷用表示（/admin/transcriptions/:id/text）を追加済み。
同様に以下も紙に印刷して読めるようにする。

- Photo（写真OCR）の英文
- Photo / Audio / Document の翻訳文
- （対称性のため）Document の英文も同様に追加する

いずれも結果本体は各ログテーブル（requests / transcription_requests /
document_requests）に保存済みのため、backend 管理画面の表示のみで完結する。

## 対応方針

1. **印刷ページ描画の共通化**: `transcriptPrint.ts` を `printView.ts` にリネームし、
   印刷用ページ全体の HTML を組む純関数 `renderPrintPageHtml({lang, title, meta, bodyHtml})`
   を追加（既存の /admin/transcriptions/:id/text のテンプレートを抽出・共通化）
   - 本文が Markdown 由来（Photo / Document）の場合に備え、印刷CSSに
     見出し・箇条書き・強調などの控えめなスタイルを追加
   - 翻訳ページ用に serif スタック（Georgia + ヒラギノ明朝系）と `lang` 属性を可変に
2. **ルート追加**（本文の組み立てはソースの形式に合わせる）
   - `GET /admin/logs/:id/text` … Photo OCR英文（renderMarkdown）
   - `GET /admin/logs/:id/translation` … Photo 訳（renderMarkdown）
   - `GET /admin/transcriptions/:id/translation` … Audio 訳（transcriptParagraphsHtml）
   - `GET /admin/documents/:id/text` … Document 英文（renderMarkdown）
   - `GET /admin/documents/:id/translation` … Document 訳（renderMarkdown）
   - 見出しは title（無い種別・行は `Photo OCR #id` / `Transcription #id` /
     `Document #id`）。翻訳ページは meta 行に「訳 (ja)」を付記
3. **導線**
   - Photo: 一覧に本文列が無いため詳細ページ（/admin/logs/:id）の
     「OCR結果」「翻訳結果」見出し脇に「印刷用表示」リンク
   - Audio: 一覧の訳セルにもリンク追加（英文セルは追加済み）
   - Document: 一覧の英文・訳セルにリンク追加

## 影響範囲

- backend のみ: `src/admin.ts`、`src/transcriptPrint.ts` → `src/printView.ts`
  （リネーム＋関数追加）、`test/transcriptPrint.test.ts` → `test/printView.test.ts`
- iOS・API・DB 変更なし

## テスト方針

- 単体テスト: `renderPrintPageHtml`（title/meta のエスケープ、lang 属性、本文挿入）
  ＋既存 `transcriptParagraphsHtml` テストの移設
- E2E: 実データ（Photo・Document・Audio 各ログ）で5ルートの表示・404・
  一覧/詳細のリンクを curl で確認、Markdown 本文（Document 訳）を
  print-to-pdf で印刷レンダリング確認
