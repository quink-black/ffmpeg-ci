#!/bin/bash
#
# V8 profiling for emsdk-built FFmpeg WASM under Node.js.
#
# Requires: emsdk build with --profiling-funcs for WASM function names.
# Use `profile.sh build-prof` to enable, `profile.sh build-noprof` to disable.
#
# Approach 1 (--cpu-prof): Generates .cpuprofile files, analyzed by
#   analyze-cpuprofile.py. Gives per-function self-time breakdown.
#   Limitation: only profiles main thread; pthread work shows as futex_wait.
#   Best for single-thread decoding or identifying JS glue overhead.
#
# Approach 2 (--prof): Generates V8 tick logs, processed by --prof-process.
#   Shows aggregated profile across all code, but WASM time is attributed to
#   libc shared library (92%+). Only useful for high-level JIT/runtime split.
#
# For comprehensive multi-thread profiling, use Chrome DevTools Performance tab.
# See `profile.sh help` or wasm-opt.md for details.
#
# Usage:
#   ./profile.sh checkasm hevc_idct *dc*      # cpu-prof checkasm benchmark
#   ./profile.sh decode <input.hevc> [frames]  # cpu-prof decode
#   ./profile.sh build-prof                     # enable --profiling-funcs
#   ./profile.sh build-noprof                   # disable --profiling-funcs
#   ./profile.sh help                           # show usage and docs

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FFMPEG_CI="${SCRIPT_DIR}/.."

pushd "${FFMPEG_CI}" > /dev/null
source env.sh
popd > /dev/null

WASM_BUILD="${build_dir}/ffmpeg-wasm"
CONFIG_MAK="${WASM_BUILD}/ffbuild/config.mak"
PROFILE_DIR="${SCRIPT_DIR}/profiles"
ANALYZE_SCRIPT="${SCRIPT_DIR}/analyze-cpuprofile.py"

if [ -z "$EMSDK_NODE" ]; then
    if [ -n "$EMSDK" ]; then
        EMSDK_NODE=$(find "$EMSDK/node" -name node -type f 2>/dev/null | head -1)
    fi
fi

check_node() {
    if [ -z "$EMSDK_NODE" ]; then
        echo "Error: EMSDK_NODE not set. Run 'source ~/local/emsdk/emsdk_env.sh' first." >&2
        exit 1
    fi
}

check_profiling_funcs() {
    local wasm_file="$1"
    if [ ! -f "$wasm_file" ]; then
        return 1
    fi
    if command -v wasm-objdump >/dev/null 2>&1; then
        if wasm-objdump -h "$wasm_file" 2>/dev/null | grep -q '"name"'; then
            return 0
        fi
    fi
    return 1
}

warn_no_names() {
    local wasm_file="$1"
    if ! check_profiling_funcs "$wasm_file"; then
        echo "WARNING: WASM binary has no name section." >&2
        echo "  Functions will show as wasm-function[N] instead of real names." >&2
        echo "  Run './profile.sh build-prof' to rebuild with --profiling-funcs." >&2
        echo "" >&2
    fi
}

run_cpuprof() {
    local prof_subdir="$1"
    shift

    mkdir -p "$PROFILE_DIR/$prof_subdir"

    # Remove old profiles
    rm -f "$PROFILE_DIR/$prof_subdir/"*.cpuprofile

    echo "=== V8 CPU profiling: $* ==="
    echo "Output: $PROFILE_DIR/$prof_subdir/"
    echo ""

    "$EMSDK_NODE" \
        --cpu-prof \
        --cpu-prof-dir="$PROFILE_DIR/$prof_subdir" \
        --cpu-prof-interval=100 \
        "$@"

    local prof_file
    prof_file=$(ls -t "$PROFILE_DIR/$prof_subdir/"*.cpuprofile 2>/dev/null | head -1)
    if [ -z "$prof_file" ]; then
        echo "Error: no .cpuprofile generated." >&2
        return 1
    fi

    echo ""
    echo "=== Analyzing profile ==="
    python3 "$ANALYZE_SCRIPT" "$prof_file" --exclude-idle --top 40
    echo ""
    echo "Profile saved: $prof_file"
    echo "Load in Chrome DevTools: Performance tab > Load profile"
}

