#!/bin/bash

set -e

source env.sh

ffmpeg_build=${build_dir}/ffmpeg
fate_samples=${DIR}/ffmpeg-fate-sample

# default path of ffmpeg source code
ffmpeg_src=${DIR}/../ffmpeg
do_install=1
enable_opt=1
build_target=node  # node or chrome
while [ $# -gt 0 ]; do
    case $1 in
        --help)
            echo "Usage: $0 [options]"
            echo "  --path <dir>        Specify ffmpeg source directory"
            echo "  --target <node|chrome>  Build target environment (default: node)"
            echo "  --enable_opt <0|1>  Enable optimizations (default: 1)"
            exit 1
            ;;
        --path)
            ffmpeg_src=$2
            shift
            ;;
        --target)
            build_target=$2
            shift
            ;;
        --enable_opt)
            enable_opt=$2
            echo "enable_opt $enable_opt"
            shift
            ;;
    esac
    shift
done

if [ "$build_target" != "node" ] && [ "$build_target" != "chrome" ]; then
    echo "Error: --target must be 'node' or 'chrome', got '$build_target'"
    exit 1
fi

echo "Build target: $build_target"

if ! [ -d ${ffmpeg_src} ]; then
    echo "Directory $ffmpeg_src not found"
    exit 1
fi

extra_config=" "

if [ -z "${EMSDK}" ]; then
    echo "Please set EMSDK env"
    exit 1
fi

TOOLCHAIN="${EMSDK}/upstream"

TARGET=wasm32

ffmpeg_build="${ffmpeg_build}-wasm-${build_target}"
install_dir="${install_dir}-wasm-${build_target}"

export AR=$TOOLCHAIN/bin/llvm-ar
export CC=$TOOLCHAIN/emscripten/emcc
export CXX=$TOOLCHAIN/emscripten/em++
export RANLIB=$TOOLCHAIN/bin/llvm-ranlib
export NM=$TOOLCHAIN/bin/llvm-nm
export STRINGS=$TOOLCHAIN/bin/llvm-strings

export CROSS_PREFIX=${TARGET}-
export HOST=${TARGET}

export PKG_CONFIG_PATH="${install_dir}/lib/pkgconfig"
mkdir -p $build_dir

pushd $build_dir

rm -Rf ${ffmpeg_build}
mkdir -p ${ffmpeg_build}
pushd ${ffmpeg_build}

if [ "$enable_opt" -eq 0 ]; then
    extra_config="${extra_config} --disable-optimizations"
fi

# Node.js: NODERAWFS for direct host filesystem access (like wasmtime --dir=/)
# Chrome: virtual FS only, disable fd/pipe protocols unsupported in browser
extra_ldflags='-s INITIAL_MEMORY=256MB -s ALLOW_MEMORY_GROWTH=1 -s MAXIMUM_MEMORY=4GB -s MALLOC=emmalloc -s STACK_OVERFLOW_CHECK=1 -s ASSERTIONS=1 -s STACK_SIZE=10MB -s ASYNCIFY_STACK_SIZE=65536 -s EXPORTED_RUNTIME_METHODS=["FS","callMain"] -s PTHREAD_POOL_SIZE=8'

if [ "$build_target" = "node" ]; then
    extra_ldflags="${extra_ldflags} -s NODERAWFS=1"
    extra_config="${extra_config} --samples=${fate_samples}"
    extra_config="${extra_config} --target-exec=${DIR}/emsdk-test/run-node.sh"
else
    extra_config="${extra_config} --disable-protocol=fd"
    extra_config="${extra_config} --disable-protocol=pipe"
fi

$ffmpeg_src/configure \
    --prefix=$install_dir \
    --enable-debug \
    --enable-nonfree \
    --enable-gpl \
    --enable-version3 \
    --target-os=none \
    --arch=wasm32 \
    --cross-prefix=${TARGET}- \
    --cc=$CC \
    --cxx=$CXX \
    --ld=$CXX \
    --as=$CC \
    --nm=$NM \
    --ranlib=$RANLIB \
    --ar=$AR \
    --enable-static --disable-shared \
    --disable-stripping \
    --disable-doc \
    --disable-network \
    --disable-autodetect \
    --extra-cflags='-msimd128 -pthread' \
    --extra-ldflags="${extra_ldflags}" \
    --extra-libs='' \
    --pkg-config=pkg-config \
    ${extra_config} \

make -j $(nproc)

if [ "$build_target" = "node" ]; then
    # Append module.exports so Node.js require() returns the Module object.
    # Without this, require() returns {} because emscripten uses 'var Module'
    # which is local to the CommonJS module scope.
    echo '' >> ffmpeg_g
    echo 'if (typeof module !== "undefined" && module.exports) module.exports = Module;' >> ffmpeg_g

    make tests/checkasm/checkasm
fi

if [ "$do_install" -eq 1 ]; then
    make install
fi

popd # ${ffmpeg_build}

popd
