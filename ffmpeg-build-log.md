# FFmpeg CMake 构建系统 — 现状与待办

> 分支: `cmake-build-5`
> 开始时间: 2026-03-08
> 最后更新: 2026-03-29

---

## 1. 项目概述

将 FFmpeg 从 `configure + Makefile` 构建系统迁移到 CMake。目标是实现功能等价的 CMake 构建，支持 macOS、Linux x86_64、Linux aarch64 和 Windows MSVC 四个平台。

---

## 2. 架构设计

CMake 构建系统采用三层控制机制（详见 `cmake-build-control.md`）：

| 层级 | 文件 | 职责 |
|------|------|------|
| L1 | `FFmpegExternalLibs.cmake` | 外部库检测（pkg-config / find_package） |
| L2 | `FFmpegDependencyResolver.cmake` | 组件依赖解析（_deps / _select / _suggest / _if / _conflict） |
| L3 | `FFmpegComponents.cmake` + 各库 `CMakeLists.txt` | 生成 config_components.h、list 文件、条件编译源文件 |

### CMake 模块调用顺序

```
CMakeLists.txt (top-level)
├── FFmpegDefaults.cmake          # 默认选项、License 标志
├── FFmpegExternalLibs.cmake      # L1: 外部库检测
├── FFmpegComponentDeps.cmake     # 定义 _DEPS/_SELECT/_SUGGEST
├── FFmpegDependencyResolver.cmake# L2: 依赖解析
├── FFmpegComponents.cmake        # L3: 生成 config_components.h + list 文件
├── add_subdirectory(libav*)      # L3: 条件编译源文件
├── FFmpegApplyExternalLibs.cmake # 链接外部库到 target
└── add_subdirectory(fftools)     # 构建 ffmpeg/ffprobe/ffplay
```

---

## 3. 平台构建现状

### 3.1 macOS (Apple Silicon, aarch64)

| 项目 | 状态 |
|------|------|
| cmake 配置 | ✅ |
| ffmpeg | ✅ |
| ffplay | ✅ |
| ffprobe | ✅ |
| checkasm | ✅ |
| api-*-test | ✅ |
| 编码器 | 164 |
| 解码器 | 500 |
| 滤镜 | 247 |
| 硬件加速 | videotoolbox, opencl, vulkan |

### 3.2 Linux x86_64 (black.local)

| 项目 | 状态 |
|------|------|
| cmake 配置 | ✅ |
| ffmpeg | ✅ |
| ffplay | ✅ |
| ffprobe | ✅ |
| checkasm | ✅ |
| api-*-test | ✅ (2598/2598) |
| 编码器 | 181 |
| 解码器 | 505 |

### 3.3 Linux aarch64 (pi.local, Debian, GCC 12)

使用 `distcc aarch64-linux-gnu-gcc-12` + `DISTCC_HOSTS=black.local/24` 加速编译。

| 项目 | 状态 |
|------|------|
| cmake 配置 | ✅ (83.7s) |
| ffmpeg | ✅ |
| ffplay | ✅ |
| ffprobe | ✅ |
| checkasm | ✅ |
| api-*-test | ✅ (2377/2377) |
| 编码器 | 181 |
| 解码器 | 505 |

### 3.4 Windows MSVC

> 在 `cmake-build-3` 分支上验证过，尚未在 `cmake-build-5` 上重新验证。

| 项目 | 状态 |
|------|------|
| cmake 配置 | ✅ (cmake-build-3) |
| ffmpeg.exe | ✅ (cmake-build-3) |
| ffprobe.exe | ✅ (cmake-build-3) |
| ffplay.exe | ❌ 未测试 |
| 功能验证 | ❌ 未测试 |

---

## 4. 已解决的关键问题

### 4.1 依赖解析器初始化 Bug
- **问题**: `FFmpegDefaults.cmake` 将所有 `config.h.in` 变量设为 0，导致依赖解析器的 `if(NOT DEFINED)` 检查跳过初始化，大量组件（如 `RV40_DECODER`）被错误保持为 0
- **修复**: 初始化步骤改为无条件将所有有依赖定义的组件设为 1，跳过 CACHE 变量和纯外部库标志

### 4.2 SChannel/SecureTransport 平台检测缺失
- **问题**: `CONFIG_SCHANNEL` 没有平台检测，在 Linux 上被默认初始化为 1，导致 `DTLS_PROTOCOL` 和 `TLS_PROTOCOL` 的 `_deps_any` 检查被错误满足
- **修复**: 添加 SChannel（仅 Windows）和 SecureTransport（仅 macOS）的平台检测，使用 `CACHE INTERNAL` 变量

### 4.3 LZMA 链接缺失
- **问题**: `tiff.c` 使用 lzma 但链接时缺少 `-llzma`
- **修复**: 在 `FFmpegApplyExternalLibs.cmake` 中添加 LZMA 链接（支持 imported target / LIBLZMA_LIBRARIES / fallback `-llzma`）

### 4.4 TLS/DTLS/WHIP 条件编译缺失
- **问题**: `whip.c`、`tls.c`、`gophers`、`https` 协议在没有 TLS 库时仍被编译
- **修复**: 在 `libavformat/CMakeLists.txt` 中添加排除列表和条件编译，并在 `protocol_list.c` 生成时过滤 TLS 相关符号

