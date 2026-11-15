#!/bin/bash
# Configure/build FreeRDP 3.33.0 for OHOS arm64 with LGPL FFmpeg H.264 decode.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="${FREERDP_SRC:-$ROOT/.build/ohos/src/freerdp}"
BUILD="$ROOT/.build/ohos/build-freerdp-arm64"
PREFIX="$ROOT/.build/ohos/prefix-freerdp-arm64-ffmpeg"
FF="$ROOT/.build/ohos/prefix-ffmpeg-arm64"
CMAKE="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native/build-tools/cmake/bin/cmake"
TOOLCHAIN="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native/build/cmake/ohos.toolchain.cmake"

if [[ ! -d "$SRC" ]]; then
    echo "FreeRDP source not found: $SRC" >&2
    exit 1
fi
if [[ ! -f "$FF/lib/libavcodec.so" ]]; then
    echo "FFmpeg prefix not found: $FF (run ffmpeg-lgpl-ohos.sh)" >&2
    exit 1
fi

"$CMAKE" -S "$SRC" -B "$BUILD" \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DWITH_FFMPEG=ON -DWITH_VIDEO_FFMPEG=ON -DWITH_SWSCALE=ON \
    -DWITH_OHOS_AVCODEC=OFF \
    -DFFMPEG_INCLUDE_DIRS="$FF/include" \
    -DFFMPEG_LIBRARIES="$FF/lib/libavcodec.so;$FF/lib/libavutil.so;$FF/lib/libswscale.so" \
    -DAVCODEC_INCLUDE_DIRS="$FF/include" -DAVCODEC_LIBRARIES="$FF/lib/libavcodec.so" \
    -DAVCODEC_FOUND=TRUE \
    -DAVUTIL_INCLUDE_DIRS="$FF/include" -DAVUTIL_LIBRARIES="$FF/lib/libavutil.so" \
    -DAVUTIL_FOUND=TRUE \
    -DSWSCALE_INCLUDE_DIRS="$FF/include" -DSWSCALE_LIBRARIES="$FF/lib/libswscale.so" \
    -DSWSCALE_FOUND=TRUE

"$CMAKE" --build "$BUILD" -j"$(sysctl -n hw.ncpu)"
"$CMAKE" --install "$BUILD"
