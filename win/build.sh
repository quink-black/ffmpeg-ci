#!/bin/bash
# FFmpeg MSVC 构建脚本
# 使用方法: 在 MSYS2 环境中执行 (需要先加载VS环境)
# 
# 前置条件:
# 1. 打开 "x64 Native Tools Command Prompt for VS 2022"
# 2. 执行: C:\msys64\msys2_shell.cmd -msys2 -use-full-path -defterm -no-start
# 3. cd 到本脚本目录执行: ./build.sh

set -e

# 配置路径 (请根据实际环境修改)
FFMPEG_SRC="${FFMPEG_SRC:-$HOME/work/ffmpeg}"  # FFmpeg 源码目录
VCPKG_ROOT="${VCPKG_ROOT:-$HOME/work/vcpkg}"   # vcpkg 安装目录
BUILD_DIR="$(pwd)/build-release"
INSTALL_DIR="$(pwd)/install-release"

# 如果 VCPKG_ROOT 指向 VS 安装目录或无效，则重置为 $HOME/work/vcpkg
if [ ! -d "${VCPKG_ROOT}/installed" ]; then
    echo "检测到 VCPKG_ROOT 无效或指向非 vcpkg 目录: ${VCPKG_ROOT}"
    VCPKG_ROOT="$HOME/work/vcpkg"
fi
if [ ! -d "${VCPKG_ROOT}/installed" ]; then
    echo "错误: vcpkg 目录不存在或未安装依赖: ${VCPKG_ROOT}"
    exit 1
fi

# vcpkg 和 OpenCV 路径
VCPKG_TRIPLET_DIR="${VCPKG_ROOT}/installed/x64-windows"
OPENCV_INC="${VCPKG_TRIPLET_DIR}/include/opencv4"
VCPKG_LIB_DIR="${VCPKG_TRIPLET_DIR}/lib"

# vcpkg pkg-config 路径
export PKG_CONFIG_PATH="${VCPKG_LIB_DIR}/pkgconfig"
export PKG_CONFIG_LIBDIR="$PKG_CONFIG_PATH"

# 构建类型: debug 或 release
BUILD_TYPE="${1:-release}"

if [ "$BUILD_TYPE" = "vcpkg" ]; then
    TRIPLET="${2:-x64-windows}"
    OVERLAY_ROOT="$(pwd)/vcpkg-overlay"
    OVERLAY_PORT="${OVERLAY_ROOT}/ffmpeg"
    PORTFILE="${OVERLAY_PORT}/portfile.cmake"
    FFMPEG_SRC_WIN="$(cygpath -m "$FFMPEG_SRC")"

    echo "=========================================="
    echo "vcpkg overlay build (local ffmpeg)"
    echo "FFmpeg源码: $FFMPEG_SRC"
    echo "vcpkg目录: $VCPKG_ROOT"
    echo "overlay端口: $OVERLAY_PORT"
    echo "triplet: $TRIPLET"
    echo "=========================================="

    if [ ! -d "$FFMPEG_SRC" ]; then
        echo "错误: FFmpeg 源码目录不存在: $FFMPEG_SRC"
        exit 1
    fi

    if [ ! -f "${VCPKG_ROOT}/vcpkg" ] && [ ! -f "${VCPKG_ROOT}/vcpkg.exe" ]; then
        echo "错误: 未找到 vcpkg 可执行文件: $VCPKG_ROOT"
        exit 1
    fi

    rm -rf "$OVERLAY_PORT"
    mkdir -p "$OVERLAY_ROOT"
    cp -r "${VCPKG_ROOT}/ports/ffmpeg" "$OVERLAY_PORT"

    if [ ! -f "$PORTFILE" ]; then
        echo "错误: overlay 端口缺少 portfile.cmake"
        exit 1
    fi

    export PORTFILE
    export FFMPEG_SRC_WIN
    python - <<'PY'
import os
import pathlib
import re

portfile = os.environ["PORTFILE"]
src = os.environ["FFMPEG_SRC_WIN"]
text = pathlib.Path(portfile).read_text(encoding="utf-8")
text = re.sub(r"vcpkg_from_github\([\s\S]*?\)\n", f"set(SOURCE_PATH \"{src}\")\n", text, count=1)
text = text.replace(
    'set(OPTIONS "--enable-pic --disable-doc --enable-runtime-cpudetect --disable-autodetect")',
    'set(OPTIONS "--enable-pic --disable-doc --enable-runtime-cpudetect --disable-autodetect")\n'
    'string(APPEND OPTIONS " --enable-libopencv --extra-cflags=-I\\"${CURRENT_INSTALLED_DIR}/include/opencv4\\" '
    '--extra-cxxflags=-I\\"${CURRENT_INSTALLED_DIR}/include/opencv4\\" '
    '--extra-ldflags=-libpath:\\"${CURRENT_INSTALLED_DIR}/lib\\" '
    '--extra-libs=\\"opencv_core4.lib opencv_imgproc4.lib\\"")'
)
pathlib.Path(portfile).write_text(text, encoding="utf-8")
PY

    if [ -f "${VCPKG_ROOT}/vcpkg.exe" ]; then
        VCPKG_BIN="${VCPKG_ROOT}/vcpkg.exe"
    else
        VCPKG_BIN="${VCPKG_ROOT}/vcpkg"
    fi

    "$VCPKG_BIN" install "ffmpeg[all-nonfree,ffmpeg,ffprobe,ffplay,avisynthplus,opengl,opencl,amf,openmpt,modplug,openh264,srt,ilbc,ssh,soxr,speex,vorbis,theora,vpx,webp,xml2,zlib,ass,fontconfig,fribidi,freetype,openjpeg,x264,x265,fdk-aac,aom,dav1d,mp3lame,snappy,opus,vulkan,zmq,rubberband]:${TRIPLET}" --overlay-ports="$OVERLAY_ROOT" --recurse
    exit 0
