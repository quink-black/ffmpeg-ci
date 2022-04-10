#!/bin/bash

set -e

src=${DIR}/openssl

pushd $src
./Configure --prefix=$install_dir --openssldir=$install_dir '-Wl,-rpath,$(LIBRPATH)'
make -j $(nproc)
make install
popd
