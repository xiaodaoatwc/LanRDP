#!/bin/bash
# 构建 LGPL-only 的 FFmpeg（H.264 解码 + swscale），供 LanRDP 动态链接使用。
#
# 用法：
#   ./scripts/ffmpeg-lgpl.sh [arm64|x86_64]
#
# - 不启用 --enable-gpl / --enable-nonfree，因此产物是 LGPL-2.1+；
# - 只保留 h264 解码器、parser 和 swscale/swresample，体积小；
# - 仅构建共享库（动态链接），不做静态链接。
#
# 产物：.build/ffmpeg-lgpl/<arch>/{include,lib}

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="${1:-arm64}"
VERSION="9.0.2"
SRC="$ROOT/.build/src/ffmpeg-$VERSION"
BUILD="$ROOT/.build/ffmpeg-build/$ARCH"
PREFIX="$ROOT/.build/ffmpeg-lgpl/$ARCH"
TARBALL="${FFMPEG_TARBALL:-}"

if [[ ! -d "$SRC" ]]; then
    mkdir -p "$ROOT/.build/src"
    if [[ -z "$TARBALL" || ! -f "$TARBALL" ]]; then
        TARBALL="$ROOT/.build/src/ffmpeg-$VERSION.tar.xz"
        if [[ ! -f "$TARBALL" ]]; then
            echo "==> 下载 FFmpeg $VERSION 源码"
            curl -fL --retry 3 -o "$TARBALL" "https://ffmpeg.org/releases/ffmpeg-$VERSION.tar.xz"
        fi
    fi
    echo "==> 解压 $TARBALL"
    tar -xf "$TARBALL" -C "$ROOT/.build/src"
fi

case "$ARCH" in
    arm64)  EXTRA=(--arch=arm64) ;;
    x86_64)
        # 在 Apple Silicon 上交叉编译 x86_64：必须让 clang 以 x86_64 为目标，
        # 否则 x86 的内联汇编会报 "invalid input constraint 'c' in asm"。
        if [[ "$(uname -m)" == "arm64" ]]; then
            EXTRA=(--arch=x86_64 --cc="clang -arch x86_64" --cxx="clang++ -arch x86_64"
                   --extra-cflags="-arch x86_64" --extra-ldflags="-arch x86_64")
        else
            EXTRA=(--arch=x86_64)
        fi
        # x86 的手写汇编需要 nasm；没有就退化为纯 C（仅作为 x86_64 slice 的后备解码器）
        if ! command -v nasm >/dev/null 2>&1; then
            echo "==> 未找到 nasm，x86_64 构建关闭 x86asm"
            EXTRA+=(--disable-x86asm)
        fi
        ;;
    *) echo "unsupported arch: $ARCH" >&2; exit 1 ;;
esac

echo "==> 配置 FFmpeg（LGPL，$ARCH）"
mkdir -p "$BUILD"
cd "$BUILD"
"$SRC/configure" \
    --prefix="$PREFIX" \
    "${EXTRA[@]}" \
    --disable-gpl --disable-nonfree \
    --disable-programs --disable-doc --disable-network --disable-autodetect \
    --disable-everything \
    --enable-avcodec --enable-avutil --enable-swscale --enable-swresample \
    --enable-decoder=h264 --enable-parser=h264 \
    --enable-shared --disable-static \
    --disable-iconv --disable-sdl2 --disable-xlib

echo "==> 构建"
make -j"$(sysctl -n hw.ncpu)"
make install

echo "==> 完成：$PREFIX"
ls -1 "$PREFIX"/lib/*.dylib
