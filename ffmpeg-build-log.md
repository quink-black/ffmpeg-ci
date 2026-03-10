# FFmpeg CMake 构建日志

本文档记录将 FFmpeg 从 configure + Makefile 构建系统迁移到 CMake 的进度。

## 开始时间
2026-03-08

---

## 阶段 1: 基础配置骨架

### 目标
创建 CMake 项目骨架，实现平台检测和特性探测，生成 `config.h`，与 `configure` 生成的版本做 diff 对比。

### 进度
- [x] 创建顶层 CMakeLists.txt
- [x] 创建 cmake/FFmpegArch.cmake 架构检测模块
- [x] 创建 cmake/FFmpegFeatureDetect.cmake 特性检测模块  
- [x] 创建 cmake/config.h.in 模板
- [x] 测试：生成 config.h 并与 configure 版本对比

### 完成时间
2026-03-08

---

## 阶段 2: 构建 libavutil

### 目标
为 libavutil 创建 CMakeLists.txt，编译生成静态库，测试基本功能。

### 进度
- [x] 创建 libavutil/CMakeLists.txt
- [x] 添加所有源文件和头文件
- [x] 配置编译选项和依赖
- [x] 生成 libavutil.a 静态库
- [x] 验证符号表和基本功能

### 完成时间
2026-03-08

### 提交信息
- Commit: 97f3bd64508
- 18 files changed, 3960 insertions(+)

---

## 阶段 3: 扩展到所有内置库

### 目标
编译全部 7 个库，仅使用内置编解码器，禁用所有第三方库。

### 进度
- [x] 创建 libswresample/CMakeLists.txt
- [x] 创建 libswscale/CMakeLists.txt
- [x] 创建 libavcodec/CMakeLists.txt
- [x] 创建 libavformat/CMakeLists.txt
- [x] 创建 libavfilter/CMakeLists.txt
- [x] 创建 libavdevice/CMakeLists.txt
- [x] 实现 FFmpegComponents.cmake 组件注册系统
- [x] 生成 codec_list.c, parser_list.c, bsf_list.c
- [x] 生成 indev_list.c, outdev_list.c
- [x] 生成 config_components.h
- [x] 验证所有库编译成功

### 完成时间
2026-03-08

### 提交信息
- 97f3bd64508: Initial CMake build system for all 7 libraries
- e1f42e862e5: Implement component registration system (step 3.2, 3.3)
- 578b5387121: Add device list files generation for libavdevice
- ef9d44ea613: Fix device list types to use FFInputFormat/FFOutputFormat

### 编译验证
```
libavutil:     ✅ libavutil.a
libswresample: ✅ libswresample.a
libswscale:    ✅ libswscale.a
libavcodec:    ✅ libavcodec.a
libavformat:   ✅ libavformat.a
libavfilter:   ✅ libavfilter.a
libavdevice:   ✅ libavdevice.a
```

---

## 阶段 4: 构建命令行工具

### 目标
编译 ffmpeg、ffplay、ffprobe 可执行文件。

### 进度
- [x] 创建 fftools/CMakeLists.txt
- [x] 处理资源文件（bin2c 生成 graph.html.c, graph.css.c）
- [x] 验证可执行文件功能
- [x] 修复 HAVE_AV_CONFIG_H 问题

### 关键问题修复
**问题**：fftools 编译失败，缺少 `AVCodecDescriptor` 等类型定义。
**原因**：错误地为 fftools 添加了 `HAVE_AV_CONFIG_H` 宏定义。
**解决**：
- 在原始 FFmpeg 构建中，库文件编译时有 `HAVE_AV_CONFIG_H`，但 fftools **没有**这个宏
- 当没有 `HAVE_AV_CONFIG_H` 时，`libavcodec/avcodec.h` 会自动包含 `codec_desc.h` 和 `codec_par.h`
- 删除 fftools/CMakeLists.txt 中的 `target_compile_definitions(... HAVE_AV_CONFIG_H)` 即可

### 完成时间
2026-03-08

### 编译验证
```
ffmpeg:   ✅ 编译成功，可运行 -version
ffprobe:  ✅ 编译成功，可运行 -version
ffplay:   ⏸️ 需要 SDL2，后续阶段处理
```

