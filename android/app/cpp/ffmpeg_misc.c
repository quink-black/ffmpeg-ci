#include "ffmpeg.h"
#include "cmdutils.h"
#include "ffmpeg_mux.h"
#include "libavcodec/jni.h"

void resetFFmpegGlobal() {
    /* Only globals that are still defined in the upstream scheduler-refactor
     * fftools are reset here. Most former option globals (video_sync_method,
     * dts_delta_threshold, vstats_filename, ...) were moved into OptionsContext
     * or removed, so referencing them would cause an undefined symbol at link
     * time. ffmpeg_cleanup() already frees the per-run resources. See
     * ANDROID_PATCHES.md PATCH 4. */
    input_files = NULL;
    nb_input_files = 0;
    output_files = NULL;
    nb_output_files = 0;
    filtergraphs = NULL;
    nb_filtergraphs = 0;
    decoders = NULL;
    nb_decoders = 0;
    hide_banner = 0;
}