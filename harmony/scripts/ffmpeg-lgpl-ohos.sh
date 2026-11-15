#!/bin/bash
# Build an LGPL-only FFmpeg (H.264 decode + swscale) for HarmonyOS arm64.
# Output: .build/ohos/prefix-ffmpeg-arm64/{include,lib}
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="${FFMPEG_SRC:-/Users/linc/Documents/deepseek-harness/default-workspace/lanrdp/.build/src/ffmpeg-9.0.2}"
BUILD="$ROOT/.build/ohos/build-ffmpeg-arm64"
PREFIX="$ROOT/.build/ohos/prefix-ffmpeg-arm64"
TOOLCHAIN="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native"
LLVM="$TOOLCHAIN/llvm/bin"
SYSROOT="$TOOLCHAIN/sysroot"

if [[ ! -x "$SRC/configure" ]]; then
    echo "FFmpeg source not found: $SRC" >&2
    exit 1
fi

TARGET="aarch64-linux-ohos"
CC="$LLVM/clang --target=$TARGET --sysroot=$SYSROOT"
CXX="$LLVM/clang++ --target=$TARGET --sysroot=$SYSROOT"

mkdir -p "$BUILD" "$PREFIX"
cd "$BUILD"

if [[ ! -f ffbuild/config.mak ]]; then
    "$SRC/configure" \
        --prefix="$PREFIX" \
        --target-os=linux \
        --arch=aarch64 \
        --cpu=armv8-a \
        --enable-cross-compile \
        --cc="$CC" \
        --cxx="$CXX" \
        --ar="$LLVM/llvm-ar" \
        --ranlib="$LLVM/llvm-ranlib" \
        --strip="$LLVM/llvm-strip" \
        --nm="$LLVM/llvm-nm" \
        --disable-gpl --disable-nonfree \
        --disable-programs --disable-doc --disable-network --disable-autodetect \
        --disable-everything \
        --enable-avcodec --enable-avutil --enable-swscale --enable-swresample \
        --enable-decoder=h264 --enable-parser=h264 \
        --enable-shared --disable-static --enable-pic \
        --disable-iconv --disable-zlib --disable-sdl2 --disable-xlib \
        --extra-cflags="-D__MUSL__" \
        --extra-ldflags="-fuse-ld=lld"
fi

make -j"$(sysctl -n hw.ncpu)"
make install

echo "==> FFmpeg OHOS installed: $PREFIX"
ls -l "$PREFIX"/lib/libavcodec.so* "$PREFIX"/lib/libavutil.so* "$PREFIX"/lib/libswscale.so*
