#!/bin/bash

set -e

DIR="$(cd "$(dirname "$0")" && pwd)"

build_dir=${DIR}/build
install_dir=${DIR}/install
lsmash_src=${DIR}/l-smash

pushd $lsmash_src
./configure --enable-debug --prefix=$install_dir
make -j $(nproc)
make install
popd
