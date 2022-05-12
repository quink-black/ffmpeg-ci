#!/bin/bash

set -e

src=${DIR}/uavs3d

pushd $src
git checkout ./
git apply ${DIR}/patch/uavs3d.patch

cmake -G Ninja \
    -DCMAKE_INSTALL_PREFIX=${install_dir} \
    -B ${build_dir}/uavs3d
popd

ninja -C ${build_dir}/uavs3d install