### 提交信息
- 5cad06e6e39: fix: Remove HAVE_AV_CONFIG_H from fftools build

---

## 阶段 5: 第三方库集成

### 目标
创建第三方库检测模块，支持 zlib、OpenSSL、x264 等外部编解码器库。

### 进度
- [x] 创建 cmake/FFmpegExternalLibs.cmake 模块
- [x] P0 核心库: zlib, bzlib, lzma, iconv
- [x] P1 安全/加密: OpenSSL, GnuTLS, libxml2
- [x] P1 外部编解码器: x264, x265, aom, dav1d, vpx, mp3lame, opus, vorbis, fdk-aac
- [x] P2 高级编解码器: SVT-AV1, VVC encoder
- [x] P3 硬件加速: Vulkan, CUDA
- [x] P3 视频处理: SDL2, libass, libzimg, FreeType, Fontconfig
- [x] 平台特定: macOS frameworks (VideoToolbox, CoreMedia, etc.), Linux ALSA/V4L2
- [x] 添加 network.c 和 TLS 支持到 libavformat
- [x] 链接外部库到 fftools
- [x] 验证 ffmpeg/ffprobe/ffplay 编译运行正常

### 关键修复
1. **TLS 库冲突**：OpenSSL 和 GnuTLS 同时启用导致编译错误，修改为优先选择 OpenSSL
2. **网络支持**：添加 network.c 和 tls.c 到 libavformat，设置 CONFIG_TLS_PROTOCOL
3. **配置不匹配警告**：设置 FFMPEG_CONFIGURATION 消除警告

### 完成时间
2026-03-08

### 编译验证
```
ffmpeg:   ✅ 编译成功，已链接 zlib, OpenSSL
ffprobe:  ✅ 编译成功，已链接 zlib, iconv
ffplay:   ✅ 编译成功，已链接 SDL2, zlib, iconv
```

### 提交信息
- dc43ff9e4bc: feat(cmake): add external library detection module (Phase 5)
- 54c32694b46: feat(cmake): add device support with lavfi, avfoundation, audiotoolbox

### 设备支持
```
Devices:
 D  lavfi           Libavfilter virtual input device  ✅
 D  avfoundation    AVFoundation input device        ✅ (macOS)
 E  audiotoolbox    AudioToolbox output device       ✅ (macOS)
```

---

## 阶段 6: 构建系统完整性修复（已完成）

### 目标
修复所有链接错误，确保 ffmpeg/ffprobe/ffplay/checkasm 全部构建成功。

