package com.example.ffmpegplay;

import androidx.appcompat.app.AppCompatActivity;

import android.os.Bundle;
import android.view.View;
import android.widget.EditText;
import android.widget.TextView;

import com.example.ffmpegplay.databinding.ActivityMainBinding;

public class MainActivity extends AppCompatActivity {

    // Used to load the 'ffmpegplay' library on application startup.
    static {
        System.loadLibrary("ffmpegplay");
    }

    private ActivityMainBinding binding;
    private TextView runFFmpeg;
    private EditText ffmpegCmd;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        binding = ActivityMainBinding.inflate(getLayoutInflater());
        setContentView(binding.getRoot());

        runFFmpeg = binding.ffmpegRun;
        runFFmpeg.setOnClickListener(this::runFFmpegCmd);

        ffmpegCmd = binding.ffmpegCmd;
    }

    private void runFFmpegCmd(View view) {
        String cmd = ffmpegCmd.getText().toString();
        runFFmpeg.setText("Run FFmpeg cmd: " + cmd + " ...");
        int ret = runFFmpeg(cmd);
        runFFmpeg.setText("Run FFmpeg cmd: " + cmd + " ret " + ret);
    }

    /**
     * A native method that is implemented by the 'ffmpegplay' native library,
     * which is packaged with this application.
     */
    public static native int runFFmpeg(String cmd);
}