# FFmpeg CI Build Project

## Project Overview

This project builds FFmpeg third-party dependencies and FFmpeg itself for development and debugging purposes.
All paths below are relative to the project root (this repo).

- **FFmpeg source code**: `../ffmpeg` (default) — override with `--path <dir>` or `path=<dir>`
- **Debug build output**: `build/ffmpeg/`
- **Optimized build output**: `build/ffmpeg_opt/`
- **ASAN build output**: `build/ffmpeg_asan/`
- **Installed libraries**: `install/`

## Build Commands

Run all commands from the **project root directory**.

### Build optimized FFmpeg (for performance testing)
```bash
./cibuild.sh --path <ffmpeg-src-dir> --enable_opt 1 --skip_test
```

### Build debug FFmpeg (for development/debugging, no optimizations)
```bash
./cibuild.sh --path <ffmpeg-src-dir> --enable_opt 0 --skip_test
```

### Build with ASAN (memory error detection)
```bash
./cibuild.sh --path <ffmpeg-src-dir> --enable_asan 1 --skip_test
```

### Rebuild only FFmpeg (skip third-party libs, faster iteration)
```bash
source ./env.sh
./build_ffmpeg.sh --path <ffmpeg-src-dir> --enable_opt 0
```

### Build only third-party libraries
```bash
make -j$(nproc)
```

### Build third-party libs + FFmpeg via make
```bash
make ffmpeg path=<ffmpeg-src-dir> enable_opt=0
make ffmpeg path=<ffmpeg-src-dir> enable_opt=1
```

## Running FFmpeg After Build

`env.sh` sets `DYLD_LIBRARY_PATH`/`LD_LIBRARY_PATH` so built binaries can find `install/lib`.
Always source it before running binaries, or use `--enable-rpath` builds which embed the path.

```bash
source ./env.sh

# Run debug build
./build/ffmpeg/ffmpeg -version

# Run optimized build
./build/ffmpeg_opt/ffmpeg -version
```

## Environment Setup (`env.sh`)

Sourcing `env.sh` sets up:
- `DYLD_LIBRARY_PATH` / `LD_LIBRARY_PATH` → `install/lib` and `install/lib64`
- `PKG_CONFIG_PATH` → `install/lib/pkgconfig`
- `PATH` → `install/bin` (nasm, etc.)
- `install_dir` = `$PWD/install`
- `build_dir` = `$PWD/build`

## Key Directories

| Directory | Purpose |
|-----------|---------|
| `build/ffmpeg/` | Debug build (no optimizations, with debug symbols) |
| `build/ffmpeg_opt/` | Optimized build |
| `build/ffmpeg_asan/` | ASAN build |
| `install/lib/` | All third-party shared/static libraries |
| `install/include/` | All third-party headers |
| `install/bin/` | Tools (nasm, etc.) |
| `ffmpeg-fate-sample/` | FATE test samples |

## FFmpeg Source Code Analysis

The FFmpeg source is located at the path passed via `--path` (default: `../ffmpeg`).
Key subdirectories within the FFmpeg source:

- `libavcodec/` — codec implementations
- `libavformat/` — container format muxers/demuxers
- `libavfilter/` — audio/video filters
- `libavutil/` — utility functions
- `libswscale/` — image scaling/conversion
- `libswresample/` — audio resampling
- `fftools/` — ffmpeg/ffprobe/ffplay CLI tools

## Third-Party Libraries Built

| Library | Purpose |
|---------|---------|
| x264 | H.264 encoder |
| x265 | H.265/HEVC encoder |
| dav1d | AV1 decoder |
| aom | AV1 encoder/decoder |
| vvenc | VVC encoder |
| uavs3d | AVS3 decoder |
| vmaf | Video quality metric |
| srt | Secure Reliable Transport |
| libplacebo | GPU video processing |

## Development Workflow

1. Edit FFmpeg source in `<ffmpeg-src-dir>`
2. Rebuild FFmpeg only (fast iteration): `cd build/ffmpeg && make -j$(sysctl -n hw.ncpu)`
3. Test: `./build/ffmpeg/ffmpeg <args>`
4. When a clean rebuild is needed (e.g. configure changes): `./cibuild.sh --skip_test --path <ffmpeg-src-dir>`

> **Note**: For day-to-day code changes, just run `make` inside `build/ffmpeg/`.
> The full `cibuild.sh` is only necessary when you need to reconfigure or start fresh.

## Notes

- Debug builds use `--enable-debug --disable-optimizations` — suitable for gdb/lldb
- `--assert-level=2` is always enabled for catching assertion failures
- `--enable-rpath` is set so binaries embed the library path (reduces need to source `env.sh`)
- On macOS, `DYLD_LIBRARY_PATH` is used; on Linux, `LD_LIBRARY_PATH` (both set by `env.sh`)
- `ccache` is used automatically if available to speed up rebuilds
