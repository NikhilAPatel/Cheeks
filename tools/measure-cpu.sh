#!/bin/zsh
# Measures the app's CPU in each state on one simulator, pinned to its own process, since another
# simulator's copy of the app has the same name. Simulator numbers are relative, and GPU work
# isn't counted. Stems are left off so they don't swamp the numbers, then put back.
#   tools/measure-cpu.sh "iPhone Duo"
set -u
ROOT=${0:A:h:h}
SIM=${1:-"iPhone Duo"}
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
STATE=/tmp/cheeks-measure-state
UDID=$(xcrun simctl list devices | grep -F "$SIM (" | grep -oE '[0-9A-F-]{36}' | head -1)
rm -f "$STATE"
xcrun simctl spawn "$UDID" defaults write com.nikhilpatel.cheeks prepareStemsOnLoad -bool NO
TEST_RUNNER_CHEEKS_UI_MEASURE="$STATE" "$ROOT/tools/ui-tests.sh" "$SIM" -only-testing:CheeksUITests/MeasureStates > /tmp/cheeks-measure-test.log 2>&1 &
TEST=$!
LAST=""
SAMPLES=()
report() { [ ${#SAMPLES[@]} -gt 0 ] && printf '%-34s %s\n' "$LAST" "$(printf '%s\n' "${SAMPLES[@]}" | awk '{s+=$1; if($1>m)m=$1} END {printf "avg %.1f%%  max %.1f%%  (%d samples)", s/NR, m, NR}')"; }
while kill -0 $TEST 2>/dev/null; do
  sleep 5
  [ -f "$STATE" ] || continue
  NOW=$(cat "$STATE")
  if [ "$NOW" != "$LAST" ]; then report; LAST=$NOW; SAMPLES=(); SKIP=2; fi
  PID=$(xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | awk '/UIKitApplication:com\.nikhilpatel\.cheeks\[/{print $1}' | head -1)
  [ -n "$PID" ] && [ "$PID" != "-" ] || continue
  # A short window, because `ps` alone reports an average over the process's whole life.
  V=$(top -l 2 -s 3 -pid "$PID" -stats cpu 2>/dev/null | grep -E '^[0-9]+\.[0-9]+' | tail -1)
  if [ "$SKIP" -gt 0 ]; then SKIP=$((SKIP - 1)); elif [ -n "$V" ]; then SAMPLES+=("$V"); fi
done
report
xcrun simctl spawn "$UDID" defaults delete com.nikhilpatel.cheeks prepareStemsOnLoad 2>/dev/null
tail -3 /tmp/cheeks-measure-test.log | cut -c1-120
