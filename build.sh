#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/.build"
APP="$ROOT/build/LanRDP.app"
FREERDP_BIN="$BUILD/build/freerdp-sdl/client/SDL/SDL3/sdl-freerdp"
OPENSSL_DIR="/opt/homebrew/opt/openssl@3/lib"

if [ ! -x "$FREERDP_BIN" ]; then
    echo "error: sdl-freerdp not found at $FREERDP_BIN" >&2
    echo "Build it first, or run the prep script described in README.md." >&2
    exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

echo "==> Compiling SwiftUI app"
xcrun swiftc \
    -parse-as-library -O \
    -target arm64-apple-macos14.0 \
    -sdk "$(xcrun --show-sdk-path)" \
    -framework SwiftUI -framework AppKit -framework Security \
    -o "$APP/Contents/MacOS/LanRDP" \
    "$ROOT"/Sources/*.swift

echo "==> Bundling resources"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
mkdir -p "$APP/Contents/Resources/Licenses"
cp "$ROOT/Resources/Licenses/"* "$APP/Contents/Resources/Licenses/"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$ROOT/MODIFICATIONS.md" "$ROOT/LICENSE" "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Bundling sdl-freerdp and OpenSSL"
cp "$FREERDP_BIN" "$APP/Contents/MacOS/sdl-freerdp"
cp -L "$OPENSSL_DIR/libssl.3.dylib" "$APP/Contents/Frameworks/libssl.3.dylib"
cp -L "$OPENSSL_DIR/libcrypto.3.dylib" "$APP/Contents/Frameworks/libcrypto.3.dylib"
chmod u+w "$APP/Contents/Frameworks/libssl.3.dylib" "$APP/Contents/Frameworks/libcrypto.3.dylib"

install_name_tool -id @rpath/libssl.3.dylib "$APP/Contents/Frameworks/libssl.3.dylib"
install_name_tool -id @rpath/libcrypto.3.dylib "$APP/Contents/Frameworks/libcrypto.3.dylib"
install_name_tool \
    -change /opt/homebrew/Cellar/openssl@3/3.3.1/lib/libcrypto.3.dylib @rpath/libcrypto.3.dylib \
    "$APP/Contents/Frameworks/libssl.3.dylib" 2>/dev/null || true
install_name_tool -add_rpath @loader_path "$APP/Contents/Frameworks/libssl.3.dylib" 2>/dev/null || true

install_name_tool \
    -change /opt/homebrew/opt/openssl@3/lib/libssl.3.dylib @rpath/libssl.3.dylib \
    -change /opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib @rpath/libcrypto.3.dylib \
    -add_rpath @executable_path/../Frameworks \
    "$APP/Contents/MacOS/sdl-freerdp"

echo "==> Signing"
codesign --force --sign - "$APP/Contents/Frameworks/libcrypto.3.dylib"
codesign --force --sign - "$APP/Contents/Frameworks/libssl.3.dylib"
codesign --force --sign - "$APP/Contents/MacOS/sdl-freerdp"
codesign --force --sign - "$APP/Contents/MacOS/LanRDP"
codesign --force --sign - "$APP"
xattr -cr "$APP"

echo "==> Built $APP"
"$APP/Contents/MacOS/sdl-freerdp" /version
