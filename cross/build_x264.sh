#!/bin/bash

set -e

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 BUILD_DIR INSTALL_PREFIX HOST" >&2
    exit 2
fi
: "${CC:?Set CC to the cross compiler}"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
build="$1"
prefix="$2"
host="$3"
case "$prefix" in
    /*) ;;
    *) prefix="$PWD/$prefix" ;;
esac

mkdir -p "$build"
cd "$build"
"${root}/x264/configure" \
    --prefix="$prefix" \
    --enable-static \
    --enable-pic \
    --cross-prefix="${CROSS_PREFIX:-}" \
    --host="$host" \
    --disable-avs \
    --disable-lavf \
    --disable-ffms \
    --disable-gpac

jobs="${FFMPEG_CI_JOBS:-$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN || echo 1)}"
make -j "$jobs" install
