# FFmpeg 开发与测试

这个仓库从指定的 FFmpeg 源码构建 `ffmpeg` 和 `ffprobe`，并为调试、FATE 和日常命令行使用提供构建配置。FFmpeg 继续使用上游的 `configure` 和 GNU Make，因此可以直接使用 FFmpeg 的构建目标。

## 原生构建

安装 Bash、Git、Python 3.10 或更新版本、C/C++ 编译器、GNU Make、pkg-config、CMake 和 Ninja。x86 构建还需要 NASM，默认的 FATE 流程还需要 rsync。构建入口从 `PATH` 查找这些工具。

在 macOS 或 Linux 上运行以下命令。在 Windows 上，可从 MSYS2 的 MinGW 环境运行相同入口，并安装 MSYS2 的 `/usr/bin/python3`。FFmpeg 的 configure 要求源码路径没有空格，因此建议将两个仓库都放在没有空格的路径下。MSVC 和 vcpkg 构建使用专门的入口。[Windows 构建说明](win/README.md)

```bash
git submodule update --init --recursive

./cibuild.sh --path ../ffmpeg --skip-test
./cibuild.sh --path ../ffmpeg --profile release --skip-test --install
./cibuild.sh --path ../ffmpeg --profile asan --no-rsync
```

`debug` 是默认配置，它保留调试信息并关闭优化。`release` 开启优化并保留调试信息。`asan` 和 `asan-release` 分别在这两种配置中启用 AddressSanitizer。如果构建环境使用 NVIDIA Vulkan ICD，ASan 配置会关闭 Vulkan。

入口会在构建结束时打印二进制文件的路径。`--install` 会把 FFmpeg 安装到该构建目录的 `install/` 子目录。脚本或调试器可以用 `--print-build-dir` 查找对应的目录。

```bash
out="$(./cibuild.sh --path ../ffmpeg --profile release --print-build-dir)"
source "$out/runtime.env"
"$out/ffmpeg" -version
"$out/ffprobe" -version
```

`runtime.env` 为动态库加载器加入构建时使用的依赖目录。需要加载 DLL 的 Windows 命令和使用 Vulkan 的 macOS 命令可以先加载此环境。

## 并行与增量构建

FFmpeg 的构建目录位于 `build/native/ffmpeg/`。入口根据 FFmpeg 源码的规范路径、构建配置和 `--variant` 分配目录，因此不同 worktree 可以同时构建。若同一 worktree 需要保留两组 configure 参数，可以给其中一组指定一个 `--variant`。同一个构建目录内的配置、编译、测试和安装依次持锁执行。

修改 FFmpeg 源码后，可以重复运行相同命令。入口会在 configure 脚本、参数、工具链或检测到的依赖配置发生变化时重新配置。其余源码变更由 FFmpeg 的 Makefile 增量处理。若外部 SDK 在原路径内更新，可以用 `--reconfigure` 强制重新配置。

```bash
./cibuild.sh --path ../ffmpeg --skip-test --jobs 8
./cibuild.sh --path ../ffmpeg --variant shared --skip-test \
    --configure-arg=--enable-shared
./cibuild.sh --path ../ffmpeg --variant shared --clean
```

## 第三方库

第三方源码和 Android 预编译库位于 `third_party/`，Git 子模块记录源码版本。入口使用每个库自己的构建系统，并按依赖关系构建库。例如 Vulkan Loader 依赖 Vulkan Headers，而 libplacebo 还依赖 Little CMS。可用的库、默认选择和源码目录由 `list-deps` 列出。

```bash
./cibuild.sh list-deps
./cibuild.sh deps --jobs 8
./cibuild.sh deps --deps x264,x265
./cibuild.sh --deps default,vvdec --skip-test
./cibuild.sh --deps none --no-optional-libs --skip-test
```

每个库在 `build/native/deps/` 下有独立的构建目录和安装前缀。入口根据源码版本、Git 已跟踪的修改、构建选项、工具链和上游依赖选择缓存条目。对于 Git 中新增的依赖源码，可以用 `git add -N` 将其纳入缓存计算。库安装成功后，其他 FFmpeg worktree 就可以复用同一个依赖。若安装中断，下次运行会重新构建该条目。

FFmpeg 会优先使用为本次构建选中的缓存库。可选功能还可以从 `--extra-prefix`、仓库的 `install/` 和系统 pkg-config 路径发现。`--deps none` 跳过托管库的构建，而 `--no-optional-libs` 跳过这些额外的功能探测。要同时关闭 FFmpeg 自己的系统依赖自动探测，可再传入 `--configure-arg=--disable-autodetect`。

可以通过系统包管理器安装 FreeType 和 Fontconfig 的开发包。构建入口通过 pkg-config 探测并启用可链接的版本。

`./install_onnxruntime.sh` 从微软的 NuGet 包安装 CPU 版 ONNX Runtime 到 `install/`。用 `ONNXRUNTIME_VERSION` 可指定版本。Intel Mac 默认使用仍提供 x86-64 动态库的上游版本。

`make` 和 `make .x264` 等入口会调用同一依赖构建器。`make ffmpeg path=../ffmpeg enable_opt=1` 会构建优化版，`make clean` 会清理所选 FFmpeg 构建的目标文件。旧脚本参数 `--enable_opt`、`--enable_asan` 和 `--skip_test` 仍可用于现有调用。原先直接调用 `build_ffmpeg.sh` 的脚本可以改用 `./cibuild.sh --reuse-deps --skip-test`，并保留原来的构建选项。需要 FATE 时可以去掉 `--skip-test`。

单独构建 L-SMASH、SRT、uavs3d、VMAF、vvdec 或 zimg 时，请运行 `./cibuild.sh deps --deps NAME`，其中 `NAME` 取 `list-deps` 列出的名称。SRT 和 zimg 需要在 `third_party/` 下提供相应的源码目录。VMAF 的 Python 模型工具通过其 `python/requirements.txt` 声明 LibSVM 等依赖。安装步骤见 [VMAF Python 文档](third_party/vmaf/resource/doc/python.md)。

## FATE 和其他平台

默认流程先运行 `fate-rsync`，然后运行 FATE。若样本已下载，可以传入 `--no-rsync`。也可以通过 `--samples` 或 `FATE_SAMPLES` 使用现有样本库，通过 `--fate-target` 指定一个或多个目标，或通过 `--skip-test-case` 向 FFmpeg 传入忽略列表。

```bash
./cibuild.sh --no-rsync --fate-target fate-aes --fate-target fate-parseutils
./cibuild.sh --skip-test-case ffmpeg-fix_sub_duration_heartbeat
```

Android、Emscripten、WASI 和 HarmonyOS 的 FFmpeg 构建入口位于 `cross/`。这些脚本以仓库根目录为基准解析相对的 `--path`，并在配置相同时复用已生成的目标文件。`FFMPEG_CI_JOBS` 可以指定编译并行数。HarmonyOS 构建通过 `OHOS_SDK_NATIVE` 指定 SDK。[Android 设备验证](android/README.md)、[Emscripten 验证](emsdk-test/README.md)、[Windows MSVC](win/README.md)、[ONNX DNN 测试](tests/dnn/README.md)

Android 和 HarmonyOS 构建可通过 `--enable_x264 1` 交叉编译 x264。若需要单独构建 WASI 版 OpenH264，请提供支持 WASI 的 OpenH264 源码，设置 `WASI_SDK_PREFIX`，然后运行 `./cross/build_openh264_wasi.sh <openh264-src>`。脚本将静态库安装到 `install-wasi/`。如果源码位于 `third_party/openh264/`，可以省略源码路径。
