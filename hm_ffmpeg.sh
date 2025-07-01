#!/bin/bash

set -e

source env.sh

ffmpeg_build=${build_dir}/ffmpeg

# default path of ffmpeg source code
ffmpeg_src=${DIR}/../ffmpeg
do_install=1
arch="arm64"
enable_opt=0
enable_x264=0
while [ $# -gt 0 ]; do
    case $1 in
        --help)
            echo "Use --path to specify ffmpeg source directory"
            echo "Use --install to install after build"
            echo "Use --arch to specify cpu arch (arm, arm64)"
            exit 1
            ;;
        --path)
            ffmpeg_src=$2
            shift
            ;;
        --arch)
            arch=$2
            shift
            ;;
        --enable_opt)
            enable_opt=$2
            echo "enable_opt $enable_opt"
            shift
            ;;
        --enable_x264)
            enable_x264=$2
            echo "enable_x264 $enable_x264"
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

TOOLCHAIN=$OHOS_SDK_NATIVE/llvm

if [ "$arch" = "arm64" ] || [ "$arch" = "aarch64" ]; then
    OHOS_ARCH="arm64-v8a"
    TARGET=aarch64-unknown-linux-ohos
    CPU=armv8-a
else
    echo "Unknown arch $arch"
    exit 1
fi

ffmpeg_build="${ffmpeg_build}-hm-${arch}"
install_dir="${install_dir}-hm-${arch}"

export AR=$TOOLCHAIN/bin/llvm-ar
export CC=$TOOLCHAIN/bin/$TARGET-clang
export CXX=$TOOLCHAIN/bin/$TARGET-clang++
export AR=$TOOLCHAIN/bin/llvm-ar
export RANLIB=$TOOLCHAIN/bin/llvm-ranlib
export NM=$TOOLCHAIN/bin/llvm-nm
export STRINGS=$TOOLCHAIN/bin/llvm-strings
export STRIP=$TOOLCHAIN/bin/llvm-strip
export PKG_CONFIG_PATH="${install_dir}/lib/pkgconfig"
export PKG_CONFIG=pkg-config

if which ccache; then
    export CC="ccache $CC"
    export CXX="ccache $CXX"
fi

if [ "$enable_x264" -eq 1 ]; then
    # x264 strip有些错误，做个假的strip
    STRIP=echo HOST=aarch64-unknown-linux ./build_x264.sh
fi

mkdir -p $build_dir

pushd $build_dir

rm -Rf ${ffmpeg_build}
mkdir -p ${ffmpeg_build}
pushd ${ffmpeg_build}

if [ "$enable_opt" -eq 0 ]; then
    extra_config="${extra_config} --disable-optimizations"
fi

if [ "$enable_x264" -eq 1 ]; then
    extra_config="${extra_config} --enable-libx264"
fi

$ffmpeg_src/configure \
    --prefix=$install_dir \
    --enable-nonfree \
    --enable-gpl \
    --enable-version3 \
    --disable-doc \
    --target-os=linux \
    --cross-prefix=${TARGET}- \
    --arch=$arch \
    --cpu=$CPU \
    --cc="$CC" \
    --cxx="$CXX" \
    --ld="$CXX" \
    --as="$CC" \
    --nm=$NM \
    --ranlib=$RANLIB \
    --strip=$STRIP \
    --ar=$AR \
    --enable-static --disable-shared \
    --enable-pic \
    --extra-libs="-lm" \
    --extra-ldflags="-static-libstdc++" \
    --enable-linux-perf \
    --pkg-config=pkg-config \
    --enable-ohcodec \
    ${extra_config} \

make -j $(nproc)

if [ "$do_install" -eq 1 ]; then
    make install
fi

popd # ${ffmpeg_build}

popd
