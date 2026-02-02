#!/bin/bash
# Build FFmpeg with vcpkg - Unified build script
# Usage: ./build.sh [--debug] [--debug-only] [--force]
#   --debug      : Build both Release and Debug configurations (default: Release only)
#   --debug-only : Build only Debug configuration (skip Release, for testing)
#   --force      : Force rebuild even if already installed

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Derive paths relative to user home
MSYS_HOME="${HOME}"
VCPKG_DIR="${MSYS_HOME}/work/vcpkg"
OVERLAY_PORTS="${SCRIPT_DIR}"
TRIPLET="x64-windows"
BUILD_DEBUG=0
BUILD_DEBUG_ONLY=0
FORCE_REBUILD=0

# Auto-detect Visual Studio installation
detect_visual_studio() {
    local VS_YEARS=("2022" "2019")
    local VS_EDITIONS=("Enterprise" "Professional" "Community" "BuildTools")
    local VS_BASE="/c/Program Files/Microsoft Visual Studio"
    
    for year in "${VS_YEARS[@]}"; do
        for edition in "${VS_EDITIONS[@]}"; do
            local vs_path="${VS_BASE}/${year}/${edition}"
            if [ -d "${vs_path}" ]; then
                # Convert MSYS path to Windows path
                local win_path="C:/Program Files/Microsoft Visual Studio/${year}/${edition}/"
                echo "${win_path}"
                return 0
            fi
        done
    done
    
    echo "ERROR: Could not find Visual Studio installation" >&2
    return 1
}

# Setup Windows environment variables dynamically
setup_windows_env() {
    local username
    username=$(whoami)
    
    export LOCALAPPDATA="C:/Users/${username}/AppData/Local"
    export APPDATA="C:/Users/${username}/AppData/Roaming"
    export TEMP="C:/Users/${username}/AppData/Local/Temp"
    export TMP="C:/Users/${username}/AppData/Local/Temp"
    unset VCPKG_ROOT
    
    local vs_install
    vs_install=$(detect_visual_studio)
    if [ $? -ne 0 ]; then
        echo "Failed to detect Visual Studio"
        exit 1
    fi
    
    export VSINSTALLDIR="${vs_install}"
    export VS170COMNTOOLS="${vs_install}Common7/Tools/"
    
    echo "Using Visual Studio: ${vs_install}"
}

# Parse arguments
for arg in "$@"; do
    case $arg in
        --debug) BUILD_DEBUG=1 ;;
        --debug-only) BUILD_DEBUG_ONLY=1 ;;
        --force) FORCE_REBUILD=1 ;;
        --help|-h) 
            echo "Usage: $0 [--debug] [--debug-only] [--force]"
            echo "  --debug      : Build both Release and Debug configurations"
            echo "  --debug-only : Build only Debug configuration (skip Release, for testing)"
            echo "  --force      : Force rebuild even if already installed"
            exit 0 
            ;;
    esac
done

# Setup environment
setup_windows_env
# Copy custom triplet file to vcpkg triplets directory
CUSTOM_TRIPLET_FILE="${SCRIPT_DIR}/x64-windows-static-md.cmake"
if [ -f "${CUSTOM_TRIPLET_FILE}" ]; then
    cp "${CUSTOM_TRIPLET_FILE}" "${VCPKG_DIR}/triplets/"
    echo "Copied custom triplet: x64-windows-static-md.cmake"
fi


# Configure triplet file
TRIPLET_FILE="${VCPKG_DIR}/triplets/${TRIPLET}.cmake"
sed -i "/VCPKG_BUILD_TYPE/d" "${TRIPLET_FILE}"
sed -i "/Debug build/d" "${TRIPLET_FILE}"

if [ $BUILD_DEBUG_ONLY -eq 1 ]; then
    BUILD_MODE="Debug only"
    LOG_FILE="${MSYS_HOME}/ffmpeg_debug_only_build.log"
    echo "# Debug only build" >> "${TRIPLET_FILE}"
    echo "set(VCPKG_BUILD_TYPE debug)" >> "${TRIPLET_FILE}"
elif [ $BUILD_DEBUG -eq 1 ]; then
    BUILD_MODE="Release + Debug"
    LOG_FILE="${MSYS_HOME}/ffmpeg_debug_build.log"
    echo "# Debug build enabled" >> "${TRIPLET_FILE}"
else
    BUILD_MODE="Release only"
    LOG_FILE="${MSYS_HOME}/ffmpeg_release_build.log"
    echo "set(VCPKG_BUILD_TYPE release)" >> "${TRIPLET_FILE}"
fi

if [ $FORCE_REBUILD -eq 1 ]; then
    echo "Force rebuild..."
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
# Note: We manually specify features instead of using 'all-gpl' to exclude 'qsv'.
# qsv feature requires libmfx (mfx-dispatch) which only has Release builds,
# causing RuntimeLibrary mismatch errors (MD vs MDd) in Debug builds.
#
# Features included from all-gpl minus qsv:
# - Core: avcodec, avdevice, avfilter, avformat, swresample, swscale
# - Codecs: aom, dav1d, mp3lame, opus, speex, theora, vorbis, vpx, webp, x264, x265, openh264, ilbc, snappy, openjpeg
# - Filters: opencv, ass, drawtext, freetype, fontconfig, fribidi
# - IO: iconv, xml2, bzip2, lzma, zlib, srt, ssh, modplug, openmpt
# - Hardware: opencl, amf, nvcodec (excluding qsv)
# - Other: ffmpeg, ffplay, sdl2, soxr, tesseract, gpl, vulkan
FFMPEG_FEATURES="gpl,avcodec,avdevice,avfilter,avformat,swresample,swscale"
FFMPEG_FEATURES="${FFMPEG_FEATURES},ffmpeg,ffplay,sdl2"
FFMPEG_FEATURES="${FFMPEG_FEATURES},aom,dav1d,mp3lame,opus,speex,theora,vorbis,vpx,webp,x264,x265,openh264,ilbc,snappy,openjpeg"
FFMPEG_FEATURES="${FFMPEG_FEATURES},opencv,ass,drawtext,freetype,fontconfig,fribidi"
FFMPEG_FEATURES="${FFMPEG_FEATURES},iconv,xml2,bzip2,lzma,zlib,srt,ssh,modplug,openmpt"
FFMPEG_FEATURES="${FFMPEG_FEATURES},opencl,amf,nvcodec"
FFMPEG_FEATURES="${FFMPEG_FEATURES},soxr,tesseract,vulkan"

./vcpkg.exe install "ffmpeg[${FFMPEG_FEATURES}]" --overlay-ports="${OVERLAY_PORTS}" --triplet="${TRIPLET}" --recurse 2>&1 | tee "${LOG_FILE}"

if [ $? -eq 0 ]; then
    echo "Build completed!"
    ls -la "${VCPKG_DIR}/installed/${TRIPLET}/bin/av*.dll" 2>/dev/null || true
    [ $BUILD_DEBUG -eq 1 ] && ls -la "${VCPKG_DIR}/installed/${TRIPLET}/debug/bin/av*.dll" 2>/dev/null || true
    ls -la "${VCPKG_DIR}/installed/${TRIPLET}/tools/ffmpeg/"*.exe 2>/dev/null || true
else
    echo "Build FAILED! Check: ${LOG_FILE}"
    exit 1
fi
