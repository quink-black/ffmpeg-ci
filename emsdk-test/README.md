# FFmpeg HEVC Decoder - emsdk Test Environment

Test environment for FFmpeg HEVC decoder built with Emscripten (emsdk).
Supports both Node.js and Chrome browser testing.

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

### V8 Profiling

```bash
# Profile checkasm
./profile.sh checkasm hevc_sao "hevc_sao_edge*"

# Profile decode
./profile.sh decode ~/video/raw.hevc 100

# Process the latest V8 isolate log
./profile.sh process
```

Profile output is saved to `profiles/` directory. The `.txt` report shows
top functions by CPU time. The raw `.log` files can also be loaded into
Chrome DevTools for visualization.

## Chrome Browser Testing

### Start Server

```bash
# Start HTTP server with Cross-Origin Isolation headers (required for SharedArrayBuffer)
./serve.sh          # default port 8080
./serve.sh 9000     # custom port
```

### Open Test Page

Open `http://localhost:8080/emsdk-test/` in Chrome.

1. Select an HEVC stream file (.hevc, .h265, .mp4, etc.)
2. Set max frames (0 = decode all)
3. Click "Decode" to run and measure performance
4. Click "Decode + Profile" to capture a Chrome DevTools profile

### Chrome DevTools Profiling

1. Open DevTools (F12) > Performance tab
2. Click "Decode + Profile" on the test page
3. The profile is captured via `console.profile()` / `console.profileEnd()`
4. Alternatively, manually record in the Performance tab for more detail

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

- **Chrome file loading**: Files are loaded entirely into memory via FileReader
  before decoding. Large files may cause high memory usage.

- **V8 WASM JIT warmup**: First decode run may be slower due to V8's tiered
  compilation. For accurate benchmarks, consider a warmup pass.

## File Overview

| File | Purpose |
|------|---------|
| `run-node.sh` | Node.js wrapper for `--target-exec` (fate test integration) |
| `run-fate.sh` | Convenience script to run fate-checkasm / fate-hevc |
| `benchmark.sh` | checkasm benchmarks and decode FPS measurement |
| `profile.sh` | V8 profiling (--prof) with auto-processing |
| `index.html` | Chrome test page UI |
| `test.js` | Chrome test page JavaScript driver |
| `serve.sh` | HTTP server with COOP/COEP headers for SharedArrayBuffer |
