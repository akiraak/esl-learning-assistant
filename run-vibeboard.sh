#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -d vibeboard ]; then
  echo "[run-vibeboard] vibeboard/ が見つかりません。clone してください。" >&2
  exit 1
fi

if [ ! -d vibeboard/node_modules ]; then
  echo "[run-vibeboard] vibeboard/node_modules が無いので npm install を実行します..."
  (cd vibeboard && npm install)
fi

# dist が無い、または src/ 配下のどれかの .ts が dist/cli.js より新しければ再ビルドする
# （cli.ts だけ見ると server.ts 等の変更を取りこぼすため src/**/*.ts 全体を対象にする）
if [ ! -f vibeboard/dist/cli.js ] || [ -n "$(find vibeboard/src -name '*.ts' -newer vibeboard/dist/cli.js -print -quit 2>/dev/null)" ]; then
  echo "[run-vibeboard] src/ に dist より新しい .ts があるため再ビルドします..."
  (cd vibeboard && npm run build)
fi

# 起動 port を決定（--port / --port= / VIBEBOARD_PORT を考慮、無ければ 3010）
TARGET_PORT="${VIBEBOARD_PORT:-3010}"
prev_arg=""
for arg in "$@"; do
  if [ "$prev_arg" = "--port" ]; then TARGET_PORT="$arg"; fi
  case "$arg" in
    --port=*) TARGET_PORT="${arg#--port=}" ;;
  esac
  prev_arg="$arg"
done

# 同じ port を握っている既存 vibeboard があれば停止する（他プロセスなら中断）
# Linux は ss、macOS は lsof を使う
find_pid_on_port() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltnp 2>/dev/null \
      | awk -v p=":${port}\$" '$4 ~ p { if (match($0, /pid=[0-9]+/)) { print substr($0, RSTART+4, RLENGTH-4); exit } }'
  elif command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null | head -n 1 || true
  fi
  return 0
}

existing_pid="$(find_pid_on_port "$TARGET_PORT")"
if [ -n "$existing_pid" ]; then
  if ps -p "$existing_pid" -o args= 2>/dev/null | grep -q "vibeboard/dist/cli.js"; then
    echo "[run-vibeboard] port $TARGET_PORT を握っている既存 vibeboard (PID $existing_pid) を停止します..."
    kill "$existing_pid" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      sleep 0.3
      if [ -z "$(find_pid_on_port "$TARGET_PORT")" ]; then
        break
      fi
    done
  else
    echo "[run-vibeboard] port $TARGET_PORT は vibeboard 以外 (PID $existing_pid) が使用中です。先に停止してください。" >&2
    exit 1
  fi
fi

exec node vibeboard/dist/cli.js --root . "$@"
