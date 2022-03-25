#!/bin/bash

set +e

DIR="$(cd "$(dirname "$0")" && pwd)"
build_dir=${DIR}/build
install_dir=${DIR}/install
nasm_src=${DIR}/nasm

if which nasm; then
    version=$(nasm -v |cut -f3 -d ' ')
    min_require="2.14.03"
    min=$(echo -e "${version}\n${min_require}" |sort -V |head -n1)
    if [ "$min" = "$min_require" ]; then
        echo "current nasm version $version larger or equal than $min_require, skip"
        exit 0
    else
        echo "current nasm version $version less than $min_require, build from source"
    fi
fi

pushd $nasm_src

./autogen.sh
./configure --prefix=$install_dir
make -j $(nproc)
make install

popd #nasm
