#!/bin/zsh
# Runs the app's own walk round itself in one simulator, with a big library and nothing else touching it, and prints every
# freeze of 50 ms or more, with CPU and memory. See Cheeks/App/SelfTour.swift. Other work on the Mac shows up here too.
#   CONFIG=Release tools/self-tour.sh "iPhone 17" [number of tracks]
set -u
ROOT=${0:A:h:h}
SIM=${1:-"iPhone 17"}
TRACKS=${2:-2000}
CONFIG=${CONFIG:-Release}
LOG=${CHEEKS_PERF_LOG:-/tmp/cheeks-self-tour.log}
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd "$ROOT"
xcodebuild -project Cheeks.xcodeproj -scheme Cheeks -configuration $CONFIG -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath build build > /tmp/cheeks-tour-build.log 2>&1 \
  || { grep -E "error:|BUILD FAILED" /tmp/cheeks-tour-build.log | head -20; exit 1; }
xcrun simctl boot "$SIM" 2>/dev/null
xcrun simctl uninstall "$SIM" com.nikhilpatel.cheeks 2>/dev/null
xcrun simctl install "$SIM" build/Build/Products/$CONFIG-iphonesimulator/Cheeks.app
DATA=$(xcrun simctl get_app_container "$SIM" com.nikhilpatel.cheeks data)
mkdir -p "$DATA/Library/Application Support"
python3 -I tools/test-music/big_library.py "$DATA/Library/Application Support/library.json" "$TRACKS" > /dev/null
tools/test-music/fetch.sh /tmp/cheeks-music > /dev/null 2>&1
cp /tmp/cheeks-music/*.mp3 "$DATA/Documents/"
# Stems stay off unless asked for, as they'd swamp everything else.
if [ -n "${CHEEKS_PERF_STEMS:-}" ]; then
  xcrun simctl spawn "$SIM" defaults delete com.nikhilpatel.cheeks prepareStemsOnLoad 2>/dev/null
else
  xcrun simctl spawn "$SIM" defaults write com.nikhilpatel.cheeks prepareStemsOnLoad -bool NO
fi
# Twice, as the first launch after an install has shaders to build, and what matters most is the second one.
for run in first second; do
  rm -f "$LOG"
  SIMCTL_CHILD_CHEEKS_LAUNCH_LOG="$LOG" SIMCTL_CHILD_CHEEKS_SELF_TOUR=1 xcrun simctl launch --terminate-running-process "$SIM" com.nikhilpatel.cheeks > /dev/null
  for i in {1..120}; do
    sleep 1
    grep -qE "STEP:  (done|stopped)" "$LOG" 2>/dev/null && break
  done
  xcrun simctl terminate "$SIM" com.nikhilpatel.cheeks 2>/dev/null
  echo "=== $run launch, $CONFIG, $SIM, $TRACKS tracks"
  grep -E "STEP:|STALL:|PERF:|first screen|main thread free" "$LOG"
done
