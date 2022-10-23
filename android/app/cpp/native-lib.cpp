#include <android/log.h>
#include <jni.h>
#include <cstring>
#include <string>
#include <vector>

#include "ffmpeg_global.h"
extern "C" {
#include "libavcodec/jni.h"
}

constexpr const char *kLogTag = "FFmpeg";

jmp_buf gFFmpegExitEntry = {};
int gFFmpegExitOffset = 100;
jobject gSurfaceObject = nullptr;

extern "C" int ffmpeg_main(int argc, char *argv[]);

extern "C"
JNIEXPORT jint JNICALL
Java_com_example_ffmpegplay_FFmpeg_runFFmpeg(JNIEnv *env, jclass clazz, jstring cmd) {
    std::string str;
    {
        const char *tmp = env->GetStringUTFChars(cmd, nullptr);
        if (tmp == nullptr) {
            __android_log_print(ANDROID_LOG_ERROR, kLogTag, "Empty cmd");
            return -1;
        }
        str = tmp;
        env->ReleaseStringUTFChars(cmd, tmp);
    }

    std::vector<char *> cmd_list;
    char *save;
    char *ptr = strtok_r(&str[0], " ", &save);
    if (ptr)
        cmd_list.push_back(ptr);
    while ((ptr = strtok_r(nullptr, " ", &save)))
        cmd_list.push_back(ptr);

    if (cmd_list.empty()) {
        __android_log_print(ANDROID_LOG_WARN, kLogTag, "invalid argument %s\n", str.c_str());
        return -1;
    }

    cmd_list.push_back(nullptr);
    int ret = setjmp(gFFmpegExitEntry);
    if (ret) {
        ret -= gFFmpegExitOffset;
        __android_log_print(ANDROID_LOG_WARN, kLogTag, "FFmpeg exit from longjump, %d", ret);
    } else {
        ret = ffmpeg_main(cmd_list.size() - 1, cmd_list.data());
        __android_log_print(ANDROID_LOG_WARN, kLogTag, "FFmpeg exit from return, %d", ret);
    }

    return ret;
}

extern "C"
JNIEXPORT void JNICALL
Java_com_example_ffmpegplay_FFmpeg_setSurface(JNIEnv *env, jclass clazz, jobject surface) {
    if (gSurfaceObject)
        env->DeleteGlobalRef(gSurfaceObject);
    gSurfaceObject = env->NewGlobalRef(surface);
}

JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {
    av_jni_set_java_vm(vm, nullptr);
    return JNI_VERSION_1_6;
}

JNIEXPORT void JNI_OnUnload(JavaVM* vm, void* reserved)
{
    av_jni_set_java_vm(nullptr, nullptr);
}

