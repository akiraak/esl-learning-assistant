# ローカルバックエンド起動用スクリプト作成プラン

## 目的・背景

[backend-claude-api-integration.md](archive/backend-claude-api-integration.md) で実装した
バックエンド（`backend/`）を、毎回 `cd backend && npm run build && npm start` と手打ちせず
リポジトリ直下から1コマンドで起動できるようにする。
[run-on-device.sh](../../ios/run-on-device.sh) と同様の位置付けのユーティリティスクリプト。

## 対応方針

- リポジトリ直下に `run-server.sh` を新規作成する
- `backend/.env` が無い場合はエラーメッセージを出して終了する（`backend/.env.example` を案内）
- `backend/node_modules` が無ければ `npm install` を実行する
- `npm run build` → `exec npm start` の順で実行する（`exec` にすることで Ctrl+C の
  シグナルが node プロセスに正しく伝わるようにする）
- `run-on-device.sh` に倣い `set -euo pipefail` とスクリプト内メッセージの `[run-server]` prefix
  を使う

## 影響範囲

- 新規: `run-server.sh`（実行権限付与）
- 変更: `TODO.md` / `DONE.md`

## テスト方針

- `./run-server.sh` を実行し、ビルド → 起動 → `curl http://localhost:8801/health` が
  `{"status":"ok"}` を返すことを確認する
- `.env` を一時的にリネームして未設定時のエラーメッセージが出ることを確認する

## Phase / Step

単一ステップのため Phase 分割なし。
