#!/bin/bash

set -e
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

arch=arm64
api=21
enable_x264=0
enable_x265=0
enable_vulkan=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --help|-h)
            cat <<'EOF'
Usage: cross/android_ffmpeg.sh [options]
  --path DIR         FFmpeg source directory (default: ../ffmpeg)
  --arch arm|arm64   Android architecture (default: arm64)
  --api LEVEL        Android API level (default: 21)
  --enable_opt 0|1   Enable optimizations (default: 1)
  --enable_x264 0|1  Build with libx264 (default: 0)
  --enable_x265 0|1  Build with libx265 (default: 0)
  --enable_vulkan 0|1  Build with Vulkan, libplacebo and shaderc (API 24+, default: 0)
  --install          Install after the build (on by default)
EOF
            exit 0
            ;;
        --path) cross_value "$@"; ffmpeg_src="$2"; shift 2 ;;
        --arch) cross_value "$@"; arch="$2"; shift 2 ;;
        --api) cross_value "$@"; api="$2"; shift 2 ;;
        --enable_opt|--enable_x264|--enable_x265|--enable_vulkan)
            cross_value "$@"
            cross_bool "$1" "$2"
            printf -v "${1#--}" '%s' "$2"
            shift 2
            ;;
        --install) shift ;;
        *) cross_error "Unknown argument: $1" ;;
    esac
done

case "$arch" in
    arm)
        abi=armeabi-v7a
        ff_arch=arm
        cpu=armv7-a
        target=armv7a-linux-androideabi
        lib_arch=armeabi-v7a
        ;;
    arm64|aarch64)
        abi=arm64-v8a
        ff_arch=aarch64
        cpu=armv8-a
        target=aarch64-linux-android
        lib_arch=aarch64
        ;;
    *) cross_error "--arch must be arm or arm64" ;;
esac
case "$api" in
    ''|0*|*[!0-9]*) cross_error "--api must be a positive integer" ;;
esac
if [ "$enable_vulkan" -eq 1 ] && [ "$api" -lt 24 ]; then
    cross_error "--enable_vulkan requires --api 24 or newer"
fi
case "$(uname -s)" in
    Linux) host=linux-x86_64 ;;
    Darwin) host=darwin-x86_64 ;;
    *) cross_error "Unsupported Android NDK host" ;;
esac

cross_source_dir
: "${ANDROID_NDK:?Set ANDROID_NDK to the Android NDK directory}"
ndk="$(cd "$ANDROID_NDK" && pwd -P)"
toolchain="$ndk/toolchains/llvm/prebuilt/$host/bin"
clang="$toolchain/$target$api-clang"
clangxx="$toolchain/$target$api-clang++"
[ -x "$clang" ] || cross_error "Android compiler not found: $clang"

ffmpeg_build="$build_dir/ffmpeg-$lib_arch"
install_dir="$install_dir-$lib_arch"
export CC="${CCACHE_BIN:+$CCACHE_BIN }$clang"
export CXX="${CCACHE_BIN:+$CCACHE_BIN }$clangxx"
export AR="$toolchain/llvm-ar" RANLIB="$toolchain/llvm-ranlib"
export NM="$toolchain/llvm-nm" STRINGS="$toolchain/llvm-strings"
export CROSS_PREFIX="$target-"
export PKG_CONFIG_PATH="$install_dir/lib/pkgconfig"
export CFLAGS='' CXXFLAGS='' LDFLAGS=''

config=()
cflags=''
ldflags=''
if [ "$enable_vulkan" -eq 1 ]; then
    shaderc="$repo_root/prebuilt_android/$lib_arch"
    [ -f "$shaderc/libshaderc.a" ] || cross_error "Missing shaderc archive in $shaderc"
    cflags="-I$repo_root/vulkan_header/include -I$repo_root/prebuilt_android/include"
    ldflags="-L$shaderc -lshaderc -lvulkan"
    export PKG_CONFIG_PATH="$shaderc/pkgconfig:$PKG_CONFIG_PATH"

    placebo_build="$build_dir/libplacebo-android-$lib_arch"
    mkdir -p "$placebo_build"
    cross_file="$placebo_build/android.ini"
    cat > "$cross_file" <<EOF
