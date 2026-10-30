# Cheeks: hands-on test script

**Who this is for:** a Claude session with computer use (it can see the screen, click and drag). Whoever built this could compile and run unit tests, but couldn't tap anything, so every result in here is new information.

**Your job:** run every test below in order and write down exactly what happens. **Don't change any code, even if you can see the fix.** A precise description of a bug is what's wanted. If something blocks a test, record it and move on to the next one.

**What to hand back:** `docs/COMPUTER_USE_RESULTS.md` in the format at the end of this file, with screenshots in `docs/test-results/`. Commit both to `master` when you're done, with the message `Add hands-on test results`, and push.

---

## Setup

Everything runs from the repo root, `/Users/nikhil/Cheeks`.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
# Build for the 13-inch iPad simulator
xcodebuild -project Cheeks.xcodeproj -scheme Cheeks \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -derivedDataPath build build 2>&1 | tail -1
# Expect: ** BUILD SUCCEEDED **

xcrun simctl boot "iPad Pro 13-inch (M5)" 2>/dev/null
xcrun simctl uninstall "iPad Pro 13-inch (M5)" com.nikhilpatel.cheeks 2>/dev/null   # start clean
xcrun simctl install "iPad Pro 13-inch (M5)" build/Build/Products/Debug-iphonesimulator/Cheeks.app

