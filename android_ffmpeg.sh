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
        --config_opt)
            enable_opt=$2
            echo "enable_opt $enable_opt"
            shift
            ;;
        --config_x264)
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

if [ $(uname) = 'Linux' ]; then
    TOOLCHAIN=$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64
elif [ $(uname) = 'Darwin' ]; then
    TOOLCHAIN=$ANDROID_NDK/toolchains/llvm/prebuilt/darwin-x86_64
else
    echo "Unsupported platform"
    exit 1
fi

if [ "$arch" = "arm" ]; then
    ANDROID_ABI="armeabi-v7a"
    TARGET=armv7a-linux-androideabi
    CPU=armv7-a
    API=17
elif [ "$arch" = "arm64" ] || [ "$arch" = "aarch64" ]; then
    ANDROID_ABI="aarch64"
    TARGET=aarch64-linux-android
    CPU=armv8-a
    # Set this to your minSdkVersion.
    API=24
else
    echo "Unknown arch $arch"
    exit 1
fi

ffmpeg_build="$ffmpeg_build-$ANDROID_ABI"

export AR=$TOOLCHAIN/bin/llvm-ar
export CC=$TOOLCHAIN/bin/$TARGET$API-clang
export CXX=$TOOLCHAIN/bin/$TARGET$API-clang++
export AS=$CC
export LD=$CC
export AR=$TOOLCHAIN/bin/llvm-ar
export RANLIB=$TOOLCHAIN/bin/llvm-ranlib
export NM=$TOOLCHAIN/bin/llvm-nm
export STRINGS=$TOOLCHAIN/bin/llvm-strings

export CROSS_PREFIX=${TARGET}-
export HOST=${TARGET}

if [ "$enable_x264" -eq 1 ]; then
    # x264 strip有些错误，做个假的strip
    export STRIP=echo
    ./build_x264.sh
fi
export STRIP=$TOOLCHAIN/bin/llvm-strip

mkdir -p $build_dir
pushd $build_dir

rm -Rf ${ffmpeg_build}
mkdir -p ${ffmpeg_build}
pushd ${ffmpeg_build}

extra_config=" "
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
    --target-os=android \
    --cross-prefix=${TARGET}- \
    --arch=$ANDROID_ABI \
    --cpu=$CPU \
    --cc=$CC \
    --cxx=$CXX \
    --as=$AS \
    --nm=$NM \
    --ranlib=$RANLIB \
    --strip=$STRIP \
    --ar=$AR \
    --enable-static --disable-shared \
    --enable-pic \
    --extra-libs="-lm" \
    --disable-linux-perf \
    --enable-mediacodec \
    --enable-jni \
    --pkg-config=pkg-config \
    --disable-vulkan \
    ${extra_config} \


make -j $(nproc)

if [ "$do_install" -eq 1 ]; then
    make install
fi

popd # ${ffmpeg_build}

popd
