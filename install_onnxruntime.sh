#!/bin/bash
# Install the native CPU files from Microsoft's ONNX Runtime NuGet package.
# Set ONNXRUNTIME_VERSION to select a different package version.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${DIR:=${SCRIPT_DIR}}"
: "${install_dir:=${DIR}/install}"

default_version=1.32.0
ARCH="$(uname -m)"
OS="$(uname -s)"

case "${ARCH}:${OS}" in
    x86_64:Linux*)  rid=linux-x64 ;;
    aarch64:Linux*) rid=linux-arm64 ;;
    arm64:Darwin*)  rid=osx-arm64 ;;
    x86_64:Darwin*)
        rid=osx-x64
        # This is the last release with an Intel macOS library in the NuGet package.
        default_version=1.23.2
        ;;
    x86_64:MINGW*|x86_64:MSYS*|x86_64:CYGWIN*) rid=win-x64 ;;
    *) echo "install_onnxruntime.sh: unsupported ${ARCH}/${OS}" >&2; exit 1 ;;
esac

if ! command -v unzip >/dev/null 2>&1; then
    echo "install_onnxruntime.sh: 'unzip' required" >&2
    exit 1
fi

VER="${ONNXRUNTIME_VERSION:-$default_version}"
package=microsoft.ml.onnxruntime
PKG="${package}.${VER}.nupkg"
URL="https://api.nuget.org/v3-flatcontainer/${package}/${VER}/${PKG}"

STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT

echo "==> Downloading ${URL}"
if command -v curl >/dev/null 2>&1; then
    curl -fL -o "${STAGE}/${PKG}" "${URL}"
else
    wget -O "${STAGE}/${PKG}" "${URL}"
fi

echo "==> Extracting native files for ${rid}"
src_lib="runtimes/${rid}/native"
src_include="build/native/include"
if ! unzip -q "${STAGE}/${PKG}" "${src_include}/*" "${src_lib}/*" -d "${STAGE}"; then
    echo "install_onnxruntime.sh: package ${VER} lacks native files for ${rid}" >&2
    exit 1
fi
src_lib="${STAGE}/${src_lib}"
src_include="${STAGE}/${src_include}"

echo "==> Installing into ${install_dir}"
mkdir -p "${install_dir}/include" "${install_dir}/lib"
cp -a "${src_include}/." "${install_dir}/include/"

if [ "$rid" = win-x64 ]; then
    # Keep both the MSVC import library and a MinGW import library for the DLL.
    mkdir -p "${install_dir}/bin"
    cp -a "${src_lib}/onnxruntime.dll" "${install_dir}/bin/"
    cp -a "${src_lib}/onnxruntime.lib" "${install_dir}/lib/"
    if [ -f "${src_lib}/onnxruntime_providers_shared.dll" ]; then
        cp -a "${src_lib}/onnxruntime_providers_shared.dll" "${install_dir}/bin/"
    fi
    if [ -f "${src_lib}/onnxruntime_providers_shared.lib" ]; then
        cp -a "${src_lib}/onnxruntime_providers_shared.lib" "${install_dir}/lib/"
    fi

    if ! command -v dlltool >/dev/null 2>&1; then
        echo "install_onnxruntime.sh: 'dlltool' not found" >&2
        exit 1
    fi

    # gendef ships in mingw-w64-tools but may live in a sibling MSYS2
    # subsystem bin/ that is not on PATH (e.g. mingw64/ while the active
    # shell runs from ucrt64/). Derive the MSYS2 root from a tool that IS
    # on PATH (dlltool) and search the standard subsystem directories, so
    # this works regardless of which MSYS2 shell launched the script.
    GENDEF="$(command -v gendef || true)"
    if [ -z "${GENDEF}" ]; then
        DLLTOOL_BIN="$(command -v dlltool)"
        MSYS_ROOT="$(dirname "$(dirname "$(dirname "${DLLTOOL_BIN}")")")"
        for sub in mingw64 ucrt64 clang64 clangarm64 clang32; do
            for cand in "${MSYS_ROOT}/${sub}/bin/gendef" \
                        "${MSYS_ROOT}/${sub}/bin/gendef.exe"; do
                if [ -x "${cand}" ]; then
                    GENDEF="${cand}"
                    break 2
                fi
            done
        done
    fi
    if [ -z "${GENDEF}" ]; then
        echo "install_onnxruntime.sh: could not locate gendef near ${MSYS_ROOT}" >&2
        exit 1
    fi

    # gendef writes onnxruntime.def next to the DLL; feed it to dlltool to
    # produce the import library that -lonnxruntime resolves to under mingw.
    ( cd "${install_dir}/bin" && "${GENDEF}" onnxruntime.dll >/dev/null 2>&1 )
    if [ ! -f "${install_dir}/bin/onnxruntime.def" ]; then
        echo "install_onnxruntime.sh: gendef failed on onnxruntime.dll" >&2
        exit 1
    fi
    dlltool -d "${install_dir}/bin/onnxruntime.def" \
            -l "${install_dir}/lib/libonnxruntime.dll.a" \
            -k
    rm -f "${install_dir}/bin/onnxruntime.def"

    echo "==> Installed:"
    ls -l "${install_dir}/include/onnxruntime_c_api.h"
    ls -l "${install_dir}/bin/onnxruntime.dll"
    ls -l "${install_dir}/lib/onnxruntime.lib"
    ls -l "${install_dir}/lib/libonnxruntime.dll.a"
elif [[ "$rid" = linux-* ]]; then
    # NuGet stores the linker name, while the ELF SONAME is libonnxruntime.so.1.
    cp -a "${src_lib}/libonnxruntime.so" "${install_dir}/lib/libonnxruntime.so.${VER}"
    ln -sfn "libonnxruntime.so.${VER}" "${install_dir}/lib/libonnxruntime.so.1"
    ln -sfn libonnxruntime.so.1 "${install_dir}/lib/libonnxruntime.so"
    if [ -f "${src_lib}/libonnxruntime_providers_shared.so" ]; then
        cp -a "${src_lib}/libonnxruntime_providers_shared.so" "${install_dir}/lib/"
    fi
else
    # Older dylibs use the full version in their install name.
    cp -a "${src_lib}/libonnxruntime.dylib" "${install_dir}/lib/libonnxruntime.${VER}.dylib"
    ln -sfn "libonnxruntime.${VER}.dylib" "${install_dir}/lib/libonnxruntime.1.dylib"
    ln -sfn libonnxruntime.1.dylib "${install_dir}/lib/libonnxruntime.dylib"
fi

echo
echo "Done. Rebuild FFmpeg with:"
echo "  ./cibuild.sh --path ../ffmpeg --skip-test"
echo "The build will probe the installed ONNX Runtime headers and library."
