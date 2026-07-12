# 管理画面コンテンツファイル一覧: Audio/Docs のタイトル表示＋画像サムネ

## 目的・背景

`/admin/content-files` はサーバ保存名（`<timestamp>-<uuid>.<ext>`）しか出せず、
どのファイルがアプリのどのコンテンツか分からない。

- アプリ側のタイトルは Audio = `AudioClip.title`（取り込みファイル名）、
  Docs = `Document.title`（元ファイル名）で、いずれも**リクエスト時点で iOS が持っている**が
  API に送っていない
- サーバのログテーブル（`transcription_requests.audio_filename` /
  `document_requests.document_filename`）には保存ファイル名があるので、
  タイトルを列追加すればファイル一覧と JOIN できる
- 画像はタイトル不要で、サムネイル表示だけでよい（ユーザー確認済み）

## 対応方針

### Phase 1: backend

- `db.ts`: `transcription_requests` / `document_requests` に `title TEXT` 列を追加
  （CREATE TABLE ＋ 既存 DB 向けに PRAGMA table_info → ALTER TABLE の起動時マイグレーション。
  requests テーブルの既存パターンに倣う）。Input/Row 型・INSERT に title を追加。
  ファイル名→タイトルの逆引き（`getAudioTitlesByFilename` / `getDocumentTitlesByFilename`）を追加
- `index.ts` `/api/transcribe-translate`: body の任意フィールド `title` を受ける
  （string 以外は 400、trim・空は null、長さ上限 200）。成功/失敗ログ両方に記録
- `documentExtract.ts` `validateDocumentExtractRequest`: 任意 `title` を検証して返す。
  `/api/document-extract-translate` でログに記録
- `admin.ts` content-files: audio / documents タブに「タイトル」列
  （ログとファイル名で突き合わせ、無ければ —）。images タブは再生列の代わりにサムネ列
  （`<img loading="lazy">`、クリックで原寸を別タブ表示）

### Phase 2: iOS

- `RemoteTranscriptionTranslationService`: RequestBody に `title` を追加し `clip.title` を送信
- `RemoteDocumentExtractTranslateService`: 同様に `document.title` を送信

### Phase 3: 検証

- 単体テスト: `validateDocumentExtractRequest` の title 受理/拒否/trim を追加
- E2E: 新コードのサーバに title 付きで音声・docx を POST →
  `/admin/content-files?dir=audio|documents` にタイトルが出ること、
  title 無し（旧形式）でも 200 で — 表示になること、images タブに `<img>` が出ることを確認
- iOS はシミュレータ向けビルドが通ることを確認

## 影響範囲

- backend: `db.ts` / `index.ts` / `documentExtract.ts` / `admin.ts`
- iOS: 送信サービス2ファイル（RequestBody 追加のみ）。title は任意フィールドなので
  旧アプリ→新サーバ、新アプリ→旧サーバのどちらの組み合わせでも壊れない
- 過去に取り込んだ分にはタイトルは付かない（—表示）。アプリ側でのリネームは再送まで反映されない

## テスト方針

上記 Phase 3 のとおり。既存テスト・tsc green を維持。
