#!/bin/bash

set -e
set -x

if [ -z "${FFMPEG_BIN:-}" ]; then
    suffix="${MSYSTEM:+.exe}"
    if native_build="$(./cibuild.sh --print-build-dir)" &&
        [ -x "${native_build}/ffmpeg${suffix}" ] && [ -f "${native_build}/runtime.env" ]; then
        source "${native_build}/runtime.env"
        FFMPEG_BIN="${native_build}/ffmpeg${suffix}"
    else
        FFMPEG_BIN="build/ffmpeg/ffmpeg${suffix}"
    fi
fi
test_dir=build/test

mkdir -p "$test_dir"

decode_test() {
    ref_md5="$2"
    out_name="$(mktemp "${test_dir}/avs.XXXXXXXX")"
    "$FFMPEG_BIN" -hide_banner -vsync 0 -i "$1" -f md5 "${out_name}" -y
    result=$(cat "$out_name")
    result=${result#MD5=}
    if [ "$ref_md5" == "$result" ]; then
        echo "Decoding test: Success: $1"
        rm "$out_name"
    else
        echo "Decoding test: Error: $out_name md5 doesn't match $1, result $result vs reference $ref_md5"
        exit 1
    fi
}

for i in avs2stream/ES/*
do
    ref_md5="$(cat "${i}/md5.txt" |tr '[:upper:]' '[:lower:]')"
    decode_test "${i}/test.avs2" "$ref_md5"
done

for i in avs3stream/ES/*
do
    ref_md5="$(tail -1 "${i}/md5.txt" |awk '{print $NF}')"
    decode_test "${i}/test.avs3" "$ref_md5"
done

for i in avs3stream/TS/*
do
    ref_md5="$(tail -1 "${i}/md5.txt" |awk '{print $NF}')"
    decode_test "${i}/test.ts" "$ref_md5"
done
