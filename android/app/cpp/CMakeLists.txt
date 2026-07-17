cmake_minimum_required(VERSION 3.6)

project("ffmpegplay")

set(ffmpeg_build_dir ${CMAKE_CURRENT_SOURCE_DIR}/../../../build/ffmpeg-aarch64/)
set(ffmpeg_src_dir ${CMAKE_CURRENT_SOURCE_DIR}/../../../build/ffmpeg-aarch64/src)
set(ffmpeg_ci_dir ${CMAKE_CURRENT_SOURCE_DIR}/../../../)
#set(ffmpeg_install_dir ${CMAKE_CURRENT_SOURCE_DIR}/../../../install)

add_library(ffmpegplay SHARED
        ffmpeg_misc.c
        native-lib.cpp
        cmdutils.c
        ffmpeg.c
        ffmpeg_dec.c
        ffmpeg_enc.c
        ffmpeg_sched.c
        ffmpeg_hw.c
        cmdutils.h
        ffmpeg.h
        ffmpeg_mux.h
        ffmpeg_sched.h
        ffmpeg_utils.h
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
        graph/graphprint.c
        textformat/avtextformat.c
        textformat/tf_compact.c
        textformat/tf_default.c
        textformat/tf_flat.c
        textformat/tf_ini.c
        textformat/tf_json.c
        textformat/tf_mermaid.c
        textformat/tf_xml.c
        textformat/tw_avio.c
        textformat/tw_buffer.c
        textformat/tw_stdout.c
        ffmpeg_resman.c
        )

target_include_directories(ffmpegplay PRIVATE
        ${ffmpeg_build_dir}
        ${ffmpeg_src_dir}/fftools
        ${ffmpeg_src_dir}
        ${CMAKE_CURRENT_SOURCE_DIR}/graph
        ${CMAKE_CURRENT_SOURCE_DIR}/textformat
        ${CMAKE_CURRENT_SOURCE_DIR}/resources
        ${CMAKE_CURRENT_SOURCE_DIR}/compat/stdbit)

# Android 15+ on arm64 requires 16KB page alignment for shared libraries.
# -z,max-page-size=16384 is sufficient for NDK versions that default to 4K.
# Newer NDK (r26+) defaults to 16KB max-page-size, so this flag is a no-op.
target_link_options(ffmpegplay PRIVATE
        "-Wl,-Bsymbolic"
        "-Wl,-z,max-page-size=16384"
        )

target_link_libraries(ffmpegplay
        ${ffmpeg_build_dir}/libavdevice/libavdevice.a
        ${ffmpeg_build_dir}/libavfilter/libavfilter.a
        ${ffmpeg_build_dir}/libavformat/libavformat.a
        ${ffmpeg_build_dir}/libavcodec/libavcodec.a
        ${ffmpeg_build_dir}/libswresample/libswresample.a
        ${ffmpeg_build_dir}/libswscale/libswscale.a
        ${ffmpeg_build_dir}/libavutil/libavutil.a
        # external deps the FFmpeg static libs were built against (NDK28 + libplacebo/vulkan)
        ${ffmpeg_ci_dir}/install-aarch64/lib/libplacebo.a
        ${ffmpeg_ci_dir}/prebuilt_android/aarch64/libshaderc.a
        vulkan
        #${ffmpeg_install_dir}/lib/libx264.a

        camera2ndk
        mediandk
        android
        m
        atomic
        z
        log)