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
    set(OPTIONS "${OPTIONS} --extra-cxxflags=-I\"${CURRENT_INSTALLED_DIR}/include/opencv4\"")
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
    string(APPEND VCPKG_COMBINED_C_FLAGS_DEBUG " -O2")
    string(REGEX REPLACE "(^| )-RTC1( |$)" " " VCPKG_COMBINED_C_FLAGS_DEBUG "${VCPKG_COMBINED_C_FLAGS_DEBUG}")
    string(REGEX REPLACE "(^| )-Od( |$)" " " VCPKG_COMBINED_C_FLAGS_DEBUG "${VCPKG_COMBINED_C_FLAGS_DEBUG}")
    string(REGEX REPLACE "(^| )-Ob0( |$)" " " VCPKG_COMBINED_C_FLAGS_DEBUG "${VCPKG_COMBINED_C_FLAGS_DEBUG}")
endif()

string(APPEND VCPKG_COMBINED_C_FLAGS_DEBUG " -I \"${CURRENT_INSTALLED_DIR}/include\"")
string(APPEND VCPKG_COMBINED_C_FLAGS_RELEASE " -I \"${CURRENT_INSTALLED_DIR}/include\"")

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
if(NOT DEFINED VCPKG_BUILD_TYPE AND EXISTS "${CURRENT_PACKAGES_DIR}/debug/bin")
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
                message(STATUS "Debug ${_tool} not found in ${CURRENT_PACKAGES_DIR}/debug/bin")
            endif()
        endif()
    endforeach()
endif()

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