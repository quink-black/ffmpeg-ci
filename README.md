# FFmpeg 开发与测试

这个仓库从指定的 FFmpeg 源码构建 `ffmpeg` 和 `ffprobe`，并为调试、FATE 和日常命令行使用提供构建配置。FFmpeg 继续使用上游的 `configure` 和 GNU Make，因此可以直接使用 FFmpeg 的构建目标。

## 原生构建

安装 Bash、Git、Python 3.9 或更新版本、C/C++ 编译器、GNU Make、pkg-config、CMake 和 Ninja。x86 构建还需要 NASM，默认的 FATE 流程还需要 rsync。构建入口从 `PATH` 查找这些工具。

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

Git 子模块记录第三方源码版本。入口使用每个库自己的构建系统，并按依赖关系构建库。例如 Vulkan Loader 依赖 Vulkan Headers，而 libplacebo 还依赖 Little CMS。可用的库、默认选择和源码目录由 `list-deps` 列出。

```bash
./cibuild.sh list-deps
./cibuild.sh deps --jobs 8
./cibuild.sh deps --deps x264,x265
./cibuild.sh --deps default,vvdec --skip-test
./cibuild.sh --deps none --no-optional-libs --skip-test
```

每个库在 `build/native/deps/` 下有独立的构建目录和安装前缀。入口根据源码版本、Git 已跟踪的修改、构建选项、工具链和上游依赖选择缓存条目。对于 Git 中新增的依赖源码，可以用 `git add -N` 将其纳入缓存计算。库安装成功后，其他 FFmpeg worktree 就可以复用同一个依赖。若安装中断，下次运行会重新构建该条目。

FFmpeg 会优先使用为本次构建选中的缓存库。可选功能还可以从 `--extra-prefix`、仓库的 `install/` 和系统 pkg-config 路径发现。`--deps none` 跳过托管库的构建，而 `--no-optional-libs` 跳过这些额外的功能探测。要同时关闭 FFmpeg 自己的系统依赖自动探测，可再传入 `--configure-arg=--disable-autodetect`。

`make` 和 `make .x264` 等入口会调用同一依赖构建器。`make ffmpeg path=../ffmpeg enable_opt=1` 会构建优化版，`make clean` 会清理所选 FFmpeg 构建的目标文件。旧脚本参数 `--enable_opt`、`--enable_asan` 和 `--skip_test` 仍可用于现有调用。`build_ffmpeg.sh` 使用已缓存或已安装的依赖，并且可以通过 `--test` 启用 FATE。

## FATE 和其他平台

默认流程先运行 `fate-rsync`，然后运行 FATE。若样本已下载，可以传入 `--no-rsync`。也可以通过 `--samples` 或 `FATE_SAMPLES` 使用现有样本库，通过 `--fate-target` 指定一个或多个目标，或通过 `--skip-test-case` 向 FFmpeg 传入忽略列表。

```bash
./cibuild.sh --no-rsync --fate-target fate-aes --fate-target fate-parseutils
./cibuild.sh --skip-test-case ffmpeg-fix_sub_duration_heartbeat
```

交叉编译脚本包括 `android_ffmpeg.sh`、`emsdk_ffmpeg.sh`、`wasi_ffmpeg.sh` 和 `hm_ffmpeg.sh`。设备和平台的验证流程见各自的说明。[Android 设备验证](android/README.md)、[Emscripten 验证](emsdk-test/README.md)、[Windows MSVC](win/README.md)、[ONNX DNN 测试](tests/dnn/README.md)
