#!/bin/zsh
# Builds tools/autodj/app_set against the app's own sources and the engine library from build_engine.sh, for macOS.
set -e
ROOT=${0:A:h:h:h}
OUT=${CHEEKS_AUTODJ_CACHE:-$HOME/Library/Caches/cheeks-autodj}
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -O -swift-version 5 -target arm64-apple-macos14.4 \
  -import-objc-header $ROOT/Cheeks/DSP/CheeksDSP.h -L$OUT -lcheeksdsp -Xlinker -rpath -Xlinker $OUT \
  -o $OUT/app_set \
  $ROOT/Cheeks/AutoDJ/Planner.swift $ROOT/Cheeks/AutoDJ/TransitionScore.swift $ROOT/Cheeks/Analysis/TrackMap.swift $ROOT/Cheeks/Analysis/Biquad.swift \
  $ROOT/Cheeks/Audio/AudioDecoder.swift $ROOT/Cheeks/Audio/DeckRenderer.swift $ROOT/Cheeks/Stems/*.swift $ROOT/tools/autodj/app_set/main.swift
echo $OUT/app_set
