#!/bin/bash
#
# Package FFmpeg HEVC WASM decoder as a distributable Node.js CLI test tool.
#
# Usage:
#   ./package.sh [--output-dir <dir>] [--enable-obfuscation] [--protect-wasm]
#
# Security:
#   --protect-wasm: Encrypt ffmpeg.wasm (AES-256-GCM) so it cannot be extracted
#
# Requirements (optional, for obfuscation):
#   - wasm-opt (from wabt or binaryen)
#   - closure-compiler (npm install -g google-closure-compiler)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FFMPEG_CI="${SCRIPT_DIR}/.."
BUILD_DIR="${FFMPEG_CI}/build/ffmpeg-wasm"
OUTPUT_DIR="${SCRIPT_DIR}/ffmpeg-hevc-test-package"

ENABLE_OBFUSCATION=false
PROTECT_WASM=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --enable-obfuscation)
            ENABLE_OBFUSCATION=true
            shift
            ;;
        --protect-wasm)
            PROTECT_WASM=true
            shift
            ;;
        --help)
            echo "Usage: $0 [--output-dir <dir>] [--enable-obfuscation] [--protect-wasm]"
            echo ""
            echo "Options:"
            echo "  --output-dir <dir>      Output directory (default: ffmpeg-hevc-test-package)"
            echo "  --enable-obfuscation    Enable JavaScript obfuscation (requires closure-compiler)"
            echo "  --protect-wasm          Encrypt ffmpeg.wasm to prevent extraction"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

echo "=== Packaging FFmpeg HEVC WASM Test Tool ==="
echo "Build directory: $BUILD_DIR"
echo "Output directory: $OUTPUT_DIR"
echo "Obfuscation: $ENABLE_OBFUSCATION"
echo "WASM protection: $PROTECT_WASM"
echo ""

# Check build directory
if [ ! -d "$BUILD_DIR" ]; then
    echo "Error: Build directory not found: $BUILD_DIR" >&2
    echo "Please run emsdk_ffmpeg.sh first." >&2
    exit 1
fi

if [ ! -f "$BUILD_DIR/ffmpeg_g" ] || [ ! -f "$BUILD_DIR/ffmpeg_g.wasm" ]; then
    echo "Error: ffmpeg_g or ffmpeg_g.wasm not found in build directory" >&2
    exit 1
fi

# Create output directory
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/wasm"

echo "Step 1: Copying FFmpeg files..."
cp "$BUILD_DIR/ffmpeg_g.wasm" "$OUTPUT_DIR/wasm/ffmpeg.wasm"
cp "$BUILD_DIR/ffmpeg_g" "$OUTPUT_DIR/wasm/ffmpeg.js"
cp "$BUILD_DIR/ffmpeg_g.worker.js" "$OUTPUT_DIR/wasm/ffmpeg.worker.js" 2>/dev/null || true

# Patch the glue JS for packaged usage:
# 1. Rename wasm file reference from ffmpeg_g.wasm to ffmpeg.wasm
# 2. Pick up global.Module when loaded via require() in Node.js
echo "  Patching ffmpeg.js for packaged usage..."
GLUE_JS="$OUTPUT_DIR/wasm/ffmpeg.js"
sed 's/var f = "ffmpeg_g\.wasm"/var f = "ffmpeg.wasm"/' "$GLUE_JS" > "$GLUE_JS.tmp" && mv "$GLUE_JS.tmp" "$GLUE_JS"
sed 's/var Module = typeof Module != "undefined" ? Module : {};/var Module = typeof Module != "undefined" ? Module : (typeof globalThis != "undefined" \&\& globalThis.Module ? globalThis.Module : {});/' "$GLUE_JS" > "$GLUE_JS.tmp" && mv "$GLUE_JS.tmp" "$GLUE_JS"

