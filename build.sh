#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/.build"
APP="$ROOT/build/LanRDP.app"
FREERDP_BIN="$BUILD/build/freerdp-sdl/client/SDL/SDL3/sdl-freerdp"
OPENSSL_DIR="/opt/homebrew/opt/openssl@3/lib"
FFMPEG_DIR="$BUILD/ffmpeg-lgpl/arm64/lib"
FFMPEG_LIBS=(
    libavcodec.63.dylib
    libavutil.61.dylib
    libswscale.10.dylib
    libswresample.7.dylib
    libavformat.63.dylib
    libavfilter.12.dylib
    libavdevice.63.dylib
)

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
mkdir -p "$APP/Contents/Resources/en.lproj"
cp "$ROOT/Resources/en.lproj/Localizable.strings" "$APP/Contents/Resources/en.lproj/Localizable.strings"
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

echo "==> Bundling LGPL FFmpeg"
for lib in "${FFMPEG_LIBS[@]}"; do
    cp -L "$FFMPEG_DIR/$lib" "$APP/Contents/Frameworks/$lib"
    chmod u+w "$APP/Contents/Frameworks/$lib"
    install_name_tool -id "@rpath/$lib" "$APP/Contents/Frameworks/$lib"
    for dep in "${FFMPEG_LIBS[@]}"; do
        install_name_tool -change "$FFMPEG_DIR/$dep" "@rpath/$dep" \
            "$APP/Contents/Frameworks/$lib" 2>/dev/null || true
    done
    install_name_tool -add_rpath @loader_path "$APP/Contents/Frameworks/$lib" 2>/dev/null || true
    install_name_tool -change "$FFMPEG_DIR/$lib" "@rpath/$lib" \
        "$APP/Contents/MacOS/sdl-freerdp" 2>/dev/null || true
done

echo "==> Signing"
codesign --force --sign - "$APP/Contents/Frameworks/libcrypto.3.dylib"
codesign --force --sign - "$APP/Contents/Frameworks/libssl.3.dylib"
for lib in "${FFMPEG_LIBS[@]}"; do
    codesign --force --sign - "$APP/Contents/Frameworks/$lib"
done
codesign --force --sign - "$APP/Contents/MacOS/sdl-freerdp"
codesign --force --sign - "$APP/Contents/MacOS/LanRDP"
codesign --force --sign - "$APP"
xattr -cr "$APP"

echo "==> Built $APP"
"$APP/Contents/MacOS/sdl-freerdp" /version
