#!/bin/bash
# shellcheck disable=SC2154,SC2034
set -e

# Resolve the directory containing this script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${DIR:=${SCRIPT_DIR}}"

# Source env.sh for build_dir / install_dir / host tool paths.
# CC / CXX / AR / RANLIB / NM / PKG_CONFIG_PATH are overridden below
# for the Android cross-toolchain; env.sh values are for the host only.
source "${DIR}/env.sh"

# ---------------------------------------------------------------------------
# Default variables
# ---------------------------------------------------------------------------
ffmpeg_src="${DIR}/../ffmpeg"
do_install=1
arch="arm64"
enable_opt=0
enable_x264=0
enable_x265=0

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case $1 in
        --help)
            echo "Usage: android_ffmpeg.sh [options]"
            echo ""
            echo "Options:"
            echo "  --path DIR           FFmpeg source directory (default: ../ffmpeg)"
            echo "  --arch ARCH          CPU architecture: arm, arm64 (default: arm64)"
            echo "  --install            Install after build (default: on)"
            echo "  --enable_opt 0|1     Enable optimizations (debug build if 0)"
            echo "  --enable_x264 0|1    Build and enable libx264"
            echo "  --enable_x265 0|1    Build and enable libx265"
            exit 0
            ;;
        --path)
            ffmpeg_src="$2"
            shift
            ;;
        --arch)
            arch="$2"
            shift
            ;;
        --enable_opt)
            enable_opt="$2"
            echo "enable_opt ${enable_opt}"
            shift
            ;;
        --enable_x264)
            enable_x264="$2"
            echo "enable_x264 ${enable_x264}"
            shift
            ;;
        --enable_x265)
            enable_x265="$2"
            echo "enable_x265 ${enable_x265}"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
    shift
done

if ! [ -d "${ffmpeg_src}" ]; then
    echo "Directory ${ffmpeg_src} not found"
    exit 1
fi

# Convert to absolute path so it remains valid after pushd
ffmpeg_src="$(cd "${ffmpeg_src}" && pwd)"

# ---------------------------------------------------------------------------
# Android toolchain setup
# ---------------------------------------------------------------------------
if [ "$(uname)" = 'Linux' ]; then
    TOOLCHAIN="${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64"
elif [ "$(uname)" = 'Darwin' ]; then
    TOOLCHAIN="${ANDROID_NDK}/toolchains/llvm/prebuilt/darwin-x86_64"
else
    echo "Unsupported platform"
    exit 1
fi

if [ "$arch" = "arm" ]; then
    ANDROID_ABI="armeabi-v7a"
    TARGET=armv7a-linux-androideabi
    CPU=armv7-a
    API=24
    TERMUX_ARCH="arm"
elif [ "$arch" = "arm64" ] || [ "$arch" = "aarch64" ]; then
    ANDROID_ABI="aarch64"
    TARGET=aarch64-linux-android
    CPU=armv8-a
    API=24
    TERMUX_ARCH="${ANDROID_ABI}"
else
    echo "Unknown arch ${arch}"
    exit 1
fi

ffmpeg_build="${build_dir}/ffmpeg-${ANDROID_ABI}"
install_dir="${install_dir}-${ANDROID_ABI}"

export AR="${TOOLCHAIN}/bin/llvm-ar"
export CC="${TOOLCHAIN}/bin/${TARGET}${API}-clang"
export CXX="${TOOLCHAIN}/bin/${TARGET}${API}-clang++"
export RANLIB="${TOOLCHAIN}/bin/llvm-ranlib"
export NM="${TOOLCHAIN}/bin/llvm-nm"
export STRINGS="${TOOLCHAIN}/bin/llvm-strings"

export CROSS_PREFIX="${TARGET}-"
export HOST="${TARGET}"

export CFLAGS="-I${DIR}/vulkan_header/include"
export LDFLAGS="-L${DIR}/prebuilt_android/${ANDROID_ABI} -lshaderc -lvulkan"
export PKG_CONFIG_PATH="${DIR}/prebuilt_android/${ANDROID_ABI}/pkgconfig:${install_dir}/lib/pkgconfig"
export PKG_CONFIG=pkg-config

if which ccache >/dev/null 2>&1; then
    export CC="ccache ${CC}"
    export CXX="ccache ${CXX}"
fi

