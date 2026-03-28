# FFmpeg CMake Three-Level Build Control

## Overview

The FFmpeg CMake build system implements a three-level control mechanism equivalent to
the original `configure + Makefile` system. This document describes how each level works,
how they interact, and the data flow from user options to compiled binaries.

```
┌─────────────────────────────────────────────────────────────────┐
│  L1: External Library Toggle                                     │
│  User: -DENABLE_LIBX264=ON                                      │
│  → pkg-config/find_package → CONFIG_LIBX264=1                   │
├─────────────────────────────────────────────────────────────────┤
│  L2: Component Dependency Resolution                             │
│  CONFIG_LIBX264=1 → CONFIG_LIBX264_ENCODER=1                   │
│  → _select → CONFIG_ATSC_A53=1, CONFIG_GOLOMB=1                │
│  → _deps check → disable components with unmet deps             │
├─────────────────────────────────────────────────────────────────┤
│  L3: Source File Conditional Compilation                         │
│  config_components.h: #define CONFIG_LIBX264_ENCODER 1          │
│  CMakeLists.txt: if(CONFIG_LIBX264_ENCODER) → libx264.c        │
│  codec_list.c: &ff_libx264_encoder (only if enabled)            │
└─────────────────────────────────────────────────────────────────┘
```

## Level 1: External Library Toggle

### configure equivalent
```bash
./configure --enable-libx264 --enable-libx265 --enable-gpl
```

### CMake equivalent
```bash
cmake -B build -DENABLE_LIBX264=ON -DENABLE_LIBX265=ON -DENABLE_GPL=ON
```

### Implementation

**File: `cmake/FFmpegExternalLibs.cmake`**

1. User options are defined via `option(ENABLE_LIBX264 ...)` 
2. When enabled, the library is detected via `pkg_check_modules()` or `find_package()`
3. On success: `set(CONFIG_LIBX264 1 CACHE INTERNAL "")`
4. On failure: `set(CONFIG_LIBX264 0 CACHE INTERNAL "")` + warning

**File: `cmake/FFmpegDefaults.cmake`**

Sets default values for all `ENABLE_*` options and license flags:
- `ENABLE_GPL` → `CONFIG_GPL`
- `ENABLE_VERSION3` → `CONFIG_VERSION3`
- `ENABLE_NONFREE` → `CONFIG_NONFREE`

### License Dependencies

Some external libraries require specific licenses:
- `libx264` requires GPL (`libx264_encoder_deps = "libx264 gpl"`)
- `libopencore_amrnb` requires GPL + version3 (`lgpl_gpl`)

The dependency resolver checks these at L2.

## Level 2: Component Dependency Resolution

### configure equivalent

The `configure` script uses two key functions:

1. **`enable_deep()`**: When a component is enabled, recursively enable all its `_select` dependencies
2. **`check_deps()`**: For each component, verify all `_deps` are satisfied; disable if not

### CMake equivalent

**File: `cmake/FFmpegDependencyResolver.cmake`**

Two macros implement the equivalent logic:

1. **`_ffmpeg_enable_deep(component)`**: Recursively enables `_SELECT` dependencies
2. **`_ffmpeg_check_deps(component)`**: Checks all dependency types

**File: `cmake/FFmpegComponentDeps.cmake`**

Defines all component dependencies using CMake variables:

```cmake
set(LIBX264_ENCODER_DEPS "LIBX264;GPL")
set(LIBX264_ENCODER_SELECT "ATSC_A53;GOLOMB")
```

### Dependency Types

| Type | configure syntax | CMake variable | Semantics |
|------|-----------------|----------------|-----------|
| `_deps` | `foo_deps="a b"` | `FOO_DEPS "A;B"` | ALL must be satisfied |
| `_deps_any` | `foo_deps_any="a b"` | `FOO_DEPS_ANY "A;B"` | ANY one must be satisfied |
| `_select` | `foo_select="a b"` | `FOO_SELECT "A;B"` | Force-enable these when foo is enabled |
| `_suggest` | `foo_suggest="a b"` | `FOO_SUGGEST "A;B"` | Enable if available (soft dependency) |
| `_if` | `foo_if="a b"` | `FOO_IF "A;B"` | ALL conditions must be true |
| `_if_any` | `foo_if_any="a b"` | `FOO_IF_ANY "A;B"` | ANY condition must be true |
| `_conflict` | `foo_conflict="a"` | `FOO_CONFLICT "A"` | Disable foo if any conflict is enabled |

