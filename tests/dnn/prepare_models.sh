#!/bin/bash
# Prepare the ONNX models used by the dnn_processing functional tests.
#
# Despite the user's "download script" framing, there is no reliable
# small ONNX model that can be downloaded and fed directly to ffmpeg's
# dnn_processing filter: the filter hands the backend a 1x3xHxW float32
# RGB tensor, while every published small SR/denoise model on the ONNX
# Model Zoo and PINTO model zoo either is Y-channel-only (1x1xHxW),
# has a fixed input resolution, or expects a different layout. None
# match without a pre/post pipeline ffmpeg does not provide.
#
# Instead this script generates three tiny models locally (a few ops,
# no learned weights) using the `onnx` Python package in a throwaway
# venv. The venv lives under tests/dnn/.venv and is reused across
# runs; models land in tests/dnn/models/. Both are gitignored.
#
# Models generated:
#   brightness.onnx    Mul by 1.4 -> visibly brighter output.
#   denoise.onnx       3x3 Gaussian conv -> visibly smoother output.
#   super_res_2x.onnx  Resize bilinear 2x -> output dims double.
#
# Usage:
#   ./tests/dnn/prepare_models.sh
#
# Force a rebuild:
#   rm -rf tests/dnn/.venv tests/dnn/models && ./tests/dnn/prepare_models.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="${SCRIPT_DIR}/.venv"
MODELS="${SCRIPT_DIR}/models"
GENERATOR="${SCRIPT_DIR}/generate_models.py"

if [ -f "${VENV}/bin/python" ]; then
    echo "==> Reusing venv at ${VENV}"
else
    echo "==> Creating venv at ${VENV}"
    python3 -m venv "${VENV}"
    "${VENV}/bin/pip" install --quiet --upgrade pip
    "${VENV}/bin/pip" install --quiet onnx
fi

echo "==> Generating models into ${MODELS}"
"${VENV}/bin/python" "${GENERATOR}" "${MODELS}"

echo
echo "Done. Models:"
ls -l "${MODELS}"/*.onnx
echo
echo "Run tests with:"
echo "  source ./env.sh && ./tests/dnn/run_all.sh"
