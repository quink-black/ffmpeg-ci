# DNN filter tests

Regression and functional tests for ffmpeg's `dnn_processing` filter
with the ONNX Runtime backend.

## Layout

```
teardown_abort/   regression test for the ONNX backend teardown abort
                  (SIGABRT in dnn_free_model_onnx after successful
                  inference). Self-contained, no model dependency.
generate_models.py  produces the tiny ONNX models used below
prepare_models.sh   creates a throwaway venv, runs the generator
test_brightness.sh  Mul-by-1.4 model -> output is ~1.4x brighter
test_denoise.sh     3x3 Gaussian conv -> variance drops sharply
test_super_res.sh   Resize bilinear 2x -> output dims double
run_all.sh          runs every test above and summarizes
common.sh           shared helpers (paths, stats, pass/fail)
```

## Why generated models, not downloaded ones

ffmpeg's `dnn_processing` hands the ONNX backend a `1x3xHxW` float32
RGB tensor. No reliably-downloadable small ONNX model on the ONNX
Model Zoo or PINTO model zoo matches that layout directly -- published
SR/denoise models are Y-channel-only (`1x1xHxW`), fixed-resolution, or
expect a different layout. Generating tiny models locally (a few ops,
no learned weights) keeps the suite self-contained and hermetic.

Only `dnn_processing` supports the ONNX backend in this ffmpeg tree;
`dnn_detect` and `dnn_classify` are TF/OpenVINO-only, so bounding-box
detection tests are out of scope here.

## Run

```bash
source ./env.sh
./tests/dnn/prepare_models.sh     # one-time: creates venv + models
./tests/dnn/run_all.sh
```

Each functional test writes before/after PNGs and ffmpeg logs under
`build/test/dnn/<name>/` so results are visible, not just pass/fail.
