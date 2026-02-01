#!/bin/bash
# Clean FFmpeg build artifacts
# Usage: ./clean.sh [triplet]
#   triplet: optional, defaults to both x64-windows and x64-windows-static-md

# Derive VCPKG directory relative to user home
MSYS_HOME="${HOME}"
VCPKG_DIR="${MSYS_HOME}/work/vcpkg"
TRIPLET=${1:-""}

clean_triplet() {
    local T=$1
    echo "Cleaning FFmpeg for triplet: ${T}..."
    rm -rf "${VCPKG_DIR}/buildtrees/ffmpeg"
    rm -rf "${VCPKG_DIR}/packages/ffmpeg_${T}"
    rm -rf "${VCPKG_DIR}/installed/${T}/include/libav*"
    rm -rf "${VCPKG_DIR}/installed/${T}/include/libsw*"
    rm -rf "${VCPKG_DIR}/installed/${T}/lib/libav*"
    rm -rf "${VCPKG_DIR}/installed/${T}/lib/libsw*"
    rm -rf "${VCPKG_DIR}/installed/${T}/lib/av*.lib"
    rm -rf "${VCPKG_DIR}/installed/${T}/lib/sw*.lib"
    rm -rf "${VCPKG_DIR}/installed/${T}/bin/av*.dll"
    rm -rf "${VCPKG_DIR}/installed/${T}/bin/sw*.dll"
    rm -rf "${VCPKG_DIR}/installed/${T}/debug/lib/av*.lib"
    rm -rf "${VCPKG_DIR}/installed/${T}/debug/lib/sw*.lib"
    rm -rf "${VCPKG_DIR}/installed/${T}/debug/bin/av*.dll"
    rm -rf "${VCPKG_DIR}/installed/${T}/debug/bin/sw*.dll"
    rm -rf "${VCPKG_DIR}/installed/${T}/tools/ffmpeg"
}

if [ -n "${TRIPLET}" ]; then
    clean_triplet "${TRIPLET}"
else
    echo "Cleaning FFmpeg build artifacts for all triplets..."
    clean_triplet "x64-windows"
    clean_triplet "x64-windows-static-md"
fi

echo "Clean completed."
