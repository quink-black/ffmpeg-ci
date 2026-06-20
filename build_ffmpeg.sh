#!/bin/bash
# shellcheck disable=SC2154
set -e

# Resolve the directory containing this script so the script can be run
# directly (e.g. from CLion) without requiring DIR to be pre-set by a
# parent script like cibuild.sh.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${DIR:=${SCRIPT_DIR}}"

# Source env.sh so build_dir / install_dir / CC / etc. are available
# regardless of whether this script is invoked standalone or via cibuild.sh.
source "${DIR}/env.sh"

# ---------------------------------------------------------------------------
# Default variables
# ---------------------------------------------------------------------------
ffmpeg_src="${DIR}/../ffmpeg"
do_test=0
do_install=0
skip_test_case=""
enable_asan=0
enable_opt=0
: "${FATE_SAMPLES:=${DIR}/ffmpeg-fate-sample}"
fate_samples="${FATE_SAMPLES}"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case $1 in
        --help)
            echo "Usage: build_ffmpeg.sh [options]"
            echo ""
            echo "Options:"
            echo "  --path DIR           FFmpeg source directory (default: ../ffmpeg)"
            echo "  --test               Run FATE tests after build"
            echo "  --install            Install after build"
            echo "  --skip_test_case T   Skip FATE test cases (comma-separated)"
            echo "  --enable_asan 0|1    Enable address sanitizer"
            echo "  --enable_opt 0|1     Enable optimizations (debug build if 0)"
            exit 0
            ;;
        --path)
            ffmpeg_src="$2"
            shift
            ;;
        --test)
            do_test=1
            ;;
        --install)
            do_install=1
            ;;
        --skip_test_case)
            skip_test_case="$2"
            shift
            ;;
        --enable_asan)
            enable_asan="$2"
            echo "enable_asan ${enable_asan}"
            shift
            ;;
        --enable_opt)
            enable_opt="$2"
            echo "enable_opt ${enable_opt}"
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
# Helper: probe if a pkg-config module exists AND a tiny program actually
# links under --static (matches ffmpeg's --pkg-config-flags=--static
# behavior).  Skips dependencies whose static transitive libs (e.g.
# liblzma) are absent.
# ---------------------------------------------------------------------------
probe_pkg_static() {
    local mod="$1"
    pkg-config --exists "$mod" 2>/dev/null || return 1
    local cflags libs
    cflags=$(pkg-config --cflags "$mod" 2>/dev/null) || return 1
    libs=$(pkg-config --static --libs "$mod" 2>/dev/null) || return 1
    local tmp
    tmp=$(mktemp -d) || return 1
    printf 'int main(void){return 0;}\n' > "$tmp/t.c"
    # shellcheck disable=SC2086
    if ${CC:-cc} $cflags "$tmp/t.c" -o "$tmp/t" $libs >/dev/null 2>&1; then
        rm -rf "$tmp"
        return 0
    fi
    rm -rf "$tmp"
    return 1
}

# ---------------------------------------------------------------------------
# Build path computation
# ---------------------------------------------------------------------------
ffmpeg_build="${build_dir}/ffmpeg"

# ---------------------------------------------------------------------------
# Compiler / flags initialization
# ---------------------------------------------------------------------------
extra_config=""
extra_cflags="-I${install_dir}/include"
extra_ldflags=""
extra_libs="-pthread"

# ---------------------------------------------------------------------------
# Library detection
# ---------------------------------------------------------------------------

# Group A — Core libraries built by the project Makefile.
# Use probe_pkg_static to verify linkability; gracefully skips if a
# dependency is missing (e.g. standalone build without running make first).
if probe_pkg_static aom; then
    extra_config+=" --enable-libaom"
fi

if probe_pkg_static vvenc; then
    extra_config+=" --enable-libvvenc"
fi

if probe_pkg_static x264; then
    extra_config+=" --enable-libx264"
fi

if probe_pkg_static x265; then
    extra_config+=" --enable-libx265"
fi

if probe_pkg_static dav1d; then
    extra_config+=" --enable-libdav1d"
fi

if probe_pkg_static uavs3d; then
    extra_config+=" --enable-libuavs3d"
fi

# Group B — System libraries needing static link verification.
if probe_pkg_static libxml-2.0; then
    extra_config+=" --enable-libxml2"
fi

if probe_pkg_static openssl; then
    # openssl requires --enable-nonfree per FFmpeg convention
    extra_config+=" --enable-openssl --enable-nonfree"
fi

if probe_pkg_static lcms2; then
    extra_config+=" --enable-lcms2"
fi

if probe_pkg_static libwebp; then
    extra_config+=" --enable-libwebp"
fi

if probe_pkg_static OpenCL; then
    extra_config+=" --enable-opencl"
fi

# Group C — System libraries with simple deps (pkg-config --exists).
if pkg-config --exists SvtAv1Enc; then
    extra_config+=" --enable-libsvtav1"
fi

if pkg-config --exists libmfx; then
    extra_config+=" --enable-libmfx"
fi