fi

if [ "$BUILD_TYPE" = "debug" ]; then
    BUILD_DIR="$(pwd)/build-debug"
    INSTALL_DIR="$(pwd)/install-debug"
    DEBUG_FLAGS="--enable-debug --disable-optimizations"
else
    DEBUG_FLAGS="--enable-debug"
fi

# 创建构建目录
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo "=========================================="
echo "FFmpeg MSVC Build"
echo "=========================================="
echo "FFmpeg源码: $FFMPEG_SRC"
echo "构建目录: $BUILD_DIR"
echo "安装目录: $INSTALL_DIR"
echo "构建类型: $BUILD_TYPE"
echo "=========================================="

# 检查是否需要配置
if [ ! -f "config.h" ]; then
    echo "[1/3] 配置中..."
    # Let configure detect SDK features and only request optional libraries
    # advertised by this FFmpeg checkout and installed in the vcpkg triplet.
    CONFIGURE_HELP="$("$FFMPEG_SRC/configure" --help)"
    THIRD_PARTY_FLAGS=(--enable-gpl --enable-version3 --enable-nonfree)
    enable_feature() {
        if grep -qE "^[[:space:]]+--(enable|disable)-$1([[:blank:]]|$)" <<<"$CONFIGURE_HELP"; then
            THIRD_PARTY_FLAGS+=("--enable-$1")
        fi
    }
    while read -r feature module; do
        if pkg-config --exists "$module"; then
            enable_feature "$feature"
        fi
    done <<'LIBRARIES'
libx264 x264
libx265 x265
libfdk-aac fdk-aac
openssl openssl
avisynth avisynth
libaom aom
libass libass
libdav1d dav1d
libfreetype freetype2
libfontconfig fontconfig
libfribidi fribidi
libopenjpeg libopenjp2
libopenmpt libopenmpt
libopus opus
libsnappy snappy
libsoxr soxr
libspeex speex
libtheora theoraenc
libvorbis vorbisenc
libvpx vpx
libwebp libwebp
libxml2 libxml-2.0
libmodplug libmodplug
libopenh264 openh264
libsrt srt
libilbc libilbc
libssh libssh
opencl OpenCL
libtesseract tesseract
libmfx libmfx
libzmq libzmq
librubberband rubberband
opengl opengl
LIBRARIES
    if [ -f "$VCPKG_LIB_DIR/mp3lame.lib" ]; then
        enable_feature libmp3lame
    fi

    # Match the dynamic MSVC runtime used by the x64-windows vcpkg triplet.
    "$FFMPEG_SRC/configure" \
        --prefix="$INSTALL_DIR" \
        --toolchain=msvc \
        $DEBUG_FLAGS \
        --disable-doc \
        --enable-libopencv \
        "${THIRD_PARTY_FLAGS[@]}" \
        --extra-cflags="-MD -I${VCPKG_TRIPLET_DIR}/include -I${OPENCV_INC}" \
        --extra-cxxflags="-MD -I${VCPKG_TRIPLET_DIR}/include -I${OPENCV_INC}" \
        --extra-ldflags="-LIBPATH:${VCPKG_LIB_DIR}" \
        --extra-libs="opencv_core4.lib opencv_imgproc4.lib"
    
    # 修复C++标准版本：FFmpeg默认使用c++17，但vf_oc_plugin.cpp需要c++20
    echo "修复C++标准版本为c++20..."
    sed -i 's|/std:c++17|/std:c++20|g' ffbuild/config.mak
else
    echo "[1/3] 已配置，跳过..."
fi

# 编译
echo "[2/3] 编译中..."
make -j$(nproc)

# 安装
echo "[3/3] 安装中..."
make install

# 复制 vcpkg 运行时 DLL
echo "复制 vcpkg DLL..."
applocal="${VCPKG_ROOT}/scripts/buildsystems/msbuild/applocal.ps1"
if [ -f "$applocal" ]; then
    applocal_win="$(cygpath -w "$applocal")"
    vcpkg_bin_win="$(cygpath -w "${VCPKG_TRIPLET_DIR}/bin")"
    for program in ffmpeg ffprobe ffplay; do
        executable="$INSTALL_DIR/bin/$program.exe"
        if [ -f "$executable" ]; then
            powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$applocal_win" \
                -targetBinary "$(cygpath -w "$executable")" -installedDir "$vcpkg_bin_win"
        fi
    done
else
    cp "${VCPKG_TRIPLET_DIR}/bin/opencv_core4.dll" "$INSTALL_DIR/bin/" 2>/dev/null || true
    cp "${VCPKG_TRIPLET_DIR}/bin/opencv_imgproc4.dll" "$INSTALL_DIR/bin/" 2>/dev/null || true
fi

echo "=========================================="
echo "构建完成!"
echo "输出目录: $INSTALL_DIR"
echo "=========================================="
