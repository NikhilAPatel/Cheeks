#!/bin/zsh
# Builds the app's real audio engine as a Mac library, so the lab renders exactly what the app plays.
set -e
ROOT=${0:A:h:h:h}
OUT=${CHEEKS_AUTODJ_CACHE:-$HOME/Library/Caches/cheeks-autodj}
mkdir -p $OUT
clang++ -std=c++17 -stdlib=libc++ -O3 -shared -fPIC \
  -I$ROOT/Cheeks/DSP -I$ROOT/Cheeks/DSP/vendor \
  -framework Accelerate \
  $ROOT/Cheeks/DSP/Engine.cpp -o $OUT/libcheeksdsp.dylib
echo $OUT/libcheeksdsp.dylib
