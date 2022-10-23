package com.example.ffmpegplay;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.appcompat.app.AppCompatActivity;

import android.content.ContentResolver;
import android.media.MediaCodec;
import android.net.Uri;
import android.os.Bundle;
import android.os.Parcel;
import android.os.ParcelFileDescriptor;
import android.util.Log;
import android.view.Surface;
import android.view.View;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;

import com.example.ffmpegplay.databinding.ActivityMainBinding;

public class MainActivity extends AppCompatActivity {
    private static final String TAG = "ffmpeg_main_activity";
    private ActivityMainBinding binding;
    private TextView runFFmpeg;
    private EditText ffmpegCmd;
    private TextView transcode;
    ActivityResultLauncher<String> getContent = registerForActivityResult(
            new ActivityResultContracts.GetContent(), this::onInputSelected);

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
        String cmd = "ffmpeg -hwaccel mediacodec -i pipe:" + fileDescriptor.getFd() + " -an -c:v h264_mediacodec -f mp4 -y " + output;
        transcode.setText("Transcode with " + cmd);
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