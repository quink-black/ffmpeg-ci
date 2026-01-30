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

# OpenCV 路径
OPENCV_INC="${VCPKG_ROOT}/installed/x64-windows/include/opencv4"
OPENCV_LIB="${VCPKG_ROOT}/installed/x64-windows/lib"

# 构建类型: debug 或 release
BUILD_TYPE="${1:-release}"

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
    "$FFMPEG_SRC/configure" \
        --prefix="$INSTALL_DIR" \
        --toolchain=msvc \
        $DEBUG_FLAGS \
        --disable-doc \
        --enable-libopencv \
        --extra-cflags=-I"${OPENCV_INC}" \
        --extra-cxxflags=-I"${OPENCV_INC}" \
        --extra-ldflags=-LIBPATH:"${OPENCV_LIB}" \
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

# 复制 OpenCV DLL
echo "复制 OpenCV DLL..."
cp "${VCPKG_ROOT}/installed/x64-windows/bin/opencv_core4.dll" "$INSTALL_DIR/bin/" 2>/dev/null || true
cp "${VCPKG_ROOT}/installed/x64-windows/bin/opencv_imgproc4.dll" "$INSTALL_DIR/bin/" 2>/dev/null || true

echo "=========================================="
echo "构建完成!"
echo "输出目录: $INSTALL_DIR"
echo "=========================================="
