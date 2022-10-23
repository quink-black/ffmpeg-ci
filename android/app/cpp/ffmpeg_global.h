//
// Created by quink on 2022/10/23.
//

#ifndef FFMPEG_PLAYGROUND_FFMPEG_GLOBAL_H
#define FFMPEG_PLAYGROUND_FFMPEG_GLOBAL_H

#include <setjmp.h>

extern jmp_buf gFFmpegExitEntry;
extern int gFFmpegExitOffset;

#endif //FFMPEG_PLAYGROUND_FFMPEG_GLOBAL_H
