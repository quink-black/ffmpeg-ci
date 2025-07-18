export DIR=$PWD
export install_dir=$DIR/install
export build_dir=${DIR}/build

export PATH=${install_dir}/bin:$PATH
export meson_bin=${DIR}/meson/meson.py

export LD_LIBRARY_PATH="${install_dir}/lib:${install_dir}/lib64:${LD_LIBRARY_PATH}"
export PKG_CONFIG_PATH="${install_dir}/lib/pkgconfig:${install_dir}/lib64/pkgconfig:/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH"

if which clang++; then
    export CC=clang
    export CXX=clang++
else
    export CC=gcc
    export CXX=g++
fi

if which ccache; then
    export CMAKE_C_COMPILER_LAUNCHER="ccache"
    export CMAKE_CXX_COMPILER_LAUNCHER="ccache"
fi

export CFLAGS='-fPIC'
export CXXFLAGS='-fPIC'
export MACOSX_DEPLOYMENT_TARGET=11.0
