#!/bin/zsh
# Walks round the app in one simulator with a big library, and prints every freeze of 100 ms or more, with CPU and memory.
#   tools/perf-tour.sh "iPhone 17" [number of tracks]
# Other work on the Mac shows up here too, so compare runs rather than believing one.
set -u
ROOT=${0:A:h:h}
SIM=${1:-"iPhone 17"}
TRACKS=${2:-2000}
LOG=${CHEEKS_PERF_LOG:-/tmp/cheeks-perf-tour.log}
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd "$ROOT"
xcodebuild build-for-testing -project Cheeks.xcodeproj -scheme CheeksUI -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath build > /tmp/cheeks-perf-build.log 2>&1 \
  || { grep -E "error:|BUILD FAILED" /tmp/cheeks-perf-build.log | head -20; exit 1; }
xcrun simctl boot "$SIM" 2>/dev/null
xcrun simctl uninstall "$SIM" com.nikhilpatel.seguedj 2>/dev/null
xcrun simctl install "$SIM" build/Build/Products/Debug-iphonesimulator/Cheeks.app
DATA=$(xcrun simctl get_app_container "$SIM" com.nikhilpatel.seguedj data)
mkdir -p "$DATA/Library/Application Support"
python3 -I tools/test-music/big_library.py "$DATA/Library/Application Support/library.json" "$TRACKS"
# Two real tracks to load, imported by the app at launch. Stems stay off unless asked for, as they'd swamp everything else.
tools/test-music/fetch.sh /tmp/cheeks-music > /dev/null 2>&1
cp /tmp/cheeks-music/*.mp3 "$DATA/Documents/"
if [ -n "${CHEEKS_PERF_STEMS:-}" ]; then
  xcrun simctl spawn "$SIM" defaults delete com.nikhilpatel.seguedj prepareStemsOnLoad 2>/dev/null
else
  xcrun simctl spawn "$SIM" defaults write com.nikhilpatel.seguedj prepareStemsOnLoad -bool NO
fi
rm -f "$LOG"
TEST_RUNNER_CHEEKS_UI_PERF="$LOG" xcodebuild test-without-building -project Cheeks.xcodeproj -scheme CheeksUI -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath build \
  -only-testing:CheeksUITests/PerfTour > /tmp/cheeks-perf-test.log 2>&1
code=$?
grep -E "error:|\*\* TEST" /tmp/cheeks-perf-test.log | cut -c1-200 | tail -6
grep -E "STEP:|STALL:|PERF:" "$LOG"
exit $code
