#!/bin/bash
#
# Run FFmpeg fate tests for the emsdk WASM build.
# Usage:
#   ./run-fate.sh                    # run both fate-checkasm and fate-hevc
#   ./run-fate.sh checkasm           # run only fate-checkasm
#   ./run-fate.sh hevc               # run only fate-hevc
#   ./run-fate.sh fate-checkasm-hevc_sao  # run a specific fate test

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FFMPEG_CI="${SCRIPT_DIR}/.."

pushd "${FFMPEG_CI}" > /dev/null
source env.sh
popd > /dev/null

WASM_BUILD="${build_dir}/ffmpeg-wasm"

if [ ! -d "$WASM_BUILD" ]; then
    echo "Error: emsdk build directory not found: $WASM_BUILD" >&2
    echo "Run emsdk_ffmpeg.sh first." >&2
    exit 1
fi

if [ -z "$EMSDK" ]; then
    echo "Error: EMSDK not set. Run 'source ~/local/emsdk/emsdk_env.sh' first." >&2
    exit 1
fi

NPROC=$(nproc 2>/dev/null || sysctl -n hw.logicalcpu)

cd "$WASM_BUILD"

if [ $# -eq 0 ]; then
    echo "=== Running fate-checkasm ==="
    make fate-checkasm -j"$NPROC" V=1
    echo ""
    echo "=== Running fate-hevc ==="
    make fate-hevc -j"$NPROC" V=1
elif [ "$1" = "checkasm" ]; then
    make fate-checkasm -j"$NPROC" V=1
elif [ "$1" = "hevc" ]; then
    make fate-hevc -j"$NPROC" V=1
else
    make "$1" -j"$NPROC" V=1
fi