case "${1:-}" in
    checkasm)
        check_node
        shift
        test_name="${1:-hevc_sao}"
        bench_pattern="${2:-}"
        checkasm="${WASM_BUILD}/tests/checkasm/checkasm"

        if [ ! -f "$checkasm" ]; then
            echo "Error: checkasm not found at $checkasm" >&2
            exit 1
        fi

        warn_no_names "${checkasm}.wasm"

        if [ -n "$bench_pattern" ]; then
            run_cpuprof "checkasm" "$checkasm" --test="$test_name" --bench="$bench_pattern"
        else
            run_cpuprof "checkasm" "$checkasm" --test="$test_name" --bench
        fi
        ;;

    decode)
        check_node
        shift
        input="$1"
        frames="${2:-100}"
        ffmpeg="${WASM_BUILD}/ffmpeg_g"

        if [ ! -f "$input" ]; then
            echo "Error: input file not found: $input" >&2
            exit 1
        fi
        if [ ! -f "$ffmpeg" ]; then
            echo "Error: ffmpeg_g not found at $ffmpeg" >&2
            exit 1
        fi

        warn_no_names "${ffmpeg}.wasm"

        run_cpuprof "decode" "$ffmpeg" -nostdin -i "$input" -frames:v "$frames" -f null -
        ;;

    build-prof)
        if [ ! -f "$CONFIG_MAK" ]; then
            echo "Error: $CONFIG_MAK not found. Run emsdk_ffmpeg.sh first." >&2
            exit 1
        fi
        if grep -q '\-\-profiling-funcs' "$CONFIG_MAK"; then
            echo "--profiling-funcs already enabled."
        else
            sed -i 's/^LDFLAGS=\(.*\)/LDFLAGS=\1 --profiling-funcs/' "$CONFIG_MAK"
            echo "--profiling-funcs enabled in $CONFIG_MAK"
        fi
        echo ""
        echo "Now rebuild the binaries you want to profile:"
        echo "  cd $WASM_BUILD && source ~/local/emsdk/emsdk_env.sh"
        echo "  rm -f ffmpeg_g ffmpeg_g.wasm && make ffmpeg_g -j\$(nproc)"
        echo "  rm -f tests/checkasm/checkasm tests/checkasm/checkasm.wasm"
        echo "  make tests/checkasm/checkasm -j\$(nproc)"
        ;;

    build-noprof)
        if [ ! -f "$CONFIG_MAK" ]; then
            echo "Error: $CONFIG_MAK not found." >&2
            exit 1
        fi
        sed -i 's/ --profiling-funcs//g' "$CONFIG_MAK"
        echo "--profiling-funcs removed from $CONFIG_MAK"
        echo "Rebuild to apply."
        ;;

    analyze)
        shift
        prof_file="$1"
        if [ -z "$prof_file" ]; then
            # Find latest
            prof_file=$(find "$PROFILE_DIR" -name '*.cpuprofile' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | awk '{print $2}')
        fi
        if [ -z "$prof_file" ] || [ ! -f "$prof_file" ]; then
            echo "Error: no .cpuprofile found." >&2
            exit 1
        fi
        shift 2>/dev/null || true
        python3 "$ANALYZE_SCRIPT" "$prof_file" "$@"
        ;;

    help|--help|-h)
        cat << 'HELPEOF'
V8 WASM Profiling Tools
========================

PREREQUISITES:
  source ~/local/emsdk/emsdk_env.sh

STEP 1: Enable --profiling-funcs (adds WASM function name section):
  ./profile.sh build-prof
  cd ~/work/ffmpeg_all/ffmpeg-ci/build/ffmpeg-wasm
  rm -f ffmpeg_g ffmpeg_g.wasm && make ffmpeg_g -j$(nproc)

STEP 2: Run profiling:
  ./profile.sh decode /path/to/stream.hevc 600
  ./profile.sh checkasm hevc_idct '*dc*'

STEP 3: Analyze (automatic, or re-analyze):
  ./profile.sh analyze                      # latest profile
  ./profile.sh analyze path/to.cpuprofile --wasm-only
  ./profile.sh analyze path/to.cpuprofile --exclude-idle --top 60

LIMITATION:
  Node.js --cpu-prof profiles the main thread only.
  With pthreads, decode work runs in Web Workers, so the main thread
  shows 80-90% emscripten_futex_wait. The decode function breakdown
  is still visible but with fewer samples (lower precision).

  For multi-thread profiling, use Chrome DevTools:
  1. Start server: ./serve.sh
  2. Open http://localhost:8080/emsdk-test/ in Chrome
  3. Open DevTools (F12) > Performance tab
  4. Click Record, then click Decode on the test page
  5. Stop recording when decode finishes
  6. Expand "Worker" threads in the flame chart to see decode functions
  7. Save profile via export button for later analysis

DISABLE profiling-funcs (for production/benchmark builds):
  ./profile.sh build-noprof
  (then rebuild)

FILES:
  profile.sh              - This script
  analyze-cpuprofile.py   - Python analyzer for .cpuprofile files
  profiles/               - Output directory for profile data
HELPEOF
        ;;

    *)
        echo "Usage:"
        echo "  $0 checkasm [test_name] [bench_pattern]   # Profile checkasm"
        echo "  $0 decode <input.hevc> [frames]            # Profile decode"
        echo "  $0 build-prof                              # Enable --profiling-funcs"
        echo "  $0 build-noprof                            # Disable --profiling-funcs"
        echo "  $0 analyze [file.cpuprofile] [options]     # Re-analyze profile"
        echo "  $0 help                                    # Full documentation"
        exit 1
        ;;
esac
