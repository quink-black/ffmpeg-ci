#!/bin/bash

set -e

DIR="$(cd "$(dirname "$0")" && pwd)"

build_dir=${DIR}/build
install_dir=${DIR}/install
x264_src=${DIR}/x264

pushd $x264_src
./configure --enable-static --prefix=$install_dir
make -j $(nproc)
make install
popd
