#!/bin/bash
# Regression test for the DNN ONNX backend teardown abort.
#
# Bug: dnn_processing with dnn_backend=onnx used to SIGABRT (rc=134) when
# the filter graph was torn down after a successful inference, because
# destroy_request_item() called ff_dnn_async_module_cleanup() which
# pthread_join()ed a thread_id that was never created. See README.md.
#
# The ONNX model is written by hand as raw protobuf (157 bytes) so the
# test has no python onnx dependency.
#
# Usage:
#   source ./env.sh
#   ./tests/dnn/teardown_abort/test.sh
#
# Env:
#   FFMPEG_BIN  ffmpeg binary to test (default: build/ffmpeg/ffmpeg)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# tests/dnn/teardown_abort -> ../../.. = project root
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
ffmpeg_bin="${FFMPEG_BIN:-${PROJECT_DIR}/build/ffmpeg/ffmpeg -hide_banner}"

test_dir="${PROJECT_DIR}/build/test/dnn_teardown_abort"
onnx_model="${test_dir}/scale_05.onnx"
log_dir="${test_dir}/logs"
mkdir -p "${test_dir}" "${log_dir}"

pass=0
fail=0
skip=0

have_backend() {
    $ffmpeg_bin -buildconf 2>&1 | grep -q -- "--enable-libonnxruntime"
}

# Hand-written ONNX model: Mul(input, 0.5) -> output, NCHW float32.
# 157 bytes; avoids the python onnx package dependency.
generate_model() {
    [ -f "${onnx_model}" ] && return
    python3 - "${onnx_model}" <<'PY'
import struct, sys

def varint(n):
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        out.append(b | (0x80 if n else 0))
        if not n:
            return bytes(out)

def tag(field, wire):
    return varint(field << 3 | wire)

def ld(field, payload):
    return tag(field, 2) + varint(len(payload)) + payload

def vi(field, value):
    return tag(field, 0) + varint(value)

FLOAT = 1

def tensor_type(dims):
    shape = b""
    for d in dims:
        dim = vi(1, d) if isinstance(d, int) else ld(2, d.encode())
        shape += ld(1, dim)
    return ld(1, vi(1, FLOAT) + ld(2, shape))

def value_info(name, dims):
    return ld(1, name.encode()) + ld(2, tensor_type(dims))

def scalar_initializer(name, value):
    return vi(2, FLOAT) + ld(8, name.encode()) + ld(9, struct.pack("<f", value))

def node(op, inputs, outputs, name):
    b = b""
    for i in inputs:
        b += ld(1, i.encode())
    for o in outputs:
        b += ld(2, o.encode())
    b += ld(3, name.encode()) + ld(4, op.encode())
    return b

scale = scalar_initializer("scale", 0.5)
n = node("Mul", ["input", "scale"], ["output"], "scale_node")
graph = (
    ld(1, n)
    + ld(2, b"scale_graph")
    + ld(5, scale)
    + ld(11, value_info("input", [1, 3, 64, 64]))
    + ld(12, value_info("output", [1, 3, 64, 64]))
)
opset = vi(2, 13)
model = vi(1, 8) + ld(2, b"handmade") + ld(7, graph) + ld(8, opset)

with open(sys.argv[1], "wb") as f:
    f.write(model)
print("wrote", sys.argv[1], len(model), "bytes")
PY
}

# Run one case, return rc. Output PNG is discarded; we only care about
# the exit code and the stderr log.
run_case() {
    local name="$1"
    local out="${test_dir}/${name}.png"
    shift
    set +e
    $ffmpeg_bin -y "$@" "${out}" > "${log_dir}/${name}.log" 2>&1
    local rc=$?
    set -e
    rm -f "${out}"
    return ${rc}
}

# Pre-flight: backend must be built in.
if ! have_backend; then
    echo "SKIP: ffmpeg not built with --enable-libonnxruntime"
    echo "      build with ./build_ffmpeg.sh after ./install_onnxruntime.sh"
    skip=$((skip + 1))
    echo "----"
    echo "teardown_abort: ${pass} passed, ${fail} failed, ${skip} skipped"
    exit 0
fi

generate_model

# Case 1 — single frame, model exists. Minimal reproducer. On buggy
# ffmpeg this aborts (rc=134) with "pthread_join failed" on stderr; on
# fixed ffmpeg it exits 0.
rc=0
run_case single_frame \
    -f lavfi -i "testsrc2=size=64x64:rate=1" -frames:v 1 \
    -vf "format=rgb24,dnn_processing=dnn_backend=onnx:model=${onnx_model}" \
    || rc=$?
case ${rc} in
    0)
        echo "PASS  single_frame: ffmpeg exited 0 (teardown clean)"
        pass=$((pass + 1))
        ;;
    134)
        echo "FAIL  single_frame: aborted on teardown (rc=134, SIGABRT)"
        grep -q "pthread_join failed" "${log_dir}/single_frame.log" \
            && echo "        pthread_join on never-created thread_id (bug regressed)" \
            || echo "        SIGABRT without pthread_join message"
        echo "        log: ${log_dir}/single_frame.log"
        fail=$((fail + 1))
        ;;
    *)
        echo "FAIL  single_frame: unexpected rc=${rc}"
        echo "        log: ${log_dir}/single_frame.log"
        fail=$((fail + 1))
        ;;
esac

# Case 2 — nonexistent model. Must fail cleanly WITHOUT aborting
# (rc != 134), proving the abort is on the success/teardown path, not
# the error path.
rc=0
run_case missing_model \
    -f lavfi -i "testsrc2=size=64x64:rate=1" -frames:v 1 \
    -vf "format=rgb24,dnn_processing=dnn_backend=onnx:model=${test_dir}/nope.onnx" \
    || rc=$?
if [ ${rc} -eq 134 ]; then
    echo "FAIL  missing_model: aborted on error path (rc=134)"
    echo "        log: ${log_dir}/missing_model.log"
    fail=$((fail + 1))
elif [ ${rc} -ne 0 ]; then
    echo "PASS  missing_model: clean failure on missing model (rc=${rc}, no abort)"
    pass=$((pass + 1))
else
    echo "FAIL  missing_model: unexpectedly succeeded"
    fail=$((fail + 1))
fi

echo "----"
echo "teardown_abort: ${pass} passed, ${fail} failed, ${skip} skipped"
[ "${fail}" -eq 0 ]
