# 管理画面にコンテンツファイル一覧ページを追加

## 目的・背景

バックエンドは `backend/data/` 配下にコンテンツファイルを保存している
（`images`＝OCR入力画像、`tts`＝合成音声、`audio`＝取り込み音声、
`documents`＝取り込みドキュメント、`illustrations`＝単語イラスト。
パスはすべて `config.ts` に定義済み）。
現状これらのファイルはログ系ページ経由でしか触れず、ディスク上に
どんなファイルが実在するかを直接確認・取得する手段がない。
管理画面にファイル一覧ページを追加し、各ファイルのダウンロードと
音声ファイルのブラウザ再生をできるようにする。

## 対応方針

すべて `backend/src/admin.ts` 内で完結させる（DB 変更なし・新規モジュールなし）。

- **一覧ページ `GET /admin/content-files`**
  - `config` の 5 ディレクトリ（images / tts / audio / documents / illustrations）を
    ホワイトリスト定義し、`?dir=` クエリで表示対象を切替（タブUI、既定は `images`）
  - 各タブに件数を併記し、選択中ディレクトリの合計サイズ・件数を stats 表示
  - テーブル列: ファイル名 / サイズ / 更新日時（既存 `formatSeattleTime`）/ 再生 / DL
  - 並びは更新日時の降順
  - 音声拡張子（.wav .mp3 .m4a .aac .caf .ogg .flac）の行には
    既存 TTS 一覧と同じ `<audio controls preload="none">` を表示
- **配信エンドポイント `GET /admin/content-files/file?dir=<key>&name=<filename>[&download=1]`**
  - `dir` はホワイトリストのキーのみ許可（それ以外は 400）
  - `name` はパストラバーサル対策として `path.basename(name) === name` かつ
    `/` `\` `..` を含まないことを検証（違反は 400）、実在しない場合は 404
  - `download=1` なら `res.download()`（Content-Disposition: attachment）、
    無指定なら `res.sendFile()`（インライン配信。`<audio>` の src 用）
- サイドバー `NAV_ITEMS` に「コンテンツファイル」を追加（TTS一覧の下あたり）

## 影響範囲

- `backend/src/admin.ts` のみ（ページ 1 つ＋配信エンドポイント 1 つ＋nav 追加）
- `/admin` 配下は Cloudflare Access（エッジ側）保護のため、アプリ内認証の追加は不要
- 既存ページ・API・DB スキーマへの変更なし

## テスト方針

- `npm run build`（tsc）が通ることを確認する
- `npm test` が既存どおり通ることを確認する（本変更はテスト対象モジュール外）
- ローカルでサーバを起動し curl で確認:
  - `/admin/content-files?dir=tts` 等の各タブでファイル行が出力される
  - `file` エンドポイントが `download=1` で `Content-Disposition: attachment` を返す
  - 音声ファイルの行に `<audio>` タグが出力され、src のインライン配信が 200 を返す
  - `name=../db.sqlite` などのトラバーサル入力が 400 になる
- ブラウザ再生は既存 TTS 一覧と同一機構のため、タグ出力＋インライン配信 200 の確認をもって代える
