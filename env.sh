export DIR=$PWD
export install_dir=$DIR/install
export build_dir=${DIR}/build

export PATH=${install_dir}/bin:$PATH
export meson_bin=${DIR}/meson/meson.py

export LD_LIBRARY_PATH="${install_dir}/lib"
export PKG_CONFIG_PATH=${install_dir}/lib/pkgconfig:$PKG_CONFIG_PATH

export LD_LIBRARY_PATH="${install_dir}/lib64:${LD_LIBRARY_PATH}"
export PKG_CONFIG_PATH=${install_dir}/lib64/pkgconfig:$PKG_CONFIG_PATH

export LD_LIBRARY_PATH="${install_dir}/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}"
export PKG_CONFIG_PATH=${install_dir}/lib/x86_64-linux-gnu/pkgconfig:$PKG_CONFIG_PATH

export CFLAGS='-fPIC'
export CXXFLAGS='-fPIC'
