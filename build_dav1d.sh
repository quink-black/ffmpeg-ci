#!/bin/bash

set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
build_dir=${DIR}/build
install_dir=${DIR}/install
dav1d_src=${DIR}/dav1d

mkdir -p $build_dir

pushd $dav1d_src

$meson_bin setup $build_dir/dav1d --buildtype release -Ddefault_library=static --prefix=$install_dir

popd # dav1d_src

ninja -C $build_dir/dav1d install
