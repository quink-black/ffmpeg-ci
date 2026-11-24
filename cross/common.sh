#!/bin/bash

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$repo_root"
source "$repo_root/env.sh"

ffmpeg_src="$repo_root/../ffmpeg"
enable_opt=1
cross_inputs=()
jobs="${FFMPEG_CI_JOBS:-$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN || echo 1)}"

cross_error() {
    printf '%s: %s\n' "${0##*/}" "$1" >&2
    exit 1
}

cross_value() {
    if [ "$#" -lt 2 ] || [[ "$2" = --* ]]; then
        cross_error "$1 requires a value"
    fi
}

cross_bool() {
    case "$2" in
        0|1) ;;
        *) cross_error "$1 must be 0 or 1" ;;
    esac
}

cross_source_dir() {
    [ -f "$ffmpeg_src/configure" ] || cross_error "FFmpeg configure not found in $ffmpeg_src"
    ffmpeg_src="$(cd "$ffmpeg_src" && pwd -P)"
}

cross_configure() {
    mkdir -p "$ffmpeg_build"
    cd "$ffmpeg_build"

    local marker=.cross-config
    local key configured=0
    key="$({
        printf '%s\0' "$ffmpeg_src" "${CFLAGS:-}" "${CXXFLAGS:-}" \
            "${LDFLAGS:-}" "${PKG_CONFIG_PATH:-}" "$@"
        cksum < "$ffmpeg_src/configure"
        if [ "${#cross_inputs[@]}" -gt 0 ]; then
            cksum "${cross_inputs[@]}"
        fi
    } | cksum)"
    if [ -f "$marker" ] && [ -f config.h ] && [ -f ffbuild/config.mak ] &&
        [ "$(cat "$marker")" = "$key" ]; then
        printf 'Using FFmpeg configuration in %s\n' "$ffmpeg_build"
        return
    fi

    [ ! -f ffbuild/config.mak ] || configured=1
    rm -f "$marker"
    printf 'Configuring FFmpeg in %s\n' "$ffmpeg_build"
    "$ffmpeg_src/configure" "$@"
    if [ "$configured" -eq 1 ]; then
        make clean
    fi
    printf '%s\n' "$key" > "$marker"
}
