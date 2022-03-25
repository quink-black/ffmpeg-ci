#!/bin/bash

set +e

DIR="$(cd "$(dirname "$0")" && pwd)"
build_dir=${DIR}/build
install_dir=${DIR}/install
tarball=${DIR}/freetype*.tar.xz

mkdir -p $build_dir
pushd $build_dir

rm -Rf freetype-*
tar xvf $tarball

pushd freetype-*

./autogen.sh
./configure --prefix=$install_dir
make -j $(nproc)
make install

popd #freetype

popd #build
