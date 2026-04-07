#!/bin/bash
#
# V8 profiling for emsdk-built FFmpeg WASM under Node.js.
# Generates V8 CPU profiles that can be loaded in Chrome DevTools.
#
# Usage:
#   ./profile.sh checkasm hevc_sao hevc_sao_edge*
#   ./profile.sh decode <input.hevc> [frames]
#   ./profile.sh process                          # process the latest isolate log

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FFMPEG_CI="${SCRIPT_DIR}/.."

pushd "${FFMPEG_CI}" > /dev/null
source env.sh
popd > /dev/null

WASM_BUILD="${build_dir}/ffmpeg-wasm"

if [ -z "$EMSDK_NODE" ]; then
    if [ -n "$EMSDK" ]; then
        EMSDK_NODE=$(find "$EMSDK/node" -name node -type f 2>/dev/null | head -1)
    fi
fi

if [ -z "$EMSDK_NODE" ]; then
    echo "Error: EMSDK_NODE not set. Run 'source ~/local/emsdk/emsdk_env.sh' first." >&2
    exit 1
fi

PROFILE_DIR="${SCRIPT_DIR}/profiles"
mkdir -p "$PROFILE_DIR"

run_profiled() {
    echo "=== V8 profiling: $* ==="
    echo "Profile output: $PROFILE_DIR/"

    cd "$PROFILE_DIR"
    "$EMSDK_NODE" --prof "$@"

    local latest_log
    latest_log=$(ls -t isolate-*.log 2>/dev/null | head -1)
    if [ -n "$latest_log" ]; then
        echo ""
        echo "=== Processing profile: $latest_log ==="
        "$EMSDK_NODE" --prof-process "$latest_log" > "${latest_log%.log}.txt"
        echo "Text report: ${PROFILE_DIR}/${latest_log%.log}.txt"
        echo ""
        echo "Top entries:"
        head -50 "${latest_log%.log}.txt"
    fi
}

case "${1:-}" in
    checkasm)
        shift
        test_name="${1:-hevc_sao}"
        bench_pattern="${2:-}"
        checkasm="${WASM_BUILD}/tests/checkasm/checkasm"

        if [ ! -f "$checkasm" ]; then
            echo "Error: checkasm not found." >&2
            exit 1
        fi

        if [ -n "$bench_pattern" ]; then
            run_profiled "$checkasm" --test="$test_name" --bench="$bench_pattern"
        else
            run_profiled "$checkasm" --test="$test_name" --bench
        fi
        ;;
    decode)
        shift
        input="$1"
        frames="${2:-100}"
        ffmpeg="${WASM_BUILD}/ffmpeg_g"

        if [ ! -f "$input" ]; then
            echo "Error: input file not found: $input" >&2
            exit 1
        fi

        run_profiled "$ffmpeg" -nostdin -i "$input" -frames:v "$frames" -f null -
        ;;
    process)
        cd "$PROFILE_DIR"
        latest_log=$(ls -t isolate-*.log 2>/dev/null | head -1)
        if [ -z "$latest_log" ]; then
            echo "No isolate log found in $PROFILE_DIR" >&2
            exit 1
        fi
        echo "Processing: $latest_log"
        "$EMSDK_NODE" --prof-process "$latest_log" > "${latest_log%.log}.txt"
        echo "Report: ${PROFILE_DIR}/${latest_log%.log}.txt"
        head -80 "${latest_log%.log}.txt"
        ;;
    *)
        echo "Usage:"
        echo "  $0 checkasm [test_name] [bench_pattern]"
        echo "  $0 decode <input.hevc> [frames]"
        echo "  $0 process  # process latest V8 isolate log"
        echo ""
        echo "Examples:"
        echo "  $0 checkasm hevc_sao hevc_sao_edge*"
        echo "  $0 decode ~/video/raw.hevc 1000"
        exit 1
        ;;
esac
