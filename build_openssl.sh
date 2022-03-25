#!/bin/bash

set -e

DIR="$(cd "$(dirname "$0")" && pwd)"

build_dir=${DIR}/build
install_dir=${DIR}/install
src=${DIR}/openssl

pushd $src
./Configure --prefix=$install_dir --openssldir=$install_dir '-Wl,-rpath,$(LIBRPATH)'
make -j $(nproc)
make install
popd
