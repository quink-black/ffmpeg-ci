# Custom FFmpeg vcpkg port - Using local ffmpeg source from ~/work/ffmpeg
# Simplified version focusing on essential features

# ============================================================================
# SECTION 1: Source Path Detection
# ============================================================================
get_filename_component(_PORT_DIR "${CMAKE_CURRENT_LIST_DIR}" ABSOLUTE)
get_filename_component(_HOME_DIR "${_PORT_DIR}/../../../.." ABSOLUTE)
set(_WORK_DIR "${_HOME_DIR}/work")

# Try cygpath for MSYS2 compatibility
execute_process(
    COMMAND cygpath -m "${_WORK_DIR}/ffmpeg"
    OUTPUT_VARIABLE SOURCE_PATH
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
)
if(NOT SOURCE_PATH)
    set(SOURCE_PATH "${_WORK_DIR}/ffmpeg")
endif()
message(STATUS "FFmpeg source: ${SOURCE_PATH}")

if(SOURCE_PATH MATCHES " ")
    message(FATAL_ERROR "Error: ffmpeg will not build with spaces in the path")
endif()

# ============================================================================
# SECTION 2: Tool Setup
# ============================================================================
vcpkg_add_to_path(PREPEND "${CURRENT_HOST_INSTALLED_DIR}/manual-tools/ffmpeg-bin2c")

if(VCPKG_TARGET_ARCHITECTURE STREQUAL "x86" OR VCPKG_TARGET_ARCHITECTURE STREQUAL "x64")
    vcpkg_find_acquire_program(NASM)
    get_filename_component(NASM_EXE_PATH "${NASM}" DIRECTORY)
    vcpkg_add_to_path("${NASM_EXE_PATH}")
endif()

# ============================================================================
# SECTION 3: Library Aliases (Windows MSVC only)
# ============================================================================
if(VCPKG_TARGET_IS_WINDOWS AND NOT VCPKG_TARGET_IS_MINGW)
    # FFmpeg configure expects certain library names that don't match vcpkg's naming
    # Create aliases so configure can find them
    set(_LIB_ALIASES_RELEASE
        "libmp3lame:mp3lame"
        "libx264:x264"
        "libx265:x265"
        "opencv_core4:opencv_core"
        "opencv_imgproc4:opencv_imgproc"
    )
    set(_LIB_ALIASES_DEBUG
        "libmp3lame:mp3lame"
        "libx264:x264"
        "libx265:x265"
        "opencv_core4d:opencv_core"
        "opencv_imgproc4d:opencv_imgproc"
    )
    # Create release aliases
    foreach(_alias IN LISTS _LIB_ALIASES_RELEASE)
        string(REPLACE ":" ";" _parts "${_alias}")
        list(GET _parts 0 _src)
        list(GET _parts 1 _dst)
        if(EXISTS "${CURRENT_INSTALLED_DIR}/lib/${_src}.lib" AND NOT EXISTS "${CURRENT_INSTALLED_DIR}/lib/${_dst}.lib")
            file(COPY_FILE "${CURRENT_INSTALLED_DIR}/lib/${_src}.lib" "${CURRENT_INSTALLED_DIR}/lib/${_dst}.lib")
        endif()
    endforeach()
    # Create debug aliases
    foreach(_alias IN LISTS _LIB_ALIASES_DEBUG)
        string(REPLACE ":" ";" _parts "${_alias}")
        list(GET _parts 0 _src)
        list(GET _parts 1 _dst)
        if(EXISTS "${CURRENT_INSTALLED_DIR}/debug/lib/${_src}.lib" AND NOT EXISTS "${CURRENT_INSTALLED_DIR}/debug/lib/${_dst}.lib")
            file(COPY_FILE "${CURRENT_INSTALLED_DIR}/debug/lib/${_src}.lib" "${CURRENT_INSTALLED_DIR}/debug/lib/${_dst}.lib")
        endif()
    endforeach()
endif()

# ============================================================================
# SECTION 4: Base Options
# ============================================================================
set(OPTIONS "--enable-pic --disable-doc --enable-runtime-cpudetect --disable-autodetect")
set(OPTIONS "${OPTIONS} --enable-static --disable-shared")

# Fix C++ STL ABI compatibility issue:
# vcpkg debug builds use _ITERATOR_DEBUG_LEVEL=2 (MSVC default for /MDd)
# We need FFmpeg's C++ code to use the same setting to avoid std::vector incompatibility
# This is done by NOT overriding _ITERATOR_DEBUG_LEVEL in CXXFLAGS

