#!/bin/bash

set -e

src=${DIR}/zimg

pushd $src
./autogen.sh
./configure \
    --prefix=$install_dir \
    --enable-static \
    --host=$HOST \

make -j $(nproc)
make install
popd
