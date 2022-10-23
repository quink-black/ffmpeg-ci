cmake_minimum_required(VERSION 3.6)

project("ffmpegplay")

set(ffmpeg_build_dir ${CMAKE_CURRENT_SOURCE_DIR}/../../../build/ffmpeg-aarch64/)
set(ffmpeg_src_dir ${CMAKE_CURRENT_SOURCE_DIR}/../../../build/ffmpeg-aarch64/src)
set(ffmpeg_install_dir ${CMAKE_CURRENT_SOURCE_DIR}/../../../install)

add_library(ffmpegplay SHARED
        native-lib.cpp
        cmdutils.c
        ffmpeg.c
        ffmpeg_hw.c
        ${ffmpeg_src_dir}/fftools/cmdutils.h
        ${ffmpeg_src_dir}/fftools/ffmpeg.h
        ${ffmpeg_src_dir}/fftools/ffmpeg_mux.h
        ${ffmpeg_src_dir}/fftools/fopen_utf8.h
        ${ffmpeg_src_dir}/fftools/objpool.h
        ${ffmpeg_src_dir}/fftools/opt_common.h
        ${ffmpeg_src_dir}/fftools/sync_queue.h
        ${ffmpeg_src_dir}/fftools/thread_queue.h
        ${ffmpeg_src_dir}/fftools/ffmpeg_demux.c
        ${ffmpeg_src_dir}/fftools/ffmpeg_filter.c
        ${ffmpeg_src_dir}/fftools/ffmpeg_mux.c
        ${ffmpeg_src_dir}/fftools/ffmpeg_mux_init.c
        ${ffmpeg_src_dir}/fftools/ffmpeg_opt.c
        ${ffmpeg_src_dir}/fftools/objpool.c
        ${ffmpeg_src_dir}/fftools/opt_common.c
        ${ffmpeg_src_dir}/fftools/sync_queue.c
        ${ffmpeg_src_dir}/fftools/thread_queue.c
        )

target_include_directories(ffmpegplay PRIVATE
        ${ffmpeg_build_dir}
        ${ffmpeg_src_dir}/fftools
        ${ffmpeg_src_dir})

target_link_libraries( # Specifies the target library.
        ffmpegplay

        ${ffmpeg_install_dir}/lib/libavdevice.a
        ${ffmpeg_install_dir}/lib/libavfilter.a
        ${ffmpeg_install_dir}/lib/libavformat.a
        ${ffmpeg_install_dir}/lib/libavcodec.a
        ${ffmpeg_install_dir}/lib/libpostproc.a
        ${ffmpeg_install_dir}/lib/libswresample.a
        ${ffmpeg_install_dir}/lib/libswscale.a
        ${ffmpeg_install_dir}/lib/libavutil.a
        ${ffmpeg_install_dir}/lib/libx264.a

        camera2ndk
        mediandk
        android
        m
        atomic
        z
        log)