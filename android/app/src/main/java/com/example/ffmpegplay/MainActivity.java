package com.example.ffmpegplay;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.appcompat.app.AppCompatActivity;

import android.Manifest;
import android.content.ContentResolver;
import android.content.pm.PackageManager;
import android.media.MediaCodec;
import android.net.Uri;
import android.os.Bundle;
import android.os.Parcel;
import android.os.ParcelFileDescriptor;
import android.util.Log;
import android.view.Surface;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;

import com.example.ffmpegplay.databinding.ActivityMainBinding;

public class MainActivity extends AppCompatActivity {
    private static final String TAG = "ffmpeg_main_activity";
    private ActivityMainBinding binding;
    private TextView runFFmpeg;
    private EditText ffmpegCmd;
    private Button transcode;
    private Button camera;

    private ActivityResultLauncher<String> getContent = registerForActivityResult(
            new ActivityResultContracts.GetContent(), this::onInputSelected);

    private ActivityResultLauncher<String> requestPermissionLauncher =
            registerForActivityResult(new ActivityResultContracts.RequestPermission(), isGranted -> {
                Log.i(TAG, "granted " + isGranted);
            });

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        binding = ActivityMainBinding.inflate(getLayoutInflater());
        setContentView(binding.getRoot());

        runFFmpeg = binding.ffmpegRun;
        runFFmpeg.setOnClickListener(this::runFFmpegCmd);

        ffmpegCmd = binding.ffmpegCmd;

        transcode = binding.transcode;
        transcode.setOnClickListener( v -> {
            getContent.launch("video/*");
        });

        camera = binding.camera;
        camera.setOnClickListener(this::cameraStreaming);

        Button quit = binding.quit;
        quit.setOnClickListener(v -> {
            FFmpeg.getInstance().quit();
        });

        checkPermission();
    }

    private void checkPermission() {
        String[] permissions = {
            Manifest.permission.CAMERA,
        };

        for (String perm : permissions) {
            if (checkSelfPermission(perm) == PackageManager.PERMISSION_GRANTED) {
                continue;
            }
            requestPermissionLauncher.launch(perm);
        }
    }

    private void cameraStreaming(View view) {
        String cmd = "ffmpeg -v debug -video_size 1280x720 -framerate 30 -f android_camera -i 0 -c:v h264_mediacodec -g 60 -b:v 500000 -f rtp_mpegts rtp://224.0.0.1:8888";
        ffmpegCmd.setText(cmd);
        runFFmpegCmd(view);
    }

    private void runFFmpegCmd(View view) {
        String cmd = ffmpegCmd.getText().toString();
        runFFmpeg.setText("Run FFmpeg cmd: " + cmd + " ...");
        FFmpeg.getInstance().runFFmpegCmd(cmd, this::onFFmpegResult);
    }

    private void onFFmpegResult(String cmd, int ret) {
        runFFmpeg.setText("Run FFmpeg cmd: " + cmd + " ret " + ret);
    }

    private void onInputSelected(Uri input) {
        ParcelFileDescriptor fileDescriptor;
        try {
            ContentResolver resolver = getContentResolver();
            fileDescriptor = resolver.openFileDescriptor(input, "r");
        } catch (Exception e) {
            Log.w(TAG, "Could not open '" + input.toString() + "'", e);
            Toast.makeText(this, "File not found.", Toast.LENGTH_LONG).show();
            return;
        }

        String output = getExternalMediaDirs()[0].getAbsolutePath() + "/" + "video.mp4";;
        String cmd = "ffmpeg -hwaccel mediacodec -i fd:" + fileDescriptor.getFd() + " -an -c:v h264_mediacodec -f mp4 -y " + output;
        ffmpegCmd.setText("Transcode with " + cmd);
        runFFmpeg.setText("Run FFmpeg cmd: " + cmd + " ...");
        Surface surface = MediaCodec.createPersistentInputSurface();
        FFmpeg.getInstance().setCodecSurface(surface);
        FFmpeg.getInstance().runFFmpegCmd(cmd, new FFmpeg.OnFFmpegFinish() {
            @Override
            public void onResult(String cmd, int ret) {
                surface.release();
                try {
                    fileDescriptor.close();
                } catch (Exception exception) {
                    Log.e(TAG, "close file exception", exception);
                }
                onFFmpegResult(cmd, ret);
            }
        });
    }
}