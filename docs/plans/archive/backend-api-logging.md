# backend API 呼び出しのログ強化 + Settings の接続テスト

## 目的・背景

本番向けビルドで単語の意味の再生成が失敗した。調査の結果、原因は
**`.env.prod` / Settings に入力した API Secret がローカル用の値（`backend/.env`）で、
本番サーバの値と一致していない**ことによる 401 だった（curl で再現確認済み）。

この種の問題（URL間違い・secret不一致・サーバ停止・API側エラー）を
アプリだけで切り分けられるよう、可視化を追加する。

## 対応方針

### Step 1: iOS — BackendAPI にログとエラー詳細を追加

- `os.Logger`（subsystem=バンドルID, category="BackendAPI"）で
  リクエスト開始（URL、secret の出所と長さ。**値そのものはログに出さない**）と
  結果（HTTPステータス、失敗時はレスポンスボディ先頭）を記録する。
  Xcode コンソール / Console.app / `log stream` で確認できる
- 送信〜検証を `BackendAPI.post(path:body:) async throws -> Data` に集約し、
  3サービス（OCR翻訳 / 単語情報 / TTS）を乗せ替える
- `BackendAPIError.serverError` に backend の `{"error": "..."}` メッセージを取り込み、
  ユーザー向けエラー文言に含める（例: "Server error (HTTP 500): ..."）

### Step 2: iOS — Settings に「Test Connection」ボタンを追加

- `/health`（無認証）でサーバ疎通、`GET /api/ping`（要認証）で secret 一致を確認し、
  結果を「Server: OK / API Secret: NG(401)…」のように表示する
- 旧 backend には /api/ping が無く 404 が返るが、401 でなければ認証は通過しているので
  secret は OK と判定する

### Step 3: backend — `GET /api/ping` を追加

- /api 配下なので認証ミドルウェアを通る。`{ ok: true }` を返すだけ
- 本番反映は g3plus-ops 側の再デプロイ時（未反映でも Step 2 は 404 判定で動く）

## 影響範囲

- iOS の backend 呼び出し3サービスとエラー型（`serverError` に message が増える。テスト追随）
- backend はエンドポイント追加のみ

## テスト方針

- iOS: ビルド + 既存ユニットテスト
- backend: `npm run build` + ローカルで /api/ping の 401 / 200 を curl 確認
