#!/bin/bash

set -e

# Resolve the directory containing this script so the script can be run
# directly (e.g. from CLion) without requiring DIR to be pre-set by a
# parent script like cibuild.sh.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${DIR:=${SCRIPT_DIR}}"

# Source env.sh early so build_dir / install_dir / CC / etc. are available
# regardless of whether this script is invoked standalone or via cibuild.sh.
source ${DIR}/env.sh

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

# Convert to absolute path so it remains valid after pushd
ffmpeg_src="$(cd "${ffmpeg_src}" && pwd)"

source ${DIR}/env.sh

extra_config=" "
extra_cflags="-I${install_dir}/include"
extra_ldflags=" "
extra_libs=""

extra_libs="$extra_libs -pthread"

#if which cl.exe; then
#    extra_config="${extra_config} --target-os=win64 --toolchain=msvc"
#fi

if grep -q enable-libav1d ${ffmpeg_src}/configure; then
    if [ -d ${install_dir}/include/av1d ]; then
        extra_config="${extra_config} --enable-libav1d"
    fi
fi

if pkg-config --exists SvtAv1Enc; then
    extra_config="${extra_config} --enable-libsvtav1"
fi

if pkg-config --exists vulkan; then
    extra_config="${extra_config} --enable-vulkan"
    #if grep -q able-libglslang ${ffmpeg_src}/configure && [ -d '/usr/local/include/glslang/Include' ]; then
    #    extra_config="${extra_config} --enable-libglslang"
    #fi
    if grep -q able-libshaderc ${ffmpeg_src}/configure && pkg-config --exists shaderc; then
        extra_config="${extra_config} --enable-libshaderc"
    fi

    if grep -q libplacebo ${ffmpeg_src}/configure && pkg-config --exists libplacebo "libplacebo >= 4.192.0"; then
        extra_config="${extra_config} --enable-libplacebo"
    fi
    if pkg-config --exists libdrm; then
        extra_config="${extra_config} --enable-libdrm"
    fi
fi

if pkg-config --exists libmfx; then
    extra_config="${extra_config} --enable-libmfx"
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

if pkg-config --exists fribidi; then
    extra_config="${extra_config} --enable-libfribidi"
fi

if pkg-config --exists davs2; then
    extra_config="${extra_config} --enable-libdavs2"
fi

#if pkg-config --exists openvino; then
#    extra_config="${extra_config} --enable-libopenvino"
#fi

if pkg-config --exists fontconfig; then
    extra_config="${extra_config} --enable-libfreetype --enable-libfontconfig"
fi

if pkg-config --exists harfbuzz; then
    extra_config="${extra_config} --enable-libharfbuzz"
fi

if pkg-config --exists whisper; then
    extra_config="${extra_config} --enable-whisper"
fi

if pkg-config --exists opencv4 && [ "$enable_asan" -eq 0 ]; then
    extra_config="${extra_config} --enable-libopencv"
fi

# Helper: probe if a pkg-config module exists AND a tiny program actually links
# under --static (matches ffmpeg's --pkg-config-flags=--static behavior).
# Skips dependencies whose static transitive libs (e.g. liblzma) are absent.
probe_pkg_static() {
    local mod=$1
    pkg-config --exists "$mod" 2>/dev/null || return 1
    local cflags libs
    cflags=$(pkg-config --cflags "$mod" 2>/dev/null) || return 1
    libs=$(pkg-config --static --libs "$mod" 2>/dev/null) || return 1
    local tmp
    tmp=$(mktemp -d) || return 1
    printf 'int main(void){return 0;}\n' > "$tmp/t.c"
    if ${CC:-cc} $cflags "$tmp/t.c" -o "$tmp/t" $libs >/dev/null 2>&1; then
        rm -rf "$tmp"
        return 0
    fi
    rm -rf "$tmp"
    return 1
}

# Optional system dependencies — enable only when the static link probe passes.
if probe_pkg_static libxml-2.0; then
    extra_config="${extra_config} --enable-libxml2"
fi

if probe_pkg_static openssl; then
    extra_config="${extra_config} --enable-openssl --enable-nonfree"