### Resolution Algorithm

```
ffmpeg_resolve_all_dependencies():
  1. Collect all known components from FFmpegComponentDeps.cmake
  2. Initialize: all components without _DEPS → CONFIG_XXX = 1 (default enabled)
  3. For each component with _DEPS:
     a. Check _deps: ALL must have CONFIG_dep = 1
     b. Check _deps_any: at least ONE must have CONFIG_dep = 1
     c. Check _conflict: NONE must have CONFIG_conflict = 1
     d. Check _if / _if_any: condition flags
     e. If all checks pass → CONFIG_XXX = 1
     f. If any check fails → CONFIG_XXX = 0
  4. For each enabled component:
     a. Process _select: enable_deep(each selected subsystem)
     b. Process _suggest: enable if available
  5. Repeat steps 3-4 until stable (max 10 iterations)
```

### Variable Scope

All `CONFIG_*` variables are stored as `CACHE INTERNAL` to ensure global visibility
across all CMake modules. This solves the original bug where `function()` scope
isolation caused variables to be lost during recursive resolution.

## Level 3: Source File Conditional Compilation

### Three output mechanisms

#### 1. `config_components.h`

**File: `cmake/FFmpegComponents.cmake`** → generates `${CMAKE_BINARY_DIR}/config_components.h`

```c
#define CONFIG_LIBX264_ENCODER 1
#define CONFIG_LIBX265_ENCODER 0
#define CONFIG_ATSC_A53 1
#define CONFIG_GOLOMB 1
```

Used by C source code for `#if CONFIG_XXX` conditional compilation blocks.

#### 2. Component list files

**File: `cmake/FFmpegComponents.cmake`** → generates `codec_list.c`, `muxer_list.c`, etc.

```c
// codec_list.c (only enabled codecs)
static const FFCodec * const codec_list[] = {
    &ff_libx264_encoder,    // CONFIG_LIBX264_ENCODER = 1
    // ff_libx265_encoder NOT included because CONFIG_LIBX265_ENCODER = 0
    &ff_h264_decoder,
    NULL
};
```

These files are `#include`d by `allcodecs.c`, `allformats.c`, etc.

#### 3. CMakeLists.txt conditional source inclusion

**File: `libavcodec/CMakeLists.txt`** (and other lib CMakeLists.txt)

```cmake
# Makefile equivalent: OBJS-$(CONFIG_ATSC_A53) += atsc_a53.o
if(CONFIG_ATSC_A53)
    list(APPEND avcodec_sources atsc_a53.c)
endif()

# Makefile equivalent: OBJS-$(CONFIG_LIBX264_ENCODER) += libx264.o
if(CONFIG_LIBX264_ENCODER)
    list(APPEND avcodec_sources libx264.c)
endif()
```

## End-to-End Example: libx264