# Platform-specific options
if(VCPKG_TARGET_IS_WINDOWS AND NOT VCPKG_TARGET_IS_MINGW)
    set(OPTIONS "${OPTIONS} --target-os=win32 --enable-w32threads --enable-d3d11va --enable-d3d12va --enable-dxva2 --enable-mediafoundation")
elseif(VCPKG_TARGET_IS_LINUX)
    set(OPTIONS "${OPTIONS} --target-os=linux --enable-pthreads")
elseif(VCPKG_TARGET_IS_OSX)
    set(OPTIONS "${OPTIONS} --target-os=darwin --enable-appkit --enable-avfoundation --enable-coreimage --enable-audiotoolbox --enable-videotoolbox")
endif()

# ============================================================================
# SECTION 5: Feature Configuration
# ============================================================================
# License options
if("nonfree" IN_LIST FEATURES)
    set(OPTIONS "${OPTIONS} --enable-nonfree")
endif()
if("gpl" IN_LIST FEATURES)
    set(OPTIONS "${OPTIONS} --enable-gpl")
endif()

# Core libraries
foreach(lib IN ITEMS avcodec avdevice avfilter avformat swresample swscale)
    if("${lib}" IN_LIST FEATURES)
        set(OPTIONS "${OPTIONS} --enable-${lib}")
    else()
        set(OPTIONS "${OPTIONS} --disable-${lib}")
    endif()
endforeach()

# Applications
foreach(app IN ITEMS ffmpeg ffplay ffprobe)
    if("${app}" IN_LIST FEATURES)
        set(OPTIONS "${OPTIONS} --enable-${app}")
    else()
        set(OPTIONS "${OPTIONS} --disable-${app}")
    endif()
endforeach()

# External libraries
if("aom" IN_LIST FEATURES)
    set(OPTIONS "${OPTIONS} --enable-libaom")
else()
    set(OPTIONS "${OPTIONS} --disable-libaom")
endif()

if("mp3lame" IN_LIST FEATURES)
    set(OPTIONS "${OPTIONS} --enable-libmp3lame")
else()
    set(OPTIONS "${OPTIONS} --disable-libmp3lame")
endif()

if("opus" IN_LIST FEATURES)
    set(OPTIONS "${OPTIONS} --enable-libopus")
else()
    set(OPTIONS "${OPTIONS} --disable-libopus")
endif()

if("vpx" IN_LIST FEATURES)
    set(OPTIONS "${OPTIONS} --enable-libvpx")
else()
    set(OPTIONS "${OPTIONS} --disable-libvpx")
endif()

if("x264" IN_LIST FEATURES)
    set(OPTIONS "${OPTIONS} --enable-libx264")
else()
    set(OPTIONS "${OPTIONS} --disable-libx264")
endif()

if("x265" IN_LIST FEATURES)
    set(OPTIONS "${OPTIONS} --enable-libx265")
else()
    set(OPTIONS "${OPTIONS} --disable-libx265")
endif()

if("sdl2" IN_LIST FEATURES)
    set(OPTIONS "${OPTIONS} --enable-sdl2")
else()
    set(OPTIONS "${OPTIONS} --disable-sdl2")
endif()

if("iconv" IN_LIST FEATURES)
    set(OPTIONS "${OPTIONS} --enable-iconv")
else()
    set(OPTIONS "${OPTIONS} --disable-iconv")
endif()

if("zlib" IN_LIST FEATURES)
    set(OPTIONS "${OPTIONS} --enable-zlib")
else()
    set(OPTIONS "${OPTIONS} --disable-zlib")
endif()

# OpenCV support
# On Windows MSVC, FFmpeg configure checks opencv_core which doesn't exist (vcpkg uses opencv_core4).
# We create library aliases in SECTION 3 to handle this.
if("opencv" IN_LIST FEATURES)
    set(OPTIONS "${OPTIONS} --enable-libopencv")
    # Note: extra-cxxflags will be set in SECTION 6 to include both include path and CRT flags
    string(APPEND VCPKG_COMBINED_C_FLAGS_DEBUG " -I \"${CURRENT_INSTALLED_DIR}/include/opencv4\"")
    string(APPEND VCPKG_COMBINED_C_FLAGS_RELEASE " -I \"${CURRENT_INSTALLED_DIR}/include/opencv4\"")
else()
    set(OPTIONS "${OPTIONS} --disable-libopencv")
endif()

# Tesseract support
if("tesseract" IN_LIST FEATURES)
    set(OPTIONS "${OPTIONS} --enable-libtesseract")
else()
    set(OPTIONS "${OPTIONS} --disable-libtesseract")
