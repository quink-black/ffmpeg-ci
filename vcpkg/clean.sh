#!/bin/bash
# =============================================================================
# FFmpeg Build Cleanup Script
# =============================================================================
# Usage: ./clean.sh [triplet]
#   triplet : Specific triplet to clean (default: x64-windows)
# =============================================================================

VCPKG_DIR="${HOME}/work/vcpkg"
TRIPLET="${1:-x64-windows}"

echo "Cleaning FFmpeg build artifacts for triplet: ${TRIPLET}"

# Remove from vcpkg
"${VCPKG_DIR}/vcpkg.exe" remove ffmpeg:${TRIPLET} --recurse 2>/dev/null || true

# Clean build trees
rm -rf "${VCPKG_DIR}/buildtrees/ffmpeg"

# Clean packages
rm -rf "${VCPKG_DIR}/packages/ffmpeg_${TRIPLET}"

echo "Clean completed."