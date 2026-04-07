#!/bin/bash
#
# Benchmark FFmpeg HEVC decoder under Node.js (V8 WASM engine).
# Usage:
#   ./benchmark.sh checkasm                     # all HEVC checkasm benchmarks
#   ./benchmark.sh checkasm hevc_sao_edge       # specific benchmark pattern
#   ./benchmark.sh decode <input.hevc> [frames] # decode benchmark with FPS

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FFMPEG_CI="${SCRIPT_DIR}/.."

pushd "${FFMPEG_CI}" > /dev/null
source env.sh
popd > /dev/null

WASM_BUILD="${build_dir}/ffmpeg-wasm"
NODE_WRAPPER="${SCRIPT_DIR}/run-node.sh"

if [ ! -d "$WASM_BUILD" ]; then
    echo "Error: emsdk build directory not found: $WASM_BUILD" >&2
    exit 1
fi

if [ -z "$EMSDK" ]; then
    echo "Error: EMSDK not set. Run 'source ~/local/emsdk/emsdk_env.sh' first." >&2
    exit 1
fi

run_checkasm_bench() {
    local test_name="${1:-hevc_sao}"
    local bench_pattern="${2:-}"
    local checkasm="${WASM_BUILD}/tests/checkasm/checkasm"

    if [ ! -f "$checkasm" ]; then
        echo "Error: checkasm not found at $checkasm" >&2
        echo "Rebuild with emsdk_ffmpeg.sh to include checkasm." >&2
        exit 1
    fi

    echo "=== checkasm benchmark: test=$test_name bench=$bench_pattern ==="
    if [ -n "$bench_pattern" ]; then
        "$NODE_WRAPPER" "$checkasm" --test="$test_name" --bench="$bench_pattern"
    else
        "$NODE_WRAPPER" "$checkasm" --test="$test_name" --bench
    fi
}

run_decode_bench() {
    local input="$1"
    local frames="${2:-100}"
    local ffmpeg="${WASM_BUILD}/ffmpeg_g"

    if [ ! -f "$input" ]; then
        echo "Error: input file not found: $input" >&2
        exit 1
    fi

    echo "=== decode benchmark: input=$(basename "$input") frames=$frames ==="
    echo ""

    local start_ms
    start_ms=$(date +%s%3N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1000))')

    "$NODE_WRAPPER" "$ffmpeg" -nostdin -i "$input" -frames:v "$frames" -f null - 2>&1

    local end_ms
    end_ms=$(date +%s%3N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1000))')

    local elapsed_ms=$((end_ms - start_ms))
    echo ""
    echo "--- Results ---"
    echo "Frames: $frames"
    echo "Wall time: ${elapsed_ms}ms"
    if [ "$elapsed_ms" -gt 0 ]; then
        local fps
        fps=$(echo "scale=2; $frames * 1000 / $elapsed_ms" | bc)
        echo "FPS: $fps"
    fi
}

case "${1:-}" in
    checkasm)
        shift
        run_checkasm_bench "$@"
        ;;
    decode)
        shift
        if [ $# -lt 1 ]; then
            echo "Usage: $0 decode <input.hevc> [frames]" >&2
            exit 1
        fi
        run_decode_bench "$@"
        ;;
    *)
        echo "Usage:"
        echo "  $0 checkasm [test_name] [bench_pattern]"
        echo "  $0 decode <input.hevc> [frames]"
        echo ""
        echo "Examples:"
        echo "  $0 checkasm hevc_sao hevc_sao_edge*"
        echo "  $0 checkasm hevc_idct"
        echo "  $0 decode ~/video/raw.hevc 1000"
        exit 1
        ;;
esac
