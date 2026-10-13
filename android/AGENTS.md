# AGENTS.md (android/)

Guidance for AI coding agents that build and test FFmpeg on an Android phone. Run commands from the `android/` directory unless stated otherwise.

## What this is

A debug app (`com.example.ffmpegplay`, arm64-v8a only) that links the FFmpeg static libraries and runs the `fftools/ffmpeg` command line in-process through JNI. A debug-only broadcast receiver lets `adb` run an ffmpeg command without touching the UI. There is no `ffprobe` in the app, and no standalone ffmpeg binary on the device.

| Path | Role |
|------|------|
| `app/cpp/native-lib.cpp` | JNI bridge: splits the command string on spaces, calls `main()`, routes `av_log` to logcat |
| `app/cpp/*.c`, `textformat/`, `graph/` | fftools synced from FFmpeg; see `app/cpp/ANDROID_PATCHES.md` and `FFMPEG_UPSTREAM_VERSION` before re-syncing |
| `app/src/debug/.../DebugFFmpegReceiver.java` | adb entry point (debug builds only) |
| `app/src/main/.../MainActivity.java` | Manual UI (command box, file-picker transcode, camera streaming) |

## Build

1. Cross-build FFmpeg and libplacebo for Android from the repo root. `ANDROID_NDK` must point to an NDK:

   ```bash
   ANDROID_NDK=<ndk> ./android_ffmpeg.sh --path <ffmpeg-src> --enable_opt 1
   ```

   This produces `build/ffmpeg-aarch64/` (FFmpeg static libs) and `install-aarch64/`. The script deletes and recreates `build/ffmpeg-aarch64/`.

2. Link the FFmpeg source into that directory. `app/cpp/CMakeLists.txt` takes headers from `build/ffmpeg-aarch64/src`, and nothing creates the link. Repeat it after every run of step 1:

   ```bash
   ln -s <ffmpeg-src> build/ffmpeg-aarch64/src
   ```

3. Build the APK. Needs JDK 17 or newer and `android/local.properties` with `sdk.dir=<sdk>` (optionally `ndk.version=<ver>`, otherwise AGP picks the installed NDK):

   ```bash
   ./gradlew :app:assembleDebug
   ```

   Output: `app/build/outputs/apk/debug/app-debug.apk`.

4. Install:

   ```bash
   adb install -r app/build/outputs/apk/debug/app-debug.apk
   ```

If only `fftools` code under `app/cpp` changed, repeat steps 3 and 4. If FFmpeg libraries changed, repeat from step 1.

## Run an ffmpeg command from the shell

The process must exist before the broadcast: start the activity once after installing, or after any `force-stop`. Broadcasts to a stopped app are silently dropped.

```bash
adb shell am start -n com.example.ffmpegplay/.MainActivity
adb logcat -c
adb shell "am broadcast -a com.example.ffmpegplay.DEBUG_RUN_FFMPEG -p com.example.ffmpegplay -e cmd 'ffmpeg -y -f lavfi -i testsrc=duration=2:size=320x240:rate=25 -c:v h264_mediacodec -f mp4 /sdcard/Android/media/com.example.ffmpegplay/t.mp4'"
adb logcat -d -s FFmpeg:* '*:S'
```

Rules that are easy to get wrong:

- **Quote twice.** Wrap the whole `am broadcast ...` in double quotes and the ffmpeg command in single quotes. Without the outer quotes, the device shell splits the command and `am` fails with `Unknown option: -v`.
- **Use `-a ... -p`, not `-n`.** The explicit-component form (`-n com.example.ffmpegplay/.DebugFFmpegReceiver`) was skipped by the system on an EMUI 14 / Android 12 device. The action form was delivered.
- **No shell quoting inside the command.** `native-lib.cpp` splits on spaces only, so an argument cannot contain a space, and `"` or `'` are passed literally. Filtergraphs must be written without spaces.
- **Commands run one at a time** on a single executor thread. Wait for the `cmd finished` line before sending the next one.
- **Do not run `ffmpeg -version`, `-encoders`, `-h`, and similar.** Their output goes to stdout, which is discarded on Android, so only the exit code shows up. Only `av_log` output reaches logcat.

## Read the result

- Exit code: the line `DebugFFmpegReceiver: cmd finished ret=<N> cmd=...` under tag `FFmpeg`. `ret=0` means success; a failure returns a negative `AVERROR` value, for example `ret=-2` for a missing input file.
- ffmpeg log: all `av_log` messages appear under tag `FFmpeg` (or the component name for context-bound messages). Each `av_log` call is a separate logcat line, so one console line may be split. Raise verbosity with `-v debug`.
- Crashes: `adb logcat -d | grep -E "FATAL|DEBUG|libc"` and tombstones from `adb bugreport`. A native crash kills the app process and ends the test.

## Files and checking output

Use the app's media directory for input and output. The app can read and write it without runtime permissions, and `adb` can reach it. Input pushed to `/data/local/tmp` is also readable, but writing there from the app is not verified:

```bash
D=/sdcard/Android/media/com.example.ffmpegplay
adb shell mkdir -p $D
adb push in.mp4 $D/
adb pull $D/t.mp4 .
adb shell rm $D/t.mp4
```

Two ways to check content:

- Pull the output and inspect it with host `ffprobe`/`ffmpeg`.
- Compute a hash on the device and read it back. stdout is discarded, so write the hash to a file:

  ```bash
  ... -e cmd 'ffmpeg -y -i $D/in.mp4 -f md5 $D/out.md5'
  adb shell cat $D/out.md5
  ```

## Hardware and surface paths

- MediaCodec encode/decode (`h264_mediacodec`, `-hwaccel mediacodec`) works from the broadcast entry point. For decode into a Surface, `FFmpeg.setCodecSurface()` must be called first; only `MainActivity` does this, so the transcode button is the way to exercise that path.
- Camera (`-f android_camera`) needs the CAMERA permission granted to the app. Grant it with `adb shell pm grant com.example.ffmpegplay android.permission.CAMERA`.
- Vulkan and libplacebo are linked in; their availability depends on the device driver.

## Pitfalls

- Android 15+ devices with 16 KB pages need the `.so` files uncompressed and 16 KB aligned. `app/build.gradle` handles this in the `realign*Apk16K` task; do not remove it.
- `ANDROID_PATCHES.md` lists local changes to fftools that must be re-applied after a re-sync, for example skipping `android_binder_threadpool_init_if_required()`, which aborts on Android 15+.
- The debug receiver is exported and has no permission check. It exists only in debug builds; never move it to `app/src/main`.
- `gradle/`, `caches/`, `daemon/`, `native/`, `jdks/` and `kotlin-profile/` are Gradle and tooling state, not sources.
