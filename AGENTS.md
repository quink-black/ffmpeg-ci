# AGENTS.md

Guidance for AI coding agents working in this repository.

## Purpose

Build external libraries and FFmpeg for development, debugging, and FATE. The
FFmpeg source is selected with `--path` and defaults to `../ffmpeg`. The default
native build enables optimizations. Select `--profile debug` for an unoptimized
build with debug symbols.

## Native builds

`cibuild.sh` is the entry point for native builds. It builds the selected
dependencies, runs FFmpeg's configure and GNU Make, and runs FATE by default.

```bash
./cibuild.sh --path ../ffmpeg --skip-test
./cibuild.sh --path ../ffmpeg --profile debug --skip-test
./cibuild.sh --path ../ffmpeg --profile asan --no-rsync
./cibuild.sh --no-rsync --fate-target fate-aes
```

An ASan build disables Vulkan when it detects an NVIDIA Vulkan ICD. Other Vulkan
implementations can still run the Vulkan FATE tests.

Use the same command after changing FFmpeg sources to reuse the configuration
and object files. Run `--print-build-dir` with the same `--path`, `--profile`, and
`--variant` to locate the build. Source its `runtime.env` if the binary needs
dependency search paths. For a specific Make target, run GNU Make from that
build directory.

```bash
out="$(./cibuild.sh --path ../ffmpeg --print-build-dir)"
source "$out/runtime.env"
make -C "$out" -j8 tests/checkasm/checkasm
```

Use `--reconfigure` after changing external tools or SDKs in place. Use
`--variant NAME` to keep multiple configurations of a worktree and profile.
`make ffmpeg` and the legacy `--enable_opt`, `--enable_asan`, and `--skip_test`
flags forward to the native entry point.

## Native dependencies

`native_build/libraries.py` defines the recipes and their dependencies.
Third-party source trees and Android prebuilt libraries are under `third_party/`.
Use `./cibuild.sh list-deps` for the default and optional dependency lists.
`./cibuild.sh deps --deps NAME` builds a dependency without building FFmpeg.

Each package uses its own build directory and prefix under `build/native/deps`.
A cache key includes the recipe, source identity, environment, tools, and
required package keys. The build holds a per-key lock and marks the prefix
complete after a successful install. FFmpeg adds selected prefixes to its
discovery paths and can also discover optional libraries through pkg-config.
`install_onnxruntime.sh` can supply ONNX Runtime from `install/`.

## Other targets

| Entry point | Target | Requires |
|---|---|---|
| `cross/android_ffmpeg.sh` | Android arm64/armv7 | `ANDROID_NDK` and bundled shaderc for Vulkan builds |
| `cross/wasi_ffmpeg.sh` | wasm32-wasi | `WASI_SDK_PREFIX` |
| `cross/build_openh264_wasi.sh` | OpenH264 for wasm32-wasi | `WASI_SDK_PREFIX` and OpenH264 sources with WASI support |
| `cross/emsdk_ffmpeg.sh` | wasm32 for Node or Chrome | `EMSDK` |
| `cross/hm_ffmpeg.sh` | HarmonyOS arm64 | `OHOS_SDK_NATIVE` |
| `win/build.bat` | Windows x64 with MSVC | Visual Studio, MSYS2 and vcpkg, as described in `win/README.md` |

Read `android/README.md` before modifying the Android app or verifying FFmpeg
on a phone through adb.
The FFmpeg cross-compilation entry points use `env.sh` for their build environment.
Android and HarmonyOS use `cross/build_x264.sh` when `--enable_x264 1` is set.

## Tests

- Run `python3 -B -m unittest discover -s tests/native` to test the native
  dependency cache and FFmpeg configuration reuse.
- FATE uses the shared `ffmpeg-fate-sample/` by default. Use `--samples` or
  `FATE_SAMPLES` to use another directory and `--no-rsync` to reuse existing
  samples. `win-run-fate.sh` is a separate Windows ASan job.
- `test_avs.sh` decodes the standard AVS2 and AVS3 test streams in `tests/avs/`
  and compares the results against reference MD5s. Set `FFMPEG_BIN` to select
  an FFmpeg build with both decoders enabled.
- `tests/dnn/` contains the ONNX `dnn_processing` tests and setup instructions.
