export DIR := ${PWD}
export install_dir := ${DIR}/install
export build_dir := ${DIR}/build

export PATH := ${install_dir}/bin:${PATH}
export meson_bin := ${DIR}/meson/meson.py

export LD_LIBRARY_PATH := "${install_dir}/lib:${install_dir}/lib64:${LD_LIBRARY_PATH}"
export PKG_CONFIG_PATH := "${install_dir}/lib/pkgconfig:${install_dir}/lib64/pkgconfig:${PKG_CONFIG_PATH}"

export CFLAGS := -fPIC
export CXXFLAGS := -fPIC
export CMAKE_BUILD_TYPE := RelWithDebInfo
export CMAKE_INSTALL_PREFIX := ${install_dir}

MAKEFLAGS := -j $(shell nproc)

CROSS_PREFIX := ""
HOST := ""

dav1d_src := ${DIR}/dav1d
dav1d_build := ${build_dir}/dav1d
.dav1d: ${dav1d_src}
	cd ${dav1d_src} && ${meson_bin} setup ${dav1d_build} \
	    --buildtype release \
	    -Ddefault_library=static \
	    --prefix=${install_dir} \
	    --libdir=${install_dir}/lib
	ninja -C ${dav1d_build} install
	touch $@

davs2_src := ${DIR}/davs2/build/linux
.davs2: ${davs2_src}
	cd ${davs2_src} && ./configure --prefix=${install_dir} --enable-pic && make install
	touch $@

freetype_version := freetype-2.12.1
.freetype: ${DIR}/${freetype_version}.tar.gz
	rm -Rf ${build_dir}/freetype-*
	tar xvf $< -C ${build_dir}
	cd ${build_dir}/${freetype_version} && ./autogen.sh && ./configure --prefix=${install_dir} && make install
	touch $@	

fontconfig_version := fontconfig-2.13.1
.fontconfig: ${DIR}/${fontconfig_version}.tar.gz .freetype
	rm -Rf ${build_dir}/fontconfig-*
	tar xvf $< -C ${build_dir}
	cd ${build_dir}/${fontconfig_version} && ./configure --prefix=${install_dir} && make install
	touch $@

xavs2_src := ${DIR}/xavs2

.xavs2: ${xavs2_src}
	cd ${xavs2_src}/build/linux && ./configure --prefix=${install_dir} --enable-static --enable-pic && make install ${MAKEFLAGS}
	touch $@

uavs3d_src := ${DIR}/uavs3d
uavs3d_build := ${build_dir}/uavs3d
.uavs3d: ${uavs3d_src}
	cd $< && cmake -B ${uavs3d_build} \
		-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE} \
		-DCMAKE_INSTALL_PREFIX=${CMAKE_INSTALL_PREFIX} && \
		cmake --build ${uavs3d_build} --target uavs3d && \
		cmake --install ${uavs3d_build}
	touch $@

uavs3e_src := ${DIR}/uavs3e
uavs3e_build := ${build_dir}/uavs3e

.uavs3e: ${uavs3e_src}
	cd $< && cmake -B ${uavs3e_build} -DCOMPILE_10BIT=ON \
		-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE} \
		-DCMAKE_INSTALL_PREFIX=${CMAKE_INSTALL_PREFIX} && \
		cmake --build ${uavs3e_build} && \
		cmake --install ${uavs3e_build}
	touch $@

vulkan_header_build := ${build_dir}/vulkan_header
.vulkan_header: ${DIR}/vulkan_header
	cd $< && cmake -B ${vulkan_header_build} \
		-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE} \
		-DCMAKE_INSTALL_PREFIX=${CMAKE_INSTALL_PREFIX} && \
		cmake --build ${vulkan_header_build} && \
		cmake --install ${vulkan_header_build}
	touch $@

vulkan_loader_build := ${build_dir}/vulkan_loader
.vulkan_loader: ${DIR}/vulkan_loader .vulkan_header
	cd $< && cmake -B ${vulkan_loader_build} \
		-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE} \
		-DCMAKE_INSTALL_PREFIX=${CMAKE_INSTALL_PREFIX} && \
		cmake --build ${vulkan_loader_build} && \
		cmake --install ${vulkan_loader_build}
	touch $@


third_party := .dav1d .uavs3d
#third_party += .xavs2 .uavs3e

CPU := $(shell uname -p)
ifneq ($(CPU),arm)
	third_party += .fontconfig .davs2
endif

clean_libs := ${third_party} .vulkan_header .vulkan_loader

all: ${third_party}

clean:
	rm -f ${clean_libs}

path ?= "../ffmpeg"
test ?= ""
skip_test_case ?= ""
enable_asan ?= 0
enable_opt ?= 0

ffmpeg: ${path} ${third_party}
	./build_ffmpeg.sh --path ${path} \
		${test} \
		--skip_test_case ${skip_test_case} \
		--enable_asan ${enable_asan} \
		--enable_opt ${enable_opt}