### 进度
- [x] 修复 libavfilter 链接错误（GPU filter 排除、VAAPI 条件编译、DNN filter 排除）
- [x] 修复 libswscale x86/ops.c 缺失（`backend_x86` undefined reference）
- [x] 修复 checkasm 构建（添加所有 checkasm/*.c 源文件 + x86/checkasm.asm）
- [x] 修复 af_biquads.c 宏定义 filter 的 symbol 处理
- [x] 修复 vf_neighbor.c 宏定义 filter 的 symbol 处理
- [x] 添加 VAAPI 库检测（libva）和条件编译
- [x] 添加 Fontconfig 库链接到 avfilter
- [x] 验证所有目标构建成功

### 关键修复

**1. libavfilter GPU filter 排除**
- 把所有 Vulkan/OpenCL/CUDA filter 文件加入排除列表
- 把 DNN filter 文件（vf_derain.c, vf_sr.c 等）加入排除列表
- 把 DSP helper 文件（vf_fsppdsp.c, vf_idetdsp.c）加入 helper 列表

**2. VAAPI 条件编译**
- 在 FFmpegExternalLibs.cmake 中添加 libva 检测
- VAAPI filter 文件（vaapi_vpp.c, vf_misc_vaapi.c 等）改为条件编译
- 通过扫描文件内容自动获取 VAAPI filter symbols

**3. af_biquads.c / vf_neighbor.c 宏定义 filter**
- 这两个文件使用宏定义 filter，CMake 的 `file(STRINGS ...)` 无法检测
- 加入排除列表，手动添加实际定义的 symbols

**4. libswscale x86/ops.c**
- `backend_x86` 定义在 `libswscale/x86/ops.c` 中，但未被包含
- 加入 x86 源文件列表

**5. checkasm 构建**
- 原来只编译 `checkasm/checkasm.c`，缺少所有 `checkasm_check_*` 函数
- 改为 `file(GLOB ...)` 包含所有 `checkasm/*.c`
- 添加 `checkasm/x86/checkasm.asm`（提供 `checkasm_stack_clobber` 等函数）

### 完成时间
2026-03-09

### 编译验证
```
avutil:      ✅ Built target avutil
swscale:     ✅ Built target swscale
swresample:  ✅ Built target swresample
avcodec:     ✅ Built target avcodec
avformat:    ✅ Built target avformat
avfilter:    ✅ Built target avfilter
avdevice:    ✅ Built target avdevice
checkasm:    ✅ Built target checkasm
ffmpeg:      ✅ Built target ffmpeg (v n8.1-dev-2731)
ffplay:      ✅ Built target ffplay
ffprobe:     ✅ Built target ffprobe
```

### 提交信息
- `cmake: fix libavfilter link errors - exclude GPU filters, add VAAPI/Fontconfig support`
- `tests: fix checkasm build - include all checkasm/*.c source files`
- `fix: add x86/ops.c to swscale, add checkasm x86 asm and NASM includes`
- `fix: resolve remaining libavfilter link errors (biquads, VAAPI, DNN filters)`

---

## 阶段 7: cmake-build-2 分支 — 构建系统重构与修复（已完成）

### 目标
在 `cmake-build-2` 分支上重构构建系统，修复所有链接错误，实现完整的 ffmpeg 构建。

### 背景
`cmake-build-2` 分支是对原有 CMake 构建系统的重构，目标是更健壮地处理：
- 需要外部库的源文件（chromaprint、vapoursynth 等）
- 硬件加速编解码器（MediaCodec、MMAL、QSV、RKMPP 等）
- 通过宏定义的编解码器（PCM、ADPCM 等）
- 条件编译的符号（`#if CONFIG_*`、`#if 0` 等）

### 进度
- [x] 修复 libavformat：排除需要外部库的文件（sctp.c、vapoursynth.c 等）
- [x] 修复 libavformat：排除 allformats.c/protocols.c 的扫描（只有 extern 声明）
- [x] 修复 libavformat：过滤条件编译符号（ff_fifo_test_muxer、ff_android_content_protocol 等）
- [x] 修复 libavcodec：解决宏定义编解码器（PCM 等）无法被扫描的问题
- [x] 修复 libavcodec：解决硬件加速编解码器（MediaCodec、MMAL、QSV、RKMPP 等）链接错误
- [x] 验证完整构建成功，ffmpeg 可运行

### 关键技术问题与解决方案

**问题 1：libavformat 外部库文件**
- `chromaprint.c`、`vapoursynth.c` 等需要外部库头文件
- **解决**：加入 `avformat_exclude_files` 排除列表

**问题 2：allformats.c 中的 extern 声明被误扫描**
- `file(STRINGS ...)` 扫描了 `allformats.c` 中的 `extern const FFOutputFormat ff_chromaprint_muxer;`
- 这些 extern 声明匹配了正则表达式，导致被错误地加入 `muxer_list.c`
- **解决**：在扫描时跳过 `allformats.c` 和 `protocols.c`（它们只有 extern 声明，不是定义）
- **修复正则**：改为 `^const ...`（行首匹配），排除 `extern const ...` 声明

**问题 3：条件编译符号**
- `ff_fifo_test_muxer`（`#ifdef FIFO_TEST`）、`ff_android_content_protocol`（`#if CONFIG_ANDROID_CONTENT_PROTOCOL`）、`ff_async_test_protocol`（`#if 0`）
- **解决**：手动加入 `list(REMOVE_ITEM ...)` 过滤列表

**问题 4：allcodecs.c 包含所有编解码器的 extern 声明**
- `allcodecs.c` 被编译后，其 `.data` 段中的 `codec_list[]` 数组引用了所有编解码器符号
- 硬件加速编解码器（`ff_h264_mediacodec_decoder` 等）的实现文件根本不存在于源码树中
- **解决**：
  1. 将 `allcodecs.c` 从 `avcodec_sources` 中排除（加入 `avcodec_auto_excluded`）
  2. 生成 `allcodecs_generated.c` 替代它，只包含实际编译的编解码器的 extern 声明
  3. 生成逻辑：从 `allcodecs.c` 读取所有 extern 声明 → 过滤被排除文件的符号 → 验证符号在 `avcodec_sources` 中存在

**问题 5：宏定义编解码器（PCM 等）无法被直接扫描**
- `pcm.c` 中的 `ff_pcm_s16le_decoder` 等通过 `PCM_CODEC(...)` 宏定义，`file(STRINGS ...)` 无法匹配
- **解决**：使用 `execute_process` 运行 `gcc -E` 预处理器展开宏，然后扫描展开后的输出

### 完成时间
2026-03-09

### 编译验证
```
cmake -DCMAKE_BUILD_TYPE=Debug -DENABLE_ASM=ON  ✅
make -j4                                         ✅ BUILD_SUCCESS

ffmpeg version n8.1-dev-2748-g3f8265a314
libavutil      60.25.100
libavcodec     62.24.101
libavformat    62.10.100
libavfilter    10.10.100
libavdevice    62. 4.100
libswscale      9. 5.100
libswresample   5. 4.100

编解码器: 479 个（含解码器+编码器）
  pcm_s16le: DEAI.S ✅（宏定义编解码器正常工作）
  mpeg4:     DEV.L. ✅
  aac:       DEA.L. ✅

功能测试:
  视频编码 (mpeg4):          ✅ 75帧/3秒，128KiB
  音视频编码 (mpeg4+aac):    ✅ 125帧/5秒，368KiB，速度18.9x
  MP4 封装:                  ✅
```

### 提交信息
- `fix: exclude sctp.c from libavformat (requires netinet/sctp.h kernel support)`
- `fix: exclude vapoursynth.c from libavformat (requires external VapourSynth library)`
- `fix: exclude allformats.c/protocols.c from list scanning (they have extern decls not definitions)`
- `fix: filter out conditionally-compiled symbols from avformat list files`
- `fix: replace allcodecs.c with generated allcodecs_generated.c (only compiled codecs)`
- `fix: exclude allcodecs.c from GLOB scan (replaced by generated allcodecs_generated.c)`
- `fix: add Step 4 to verify codec symbols exist in avcodec_sources (handles macro-defined and missing codecs)`

---

## 阶段 8: Linux 跨平台编译测试

### 目标
验证 CMake 构建系统在 Linux x86 环境下的正确性。

### 测试环境
- **主机**: black2.local (Linux x86_64)
- **源码路径**: `/home/quink/work/ffmpeg_all/master_ffmpeg`
- **构建路径**: `/home/quink/work/ffmpeg_all/master_ffmpeg/build_cmake`
- **对比版本**: `/home/quink/work/ffmpeg_all/ffmpeg-ci/build/ffmpeg_opt` (configure 构建)

### 测试过程

#### 1. 配置与编译
```bash
cd /home/quink/work/ffmpeg_all/master_ffmpeg
rm -rf build_cmake && mkdir build_cmake
cd build_cmake
cmake .. -DCMAKE_BUILD_TYPE=Debug
make -j4
```

**结果**: ✅ 编译全部成功

#### 2. 编译产物验证
```
Built targets:
  ✅ avutil      (libavutil.a)
  ✅ swresample  (libswresample.a)
  ✅ swscale     (libswscale.a)
  ✅ avcodec     (libavcodec.a)
  ✅ avformat    (libavformat.a)
  ✅ avfilter    (libavfilter.a)
  ✅ avdevice    (libavdevice.a)
  ✅ checkasm    (tests/checkasm)
  ✅ ffmpeg      (fftools/ffmpeg, 82.7MB)
  ✅ ffprobe     (fftools/ffprobe, 81.9MB)
  ✅ ffplay      (fftools/ffplay, 82.1MB)
```

#### 3. 编解码器数量对比
| 构建方式 | 编解码器数量 |
|---------|-------------|
| CMake   | 497 个 |
| configure | 504 个 |
| 差异 | 7 个 |

**说明**: 差异主要来自 configure 构建启用了更多外部库（libaom, libx264, libx265 等）

#### 4. 基本功能测试
```bash
# 版本信息测试
./ffmpeg -version
# ✅ 输出正常: ffmpeg version n8.1-dev-2629-g113b922153

# 视频编码测试
./ffmpeg -f lavfi -i "testsrc=duration=1:size=320x240:rate=25" \
         -c:v mpeg4 -f null /dev/null
# ✅ 编码成功, speed=35x
```

### 完成时间
2026-03-09

---

## 阶段 9: 编解码器与 Filter 差异分析

### 差异概览

| 类别 | CMake | Configure | 差异 |
|-----|-------|-----------|------|
| 编解码器 | 497 | 504 | -7 |
| Filters | 244 | 250 | -6 |

### 缺失的编解码器（7个）

| 编解码器 | 类型 | 说明 | 可能原因 |
|---------|------|------|--------- |
| `aac_latm` | 音频 | AAC LATM 封装 | codec_list 生成问题 |
| `avs2` | 视频 | AVS2 视频编码 | 条件编译宏未定义 |
| `avs3` | 视频 | AVS3 视频编码 | 依赖 libuavs3d 检测 |
| `dsd_lsbf` | 音频 | DSD 格式 | codec_list 生成问题 |
| `dsd_lsbf_planar` | 音频 | DSD planar 格式 | codec_list 生成问题 |
| `dsd_msbf` | 音频 | DSD MSBF 格式 | codec_list 生成问题 |
| `dsd_msbf_planar` | 音频 | DSD MSBF planar | codec_list 生成问题 |

### 缺失的 Filters（6个）

| Filter | 类型 | 说明 | 可能原因 |
|--------|------|------|---------|
| `aeval` | 音频 | 评估表达式 | 可能是aevalsrc别名 |
| `lutrgb` | 视频 | RGB 查找表 | filter_list 生成问题 |
| `lutyuv` | 视频 | YUV 查找表 | filter_list 生成问题 |
| `bwdif_cuda` | 视频 | CUDA bwdif | 需要 CUDA */
| `overlay_cuda` | 视频 | CUDA 叠加 | 需要 CUDA */
| `yadif_cuda` | 视频 | CUDA yadif | 需要 CUDA */

