#!/bin/bash

set -e

x264_src=${DIR}/x264

pushd $x264_src
./configure \
    --prefix=$install_dir \
    --enable-static \
    --enable-pic \
    --cross-prefix=$CROSS_PREFIX \
    --host=$HOST \
    --disable-avs \
    --disable-lavf \
    --disable-ffms \
    --disable-gpac \

make -j $(nproc)
make install
popd
