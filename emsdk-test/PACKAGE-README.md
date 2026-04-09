# FFmpeg HEVC WASM Decoder - Distribution Package

## Overview

This tool packages the FFmpeg HEVC decoder with WASM SIMD128 optimizations
into a portable Node.js CLI application for performance and correctness testing.

## Packaging

```bash
# Package with WASM protection (recommended for distribution)
./package.sh --protect-wasm

# Package without protection (development)
./package.sh

# All options
./package.sh [--output-dir <dir>] [--enable-obfuscation] [--protect-wasm]
```

### Options

| Option | Description |
|--------|-------------|
| `--output-dir <dir>` | Output directory (default: `ffmpeg-hevc-test-package`) |
| `--protect-wasm` | Encrypt ffmpeg.wasm to prevent extraction |
| `--enable-obfuscation` | Enable JS obfuscation (requires closure-compiler) |

## Distribution

```bash
# Create archive
tar czf ffmpeg-hevc-test.tar.gz ffmpeg-hevc-test-package

# Recipient extracts and runs:
tar xzf ffmpeg-hevc-test.tar.gz
cd ffmpeg-hevc-test-package
./decode.sh input.hevc --frames 100
```

## WASM Protection

When packaged with `--protect-wasm`, the WASM binary is encrypted using:

- **AES-256-GCM** authenticated encryption
- **Key derivation**: PBKDF2 from SHA-256 hash of the glue JS file + random salt
- The encrypted `.wasm.enc` file is **useless** without the matching `ffmpeg.js`
- The original `.wasm` file is removed from the package

## Package Contents

```
ffmpeg-hevc-test-package/
├── node-decode.js       # Node.js CLI decoder
├── decode.sh            # Shell wrapper (Mac/Linux)
├── decode.bat           # Batch wrapper (Windows)
├── README.md            # User-facing documentation
├── LICENSE              # License agreement
└── wasm/
    ├── ffmpeg.wasm.enc  # Encrypted WASM binary (with --protect-wasm)
    ├── ffmpeg.wasm      # Plain WASM binary (without --protect-wasm)
    ├── ffmpeg.js        # JavaScript glue code
    └── ffmpeg.worker.js # Web Worker script (for pthreads)
```

## License

Copyright (c) 2026 Zhao Zhili. All rights reserved.

See `LICENSE` file for full license terms.
