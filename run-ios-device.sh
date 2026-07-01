#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/ios"

SCHEME="ESLLearningAssistant"
PROJECT="ESLLearningAssistant.xcodeproj"
BUNDLE_ID="com.akiraak.esllearningassistant"

# デバイスIDは DEVICE_ID 環境変数で上書き可能。未指定ならペアリング済みデバイスを自動検出する
if [ -z "${DEVICE_ID:-}" ]; then
  DEVICES_JSON="$(mktemp -t devicectl-devices)"
  trap 'rm -f "$DEVICES_JSON"' EXIT
  xcrun devicectl list devices -j "$DEVICES_JSON" >/dev/null
  device_count="$(jq '.result.devices | length' "$DEVICES_JSON")"
  if [ "$device_count" -eq 0 ]; then
    echo "[run-ios-device] ペアリング済みデバイスが見つかりません。USBで一度接続してペアリングしてください。" >&2
    exit 1
  fi
  if [ "$device_count" -gt 1 ]; then
    echo "[run-ios-device] デバイスが複数見つかりました。DEVICE_ID 環境変数で指定してください:" >&2
    jq -r '.result.devices[] | "\(.identifier)\t\(.deviceProperties.name)"' "$DEVICES_JSON" >&2
    exit 1
  fi
  DEVICE_ID="$(jq -r '.result.devices[0].identifier' "$DEVICES_JSON")"
fi

# バックエンドURLは BACKEND_BASE_URL 環境変数で上書き可能。未指定ならMacのLAN IPを自動検出して使う
if [ -z "${BACKEND_BASE_URL:-}" ]; then
  MAC_IP=""
  for iface in en0 en1 en2; do
    MAC_IP="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
    [ -n "$MAC_IP" ] && break
  done
  if [ -n "$MAC_IP" ]; then
    BACKEND_BASE_URL="http://${MAC_IP}:8801"
    echo "[run-ios-device] BACKEND_BASE_URL=${BACKEND_BASE_URL}（MacのLAN IPを自動検出）"
  else
    BACKEND_BASE_URL="http://localhost:8801"
    echo "[run-ios-device] MacのLAN IPを自動検出できませんでした。アプリの設定画面でサーバーURLを手動設定してください。" >&2
  fi
fi

echo "[run-ios-device] DEVICE_ID=$DEVICE_ID でビルドします..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "id=$DEVICE_ID" -allowProvisioningUpdates \
  BACKEND_BASE_URL="$BACKEND_BASE_URL" build

DERIVED_DATA_APP_DIR="$HOME/Library/Developer/Xcode/DerivedData"
# Index.noindex 配下はSourceKitのインデックス作成用ビルドで、インストール可能な実体ではないため除外する
APP_PATH="$(find "$DERIVED_DATA_APP_DIR" -maxdepth 6 -name "${SCHEME}.app" -path "*Debug-iphoneos*" -not -path "*Index.noindex*" -print -quit)"
if [ -z "$APP_PATH" ]; then
  echo "[run-ios-device] ビルド済みの ${SCHEME}.app が見つかりませんでした。" >&2
  exit 1
fi
echo "[run-ios-device] APP_PATH=$APP_PATH"

echo "[run-ios-device] デバイスへインストールします..."
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

echo "[run-ios-device] アプリを起動します..."
xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID"

echo "[run-ios-device] 完了しました。"
