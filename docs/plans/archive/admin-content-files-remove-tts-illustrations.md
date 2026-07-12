# 管理画面コンテンツファイル一覧から TTS音声・単語イラストを除外

## 目的・背景

`/admin/content-files`（c6640ec で追加）は data/ 配下5ディレクトリをタブ表示しているが、
TTS音声と単語イラストには専用ページ（`/admin/tts`・`/admin/illustrations`）が既にあり、
コンテンツファイル一覧に重複して出す必要がない。タブを 画像 / 取り込み音声 / ドキュメント
の3つに絞る。

## 対応方針

`backend/src/admin.ts` の `CONTENT_DIRS` から `tts` と `illustrations` の2エントリを削除する。

- `CONTENT_DIRS` はタブ表示と `/admin/content-files/file` の dir ホワイトリストを兼ねるため、
  削除だけで一覧からも配信からも消える（`?dir=tts` は既存の 400 分岐に落ちる）
- 専用ページは独自ルート（`/admin/tts/:id/audio`・`/admin/illustrations/:id/image`）で
  配信しており影響なし

## 影響範囲

- `backend/src/admin.ts` の `CONTENT_DIRS` のみ
- `/admin/content-files` のタブが3つになる。`?dir=tts` / `?dir=illustrations` は 400

## テスト方針

- `tsc --noEmit` と既存テスト green
- サーバを起動し `/admin/content-files` のタブに TTS音声・単語イラストが無いこと、
  `?dir=tts` が 400 になること、残る3タブ（`?dir=images` 等）が 200 のままなことを curl で確認
