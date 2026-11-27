---
description: "Check FFmpeg builds in the debug, release, and ASan release profiles"
allowed-tools: Bash(./cibuild.sh:*)
---

Build FFmpeg in the debug and release profiles with FATE skipped. Build the
ASan release profile when the selected toolchain can link AddressSanitizer.
Set `FFMPEG_SRC` to use a specific FFmpeg worktree.

!`./cibuild.sh ${FFMPEG_SRC:+--path "$FFMPEG_SRC"} --profile debug --skip-test && ./cibuild.sh ${FFMPEG_SRC:+--path "$FFMPEG_SRC"} --profile release --skip-test && ./cibuild.sh ${FFMPEG_SRC:+--path "$FFMPEG_SRC"} --profile asan-release --skip-test --skip-unsupported-asan`
