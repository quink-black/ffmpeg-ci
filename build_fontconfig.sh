#!/bin/bash

set +e

if pkg-config --exists fontconfg-devel; then
    echo $(pkg-config --cflags fontconfg-devel)
    exit 0
fi

DIR="$(cd "$(dirname "$0")" && pwd)"
build_dir=${DIR}/build
install_dir=${DIR}/install
tarball=${DIR}/fontconfig*.tar.gz

mkdir -p $build_dir
pushd $build_dir

rm -Rf fontconfig-*
tar xvf $tarball

pushd fontconfig-*

./configure --prefix=$install_dir
make -j $(nproc)
make install

popd #fontconfig

popd #build
