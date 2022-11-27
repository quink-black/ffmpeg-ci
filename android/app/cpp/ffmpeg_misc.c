#include "ffmpeg.h"
#include "cmdutils.h"
#include "ffmpeg_mux.h"
#include "libavcodec/jni.h"

void resetFFmpegGlobal() {
    input_streams = NULL;
    nb_input_streams = 0;
    input_files = NULL;
    nb_input_files = 0;
    output_files = NULL;
    nb_output_files = 0;
    filtergraphs = NULL;
    nb_filtergraphs = 0;
    vstats_filename = NULL;
    sdp_filename = NULL;
    audio_drift_threshold = 0.1f;
    dts_delta_threshold = 10;
    dts_error_threshold = 3600 * 30;
    video_sync_method = VSYNC_AUTO;
    frame_drop_threshold = 0;
    do_benchmark      = 0;
    do_benchmark_all  = 0;
    do_hex_dump       = 0;
    do_pkt_dump       = 0;
    copy_ts           = 0;
    start_at_zero     = 0;
    copy_tb           = -1;
    debug_ts          = 0;
    exit_on_error     = 0;
    abort_on_flags    = 0;
    print_stats       = -1;
    qp_hist           = 0;
    stdin_interaction = 1;
    max_error_rate  = 2.0/3;
    filter_nbthreads = 0;
    filter_complex_nbthreads = 0;
    vstats_version = 2;
    auto_conversion_filters = 1;
    stats_period = 500000;
    qp_hist = 0;
    stdin_interaction = 1;
    progress_avio = NULL;
    max_error_rate = 2.0 /3;
    filter_nbthreads = NULL;
    filter_complex_nbthreads = 0;
    vstats_version = 2;
    auto_conversion_filters = 1;
    filter_hw_device = NULL;
    nb_output_dumped = 0;
    main_return_code = 0;
    ignore_unknown_streams = 0;
    copy_unknown_streams = 0;
    do_psnr = 0;
    sws_dict = NULL;
    swr_opts = NULL;
    format_opts = NULL;
    codec_opts = NULL;
    hide_banner = 0;
    want_sdp = 1;
}

