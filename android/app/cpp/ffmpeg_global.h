//
// Created by quink on 2022/10/23.
//

#ifndef FFMPEG_PLAYGROUND_FFMPEG_GLOBAL_H
#define FFMPEG_PLAYGROUND_FFMPEG_GLOBAL_H

#include <setjmp.h>
#include <jni.h>

extern jobject gSurfaceObject;

#ifdef __cplusplus
extern "C" {
#endif

int readVirtualKey();

void resetFFmpegGlobal();

#ifdef __cplusplus
}
#endif

#endif //FFMPEG_PLAYGROUND_FFMPEG_GLOBAL_H
