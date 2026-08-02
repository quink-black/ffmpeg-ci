# DNN ONNX teardown abort — regression test

## Bug

`dnn_processing` with `dnn_backend=onnx` used to abort (SIGABRT, rc=134)
when the filter graph was torn down after a successful inference. The
model loaded, inference ran, output was produced, and ffmpeg died in
`dnn_free_model_onnx` releasing the request item.

Root cause: `destroy_request_item()` in `libavfilter/dnn/dnn_backend_onnx.c`
called `ff_dnn_async_module_cleanup(&item->exec_module)`, which under
`HAVE_PTHREAD_CANCEL` does `pthread_join(async_module->thread_id, ...)`.
The ONNX backend is synchronous and never calls `ff_dnn_start_inference_async`,
so `thread_id` stayed zero-initialized from `av_mallocz`. `pthread_join`
on the zeroed handle returns `ESRCH`, and `strict_pthread_join` in
`libavutil/thread.h` calls `abort()` on any non-zero return.

The OpenVINO backend is also synchronous but avoids the abort by not
routing through the async cleanup helper. The ONNX backend was the only
one that called the async cleanup without ever having started the async
thread.

## Test

`test.sh` runs two cases against the built ffmpeg:

1. `single_frame` — one frame through `dnn_processing` with a hand-written
   157-byte ONNX model (Mul by 0.5). This is the minimal reproducer. On
   the buggy code ffmpeg exits 134 with `pthread_join failed` on stderr;
   on fixed code it exits 0.
2. `missing_model` — nonexistent model path. Must fail cleanly WITHOUT
   aborting (rc != 134), proving the abort was on the success/teardown
   path, not the error path.

The ONNX model is written by hand as raw protobuf (no python `onnx`
dependency), so the test runs on any machine with the built ffmpeg.

## Run

```bash
cd ffmpeg-ci
source ./env.sh
./tests/dnn/teardown_abort/test.sh
```

Expected on fixed ffmpeg: both cases PASS. If `single_frame` ever
aborts with rc=134 and `pthread_join failed` on stderr, the bug has
regressed.