# ---------------------------------------------------------------------------
# Build third-party dependencies for Android
# ---------------------------------------------------------------------------
mkdir -p "${build_dir}"

source "${DIR}/setup_meson.sh"
termux_setup_meson

# libplacebo (always built for Android)
pushd "${DIR}/libplacebo" > /dev/null
"${DIR}/meson/meson.py" setup \
    "${build_dir}/libplacebo-${ANDROID_ABI}" \
    --cross-file "${TERMUX_MESON_CROSSFILE}" \
    -Ddefault_library=static \
    -Ddemos=false \
    --prefix="${install_dir}" \
    --libdir="${install_dir}/lib"

ninja -C "${build_dir}/libplacebo-${ANDROID_ABI}" install
# Patch libplacebo.pc to include transitive deps that meson omits
sed -i 's/Libs.*$/Libs: -L${libdir} -lplacebo -lm -pthread -ldl -lvulkan/' \
    "${install_dir}/lib/pkgconfig/libplacebo.pc"
popd > /dev/null

if [ "${enable_x264}" -eq 1 ]; then
    # x264's configure rejects the Android strip; use a no-op during build
    export STRIP=echo
    ./build_x264.sh
fi
export STRIP="${TOOLCHAIN}/bin/llvm-strip"

if [ "${enable_x265}" -eq 1 ]; then
    x265_src="${DIR}/x265/source"

    pushd "${x265_src}" > /dev/null
    cmake -G Ninja \
        --toolchain "${ANDROID_NDK}/build/cmake/android.toolchain.cmake" \
        -DASM_FLAGS="--target=${TARGET}${API}" \
        -DENABLE_CLI=OFF \
        -DCMAKE_INSTALL_PREFIX="${install_dir}" \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DENABLE_SHARED=OFF \
        -DANDROID_ABI="${ANDROID_ABI}" \
        -DANDROID_STL=c++_static \
        -DANDROID_PLATFORM=android-21 \
        -B "${build_dir}/x265"
    popd > /dev/null

    ninja -C "${build_dir}/x265" install
fi

# ---------------------------------------------------------------------------
# FFmpeg configure and build
# ---------------------------------------------------------------------------
extra_config=""

# Vulkan and shaderc are always available via prebuilt Android libs
extra_config+=" --enable-vulkan"
if grep -q -- '--enable-libshaderc ' "${FFMPEG_SRC}/configure"; then
    extra_config+=" --enable-libshaderc"
fi

# libplacebo was built above; always enable it
extra_config+=" --enable-libplacebo"

if [ "${enable_x264}" -eq 1 ]; then
    extra_config+=" --enable-libx264"
fi

if [ "${enable_x265}" -eq 1 ]; then
    extra_config+=" --enable-libx265"
fi

if [ "${enable_opt}" -eq 0 ]; then
    extra_config+=" --enable-debug --disable-optimizations"
fi

NPROC=$(nproc 2>/dev/null || sysctl -n hw.logicalcpu)

pushd "${build_dir}" > /dev/null

rm -Rf "${ffmpeg_build}"
mkdir -p "${ffmpeg_build}"
pushd "${ffmpeg_build}" > /dev/null

# shellcheck disable=SC2086
"${ffmpeg_src}/configure" \
    --prefix="${install_dir}" \
    --enable-nonfree \
    --enable-gpl \
    --enable-version3 \
    --disable-doc \
    --target-os=android \
    --cross-prefix="${TARGET}-" \
    --arch="${ANDROID_ABI}" \
    --cpu="${CPU}" \
    --cc="${CC}" \
    --cxx="${CXX}" \
    --ld="${CXX}" \
    --as="${CC}" \
    --nm="${NM}" \
    --ranlib="${RANLIB}" \
    --strip="${STRIP}" \
    --ar="${AR}" \
    --enable-static \
    --disable-shared \
    --enable-pic \
    --extra-libs="-lm" \
    --extra-ldflags="-static-libstdc++" \
    --enable-linux-perf \
    --enable-mediacodec \
    --enable-jni \
    --pkg-config=pkg-config \
    --extra-cflags="${CFLAGS}" \
    --extra-ldflags="${LDFLAGS}" \
    ${extra_config}

make -j "${NPROC}"

if [ "${do_install}" -eq 1 ]; then
    make install
fi

popd > /dev/null

popd > /dev/null
