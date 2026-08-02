#!/usr/bin/env python3
"""Generate small ONNX models for ffmpeg dnn_processing regression tests.

The models are intentionally tiny (a few ops, no learned weights) so the
test suite has no external model-zoo dependency. Each model takes a
1x3xHxW float32 RGB tensor (what ffmpeg's dnn_processing hands to the
ONNX backend after converting an rgb24 frame) and produces a visible,
verifiable output change:

  brightness.onnx   Mul by 1.4 -> visibly brighter; mean pixel rises.
  denoise.onnx      3x3 Gaussian conv (groups=3) -> visibly smoother;
                    pixel variance drops.
  super_res_2x.onnx Resize bilinear 2x -> output dims double; pipeline
                    exercises the Resize op end to end.

Run:
  venv/bin/python generate_models.py <out_dir>
"""

import os
import sys

import onnx
from onnx import helper, TensorProto


def _dyn_input(name="input"):
    """1x3xHxW float32 with dynamic spatial dims."""
    return helper.make_tensor_value_info(
        name, TensorProto.FLOAT, [1, 3, "H", "W"]
    )


def make_brightness(out_path):
    """output = input * 1.4  (no clamp; ffmpeg clamps on encode)."""
    scale = helper.make_tensor("scale", TensorProto.FLOAT, [], [1.4])
    inp = _dyn_input()
    out = helper.make_tensor_value_info(
        "output", TensorProto.FLOAT, [1, 3, "H", "W"]
    )
    node = helper.make_node("Mul", ["input", "scale"], ["output"])
    graph = helper.make_graph([node], "brightness", [inp], [out], [scale])
    model = helper.make_model(
        graph,
        producer_name="ffmpeg-ci-tests",
        opset_imports=[helper.make_opsetid("", 13)],
    )
    onnx.checker.check_model(model)
    onnx.save(model, out_path)


def make_denoise(out_path):
    """3x3 Gaussian blur, per-channel (groups=3). Same HxW out."""
    # Gaussian 3x3 sigma~0.85, sum=1.0 so output stays in [0,1].
    k = [
        0.0625, 0.1250, 0.0625,
        0.1250, 0.2500, 0.1250,
        0.0625, 0.1250, 0.0625,
    ]
    # Shape: [out_channels, in_channels/groups, kH, kW] = [3, 1, 3, 3]
    weights = helper.make_tensor(
        "conv_w", TensorProto.FLOAT, [3, 1, 3, 3], k * 3
    )
    bias = helper.make_tensor("conv_b", TensorProto.FLOAT, [3], [0, 0, 0])
    inp = _dyn_input()
    out = helper.make_tensor_value_info(
        "output", TensorProto.FLOAT, [1, 3, "H", "W"]
    )
    node = helper.make_node(
        "Conv",
        ["input", "conv_w", "conv_b"],
        ["output"],
        kernel_shape=[3, 3],
        pads=[1, 1, 1, 1],
        strides=[1, 1],
        group=3,
    )
    graph = helper.make_graph(
        [node], "denoise", [inp], [out], [weights, bias]
    )
    model = helper.make_model(
        graph,
        producer_name="ffmpeg-ci-tests",
        opset_imports=[helper.make_opsetid("", 13)],
    )
    onnx.checker.check_model(model)
    onnx.save(model, out_path)


def make_super_res_2x(out_path):
    """2x bilinear upscale via Resize. Output 1x3x2Hx2W."""
    # Resize needs a shape tensor or scales. Scales is simpler.
    scales = helper.make_tensor(
        "scales", TensorProto.FLOAT, [4], [1.0, 1.0, 2.0, 2.0]
    )
    inp = _dyn_input()
    out = helper.make_tensor_value_info(
        "output", TensorProto.FLOAT, [1, 3, "2H", "2W"]
    )
    # roi absent (mode='nearest' or 'linear' with no roi for opset 13).
    node = helper.make_node(
        "Resize",
        ["input", "", "scales"],
        ["output"],
        mode="linear",
    )
    graph = helper.make_graph(
        [node], "super_res_2x", [inp], [out], [scales]
    )
    model = helper.make_model(
        graph,
        producer_name="ffmpeg-ci-tests",
        opset_imports=[helper.make_opsetid("", 13)],
    )
    onnx.checker.check_model(model)
    onnx.save(model, out_path)


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out_dir, exist_ok=True)

    for name, fn in [
        ("brightness.onnx", make_brightness),
        ("denoise.onnx", make_denoise),
        ("super_res_2x.onnx", make_super_res_2x),
    ]:
        path = os.path.join(out_dir, name)
        fn(path)
        size = os.path.getsize(path)
        print(f"wrote {path} ({size} bytes)")


if __name__ == "__main__":
    main()
