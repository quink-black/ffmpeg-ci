#!/bin/bash

TOOLCHAIN="${WASI_SDK_PREFIX}"

export AR=$TOOLCHAIN/bin/llvm-ar
export CC=$TOOLCHAIN/bin/wasm32-wasi-threads-clang
export CXX=$TOOLCHAIN/bin/wasm32-wasi-threads-clang++
export RANLIB=$TOOLCHAIN/bin/llvm-ranlib
export NM=$TOOLCHAIN/bin/llvm-nm
export STRINGS=$TOOLCHAIN/bin/llvm-strings

CFLAGS="-D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_PROCESS_CLOCKS -mllvm -wasm-enable-sjlj -pthread" \
    LDFLAGS="-lwasi-emulated-signal -lwasi-emulated-process-clocks -Wl,--import-memory,--export-memory,--max-memory=4294967296" \
    make OS=linux ARCH=wasm32  PREFIX="$PWD/install-wasi" -C openh264 -j10 install-static