if pkg-config --exists libass; then
    extra_config+=" --enable-libass"
fi

if pkg-config --exists fribidi; then
    extra_config+=" --enable-libfribidi"
fi

if pkg-config --exists davs2; then
    extra_config+=" --enable-libdavs2"
fi

if pkg-config --exists fontconfig; then
    extra_config+=" --enable-libfreetype --enable-libfontconfig"
fi

if pkg-config --exists harfbuzz; then
    extra_config+=" --enable-libharfbuzz"
fi

if pkg-config --exists whisper; then
    extra_config+=" --enable-whisper"
fi

if pkg-config --exists caca; then
    extra_config+=" --enable-libcaca"
fi

if pkg-config --exists opencv4 && [ "$enable_asan" -eq 0 ]; then
    extra_config+=" --enable-libopencv"
fi

# Group D — Libraries needing configure capability check + pkg-config.
# Anchored grep patterns prevent fragment matches in configure.
if grep -q -- '--enable-libzimg ' "${ffmpeg_src}/configure" \
   && pkg-config --exists zimg; then
    extra_config+=" --enable-libzimg"
fi

# Group E — Vulkan and related (de-nested: libdrm and libplacebo are
# independent of Vulkan).
if pkg-config --exists vulkan; then
    extra_config+=" --enable-vulkan"
    if grep -q -- '--enable-libshaderc ' "${ffmpeg_src}/configure" \
       && pkg-config --exists shaderc; then
        extra_config+=" --enable-libshaderc"
    fi
fi

if grep -q -- '--enable-libplacebo ' "${ffmpeg_src}/configure" \
   && pkg-config --exists libplacebo "libplacebo >= 4.192.0"; then
    extra_config+=" --enable-libplacebo"
fi

if pkg-config --exists libdrm; then
    extra_config+=" --enable-libdrm"
fi

# ---------------------------------------------------------------------------
# ASAN
# ---------------------------------------------------------------------------
if [ "$enable_asan" -eq 1 ]; then
    if ${CC:-cc} -v 2>&1 | grep 'clang version' -q; then
        extra_config="--toolchain=clang-asan ${extra_config}"
        asan_uar_flag=""
    else
        extra_config="--toolchain=gcc-asan ${extra_config}"
        extra_ldflags+=" -static-libasan"
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
        asan_probe_dir=$(mktemp -d)
        trap 'rm -rf "${asan_probe_dir}"' EXIT
        printf 'int main(void){return 0;}\n' > "${asan_probe_dir}/t.c"
        if ${CC:-cc} -fsanitize=address ${asan_uar_flag} \
                "${asan_probe_dir}/t.c" -o "${asan_probe_dir}/t" >/dev/null 2>&1; then
            extra_cflags+=" ${asan_uar_flag}"
        else
            echo "warning: ${CC:-cc} rejects ${asan_uar_flag}; ASan stack-use-after-return stays on"
        fi
        rm -rf "${asan_probe_dir}"
        trap - EXIT
    fi
    ffmpeg_build="${ffmpeg_build}_asan"
fi

# ---------------------------------------------------------------------------
# Opt / debug build path suffix
# ---------------------------------------------------------------------------
if [ "$enable_opt" -eq 0 ]; then
    extra_config+=" --enable-debug --disable-optimizations"
else
    ffmpeg_build="${ffmpeg_build}_opt"
fi

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
NPROC=$(nproc 2>/dev/null || sysctl -n hw.logicalcpu)

mkdir -p "${build_dir}"

pushd "${build_dir}" > /dev/null

# allow in source build of ffmpeg with msys
if [ -z "$MSYSTEM" ]; then
    rm -Rf "${ffmpeg_build}"
fi

mkdir -p "${ffmpeg_build}"
pushd "${ffmpeg_build}" > /dev/null

ignore_tests_arg=""
if [ -n "${skip_test_case}" ]; then
    ignore_tests_arg="--ignore-tests=${skip_test_case}"
fi

# shellcheck disable=SC2086
"${ffmpeg_src}/configure" \
    --prefix="${install_dir}" \
    --cc="${CCACHE_BIN:+${CCACHE_BIN} }${CC}" \
    --cxx="${CCACHE_BIN:+${CCACHE_BIN} }${CXX}" \
    --ld="${CXX}" \
    --assert-level=2 \
    --extra-cflags="${extra_cflags}" \
    --extra-ldflags="-L${install_dir}/lib ${extra_ldflags}" \
    --extra-libs="-lstdc++ ${extra_libs} -lm" \
    --pkg-config-flags='--static' \
    --enable-gpl \
    --enable-version3 \
    --enable-rpath \
    --disable-doc \
    --disable-stripping \
    --samples="${fate_samples}" \
    ${ignore_tests_arg} \
    ${extra_config}

make -j "${NPROC}"

if [ "$do_test" -eq 1 ]; then
    make fate-rsync -j "${NPROC}"
    VERBOSE=1 make fate -j "${NPROC}"
fi

if [ "$do_install" -eq 1 ]; then
    make install
fi

popd > /dev/null

popd > /dev/null
