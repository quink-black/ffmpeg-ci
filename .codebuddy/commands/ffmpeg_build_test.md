---
description: "Build FFmpeg in debug, optimized, and optimized+ASAN configs"
allowed-tools: Bash(./cibuild.sh:*)
---

Build FFmpeg in three configurations (debug, optimized, optimized+ASAN) with tests skipped.

!`unset -f rm 2>/dev/null; unalias rm 2>/dev/null; FFMPEG_SRC=$PWD/../ffmpeg; if [ ! -d "$FFMPEG_SRC" ]; then FFMPEG_SRC=$PWD/../master_ffmpeg; fi; ./cibuild.sh --path "$FFMPEG_SRC" --skip_test && ./cibuild.sh --path "$FFMPEG_SRC" --enable_opt 1 --skip_test && ./cibuild.sh --path "$FFMPEG_SRC" --enable_opt 1 --enable_asan 1 --skip_test`