endif()

# ============================================================================
# SECTION 6: Compiler/Toolchain Setup
# ============================================================================
vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

if(VCPKG_DETECTED_MSVC)
    set(OPTIONS "--toolchain=msvc ${OPTIONS}")
endif()

string(APPEND VCPKG_COMBINED_C_FLAGS_DEBUG " -I \"${CURRENT_INSTALLED_DIR}/include\"")
string(APPEND VCPKG_COMBINED_C_FLAGS_RELEASE " -I \"${CURRENT_INSTALLED_DIR}/include\"")

# Set C++ extra flags to ensure ABI compatibility with vcpkg-built libraries
# FFmpeg's configure sets CXXFLAGS separately from CFLAGS, so we need to pass CRT flags explicitly
# For debug: /MDd ensures _ITERATOR_DEBUG_LEVEL=2 (MSVC default) - compatible with vcpkg debug libs
# For release: /MD ensures _ITERATOR_DEBUG_LEVEL=0 (MSVC default) - compatible with vcpkg release libs
set(_OPENCV_INCLUDE "")
if("opencv" IN_LIST FEATURES)
    set(_OPENCV_INCLUDE "-I\"${CURRENT_INSTALLED_DIR}/include/opencv4\" ")
endif()
if(VCPKG_DETECTED_MSVC)
    # Debug C++ flags: include /MDd for proper STL debug mode
    set(EXTRA_CXXFLAGS_DEBUG "${_OPENCV_INCLUDE}/MDd")
    # Release C++ flags: include /MD for release mode
    set(EXTRA_CXXFLAGS_RELEASE "${_OPENCV_INCLUDE}/MD")
else()
    set(EXTRA_CXXFLAGS_DEBUG "${_OPENCV_INCLUDE}")
    set(EXTRA_CXXFLAGS_RELEASE "${_OPENCV_INCLUDE}")
endif()

# Setup compiler paths
set(prog_env "")

if(VCPKG_DETECTED_CMAKE_C_COMPILER)
    get_filename_component(CC_path "${VCPKG_DETECTED_CMAKE_C_COMPILER}" DIRECTORY)
    get_filename_component(CC_filename "${VCPKG_DETECTED_CMAKE_C_COMPILER}" NAME)
    set(ENV{CC} "${CC_filename}")
    string(APPEND OPTIONS " --cc=${CC_filename} --host-cc=${CC_filename}")
    list(APPEND prog_env "${CC_path}")
endif()

if(VCPKG_DETECTED_CMAKE_CXX_COMPILER)
    get_filename_component(CXX_path "${VCPKG_DETECTED_CMAKE_CXX_COMPILER}" DIRECTORY)
    get_filename_component(CXX_filename "${VCPKG_DETECTED_CMAKE_CXX_COMPILER}" NAME)
    set(ENV{CXX} "${CXX_filename}")
    string(APPEND OPTIONS " --cxx=${CXX_filename}")
    list(APPEND prog_env "${CXX_path}")
endif()

if(VCPKG_DETECTED_CMAKE_LINKER AND VCPKG_TARGET_IS_WINDOWS AND NOT VCPKG_TARGET_IS_MINGW)
    get_filename_component(LD_path "${VCPKG_DETECTED_CMAKE_LINKER}" DIRECTORY)
    get_filename_component(LD_filename "${VCPKG_DETECTED_CMAKE_LINKER}" NAME)
    set(ENV{LD} "${LD_filename}")
    string(APPEND OPTIONS " --ld=${LD_filename}")
    list(APPEND prog_env "${LD_path}")
endif()

if(VCPKG_DETECTED_CMAKE_AR)
    get_filename_component(AR_path "${VCPKG_DETECTED_CMAKE_AR}" DIRECTORY)
    get_filename_component(AR_filename "${VCPKG_DETECTED_CMAKE_AR}" NAME)
    if(AR_filename MATCHES [[^(llvm-)?lib\.exe$]])
        set(ENV{AR} "ar-lib ${AR_filename}")
        string(APPEND OPTIONS " --ar='ar-lib ${AR_filename}'")
    else()
        set(ENV{AR} "${AR_filename}")
        string(APPEND OPTIONS " --ar='${AR_filename}'")
    endif()
    list(APPEND prog_env "${AR_path}")
endif()

