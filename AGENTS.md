# AGENTS.md

Guidance for AI coding agents working in this repository.

## Purpose

Build external libraries and FFmpeg for development, debugging, and FATE. The
FFmpeg source is selected with `--path` and defaults to `../ffmpeg`. The default
native profile disables optimizations for debugging.

## Native builds

`cibuild.sh` is the entry point for native builds. It builds the selected
dependencies, runs FFmpeg's configure and GNU Make, and runs FATE by default.

```bash
./cibuild.sh --path ../ffmpeg --skip-test
./cibuild.sh --path ../ffmpeg --profile release --skip-test
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
Use `./cibuild.sh list-deps` for the default and optional dependency lists.
`./cibuild.sh deps --deps NAME` builds a dependency without building FFmpeg.

Each package uses its own build directory and prefix under `build/native/deps`.
A cache key includes the recipe, source identity, environment, tools, and
required package keys. The build holds a per-key lock and marks the prefix
complete after a successful install. FFmpeg adds selected prefixes to its
discovery paths and can also discover optional libraries through pkg-config.
Legacy manual helpers and `install_onnxruntime.sh` can supply dependencies from
`install/`.

## Other targets

| Entry point | Target | Requires |
|---|---|---|
| `android_ffmpeg.sh` | Android arm64/armv7 | `ANDROID_NDK` and prebuilt Vulkan/shaderc in `prebuilt_android/` |
| `wasi_ffmpeg.sh` | wasm32-wasi | `WASI_SDK_PREFIX` |
| `emsdk_ffmpeg.sh` | wasm32 for Node or Chrome | `EMSDK` |
| `hm_ffmpeg.sh` | HarmonyOS arm64 | `OHOS_SDK_NATIVE` |
| `win/build.bat` | Windows x64 with MSVC | Visual Studio, MSYS2 and vcpkg, as described in `win/README.md` |

Read `android/README.md` before modifying the Android app or verifying FFmpeg
on a phone through adb.
The cross-compilation helpers use `env.sh` for their build environment.

## Tests

- Run `python3 -B -m unittest discover -s tests/native` to test the native
  dependency cache and FFmpeg configuration reuse.
- FATE uses the shared `ffmpeg-fate-sample/` by default. Use `--samples` or
  `FATE_SAMPLES` to use another directory and `--no-rsync` to reuse existing
  samples. `win-run-fate.sh` is a separate Windows ASan job.
- `test_avs.sh` compares decoded AVS2 and AVS3 samples against reference MD5s.
  Set `FFMPEG_BIN` to select the binary.
- `tests/dnn/` contains the ONNX `dnn_processing` tests and setup instructions.
