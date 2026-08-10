#!/bin/bash
# Download and install ONNX Runtime (CPU) into install/ so that
# build_ffmpeg.sh auto-detects it and passes --enable-libonnxruntime to
# FFmpeg's configure.
#
# Why a script: Ubuntu apt and snap have NO onnxruntime package.
#   $ apt-cache search onnxruntime       # nothing
#   $ apt-cache madison libonnxruntime   # nothing
#   $ snap find onnxruntime              # nothing (lemonade-server /
#                                         # piper-tts / drutai / djlbench
#                                         # bundle it internally with no
#                                         # exposed dev files)
# The only usable source on Linux is the official GitHub release tarball.
#
# Why no pkg-config: the official Linux tarball DOES ship a
# libonnxruntime.pc, but it is hardcoded to
#   prefix=/usr/local  libdir=${prefix}/lib64  includedir=${prefix}/include/onnxruntime
# which matches neither the tarball's own layout (flat include/, lib/ not
# lib64/) nor this repo's install/ layout. build_ffmpeg.sh therefore probes
# onnxruntime directly (compile+link the real symbol) instead of relying
# on pkg-config. This script just lays out headers and libs; no .pc is
# installed.
#
# Layout (matches the tarball's own flat structure):
#   install/include/onnxruntime_c_api.h        (+ other flat *.h + core/)
#   install/lib/libonnxruntime.so -> .so.1 -> .so.1.28.0
#   install/lib/libonnxruntime_providers_shared.so   (if shipped)
#
# Because install/include is already on the default include path and
# install/lib on the default lib path (env.sh + build_ffmpeg.sh defaults),
# build_ffmpeg.sh needs no extra -I/-L for this layout -- it only adds
# --enable-libonnxruntime.
#
# Usage:
#   ./install_onnxruntime.sh                              # default version
#   ONNXRUNTIME_VERSION=1.27.0 ./install_onnxruntime.sh   # pin a version
#
# Platform handling is automatic: Linux/macOS use the .tgz with .so/.dylib,
# Windows (MSYS2/mingw) uses the .zip and generates libonnxruntime.dll.a
# from onnxruntime.dll via gendef + dlltool so -lonnxruntime links under gcc.
#
# For a GPU/CUDA build, download the -gpu_cuda12 tarball manually instead;
# this script intentionally targets the CPU build that matches the DNN
# filters' default execution provider.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${DIR:=${SCRIPT_DIR}}"
# Source env.sh only to pick up install_dir; tolerate its absence so the
# script works standalone.
if [ -f "${DIR}/env.sh" ]; then
    # shellcheck disable=SC1091
    source "${DIR}/env.sh"
fi
: "${install_dir:=${DIR}/install}"

VER="${ONNXRUNTIME_VERSION:-1.28.0}"
ARCH="$(uname -m)"
OS="$(uname -s)"

# Map (arch, OS) to the official release artifact naming.
#   Linux:   onnxruntime-linux-{x64,aarch64}-{VER}.tgz        (libonnxruntime.so*)
#   macOS:   onnxruntime-osx-universal2-{VER}.tgz            (libonnxruntime.dylib*)
#   Windows: onnxruntime-win-x64-{VER}.zip                   (onnxruntime.dll + .lib)
# Windows ships an MSVC import library (onnxruntime.lib) that mingw gcc
# cannot link against directly, so we generate libonnxruntime.dll.a from
# the DLL with gendef + dlltool (both shipped by mingw-w64-tools).
case "${ARCH}:${OS}" in
    x86_64:Linux*)    ORT_ARCH="x64";        ORT_OS="linux"  ;;
    aarch64:Linux*)   ORT_ARCH="aarch64";    ORT_OS="linux"  ;;
    arm64:Darwin*)    ORT_ARCH="universal2"; ORT_OS="osx"    ;;
    x86_64:Darwin*)   ORT_ARCH="universal2"; ORT_OS="osx"    ;;
    x86_64:MINGW*|x86_64:MSYS*|x86_64:CYGWIN*)
                      ORT_ARCH="x64";        ORT_OS="win"    ;;
    *) echo "install_onnxruntime.sh: unsupported ${ARCH}/${OS}" >&2; exit 1 ;;
esac

if [ "${ORT_OS}" = "win" ]; then
    PKG="onnxruntime-win-${ORT_ARCH}-${VER}.zip"
else
    PKG="onnxruntime-${ORT_OS}-${ORT_ARCH}-${VER}.tgz"
fi
URL="https://github.com/microsoft/onnxruntime/releases/download/v${VER}/${PKG}"

STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT

echo "==> Downloading ${URL}"
if command -v curl >/dev/null 2>&1; then
    curl -fL -o "${STAGE}/${PKG}" "${URL}"
else
    wget -O "${STAGE}/${PKG}" "${URL}"
fi

echo "==> Extracting"
if [ "${ORT_OS}" = "win" ]; then
    if ! command -v unzip >/dev/null 2>&1; then
        echo "install_onnxruntime.sh: 'unzip' required on Windows" >&2
        exit 1
    fi
    unzip -q "${STAGE}/${PKG}" -d "${STAGE}"
else
    tar -xzf "${STAGE}/${PKG}" -C "${STAGE}"
fi

# The extracted top-level dir differs by platform; locate it by marker file.
SRC="$(find "${STAGE}" -maxdepth 4 -type f -name onnxruntime_c_api.h -print -quit)"
SRC="${SRC%/include/*}"
if [ ! -d "${SRC}" ]; then
    echo "install_onnxruntime.sh: could not find onnxruntime_c_api.h under ${STAGE}" >&2
    exit 1
