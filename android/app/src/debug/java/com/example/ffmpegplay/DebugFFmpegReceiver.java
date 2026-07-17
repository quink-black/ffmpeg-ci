package com.example.ffmpegplay;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

/*
 * Debug-only receiver that runs an FFmpeg command from an intent extra so
 * automated tests can drive FFmpeg without the IME. Only registered in
 * debug builds via the debug AndroidManifest; never ships in release.
 *
 * Usage:
 *   adb shell am broadcast \
 *       -n com.example.ffmpegplay/.DebugFFmpegReceiver \
 *       -e cmd "ffmpeg -version"
 * The command runs on the FFmpeg executor thread; results go to logcat
 * under the FFmpeg tag (see FFmpeg.runFFmpegCmd).
 */
public class DebugFFmpegReceiver extends BroadcastReceiver {
    private static final String TAG = "FFmpeg";

    @Override
    public void onReceive(Context context, Intent intent) {
        String cmd = intent.getStringExtra("cmd");
        if (cmd == null || cmd.isEmpty()) {
            Log.w(TAG, "DebugFFmpegReceiver: missing 'cmd' extra");
            return;
        }
        Log.i(TAG, "DebugFFmpegReceiver: running cmd: " + cmd);
        FFmpeg.getInstance().runFFmpegCmd(cmd, (c, ret) ->
                Log.i(TAG, "DebugFFmpegReceiver: cmd finished ret=" + ret + " cmd=" + c));
    }
}
