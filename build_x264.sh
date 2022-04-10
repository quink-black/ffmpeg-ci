#!/bin/bash

set -e

x264_src=${DIR}/x264

pushd $x264_src
./configure --enable-static --prefix=$install_dir
make -j $(nproc)
make install
popd
