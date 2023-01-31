#!/bin/bash

set -e

src=${DIR}/vvdec

pushd $src
cmake -G Ninja \
    -DCMAKE_INSTALL_PREFIX=${install_dir} \
    -DBUILD_SHARED_LIBS=OFF \
    -B ${build_dir}/vvdec
popd

ninja -C ${build_dir}/vvdec install
