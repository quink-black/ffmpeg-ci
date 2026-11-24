#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --help|-h)
            cat <<'EOF'
Usage: cross/wasi_ffmpeg.sh [--path DIR] [--enable_opt 0|1] [--install]
Build and install FFmpeg using the WASI SDK in WASI_SDK_PREFIX.
Optimizations are enabled and installation runs by default.
EOF
            exit 0
            ;;
        --path) cross_value "$@"; ffmpeg_src="$2"; shift 2 ;;
        --enable_opt) cross_value "$@"; cross_bool "$1" "$2"; enable_opt="$2"; shift 2 ;;
        --install) shift ;;
        *) cross_error "Unknown argument: $1" ;;
    esac
done

cross_source_dir
: "${WASI_SDK_PREFIX:?Set WASI_SDK_PREFIX to the WASI SDK directory}"
toolchain="$(cd "$WASI_SDK_PREFIX" && pwd -P)"

ffmpeg_build="$build_dir/ffmpeg-wasi"
install_dir="$install_dir-wasi"
CC="$toolchain/bin/wasm32-wasi-threads-clang"
CXX="$toolchain/bin/wasm32-wasi-threads-clang++"
if [ -n "$CCACHE_BIN" ]; then
    CC="$CCACHE_BIN $CC"
    CXX="$CCACHE_BIN $CXX"
fi
export PKG_CONFIG_PATH="$install_dir/lib/pkgconfig"

config=()
if [ "$enable_opt" -eq 0 ]; then
    config+=(--disable-optimizations)
fi

cross_configure \
    --prefix="$install_dir" \
    --enable-debug --enable-nonfree --enable-gpl --enable-version3 \
    --target-os=none --arch=wasm32 --cross-prefix=wasm32-wasi- \
    --cc="$CC" --cxx="$CXX" --ld="$CXX" --as="$CC" \
    --nm="$toolchain/bin/llvm-nm" --ranlib="$toolchain/bin/llvm-ranlib" --ar="$toolchain/bin/llvm-ar" \
    --enable-static --disable-shared --disable-stripping --disable-doc \
    --disable-network --disable-autodetect --pkg-config=pkg-config \
    --extra-cflags='-D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_PROCESS_CLOCKS -mllvm -wasm-enable-sjlj -msimd128 -pthread' \
    --extra-ldflags='-Wl,--import-memory,--export-memory,--max-memory=4294967296 -Wl,-z,stack-size=10485760' \
    --extra-libs='-lwasi-emulated-signal -lwasi-emulated-process-clocks' \
    --disable-parser=apv --disable-demuxer=apv \
    --samples="$repo_root/ffmpeg-fate-sample" \
    --target-exec='wasmtime --wasi threads --dir=/ ' \
    "${config[@]}"

make -j "$jobs"
make install
