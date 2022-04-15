#!/bin/bash

set -e

ffmpeg_src="../ffmpeg"
skip_test_case=""
enable_asan=0
enable_opt=0
do_test="--test"
while [ $# -gt 0 ]; do
    case $1 in
        --help)
            echo "Use --path to specify ffmpeg source directory"
            echo "Use --skip_test_case to skip some test cases, separated by comma"
            echo "Use --skip_test to skip all test cases"
            echo "Use --enable_asan 1 to enable address sanitizer"
            exit 1
            ;;
        --path)
            ffmpeg_src=$2
            shift
            ;;
        --skip_test)
            do_test=
            ;;
        --skip_test_case)
            skip_test_case=$2
            shift
            ;;
        --enable_asan)
            enable_asan=$2
            echo "enable_asan $enable_asan"
            shift
            ;;
        --enable_opt)
            enable_opt=$2
            echo "enable_opt $enable_opt"
            shift
            ;;
        *)
            echo "Known option $1, exit"
            exit 1
            ;;
    esac
    shift
done

if true; then
# first build tools needs by other projects
./build_nasm.sh

source ./env.sh

./build_lsmash.sh
./build_dav1d.sh
./build_vmaf.sh
./build_x264.sh
./build_x265.sh
./build_freetype.sh
./build_fontconfig.sh
./build_srt.sh
fi

./build_ffmpeg.sh --path $ffmpeg_src \
    ${do_test} \
    --skip_test_case "$skip_test_case" \
    --enable_asan $enable_asan \
    --enable_opt $enable_opt
