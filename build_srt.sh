#!/bin/bash

set -e

DIR="$(cd "$(dirname "$0")" && pwd)"

build_dir=${DIR}/build
install_dir=${DIR}/install
src=${DIR}/srt

pushd $src
cmake -G Ninja \
    -DENABLE_TESTING=OFF \
    -DENABLE_UNITTESTS=OFF \
    -DENABLE_HEAVY_LOGGING=ON \
    -DENABLE_STDCXX_SYNC=ON \
    -DCMAKE_INSTALL_PREFIX=${install_dir} \
    -DENABLE_SHARED=OFF \
    -B ${build_dir}/srt
popd

ninja -C ${build_dir}/srt install
