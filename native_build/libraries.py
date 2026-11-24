from dataclasses import dataclass

from common import DARWIN


@dataclass(frozen=True)
class Dependency:
    source: str
    backend: str
    options: tuple = ()
    requires: tuple = ()
    module: str = ''
    feature: str = ''
    default: bool = False
    probes: tuple = ()


DEPENDENCIES = {
    'aom': Dependency('aom', 'cmake', ('-DENABLE_TESTS=OFF',),
                      module='aom', feature='libaom', default=True),
    'cms': Dependency('cms', 'meson', ('--buildtype=debug',),
                      module='lcms2', feature='lcms2', default=True,
                      probes=('libjpeg', 'libtiff-4')),
    'dav1d': Dependency('dav1d', 'meson', ('-Denable_tests=false',),
                        module='dav1d', feature='libdav1d', default=True),
    'davs2': Dependency('davs2', 'davs2', module='davs2', feature='libdavs2', default=True),
    'freetype': Dependency('freetype-2.12.1.tar.gz', 'cmake',
                           ('-DFT_DISABLE_HARFBUZZ=TRUE',), module='freetype2',
                           feature='libfreetype', probes=('zlib', 'libpng', 'bzip2', 'libbrotlidec')),
    'fontconfig': Dependency('fontconfig-2.13.1.tar.gz', 'configure',
                             ('--disable-docs', *(('--with-default-fonts=/System/Library/Fonts',
                                                  '--with-add-fonts=/Library/Fonts') if DARWIN else ())),
                             requires=('freetype',), module='fontconfig', feature='libfontconfig',
                             probes=('expat', 'libxml-2.0', 'uuid')),
    'libplacebo': Dependency('libplacebo', 'meson', ('--buildtype=debug',),
                             requires=('cms', 'vulkan_loader'), module='libplacebo',
                             feature='libplacebo', default=True, probes=(
                                 'shaderc', 'shaderc_combined', 'glslang', 'spirv', 'egl', 'gl',
                                 'libunwind', 'libxxhash', 'dovi', 'sdl2', 'sdl3', 'glfw3')),
    'lsmash': Dependency('l-smash', 'configure', ('--enable-debug',), module='liblsmash'),
    'srt': Dependency('srt', 'cmake', ('-DENABLE_TESTING=OFF', '-DENABLE_UNITTESTS=OFF',
                                      '-DENABLE_HEAVY_LOGGING=ON', '-DENABLE_STDCXX_SYNC=ON',
                                      '-DENABLE_SHARED=OFF', '-DENABLE_ENCRYPTION=OFF',
                                      '-DCMAKE_INSTALL_BINDIR=bin', '-DCMAKE_INSTALL_INCLUDEDIR=include'),
                      module='srt', feature='libsrt'),
    'uavs3d': Dependency('uavs3d', 'cmake-copy', ('-DCOMPILE_10BIT=ON', '-DBUILD_SHARED_LIBS=OFF'),
                         module='uavs3d', feature='libuavs3d', default=True),
    'uavs3e': Dependency('uavs3e', 'cmake-copy', ('-DCOMPILE_10BIT=ON',),
                         module='uavs3e', feature='libuavs3e'),
    'vmaf': Dependency('vmaf/libvmaf', 'meson', ('-Denable_float=true',),
                       module='libvmaf', feature='libvmaf'),
    'vulkan_header': Dependency('vulkan_header', 'cmake', default=True),
    'vulkan_loader': Dependency('vulkan_loader', 'cmake', ('-DENABLE_WERROR=OFF', '-DUSE_MASM=OFF'),
                                requires=('vulkan_header',), module='vulkan', default=True,
                                probes=('xcb', 'x11', 'xrandr', 'wayland-client')),
    'vvdec': Dependency('vvdec', 'cmake', ('-DBUILD_SHARED_LIBS=OFF',),
                        module='libvvdec', feature='libvvdec'),
    'vvenc': Dependency('vvenc', 'cmake', ('-DBUILD_SHARED_LIBS=OFF',
                                          '-DVVENC_ENABLE_LINK_TIME_OPT=OFF',
                                          '-DVVENC_ENABLE_WERROR=OFF'),
                        module='libvvenc', feature='libvvenc', default=True),
    'x264': Dependency('x264', 'configure', ('--enable-static', '--enable-pic', '--disable-avs',
                                            '--disable-lavf', '--disable-ffms', '--disable-gpac'),
                       module='x264', feature='libx264', default=True),
    'x265': Dependency('x265/source', 'x265', module='x265', feature='libx265', default=True),
    'xavs2': Dependency('xavs2', 'davs2', ('--enable-static',),
                        module='xavs2', feature='libxavs2'),
    'zimg': Dependency('zimg', 'autogen', ('--enable-static', '--disable-shared'),
                       module='zimg', feature='libzimg'),
}
