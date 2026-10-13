#!/bin/sh
set -eu
bmusic_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bmusic_check_dir=$(mktemp -d "${TMPDIR:-/tmp}/bmusic-audio-check.XXXXXX")
trap 'rm -rf "$bmusic_check_dir"' EXIT
swiftc -parse-as-library -target "$(uname -m)-apple-macos15.0" -module-cache-path "$bmusic_check_dir/module-cache" \
    "$bmusic_root/BMusic/BMusicAudioEngine.swift" \
    "$bmusic_root/Tests/BMusicAudioEngineChecks.swift" \
    -o "$bmusic_check_dir/audio-check"
"$bmusic_check_dir/audio-check"
