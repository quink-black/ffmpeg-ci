# AGENTS.md

Guidance for AI coding agents working in this repository.

## Purpose

CI build system that compiles FFmpeg's third-party dependencies and FFmpeg itself for development, debugging, and FATE testing. Builds default to no optimization (`--enable-debug --disable-optimizations`), so they are not meant for production use.

FFmpeg source is not in this repo. It lives at the path given by `--path` (default `../ffmpeg`).

## Build

Run everything from the repo root. `cibuild.sh` is the entry point: it sources `env.sh`, builds the third-party libs via `make`, then calls `build_ffmpeg.sh` (internal, do not call directly). FATE tests run by default.

```bash
./cibuild.sh --path <ffmpeg-src> --enable_opt 0 --skip_test   # debug
./cibuild.sh --path <ffmpeg-src> --enable_opt 1 --skip_test   # optimized
./cibuild.sh --path <ffmpeg-src> --enable_asan 1 --skip_test  # ASAN
./cibuild.sh --path <ffmpeg-src> --skip_test_case "t1,t2"     # FATE, skipping tests
```

After a successful `cibuild.sh`, iterate without reconfiguring:

```bash
source ./env.sh
make -C build/ffmpeg -j8           # build/ffmpeg_opt or build/ffmpeg_asan for the other variants
make                               # third-party libs only
make ffmpeg path=<ffmpeg-src> enable_opt=0   # libs + FFmpeg
```

Re-run `cibuild.sh` when configure options change. It deletes and recreates the FFmpeg build directory.

Run the result with `source ./env.sh` first, then `./build/ffmpeg/ffmpeg` (or `build/ffmpeg_opt/`, `build/ffmpeg_asan/`).

## Pipeline

1. `env.sh`: sets `PATH`, `LD_LIBRARY_PATH`, `PKG_CONFIG_PATH`, `CC`/`CXX`, `CFLAGS=-fPIC`, `MACOSX_DEPLOYMENT_TARGET=11.0`, and ccache launcher variables when ccache is installed.
2. `Makefile`: stamp files (`.aom`, `.x264`, ...) at the repo root record built libs. Active set: aom, cms (Little-CMS), dav1d, uavs3d, x264, x265, vulkan_header, vulkan_loader, libplacebo, vvenc, plus davs2 on non-ARM, non-MSYS hosts. Everything installs into `install/`. `make clean` removes the stamp files only.
3. `build_ffmpeg.sh`: probes pkg-config and FFmpeg's `configure` for optional libraries, then configures and builds in `build/`. Adding a library to the Makefile set is usually enough; no configure flag edits needed. Always passes `--assert-level=2` and `--enable-rpath`.

Libraries with `Makefile` rules or `build_*.sh` scripts that `cibuild.sh` does not run (xavs2, uavs3e, freetype, fontconfig, lsmash, srt, vmaf, vvdec, zimg, openh264) are built manually.

## Layout

| Path | Purpose |
|------|---------|
| `build/ffmpeg`, `build/ffmpeg_opt`, `build/ffmpeg_asan` | Debug, optimized, ASAN FFmpeg builds |
| `install/` | Third-party libs, headers, tools |
| `ffmpeg-fate-sample/` | FATE samples (git-ignored) |
| `meson/` | Submodule; the in-tree meson used by dav1d, cms, libplacebo |
| `aom/`, `dav1d/`, `x264/`, `x265/`, ... | Third-party source submodules |
| `avs2stream/`, `avs3stream/` | AVS2/AVS3 reference streams with MD5s |
| `tests/dnn/` | ONNX `dnn_processing` filter tests (see its README) |

Build systems: CMake (aom, x265, uavs3d, vulkan_*, vvenc), meson (dav1d, cms, libplacebo), custom configure (x264, davs2, xavs2).

## Other targets

| Script | Target | Requires |
|--------|--------|----------|
| `android_ffmpeg.sh` | Android arm64/armv7 | `ANDROID_NDK`; prebuilt Vulkan/shaderc in `prebuilt_android/` |
| `wasi_ffmpeg.sh` | wasm32-wasi | `WASI_SDK_PREFIX` |
| `emsdk_ffmpeg.sh` | wasm32 (`--target node\|chrome`) | `EMSDK` |
| `hm_ffmpeg.sh` | HarmonyOS arm64 | `OHOS_SDK_NATIVE` |
| `win/build.bat` -> `win/build.sh` | Windows x64 (MSVC, MSYS2, vcpkg) | see `win/README.md` |

## Tests

- FATE: run through `cibuild.sh` (builds, then `make fate-rsync && make fate`). `win-run-fate.sh` is a standalone Windows ASAN FATE job.
- `test_avs.sh`: decodes AVS2/AVS3 streams with `build/ffmpeg/ffmpeg` and compares MD5s. Its call in `cibuild.sh` is disabled.
