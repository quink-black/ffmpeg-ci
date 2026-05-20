# CODEBUDDY.md

This file provides guidance to CodeBuddy Code when working with code in this repository.

## Project Purpose

This is an FFmpeg CI build system that compiles FFmpeg's third-party dependencies and FFmpeg itself for development, debugging, and testing. The built FFmpeg has optimizations disabled by default, making it suitable for debugging but not production use.

## Build Commands

All commands run from the project root directory.

### Full build (third-party libs + FFmpeg)
```bash
./cibuild.sh --path <ffmpeg-src-dir> --enable_opt 0 --skip_test   # debug
./cibuild.sh --path <ffmpeg-src-dir> --enable_opt 1 --skip_test   # optimized
./cibuild.sh --path <ffmpeg-src-dir> --enable_asan 1 --skip_test  # ASAN
```

### Rebuild only FFmpeg (fast iteration, skip third-party libs)
```bash
source ./env.sh
./build_ffmpeg.sh --path <ffmpeg-src-dir> --enable_opt 0
```

### Rebuild FFmpeg after code edits (no reconfigure)
```bash
source ./env.sh
make -C build/ffmpeg -j$(nproc)
```

### Build only third-party libraries
```bash
source ./env.sh
make -j$(nproc)
```

### Build specific third-party lib via make
```bash
make ffmpeg path=<ffmpeg-src-dir> enable_opt=0
```

### Run FATE tests
```bash
./cibuild.sh --path <ffmpeg-src-dir>                           # all tests
./cibuild.sh --path <ffmpeg-src-dir> --skip_test_case "t1,t2"  # skip specific tests
```

### Run built FFmpeg
```bash
source ./env.sh
./build/ffmpeg/ffmpeg -version       # debug build
./build/ffmpeg_opt/ffmpeg -version   # optimized build
```

## Build Pipeline Architecture

Three layers, run in order:

1. **env.sh** -- Sets `PATH` (install/bin), `LD_LIBRARY_PATH`/`DYLD_LIBRARY_PATH` (install/lib), `PKG_CONFIG_PATH`, ccache launcher vars, `MACOSX_DEPLOYMENT_TARGET=11.0`, `CFLAGS=-fPIC`.

2. **Makefile** (third-party libs) -- Stamp-file targets at project root (`.aom`, `.x264`, etc.) track which libs are built. Active set: aom, cms (Little-CMS), dav1d, davs2 (non-ARM/non-Msys only), uavs3d, x264, x265, vulkan_header, vulkan_loader, libplacebo, vvenc. All install into `install/`.

3. **build_ffmpeg.sh** (FFmpeg) -- Auto-detects available libraries via pkg-config and ffmpeg's configure script, then configures and builds FFmpeg. Output goes to `build/ffmpeg/`, `build/ffmpeg_opt/`, or `build/ffmpeg_asan/`.

## Third-Party Library Build Systems

| Build System | Libraries |
|-------------|-----------|
| CMake | aom, x265, uavs3d, vulkan_header, vulkan_loader, vvenc, srt, vvdec |
| Meson (in-tree `meson/meson.py`) | dav1d, cms, libplacebo, vmaf |
| Autotools/custom configure | x264, nasm, davs2, xavs2, freetype, fontconfig, zimg, lsmash |

## Key Directory Layout

| Path | Purpose |
|------|---------|
| `build/ffmpeg/` | Debug FFmpeg build (no opts, with debug symbols) |
| `build/ffmpeg_opt/` | Optimized FFmpeg build |
| `build/ffmpeg_asan/` | ASAN FFmpeg build |
| `install/lib/` | All third-party shared/static libraries |
| `install/include/` | All third-party headers |
| `ffmpeg-fate-sample/` | FATE test sample files (304 subdirectories) |
| `aom/`, `dav1d/`, `x264/`, `x265/`, etc. | Git submodule sources for third-party libs |
| `meson/` | In-tree meson (git submodule), used by dav1d/cms/libplacebo/vmaf |

## Cross-Compilation and Platform Builds

| Script | Target | Toolchain |
|--------|--------|-----------|
| `android_ffmpeg.sh` | Android arm64/arm | Android NDK LLVM, meson cross-file via `setup_meson.sh` |
| `wasi_ffmpeg.sh` | wasm32-wasi | WASI SDK, wasmtime runtime |
| `emsdk_ffmpeg.sh` | wasm32 (Node/Chrome) | Emscripten SDK |
| `hm_ffmpeg.sh` | HarmonyOS arm64 | OHOS SDK (`aarch64-unknown-linux-ohos`) |
| `win/build.sh` | Windows x64 | MSVC + vcpkg (two modes: direct or vcpkg overlay port) |

Android pre-built Vulkan/shaderc libs are in `prebuilt_android/{aarch64,armeabi-v7a}/`.

Windows builds use `win/build.bat` (finds VS, loads vcvars64) then `win/build.sh` in MSYS2. The vcpkg overlay port is in `vcpkg/ffmpeg/`.

## Important Behavior Notes

- `build_ffmpeg.sh` resolves `SCRIPT_DIR` so it can run standalone, not only via `cibuild.sh`.
- `build_ffmpeg.sh` auto-detects available libraries -- adding a new library to the Makefile install set is usually sufficient; no need to edit the FFmpeg configure flags manually for auto-detected libs.
- FFmpeg source is NOT in this repo; it lives at the path passed via `--path` (default `../ffmpeg`).
- `--enable-rpath` is always set, so binaries embed the library path. Sourcing `env.sh` is still needed for tools that don't use rpath.
- ccache is used automatically if available.
- `--assert-level=2` is always enabled in FFmpeg configure.
- `test_avs.sh` runs custom AVS2/AVS3 decode tests with MD5 checksum verification against `avs2stream/` and `avs3stream/` references.
