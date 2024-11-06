#!/bin/bash

set -e

source env.sh

ffmpeg_build=${build_dir}/ffmpeg

# default path of ffmpeg source code
ffmpeg_src=${DIR}/../ffmpeg
do_install=1
enable_opt=0
while [ $# -gt 0 ]; do
    case $1 in
        --help)
            echo "Use --path to specify ffmpeg source directory"
            echo "Use --install to install after build"
            exit 1
            ;;
        --path)
            ffmpeg_src=$2
            shift
            ;;
        --config_opt)
            enable_opt=$2
            echo "enable_opt $enable_opt"
            shift
            ;;
    esac
    shift
done

if ! [ -d ${ffmpeg_src} ]; then
    echo "Directory $ffmpeg_src not found"
    exit 1
fi

extra_config=" "

if [ -z "${WASI_SDK_PREFIX}" ]; then
    echo "Please set WASI_SDK_PREFIX env"
    exit 1
fi

TOOLCHAIN="${WASI_SDK_PREFIX}"

TARGET=wasm32-wasi

ffmpeg_build="${ffmpeg_build}-wasi"
install_dir="${install_dir}-wasi"

export AR=$TOOLCHAIN/bin/llvm-ar
export CC=$TOOLCHAIN/bin/clang
export CXX=$TOOLCHAIN/bin/clang++
export RANLIB=$TOOLCHAIN/bin/llvm-ranlib
export NM=$TOOLCHAIN/bin/llvm-nm
export STRINGS=$TOOLCHAIN/bin/llvm-strings

export CROSS_PREFIX=${TARGET}-
export HOST=${TARGET}

export PKG_CONFIG=pkg-config
mkdir -p $build_dir

pushd $build_dir

rm -Rf ${ffmpeg_build}
mkdir -p ${ffmpeg_build}
pushd ${ffmpeg_build}

if [ "$enable_opt" -eq 0 ]; then
    extra_config="${extra_config} --disable-optimizations --enable-debug"
fi

$ffmpeg_src/configure \
    --prefix=$install_dir \
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
    --disable-pthreads \
    --disable-network \
    --disable-protocol=fd \
    --disable-protocol=pipe \
    --disable-autodetect \
    --extra-cflags='-D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_PROCESS_CLOCKS' \
    --extra-libs='-lwasi-emulated-signal -lwasi-emulated-process-clocks' \
    ${extra_config} \

make -j $(nproc)

if [ "$do_install" -eq 1 ]; then
    make install
fi

popd # ${ffmpeg_build}

popd
