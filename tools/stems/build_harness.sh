#!/bin/sh
# Builds tools/stems/swift_eval against the app's own sources, for macOS. Writes to the cache folder.
set -e
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="$HOME/Library/Caches/cheeks-stems/harness"
mkdir -p "$out"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -O -swift-version 5 \
    -target arm64-apple-macos14.4 \
    -o "$out/swift_eval" \
    "$root"/Cheeks/Stems/*.swift \
    "$root"/Cheeks/Audio/AudioDecoder.swift \
    "$root"/Cheeks/Analysis/Biquad.swift \
    "$root"/tools/stems/swift_eval/main.swift
echo "$out/swift_eval"
