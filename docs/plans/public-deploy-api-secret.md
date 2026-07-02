# backend 公開デプロイ対応（API_SECRET ヘッダ認証）

## 目的・背景

backend（`run-server.sh` で起動しているローカル開発サーバ）を g3plus サーバ上で Docker コンテナとして公開運用する（`https://esl.chobi.me/`、Cloudflare Tunnel 経由）。

backend は認証なしで Anthropic / Gemini API を叩けるため、素のまま公開はできない。保護方式は以下の2段構え：

- **`/api/*`**: 共有 secret（`API_SECRET`）を HTTP ヘッダ `X-API-Secret` に含めて送る方式。URL に含めないためブラウザ履歴・Referer に漏れず、ローテーションしても URL が変わらない
- **`/admin/*`**: Cloudflare Access（Google アカウント認証）でエッジ側保護。backend 側のコード変更は不要
- **`/health`**: 無認証のまま（疎通確認用）

## 対応方針

1. `backend/src/config.ts` に `apiSecret`（環境変数 `API_SECRET`）を追加
2. `backend/src/index.ts`:
   - 起動時に `API_SECRET` を検証（16 文字以上、`[A-Za-z0-9_-]` のみ）。不正なら exit 1（fail-fast、意図しない無防備公開を防ぐ）
   - `/api/*` に `X-API-Secret` ヘッダ検証ミドルウェアを追加（timing-safe 比較、不一致は 401）
3. `backend/.env.example` に `API_SECRET` を追記（生成方法コメント付き）

## 影響範囲

- **ローカル開発**: `backend/.env` に `API_SECRET` の追記が必須になる（未設定だと起動しない）
- **iOS アプリ**: `/api/*` を呼ぶ際に `X-API-Secret` ヘッダの送信が必要になる（別タスク、TODO.md 参照）
- デプロイ設定（Dockerfile / docker-compose.yml / 本番 .env）は g3plus-ops リポジトリ側で管理（`g3plus-ops/esl-learning-assistant/`）

## テスト方針

- `npm run build` が通ること
- `API_SECRET` 未設定 / 15 文字以下で起動が exit 1 すること
- ヘッダなし・不正ヘッダで `/api/*` が 401、正しいヘッダで従来どおり動作すること
- `/health` と `/admin` はヘッダなしで従来どおりアクセスできること