fi

if probe_pkg_static lcms2; then
    extra_config="${extra_config} --enable-lcms2"
fi

if probe_pkg_static OpenCL; then
    extra_config="${extra_config} --enable-opencl"
fi

if [ "$enable_asan" -eq 1 ]; then
    if ${CC} -v 2>&1 |grep 'clang version' -q; then
        extra_config="--toolchain=clang-asan ${extra_config}"
        # clang/compiler-rt defaults detect_stack_use_after_return to false at
        # runtime, so the fake-stack hot path is not active by default and no
        # extra flag is needed.
        asan_uar_flag=""
    else
        extra_config="--toolchain=gcc-asan ${extra_config}"
        extra_ldflags="${extra_ldflags} -static-libasan"
        # GCC's libsanitizer (e.g. Ubuntu 24.04 gcc-13) defaults
        # detect_stack_use_after_return to true. The __asan_stack_malloc_*
        # helper then dominates hot leaf functions on aarch64 (wavpack
        # wv_get_value, sws_ops kernels), turning a 10s decode into an
        # effectively unbounded run. Disable the instrumentation at compile
        # time so the runtime flag is moot. We trade only stack-use-after-
        # return detection; heap/global/stack-buffer-overflow stays on.
        asan_uar_flag="--param=asan-use-after-return=0"
    fi
    if [ -n "${asan_uar_flag}" ]; then
        # Verify the compiler actually accepts the flag before adopting it.
        asan_probe_dir=$(mktemp -d)
        printf 'int main(void){return 0;}\n' > "${asan_probe_dir}/t.c"
        if ${CC} -fsanitize=address ${asan_uar_flag} \
                "${asan_probe_dir}/t.c" -o "${asan_probe_dir}/t" >/dev/null 2>&1; then
            extra_cflags="${extra_cflags} ${asan_uar_flag}"
        else
            echo "warning: ${CC} rejects ${asan_uar_flag}; ASan stack-use-after-return stays on"
        fi
        rm -rf "${asan_probe_dir}"
    fi
    ffmpeg_build=${ffmpeg_build}_asan
fi

#if which nvcc; then
#    extra_config="${extra_config} --enable-cuda-nvcc"
#fi

if [ "$enable_opt" -eq 0 ]; then
    extra_config="${extra_config} --enable-debug --disable-optimizations"
else
    ffmpeg_build=${ffmpeg_build}_opt
fi

NPROC=$(nproc 2>/dev/null || sysctl -n hw.logicalcpu)

mkdir -p $build_dir

pushd $build_dir

# allow in source build of ffmpeg with msys
if [ -z "$MSYSTEM" ]; then
    # cleanup for non-msys
    rm -Rf ${ffmpeg_build}
fi

mkdir -p ${ffmpeg_build}
pushd ${ffmpeg_build}

$ffmpeg_src/configure \
    --prefix=$install_dir \
    --cc="${CCACHE_BIN:+${CCACHE_BIN} }${CC}" \
    --cxx="${CCACHE_BIN:+${CCACHE_BIN} }${CXX}" \
    --ld="${CXX}" \
    --assert-level=2 \
    --extra-cflags="${extra_cflags}" \
    --extra-ldflags="-L${install_dir}/lib ${extra_ldflags}" \
    --extra-libs="-lstdc++ $extra_libs -lm" \
    --pkg-config-flags='--static' \
    --enable-libaom \
    --enable-libvvenc \
    --enable-libx264 \
    --enable-libx265 \
    --enable-libdav1d \
    --enable-gpl \
    --enable-version3 \
    --enable-rpath \
    --disable-doc \
    --samples=${fate_samples} \
    --ignore-tests="${skip_test_case}" \
    --disable-stripping \
    ${extra_config} 


make -j ${NPROC}

if [ "$do_test" -eq 1 ]; then
    make fate-rsync -j ${NPROC}
    VERBOSE=1 make fate -j ${NPROC}
fi

if [ "$do_install" -eq 1 ]; then
    make install
fi

popd # ${ffmpeg_build}

popd
