# 管理画面: 音声文字起こし英文の印刷用表示

## 目的・背景

音声読み上げ（/api/transcribe-translate）の文字起こし英文は、管理画面の
「音声文字起こしログ」一覧で 120 字のプレビュー表示しかできない
（全文は `title` 属性のツールチップ頼み）。英文を紙に印刷して読む用途があるため、
読みやすい組版で全文を表示できる印刷向けページを管理画面に追加する。

英文本体は `transcription_requests.english_text` に保存済みなので、
バックエンドの管理画面だけで完結する（iOS・API 変更なし）。

## 対応方針

1. **純関数の切り出し**: `src/transcriptPrint.ts`（新規・副作用なし）に
   `transcriptParagraphsHtml(text: string): string` を実装する
   - `formatTranscriptParagraphs`（transcribe.ts）を再適用して段落を正規化
     （段落整形導入前の旧レコード対策）
   - 空行区切りの段落ごとに HTML エスケープして `<p>…</p>` を組み立てる
2. **印刷用ページ**: `GET /admin/transcriptions/:id/text` を admin.ts に追加
   - 管理画面のダークテーマ・サイドバーは使わず、印刷前提の白地・serif・
     広め行間・本文幅制限の単独ページとして描画する
   - 見出しはアプリ側タイトル（`title`）、無ければ `Transcription #<id>`
   - 画面表示時のみ「← 一覧に戻る」「印刷」ツールバーを出し、`@media print` で隠す
   - レコードが無い場合は 404、`english_text` が空（エラーレコード等）の場合は
     その旨を表示
3. **一覧からの導線**: `/admin/transcriptions` の英文セルに
   「印刷用表示」リンク（`target="_blank"`）を追加する

## 影響範囲

- backend のみ: `src/admin.ts`（ルート＋一覧リンク）、`src/transcriptPrint.ts`（新規）、
  `test/transcriptPrint.test.ts`（新規）
- iOS・API・DB スキーマの変更なし

## テスト方針

- 単体テスト（node:test）: `transcriptParagraphsHtml` の
  段落分割 / HTML エスケープ / 旧形式（単一改行・改行なし長文）の再整形
- E2E: サーバを起動し、既存レコード（#3: title なし、#4: title あり）で
  印刷用ページの表示・404・一覧リンクを curl / ブラウザで確認
