# FFmpeg vcpkg Overlay Port

This directory contains a custom vcpkg overlay port for building FFmpeg with additional features including OpenCV support.

## Prerequisites

1. **MSYS2** environment on Windows
2. **Visual Studio 2019/2022** (Community, Professional, or Enterprise)
3. **vcpkg** installed at `~/work/vcpkg`
4. **FFmpeg source** at `~/work/ffmpeg`

## Directory Structure

Expected directory structure:
```
~/work/
├── vcpkg/              # vcpkg installation
├── ffmpeg/             # FFmpeg source code
└── ffmpeg-ci/
    └── vcpkg/          # This overlay port directory
```

## Usage

### Build Release Only (Default)
```bash
./build.sh
```

### Build Release + Debug
```bash
./build.sh --debug
```

### Force Rebuild
```bash
./build.sh --force
```

### Clean Build Artifacts
```bash
./clean.sh                    # Clean all triplets
./clean.sh x64-windows        # Clean specific triplet
```

## Features

This overlay port includes:
- **all-gpl** features (x264, x265, etc.)
- **OpenCV** support for video filtering
- **Tesseract** OCR support
- **QSV** (Intel Quick Sync Video) support
- And many more codecs and filters

## Troubleshooting

### Visual Studio Not Found
The build script auto-detects Visual Studio installation. Supported editions:
- Visual Studio 2022/2019 Enterprise
- Visual Studio 2022/2019 Professional  
- Visual Studio 2022/2019 Community
- Visual Studio 2022/2019 Build Tools

### Build Errors
Check the log files:
- Release build: `~/ffmpeg_release_build.log`
- Debug build: `~/ffmpeg_debug_build.log`

## Notes

- The port automatically detects FFmpeg source location relative to the overlay port directory
- Runtime library flags are correctly set for both Debug (-MDd) and Release (-MD) builds
- All paths are dynamically determined based on the current user's environment
