#!/bin/zsh
# Runs the UI tests: the real app driven by real touch events in a simulator.
#   tools/ui-tests.sh "iPhone Duo" [-only-testing:CheeksUITests/SomeTests/testSomething]
# Screenshots land in $CHEEKS_UI_SHOTS (default /tmp/cheeks-ui-shots). One run per simulator at a time.
set -u
ROOT=${0:A:h:h}
SIM=${1:-"iPhone Duo"}
shift 2>/dev/null
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SHOTS=${CHEEKS_UI_SHOTS:-/tmp/cheeks-ui-shots}
mkdir -p "$SHOTS"
cd "$ROOT"
xcodebuild build-for-testing -project Cheeks.xcodeproj -scheme CheeksUI -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath build > /tmp/cheeks-ui-build.log 2>&1 \
  || { grep -E "error:|BUILD FAILED" /tmp/cheeks-ui-build.log | head -20; exit 1; }
xcrun simctl boot "$SIM" 2>/dev/null
xcrun simctl install "$SIM" build/Build/Products/Debug-iphonesimulator/Cheeks.app
# Two tracks for the tests to load, imported by the app at launch if it doesn't have them yet.
tools/test-music/fetch.sh /tmp/cheeks-music > /dev/null 2>&1
DATA=$(xcrun simctl get_app_container "$SIM" com.nikhilpatel.seguedj data)
if [[ -z "$(ls -A "$DATA/Documents/Music" 2>/dev/null)" ]]; then cp /tmp/cheeks-music/*.mp3 "$DATA/Documents/"; fi
# A simulator that can't launch anything hangs a test for good, so no test gets longer than 10 minutes.
TEST_RUNNER_CHEEKS_UI_SHOTS="$SHOTS" xcodebuild test-without-building -project Cheeks.xcodeproj -scheme CheeksUI -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath build -test-timeouts-enabled YES -default-test-execution-time-allowance 600 -maximum-test-execution-time-allowance 600 "$@" > /tmp/cheeks-ui-test.log 2>&1
grep -E "UITEST:|error:|Test Case.*(passed|failed)|Executed [0-9]+ test|\*\* TEST" /tmp/cheeks-ui-test.log | cut -c1-240
grep -q "\*\* TEST EXECUTE SUCCEEDED \*\*\|\*\* TEST SUCCEEDED \*\*" /tmp/cheeks-ui-test.log