# Optimize WASM binary
if [ "$ENABLE_OBFUSCATION" = true ]; then
    echo "Step 2: Optimizing and obfuscating WASM binary..."
    if command -v wasm-opt &> /dev/null; then
        echo "  Running wasm-opt -O4 --strip-producers..."
        wasm-opt -O4 --strip-producers "$OUTPUT_DIR/wasm/ffmpeg.wasm" \
            -o "$OUTPUT_DIR/wasm/ffmpeg.wasm.opt" 2>/dev/null || {
            echo "Warning: wasm-opt with --strip-producers failed, trying -O4 only"
            wasm-opt -O4 "$OUTPUT_DIR/wasm/ffmpeg.wasm" \
                -o "$OUTPUT_DIR/wasm/ffmpeg.wasm.opt" 2>/dev/null || {
                echo "Warning: wasm-opt failed, using original WASM"
                cp "$OUTPUT_DIR/wasm/ffmpeg.wasm" "$OUTPUT_DIR/wasm/ffmpeg.wasm.opt"
            }
        }
        mv "$OUTPUT_DIR/wasm/ffmpeg.wasm.opt" "$OUTPUT_DIR/wasm/ffmpeg.wasm"
    else
        echo "Step 2: Skipping WASM optimization (wasm-opt not found)"
    fi
    if command -v wasm-strip &> /dev/null; then
        echo "  Stripping WASM name/debug sections..."
        wasm-strip "$OUTPUT_DIR/wasm/ffmpeg.wasm" 2>/dev/null || \
            echo "Warning: wasm-strip failed"
    fi
else
    if command -v wasm-opt &> /dev/null; then
        echo "Step 2: Optimizing WASM binary (removing debug info)..."
        wasm-opt -O4 "$OUTPUT_DIR/wasm/ffmpeg.wasm" -o "$OUTPUT_DIR/wasm/ffmpeg.wasm.opt" 2>/dev/null || {
            echo "Warning: wasm-opt failed, using original WASM"
            cp "$OUTPUT_DIR/wasm/ffmpeg.wasm" "$OUTPUT_DIR/wasm/ffmpeg.wasm.opt"
        }
        mv "$OUTPUT_DIR/wasm/ffmpeg.wasm.opt" "$OUTPUT_DIR/wasm/ffmpeg.wasm"
    else
        echo "Step 2: Skipping WASM optimization (wasm-opt not found)"
    fi
fi

# Obfuscate JavaScript
if [ "$ENABLE_OBFUSCATION" = true ]; then
    echo "Step 3: Obfuscating JavaScript..."
    if command -v google-closure-compiler &> /dev/null; then
        for js_file in "$OUTPUT_DIR/wasm/ffmpeg.js" "$OUTPUT_DIR/wasm/ffmpeg.worker.js"; do
            [ -f "$js_file" ] || continue
            echo "  Obfuscating $(basename "$js_file")..."
            google-closure-compiler \
                --compilation_level SIMPLE_OPTIMIZATIONS \
                --js "$js_file" \
                --js_output_file "$js_file.obf" 2>/dev/null || {
                echo "Warning: closure-compiler failed for $(basename "$js_file"), keeping original"
                cp "$js_file" "$js_file.obf"
            }
            mv "$js_file.obf" "$js_file"
        done
    else
        echo "  Skipping JS obfuscation (google-closure-compiler not found)"
        echo "  Install: npm install -g google-closure-compiler"
    fi
else
    echo "Step 3: Skipping JS obfuscation (not enabled)"
fi

# ---------------------------------------------------------------------------
# WASM Protection (encrypt ffmpeg.wasm)
# ---------------------------------------------------------------------------
if [ "$PROTECT_WASM" = true ]; then
    echo "Step 4: Encrypting WASM binary..."
    if ! command -v node &> /dev/null; then
        echo "Error: Node.js is required for --protect-wasm" >&2
        exit 1
    fi
    node "$SCRIPT_DIR/protect-wasm.js" "$OUTPUT_DIR/wasm" --verify
    echo ""
else
    echo "Step 4: Skipping WASM protection (not enabled)"
fi

# ---------------------------------------------------------------------------
# Node.js CLI package
# ---------------------------------------------------------------------------
echo "Step 5: Creating Node.js CLI package..."
cp "$SCRIPT_DIR/node-decode.js" "$OUTPUT_DIR/node-decode.js"

cat > "$OUTPUT_DIR/decode.sh" << 'DECODE_SH_EOF'
#!/bin/bash
# FFmpeg HEVC WASM Decoder - Node.js CLI
# Usage: ./decode.sh <input.hevc> [options]
#
# Options:
#   --frames <n>       Max frames (0=all, default: 0)
#   --threads <n>      Threads (default: 1)
#   --verify <mode>    none, framemd5, md5 (default: none)
#   --warmup <n>       Warmup frames (default: 0)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export PATH="$HOME/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
node "$SCRIPT_DIR/node-decode.js" "$@"
DECODE_SH_EOF
chmod +x "$OUTPUT_DIR/decode.sh"

