# FFmpeg系统测试

[toc]

## 功能

* 编译FFmpeg依赖的工具和第三方库
* 执行FFmpeg fate测试，包括
  * fate sample管理
  * asan内存检查
  * 跳过指定的测试项

**注意：编译出的FFmpeg方便测试调试，因为关闭了编译优化，不适合业务使用。**



## 使用方法

```sh
./cibuild.sh --help
Use --path to specify ffmpeg source directory
Use --skip_test_case to skip some test cases, separated by comma
Use --enable_asan 1 to enable address sanitizer
```

例如

```sh
#!/bin/bash

set -x

cd ${WORKSPACE}/ffmpeg-build
./cibuild.sh --path ${WORKSPACE}/ffmpeg --enable_asan 1
```

## 工具

* nasm: FFmpeg、dav1d、x264等依赖nasm
* meson: dav1d、vmaf依赖meson


## 第三方库

* dav1d：AV1解码库
* lsmash: mp4 muxer/demuxer/分析工具，给x264用，可以脱离FFmpeg测试x264
* openssl: ssl库
* vmaf：视频质量评测工具
* x264：H.264编码库
