#!/bin/bash
#
# Start a local HTTP server with Cross-Origin Isolation headers.
# Required for SharedArrayBuffer support in Chrome (needed by pthread/WASM threads).
#
# Usage:
#   ./serve.sh [port]    # default port 8080

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PORT="${1:-8080}"

FFMPEG_CI="${SCRIPT_DIR}/.."
WASM_BUILD="${FFMPEG_CI}/build/ffmpeg-wasm"

if [ ! -d "$WASM_BUILD" ]; then
    echo "Error: emsdk build directory not found: $WASM_BUILD" >&2
    echo "Run emsdk_ffmpeg.sh first." >&2
    exit 1
fi

echo "Serving at http://localhost:${PORT}"
echo "  Test page: http://localhost:${PORT}/emsdk-test/"
echo "  WASM build: $WASM_BUILD"
echo ""
echo "Press Ctrl+C to stop."

cd "$FFMPEG_CI"

python3 -c "
import http.server
import socketserver

class COOPCOEPHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        super().end_headers()

    def guess_type(self, path):
        if path.endswith('.wasm'):
            return 'application/wasm'
        return super().guess_type(path)

with socketserver.TCPServer(('', ${PORT}), COOPCOEPHandler) as httpd:
    httpd.serve_forever()
"
