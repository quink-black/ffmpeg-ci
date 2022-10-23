package com.example.ffmpegplay;

import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.Surface;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class FFmpeg {
    // Used to load the 'ffmpegplay' library on application startup.
    static {
        System.loadLibrary("ffmpegplay");
    }

    private static final String TAG = "FFmpeg";
    private ExecutorService executor = Executors.newSingleThreadExecutor();
    private Handler handler = new Handler(Looper.getMainLooper());

    public static interface OnFFmpegFinish {
        void onResult(String cmd, int ret);
    }

    public void runFFmpegCmd(String cmd, OnFFmpegFinish callback) {
        Log.i(TAG, "run cmd " + cmd);
        executor.submit(() -> {
            int ret = runFFmpeg(cmd);
            handler.post(() -> callback.onResult(cmd, ret));
        });
    }

    public void setCodecSurface(Surface surface) {
        Log.i(TAG, "set surface");
        setSurface(surface);
    }

    private static native void setSurface(Surface surface);

    private static native int runFFmpeg(String cmd);

    private static FFmpeg instance = new FFmpeg();
    public static FFmpeg getInstance() {
        return instance;
    }
}
