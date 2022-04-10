#!/bin/bash

set -e

DIR="$(cd "$(dirname "$0")" && pwd)"

build_dir=${DIR}/build
install_dir=${DIR}/install
src=${DIR}/x265/source

pushd $src
cmake -G Ninja \
    -DCMAKE_INSTALL_PREFIX=${install_dir} \
    -DENABLE_SHARED=OFF \
    -B ${build_dir}/x265
popd

ninja -C ${build_dir}/x265 install
