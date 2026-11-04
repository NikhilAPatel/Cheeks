# Cheeks: hands-on task

**Who this is for:** a Claude session with computer use (it can see the screen, click and drag). This is the only document you need.

**Your job:** set up as below, then run **the retest**, **since the panels changed**, **the first-time user** and **pressing harder**, and answer **Part 3**.

**Rules:**
- **Don't change any code**, even if you can see the fix. A precise description is what's wanted.
- Record every test as PASS, FAIL or BLOCKED, based on what you actually saw. If you couldn't check it, it's BLOCKED, and say why.
- If something's blocked or the app crashes, record it and carry on. Get the crash report with `ls -t ~/Library/Logs/DiagnosticReports | grep -i cheeks | head -1` and copy it to `docs/test-results-13/`.
- Also note anything that merely looks wrong, even if the test passes.
- The sentence after each test is what the last test found. It's there so you can tell whether it changed, not to tell you what to see.

**What to hand back:** `docs/COMPUTER_USE_RESULTS_13.md` in the format at the end, with screenshots in `docs/test-results-13/`. Commit only those to `master`, with the message `Add hands-on test results, part 13`. **Don't push.**

**Other sessions:** before you start, check nobody else is running tests on your simulator. `tools/ui-tests.sh` reinstalls the app and ended the last run partway through.

---

## Setup

Everything runs from `/Users/nikhil/Cheeks`, on the `master` branch. First check you have the right code: `git log --oneline -1 -- docs/COMPUTER_USE_TASK.md` should print a commit. If it doesn't, stop and tell the owner.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM="iPhone Duo"
xcodebuild -project Cheeks.xcodeproj -scheme Cheeks -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath build build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
# Expect: ** BUILD SUCCEEDED **

xcrun simctl boot "$SIM" 2>/dev/null
xcrun simctl uninstall "$SIM" com.nikhilpatel.seguedj 2>/dev/null   # start clean
xcrun simctl install "$SIM" build/Build/Products/Debug-iphonesimulator/Cheeks.app

