export DIR=$PWD
export install_dir=$DIR/install
export build_dir=${DIR}/build

export PATH=${install_dir}/bin:$PATH
export meson_bin=${DIR}/meson/meson.py

export LD_LIBRARY_PATH="${install_dir}/lib:${install_dir}/lib64:${LD_LIBRARY_PATH}"
export PKG_CONFIG_PATH="${install_dir}/lib/pkgconfig:${install_dir}/lib64/pkgconfig:/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH"

export CC=cc
export CXX=c++

if which ccache >/dev/null 2>&1; then
    export CMAKE_C_COMPILER_LAUNCHER="ccache"
    export CMAKE_CXX_COMPILER_LAUNCHER="ccache"
    export CCACHE_BIN="ccache"
else
    unset CMAKE_C_COMPILER_LAUNCHER
    unset CMAKE_CXX_COMPILER_LAUNCHER
    export CCACHE_BIN=""
fi

export CFLAGS='-fPIC'
export CXXFLAGS='-fPIC'
export MACOSX_DEPLOYMENT_TARGET=11.0
