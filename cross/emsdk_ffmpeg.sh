#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

build_target=node
while [ "$#" -gt 0 ]; do
    case "$1" in
        --help|-h)
            cat <<'EOF'
Usage: cross/emsdk_ffmpeg.sh [--path DIR] [--target node|chrome] [--enable_opt 0|1]
Build and install FFmpeg using the Emscripten SDK in EMSDK.
The target defaults to node and optimizations are enabled by default.
EOF
            exit 0
            ;;
        --path) cross_value "$@"; ffmpeg_src="$2"; shift 2 ;;
        --target) cross_value "$@"; build_target="$2"; shift 2 ;;
        --enable_opt) cross_value "$@"; cross_bool "$1" "$2"; enable_opt="$2"; shift 2 ;;
        *) cross_error "Unknown argument: $1" ;;
    esac
done

case "$build_target" in
    node|chrome) ;;
    *) cross_error "--target must be node or chrome" ;;
esac
cross_source_dir
: "${EMSDK:?Set EMSDK by sourcing emsdk_env.sh}"
toolchain="$(cd "$EMSDK/upstream" && pwd -P)"

ffmpeg_build="$build_dir/ffmpeg-wasm-$build_target"
install_dir="$install_dir-wasm-$build_target"
CC="$toolchain/emscripten/emcc"
CXX="$toolchain/emscripten/em++"
export PKG_CONFIG_PATH="$install_dir/lib/pkgconfig"

config=()
# Pthreads need shared memory at link time. The main and worker stacks are separate.
ldflags='-pthread -s INITIAL_MEMORY=256MB -s ALLOW_MEMORY_GROWTH=1 -s MAXIMUM_MEMORY=4GB -s STACK_SIZE=10MB -s EXPORTED_RUNTIME_METHODS=FS,callMain -s PTHREAD_POOL_SIZE=8'
if [ "$enable_opt" -eq 0 ]; then
    config+=(--disable-optimizations)
    ldflags+=" -s ASSERTIONS=1 -s STACK_OVERFLOW_CHECK=1"
fi

if [ "$build_target" = node ]; then
    ldflags+=" -s NODERAWFS=1"
    config+=(--samples="$repo_root/ffmpeg-fate-sample" --target-exec="$repo_root/emsdk-test/run-node.sh")
else
    config+=(--disable-protocol=fd --disable-protocol=pipe)
fi

cross_configure \
    --prefix="$install_dir" \
    --enable-debug --enable-nonfree --enable-gpl --enable-version3 \
    --target-os=none --arch=wasm32 --cross-prefix=wasm32- \
    --cc="$CC" --cxx="$CXX" --ld="$CXX" --as="$CC" \
    --nm="$toolchain/bin/llvm-nm" --ranlib="$toolchain/bin/llvm-ranlib" --ar="$toolchain/bin/llvm-ar" \
    --enable-static --disable-shared --disable-stripping --disable-doc \
    --disable-network --disable-autodetect --pkg-config=pkg-config \
    --extra-cflags='-msimd128 -pthread' --extra-ldflags="$ldflags" \
    "${config[@]}"

make -j "$jobs"
if [ "$build_target" = node ]; then
    # The Emscripten glue keeps Module local to the CommonJS file.
    node_export='if (typeof module !== "undefined" && module.exports) module.exports = Module;'
    if ! grep -Fxq "$node_export" ffmpeg_g; then
        printf '\n%s\n' "$node_export" >> ffmpeg_g
    fi
    make -j "$jobs" tests/checkasm/checkasm
fi
make install
