#!/bin/bash

set -e

lsmash_src=${DIR}/l-smash

pushd $lsmash_src
./configure --enable-debug --prefix=$install_dir
make -j $(nproc)
make install
popd
