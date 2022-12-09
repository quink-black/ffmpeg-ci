cmake_minimum_required(VERSION 3.6)

project("ffmpegplay")

set(ffmpeg_build_dir ${CMAKE_CURRENT_SOURCE_DIR}/../../../build/ffmpeg-aarch64/)
set(ffmpeg_src_dir ${CMAKE_CURRENT_SOURCE_DIR}/../../../build/ffmpeg-aarch64/src)
#set(ffmpeg_install_dir ${CMAKE_CURRENT_SOURCE_DIR}/../../../install)

add_library(ffmpegplay SHARED
        ffmpeg_misc.c
        native-lib.cpp
        cmdutils.c
        ffmpeg.c
        ffmpeg_hw.c
        cmdutils.h
        ffmpeg.h
        ffmpeg_mux.h
        fopen_utf8.h
        objpool.h
        opt_common.h
        sync_queue.h
        thread_queue.h
        ffmpeg_demux.c
        ffmpeg_filter.c
        ffmpeg_mux.c
        ffmpeg_mux_init.c
        ffmpeg_opt.c
        objpool.c
        opt_common.c
        sync_queue.c
        thread_queue.c
        )

target_include_directories(ffmpegplay PRIVATE
        ${ffmpeg_build_dir}
        ${ffmpeg_src_dir}/fftools
        ${ffmpeg_src_dir})

target_link_libraries(ffmpegplay
        ${ffmpeg_build_dir}/libavdevice/libavdevice.a
        ${ffmpeg_build_dir}/libavfilter/libavfilter.a
        ${ffmpeg_build_dir}/libavformat/libavformat.a
        ${ffmpeg_build_dir}/libavcodec/libavcodec.a
        ${ffmpeg_build_dir}/libpostproc/libpostproc.a
        ${ffmpeg_build_dir}/libswresample/libswresample.a
        ${ffmpeg_build_dir}/libswscale/libswscale.a
        ${ffmpeg_build_dir}/libavutil/libavutil.a
        #${ffmpeg_install_dir}/lib/libx264.a

        camera2ndk
        mediandk
        android
        m
        atomic
        z
        log)