### TODO 列表

- [ ] 修复 `aac_latm` 编解码器注册问题
- [ ] 修复 `avs2` / `avs3` 编解码器条件编译问题
- [ ] 修复 `dsd_*` 编解码器注册问题
- [ ] 修复 `lutrgb` / `lutyuv` filter 注册问题
- [ ] 验证 `aeval` 是否是别名问题
- [ ] 添加 CUDA 支持以启用 CUDA filters

---

## 阶段 10: Windows MSVC 构建支持（已完成）

### 目标
验证并修复 CMake 构建系统在 Windows MSVC 环境下的正确性。

### 进度
- [x] 修复 Windows 套接字结构体检测（Winsock2 structs force-set to 1）
- [x] 添加 `HAVE_GETADDRINFO` 检测（Windows 强制设为 1）
- [x] 验证 `HAVE_WINDOWS_H` / `HAVE_WINSOCK2_H` / `HAVE_WS2TCPIP_H` 检测
- [x] 添加 Windows 特定函数检测（`SetDllDirectory`, `GetModuleHandle` 等）
- [x] 添加 MSVC 特定编译器警告标志（/W3 /wd4018 /wd4244 等）
- [x] 使用 `/std:c17` 启用 C17 标准
- [x] 使用 `compat/atomics/win32/stdatomic.h` 替代系统 stdatomic.h
- [x] 链接 `ws2_32.lib` 到 libavformat
- [x] 修复 SIMD 外部符号：force-enable AESNI/FMA3/FMA4/XOP/AVX512/AVX512ICL/MMXEXT
- [x] 排除 64-bit MSVC 不支持的 MMX（`_mm_empty()` 不可用）
- [x] 生成 `vf_drawtext_stub.c`（FreeType2 不可用时提供 `ff_vf_drawtext` 存根）
- [x] 生成 `avformat_xml_stubs.c`（libxml2/OpenSSL 不可用时提供 dash/imf/whip/unix 存根）
- [x] 排除 `hscale_fast_bilinear_simd.c`（需要 GCC inline asm，MSVC 不支持）

