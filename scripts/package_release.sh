#!/bin/bash
# 构建 Release 版并生成用于 GitHub Releases 的 zip 与 SHA256 文件
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' TrafficSentinel.xcodeproj/project.pbxproj | head -n 1)"
if [[ -z "$VERSION" ]]; then
  echo "无法从工程中读取版本号" >&2
  exit 1
fi

"$ROOT/scripts/build.sh" Release

APP="$ROOT/dist/流量哨兵.app"
ZIP_NAME="TrafficSentinel-${VERSION}-macOS.zip"
ZIP="$ROOT/dist/$ZIP_NAME"

if [[ ! -d "$APP" ]]; then
  echo "构建产物不存在：$APP" >&2
  exit 1
fi

rm -f "$ZIP" "$ZIP.sha256"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
(
  cd "$ROOT/dist"
  shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256"
)

echo
echo "完成："
echo "  $ZIP"
echo "  $ZIP.sha256"
