#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

arch=arm64
enable_opt=0
enable_x264=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --help|-h)
            cat <<'EOF'
Usage: cross/hm_ffmpeg.sh [options]
  --path DIR         FFmpeg source directory (default: ../ffmpeg)
  --arch arm64       OpenHarmony architecture (default: arm64)
  --enable_opt 0|1   Enable optimizations (default: 0)
  --enable_x264 0|1  Build with libx264 (default: 0)
  --install          Install after the build (on by default)
Set OHOS_SDK_NATIVE to the OpenHarmony native SDK directory.
EOF
            exit 0
            ;;
        --path) cross_value "$@"; ffmpeg_src="$2"; shift 2 ;;
        --arch) cross_value "$@"; arch="$2"; shift 2 ;;
        --enable_opt) cross_value "$@"; cross_bool "$1" "$2"; enable_opt="$2"; shift 2 ;;
        --enable_x264) cross_value "$@"; cross_bool "$1" "$2"; enable_x264="$2"; shift 2 ;;
        --install) shift ;;
        *) cross_error "Unknown argument: $1" ;;
    esac
done

case "$arch" in
    arm64|aarch64) ;;
    *) cross_error "--arch must be arm64" ;;
esac

cross_source_dir
: "${OHOS_SDK_NATIVE:?Set OHOS_SDK_NATIVE to the OpenHarmony native SDK directory}"
toolchain="$(cd "$OHOS_SDK_NATIVE/llvm/bin" && pwd -P)"
target=aarch64-unknown-linux-ohos
clang="$toolchain/$target-clang"
clangxx="$toolchain/$target-clang++"
[ -x "$clang" ] || cross_error "OpenHarmony compiler not found in $toolchain"

ffmpeg_build="$build_dir/ffmpeg-hm-$arch"
install_dir="$install_dir-hm-$arch"
export CC="${CCACHE_BIN:+$CCACHE_BIN }$clang"
export CXX="${CCACHE_BIN:+$CCACHE_BIN }$clangxx"
export AR="$toolchain/llvm-ar" RANLIB="$toolchain/llvm-ranlib"
export NM="$toolchain/llvm-nm" STRINGS="$toolchain/llvm-strings"
export PKG_CONFIG_PATH="$install_dir/lib/pkgconfig"

config=()
if [ "$enable_opt" -eq 0 ]; then
    config+=(--disable-optimizations)
fi
if [ "$enable_x264" -eq 1 ]; then
    # x264's configure rejects the SDK strip probe.
    STRIP=echo "$repo_root/cross/build_x264.sh" \
        "$build_dir/x264-hm-$arch" "$install_dir" aarch64-unknown-linux
    cross_inputs+=("$install_dir/lib/libx264.a")
    config+=(--enable-libx264)
fi

cross_configure \
    --prefix="$install_dir" --target-os=linux --arch=aarch64 --cpu=armv8-a \
    --enable-nonfree --enable-gpl --enable-version3 --disable-doc \
    --cross-prefix="$target-" --cc="$CC" --cxx="$CXX" --ld="$CXX" --as="$CC" \
    --nm="$NM" --ranlib="$RANLIB" --strip="$toolchain/llvm-strip" --ar="$AR" \
    --enable-static --disable-shared --enable-pic \
    --extra-libs=-lm --extra-ldflags=-static-libstdc++ \
    --enable-linux-perf --pkg-config=pkg-config --enable-ohcodec \
    "${config[@]}"

make -j "$jobs"
make install
