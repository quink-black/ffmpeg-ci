#!/bin/bash

set -e

ffmpeg_build=${build_dir}/ffmpeg
fate_samples=${DIR}/ffmpeg-fate-sample

# default path of ffmpeg source code
ffmpeg_src=${DIR}/../ffmpeg
do_test=0
do_install=0
skip_test_case=""
enable_asan=0
enable_opt=0
while [ $# -gt 0 ]; do
    case $1 in
        --help)
            echo "Use --path to specify ffmpeg source directory"
            echo "Use --test to run fate test"
            echo "Use --install to install after build"
            echo "Use --skip_test_case to skip some test cases, separated by comma"
            echo "Use --enable_asan 1 to enable address sanitizer"
            exit 1
            ;;
        --path)
            ffmpeg_src=$2
            shift
            ;;
        --test)
            do_test=1
            ;;
        --install)
            do_install=1
            ;;
        --skip_test_case)
            skip_test_case=$2
            shift
            ;;
        --enable_asan)
            enable_asan=$2
            echo "enable_asan $enable_asan"
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

if ! [ -d ${ffmpeg_src} ]; then
    echo "Directory $ffmpeg_src not found"
    exit 1
fi

source ${DIR}/env.sh

extra_config=" "
extra_ldflags=" "
extra_libs=""

extra_libs="$extra_libs -pthread"
extra_config="${extra_config} --enable-libdavs2"

if grep -q enable-libav1d ${ffmpeg_src}/configure; then
    if [ -d ${install_dir}/include/av1d ]; then
        extra_config="${extra_config} --enable-libav1d"
    fi
fi

#if grep -q able-libglslang ${ffmpeg_src}/configure && [ -d '/usr/local/include/glslang/Include' ]; then
#    extra_config="${extra_config} --enable-libglslang"
#fi
if grep -q able-libshaderc ${ffmpeg_src}/configure && pkg-config --exists shaderc; then
    extra_config="${extra_config} --enable-libshaderc"
fi

if grep -q libplacebo ${ffmpeg_src}/configure && pkg-config --exists libplacebo "libplacebo >= 4.192.0"; then
    extra_config="${extra_config} --enable-libplacebo --enable-vulkan"
fi

if grep -q able-libzimg ${ffmpeg_src}/configure && pkg-config --exists zimg; then
    extra_config="${extra_config} --enable-libzimg"
fi

if grep -q enable-libuavs3d ${ffmpeg_src}/configure; then
    extra_config="${extra_config} --enable-libuavs3d"
fi

#if grep -q enable-libvvdec ${ffmpeg_src}/configure; then
#    extra_config="${extra_config} --enable-libvvdec"
#fi

if pkg-config --exists libass; then
    extra_config="${extra_config} --enable-libass"
fi

if [ "$enable_asan" -eq 1 ]; then
    if cc -v 2>&1 |grep 'clang version' -q; then
        extra_config="--toolchain=clang-asan ${extra_config}"
    else
        extra_config="--toolchain=gcc-asan ${extra_config}"
        extra_ldflags="${extra_ldflags} -static-libasan"
    fi
fi

if which nvcc; then
    extra_config="${extra_config} --enable-cuda-nvcc"
fi

if [ "$enable_opt" -eq 0 ]; then
    extra_config="${extra_config} --enable-debug --disable-optimizations"
fi

mkdir -p $build_dir

pushd $build_dir

rm -Rf ${ffmpeg_build}
mkdir -p ${ffmpeg_build}
pushd ${ffmpeg_build}

$ffmpeg_src/configure \
    --prefix=$install_dir \
    --extra-cflags="-I${install_dir}/include" \
    --extra-ldflags="-L${install_dir}/lib ${extra_ldflags}" \
    --extra-libs="-lstdc++ $extra_libs -lm" \
    --pkg-config-flags='--static' \
    --enable-libvmaf \
    --enable-libx264 \
    --enable-libx265 \
    --enable-libdav1d \
    --enable-nonfree \
    --enable-gpl \
    --enable-version3 \
    --enable-libfreetype \
    --enable-libfontconfig \
    --enable-libsrt \
    --enable-libxml2 \
    --enable-openssl \
    --disable-doc \
    --samples=${fate_samples} \
    --ignore-tests="${skip_test_case}" \
    --disable-stripping \
    ${extra_config} 


make -j $(nproc)

if [ "$do_test" -eq 1 ]; then
    make fate-rsync -j $(nproc)
    VERBOSE=1 make fate -j $(nproc)
fi

if [ "$do_install" -eq 1 ]; then
    make install
fi

popd # ${ffmpeg_build}

popd
