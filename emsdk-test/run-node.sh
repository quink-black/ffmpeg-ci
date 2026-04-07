#!/bin/bash
#
# Node.js wrapper for running emsdk-built WASM binaries.
# Used as --target-exec in ffmpeg's configure.
# Invoked by the fate test system as: run-node.sh ./path/to/binary [args...]
#
# NODERAWFS ioctl limitation: running ffmpeg manually without -nostdin
# may crash on isatty(). The fate system passes -nostdin automatically.
# For manual use: node ffmpeg_g -nostdin -i input.hevc -f null -

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$EMSDK_NODE" ]; then
    if [ -n "$EMSDK" ]; then
        EMSDK_NODE=$(find "$EMSDK/node" -name node -type f 2>/dev/null | head -1)
    fi
fi

if [ -z "$EMSDK_NODE" ]; then
    echo "Error: EMSDK_NODE not set. Run 'source emsdk_env.sh' first." >&2
    exit 1
fi

exec "$EMSDK_NODE" "$@"
