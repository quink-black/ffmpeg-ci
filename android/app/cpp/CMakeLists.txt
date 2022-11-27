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