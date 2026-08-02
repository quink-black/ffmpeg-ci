#!/bin/bash
# Functional test: brightness model (Mul by 1.4).
#
# Verifies the full dnn_processing pipeline end to end:
#   - ffmpeg loads the ONNX model
#   - inference runs without abort (regression: see teardown_abort/)
#   - output is visibly brighter than input
#   - output mean is ~1.4x the input mean (within tolerance)
#
# Uses a solid mid-gray input (0x303030 = 48) so no pixels saturate at
# 255 -- that keeps the mean ratio close to the model's true 1.4 factor
# instead of being diluted by clamping. testsrc2 saturates too many
# pixels to give a clean ratio.
#
# Artifacts (visible to the user):
#   build/test/dnn/brightness/input.png    source frame (mid-gray)
#   build/test/dnn/brightness/output.png   dnn-processed frame (brighter)
#   build/test/dnn/brightness/logs/run.log ffmpeg stderr
#
# Usage:
#   source ./env.sh && ./tests/dnn/test_brightness.sh

set -e
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

NAME="brightness"
if ! dnn_init "${NAME}"; then
    exit 0
fi

IN="${dnn_out_dir}/input.png"
OUT="${dnn_out_dir}/output.png"
MODEL="${MODELS_DIR}/brightness.onnx"

# Solid mid-gray (0x303030 = 48) avoids clamping at 255 so the mean ratio
# reflects the model's true 1.4 factor.
SRC="color=0x303030:s=128x128:r=1"

# Capture the source frame unchanged for side-by-side comparison.
dnn_run capture -f lavfi -i "${SRC}" -frames:v 1 \
    -vf "format=rgb24" "${IN}"
if [ "${dnn_rc}" -ne 0 ]; then
    dnn_fail "${NAME}: could not capture input frame (rc=${dnn_rc})"
    dnn_summary "${NAME}"; exit 1
fi

# Run the model.
dnn_run run -f lavfi -i "${SRC}" -frames:v 1 \
    -vf "format=rgb24,dnn_processing=dnn_backend=onnx:model=${MODEL}" \
    "${OUT}"
if [ "${dnn_rc}" -ne 0 ]; then
    dnn_fail "${NAME}: ffmpeg failed (rc=${dnn_rc})"
    echo "       log: ${dnn_log_dir}/run.log"
    dnn_summary "${NAME}"; exit 1
fi

# Compare stats. brightness model is Mul by 1.4 on a non-saturating
# input, so output mean should be ~1.4x input mean.
in_stats=$(dnn_stats "${IN}")
out_stats=$(dnn_stats "${OUT}")
in_mean=${in_stats#mean=}; in_mean=${in_mean%% *}
out_mean=${out_stats#mean=}; out_mean=${out_mean%% *}

ratio=$(python3 -c "print(f'{${out_mean}/${in_mean}:.3f}')")
echo "    input : ${in_stats}"
echo "    output: ${out_stats}"
echo "    mean ratio (out/in): ${ratio} (expected ~1.4)"

# Tolerance: 1.30 .. 1.50. Solid-gray input has no saturated pixels, so
# clamping is a non-issue and the ratio should land very close to 1.4.
if python3 -c "exit(0 if 1.30 < ${ratio} < 1.50 else 1)"; then
    dnn_pass "${NAME}: output is ~1.4x brighter (ratio=${ratio})"
else
    dnn_fail "${NAME}: brightness ratio ${ratio} outside [1.30, 1.50]"
fi

echo "    artifacts: ${IN} , ${OUT}"
dnn_summary "${NAME}"
