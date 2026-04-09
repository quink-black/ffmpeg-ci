# FFmpeg HEVC Decoder - emsdk Test Environment

Test environment for FFmpeg HEVC decoder built with Emscripten (emsdk).

## Prerequisites

```bash
# Source emsdk environment
source ~/local/emsdk/emsdk_env.sh

# Build FFmpeg with emsdk (builds ffmpeg + checkasm with NODERAWFS)
cd ~/work/ffmpeg_all/ffmpeg-ci
./emsdk_ffmpeg.sh --path ~/work/ffmpeg_all/wasm-ffmpeg/
```

## Node.js Testing

### Fate Tests (Correctness)

Run FFmpeg's built-in test suite to verify decoder correctness:

```bash
# Run all HEVC checkasm tests
./run-fate.sh checkasm

# Run all HEVC decoder tests
./run-fate.sh hevc

# Run both
./run-fate.sh

# Run a specific test
./run-fate.sh fate-checkasm-hevc_sao
```

### Benchmarks

```bash
# checkasm benchmark for specific DSP functions
./benchmark.sh checkasm hevc_sao
./benchmark.sh checkasm hevc_sao "hevc_sao_edge*"
./benchmark.sh checkasm hevc_idct

# Decode benchmark with real video files
./benchmark.sh decode ~/video/raw.hevc 1000
./benchmark.sh decode /Volumes/quink/video/customer/dji/hevc_stream/file.hevc 100
```

### V8 Profiling (function-level)

Requires `--profiling-funcs` to add WASM function names to the profile:

```bash
# Step 1: Enable --profiling-funcs (one-time)
./profile.sh build-prof

# Rebuild the binaries
cd ~/work/ffmpeg_all/ffmpeg-ci/build/ffmpeg-wasm
source ~/local/emsdk/emsdk_env.sh
rm -f ffmpeg_g ffmpeg_g.wasm && make ffmpeg_g -j$(nproc)
rm -f tests/checkasm/checkasm tests/checkasm/checkasm.wasm
make tests/checkasm/checkasm -j$(nproc)

# Step 2: Profile
cd ~/work/ffmpeg_all/ffmpeg-ci/emsdk-test
./profile.sh checkasm hevc_sao "hevc_sao_edge*"
./profile.sh decode ~/video/raw.hevc 600

# Step 3: Re-analyze existing profiles
./profile.sh analyze                      # latest profile
./profile.sh analyze profiles/decode/*.cpuprofile --wasm-only --top 60

# Disable --profiling-funcs when done
./profile.sh build-noprof
```

Profile output is saved to `profiles/{checkasm,decode}/` directory.
The `.cpuprofile` files can be loaded in Chrome DevTools > Performance tab.

**Limitation**: Node.js `--cpu-prof` only profiles the main thread. With
pthreads, decode work runs in Web Workers (80-90% shows as futex_wait).

## Packaging for Distribution

Package the decoder as a portable Node.js CLI tool:

```bash
# Package with WASM protection (recommended)
./package.sh --protect-wasm

# Package without protection (development)
./package.sh
```

The packaged tool is in `ffmpeg-hevc-test-package/`. See
[PACKAGE-README.md](PACKAGE-README.md) for packaging details.

```bash
# Test the package
cd ffmpeg-hevc-test-package
./decode.sh input.hevc --frames 100

# Distribute
tar czf ffmpeg-hevc-test.tar.gz ffmpeg-hevc-test-package
```

## Manual Usage

Run ffmpeg directly under Node.js (always use `-nostdin` to avoid ioctl crash):

```bash
source ~/local/emsdk/emsdk_env.sh
cd ~/work/ffmpeg_all/ffmpeg-ci/build/ffmpeg-wasm

# Decode HEVC to null output
$EMSDK_NODE ffmpeg_g -nostdin -i /path/to/input.hevc -frames:v 100 -f null -

# Run checkasm
$EMSDK_NODE tests/checkasm/checkasm --test=hevc_sao
$EMSDK_NODE tests/checkasm/checkasm --test=hevc_sao --bench
$EMSDK_NODE tests/checkasm/checkasm --test=hevc_sao --bench="hevc_sao_edge*"

# V8 profiling
$EMSDK_NODE --prof tests/checkasm/checkasm --test=hevc_sao --bench
$EMSDK_NODE --prof-process isolate-*.log > profile.txt
```

## Known Limitations

- **NODERAWFS ioctl**: Running `ffmpeg` without `-nostdin` crashes due to
  emscripten NODERAWFS not supporting terminal ioctls. The fate test system
  passes `-nostdin` automatically, so this only affects manual usage.

- **V8 WASM JIT warmup**: First decode run may be slower due to V8's tiered
  compilation. For accurate benchmarks, consider a warmup pass.

## File Overview

| File | Purpose |
|------|---------|
| `run-node.sh` | Node.js wrapper for `--target-exec` (fate test integration) |
| `run-fate.sh` | Convenience script to run fate-checkasm / fate-hevc |
| `benchmark.sh` | checkasm benchmarks and decode FPS measurement |
| `profile.sh` | V8 CPU profiling (--cpu-prof) with auto-analysis |
| `analyze-cpuprofile.py` | Python analyzer for `.cpuprofile` files (WASM function names) |
| `run-decode.js` | Node.js decode wrapper (used by benchmark.sh) |
| `node-decode.js` | Standalone Node.js CLI decoder (used in packaged distribution) |
| `protect-wasm.js` | WASM encryption tool for secure distribution |
| `package.sh` | Package the decoder for distribution |