fi

echo "==> Installing into ${install_dir}"
mkdir -p "${install_dir}/include" "${install_dir}/lib"

# Headers: copy flat (matches the tarball layout). The release ships
# onnxruntime_c_api.h and friends directly under include/, plus a small
# core/providers/ subdir. None of these collide with the other libs in
# install/include/ (verified: no existing core/ or onnxruntime_*.h).
cp -a "${SRC}/include/." "${install_dir}/include/"

if [ "${ORT_OS}" = "win" ]; then
    # Windows release layout: lib/onnxruntime.dll + onnxruntime.lib (MSVC
    # import lib) + onnxruntime_providers_shared.{dll,lib}. Put DLLs in
    # bin/ so env.sh's PATH finds them at runtime. Install the MSVC .lib
    # as-is for cl.exe/link.exe builds, AND generate a mingw import lib
    # (libonnxruntime.dll.a) via gendef+dlltool so -lonnxruntime also
    # links under gcc.
    mkdir -p "${install_dir}/bin"
    cp -a "${SRC}/lib/onnxruntime.dll" "${install_dir}/bin/"
    cp -a "${SRC}/lib/onnxruntime.lib" "${install_dir}/lib/"

    # providers_shared.dll ships in some builds for custom ops.
    if [ -f "${SRC}/lib/onnxruntime_providers_shared.dll" ]; then
        cp -a "${SRC}/lib/onnxruntime_providers_shared.dll" "${install_dir}/bin/"
    fi
    if [ -f "${SRC}/lib/onnxruntime_providers_shared.lib" ]; then
        cp -a "${SRC}/lib/onnxruntime_providers_shared.lib" "${install_dir}/lib/"
    fi

    if ! command -v dlltool >/dev/null 2>&1; then
        echo "install_onnxruntime.sh: 'dlltool' not found" >&2
        exit 1
    fi

    # gendef ships in mingw-w64-tools but may live in a sibling MSYS2
    # subsystem bin/ that is not on PATH (e.g. mingw64/ while the active
    # shell runs from ucrt64/). Derive the MSYS2 root from a tool that IS
    # on PATH (dlltool) and search the standard subsystem directories, so
    # this works regardless of which MSYS2 shell launched the script.
    GENDEF="$(command -v gendef || true)"
    if [ -z "${GENDEF}" ]; then
        DLLTOOL_BIN="$(command -v dlltool)"
        MSYS_ROOT="$(dirname "$(dirname "$(dirname "${DLLTOOL_BIN}")")")"
        for sub in mingw64 ucrt64 clang64 clangarm64 clang32; do
            for cand in "${MSYS_ROOT}/${sub}/bin/gendef" \
                        "${MSYS_ROOT}/${sub}/bin/gendef.exe"; do
                if [ -x "${cand}" ]; then
                    GENDEF="${cand}"
                    break 2
                fi
            done
        done
    fi
    if [ -z "${GENDEF}" ]; then
        echo "install_onnxruntime.sh: could not locate gendef near ${MSYS_ROOT}" >&2
        exit 1
    fi

    # gendef writes onnxruntime.def next to the DLL; feed it to dlltool to
    # produce the import library that -lonnxruntime resolves to under mingw.
    ( cd "${install_dir}/bin" && "${GENDEF}" onnxruntime.dll >/dev/null 2>&1 )
    if [ ! -f "${install_dir}/bin/onnxruntime.def" ]; then
        echo "install_onnxruntime.sh: gendef failed on onnxruntime.dll" >&2
        exit 1
    fi
    dlltool -d "${install_dir}/bin/onnxruntime.def" \
            -l "${install_dir}/lib/libonnxruntime.dll.a" \
            -k
    rm -f "${install_dir}/bin/onnxruntime.def"

    echo "==> Installed:"
    ls -l "${install_dir}/include/onnxruntime_c_api.h"
    ls -l "${install_dir}/bin/onnxruntime.dll"
    ls -l "${install_dir}/lib/onnxruntime.lib"
    ls -l "${install_dir}/lib/libonnxruntime.dll.a"
else
    # Shared libs + symlinks: libonnxruntime.so -> .so.1 -> .so.<ver>
    cp -a "${SRC}/lib/"libonnxruntime*.so* "${install_dir}/lib/"

    # providers_shared.so ships in some builds for custom ops; install if
    # present so custom-op users aren't surprised by a missing library.
    if [ -f "${SRC}/lib/libonnxruntime_providers_shared.so" ]; then
        cp -a "${SRC}/lib/libonnxruntime_providers_shared.so" "${install_dir}/lib/"
    fi

    echo "==> Installed:"
    ls -l "${install_dir}/include/onnxruntime_c_api.h"
    ls -l "${install_dir}/lib/"libonnxruntime*.so*
fi

# NOTE: the Linux tarball's lib/pkgconfig/libonnxruntime.pc is intentionally
# NOT installed -- its hardcoded /usr/local + lib64 + include/onnxruntime
# paths are wrong for this layout and would mislead pkg-config consumers.
echo
echo "Done. Rebuild FFmpeg with:"
echo "  source ./env.sh && ./build_ffmpeg.sh --path ../ffmpeg --enable_opt 1"
echo "build_ffmpeg.sh will auto-detect onnxruntime and pass --enable-libonnxruntime."
