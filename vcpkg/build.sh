#!/bin/bash
# =============================================================================
# FFmpeg Custom Build Script
# =============================================================================
# Usage: ./build.sh [--debug] [--debug-only] [--force] [--clean]
#   --debug      : Build both Release and Debug configurations (default: Release only)
#   --debug-only : Build Debug configuration only (faster for testing)
#   --force      : Force rebuild even if already installed
#   --clean      : Clean build artifacts before building
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VCPKG_DIR="${HOME}/work/vcpkg"
OVERLAY_PORTS="${SCRIPT_DIR}"
TRIPLET="x64-windows"
BUILD_MODE_ARG=""
FORCE_REBUILD=0
CLEAN_FIRST=0

# Parse arguments
for arg in "$@"; do
    case $arg in
        --debug) BUILD_MODE_ARG="both" ;;
        --debug-only) BUILD_MODE_ARG="debug" ;;
        --force) FORCE_REBUILD=1 ;;
        --clean) CLEAN_FIRST=1 ;;
        --help|-h) 
            echo "Usage: $0 [--debug] [--debug-only] [--force] [--clean]"
            echo "  --debug      : Build both Release and Debug configurations"
            echo "  --debug-only : Build Debug configuration only (faster for testing)"
            echo "  --force      : Force rebuild"
            echo "  --clean      : Clean before building"
            exit 0 
            ;;
    esac
done

# Configure build mode
TRIPLET_FILE="${VCPKG_DIR}/triplets/${TRIPLET}.cmake"
sed -i "/VCPKG_BUILD_TYPE/d" "${TRIPLET_FILE}" 2>/dev/null || true

case "$BUILD_MODE_ARG" in
    "both")
        BUILD_MODE="Release + Debug"
        LOG_FILE="${HOME}/ffmpeg_build.log"
        # Don't set VCPKG_BUILD_TYPE to build both
        ;;
    "debug")
        BUILD_MODE="Debug only"
        LOG_FILE="${HOME}/ffmpeg_debug_build.log"
        echo "set(VCPKG_BUILD_TYPE debug)" >> "${TRIPLET_FILE}"
        ;;
    *)
        BUILD_MODE="Release only"
        LOG_FILE="${HOME}/ffmpeg_release_build.log"
        echo "set(VCPKG_BUILD_TYPE release)" >> "${TRIPLET_FILE}"
        ;;
esac

# Clean if requested
if [ $CLEAN_FIRST -eq 1 ] || [ $FORCE_REBUILD -eq 1 ]; then
    echo "Cleaning previous build..."
    "${VCPKG_DIR}/vcpkg.exe" remove ffmpeg:${TRIPLET} --recurse 2>/dev/null || true
    rm -rf "${VCPKG_DIR}/buildtrees/ffmpeg" "${VCPKG_DIR}/packages/ffmpeg_${TRIPLET}"
fi

echo ""
echo "==========================================" 
echo "Building FFmpeg (${BUILD_MODE})"
echo "==========================================" 
echo "VCPKG_DIR: ${VCPKG_DIR}"
echo "OVERLAY_PORTS: ${OVERLAY_PORTS}"
echo "LOG_FILE: ${LOG_FILE}"
echo ""

cd "${VCPKG_DIR}"

# Simplified feature set - only what we actually need
FFMPEG_FEATURES="gpl,avcodec,avdevice,avfilter,avformat,swresample,swscale"
FFMPEG_FEATURES="${FFMPEG_FEATURES},ffmpeg,ffprobe"
FFMPEG_FEATURES="${FFMPEG_FEATURES},x264,x265,mp3lame,opus,vpx,aom"
FFMPEG_FEATURES="${FFMPEG_FEATURES},opencv,tesseract"
FFMPEG_FEATURES="${FFMPEG_FEATURES},iconv,zlib"

echo "Features: ${FFMPEG_FEATURES}"
echo ""

./vcpkg.exe install "ffmpeg[${FFMPEG_FEATURES}]" \
    --overlay-ports="${OVERLAY_PORTS}" \
    --triplet="${TRIPLET}" \
    --recurse 2>&1 | tee "${LOG_FILE}"

BUILD_RESULT=$?

if [ $BUILD_RESULT -eq 0 ]; then
    echo ""
    echo "==========================================" 
    echo "Build completed successfully!"
    echo "==========================================" 
    echo ""
    echo "Output locations:"
    
    if [ "$BUILD_MODE_ARG" != "debug" ]; then
        echo ""
        echo "Release tools:"
        ls -la "${VCPKG_DIR}/installed/${TRIPLET}/tools/ffmpeg/"*.exe 2>/dev/null || echo "  (none found)"
        echo ""
        echo "Release libraries:"
        ls -la "${VCPKG_DIR}/installed/${TRIPLET}/lib/"*.lib 2>/dev/null | head -10 || echo "  (none found)"
    fi
    
    if [ "$BUILD_MODE_ARG" = "both" ] || [ "$BUILD_MODE_ARG" = "debug" ]; then
        echo ""
        echo "Debug tools:"
        ls -la "${VCPKG_DIR}/installed/${TRIPLET}/tools/ffmpeg/debug/"*.exe 2>/dev/null || echo "  (none found)"
        echo ""
        echo "Debug libraries:"
        ls -la "${VCPKG_DIR}/installed/${TRIPLET}/debug/lib/"*.lib 2>/dev/null | head -10 || echo "  (none found)"
    fi
    
    echo ""
    echo "==========================================" 
    echo "To use FFmpeg:"
    if [ "$BUILD_MODE_ARG" != "debug" ]; then
        echo "  Release: ${VCPKG_DIR}/installed/${TRIPLET}/tools/ffmpeg/ffmpeg.exe"
    fi
    if [ "$BUILD_MODE_ARG" = "both" ] || [ "$BUILD_MODE_ARG" = "debug" ]; then
        echo "  Debug:   ${VCPKG_DIR}/installed/${TRIPLET}/tools/ffmpeg/debug/ffmpeg.exe"
    fi
    echo "==========================================" 
else
    echo ""
    echo "Build FAILED! Check log: ${LOG_FILE}"
    exit 1
fi