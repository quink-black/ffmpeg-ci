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

# Configure build mode via marker file (read by portfile.cmake)
# Note: Environment variables and --x-cmake-args don't work reliably with portfile.cmake
# So we use a marker file that portfile.cmake can check
BUILD_MODE_FILE="${VCPKG_DIR}/buildtrees/ffmpeg/.build_mode"
mkdir -p "${VCPKG_DIR}/buildtrees/ffmpeg"

case "$BUILD_MODE_ARG" in
    "both")
        BUILD_MODE="Release + Debug"
        LOG_FILE="${HOME}/ffmpeg_build.log"
        echo "both" > "${BUILD_MODE_FILE}"
        ;;
    "debug")
        BUILD_MODE="Debug only"
        LOG_FILE="${HOME}/ffmpeg_debug_build.log"
        echo "debug" > "${BUILD_MODE_FILE}"
        ;;
    *)
        BUILD_MODE="Release only"
        LOG_FILE="${HOME}/ffmpeg_release_build.log"
        echo "release" > "${BUILD_MODE_FILE}"
        ;;
esac

# Clean if requested
if [ $CLEAN_FIRST -eq 1 ] || [ $FORCE_REBUILD -eq 1 ]; then
    echo "Cleaning previous build..."
    "${VCPKG_DIR}/vcpkg.exe" remove ffmpeg:${TRIPLET} --recurse 2>/dev/null || true
    rm -rf "${VCPKG_DIR}/buildtrees/ffmpeg" "${VCPKG_DIR}/packages/ffmpeg_${TRIPLET}"
    # Recreate the marker file after cleaning
    mkdir -p "${VCPKG_DIR}/buildtrees/ffmpeg"
    case "$BUILD_MODE_ARG" in
        "both") echo "both" > "${BUILD_MODE_FILE}" ;;
        "debug") echo "debug" > "${BUILD_MODE_FILE}" ;;
        *) echo "release" > "${BUILD_MODE_FILE}" ;;
    esac
fi

