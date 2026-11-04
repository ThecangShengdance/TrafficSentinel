#!/bin/bash
# 构建「流量哨兵」并打包到 dist/流量哨兵.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-Release}"
DERIVED="$ROOT/.build/DerivedData"

mkdir -p "$ROOT/.build/tmp" "$DERIVED"

echo "==> Building TrafficSentinel ($CONFIG)"
TMPDIR="$ROOT/.build/tmp" xcodebuild \
  -project TrafficSentinel.xcodeproj \
  -scheme TrafficSentinel \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  build

APP="$DERIVED/Build/Products/$CONFIG/TrafficSentinel.app"
if [[ ! -d "$APP" ]]; then
  echo "构建产物不存在：$APP" >&2
  exit 1
fi

mkdir -p "$ROOT/dist"
rm -rf "$ROOT/dist/流量哨兵.app"
ditto "$APP" "$ROOT/dist/流量哨兵.app"

echo
echo "完成：$ROOT/dist/流量哨兵.app"
echo "首次打开如被 Gatekeeper 拦截，请在 Finder 中右键 → 打开。"
