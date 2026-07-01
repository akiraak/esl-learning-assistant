#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$SCRIPT_DIR/backend"
cd "$BACKEND_DIR"

if [ ! -f .env ]; then
  echo "[run-server] backend/.env が見つかりません。backend/.env.example を参考に作成してください。" >&2
  exit 1
fi

PORT="$(grep -E '^PORT=' .env | tail -n1 | cut -d'=' -f2- | tr -d '[:space:]')"
PORT="${PORT:-8801}"

EXISTING_PIDS="$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)"
if [ -n "$EXISTING_PIDS" ]; then
  echo "[run-server] ポート $PORT を使用中のプロセス (PID: $(echo "$EXISTING_PIDS" | xargs)) を停止します..."
  kill $EXISTING_PIDS 2>/dev/null || true
  for _ in $(seq 1 10); do
    lsof -tiTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1 || break
    sleep 0.5
  done
  if lsof -tiTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "[run-server] プロセスが停止しなかったため強制終了します..." >&2
    kill -9 $EXISTING_PIDS 2>/dev/null || true
    sleep 0.5
  fi
fi

if [ ! -d node_modules ]; then
  echo "[run-server] node_modules が無いため npm install を実行します..."
  npm install
fi

echo "[run-server] ビルドします..."
npm run build

echo "[run-server] サーバーを起動します...（ログは標準出力と backend/data/server.log の両方に出力されます）"
exec npm start
