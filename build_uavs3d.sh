#!/bin/bash

set -e

src=${DIR}/uavs3d

pushd $src

cmake -G Ninja \
    -DCMAKE_INSTALL_PREFIX=${install_dir} \
    -DCOMPILE_10BIT=ON \
    -B ${build_dir}/uavs3d
popd

ninja -C ${build_dir}/uavs3d install
