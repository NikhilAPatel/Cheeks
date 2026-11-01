#!/bin/zsh
# Builds tools/autodj/app_map against the app's own sources, for macOS. Writes to the lab's cache folder.
set -e
ROOT=${0:A:h:h:h}
OUT=${CHEEKS_AUTODJ_CACHE:-$HOME/Library/Caches/cheeks-autodj}
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -O -swift-version 5 -target arm64-apple-macos14.4 \
  -o $OUT/app_map \
  $ROOT/Cheeks/Analysis/TrackMap.swift $ROOT/Cheeks/Analysis/Biquad.swift $ROOT/Cheeks/Audio/AudioDecoder.swift $ROOT/Cheeks/Stems/*.swift \
  $ROOT/tools/autodj/app_map/main.swift
echo $OUT/app_map
