# VVC decode optimization

## development environment

### local machine
- ffmpeg source code: /Users/quink/work/ffmpeg_all/ffmpeg
- vvc decoder is at libavcodec/vvc

### pi2: Raspberry Pi 5
- Raspberry Pi 5 machine in local network can be accessed via any of these methods:
   - ssh pi2.local
   - tmux-mcp-agent, in tmux session pi2
- ffmpeg source code on pi2: /home/quink/work/ffmpeg
- local and pi2 share same remote git repo: `share2  quink@pi2.local:work/bare-ffmpeg`
- perf works on Raspberry Pi 5
- /home/quink/work/clang-ffmpeg: ffmpeg build directory, run make -j20 to build

### black2: x86 linux machine
- x86 linux machine in local network can be accessed via any of these methods:
   - ssh black2.local
   - tmux-mcp-agent, in tmux session black2
- ffmpeg source code on black2: /home/quink/work/ffmpeg_all/master_ffmpeg
- local and black2 share same remote git repo: `share2  quink@pi2.local:work/bare-ffmpeg`
- perf works on black2
- /home/quink/work/ffmpeg_all/ffmpeg-ci/build/ffmpeg_opt: ffmpeg build directory, run make -j20 to build

### Android device
- build directory: /Users/quink/work/ffmpeg_all/ffmpeg-ci/build/ffmpeg-aarch64, run make -j20 to build
- push to Android device:
```
quink@ZHILIZHAO-MC2:~/work/ffmpeg_all/ffmpeg-ci/build/ffmpeg-aarch64$ adb push ffmpeg_g /data/local/tmp/
```
- run test on Android device:
```
quink@ZHILIZHAO-MC2:~/work/ffmpeg_all/ffmpeg-ci/build/ffmpeg-aarch64$ adb shell

husky: $ cd /data/local/tmp
husky:/data/local/tmp $ simpleperf record -g /data/local/tmp/ffmpeg_g -threads 1 -i /sdcard/DCIM/vvc-perf/city_crowd_1920x1080.mp4 -an -f null -
```

- then analysis perf results

### video samples

On pi2 the following video samples are available:
```
quink@pi2:~/minipc/quink/video/vvc-perf$ ls -1
city_crowd_1920x1080.mp4
out_vod_p7_10bit.mp4
t266_8M_tearsofsteel_4k.266
```
The first two are 10bits, the last one is 8bits.

On black2 the following video samples are available:
```
quink@black2:~/minipc/quink/video/vvc-perf$ ls -1
city_crowd_1920x1080.mp4
out_vod_p7_10bit.mp4
t266_8M_tearsofsteel_4k.266
```

## task 1: find vvc decoder bottleneck

- **Read ffmpeg source code to write a document on vvc decoder archtecture**
- Use perf to analyze vvc decoder performance
- Figure out the **bottleneck at two levels**: the architecture level and the hot function level
- Write a document on how to optimize vvc decoder