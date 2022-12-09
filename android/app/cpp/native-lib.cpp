#include <android/log.h>
#include <jni.h>
#include <cstring>
#include <mutex>
#include <queue>
#include <string>
#include <vector>
#include <dlfcn.h>

#include "ffmpeg_global.h"
extern "C" {
#include "libavutil/log.h"
#include "libavcodec/jni.h"
}

constexpr const char *kLogTag = "FFmpeg";

jobject gSurfaceObject = nullptr;

static std::mutex sMutex;
static std::queue<char> sVirtualKeyQueue;

static JavaVM *gJavaVM;

extern "C" int ffmpeg_main(int argc, char **argv);

static void log_callback(void *ctx, int prio, const char *fmt, va_list va)
{
    AVClass* avc = ctx ? *(AVClass **) ctx : NULL;
    const char *tag = "FFmpeg";
    int android_prio = ANDROID_LOG_INFO;

    if (prio > av_log_get_level())
        return;

    if (avc && avc->item_name(ctx))
        tag = avc->item_name(ctx);
    if (prio >= AV_LOG_TRACE)
        android_prio = ANDROID_LOG_VERBOSE;
    else if (prio >= AV_LOG_DEBUG)
        android_prio = ANDROID_LOG_DEBUG;
    else if (prio >= AV_LOG_INFO)
        android_prio = ANDROID_LOG_INFO;
    else if (prio >= AV_LOG_WARNING)
        android_prio = ANDROID_LOG_WARN;
    else if (prio >= AV_LOG_ERROR)
        android_prio = ANDROID_LOG_ERROR;
    else if (prio >= AV_LOG_FATAL)
        android_prio = ANDROID_LOG_FATAL;

    __android_log_vprint(android_prio, tag, fmt, va);
}

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

    resetFFmpegGlobal();

    av_log_set_callback(log_callback);
    av_jni_set_java_vm(gJavaVM, nullptr);

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
    int ret = ffmpeg_main(cmd_list.size() - 1, cmd_list.data());
    __android_log_print(ANDROID_LOG_WARN, kLogTag, "FFmpeg exit from return, %d", ret);

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
    gJavaVM = vm;
    return JNI_VERSION_1_6;
}

extern "C"
JNIEXPORT void JNICALL
Java_com_example_ffmpegplay_FFmpeg_sendKey(JNIEnv *env, jclass clazz, jint key) {
    std::lock_guard<std::mutex> lockGuard(sMutex);
    sVirtualKeyQueue.push(key);
}

int readVirtualKey() {
    std::lock_guard<std::mutex> lockGuard(sMutex);
    if (sVirtualKeyQueue.empty())
        return -1;
    char c = sVirtualKeyQueue.back();
    sVirtualKeyQueue.pop();
    return c;
}