#!/bin/bash

LOGFILE=$HOME/log/ffmpeg_fate.log
ERRORFILE=$HOME/log/ffmpeg_fate.err
SUCCESS_FLAG=$HOME/log/ffmpeg_fate.flag

if [ -f "$SUCCESS_FLAG" ]; then
        rm "$SUCCESS_FLAG"
    else
        echo "Last run failed. Exiting." >> "$ERRORFILE"
        #exit 1
fi

exec > >(tee -a "$LOGFILE") 2> >(tee -a "$ERRORFILE")

echo "=========================================="
echo "Job started on $(date)"
echo "=========================================="

cd $HOME/work/fate-ffmpeg && git clean -df && git pull && \
    ./configure --enable-debug \
    --disable-stripping \
    --toolchain=msvc --target-os=win64 \
    --cc=cl.exe --cxx=cl.exe \
    --extra-cflags=-fsanitize=address \
    --ignore-tests=fate-ffmpeg-fix_sub_duration_heartbeat \
    --samples=../fate-sample && \
    make -j8 && make fate-rsync -j8 && \
    ASAN_OPTIONS=windows_hook_legacy_allocators=false make fate -j8

if [ $? -ne 0 ]; then
    echo "=========================================="
    echo "Job failed on $(date)"
    echo "=========================================="
    exit 1
else
    echo "=========================================="
    echo "Job finished successfully on $(date)"
    echo "=========================================="
    touch "$SUCCESS_FLAG"
fi
