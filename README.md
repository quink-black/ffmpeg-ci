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
Use --skip_test to skip all test cases
Use --enable_asan 1 to enable address sanitizer
```

例如

```sh
#!/bin/bash

set -x

cd ${WORKSPACE}/ffmpeg-build
./cibuild.sh --path ${WORKSPACE}/ffmpeg --enable_asan 1
```

如果手动执行编译出来的FFmpeg命令，先执行下`source env.sh`，把install下的lib加进LD_LIBRARY_PATH。

```
$ source env.sh
$ cd build/ffmpeg/
$ ./ffmpeg -version
ffmpeg version N-106415-gfa12d808d7 Copyright (c) 2000-2022 the FFmpeg developers
built with gcc 7 (Ubuntu 7.5.0-3ubuntu1~18.04)
configuration: --prefix=/mnt/src/src/ffmpeg-ci/install --extra-cflags=-I/mnt/src/src/ffmpeg-ci/install/include --extra-ldflags='-L/mnt/src/src/ffmpeg-ci/install/lib -static-libasan' --extra-libs='-lstdc++ ' --enable-libvmaf --enable-libx264 --enable-libdav1d --enable-nonfree --enable-gpl --enable-version3 --enable-libfreetype --enable-libfontconfig --disable-doc --samples=/mnt/src/src/ffmpeg-ci/ffmpeg-fate-sample --ignore-tests= --disable-stripping --disable-optimizations --enable-openssl --toolchain=gcc-asan
libavutil      57. 24.101 / 57. 24.101
libavcodec     59. 25.100 / 59. 25.100
libavformat    59. 20.101 / 59. 20.101
libavdevice    59.  6.100 / 59.  6.100
libavfilter     8. 29.100 /  8. 29.100
libswscale      6.  6.100 /  6.  6.100
libswresample   4.  6.100 /  4.  6.100
libpostproc    56.  5.100 / 56.  5.100
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
