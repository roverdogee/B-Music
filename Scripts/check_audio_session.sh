#!/bin/sh
set -eu
if [ "$#" -ne 1 ]; then
    echo "Usage: sh Scripts/check_audio_session.sh <booted-simulator-UUID>" >&2
    exit 1
fi
bmusic_device=$1
bmusic_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bmusic_check_dir=$(mktemp -d "${TMPDIR:-/tmp}/bmusic-session-check.XXXXXX")
trap 'rm -rf "$bmusic_check_dir"' EXIT
bmusic_sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator swiftc -parse-as-library \
    -target "$(uname -m)-apple-ios26.0-simulator" -sdk "$bmusic_sdk" \
    -module-cache-path "$bmusic_check_dir/module-cache" \
    "$bmusic_root/BMusic/BMusicAudioEngine.swift" \
    "$bmusic_root/BMusic/NativeAudioPlayer.swift" \
    "$bmusic_root/Tests/BMusicAudioSessionChecks.swift" \
    -o "$bmusic_check_dir/audio-session-check"
xcrun simctl spawn "$bmusic_device" "$bmusic_check_dir/audio-session-check"