### 4.5 VideoToolbox 文件排除不完整
- **问题**: `videotoolbox_av1.c` 和 `videotoolbox_vp9.c` 在 Linux 上被错误编译
- **修复**: 排除规则改为 `^videotoolbox` 前缀匹配，并在条件编译部分按 hwaccel CONFIG 添加

### 4.6 socklen_t 检测失败
- **问题**: `check_c_source_compiles` 在 Linux 上检测 socklen_t 失败
- **修复**: 对所有 POSIX 系统强制设为 `HAVE_SOCKLEN_T=1`

### 4.7 AudioToolbox 框架链接缺失
- **问题**: `audiotoolboxdec.c` 编译成功但链接时缺少 `-framework AudioToolbox`
- **修复**: 在 `libavcodec/CMakeLists.txt` 中添加 Apple 框架条件链接

### 4.8 libswscale Vulkan 子目录缺失
- **问题**: `libswscale/ops.c` 引用 `backend_vulkan`，但 `vulkan/ops.c` 未被编译
- **修复**: 在 `libswscale/CMakeLists.txt` 中添加 Vulkan 子目录文件的条件编译

### 4.9 宏定义编解码器/Filter 扫描
- **问题**: `pcm.c` 中的 `PCM_CODEC(...)` 宏、`af_biquads.c`/`vf_neighbor.c` 中的宏定义 filter 无法被 `file(STRINGS ...)` 扫描
- **修复**: 使用 `gcc -E` 预处理器展开宏后扫描；手动添加宏定义 filter 的 symbols

### 4.10 allcodecs.c 硬件加速编解码器
- **问题**: `allcodecs.c` 引用了所有编解码器（含 MediaCodec、MMAL、QSV 等），但这些实现文件不存在
- **修复**: 生成 `allcodecs_generated.c` 替代，只包含实际编译的编解码器

---

## 5. 待办事项

### P0 — 构建质量

- [ ] 在 `cmake-build-5` 分支上重新验证 Windows MSVC 构建
- [ ] 对比 configure 生成的 `config.h` 与 CMake 生成的 `config.h`，修复差异
- [ ] 对比 configure 构建与 CMake 构建的编解码器/Filter 数量差异（已知差异见下方）

### P1 — 已知差异修复

缺失的编解码器（与 configure 构建对比）：

| 编解码器 | 类型 | 原因 |
|---------|------|------|
| `aac_latm` | 音频 | codec_list 生成问题 |
| `dsd_lsbf` / `dsd_lsbf_planar` / `dsd_msbf` / `dsd_msbf_planar` | 音频 | codec_list 生成问题 |
| `avs2` / `avs3` | 视频 | 条件编译宏未定义 |

缺失的 Filter：

| Filter | 类型 | 原因 |
|--------|------|------|
| `aeval` | 音频 | 可能是 aevalsrc 别名 |
| `lutrgb` / `lutyuv` | 视频 | filter_list 生成问题 |
| `bwdif_cuda` / `overlay_cuda` / `yadif_cuda` | 视频 | 需要 CUDA 支持 |

### P1 — 功能测试

- [ ] 运行 checkasm 测试，验证汇编优化正确性
- [ ] 运行编解码功能测试（视频编码、音视频编码、转封装）
- [ ] 运行 FATE 测试子集

### P2 — Windows 功能验证

- [ ] 验证 `ffmpeg.exe -version` / `ffprobe.exe -version`
- [ ] 视频编码测试（testsrc → mpeg4）
- [ ] 音视频编码测试（testsrc + sine → mp4）
- [ ] 启用 D3D11VA / DXVA2 解码支持
- [ ] 启用 MediaFoundation 支持
- [ ] 添加 dshow / gdigrab 设备支持

### P2 — 第三方库完善

- [ ] 完善更多外部编解码器检测（librav1e、libsvtav1 等）
- [ ] Windows 上集成 OpenSSL（HTTPS/TLS 支持）
- [ ] Windows 上集成 x264/x265（H.264/H.265 编码）
- [ ] Windows 上集成 FreeType2（drawtext filter）

### P3 — 构建系统改进

- [ ] 支持共享库（.so / .dylib / .dll）构建
- [ ] 支持 `install` target
- [ ] 支持 `pkg-config` 文件生成
- [ ] 支持交叉编译工具链文件
- [ ] CI 集成（GitHub Actions / GitLab CI）

---

## 6. 提交历史（cmake-build-5 分支）

```
1ebad3f cmake: fix libavformat TLS/DTLS/WHIP conditional compilation for non-TLS platforms
6f7e950 cmake: add SChannel/SecureTransport platform detection, fix DTLS/TLS deps_any resolution
5ccfa5d cmake: add lzma and system library linking to avcodec
0f2d87a cmake: fix socklen_t detection for POSIX systems
a234455 cmake: fix videotoolbox file exclusion for Linux builds
df070cf cmake: fix dependency resolver init, add Apple framework linking, add swscale vulkan support
689335c Fix libplacebo detection: disable if API >= 339 (7.x) due to incompatibility
c8986ac Fix CMake build: centralized external libs, conditional codec discovery, TLS conflicts
6670472 Add macOS st_mtimespec.tv_nsec struct member detection
72d3c59 fix(cmake): fix build errors on mac, black and pi
a50d5e6 fix(cmake): use pkg-config detected libxml2 instead of find_package
f196caa add cmake build
```