# Two test tracks, then drop them in the app's Documents folder, which it imports from at launch
tools/test-music/fetch.sh /tmp/cheeks-music
DATA=$(xcrun simctl get_app_container "iPad Pro 13-inch (M5)" com.nikhilpatel.cheeks data)
cp /tmp/cheeks-music/*.mp3 "$DATA/Documents/"

xcrun simctl launch "iPad Pro 13-inch (M5)" com.nikhilpatel.cheeks
```

**Seeing and touching the simulator:** Xcode 27 has no standalone Simulator.app on this Mac, so use the Claude simulator panel, or try `open -a Simulator` if it turns out to exist. To save a screenshot:

```sh
mkdir -p docs/test-results
xcrun simctl io "iPad Pro 13-inch (M5)" screenshot docs/test-results/NAME.png
```

Simulator screenshots may come out rotated 90°. That's only the framebuffer, not a bug.

**What can't be tested here, so don't report it as failed:** haptics (simulators have no Taptic Engine), how anything sounds to you (unless you can capture audio), and true multi-finger touch beyond what your tooling can do.

**If the app crashes:** note what you just did, get the newest report from `ls -t ~/Library/Logs/DiagnosticReports | grep -i cheeks | head -1`, copy it to `docs/test-results/`, relaunch, and carry on.

**Where things are on screen**, top to bottom:
- **Top bar:** `cheeks` logo, `BROWSE`, `REC`, a waveform icon (Recordings), `MASTER n` with a tempo in the middle, the clock, a gear (Settings).
- **Waveforms:** a thin overview, the big scrolling waveform for deck 1, a thin strip of beat blocks, the big waveform for deck 2, another overview.
- **Decks** on the left and right, with the **mixer** between them.
- **In each deck:** a black header (artwork, title, BPM, time); the tempo fader at the outer edge; the big jog wheel; a column of keys on the inner side (`BEAT SYNC`, `MASTER`, `BEAT JUMP`, `Q`, `SLIP`, `KEY`, `REV`, `−`/`+`, `KEY SYNC`); then `IN`/`OUT`/`RELOOP` and `‹ 4 ›`; a row of tabs (`CUE MEM LOOP ROLL SLICER JUMP STEMS FX SAMPLE`); and eight pads. Round `CUE` and `PLAY` buttons sit in the bottom outer corner.

---

## The tests

For each one, record PASS, FAIL or BLOCKED, what you actually saw, and any screenshot. Also note anything that merely **looks wrong** (clipped text, overlaps, misaligned parts, flicker, jank, slow response), even if the test passes. That kind of note is as valuable as a failure.

### A. Launch
1. **Launch:** the app opens without crashing. Watch the first second if you can: the jog rings should sweep on clockwise and the meters should run up and back down. Screenshot `a1-launch`.
2. **Import:** within about 30 seconds of launch, two tracks are in the library and analysed (BPM and key filled in). A small "Analysing…" note shows in the top bar meanwhile. Note how long it took.
3. **Clean log:** run `xcrun simctl spawn "iPad Pro 13-inch (M5)" log show --last 2m --predicate 'process == "Cheeks"' --style compact | grep -iE 'error|fault|assert' | head -30` and paste the output.

### B. Browser
1. Tap `BROWSE` if the browser isn't already showing. It should slide in, with the mixer moving to the right side and two compact decks above the list. Screenshot `b1-browser`.
2. **Rows:** each shows artwork or a coloured letter tile, a tiny waveform, title, artist, BPM, key, time, and `1` and `2` buttons. Are the tiny waveforms actually drawn?
3. **Sort:** tap the `TITLE`, `BPM`, `KEY` and `TIME` column headers. The rows should reorder with a smooth animation, and tapping again should flip the order with the arrow changing.
4. **Search:** type part of a title. The list should filter as you type, and the ✕ clears it. Search for nonsense and check that a "no results" view appears.
5. **Preview:** tap a row's tiny waveform. It should dim and show a stop icon with a line moving across it. Tap again to stop it. Try tapping a different row's while one is previewing.
6. **Context menu:** long-press a row. Check for Load on Deck 1, Load on Deck 2, Re-analyse and Delete.
7. **Swipe:** swipe a row right (loads on deck 1) and left (loads on deck 2).
8. **Drag:** press and drag a row onto a compact deck above the list. The deck should get a blue outline while hovering, and the track loads on drop.
9. **Playlists:** create a playlist with New Playlist, add a track through the context menu, and select the playlist in the sidebar.

### C. Loading and transport
1. Load track 1 on deck 1 and track 2 on deck 2 using the `1` and `2` buttons. Tap `BROWSE` to return to the decks. Screenshot `c1-loaded`. Check: titles and BPM in the headers, waveforms drawn in colour (blue, orange and white), and the time showing.
2. **Waveform load-in:** load a track again and watch for the waveform opening out from the centre line.
3. **Play:** press `PLAY` on deck 1. The waveform should scroll smoothly, the time counts down, the jog marker and LED comet turn, the meters move, and the icon becomes pause. Does the motion look smooth or does it stutter?
4. **Pause and cue:** press `PLAY` again to pause. Press `CUE` while playing: it should jump back to the cue point and stop.
5. **Refused load:** with deck 1 playing, open the browser and tap `1` on a track. It must refuse: the button shakes and a capsule at the top says deck 1 is playing. The playing track must not change.
6. **Needle search:** tap partway along a deck's thin overview. The position should jump there.

### D. Hot cues (`CUE` tab)
1. Tap an empty pad while playing. It should light in its colour, with its letter and a time. A coloured flag appears on the waveform and the overview.
2. Tap it again later in the track: the deck jumps back. With `Q` on, does it stay in time?
3. Tap `DEL` (it lights red), then tap a set cue. It should be removed, `DEL` turns off, and a capsule says "Deleted hot cue X" with **Undo**. Tap Undo and the cue comes back. Screenshot `d3-undo`.

### E. Loops
1. **Auto-loop:** tap the number between `‹` and `›`. A loop region should appear on the waveform, the jog ring shows an orange arc, the playhead repeats within the region, and the key becomes `EXIT`-lit.
2. `‹` and `›` should halve and double it, with the region resizing. `EXIT` should leave the loop, and `RELOOP` go back into it.
3. **Manual loop:** `IN`, then a moment later `OUT`.
4. **`LOOP` tab:** each pad sets that length, and tapping the lit pad exits.
5. **`ROLL` tab:** hold a pad for a couple of seconds and release. The playhead should jump ahead to where the track would have been.
6. **`SLICER` tab:** hold pad 3 and release; same return-in-time behaviour.
7. **`JUMP` tab, and `BEAT JUMP` in the key column:** each jumps by the shown number of beats. Tapping the middle number in the key column cycles 1, 2, 4, 8, 16, 32.

### F. Tempo and sync
1. **Tempo fader:** drag it. The percentage updates, the jog BPM updates and the waveform on that deck compresses or stretches. It should click to a stop at exactly 0.0. Double-tap to reset it. Tap the `±10` key to cycle the range through ±6, ±10, ±16, WIDE.
2. **Sync:** with both decks playing, tap `BEAT SYNC` on deck 2. Deck 2's BPM should match deck 1's within a moment, its tempo cap turns blue, and the **beat lines on the two waveforms line up vertically**. Screenshot `f2-synced`. In the strip between the waveforms, the marker should sit in the centre and be green.
3. Leave it synced for 2 minutes. Does the marker stay centred?
4. **Master:** tap `MASTER` on deck 2. The amber light should move to deck 2, deck 2's sync turns off, and the top bar shows `MASTER 2`.
5. **Key:** tap `+` a few times. The offset and the key on the jog change. `KEY SYNC` should set it to something compatible with the other deck.

### G. Jog wheel and waveform by hand
1. **Scratching while paused:** drag in a circle on the black record. The track position should follow your hand in both directions, and the platter should light slightly.
2. **Scratching while playing:** the same; when you let go it should spin back up to speed smoothly.
3. **Pitch bend:** while playing, drag around the metal outer ring. It should nudge without stopping.
4. **Waveform:** drag the big waveform left and right: it should scrub. Pinch to zoom if you can (both decks should zoom together). Double-tap to reset the zoom.

### H. Mixer
1. **Knobs:** drag each one up and down. The white pointer turns, a blue arc grows from the centre, and it should stick at the middle. Double-tap springs it back. Try `TRIM`, `HI`, `MID`, `LOW`, `FILTER`, `MASTER`, `CUE/MST`, `LEVEL`.
2. **Channel faders:** drag them. The channel's meter should keep moving (it's pre-fader), but the two master meters in the middle should drop as the fader comes down.
3. **Crossfader:** drag it fully each way. The master meters should drop when the playing deck is faded out, and it should stick at the centre. Double-tap to centre it.
4. **Cue and split:** `CUE` keys and `SPLIT` should light and unlight.
5. **Simultaneous controls:** if your tooling can do two touches at once, hold a pad while moving a fader. Report if not.

### I. Stems (`STEMS` tab) — the headline feature
1. First check the model is present: `ls Cheeks/Stems.mlpackage`. It isn't in git, so if it's missing, stop and report that, because the rest of this section would only test the fallback. Load a track and open the `STEMS` tab. Separation starts by itself on load. The control row should show a percentage counting up, then a green dot with **AI**. Note how long it takes for the 2:25 track and the 6:52 track. The simulator is CPU-only, so expect well under realtime but much slower than a real GPU; record the times anyway.
2. When ready, the waveform should change to four colours: pink vocals, green instruments, blue bass, amber drums. Both test tracks are instrumental, so little or no pink is expected. Screenshot `i2-stems`.
3. Tap `VOCAL`. The pad should dim immediately, and the pink layer on the waveform should drop to a ghost. Tap again to restore it.
4. Slide up and down on a stem pad: its level changes, a dark band shows it, and the waveform layer changes size or brightness. The stem should **not** end up muted by the slide.
5. Try `ACAPELLA`, `NO VOCAL`, `BEAT` and `ALL`, and each `SOLO` pad (soloing again restores what was on before).
6. **Relaunch check:** load the same track again, and after relaunching the app too. Stems should come back almost instantly from the cache. Note the time.
7. **While playing:** does the swap to stems happen without a gap or a jump in the waveform?
8. **Memory:** with both decks on stems, run `ps -o rss= -p $(pgrep -x Cheeks) | awk '{print $1/1024 " MB"}'`.

### J. Beat FX (`FX` tab)
1. Hold each of the 12 pads for a second while playing, and let go. The pad lights while held. Note anything that crashes, or any that seem to do nothing (watch the meters if you can't hear).
2. **Latch:** tap a pad quickly. It should stay lit until tapped again.
3. **Slide while holding:** slide up and down to change `DEPTH` (the bar in the control row moves), and left and right to change the beat value.
4. **Stem targeting:** with stems ready, turn off `V`, `I`, `B` and `D` one at a time. At least one always stays on.
5. **`BRAKE` and `BACKSPIN`:** the deck should slow to a stop and the play button should go back to its stopped state.

### K. Sampler (`SAMPLE` tab)
1. Tap all eight pads. Check that the master meters jump for each, including with no deck playing.

### L. Recording
1. Tap `REC` while a deck plays. It should widen, turn red and show a running timer.
2. After 20 seconds, tap it again: it asks for confirmation. Choose "Stop and save". A "Saving your mix…" capsule should appear, then "Saved Mix…". Screenshot `l2-saved`.
3. Open Recordings (waveform icon). The mix should be listed with its length and size. Play it. Rename it. Check that its tracklist shows if a track was on air for 10+ seconds.
4. Check the file exists: `ls -la "$(xcrun simctl get_app_container "iPad Pro 13-inch (M5)" com.nikhilpatel.cheeks data)/Documents/Recordings/"`.

### M. Settings and resilience
1. Open the gear. Switch **Waveform colours** to RGB and back, and check the waveforms change. Toggle the others. Check that the sheet looks like a normal iOS settings screen.
2. **Background:** with a deck playing, send the app to the background (`xcrun simctl launch "iPad Pro 13-inch (M5)" com.apple.Preferences`), wait 10 seconds, and return (`xcrun simctl launch "iPad Pro 13-inch (M5)" com.nikhilpatel.cheeks`). The state should be right, with no frozen visuals.
3. **Persistence:** set a hot cue, terminate (`xcrun simctl terminate "iPad Pro 13-inch (M5)" com.nikhilpatel.cheeks`), relaunch and reload the track. The cue should still be there.
4. **Crash-safe recording:** start a recording, wait 15 seconds, terminate as above, relaunch. A "Recovered…" capsule should appear and the mix should be in Recordings.

### N. Performance
Measure with the app in the foreground in each of these states, for 30 seconds each. Use `ps -o %cpu=,rss= -p $(pgrep -x Cheeks)` every 5 seconds and report the averages:
1. Idle, nothing loaded.
2. Two tracks loaded, paused. (This should be very low: it draws nothing when nothing changes.)
3. One deck playing.
4. Both decks playing and synced, with a tempo offset so the stretcher is running.
5. Both of those plus stems and an echo on.

Simulator numbers run on the Mac's GPU, so treat them as relative. The interesting question is how the states compare.

### O. First impressions
Finish by answering these honestly, as a person seeing this app for the first time. They're as useful as the bug list:
1. Does it look like $1000 pro software? Name the three things that most break the illusion, however small.
2. What felt slow, confusing or surprising to use?
3. Which control was hardest to find or hit?

---

## Results format

Write `docs/COMPUTER_USE_RESULTS.md` like this:

```markdown
# Hands-on results, <date>

Commit tested: <git rev-parse --short HEAD>
Tooling limits: <what you couldn't do, such as multi-touch or hearing audio>

## Summary
<PASS/FAIL/BLOCKED counts, then the 3 most important problems>

## Failures
### D3: Undo didn't restore the cue
- Steps: ...
- Expected: ...
- Actual: ...
- Screenshot: docs/test-results/d3-undo.png
- Crash report (if any): ...

## Looks wrong
- <where it is, what's wrong, screenshot>

## All results
| Test | Result | Notes |
|---|---|---|
| A1 | PASS | Launched in 2 s, ring sweep visible |
| ... | | |

## Timings and measurements
<import time, stem times, memory, the CPU table>

## First impressions
<section O>
```