### 关键问题修复

| 问题 | 原因 | 修复方案 |
|------|------|----------|
| `ff_aes_decrypt_10_aesni` 等符号缺失 | `HAVE_AESNI_EXTERNAL=0`，NASM 汇编未启用 | `FFmpegArch.cmake`：强制设置 AESNI/FMA3/FMA4/XOP/AVX512/AVX512ICL/MMXEXT 的 `_EXTERNAL=1` |
| `__WSAFDIsSet`、`select` 等 Winsock 符号缺失 | `avformat` 未链接 `ws2_32.lib` | `libavformat/CMakeLists.txt`：Windows 下添加 `target_link_libraries(avformat PRIVATE ws2_32)` |
| `ff_dash_demuxer`、`ff_imf_demuxer` 未定义 | `dashdec.c`/`imfdec.c` 被排除（无 libxml2），但 `allformats.c` 无条件引用 | `libavformat/CMakeLists.txt`：生成存根文件 `avformat_xml_stubs.c` |
| `ff_whip_muxer` 未定义 | `whip.c` 被排除（无 OpenSSL），但 `allformats.c` 无条件引用 | 同上，在存根文件中提供 |
| `ff_unix_protocol` 未定义 | `unix.c` 被排除（Windows 无 `sys/un.h`），但 `protocols.c` 无条件引用 | 同上，在存根文件中提供 |
| `ff_vf_drawtext` 未定义 | `vf_drawtext.c` 被排除（无 FreeType2），但 `allfilters.c` 无条件引用 | `libavfilter/CMakeLists.txt`：生成存根文件 `vf_drawtext_stub.c` |
| `_mm_empty` 未定义 | 64 位 MSVC 不支持 MMX intrinsics | `FFmpegArch.cmake`：从强制设置列表中移除 `MMX` |

