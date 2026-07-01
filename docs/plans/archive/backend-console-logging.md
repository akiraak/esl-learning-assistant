# バックエンドのログ出力強化

## 目的・背景

現状バックエンドは、OCR・翻訳リクエストの成功/失敗を`backend/data/db.sqlite`の`requests`テーブルに
記録するのみで、コンソールへのログ出力はサーバー起動時のメッセージだけ
（`ios/`→実機からの接続失敗のように、リクエストがサーバーに到達すらしていない場合はDBにも
何も残らず、原因切り分けができない）。実機での再翻訳が失敗した際に、リアルタイムでサーバー側の
状況を確認できるよう、コンソール（および永続ファイル）にログを出力するようにする。

## 対応方針

- `backend/src/logger.ts` を新設。タイムスタンプ付きで `console.log`/`console.error` に出力しつつ、
  `backend/data/server.log` にも追記する簡易ロガー（info/warn/error）を実装する
  （`backend/data/` は既にgitignore対象・db.tsが起動時にディレクトリ作成済みのものを利用）。
- `backend/src/index.ts`:
  - 全リクエストを記録するロギングミドルウェアを追加（method・path・IPを記録。実機から
    そもそもリクエストが届いているかどうかを切り分けられるようにする）。
  - `/api/ocr-translate` ハンドラの開始・成功・失敗時にロガーで詳細（targetLanguage、latency、
    エラーメッセージ）を出力する。
  - `process.on("uncaughtException"/"unhandledRejection")` を追加し、想定外エラーで
    サーバーが無言で落ちる/リクエストが応答不能になるケースもログに残す。
  - 起動時ログもロガー経由に統一する。
- `run-server.sh` はforegroundで`npm start`するため標準出力はそのまま表示される。
  ログファイル`backend/data/server.log`の場所を案内する一文を追記する。

## 影響範囲

- `backend/src/logger.ts`（新規）
- `backend/src/index.ts`
- `run-server.sh`

## テスト方針

- `npm run build` でTypeScriptのビルドが通ることを確認する。
- サーバーを再起動し、`curl`でヘルスチェック・OCR-translateエンドポイントを叩いて
  コンソール・`backend/data/server.log`双方にログが出力されることを確認する。
