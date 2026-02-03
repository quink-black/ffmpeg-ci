# FFmpeg Custom vcpkg Build

这是一个简化的 vcpkg overlay port，用于构建带OpenCV插件功能的FFmpeg。

## 目录结构

```
~/work/
├── vcpkg/              # vcpkg 安装目录
├── ffmpeg/             # FFmpeg 源码目录
└── ffmpeg-ci/
    └── vcpkg/          # 本 overlay port 目录
        ├── build.sh        # 构建脚本
        ├── clean.sh        # 清理脚本
        ├── README.md       # 本文档
        └── ffmpeg/         # FFmpeg port 定义
            ├── vcpkg.json      # 包配置
            ├── portfile.cmake  # 构建逻辑
            └── build.sh.in     # 构建模板
```

## 快速开始

### 前置条件

1. **Visual Studio 2019/2022** (Community/Professional/Enterprise)
2. **MSYS2** 环境 (用于运行 bash 脚本)
3. **vcpkg** 安装在 `~/work/vcpkg`
4. **FFmpeg 源码** 在 `~/work/ffmpeg`

### 构建命令

```bash
# 只构建 Release 版本 (默认)
./build.sh

# 构建 Release + Debug 两个版本
./build.sh --debug

# 强制重新构建
./build.sh --force

# 清理后重新构建
./build.sh --clean
```

### 清理命令

```bash
# 清理所有构建产物
./clean.sh

# 清理指定 triplet
./clean.sh x64-windows
```

## 输出文件位置

构建完成后，文件位于：

### Release 版本
```
~/work/vcpkg/installed/x64-windows/
├── tools/ffmpeg/
│   ├── ffmpeg.exe      # FFmpeg 主程序
│   └── ffprobe.exe     # FFprobe 工具
├── lib/                # 静态库 (.lib)
├── include/            # 头文件
└── bin/                # DLL (如果是动态链接)
```

### Debug 版本 (使用 --debug 构建时)
```
~/work/vcpkg/installed/x64-windows/
├── tools/ffmpeg/debug/
│   ├── ffmpeg.exe      # Debug 版 FFmpeg
│   └── ffprobe.exe     # Debug 版 FFprobe
└── debug/
    └── lib/            # Debug 静态库
```

## 包含的功能

### 核心库
- avcodec, avdevice, avfilter, avformat, swresample, swscale

### 编解码器
- **视频**: x264 (H.264), x265 (HEVC), vpx (VP8/VP9), aom (AV1)
- **音频**: mp3lame (MP3), opus

### 滤镜扩展
- **OpenCV** - 视频滤镜处理
- **Tesseract** - OCR 文字识别

### 工具
- ffmpeg - 音视频转码
- ffprobe - 媒体信息分析

## 开发者指南：编译自定义插件

如果你需要编译自己的 FFmpeg 插件并用我们的 FFmpeg 运行：

### 1. 使用 Debug 版本构建

```bash
./build.sh --debug
```

### 2. 配置你的插件项目

在你的 CMakeLists.txt 中：

```cmake
# 添加 FFmpeg 头文件路径
include_directories(
    ~/work/vcpkg/installed/x64-windows/include
)

# Debug 配置时链接 Debug 库
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    link_directories(~/work/vcpkg/installed/x64-windows/debug/lib)
    # 运行时库使用 /MDd
    set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreadedDebugDLL")
else()
    link_directories(~/work/vcpkg/installed/x64-windows/lib)
    # 运行时库使用 /MD
    set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreadedDLL")
endif()

# 链接 FFmpeg 库
target_link_libraries(your_plugin
    avcodec
    avformat
    avutil
    swresample
    swscale
)
```

### 3. 运行时库兼容性

**重要**: 确保你的插件使用正确的运行时库：
- **Release**: `/MD` (Multi-threaded DLL)
- **Debug**: `/MDd` (Multi-threaded Debug DLL)

如果运行时库不匹配，会出现链接错误或运行时崩溃。

## 故障排除

### 找不到 FFmpeg 源码
确保 FFmpeg 源码在 `~/work/ffmpeg` 目录。

### 构建失败
查看日志文件：
- Release: `~/ffmpeg_release_build.log`
- Debug: `~/ffmpeg_build.log`

### 运行时库不匹配
错误信息类似：`error LNK2038: mismatch detected for 'RuntimeLibrary'`

解决方法：确保你的项目和 FFmpeg 使用相同的运行时库配置。

## 许可证

FFmpeg 使用 GPL v3 许可证（因为启用了 x264/x265）。