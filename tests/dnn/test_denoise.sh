#!/bin/bash
# Functional test: denoise model (3x3 Gaussian conv).
#
# Feeds a noisy solid-gray frame through the model and verifies the
# output is smoother (lower pixel variance) than the input. A solid
# gray source has ~zero intrinsic variance, so all variance comes from
# the added noise -- the Gaussian kernel should cut it sharply.
#
# testsrc2 is a poor input here: its own detail dominates the variance
# and drowns out the noise reduction signal.
#
# Artifacts:
#   build/test/dnn/denoise/input.png    noisy source frame
#   build/test/dnn/denoise/output.png   smoothed frame
#   build/test/dnn/denoise/logs/run.log
#
# Usage:
#   source ./env.sh && ./tests/dnn/test_denoise.sh

set -e
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

NAME="denoise"
if ! dnn_init "${NAME}"; then
    exit 0
fi

IN="${dnn_out_dir}/input.png"
OUT="${dnn_out_dir}/output.png"
MODEL="${MODELS_DIR}/denoise.onnx"

# Solid gray + heavy noise. The solid source has no variance of its
# own, so the noise dominates and the Gaussian smoothing shows a sharp
# variance drop. Use a fixed noise seed so input and output see the
# same noise pattern (makes the variance comparison fair).
SRC="color=0x808080:s=128x128:r=1"
NOISE_VF="format=rgb24,noise=alls=100:allf=t+u:all_seed=42"
DNN_VF="format=rgb24,dnn_processing=dnn_backend=onnx:model=${MODEL}"

# Capture the noisy input (before denoising).
dnn_run capture -f lavfi -i "${SRC}" -frames:v 1 \
    -vf "${NOISE_VF}" "${IN}"
if [ "${dnn_rc}" -ne 0 ]; then
    dnn_fail "${NAME}: could not capture noisy input (rc=${dnn_rc})"
    dnn_summary "${NAME}"; exit 1
fi

# Run the denoise model on the same noisy source (same seed -> same
# noise pattern).
dnn_run run -f lavfi -i "${SRC}" -frames:v 1 \
    -vf "${NOISE_VF},${DNN_VF}" "${OUT}"
if [ "${dnn_rc}" -ne 0 ]; then
    dnn_fail "${NAME}: ffmpeg failed (rc=${dnn_rc})"
    echo "       log: ${dnn_log_dir}/run.log"
    dnn_summary "${NAME}"; exit 1
fi

in_stats=$(dnn_stats "${IN}")
out_stats=$(dnn_stats "${OUT}")
in_var=${in_stats#*var=}; in_var=${in_var%% *}
out_var=${out_stats#*var=}; out_var=${out_var%% *}

ratio=$(python3 -c "print(f'{${out_var}/${in_var}:.3f}')")
echo "    input : ${in_stats}"
echo "    output: ${out_stats}"
echo "    variance ratio (out/in): ${ratio} (expected well below 1.0)"

# Gaussian 3x3 on pure noise should cut variance to ~14% of input
# (sum of squared kernel weights = 0.140625). Accept anything below
# 0.3 as a clear smoothing effect.
if python3 -c "exit(0 if ${ratio} < 0.3 else 1)"; then
    dnn_pass "${NAME}: variance dropped to ${ratio} of input (smoothing confirmed)"
else
    dnn_fail "${NAME}: variance ratio ${ratio} not below 0.3 (no smoothing?)"
fi

echo "    artifacts: ${IN} , ${OUT}"
dnn_summary "${NAME}"
