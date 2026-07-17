Android platform patches applied on top of upstream fftools
==========================================================

These are the ONLY changes made to the upstream fftools files synced from
/Users/quink/work/ffmpeg_all/ffmpeg (see FFMPEG_UPSTREAM_VERSION). They must
be re-applied after every re-sync. Everything below is project-private and
does NOT exist upstream.

----------------------------------------------------------------------
PATCH 1 (KEEP) - MediaCodec surface injection for on-screen rendering
----------------------------------------------------------------------
File : ffmpeg_hw.c
Why  : Pass the Java Surface (set via FFmpeg.setSurface() -> gSurfaceObject in
       native-lib.cpp) into the MediaCodec hardware device, so decoded video
       frames are rendered directly to the Android Surface instead of being
       copied back to CPU memory. Upstream has no equivalent: upstream creates
       the MediaCodec device with av_hwdevice_ctx_create() and leaves surface
       == NULL.
How  : In BOTH device-creation paths, when type == AV_HWDEVICE_TYPE_MEDIACODEC,
       replace av_hwdevice_ctx_create() with:
           device_ref = av_hwdevice_ctx_alloc(type);
           ((AVMediaCodecDeviceContext *)device_ref->data->hwctx)->surface =
               gSurfaceObject;
           av_hwdevice_ctx_init(device_ref);
       - hw_device_init_from_string(): the "no parameters" branch  (if (!*p))
       - hw_device_init_from_type()  : the whole body for MEDIACODEC
       Also add at top of file:
           #include "libavutil/hwcontext_mediacodec.h"
           #include "ffmpeg_global.h"
           extern jobject gSurfaceObject;
Re-apply after sync: search ffmpeg_hw.c for "av_hwdevice_ctx_create" inside
       the two functions above and wrap the MEDIACODEC case as described.

----------------------------------------------------------------------
PATCH 2 (DROP) - reentrant ffmpeg_main() via setjmp/longjmp
----------------------------------------------------------------------
Was  : ffmpeg.c used to define int ffmpeg_main(...) wrapping main() with
       setjmp(exit_buf) + register_exit(ffmpeg_cleanup), turning the upstream
       exit_program()/exit() into a longjmp so the process is NOT killed and
       ffmpeg can be invoked repeatedly from the same Android process.
Now  : NOT NEEDED. Since the scheduler-refactor the upstream main() no longer
       calls exit(); it does `goto finish; ffmpeg_cleanup(ret); return ret;`.
       native-lib.cpp simply calls main(argc, argv) directly. No patch needed.
Re-apply after sync: NONE. Just keep native-lib.cpp calling main().

----------------------------------------------------------------------
PATCH 3 (DROP) - read_key() -> readVirtualKey()
----------------------------------------------------------------------
Was  : ffmpeg.c's read_key() was replaced by readVirtualKey() (a JNI bridge to
       Java key events) so interactive '?'/'q' worked under Android.
Now  : NOT NEEDED. On Android (no HAVE_TERMIOS_H / HAVE_KBHIT) the upstream
       read_key() already returns -1, i.e. keyboard interaction is disabled.
       The app drives ffmpeg non-interactively. No patch needed.
Re-apply after sync: NONE.

----------------------------------------------------------------------
PATCH 4 (ADAPT) - resetFFmpegGlobal() globals list
----------------------------------------------------------------------
File : ffmpeg_misc.c
Why  : resetFFmpegGlobal() resets the global option variables. The set of
       globals changed across the refactor (sdp_filename, qp_hist,
       main_return_code, do_psnr, sws_dict, format_opts, codec_opts,
       hide_banner, want_sdp, etc. were removed upstream). Keep only the
       globals that still exist in the current ffmpeg.h/cmdutils.h.
Re-apply after sync: grep ffmpeg.h for each variable name; comment out the
       ones that no longer exist.

----------------------------------------------------------------------
PATCH 5 (KEEP) - skip android_binder_threadpool_init_if_required()
----------------------------------------------------------------------
File : ffmpeg.c
Why  : Upstream ffmpeg.c calls android_binder_threadpool_init_if_required()
       (guarded by CONFIG_MEDIACODEC) before transcode(). That helper calls
       ABinderProcess_setThreadPoolMaxThreadCount() / startThreadPool(), which
       asserts (SIGABRT) on Android 15+ (API 35) when FFmpeg runs as a
       library inside an app process that already owns a binder thread pool.
       libavutil.a provides the symbol; we simply never call it. No shadow
       binder.c/binder.h is needed in app/cpp.
How  : In ffmpeg.c, wrap the upstream
           #if CONFIG_MEDIACODEC
           android_binder_threadpool_init_if_required();
           #endif
       block in `#if 0 ... #endif` with a comment pointing here. Also drop
       the `#include "compat/android/binder.h"` near the top of ffmpeg.c.
Re-apply after sync: after copying the new ffmpeg.c, search for
       android_binder_threadpool_init_if_required and re-wrap the call in
       #if 0 with the explanatory comment. Confirm CMakeLists.txt does not
       list a local binder.c.

----------------------------------------------------------------------
PATCH 6 (KEEP) - reset file-local statics at the start of main()
----------------------------------------------------------------------
File : ffmpeg.c
Why  : Upstream main() is written for a single invocation per process.
       Several file-local statics are left dirty after a run and are never
       zeroed: received_sigterm / received_nb_signals (set by
       sigterm_handler; read by decode_interrupt_cb and the final exit-code
       mapping at `received_nb_signals ? 255 : ...`), transcode_init_done
       (set to 1 in transcode(); read by decode_interrupt_cb), ffmpeg_exited
       (set to 1 in ffmpeg_cleanup()), and copy_ts_first_pts (set to the
       first PTS; read by print_report). This build calls main() repeatedly
       from one app process (native-lib.cpp), so a signal received in one
       run poisons the next: the follow-up run reports "Exiting normally,
       received signal N" and exits 255 even though transcoding succeeded.
How  : At the top of main(), before init_dynload(), reset all five statics
       to their initial values:
         received_sigterm = 0;
         received_nb_signals = 0;
         atomic_store(&transcode_init_done, 0);
         ffmpeg_exited = 0;
         copy_ts_first_pts = AV_NOPTS_VALUE;
Re-apply after sync: after copying the new ffmpeg.c, add the reset block
       at the top of main() (after the local variable declarations, before
       init_dynload()). Verify the five statics still exist with the same
       names; if upstream renamed or removed any, adjust accordingly.

----------------------------------------------------------------------
Files that are project-private and never overwritten by sync
----------------------------------------------------------------------
  native-lib.cpp   - JNI bridge: runFFmpeg() tokenizes the cmd string and
                     calls main(argc, argv); setSurface() stores the Java
                     Surface into gSurfaceObject; sendKey() feeds readVirtualKey.
  ffmpeg_global.h  - declares gSurfaceObject (jobject), readVirtualKey(),
                     resetFFmpegGlobal().
  ffmpeg_misc.c    - resetFFmpegGlobal() (see PATCH 4).
  objpool.c/.h     - leftover from an older fftools layout, still compiled.