cat > "$OUTPUT_DIR/decode.bat" << 'DECODE_BAT_EOF'
@echo off
REM FFmpeg HEVC WASM Decoder - Node.js CLI
REM Usage: decode.bat <input.hevc> [options]
node "%~dp0node-decode.js" %*
DECODE_BAT_EOF

echo "Step 6: Creating README..."
cat > "$OUTPUT_DIR/README.md" << 'README_EOF'
# FFmpeg HEVC WASM Decoder

Node.js CLI tool for testing FFmpeg HEVC decoder with WASM SIMD128 optimizations.

## Requirements

- **Node.js 16+** (only dependency)

## Quick Start

```bash
# Extract the package
tar xzf ffmpeg-hevc-test.tar.gz
cd ffmpeg-hevc-test-package

# Decode an HEVC file
./decode.sh input.hevc --frames 100

# Or call node directly
node node-decode.js input.hevc --frames 100
```

## CLI Options

```
node node-decode.js <input> [options]

Options:
  --frames <n>       Max frames to decode (0 = all, default: 0)
  --threads <n>      Number of threads (default: 1)
  --verify <mode>    Verification: none, framemd5, md5 (default: none)
  --warmup <n>       Warmup frames before measurement (default: 0)
  --help             Show help
```

## Examples

```bash
# Performance test: decode 200 frames
./decode.sh video.hevc --frames 200

# Correctness verification with framemd5
./decode.sh video.hevc --verify framemd5 --frames 50

# Multi-threaded with warmup
./decode.sh video.hevc --threads 4 --warmup 20 --frames 200

# Decode from container format
./decode.sh video.mp4 --frames 100
```

## Troubleshooting

### "Cannot find module" error
Ensure you run from the package directory:
```bash
cd ffmpeg-hevc-test-package
./decode.sh input.hevc
```

### Slow first run
WASM JIT compilation warmup. Use `--warmup` flag:
```bash
./decode.sh input.hevc --warmup 20 --frames 200
```

## License

Copyright (c) 2026 Zhao Zhili. All rights reserved.
See LICENSE file for full terms.
README_EOF

echo "Step 7: Creating license file..."
cat > "$OUTPUT_DIR/LICENSE" << 'LICENSE_EOF'
FFMPEG HEVC WASM TEST TOOL LICENSE AGREEMENT

Copyright (c) 2026 Zhao Zhili. All rights reserved.

This license agreement ("Agreement") governs your use of the FFmpeg HEVC WASM Test Tool ("Software").

1. GRANT OF LICENSE
   The Software is licensed, not sold, to you for testing and demonstration purposes only.

2. RESTRICTIONS
   You may NOT:
   a) Reverse engineer, decompile, disassemble, or otherwise attempt to derive the source code of the Software, including but not limited to the WASM binary and JavaScript code;
   b) Extract, copy, modify, adapt, translate, or create derivative works based on the Software;
   c) Rent, lease, loan, sell, resell, sublicense, distribute, or otherwise transfer rights to the Software;
   d) Remove, alter, or obscure any proprietary notices, labels, or marks on the Software;
   e) Use the Software for any commercial purpose without obtaining a separate commercial license.

3. OWNERSHIP
   The Software is protected by copyright laws and international treaty provisions. The Software contains proprietary technology and trade secrets.

4. DISCLAIMER OF WARRANTY
   THE SOFTWARE IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NONINFRINGEMENT.

5. LIMITATION OF LIABILITY
   IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE THE SOFTWARE.

6. TERMINATION
   This license is effective until terminated. Your rights under this license will terminate automatically without notice if you fail to comply with any of its terms.

7. GOVERNING LAW
   This Agreement shall be governed by the laws of the jurisdiction in which the author resides.

BY USING THE SOFTWARE, YOU AGREE TO BE BOUND BY THE TERMS OF THIS AGREEMENT.

For commercial licensing inquiries, contact: quinkblack@foxmail.com
LICENSE_EOF

echo ""
echo "=== Packaging Complete ==="
echo "Output directory: $OUTPUT_DIR"
echo ""
echo "Files created:"
ls -lh "$OUTPUT_DIR" | tail -n +2
echo ""
ls -lh "$OUTPUT_DIR/wasm/" | tail -n +2
echo ""
echo "To test the package:"
echo "  cd $OUTPUT_DIR"
echo "  ./decode.sh <input.hevc> --frames 100"
echo ""
echo "To distribute:"
echo "  tar czf ffmpeg-hevc-test.tar.gz $(basename $OUTPUT_DIR)"
echo ""