# Setup shell for build
if(VCPKG_HOST_IS_WINDOWS)
    vcpkg_acquire_msys(MSYS_ROOT PACKAGES automake)
    set(SHELL "${MSYS_ROOT}/usr/bin/bash.exe")
    vcpkg_execute_required_process(
        COMMAND "${SHELL}" -c "'/usr/bin/automake' --print-lib"
        OUTPUT_VARIABLE automake_lib
        OUTPUT_STRIP_TRAILING_WHITESPACE
        WORKING_DIRECTORY "${MSYS_ROOT}"
        LOGNAME automake-print-lib
    )
    list(APPEND prog_env "${MSYS_ROOT}/usr/bin" "${MSYS_ROOT}${automake_lib}")
else()
    find_program(SHELL bash)
endif()

list(REMOVE_DUPLICATES prog_env)
vcpkg_add_to_path(PREPEND ${prog_env})

file(REMOVE_RECURSE "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-dbg" "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

# Architecture setup
if(VCPKG_TARGET_ARCHITECTURE STREQUAL "x64")
    set(BUILD_ARCH "x86_64")
else()
    set(BUILD_ARCH ${VCPKG_TARGET_ARCHITECTURE})
endif()

# Windows-specific flags
if(VCPKG_TARGET_IS_WINDOWS AND NOT VCPKG_TARGET_IS_MINGW)
    set(OPTIONS "${OPTIONS} --extra-cflags=-DHAVE_UNISTD_H=0")
endif()

# PKG_CONFIG setup
vcpkg_find_acquire_program(PKGCONFIG)
set(OPTIONS "${OPTIONS} --pkg-config=\"${PKGCONFIG}\"")
if(VCPKG_LIBRARY_LINKAGE STREQUAL "static")
    set(OPTIONS "${OPTIONS} --pkg-config-flags=--static")
endif()

# Build configuration options
set(OPTIONS_DEBUG "--disable-optimizations --enable-debug")
set(OPTIONS_RELEASE "--enable-optimizations")

message(STATUS "Building Options: ${OPTIONS}")

# ============================================================================
# SECTION 7: Release Build
# ============================================================================
if(NOT VCPKG_BUILD_TYPE OR VCPKG_BUILD_TYPE STREQUAL "release")
    if(VCPKG_DETECTED_MSVC)
        set(OPTIONS_RELEASE "${OPTIONS_RELEASE} --extra-ldflags=-libpath:\"${CURRENT_INSTALLED_DIR}/lib\"")
        set(OPTIONS_RELEASE "${OPTIONS_RELEASE} --extra-ldflags=iconv.lib")
        set(OPTIONS_RELEASE "${OPTIONS_RELEASE} --extra-cxxflags=${EXTRA_CXXFLAGS_RELEASE}")
    else()
        set(OPTIONS_RELEASE "${OPTIONS_RELEASE} --extra-ldflags=-L\"${CURRENT_INSTALLED_DIR}/lib\"")
    endif()

    message(STATUS "Building ${PORT} for Release")
    file(MAKE_DIRECTORY "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")

    set(crsp "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel/cflags.rsp")
    string(REGEX REPLACE "-arch [A-Za-z0-9_]+" "" VCPKG_COMBINED_C_FLAGS_RELEASE_SANITIZED "${VCPKG_COMBINED_C_FLAGS_RELEASE}")
    file(WRITE "${crsp}" "${VCPKG_COMBINED_C_FLAGS_RELEASE_SANITIZED}")
    set(ldrsp "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel/ldflags.rsp")
    string(REGEX REPLACE "-arch [A-Za-z0-9_]+" "" VCPKG_COMBINED_SHARED_LINKER_FLAGS_RELEASE_SANITIZED "${VCPKG_COMBINED_SHARED_LINKER_FLAGS_RELEASE}")
    file(WRITE "${ldrsp}" "${VCPKG_COMBINED_SHARED_LINKER_FLAGS_RELEASE_SANITIZED}")
    set(ENV{CFLAGS} "@${crsp}")
    set(ENV{LDFLAGS} "@${ldrsp}")
    set(ENV{ARFLAGS} "${VCPKG_COMBINED_STATIC_LINKER_FLAGS_RELEASE}")

    set(BUILD_DIR         "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel")
    set(CONFIGURE_OPTIONS "${OPTIONS} ${OPTIONS_RELEASE}")
    set(INST_PREFIX       "${CURRENT_PACKAGES_DIR}")

    configure_file("${CMAKE_CURRENT_LIST_DIR}/build.sh.in" "${BUILD_DIR}/build.sh" @ONLY)

    z_vcpkg_setup_pkgconfig_path(CONFIG RELEASE)

    vcpkg_execute_required_process(
        COMMAND "${SHELL}" ./build.sh
        WORKING_DIRECTORY "${BUILD_DIR}"
        LOGNAME "build-${TARGET_TRIPLET}-rel"
        SAVE_LOG_FILES ffbuild/config.log
    )

    z_vcpkg_restore_pkgconfig_path()
endif()

# ============================================================================
# SECTION 8: Debug Build
# ============================================================================
if(NOT VCPKG_BUILD_TYPE OR VCPKG_BUILD_TYPE STREQUAL "debug")
    if(VCPKG_DETECTED_MSVC)
        set(OPTIONS_DEBUG "${OPTIONS_DEBUG} --extra-ldflags=-libpath:\"${CURRENT_INSTALLED_DIR}/debug/lib\"")
        set(OPTIONS_DEBUG "${OPTIONS_DEBUG} --extra-ldflags=-libpath:\"${CURRENT_INSTALLED_DIR}/lib\"")
        set(OPTIONS_DEBUG "${OPTIONS_DEBUG} --extra-ldflags=iconv.lib")
        set(OPTIONS_DEBUG "${OPTIONS_DEBUG} --extra-cxxflags=${EXTRA_CXXFLAGS_DEBUG}")
    else()
        set(OPTIONS_DEBUG "${OPTIONS_DEBUG} --extra-ldflags=-L\"${CURRENT_INSTALLED_DIR}/debug/lib\"")
        set(OPTIONS_DEBUG "${OPTIONS_DEBUG} --extra-ldflags=-L\"${CURRENT_INSTALLED_DIR}/lib\"")
    endif()

    message(STATUS "Building ${PORT} for Debug")
    file(MAKE_DIRECTORY "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-dbg")

    set(crsp "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-dbg/cflags.rsp")
    string(REGEX REPLACE "-arch [A-Za-z0-9_]+" "" VCPKG_COMBINED_C_FLAGS_DEBUG_SANITIZED "${VCPKG_COMBINED_C_FLAGS_DEBUG}")
    file(WRITE "${crsp}" "${VCPKG_COMBINED_C_FLAGS_DEBUG_SANITIZED}")
    set(ldrsp "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-dbg/ldflags.rsp")
    string(REGEX REPLACE "-arch [A-Za-z0-9_]+" "" VCPKG_COMBINED_SHARED_LINKER_FLAGS_DEBUG_SANITIZED "${VCPKG_COMBINED_SHARED_LINKER_FLAGS_DEBUG}")
    file(WRITE "${ldrsp}" "${VCPKG_COMBINED_SHARED_LINKER_FLAGS_DEBUG_SANITIZED}")
    set(ENV{CFLAGS} "@${crsp}")
    set(ENV{LDFLAGS} "@${ldrsp}")
    set(ENV{ARFLAGS} "${VCPKG_COMBINED_STATIC_LINKER_FLAGS_DEBUG}")

    set(BUILD_DIR         "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-dbg")
    set(CONFIGURE_OPTIONS "${OPTIONS} ${OPTIONS_DEBUG}")
    set(INST_PREFIX       "${CURRENT_PACKAGES_DIR}/debug")

    configure_file("${CMAKE_CURRENT_LIST_DIR}/build.sh.in" "${BUILD_DIR}/build.sh" @ONLY)

    z_vcpkg_setup_pkgconfig_path(CONFIG DEBUG)
    vcpkg_host_path_list(APPEND ENV{PKG_CONFIG_PATH} "${CURRENT_INSTALLED_DIR}/lib/pkgconfig")

    vcpkg_execute_required_process(
        COMMAND "${SHELL}" ./build.sh
        WORKING_DIRECTORY "${BUILD_DIR}"
        LOGNAME "build-${TARGET_TRIPLET}-dbg"
        SAVE_LOG_FILES ffbuild/config.log
    )

    z_vcpkg_restore_pkgconfig_path()
endif()

# ============================================================================
# SECTION 9: Post-Build Processing
# ============================================================================
# Generate .lib files from .def on Windows
if(VCPKG_TARGET_IS_WINDOWS AND NOT VCPKG_TARGET_IS_MINGW)
    file(GLOB DEF_FILES "${CURRENT_PACKAGES_DIR}/lib/*.def" "${CURRENT_PACKAGES_DIR}/debug/lib/*.def")

    if(VCPKG_TARGET_ARCHITECTURE STREQUAL "x64")
        set(LIB_MACHINE_ARG /machine:x64)
    elseif(VCPKG_TARGET_ARCHITECTURE STREQUAL "x86")
        set(LIB_MACHINE_ARG /machine:x86)
    elseif(VCPKG_TARGET_ARCHITECTURE STREQUAL "arm64")
        set(LIB_MACHINE_ARG /machine:ARM64)
    endif()

    foreach(DEF_FILE ${DEF_FILES})
        get_filename_component(DEF_FILE_DIR "${DEF_FILE}" DIRECTORY)
        get_filename_component(DEF_FILE_NAME "${DEF_FILE}" NAME)
        string(REGEX REPLACE "-[0-9]*\\.def" "${VCPKG_TARGET_STATIC_LIBRARY_SUFFIX}" OUT_FILE_NAME "${DEF_FILE_NAME}")
        file(TO_NATIVE_PATH "${DEF_FILE}" DEF_FILE_NATIVE)
        file(TO_NATIVE_PATH "${DEF_FILE_DIR}/${OUT_FILE_NAME}" OUT_FILE_NATIVE)
        vcpkg_execute_required_process(
            COMMAND lib.exe "/def:${DEF_FILE_NATIVE}" "/out:${OUT_FILE_NATIVE}" ${LIB_MACHINE_ARG}
            WORKING_DIRECTORY "${CURRENT_PACKAGES_DIR}"
            LOGNAME "libconvert-${TARGET_TRIPLET}"
        )
    endforeach()

    file(GLOB EXP_FILES "${CURRENT_PACKAGES_DIR}/lib/*.exp" "${CURRENT_PACKAGES_DIR}/debug/lib/*.exp")
    file(GLOB LIB_FILES "${CURRENT_PACKAGES_DIR}/bin/*${VCPKG_TARGET_STATIC_LIBRARY_SUFFIX}" "${CURRENT_PACKAGES_DIR}/debug/bin/*${VCPKG_TARGET_STATIC_LIBRARY_SUFFIX}")
    set(files_to_remove ${EXP_FILES} ${LIB_FILES} ${DEF_FILES})
    if(files_to_remove)
        file(REMOVE ${files_to_remove})
    endif()
endif()

# ============================================================================
# SECTION 10: Install Tools
# ============================================================================
# Determine tools search directory
if(DEFINED VCPKG_BUILD_TYPE AND VCPKG_BUILD_TYPE STREQUAL "debug")
    set(TOOLS_SEARCH_DIR "${CURRENT_PACKAGES_DIR}/debug/bin")
else()
    set(TOOLS_SEARCH_DIR "${CURRENT_PACKAGES_DIR}/bin")
endif()

# Copy Release tools
if("ffmpeg" IN_LIST FEATURES)
    vcpkg_copy_tools(TOOL_NAMES ffmpeg SEARCH_DIR "${TOOLS_SEARCH_DIR}" AUTO_CLEAN)
endif()
if("ffprobe" IN_LIST FEATURES)
    vcpkg_copy_tools(TOOL_NAMES ffprobe SEARCH_DIR "${TOOLS_SEARCH_DIR}" AUTO_CLEAN)
endif()
if("ffplay" IN_LIST FEATURES)
    vcpkg_copy_tools(TOOL_NAMES ffplay SEARCH_DIR "${TOOLS_SEARCH_DIR}" AUTO_CLEAN)
endif()

# Copy Debug tools to separate directory
# Note: Debug executables may have '_g' suffix (ffmpeg_g.exe) or no suffix depending on build
if(NOT DEFINED VCPKG_BUILD_TYPE)
    set(DEBUG_TOOLS_DIR "${CURRENT_PACKAGES_DIR}/tools/${PORT}/debug")
    file(MAKE_DIRECTORY "${DEBUG_TOOLS_DIR}")

    # Try both regular and _g suffix versions
    foreach(_tool ffmpeg ffprobe ffplay)
        if("${_tool}" IN_LIST FEATURES)
            set(_found FALSE)
            foreach(_suffix "" "_g")
                set(_exe "${CURRENT_PACKAGES_DIR}/debug/bin/${_tool}${_suffix}.exe")
                if(EXISTS "${_exe}")
                    file(COPY "${_exe}" DESTINATION "${DEBUG_TOOLS_DIR}")
                    # Also copy PDB file if exists
                    set(_pdb "${CURRENT_PACKAGES_DIR}/debug/bin/${_tool}${_suffix}.pdb")
                    if(EXISTS "${_pdb}")
                        file(COPY "${_pdb}" DESTINATION "${DEBUG_TOOLS_DIR}")
                    endif()
                    message(STATUS "Installed debug ${_tool}${_suffix}.exe to ${DEBUG_TOOLS_DIR}")
                    set(_found TRUE)
                    break()
                endif()
            endforeach()
            if(NOT _found)
                message(WARNING "Debug ${_tool} not found in ${CURRENT_PACKAGES_DIR}/debug/bin - checking build directory")
                # Fallback: try to copy from build directory
                foreach(_suffix "" "_g")
                    set(_exe "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-dbg/${_tool}${_suffix}.exe")
                    if(EXISTS "${_exe}")
                        file(COPY "${_exe}" DESTINATION "${DEBUG_TOOLS_DIR}")
                        message(STATUS "Installed debug ${_tool}${_suffix}.exe from build dir to ${DEBUG_TOOLS_DIR}")
                        set(_found TRUE)
                        break()
                    endif()
                endforeach()
            endif()
            if(NOT _found)
                message(WARNING "Debug ${_tool} not found anywhere")
            endif()
        endif()
    endforeach()

    # ========================================================================
    # Recursive DLL dependency resolution using dumpbin
    # This function finds all DLL dependencies for an executable
    # ========================================================================
    function(copy_dll_dependencies EXE_PATH DEST_DIR SEARCH_DIRS IS_DEBUG)
        if(NOT EXISTS "${EXE_PATH}")
            message(WARNING "Executable not found: ${EXE_PATH}")
            return()
        endif()

        # Use dumpbin to get DLL dependencies
        execute_process(
            COMMAND dumpbin /DEPENDENTS "${EXE_PATH}"
            OUTPUT_VARIABLE DUMPBIN_OUTPUT
            ERROR_QUIET
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )

        # Parse dumpbin output to extract DLL names
        string(REPLACE "\n" ";" DUMPBIN_LINES "${DUMPBIN_OUTPUT}")
        set(_NEEDED_DLLS "")
        foreach(_line IN LISTS DUMPBIN_LINES)
            string(STRIP "${_line}" _line)
            # DLL names appear as lines ending with .dll (case insensitive)
            if(_line MATCHES "^[A-Za-z0-9_\\-\\.]+\\.[Dd][Ll][Ll]$")
                list(APPEND _NEEDED_DLLS "${_line}")
            endif()
        endforeach()

        # System DLLs to skip (Windows system libraries)
        set(_SYSTEM_DLLS
            "KERNEL32.dll" "kernel32.dll"
            "USER32.dll" "user32.dll"
            "GDI32.dll" "gdi32.dll"
            "ADVAPI32.dll" "advapi32.dll"
            "SHELL32.dll" "shell32.dll"
            "ole32.dll" "OLE32.dll"
            "OLEAUT32.dll" "oleaut32.dll"
            "COMCTL32.dll" "comctl32.dll"
            "COMDLG32.dll" "comdlg32.dll"
            "SHLWAPI.dll" "shlwapi.dll"
            "WS2_32.dll" "ws2_32.dll"
            "WINMM.dll" "winmm.dll"
            "WINSPOOL.DRV" "winspool.drv"
            "MSVCRT.dll" "msvcrt.dll"
            "MSVCP140.dll" "msvcp140.dll"
            "VCRUNTIME140.dll" "vcruntime140.dll"
            "VCRUNTIME140_1.dll" "vcruntime140_1.dll"
            "ucrtbase.dll" "UCRTBASE.dll"
            "api-ms-win-*"
            "ntdll.dll" "NTDLL.dll"
            "bcrypt.dll" "BCRYPT.dll"
            "crypt32.dll" "CRYPT32.dll"
            "secur32.dll" "SECUR32.dll"
            "mfplat.dll" "MFPLAT.dll"
            "mfuuid.dll"
            "d3d11.dll" "D3D11.dll"
            "dxgi.dll" "DXGI.dll"
            "d3d12.dll"
            "IMM32.dll" "imm32.dll"
            "VERSION.dll" "version.dll"
            "SETUPAPI.dll" "setupapi.dll"
        )

        foreach(_dll_name IN LISTS _NEEDED_DLLS)
            # Skip system DLLs
            set(_is_system FALSE)
            foreach(_sys_dll IN LISTS _SYSTEM_DLLS)
                if(_dll_name MATCHES "${_sys_dll}" OR _dll_name STREQUAL "${_sys_dll}")
                    set(_is_system TRUE)
                    break()
                endif()
            endforeach()

            if(_is_system)
                continue()
            endif()

            # Skip if already copied
            if(EXISTS "${DEST_DIR}/${_dll_name}")
                continue()
            endif()

            # Search for the DLL in provided directories
            set(_dll_found FALSE)
            foreach(_search_dir IN LISTS SEARCH_DIRS)
                # Case-insensitive search on Windows
                file(GLOB _found_dlls "${_search_dir}/${_dll_name}" "${_search_dir}/${_dll_name}")
                if(NOT _found_dlls)
                    # Try lowercase
                    string(TOLOWER "${_dll_name}" _dll_name_lower)
                    file(GLOB _found_dlls "${_search_dir}/${_dll_name_lower}")
                endif()
                if(NOT _found_dlls)
                    # Try uppercase
                    string(TOUPPER "${_dll_name}" _dll_name_upper)
                    file(GLOB _found_dlls "${_search_dir}/${_dll_name_upper}")
                endif()

                if(_found_dlls)
                    list(GET _found_dlls 0 _dll_path)
                    file(COPY "${_dll_path}" DESTINATION "${DEST_DIR}")
                    message(STATUS "Copied ${_dll_name} to ${DEST_DIR}")
                    set(_dll_found TRUE)

                    # Recursively copy dependencies of this DLL
                    copy_dll_dependencies("${_dll_path}" "${DEST_DIR}" "${SEARCH_DIRS}" ${IS_DEBUG})
                    break()
                endif()
            endforeach()

            if(NOT _dll_found)
                message(STATUS "DLL not found in vcpkg (may be system DLL): ${_dll_name}")
            endif()
        endforeach()
    endfunction()

    # Define search directories for debug (prefer debug, fallback to release)
    set(_DEBUG_SEARCH_DIRS
        "${CURRENT_INSTALLED_DIR}/debug/bin"
        "${CURRENT_INSTALLED_DIR}/bin"
    )

    # Copy DLLs for debug tools
    foreach(_tool ffmpeg ffprobe ffplay)
        if("${_tool}" IN_LIST FEATURES)
            foreach(_suffix "" "_g")
                set(_exe "${DEBUG_TOOLS_DIR}/${_tool}${_suffix}.exe")
                if(EXISTS "${_exe}")
                    message(STATUS "Resolving DLL dependencies for debug ${_tool}${_suffix}.exe")
                    copy_dll_dependencies("${_exe}" "${DEBUG_TOOLS_DIR}" "${_DEBUG_SEARCH_DIRS}" TRUE)
                    break()
                endif()
            endforeach()
        endif()
    endforeach()
endif()

# Copy DLLs for release tools
set(RELEASE_TOOLS_DIR "${CURRENT_PACKAGES_DIR}/tools/${PORT}")
set(_RELEASE_SEARCH_DIRS
    "${CURRENT_INSTALLED_DIR}/bin"
)

foreach(_tool ffmpeg ffprobe ffplay)
    if("${_tool}" IN_LIST FEATURES)
        set(_exe "${RELEASE_TOOLS_DIR}/${_tool}.exe")
        if(EXISTS "${_exe}")
            message(STATUS "Resolving DLL dependencies for release ${_tool}.exe")
            copy_dll_dependencies("${_exe}" "${RELEASE_TOOLS_DIR}" "${_RELEASE_SEARCH_DIRS}" FALSE)
        endif()
    endif()
endforeach()

# ============================================================================
# SECTION 11: Cleanup and Install
# ============================================================================
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include" "${CURRENT_PACKAGES_DIR}/debug/share")

if(VCPKG_LIBRARY_LINKAGE STREQUAL "static")
    file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/bin" "${CURRENT_PACKAGES_DIR}/debug/bin")
endif()

vcpkg_copy_pdbs()
vcpkg_fixup_pkgconfig()

file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")

# Handle copyright
file(STRINGS "${CURRENT_BUILDTREES_DIR}/build-${TARGET_TRIPLET}-rel-out.log" LICENSE_STRING REGEX "License: .*" LIMIT_COUNT 1)
if(LICENSE_STRING STREQUAL "License: LGPL version 2.1 or later")
    set(LICENSE_FILE "COPYING.LGPLv2.1")
elseif(LICENSE_STRING STREQUAL "License: LGPL version 3 or later")
    set(LICENSE_FILE "COPYING.LGPLv3")
elseif(LICENSE_STRING STREQUAL "License: GPL version 2 or later")
    set(LICENSE_FILE "COPYING.GPLv2")
elseif(LICENSE_STRING STREQUAL "License: GPL version 3 or later")
    set(LICENSE_FILE "COPYING.GPLv3")
elseif(LICENSE_STRING STREQUAL "License: nonfree and unredistributable")
    set(LICENSE_FILE "COPYING.NONFREE")
    file(WRITE "${SOURCE_PATH}/${LICENSE_FILE}" "${LICENSE_STRING}")
else()
    message(FATAL_ERROR "Failed to identify license (${LICENSE_STRING})")
endif()

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/${LICENSE_FILE}")
