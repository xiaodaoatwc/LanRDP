#!/bin/bash
# 打一个测试包：自动把 CFBundleVersion +1，构建 App，再生成 DMG。
#
# 用法：
#   ./scripts/make-test-dmg.sh [标签]
#
# 例：
#   ./scripts/make-test-dmg.sh gfx
#   → build/LanRDP-1.14.2-b19-gfx.dmg，App 里“关于”显示 1.14.2 (build 19)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="$ROOT/Resources/Info.plist"
LABEL="${1:-test}"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
CURRENT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
NEXT=$((CURRENT + 1))

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEXT" "$PLIST"

echo "==> 版本 $VERSION，build $CURRENT → $NEXT"
"$ROOT/build.sh" >/dev/null

OUT="$ROOT/build/LanRDP-${VERSION}-b${NEXT}-${LABEL}.dmg"
VOLUME="LanRDP b${NEXT}"

"$ROOT/scripts/make-dmg.sh" "$ROOT/build/LanRDP.app" "$OUT" "$VOLUME" >/dev/null
echo "==> $OUT"
