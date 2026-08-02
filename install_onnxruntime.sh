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
case "${ARCH}" in
    x86_64)  ORT_ARCH="x64" ;;
    aarch64) ORT_ARCH="aarch64" ;;
    *) echo "install_onnxruntime.sh: unsupported arch ${ARCH}" >&2; exit 1 ;;
esac

TARBALL="onnxruntime-linux-${ORT_ARCH}-${VER}.tgz"
URL="https://github.com/microsoft/onnxruntime/releases/download/v${VER}/${TARBALL}"

STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT

echo "==> Downloading ${URL}"
if command -v curl >/dev/null 2>&1; then
    curl -fL -o "${STAGE}/${TARBALL}" "${URL}"
else
    wget -O "${STAGE}/${TARBALL}" "${URL}"
fi

echo "==> Extracting"
tar -xzf "${STAGE}/${TARBALL}" -C "${STAGE}"
SRC="${STAGE}/onnxruntime-linux-${ORT_ARCH}-${VER}"
if [ ! -d "${SRC}" ]; then
    echo "install_onnxruntime.sh: expected ${SRC} after extract" >&2
    exit 1
fi

echo "==> Installing into ${install_dir}"
mkdir -p "${install_dir}/include" "${install_dir}/lib"

# Headers: copy flat (matches the tarball layout). The tarball ships
# onnxruntime_c_api.h and friends directly under include/, plus a small
# core/providers/ subdir. None of these collide with the other libs in
# install/include/ (verified: no existing core/ or onnxruntime_*.h).
cp -a "${SRC}/include/." "${install_dir}/include/"

# Shared libs + symlinks: libonnxruntime.so -> .so.1 -> .so.<ver>
cp -a "${SRC}/lib/"libonnxruntime*.so* "${install_dir}/lib/"

# providers_shared.so ships in some builds for custom ops; install if
# present so custom-op users aren't surprised by a missing library.
if [ -f "${SRC}/lib/libonnxruntime_providers_shared.so" ]; then
    cp -a "${SRC}/lib/libonnxruntime_providers_shared.so" "${install_dir}/lib/"
fi

# NOTE: the tarball's lib/pkgconfig/libonnxruntime.pc is intentionally NOT
# installed -- its hardcoded /usr/local + lib64 + include/onnxruntime
# paths are wrong for this layout and would mislead pkg-config consumers.

echo "==> Installed:"
ls -l "${install_dir}/include/onnxruntime_c_api.h"
ls -l "${install_dir}/lib/"libonnxruntime*.so*
echo
echo "Done. Rebuild FFmpeg with:"
echo "  source ./env.sh && ./build_ffmpeg.sh --path ../ffmpeg --enable_opt 0"
echo "build_ffmpeg.sh will auto-detect onnxruntime and pass --enable-libonnxruntime."