# Two test tracks, dropped where the app imports from at launch
tools/test-music/fetch.sh /tmp/cheeks-music
DATA=$(xcrun simctl get_app_container "$SIM" com.nikhilpatel.seguedj data)
cp /tmp/cheeks-music/*.mp3 "$DATA/Documents/"

xcrun simctl launch "$SIM" com.nikhilpatel.seguedj
mkdir -p docs/test-results-13
```

**The small iPhone:** use `iPhone SE Cheeks` (59B64076-E0E9-491A-AA6F-A82A60C3D2D2, iOS 27.2), which the owner's given the touch tool access to. It needs a fresh install. Never use `iPhone SE (3rd generation)`: by name that's another project's simulator.

**Things the last run learned about this setup:**
- **Use the iPhone Duo, unfolded (951×669 pt).** The simulator tool can report a 678×466 space, but taps land in 951×669. Don't reboot it: that folds it, and only Device Hub can open it again.
- **Tap length:** default taps last about 10 ms, and system switches ignore them. Use a 0.2 s press on those. Taps sent while a sheet is closing get lost.
- **Measure the right process.** Other simulators can be running their own `Cheeks`, so never use `pgrep -x Cheeks`. Get this simulator's with:
  ```sh
  PID=$(xcrun simctl spawn "$SIM" launchctl list | awk '/UIKitApplication:com\.nikhilpatel\.seguedj\[/{print $1}' | head -1)
  ```
  The PID changes every time the app restarts, so get it again after one. `ps` reports an average over the process's whole life, so measure CPU with `top -l 7 -s 5 -pid $PID -stats cpu`, and ignore the first line of numbers.
- **Logs:** to see real problems, filter on the level, not on words, because `grep fault` also matches "Default":
  ```sh
  xcrun simctl spawn "$SIM" log show --last 5m --predicate 'process == "Cheeks" AND (messageType == error OR messageType == fault)' --style compact
  ```
- **Screenshots:** `xcrun simctl io "$SIM" screenshot --display=primary-1 docs/test-results-13/NAME.png` for the inner screen. Please downscale them to about 1600 px wide before committing, to keep the repo small.
- **Reading the meters from video:** crop widths must be even. An odd width gets rounded by ffmpeg on 4:2:0 video, which shears every frame, and round 6's first figures were wrong because of it. Run a control that's known to be red before believing a 0%.
- **Check a reload really happened:** `playCount` in `library.json` goes up by one each time. A very busy Mac can take over 1 s to open the browser, so a load key tap sent too soon lands on the old layout. Allow about 1.5 s after `BROWSE`, and at least 5 s after a load key before seeking.
- **Load average is unreliable on this Mac:** it read 40 to 940 while the busiest processes added up to a few cores. Go by what the processes use.
- **Stopping a video:** `simctl io recordVideo` stops on SIGINT, and a background job in a non-interactive shell ignores that unless you restore it. Never send SIGTERM: last round that left the Duo's render server recording with nothing attached, writing about 118 MB a minute, and only a shutdown clears it, which folds the Duo.
- **Your touches aren't a UI test's.** A press along the top of the screen set off iOS's scroll-to-top for your tool and not for XCUITest, so a UI test passing doesn't settle anything near the screen's edges.
- **Can't be tested here, so don't report as failed:** haptics, how anything sounds, and the headphone output. List them under Tooling limits.

**Where things are:**
- **Top bar:** `SEGUE DJ`, `BROWSE`, `REC`, a waveform icon (Recordings), `MASTER n` and the tempo in the middle, then messages, the clock, `?` and the gear (Settings).
- **Waveforms:** overview, deck 1, a strip of beat blocks, deck 2, overview.
- **Decks** left and right with the **mixer** between them. Each deck has a header, a tempo fader at the outer edge, the jog, a column of keys (`BEAT SYNC`, `MASTER`, `BEAT JUMP`, `Q`, `SLIP`, `KEY`, `REV`, `−`/`+`, `KEY SYNC`), a row of controls for the current pad page, the tabs (`CUE MEM LOOP ROLL SLICER JUMP STEMS FX SAMPLE`) and eight pads. Round `CUE` and `PLAY` are in the bottom outer corner.

Load one track on each deck through `BROWSE` and the `1` and `2` keys, then close the browser. Each load starts splitting stems in the background, which uses a lot of CPU for a minute or two. Let that finish before anything that measures.

---

## The retest
To see what these were, look in `docs/COMPUTER_USE_RESULTS_12.md`, which ends with what was done about them.

**Reading the library:** `library.json` is in the app's data folder at `Library/Application Support/`. It's written about half a second after a change.

**Other sessions:** the other session may be building at low priority on `iPad Air 13-inch (M4)`, and it'll hold off if you ask before measuring. Other projects' jobs may be running as well, so say what was running beside anything you measure. Check which app's in the simulator's foreground before relying on a tap.

**The tracks:** copy in the three club tracks as well as the usual two, then relaunch. Splitting stems runs on the CPU in the simulator, so allow a few minutes a track, and wait for each deck's stems before pressing `AUTO`.

```sh
cp ~/Library/Caches/cheeks-autodj/music/jam1280420.mp3 ~/Library/Caches/cheeks-autodj/music/jam1072904.mp3 ~/Library/Caches/cheeks-autodj/music/jam1197771.mp3 "$DATA/Documents/"
```

`jam1197771` is Skylander (125), `jam1072904` is Gepzene (128) and `jam1280420` is Houston (126). The `AUTO` key is under the `FILTER` key on the mixer, and `MIX` and `NEXT` are in the browser's toolbar. The rules for taking over are in the table under **In the app** in `docs/AUTO_DJ.md`.

**A bass swap has a beat of silence in it on purpose,** just before the new track lands: about 0.45 s under -50 dB on a recording. That isn't a hole. Anywhere else, it is.

**The disk:** while the Duo's stuck recorder is running it writes up to about 650 MB a minute with the screen moving. Keep an eye on free disk and stop at 40 GB, as before. If the Duo hasn't been restarted, do what moves a lot on the small iPhone, and say which.

### FA. Blocked last time
Only if the Duo's been restarted and opened again, which clears its stuck recorder. If not, say BLOCKED and carry on.
1. **The browser on video on the Duo.** With 2,000 tracks (before launching: `python3 tools/test-music/big_library.py "$DATA/Library/Application Support/library.json" 2000`) and both decks playing, open and close it ten times. Worst gap between changed frames, and how many? *Round 10, by the freeze log only: nothing of 100 ms or more.*
2. **The logo, frame by frame,** on the Duo: it shouldn't double or jump at the handover.
3. **The launch sweep,** five launches on the Duo: the meters should run up and back once as the logo lifts.

### FB. What failed last time
1. **N2: a press just after closing the browser.** With the browser open, `BROWSE` and then `PLAY` as your very next call, on each deck, at least 5 times each. It should start the deck every time, or at worst do nothing, and it should never set a cue. Then the same with a pad, and straight after opening the browser with a row's `1`. A mixer key (`AUTO`) pressed in the first 0.45 s should do nothing, as the mixer takes no touches while it moves, and should work straight after: say if that's a nuisance. My test can't press during the slide with a real touch, so this result is the one that matters. *Last time: a hot cue, 4 of 5.*
2. **Does the slide still look right?** The decks now slide with UIKit and the mixer with SwiftUI. On video where you can, frame by frame: they should look like one thing moving, with no gap opening between them, no jump at either end and no flash, both ways, and pressing `BROWSE` twice quickly should turn round smoothly.
3. **N3: `AUTO` running out.** A track with under a minute left, a track with no stems yet on the other deck, then `AUTO`. It should say the next one starts if this one ends first, and when it ends, the next should start and be heard, with no gap you could call silence on a recording. Try it with the waiting deck's fader down and the crossfader away from it. Then:
   - Stems finishing with a few seconds left.
   - Stems ready, with about 5 s left: "No clean way in from here. Deck 2 starts when this one ends.", and `AUTO…` until it does.
   - `AUTO` again during either wait should call it off, and the next track shouldn't start.
   - Starting the waiting deck yourself during the wait.
   - A track that fades out long before its end.
   *Last time: silence with the next track ready, 2 of 2.*
4. **N1: long messages on the Duo.** "Exhilarate's file is missing…", "FX pads slide…", `RELOOP` with no loop, "Auto DJ stopped: deck 2's loop was changed…": each whole, on two lines if it needs them. Short ones should look as they did. `UNDO` and the thumbs should still work from the first frame, and should still line up with their keys on a two-line message. *Last time: cut from about 60 characters.*

### FC. What looked wrong last time
1. **`BEAT SYNC` and bars.** A track playing, `BEAT SYNC` on a stopped deck, then `PLAY`, at least 5 times at different moments with `CUE` between. The two counters should be on the same beat of the bar: CHORUS 39.1 with INTRO 4.1, say. Say what it does with a cue set on a downbeat, and from the very start of a track. `SYNC` pressed with both decks playing should only move it to the nearest beat. *Last time: bars apart, 3 of 3.*
2. **`NEXT` and `MIX`:** what's on a deck, or has played for 10 s or more since you opened the app, should come last. *Last time: the track just faded out came first.*
3. **`RELOOP` after a Loop build,** stopped by `EXIT` and after one that finished: it should say there's no loop to go back to. One you're still in, by pressing a size key, should stay. *Last time: back about 1:35, to the score's loop.*
4. **"starting":** the key should count down and say "starting" as it reaches nothing, with knobs starting to move about then. *Last time: 4 to 6 s early.*
5. **After stems finish while `AUTO` waits:** "The stems are ready. Auto DJ is choosing a move." with `AUTO…`.
6. **A lit FX pad:** a slide of 6 to 8 pt should keep it lit, a plain tap should still turn it off, and so should a 0.2 s press. *Last time: 8 pt turned it off.*
7. **The jog on a busy cover,** like Houston's: can you read the small text now?
8. **The notes** for `AUTO`, `BEAT BLOCKS`, `BEAT SYNC`, `BEAT JUMP`, `CUE` and `WAVEFORM`: true, as far as you can try them?
9. **Section names.** They come from the stems now, once a track's split. For each track you use, write down what they read in order, with roughly where they change, and say whether they change on the screen when the stems finish, as they should. `UP` should be the last few bars before a `CHORUS`. You can't check them by ear, so just list them, and say what looks unlikely.
10. **`BROWSE` doing nothing:** two presses did, once, with stems splitting on both decks. Try for it again: a dozen presses with stems splitting.
11. **Fault-level log lines:** count them after a browser open and close, as the slide's changed. *Last time: 22 from `AnimationKit`, about 'bounds' and 'position'.*

## Since the panels changed
The decks and the browser slide differently now, and the mixer takes no touches while it moves. So run these from **Part 1** on the Duo: **A1, A2, A3, B1, B3, B4, C1, C2, C3, C5, C6, D2, D3, D4** and **D11**, and from **Part 2**, **G, H** and **I**. Also `?` over everything on the mixer. The rest passed last round and hasn't changed.

## The first-time user
Forget everything above. Uninstall, install, and open the app as someone who's never seen it and has some music in Files. Stay away from the repo's docs and code, and say what you can't un-know.

Last time this got 13 minutes, and never reached `MIX` properly. So **give it the full 45 minutes, and start from what it missed:** `MIX`, the pad pages, FX, stems, `REC`, settings and playlists, after a quick mix by hand. On the Duo if it's been restarted, and on the small iPhone on its side if not.

1. Every moment you weren't sure what to do, what you tried first, and how long each stage took. Screenshot each, as `fu-*`.
2. **Use `?` as you go.** What's still a mystery after it? Which note was wrong, or didn't help?

### Pressing harder
**A long run.** 15 minutes, with `MIX` and `AUTO` running, and taking over as many ways as you can, this time including pressing things just as a panel slides, and `AUTO` late in a track. A recording running throughout, so you can check for gaps, and music on throughout. Afterwards the decks should always be usable, with nothing left silent, looping or filtered that the screen doesn't show. Crashes, dropouts, or a stop you can't explain? On the small iPhone if the Duo hasn't been restarted.

---

## Part 1: was it fixed?

### A. The three failures
1. **Undo (the top priority).** Set a hot cue with an empty pad on the `CUE` tab. Tap `DEL`, then the cue. The capsule offers an `UNDO` key. Tap it. The cue should come back and the capsule should go. Try it with a default tap and a 0.2 s press, with the deck paused and playing. Screenshot `a1-undo`. *Last time: five taps did nothing. The control has been rebuilt, and it couldn't be reproduced with another touch tool, so this result is the one that matters.* Report exactly which attempts worked.
2. **Refused load.** With deck 1 playing, open the browser and tap `1` on the other track. It must not load. The key should shake, and a capsule should say deck 1 is playing, with a hand icon rather than a green tick. Record a short video if you can, to catch the shake. Swiping the row shows a `Deck 1` action, and tapping that should say the same. Screenshot `a2-refused`. *Last time: no shake and no message on a tap, and a green tick on a swipe.*
3. **CPU.** Measure each state for 30 s, after 10 s of settling, on the pinned process. Stems must have finished first. *Last time: 4.5%, 5.4%, 10.6%, 20.2% and 20.4%, beside the stuck recorder.*
   - Idle, nothing loaded (terminate and relaunch for this one, then wait 30 s, as launching takes a while to settle)
   - Two tracks loaded, paused
   - One deck playing
   - Both playing and synced, with a tempo offset
   - Both of those, plus stems and an echo

### B. Meters and readouts
1. **Fake meter movement.** Both decks stopped, nothing playing. Open and close the browser four times, recording a video. The master meters must not move at all. Screenshot `b1-meters`. *Last time: they ran through red and back each time.*
2. **Launch sweep.** Terminate and relaunch. The meters should still run up and back once, in the first second or so.
3. **Capsule.** Trigger a capsule (the refused load is a good one). It must sit to the right of the `MASTER` readout, with the whole number readable. *Last time: it covered the number.*
4. **Sync marker.** Sync both decks, then sample the marker in the strip between the waveforms 11 times over 2 minutes. It should be centred and green in all of them. Screenshot `b4-marker`. *Last time: 3 of 11 were amber.*
5. **Jog readout.** Load a track and close the browser straight away, without waiting. Once it's loaded, the jog must show the tempo, not `NO TRACK`.
6. **Header BPM.** Move a tempo fader, then sync the other deck. On each deck, the BPM in the header and on the jog must match. Tap the header's BPM: the menu's title should give the track's own speed. Screenshot `b6-bpm`. *Last time: the header said 170.59 and the jog 185.16.*

### C. Layout
1. **Fader caps.** Crop a full-resolution screenshot around the crossfader and a tempo fader at zero. Measure how far the cap's index line is from the centre tick and the green LED. Screenshot `c1-caps`. *Last time: about 6 pt off.*
2. **Crossfader centre.** Drag the crossfader slowly through the middle. It should catch at the centre within about 3 pt each way. *Last time: 2 pt stayed, and 3 pt left.*
3. **Keyboard.** Open the browser and tap search. The mixer must stay exactly where it was, and the search field must stay visible. Screenshot `c3-keyboard`. *Last time: the mixer spilled onto the waveforms.*
4. **Stop recording.** Tap `REC`, wait, tap it again. An alert should offer both **Keep recording** and **Stop and save**. Try both. Screenshot `c4-alert`. *Last time: a popover with a misplaced arrow and no Keep recording.*
5. **Bottom of the screen.** The empty strip along the bottom should be gone, with the controls using that space. **Press everything near the bottom edge:** `PLAY`, `CUE`, the bottom row of pads, the crossfader. Does each register first time? Does anything trigger a system gesture? Screenshot `c5-bottom`.
6. **Top of the screen.** Press `BROWSE`, `REC` and the gear the same way.
7. **Titles.** In the browser, "Severe Tire Damage" should show more of its title than before, and the compact decks should use two lines. Screenshot `c7-titles`.
8. **Bar counter.** Set a loop with the counter beside the playhead. The loop's line shouldn't cut through the text.
9. **Tabs.** All nine labels should be the same size, and `SAMPLE` shouldn't crowd `DEL`.

### D. Feedback
1. **`SOLO`.** On `STEMS`, tap a `SOLO` pad. It should stay lit while soloed. Tap again to restore. Screenshot `d1-solo`.
2. **Pad flash.** Record a video while tapping pads quickly. Each should flash white and settle. A held slicer pad should be clearly brighter than the others.
3. **Sampler.** A quick tap on a sampler pad should keep it lit for as long as the sound lasts.
4. **`IN`.** Tap `IN`. It should light and show a marker on the waveform before you tap `OUT`.
5. **Load.** Load a different track on a stopped deck. The header should show the new title straight away, not the old one.
6. **Stems progress.** With the browser open, load a track that hasn't been split. Its compact deck should show `Stems` and a percentage.
7. **Loop key.** Set the loop length to 32. Hold a `ROLL` pad and let go. The loop key should still say 32.
8. **Stale loop.** Set a loop, then load a different track on that deck. The old loop shouldn't appear on the new track.
9. **Recording rename.** Rename a recording, then read its `.cue` and `.txt` in `Documents/Recordings/`. Both should use the new name inside.
10. **`INST` waveform.** On `STEMS`, once split, does the mint layer show the music's shape rather than a flat band? Screenshot `d10-stems`.
11. **`DEPTH` bar.** On `FX`, drag along the `DEPTH` bar itself. Does it change? *Last time: it moved relative to the touch.*
12. **Stem colours away from `STEMS`.** Once split, go to `CUE` with every stem on: the waveform should be in its normal colours. Back on `STEMS`, mute one stem and go to `CUE` again: the stem colours should stay, with the muted stem a dim ghost. Unmute it from `STEMS` and leave: the normal colours should return. Screenshot `d12-muted`.

### E. The audio session warning
Open Recordings and play a mix, then pause it. Run this, and paste the output:
```sh
xcrun simctl spawn "$SIM" log show --last 5m --predicate 'process == "Cheeks" AND category CONTAINS "Hang"' --style compact
```
It should list nothing. *Last time: "This method can lead to UI unresponsiveness".* The play button should still show pause while it's playing, and go back to play when the mix ends.

---

## Part 2: new features nobody has touched

### F. Memory cues and saved loops
1. Open the `MEM` tab. It should show `SAVE CUE`, `SAVE LOOP`, a page count, `LIST` and eight pads, with `DEL` on the tab row. Screenshot `f1-mem`.
2. Tap `SAVE CUE` twice. One red bookmark pad appears, and the second tap is refused with a capsule. A red triangle appears on the top edge of the waveform and the overview.
3. Tap `SAVE LOOP` with no loop set: a capsule says to set one. Set a 4-beat loop on the `LOOP` tab, come back and tap it again: an orange pad appears, with an orange bar along the waveform's top edge.
4. Exit the loop and needle-search elsewhere. Tap the orange pad: the deck jumps to the loop and stays in it, and the pad lights. Tap it again: the loop ends.
5. Tap `DEL`, then a pad. It goes, and the capsule offers `UNDO`. Tap it.
6. Tap `LIST`. A native list shows hot cues, memory cues and loops. Name a hot cue, change its colour, and check the `CUE` pad and waveform flag change. Switch a loop's toggle on and reload the track: the loop should be active without the deck jumping to it. Screenshot `f6-list`.
7. Terminate and relaunch. Is everything still there?

### G. Sampler
1. Open `SAMPLE`. The row should show `SET`, `Q`, `VOLUME` and `STOP`, and all eight pads should fire.
2. Tap `SET`, then a pad. A sheet opens. Screenshot `g2-sheet`. The grab buttons should only be there for decks with a loop set.
3. Set the mode to Gate and close it. Holding the pad should stop when released. Set Loop: one tap starts it, and the next stops it.
4. Set a loop on deck 1. `SET`, a pad, `Grab Deck 1's Loop`. The pad is named `LOOP 1` and goes round when tapped.
5. `SET`, a pad, `Record the Master`. A red timer replaces `SET`. After 5 seconds, tap it: the pad holds a recording of what was playing. Check the meters move when you play it.
6. `SET`, a pad with its own sound, `Restore the Original Sound`.
7. Drag `VOLUME` to the bottom: pads go quiet on the meters. `STOP` stops a looping pad.

### H. FX chain
1. On `FX`, tap `ECHO`, `FLANGER` and `TRANS` quickly: all three stay lit. Tap `CRUSH`: `ECHO` goes out and the other three stay lit. Screenshot `h1-chain`.
2. Slide on a lit pad: `DEPTH` follows that effect, and the others keep theirs.
3. Let everything go. With a deck playing, tap `OUT`. It lights, a capsule explains it, and within a beat or so the track stops and only echoes are left (watch the meters fall). Tap it again: the track comes back further along.
4. Tap `OUT` with the deck stopped: it should refuse. Pause a deck during an echo out and play it again: it mustn't come back silent.

### I. Color FX
1. In the mixer's middle column, tap `FILTER` repeatedly. It cycles `DUB`, `SPACE`, `NOISE`, `CRUSH`, `PITCH`, `FILTER`, and the label under both bottom knobs changes to match. Screenshot `i1-color`.
2. With a deck playing, turn the knob each way for each one. Report anything that goes silent, jumps to the top of the meter, or crashes. Double-tap brings it back.
3. With `DUB`, turn the knob well round, back to the centre, then pause: the meters should keep moving for a few seconds.

### J. Phrases and tempo
1. Is there a strip of colour along the bottom of each overview and big waveform? Screenshot `j1-phrases`. Note how many sections each track got, and their names.
2. The counter beside the playhead should read like `CHORUS 12.3` and count up. Does it restart at a section boundary?
3. Do the two test tracks' BPM readouts stay still while playing? If they change, that's a false tempo map: report it.

### K. Backup and restore
1. In Settings, scroll to **Library**. Tap **Save a Backup…** and save it to Files on the simulator. If the picker can't be driven, report that and carry on.
2. Delete a hot cue, then **Restore from a Backup…**. The cue should return, with a summary.
3. Find a track's file in `"$DATA/Documents/Music/"`. Move it out, terminate and relaunch. The track should show a warning triangle, and loading it should be refused with a message.
4. Copy it back into `Documents/` under the name it was imported with, and relaunch. The warning should go, and its cues should still be there.
5. Check `Documents/Backups/` has a dated JSON file.

---

## Part 3: first impressions
Answer honestly, as someone seeing it fresh. Criticism is the useful part.
1. Does it look like $1000 pro software? Name the three things that most break the illusion.
2. What felt slow, confusing or surprising?
3. Which control was hardest to find or hit?

**Don't report these two:** they're deliberate. White arcs on the level knobs (`TRIM`, `MASTER`, `CUE/MST`, `LEVEL`), and stem colours not showing on other tabs while every stem is on at full level.

---

## Results format

Write `docs/COMPUTER_USE_RESULTS_13.md` like this:

```markdown
# Hands-on results, part 13, <date>

Commit tested: <git rev-parse --short HEAD>
Device: <simulator and screen size>
Tooling limits: <what you couldn't do>

## Summary
<PASS/FAIL/BLOCKED counts, then the 3 most important problems>

## Failures
### A1: <what failed>
- Steps: ...
- Expected: ...
- Actual: ...
- Screenshot: docs/test-results-13/...
- Crash report (if any): ...

## Looks wrong
- <where, what's wrong, screenshot>

## All results
| Test | Result | Notes |
|---|---|---|
| A1 | PASS | ... |

## Timings and measurements
<the CPU table>

## First impressions
<part 3>
```