### 完成时间
2026-03-10

### 编译验证
```
Build: [206/206] Linking C executable fftools\ffmpeg.exe  ✅

fftools/ffmpeg.exe   ✅ (37.4 MB)
fftools/ffprobe.exe  ✅ (37.0 MB)
avcodec.lib          ✅
avformat.lib         ✅
avfilter.lib         ✅
avutil.lib           ✅
swscale.lib          ✅
swresample.lib       ✅
avdevice.lib         ✅
```

### 提交信息
- `cmake: add MSVC/Windows build support` (99b13e5bc8)
  - Branch: `cmake-build-3`
  - 8 files changed, 441 insertions(+), 78 deletions(-)

### 构建环境
- **代码分支**: `cmake-build-3`
- **构建系统**: Visual Studio 2022 + MSVC 19.44.35221
- **构建脚本**: `ffmpeg-ci/win/cmake_build.sh`

---

## 阶段 11: 构建质量提升（待开始）

### 目标
修复上述差异，确保 CMake 构建与 configure 构建功能一致。

### 计划
- [ ] 对比 configure 生成的 config.h 与 CMake 生成的 config.h
- [ ] 运行 checkasm 测试，验证汇编优化正确性
- [ ] 运行更多功能测试（编解码、转封装）
- [ ] 完善第三方库检测，启用更多外部编解码器
- [ ] 修复发现的差异和问题

---

## 阶段 12: Windows MSVC 功能验证（待开始）

### 目标
在 Windows 上运行 ffmpeg.exe 并验证基本功能。

### TODO 列表

#### P0 - 基本运行验证
- [ ] 验证 `ffmpeg.exe -version` 输出正常
- [ ] 验证 `ffprobe.exe -version` 输出正常
- [ ] 验证编解码器列表（`ffmpeg -codecs`）

#### P1 - 功能测试
- [ ] 视频编码测试（testsrc → mpeg4）
- [ ] 音视频编码测试（testsrc + sine → mp4）
- [ ] 格式转换测试

#### P1 - 硬件加速（可选）
- [ ] 启用 D3D11VA 解码支持（`CONFIG_D3D11VA`）
- [ ] 启用 DXVA2 解码支持（`CONFIG_DXVA2`）
- [ ] 启用 MediaFoundation（`CONFIG_MEDIAFOUNDATION`）

#### P2 - 设备支持（可选）
- [ ] 添加 dshow（DirectShow）输入设备支持
- [ ] 添加 gdigrab（屏幕捕获）输入设备支持

#### P2 - 第三方库（可选）
- [ ] 集成 OpenSSL（启用 HTTPS/TLS 支持）
- [ ] 集成 x264/x265（启用 H.264/H.265 编码）
- [ ] 集成 FreeType2（启用 drawtext filter）
