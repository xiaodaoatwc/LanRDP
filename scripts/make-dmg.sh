#!/bin/bash
# Build a styled LanRDP DMG with only LanRDP.app and an Applications shortcut.
#
# Usage:
#   ./scripts/make-dmg.sh <app-bundle> <output-dmg> [volume-name]
#
# Finder automation is used to position the icons. macOS may ask for
# permission to control Finder the first time.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/build/LanRDP-universal.app}"
OUT="${2:-$ROOT/build/LanRDP.dmg}"
VOLUME="${3:-LanRDP}"

if [[ ! -d "$APP" ]]; then
    echo "App bundle not found: $APP" >&2
    exit 1
fi

MOUNT="/Volumes/$VOLUME"
if [[ -e "$MOUNT" ]]; then
    echo "Volume already mounted: $MOUNT" >&2
    echo "Eject it first, or pass a different volume name." >&2
    exit 1
fi

STAGE="$(mktemp -d /tmp/lanrdp-dmg-stage.XXXXXX)"
RW="$(mktemp -u /tmp/lanrdp-dmg-rw.XXXXXX.dmg)"
DISK=""

cleanup() {
    if [[ -n "$DISK" ]]; then
        hdiutil detach "$DISK" >/dev/null 2>&1 || true
    fi
    rm -rf "$STAGE" "$RW"
}
trap cleanup EXIT

mkdir -p "$STAGE/.background"
chmod 755 "$STAGE"
cp -R "$APP" "$STAGE/LanRDP.app"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/Resources/DMGBackground.png" "$STAGE/.background/background.png"
cp "$ROOT/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"

hdiutil create -volname "$VOLUME" -srcfolder "$STAGE" -ov -format UDRW "$RW" >/dev/null
DISK="$(hdiutil attach "$RW" -nobrowse | awk '/\/Volumes\// {print $1; exit}')"

osascript <<APPLESCRIPT
tell application "Finder"
    activate
    tell disk "$VOLUME"
        open
        set w to container window
        set current view of w to icon view
        set toolbar visible of w to false
        set statusbar visible of w to false
        try
            set sidebar width of w to 0
        end try
        set bounds of w to {100, 100, 760, 530}
        set viewOptions to the icon view options of w
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set background picture of viewOptions to file ".background:background.png"
        set position of item "LanRDP.app" of w to {165, 238}
        set position of item "Applications" of w to {495, 238}
        close
    end tell
end tell
APPLESCRIPT

SetFile -a C "$MOUNT" 2>/dev/null || true
hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
DISK=""

rm -f "$OUT"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
echo "$OUT"
