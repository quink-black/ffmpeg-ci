#!/bin/bash
# Functional test: super_res_2x model (Resize bilinear 2x).
#
# Feeds a 64x64 frame through the model and verifies the output is
# 128x128 -- i.e. the Resize op ran inside the ONNX backend and the
# dnn_processing filter propagated the new dimensions through the
# filter graph. This is the only test that exercises a dimension
# change, which is the part of the pipeline most likely to break
# (frame-size negotiation, tensor layout).
#
# Artifacts:
#   build/test/dnn/super_res/input.png     64x64 source
#   build/test/dnn/super_res/output.png    128x128 upscaled
#   build/test/dnn/super_res/logs/run.log
#
# Usage:
#   source ./env.sh && ./tests/dnn/test_super_res.sh

set -e
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

NAME="super_res"
if ! dnn_init "${NAME}"; then
    exit 0
fi

IN="${dnn_out_dir}/input.png"
OUT="${dnn_out_dir}/output.png"
MODEL="${MODELS_DIR}/super_res_2x.onnx"

IN_W=64
IN_H=64

# Capture the small input.
dnn_run capture -f lavfi -i "testsrc2=size=${IN_W}x${IN_H}:rate=1" -frames:v 1 \
    -vf "format=rgb24" "${IN}"
if [ "${dnn_rc}" -ne 0 ]; then
    dnn_fail "${NAME}: could not capture input (rc=${dnn_rc})"
    dnn_summary "${NAME}"; exit 1
fi

# Run the upscale model.
dnn_run run -f lavfi -i "testsrc2=size=${IN_W}x${IN_H}:rate=1" -frames:v 1 \
    -vf "format=rgb24,dnn_processing=dnn_backend=onnx:model=${MODEL}" \
    "${OUT}"
if [ "${dnn_rc}" -ne 0 ]; then
    dnn_fail "${NAME}: ffmpeg failed (rc=${dnn_rc})"
    echo "       log: ${dnn_log_dir}/run.log"
    dnn_summary "${NAME}"; exit 1
fi

read -r in_w in_h < <(dnn_dims "${IN}")
read -r out_w out_h < <(dnn_dims "${OUT}")
echo "    input : ${in_w}x${in_h}"
echo "    output: ${out_w}x${out_h}"
echo "    expected: $((IN_W * 2))x$((IN_H * 2))"

exp_w=$((IN_W * 2))
exp_h=$((IN_H * 2))
if [ "${out_w}" -eq "${exp_w}" ] && [ "${out_h}" -eq "${exp_h}" ]; then
    dnn_pass "${NAME}: ${in_w}x${in_h} -> ${out_w}x${out_h} (2x upscale confirmed)"
else
    dnn_fail "${NAME}: output ${out_w}x${out_h} != expected ${exp_w}x${exp_h}"
fi

echo "    artifacts: ${IN} , ${OUT}"
dnn_summary "${NAME}"
