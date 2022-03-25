#!/bin/bash

set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
build_dir=${DIR}/build
install_dir=${DIR}/install
vmaf_src=${DIR}/vmaf

mkdir -p $build_dir

pushd $vmaf_src

pushd third_party/libsvm
make lib
popd

$meson_bin setup $build_dir/vmaf libvmaf --buildtype release -Ddefault_library=static -Denable_float=true --prefix=$install_dir

popd # vmaf_src

ninja -C $build_dir/vmaf install