echo ""
echo "=========================================="
echo "Building FFmpeg (${BUILD_MODE})"
echo "=========================================="
echo "VCPKG_DIR: ${VCPKG_DIR}"
echo "OVERLAY_PORTS: ${OVERLAY_PORTS}"
echo "LOG_FILE: ${LOG_FILE}"
echo "BUILD_MODE_FILE: ${BUILD_MODE_FILE}"
echo "BUILD_MODE_CONTENT: $(cat ${BUILD_MODE_FILE})"
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

    # ==========================================================================
    # Create package with ffmpeg tools, DLLs and PDBs
    # ==========================================================================
    echo ""
    echo "=========================================="
    echo "Creating FFmpeg package..."
    echo "=========================================="

    PACKAGE_DIR="${SCRIPT_DIR}/ffmpeg-package"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    PACKAGE_NAME="ffmpeg-${TRIPLET}-${TIMESTAMP}.zip"

    # Clean and create package directory structure
    rm -rf "${PACKAGE_DIR}"
    mkdir -p "${PACKAGE_DIR}/release"
    mkdir -p "${PACKAGE_DIR}/debug"

    TOOLS_DIR="${VCPKG_DIR}/installed/${TRIPLET}/tools/ffmpeg"
    DEBUG_TOOLS_DIR="${TOOLS_DIR}/debug"

    # Copy Release files (if not debug-only build)
    if [ "$BUILD_MODE_ARG" != "debug" ]; then
        echo "Copying release files..."
        # Copy exe files
        for exe in ffmpeg.exe ffprobe.exe ffplay.exe; do
            if [ -f "${TOOLS_DIR}/${exe}" ]; then
                cp "${TOOLS_DIR}/${exe}" "${PACKAGE_DIR}/release/"
                echo "  Copied: release/${exe}"
            fi
        done
        # Copy all DLLs (case-insensitive to handle .dll and .DLL)
        find "${TOOLS_DIR}" -maxdepth 1 -iname "*.dll" -type f | while read dll; do
            cp "$dll" "${PACKAGE_DIR}/release/"
            echo "  Copied: release/$(basename "$dll")"
        done
        # Copy PDB files from installed directory
        for pdb in "${VCPKG_DIR}/installed/${TRIPLET}/bin"/*.pdb; do
            if [ -f "$pdb" ]; then
                cp "$pdb" "${PACKAGE_DIR}/release/"
                echo "  Copied: release/$(basename $pdb)"
            fi
        done
        # Also check tools directory for PDBs
        for pdb in "${TOOLS_DIR}"/*.pdb; do
            if [ -f "$pdb" ]; then
                cp "$pdb" "${PACKAGE_DIR}/release/"
                echo "  Copied: release/$(basename $pdb)"
            fi
        done
    fi

    # Copy Debug files (if debug or both mode)
    if [ "$BUILD_MODE_ARG" = "both" ] || [ "$BUILD_MODE_ARG" = "debug" ]; then
        echo "Copying debug files..."
        # Copy exe files
        for exe in ffmpeg.exe ffprobe.exe ffplay.exe ffmpeg_g.exe ffprobe_g.exe ffplay_g.exe; do
            if [ -f "${DEBUG_TOOLS_DIR}/${exe}" ]; then
                cp "${DEBUG_TOOLS_DIR}/${exe}" "${PACKAGE_DIR}/debug/"
                echo "  Copied: debug/${exe}"
            fi
        done
        # Copy all DLLs (case-insensitive to handle .dll and .DLL)
        find "${DEBUG_TOOLS_DIR}" -maxdepth 1 -iname "*.dll" -type f | while read dll; do
            cp "$dll" "${PACKAGE_DIR}/debug/"
            echo "  Copied: debug/$(basename "$dll")"
        done
        # Copy PDB files from installed debug directory
        for pdb in "${VCPKG_DIR}/installed/${TRIPLET}/debug/bin"/*.pdb; do
            if [ -f "$pdb" ]; then
                cp "$pdb" "${PACKAGE_DIR}/debug/"
                echo "  Copied: debug/$(basename $pdb)"
            fi
        done
        # Also check debug tools directory for PDBs
        for pdb in "${DEBUG_TOOLS_DIR}"/*.pdb; do
            if [ -f "$pdb" ]; then
                cp "$pdb" "${PACKAGE_DIR}/debug/"
                echo "  Copied: debug/$(basename $pdb)"
            fi
        done
    fi

    # For debug-only build, also copy to release folder (since "release" tools are actually debug)
    if [ "$BUILD_MODE_ARG" = "debug" ]; then
        echo "Copying debug files to release folder (debug-only build)..."
        # Copy exe files from main tools dir
        for exe in ffmpeg.exe ffprobe.exe ffplay.exe; do
            if [ -f "${TOOLS_DIR}/${exe}" ]; then
                cp "${TOOLS_DIR}/${exe}" "${PACKAGE_DIR}/release/"
                echo "  Copied: release/${exe}"
            fi
        done
        # Copy all DLLs (case-insensitive to handle .dll and .DLL)
        find "${TOOLS_DIR}" -maxdepth 1 -iname "*.dll" -type f | while read dll; do
            cp "$dll" "${PACKAGE_DIR}/release/"
            echo "  Copied: release/$(basename "$dll")"
        done
        # Copy PDB files
        for pdb in "${TOOLS_DIR}"/*.pdb; do
            if [ -f "$pdb" ]; then
                cp "$pdb" "${PACKAGE_DIR}/release/"
                echo "  Copied: release/$(basename $pdb)"
            fi
        done
    fi

    # Create zip package
    echo ""
    echo "Creating zip package: ${PACKAGE_NAME}"
    cd "${SCRIPT_DIR}"
    
    # Check if zip command is available, otherwise use powershell
    if command -v zip &> /dev/null; then
        zip -r "${PACKAGE_NAME}" "ffmpeg-package"
    else
        # Use PowerShell for Windows
        powershell -Command "Compress-Archive -Path 'ffmpeg-package/*' -DestinationPath '${PACKAGE_NAME}' -Force"
    fi

    if [ -f "${SCRIPT_DIR}/${PACKAGE_NAME}" ]; then
        PACKAGE_SIZE=$(ls -lh "${SCRIPT_DIR}/${PACKAGE_NAME}" | awk '{print $5}')
        echo ""
        echo "=========================================="
        echo "Package created successfully!"
        echo "  Location: ${SCRIPT_DIR}/${PACKAGE_NAME}"
        echo "  Size: ${PACKAGE_SIZE}"
        echo "=========================================="
        echo ""
        echo "Package contents:"
        if [ "$BUILD_MODE_ARG" != "debug" ]; then
            echo "  release/  - Release binaries with DLLs and PDBs"
        fi
        if [ "$BUILD_MODE_ARG" = "both" ] || [ "$BUILD_MODE_ARG" = "debug" ]; then
            echo "  debug/    - Debug binaries with DLLs and PDBs"
        fi
        if [ "$BUILD_MODE_ARG" = "debug" ]; then
            echo "  release/  - Debug binaries (debug-only build)"
        fi
    else
        echo "Warning: Failed to create zip package"
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