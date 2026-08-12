#!/bin/bash
# Shared helpers for the dnn functional tests. Sourced by test_*.sh;
# not meant to be run directly.
#
# Provides:
#   dnn_init <test_name>           sets up dirs, checks backend, returns 1 if skip
#   dnn_run <name> <ffmpeg_args…>  runs ffmpeg, captures rc + log
#   dnn_stats <png>                prints mean and variance (RGB, 0-1)
#   dnn_dims <png>                 prints "W H"
#   dnn_pass <msg> / dnn_fail <msg>
#   dnn_summary <test_name>

# Resolve project root (tests/dnn/../../.. = ffmpeg-ci/).
# This file is at tests/dnn/common.sh, so ../.. = tests/, ../../.. = root.
DNN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${DNN_DIR}/../.." && pwd)"

# Prefer the project-local venv created by prepare_models.sh (it has
# numpy + Pillow); fall back to system python3.
if [ -x "${DNN_DIR}/.venv/bin/python" ]; then
    DNN_PY="${DNN_DIR}/.venv/bin/python"
else
    DNN_PY="python3"
fi

FFMPEG_BIN="${FFMPEG_BIN:-${PROJECT_DIR}/build/ffmpeg/ffmpeg -hide_banner}"
MODELS_DIR="${DNN_DIR}/models"
OUT_BASE="${PROJECT_DIR}/build/test/dnn"

dnn_pass_count=0
dnn_fail_count=0

dnn_have_backend() {
    $FFMPEG_BIN -buildconf 2>&1 | grep -q -- "--enable-libonnxruntime"
}

dnn_have_models() {
    [ -f "${MODELS_DIR}/brightness.onnx" ] \
        && [ -f "${MODELS_DIR}/denoise.onnx" ] \
        && [ -f "${MODELS_DIR}/super_res_2x.onnx" ]
}

# dnn_init <test_name>
# Sets $dnn_out_dir and $dnn_log_dir. Returns 0 if OK to run, 1 if skipped.
dnn_init() {
    local name="$1"
    dnn_out_dir="${OUT_BASE}/${name}"
    dnn_log_dir="${dnn_out_dir}/logs"
    mkdir -p "${dnn_out_dir}" "${dnn_log_dir}"

    if ! dnn_have_backend; then
        echo "SKIP ${name}: ffmpeg not built with --enable-libonnxruntime"
        return 1
    fi
    if ! dnn_have_models; then
        echo "SKIP ${name}: models missing -- run ./tests/dnn/prepare_models.sh"
        return 1
    fi
    return 0
}

# dnn_run <log_basename> <ffmpeg_args...>
# Runs ffmpeg with -y, last arg is the output file. Captures rc in $dnn_rc.
dnn_run() {
    local log_name="$1"
    shift
    set +e
    $FFMPEG_BIN -y "$@" > "${dnn_log_dir}/${log_name}.log" 2>&1
    dnn_rc=$?
    set -e
}

# dnn_stats <png>  -> "mean=<f> var=<f>" (RGB, normalized 0-1)
dnn_stats() {
    "${DNN_PY}" - "$1" <<'PY'
import sys
from PIL import Image
import numpy as np
im = np.asarray(Image.open(sys.argv[1]).convert("RGB"), dtype=np.float32) / 255.0
print(f"mean={im.mean():.4f} var={im.var():.4f}")
PY
}

# dnn_dims <png>  -> "W H"
dnn_dims() {
    "${DNN_PY}" - "$1" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1])
print(f"{im.size[0]} {im.size[1]}")
PY
}

dnn_pass() {
    echo "PASS $1"
    dnn_pass_count=$((dnn_pass_count + 1))
}

dnn_fail() {
    echo "FAIL $1"
    dnn_fail_count=$((dnn_fail_count + 1))
}

# dnn_summary <test_name>
dnn_summary() {
    echo "----"
    echo "$1: ${dnn_pass_count} passed, ${dnn_fail_count} failed"
    [ "${dnn_fail_count}" -eq 0 ]
}
