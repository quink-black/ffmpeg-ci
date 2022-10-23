//
// Created by quink on 2022/10/23.
//

#ifndef FFMPEG_PLAYGROUND_FFMPEG_GLOBAL_H
#define FFMPEG_PLAYGROUND_FFMPEG_GLOBAL_H

#include <setjmp.h>
#include <jni.h>

extern jmp_buf gFFmpegExitEntry;
extern int gFFmpegExitOffset;
extern jobject gSurfaceObject;

#endif //FFMPEG_PLAYGROUND_FFMPEG_GLOBAL_H