```
User: cmake -B build -DENABLE_LIBX264=ON -DENABLE_GPL=ON

L1: FFmpegExternalLibs.cmake
    ├── pkg_check_modules(LIBX264 x264) → found
    ├── set(CONFIG_LIBX264 1 CACHE INTERNAL "")
    └── set(CONFIG_GPL 1)  (from FFmpegDefaults.cmake)

L2: FFmpegDependencyResolver.cmake
    ├── Component: LIBX264_ENCODER
    │   ├── LIBX264_ENCODER_DEPS = "LIBX264;GPL"
    │   │   ├── CONFIG_LIBX264 = 1 ✓
    │   │   └── CONFIG_GPL = 1 ✓
    │   ├── → CONFIG_LIBX264_ENCODER = 1
    │   └── LIBX264_ENCODER_SELECT = "ATSC_A53;GOLOMB"
    │       ├── enable_deep(ATSC_A53) → CONFIG_ATSC_A53 = 1
    │       └── enable_deep(GOLOMB) → CONFIG_GOLOMB = 1
    └── (repeat for all components)

L3: FFmpegComponents.cmake + libavcodec/CMakeLists.txt
    ├── config_components.h:
    │   ├── #define CONFIG_LIBX264_ENCODER 1
    │   ├── #define CONFIG_ATSC_A53 1
    │   └── #define CONFIG_GOLOMB 1
    ├── codec_list.c:
    │   └── &ff_libx264_encoder  (included)
    ├── libavcodec/CMakeLists.txt:
    │   ├── if(CONFIG_LIBX264_ENCODER) → libx264.c  (compiled)
    │   ├── if(CONFIG_ATSC_A53) → atsc_a53.c  (compiled)
    │   └── if(CONFIG_GOLOMB) → golomb.c  (compiled)
    └── FFmpegApplyExternalLibs.cmake:
        └── target_link_libraries(avcodec PRIVATE ${LIBX264_LIBRARIES})
```

## CMake Module Call Order

```
CMakeLists.txt (top-level)
│
├── include(FFmpegDefaults)          # Set default options, license flags
├── include(FFmpegExternalLibs)      # L1: Detect external libraries
│   └── ffmpeg_detect_libraries()    # pkg-config / find_package
├── include(FFmpegComponentDeps)     # Define _DEPS/_SELECT/_SUGGEST
├── include(FFmpegDependencyResolver)# L2: Resolve all dependencies
│   └── ffmpeg_resolve_all_dependencies()
├── include(FFmpegComponents)        # L3: Generate config_components.h + list files
│   └── ffmpeg_generate_components()
├── add_subdirectory(libavutil)
├── add_subdirectory(libavcodec)     # L3: Conditional source compilation
├── add_subdirectory(libavformat)
├── add_subdirectory(libavfilter)
├── add_subdirectory(libswscale)
├── add_subdirectory(libswresample)
├── add_subdirectory(libavdevice)
├── include(FFmpegApplyExternalLibs) # Link external libs to targets
│   └── ffmpeg_apply_external_libs()
└── add_subdirectory(fftools)        # Build ffmpeg, ffprobe, ffplay
```

## Generated Files

| File | Location | Purpose |
|------|----------|---------|
| `config.h` | `build/config.h` | Feature flags, HAVE_* macros |
| `config_components.h` | `build/config_components.h` | CONFIG_*_ENCODER/DECODER/etc. |
| `codec_list.c` | `build/libavcodec/codec_list.c` | Enabled codec list |
| `parser_list.c` | `build/libavcodec/parser_list.c` | Enabled parser list |
| `bsf_list.c` | `build/libavcodec/bsf_list.c` | Enabled BSF list |
| `muxer_list.c` | `build/libavformat/muxer_list.c` | Enabled muxer list |
| `demuxer_list.c` | `build/libavformat/demuxer_list.c` | Enabled demuxer list |
| `protocol_list.c` | `build/libavformat/protocol_list.c` | Enabled protocol list |
| `filter_list.c` | `build/libavfilter/filter_list.c` | Enabled filter list |
| `indev_list.c` | `build/libavdevice/indev_list.c` | Enabled input device list |
| `outdev_list.c` | `build/libavdevice/outdev_list.c` | Enabled output device list |
| `avconfig.h` | `build/libavutil/avconfig.h` | AV_HAVE_* macros |
| `ffversion.h` | `build/libavutil/ffversion.h` | Version string |

## Debugging Tips

### Check which components are enabled
```bash
cmake -B build -DENABLE_LIBX264=ON -DENABLE_GPL=ON 2>&1 | grep "CONFIG_"
```

### Check generated config_components.h
```bash
grep "LIBX264" build/config_components.h
```

### Check codec list
```bash
cat build/libavcodec/codec_list.c
```

### Verify dependency chain
Look for messages like:
```
-- Dependency resolved: LIBX264_ENCODER = 1 (deps: LIBX264 GPL)
-- Dependency resolved: ATSC_A53 = 1 (selected by: LIBX264_ENCODER)
```