[binaries]
c = '$clang'
cpp = '$clangxx'
ar = '$AR'
strip = '$toolchain/llvm-strip'
pkg-config = 'pkg-config'

[properties]
needs_exe_wrapper = true
pkg_config_libdir = ['$shaderc/pkgconfig', '$install_dir/lib/pkgconfig']

[host_machine]
system = 'android'
cpu_family = '$ff_arch'
cpu = '$cpu'
endian = 'little'
EOF
    meson_args=()
    if [ -f "$placebo_build/meson-private/coredata.dat" ]; then
        meson_args+=(--reconfigure)
    fi
    "$meson_bin" setup "${meson_args[@]}" "$placebo_build" "$repo_root/libplacebo" \
        --cross-file "$cross_file" --prefix "$install_dir" --libdir lib \
        --wrap-mode=nodownload -Ddefault_library=static -Ddemos=false
    ninja -C "$placebo_build" -j "$jobs" install

    # FFmpeg links the Vulkan loader and shaderc when it consumes static libplacebo.
    pc="$install_dir/lib/pkgconfig/libplacebo.pc"
    sed 's/^Libs: .*/& -pthread -lvulkan/' "$pc" > "$pc.tmp"
    mv "$pc.tmp" "$pc"
    cross_inputs+=("$install_dir/lib/libplacebo.a" "$shaderc/libshaderc.a")
    config+=(--enable-vulkan --enable-libplacebo)
    if grep -q -- '--enable-libshaderc ' "$ffmpeg_src/configure"; then
        config+=(--enable-libshaderc)
    fi
else
    config+=(--disable-vulkan)
fi

if [ "$enable_x264" -eq 1 ]; then
    # x264's configure rejects the NDK strip probe.
    STRIP=echo "$repo_root/cross/build_x264.sh" \
        "$build_dir/x264-android-$abi" "$install_dir" "$target"
    cross_inputs+=("$install_dir/lib/libx264.a")
    config+=(--enable-libx264)
fi

if [ "$enable_x265" -eq 1 ]; then
    x265_build="$build_dir/x265-android-$abi"
    cmake -G Ninja -S "$repo_root/x265/source" -B "$x265_build" \
        --toolchain "$ndk/build/cmake/android.toolchain.cmake" \
        -DASM_FLAGS="--target=$target$api" -DENABLE_CLI=OFF \
        -DCMAKE_INSTALL_PREFIX="$install_dir" -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DENABLE_SHARED=OFF -DANDROID_ABI="$abi" -DANDROID_STL=c++_static \
        -DANDROID_PLATFORM="android-$api"
    cmake --build "$x265_build" --parallel "$jobs"
    cmake --install "$x265_build"
    cross_inputs+=("$install_dir/lib/libx265.a")
    config+=(--enable-libx265)
fi

if [ "$enable_opt" -eq 0 ]; then
    config+=(--enable-debug --disable-optimizations)
fi

cross_configure \
    --prefix="$install_dir" --target-os=android --arch="$ff_arch" --cpu="$cpu" \
    --enable-nonfree --enable-gpl --enable-version3 --disable-doc \
    --cross-prefix="$CROSS_PREFIX" --cc="$CC" --cxx="$CXX" --ld="$CXX" --as="$CC" \
    --nm="$NM" --ranlib="$RANLIB" --strip="$toolchain/llvm-strip" --ar="$AR" \
    --enable-static --disable-shared --enable-pic \
    --extra-cflags="$cflags" --extra-ldflags="-static-libstdc++ $ldflags" --extra-libs=-lm \
    --enable-linux-perf --enable-mediacodec --enable-jni --pkg-config=pkg-config \
    "${config[@]}"

make -j "$jobs"
make install
