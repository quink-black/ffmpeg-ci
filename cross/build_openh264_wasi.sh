#!/bin/bash

set -e
: "${WASI_SDK_PREFIX:?Set WASI_SDK_PREFIX to the WASI SDK directory}"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source_dir="${1:-${root}/openh264}"
if [ ! -f "${source_dir}/Makefile" ]; then
    echo "OpenH264 Makefile not found in ${source_dir}. Pass its source directory as the first argument." >&2
    exit 1
fi
source_dir="$(cd "$source_dir" && pwd -P)"
toolchain="$(cd "$WASI_SDK_PREFIX" && pwd -P)"
build="${root}/build/openh264-wasi"
mkdir -p "$build"

export AR="$toolchain/bin/llvm-ar"
export CC="$toolchain/bin/wasm32-wasi-threads-clang"
export CXX="$toolchain/bin/wasm32-wasi-threads-clang++"
export RANLIB="$toolchain/bin/llvm-ranlib"
export NM="$toolchain/bin/llvm-nm"
export STRINGS="$toolchain/bin/llvm-strings"

jobs="${FFMPEG_CI_JOBS:-$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN || echo 1)}"
CFLAGS="-D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_PROCESS_CLOCKS -mllvm -wasm-enable-sjlj -pthread" \
    LDFLAGS="-lwasi-emulated-signal -lwasi-emulated-process-clocks -Wl,--import-memory,--export-memory,--max-memory=4294967296" \
    make -C "$build" -f "${source_dir}/Makefile" -j "$jobs" \
        OS=linux ARCH=wasm32 PREFIX="${root}/install-wasi" install-static
