# Android Shaderc

Each ABI directory contains Shaderc's `shaderc_combined` static archive as
`libshaderc.a`. Both archives target Android API 24 and were built with
NDK 27.2.12479018 and `c++_static`. The public headers come from the same
release. The license texts for the bundled components are under `licenses/`.
The pkg-config files record the [Shaderc release](https://github.com/google/shaderc/releases).

To replace the archives, check out the matching upstream tag and run
`python3 utils/git-sync-deps` in that source tree to fetch its pinned
dependencies. Set `shaderc_src` to the checkout and `ANDROID_NDK` to the NDK.
Configure and build each ABI in a separate directory.

```bash
for abi in arm64-v8a armeabi-v7a; do
    out="build/shaderc-$abi"
    cmake -G Ninja -S "$shaderc_src" -B "$out" \
        --toolchain "$ANDROID_NDK/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI="$abi" -DANDROID_PLATFORM=android-24 -DANDROID_STL=c++_static \
        -DCMAKE_BUILD_TYPE=Release -DSHADERC_SKIP_TESTS=ON \
        -DSHADERC_SKIP_EXAMPLES=ON -DSHADERC_SKIP_COPYRIGHT_CHECK=ON
    cmake --build "$out" --target shaderc_combined
done
```

Use the NDK's `llvm-strip --strip-debug` on the resulting archives. Copy
`arm64-v8a` to `aarch64/` and `armeabi-v7a` to `armeabi-v7a/`. Update the
headers from `libshaderc/include/shaderc/`, the license texts, and both
pkg-config versions together.
