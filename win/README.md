# FFmpeg Windows MSVC Build Guide

本文档说明如何使用 MSVC 工具链在 Windows 上构建 FFmpeg，并启用 libopencv 支持。

## 特性

- **Out-of-tree 构建**：源码和构建目录分离
- **Debug/Release 双版本**：支持分别构建调试版和发布版
- **OpenCV 支持**：启用 `libopencv`，支持 `ocv` 和 `oc_plugin` 滤镜

## 环境要求

| 软件 | 版本 | 说明 |
|----------|---------|-------------|
| Visual Studio | 2019/2022 | 需要 C++ 桌面开发工作负载 |
| MSYS2 | 最新版 | 提供 Unix 构建环境 |
| vcpkg | 最新版 | C++ 包管理器 |

### 路径配置

以下路径在 `build.sh` 中配置：

| 变量 | 默认值 | 说明 |
|----------|--------|------|
| `FFMPEG_SRC` | `$HOME/work/ffmpeg` | FFmpeg 源码目录 |
| `VCPKG_ROOT` | `$HOME/work/vcpkg` | vcpkg 安装目录 |

## 快速开始

### 构建 Release 版本

```powershell
.\build.bat release
```

### 构建 Debug 版本

```powershell
.\build.bat debug
```

## 输出目录结构

```
ffmpeg-ci/win/
├── build.bat              # Windows 入口脚本
├── build.sh               # MSYS2 构建脚本
├── build-release/         # Release 构建目录
├── build-debug/           # Debug 构建目录
├── install-release/       # Release 安装目录
│   ├── bin/
│   │   ├── ffmpeg.exe
│   │   ├── ffprobe.exe
│   │   ├── opencv_core4.dll
│   │   └── opencv_imgproc4.dll
│   ├── include/
│   └── lib/
└── install-debug/         # Debug 安装目录
```

## 验证构建

```powershell
# 检查版本和配置
.\install-release\bin\ffmpeg.exe -version

# 确认 OpenCV 滤镜已启用
.\install-release\bin\ffmpeg.exe -filters | findstr ocv
```

应输出：
```
 .. ocv               V->V       Apply transform using libopencv.
 .. oc_plugin         N->N       Apply processing using external OpenCV plugin.
```

## 手动构建步骤

如果自动脚本失败，可以按以下步骤手动构建：

### 步骤 1：安装 vcpkg 依赖

```powershell
cd $env:VCPKG_ROOT
.\vcpkg.exe install --triplet=x64-windows opencv4
```

### 步骤 2：启动 MSVC + MSYS2 环境

1. 打开 **x64 Native Tools Command Prompt for VS 2022**
2. 启动 MSYS2:
   ```cmd
   C:\msys64\msys2_shell.cmd -msys2 -use-full-path -defterm -no-start
   ```

### 步骤 3：Out-of-tree 配置和编译

```bash
# 设置环境变量 (根据实际路径修改)
export FFMPEG_SRC="/c/path/to/ffmpeg"
export VCPKG_ROOT="/c/path/to/vcpkg"

# 创建构建目录
mkdir -p build-release
cd build-release

# 配置
"$FFMPEG_SRC/configure" \
    --prefix="$(pwd)/../install-release" \
    --toolchain=msvc \
    --enable-debug \
    --disable-doc \
    --enable-libopencv \
    --extra-cflags="-I${VCPKG_ROOT}/installed/x64-windows/include/opencv4" \
    --extra-cxxflags="-I${VCPKG_ROOT}/installed/x64-windows/include/opencv4" \
    --extra-ldflags="-LIBPATH:${VCPKG_ROOT}/installed/x64-windows/lib" \
    --extra-libs="opencv_core4.lib opencv_imgproc4.lib"

# 修复 C++ 标准版本（FFmpeg 默认 c++17，但 vf_oc_plugin.cpp 需要 c++20）
sed -i 's|/std:c++17|/std:c++20|g' ffbuild/config.mak

# 编译安装
make -j$(nproc)
make install
```

## 常见问题

**Q: 配置时报错 "cl.exe not found"？**
A: 必须从 VS Developer Command Prompt 启动 MSYS2，使用 `-use-full-path` 参数继承环境变量。

**Q: 编译 vf_oc_plugin.cpp 报错 "requires at least '/std:c++20'"？**
A: FFmpeg 默认使用 `/std:c++17`，需要在 configure 后手动修改 `ffbuild/config.mak`，将 `/std:c++17` 替换为 `/std:c++20`。`build.sh` 会自动处理。

**Q: OpenCV 滤镜运行时找不到 DLL？**
A: 确保 `opencv_core4.dll` 和 `opencv_imgproc4.dll` 在 PATH 中或与 ffmpeg.exe 同目录。`build.sh` 会自动复制这些 DLL 到安装目录。

**Q: 如何重新配置？**
A: 删除 `build-release/config.h` 文件后重新运行 `build.bat`。
