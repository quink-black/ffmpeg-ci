#!/bin/bash

set -e

davs2_src=${DIR}/davs2

pushd $davs2_src/build/linux
./configure --prefix=$install_dir --enable-pic
make -j $(nproc)
make install
