#!/bin/bash

set -e
set -x

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
samples_dir="$repo_root/tests/avs"

if [ -z "${FFMPEG_BIN:-}" ]; then
    suffix="${MSYSTEM:+.exe}"
    if native_build="$("$repo_root/cibuild.sh" --print-build-dir)" &&
        [ -x "${native_build}/ffmpeg${suffix}" ] && [ -f "${native_build}/runtime.env" ]; then
        source "${native_build}/runtime.env"
        FFMPEG_BIN="${native_build}/ffmpeg${suffix}"
    else
        FFMPEG_BIN="$repo_root/build/ffmpeg/ffmpeg${suffix}"
    fi
fi
test_dir="$repo_root/build/test"

mkdir -p "$test_dir"

decode_test() {
    local sample="$1" ref_md5="$2" out_name result
    shift 2
    out_name="$(mktemp "${test_dir}/avs.XXXXXXXX")"
    "$FFMPEG_BIN" -hide_banner "$@" -i "$sample" -fps_mode passthrough -f md5 "${out_name}" -y
    result=$(cat "$out_name")
    result=${result#MD5=}
    if [ "$ref_md5" == "$result" ]; then
        echo "Decoding test: Success: $sample"
        rm "$out_name"
    else
        echo "Decoding test: Error: $out_name md5 doesn't match $sample, result $result vs reference $ref_md5"
        exit 1
    fi
}

# Frame threading in libdavs2 can change the decoded MD5 between runs.
for i in "$samples_dir"/avs2stream/ES/*
do
    ref_md5="$(cat "${i}/md5.txt" |tr '[:upper:]' '[:lower:]')"
    decode_test "${i}/test.avs2" "$ref_md5" -threads:v 1
done

for i in "$samples_dir"/avs3stream/ES/*
do
    ref_md5="$(tail -1 "${i}/md5.txt" |awk '{print $NF}')"
    decode_test "${i}/test.avs3" "$ref_md5"
done

for i in "$samples_dir"/avs3stream/TS/*
do
    ref_md5="$(tail -1 "${i}/md5.txt" |awk '{print $NF}')"
    decode_test "${i}/test.ts" "$ref_md5"
done
