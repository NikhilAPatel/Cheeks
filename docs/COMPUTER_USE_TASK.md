# Cheeks: hands-on task

**Who this is for:** a Claude session with computer use (it can see the screen, click and drag). This is the only document you need.

**Your job:** this round is bigger than the last few. The owner's said bugs, usability and speed are what stand between this app and a launch, and Parts 1 to 3 haven't been run since round 2, with a lot added since. Set up as below, then run **the retest**, **the first-time user**, **a big library**, and all of **Parts 1 and 2**, and write down exactly what happens. Then answer **Part 3** properly. Take as long as it takes.

**Rules:**
- **Don't change any code**, even if you can see the fix. A precise description is what's wanted.
- Record every test as PASS, FAIL or BLOCKED, based on what you actually saw. If you couldn't check it, it's BLOCKED, and say why.
- If something's blocked or the app crashes, record it and carry on. Get the crash report with `ls -t ~/Library/Logs/DiagnosticReports | grep -i cheeks | head -1` and copy it to `docs/test-results-9/`.
- Also note anything that merely looks wrong, even if the test passes.
- The sentence after each test is what the last test found. It's there so you can tell whether it changed, not to tell you what to see.

**What to hand back:** `docs/COMPUTER_USE_RESULTS_9.md` in the format at the end, with screenshots in `docs/test-results-9/`. Commit only those to `master`, with the message `Add hands-on test results, part 9`. **Don't push.**

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
xcrun simctl uninstall "$SIM" com.nikhilpatel.cheeks 2>/dev/null   # start clean
xcrun simctl install "$SIM" build/Build/Products/Debug-iphonesimulator/Cheeks.app

# Two test tracks, dropped where the app imports from at launch
tools/test-music/fetch.sh /tmp/cheeks-music
DATA=$(xcrun simctl get_app_container "$SIM" com.nikhilpatel.cheeks data)
cp /tmp/cheeks-music/*.mp3 "$DATA/Documents/"

xcrun simctl launch "$SIM" com.nikhilpatel.cheeks
mkdir -p docs/test-results-9
```

**The small iPhone:** use `iPhone SE Cheeks` (59B64076-E0E9-491A-AA6F-A82A60C3D2D2, iOS 27.2), which the owner's given the touch tool access to. It needs a fresh install. Never use `iPhone SE (3rd generation)`: by name that's another project's simulator.

**Things the last run learned about this setup:**
- **Use the iPhone Duo, unfolded (951×669 pt).** The simulator tool reports a 678×466 space, but taps land in 951×669.
- **Tap length:** default taps last about 10 ms, and system switches ignore them. Use a 0.2 s press on those. Taps sent while a sheet is closing get lost.
- **Measure the right process.** Other simulators can be running their own `Cheeks`, so never use `pgrep -x Cheeks`. Get this simulator's with:
  ```sh
  PID=$(xcrun simctl spawn "$SIM" launchctl list | awk '/UIKitApplication:com\.nikhilpatel\.cheeks\[/{print $1}' | head -1)
  ```
  The PID changes every time the app restarts, so get it again after one. `ps` reports an average over the process's whole life, so measure CPU with `top -l 7 -s 5 -pid $PID -stats cpu`, and ignore the first line of numbers.
- **Logs:** to see real problems, filter on the level, not on words, because `grep fault` also matches "Default":
  ```sh
  xcrun simctl spawn "$SIM" log show --last 5m --predicate 'process == "Cheeks" AND (messageType == error OR messageType == fault)' --style compact
  ```
- **Screenshots:** `xcrun simctl io "$SIM" screenshot --display=primary-1 docs/test-results-9/NAME.png` for the inner screen. Please downscale them to about 1600 px wide before committing, to keep the repo small.
- **Reading the meters from video:** crop widths must be even. An odd width gets rounded by ffmpeg on 4:2:0 video, which shears every frame, and round 6's first figures were wrong because of it. Run a control that's known to be red before believing a 0%.
- **Check a reload really happened:** `playCount` in `library.json` goes up by one each time. A very busy Mac can take over 1 s to open the browser, so a load key tap sent too soon lands on the old layout. Allow about 1.5 s after `BROWSE`, and at least 5 s after a load key before seeking.
- **Load average is unreliable on this Mac:** it read 40 to 940 while the busiest processes added up to a few cores. Go by what the processes use.
- **Can't be tested here, so don't report as failed:** haptics, how anything sounds, and the headphone output. List them under Tooling limits.

**Where things are:**
- **Top bar:** `cheeks`, `BROWSE`, `REC`, a waveform icon (Recordings), `MASTER n` and the tempo in the middle, then messages, the clock and the gear (Settings).
- **Waveforms:** overview, deck 1, a strip of beat blocks, deck 2, overview.
- **Decks** left and right with the **mixer** between them. Each deck has a header, a tempo fader at the outer edge, the jog, a column of keys (`BEAT SYNC`, `MASTER`, `BEAT JUMP`, `Q`, `SLIP`, `KEY`, `REV`, `−`/`+`, `KEY SYNC`), a row of controls for the current pad page, the tabs (`CUE MEM LOOP ROLL SLICER JUMP STEMS FX SAMPLE`) and eight pads. Round `CUE` and `PLAY` are in the bottom outer corner.

Load one track on each deck through `BROWSE` and the `1` and `2` keys, then close the browser. Each load starts splitting stems in the background, which uses a lot of CPU for a minute or two. Let that finish before anything that measures.

---

## The retest
To see what these were, look in `docs/COMPUTER_USE_RESULTS_8.md`, which ends with what was done about them.

**Reading the library:** `library.json` is in the app's data folder at `Library/Application Support/`. It's written about half a second after a change.

**Other sessions:** the other session may be running low-priority jobs on this Mac for a separate feature, off the simulators. It'll pause them if you ask before measuring. Check which app's in the Duo's foreground before relying on a tap: another project's session took it for 10 minutes last time.

**With two fingers:** as last time, both land together and the second slides. Say which way round each test went.

**The tracks:** copy in the three club tracks as well as the usual two, then relaunch. Splitting stems runs on the CPU in the simulator, so allow a few minutes a track, and wait for each deck's stems before pressing `AUTO`.

```sh
cp ~/Library/Caches/cheeks-autodj/music/jam1280420.mp3 ~/Library/Caches/cheeks-autodj/music/jam1072904.mp3 ~/Library/Caches/cheeks-autodj/music/jam1197771.mp3 "$DATA/Documents/"
```

`jam1197771` is Skylander (125), `jam1072904` is Gepzene (128) and `jam1280420` is Houston (126). The `AUTO` key is under the `FILTER` key on the mixer, and `MIX` and `NEXT` are in the browser's toolbar. The rules for taking over are in the table under **In the app** in `docs/AUTO_DJ.md`.

### BA. Opening the app
The first time it ran on a real phone, it took about 20 s to load things, with "image provider timed out" in the console. The pre-rendered parts are now drawn a different way.
1. **A fresh install.** Uninstall, install, launch, and time it from the launch command until a control responds. Then run this, which should find nothing:
   ```sh
   xcrun simctl spawn "$SIM" log show --last 5m --predicate 'process == "Cheeks" AND eventMessage CONTAINS "timed out"' --style compact
   ```
2. **Launching again.** The same three times more, with no reinstall.
3. **Does it look the same?** Compare the knobs, keys, fader caps and round `CUE` and `PLAY` with a screenshot from `docs/test-results-8/`, up close, lit and unlit, pressed and not. The ring's metal highlight and the knob's sheen may be a touch brighter. Is anything else different? Is anything blank, at any point in the launch? Screenshot `ba3-parts`.

### BB. `AUTO` with a loop
1. **A loop you set.** On a playing deck, `IN` then `OUT`, then `AUTO`. The loop should go, and it should plan and get there. *Last time: it counted down forever.*
2. **After stopping a move.** Stop a Loop build part-way with `AUTO`, which leaves its loop running with its filter and `LOW` moved. Press `AUTO` again. Everything the move left should go, and it should plan and get there. Screenshot `bb2-again`.
3. **During the countdown.** Press `AUTO`, then set a loop while it counts down. It should say the deck's in a loop, and call it off.
4. **In a mix, during the countdown.** The same during `MIX`. The mix should stay on, and say it'll carry on when the loop ends. `EXIT`, and it should plan again and carry on. Does anything look stuck while it waits?
5. **`MIX` with a loop running.** Start `MIX` with a playing deck in a loop. The loop should go.

### BC. The rest of what changed
1. **`Mix off`.** Press the key during a mix's move, before and after the new track lands. It should say `Mix off. The decks are yours.` and `Mix off. Deck N is on.` *Last time: "Auto DJ stopped."*
2. **Loading the waiting deck mid-move.** The old deck should carry on clean, with "Auto DJ stopped: the track changed. Deck N carries on." *Last time: left looping and filtered.*
3. **Pausing during the countdown.** It should say the deck was stopped, not that it lost its moment. In a mix, `Mix off:`.
4. **`REV` on a move's old deck** should be off once the deck's stopped.
5. **An empty list.** With nothing typed: `IN KEY` and `±6% BPM` emptying a list should say to turn them off, and an empty playlist should say how to add to it. With something typed, the usual search message.
6. **The tracklist.** During a recording: play a track, then another, then go back to the first on the same deck, for over 10 s each. All three should be in the tracklist, at the right times, and in that day's History. Stopping and starting a track with nothing in between should give one line. *Last time: the return was missing.*
7. **Ratings on a small iPhone.** Try AX5 again, on the simulator below. With an Undo and a rating showing: is the text readable, and can you press the keys? Can you still use the overview and the browser's keys beside and under the capsule?

### BD. When nothing else will do
New. When no move passes its audition, it now echoes the old track out on a phrase, and the new one starts where its beat comes in, at its own tempo, not stretched to match. It used to refuse, or a mix would just start the next track. You can't force this. Run `AUTO` and `MIX` on your tracks in every order you can, and report any "Echo throw" where the new track starts in its first third with its tempo at +0.0. How does the join look, in levels and gaps? Does anything still say it couldn't find a way?

## The first-time user
Forget everything above. Uninstall, install, and open the app as someone who's never seen it and has some music in Files. Nobody's tried this since round 2, and it may be the first thing an App Store reviewer does.

Do this on `iPhone SE Cheeks` as well as the Duo: it's the smallest screen the app has to work on, and it's had the least real touch.

1. **From nothing to a mix.** Without reading anything in the repo: get a track in, get it on a deck, get it playing, get a second one in time with it, and mix across. Then find out how to get Auto DJ to do it. Write down every moment you weren't sure what to do, what you tried first, and how long each stage took. Screenshot each moment you got stuck, as `fu-*`.
2. **What does it say when it's empty?** Every screen with nothing in it: the browser, the decks, Recordings, a playlist, the pads with no track. Is it clear what to do next?
3. **Stems.** Do you notice they're being split? Would you know why `AUTO` won't start yet? Is it clear how long it'll take?
4. **What needs explaining?** List every control you couldn't work out from looking at it. Don't be polite.
5. **What happens when you do it wrong?** Press things in the wrong order, with nothing loaded, twice, and during a load. Is every refusal clear? Is anything silently ignored?

## A big library
It's only been tried with 5 tracks. Before launching, write a library of made-up tracks. They've no audio, so they show a warning triangle, and your real tracks are imported alongside them:
```sh
python3 tools/test-music/big_library.py "$DATA/Library/Application Support/library.json" 2000
```
1. **Launch:** how long until a control responds?
2. **The browser:** open and close it, scroll hard, type in the search box, tap each column, and use `NEXT`, `IN KEY` and `±6% BPM`. Record a video. Is there any hitch you can see? Say where, and how long.
3. **While playing:** the same, with both decks playing and a recording running. Check the recording for gaps afterwards.
4. **Measure:** CPU and memory scrolling and at rest, by the method above.

### Pressing harder
**A long run.** 15 minutes, with `MIX` and `AUTO` running, and taking over as many ways as you can, with loops now too. A recording running throughout, so you can check for gaps. Afterwards the decks should always be usable, with nothing left silent, looping or filtered that the screen doesn't show. Crashes, dropouts, or a stop you can't explain?

---

## Part 1: was it fixed?

### A. The three failures
1. **Undo (the top priority).** Set a hot cue with an empty pad on the `CUE` tab. Tap `DEL`, then the cue. The capsule offers an `UNDO` key. Tap it. The cue should come back and the capsule should go. Try it with a default tap and a 0.2 s press, with the deck paused and playing. Screenshot `a1-undo`. *Last time: five taps did nothing. The control has been rebuilt, and it couldn't be reproduced with another touch tool, so this result is the one that matters.* Report exactly which attempts worked.
2. **Refused load.** With deck 1 playing, open the browser and tap `1` on the other track. It must not load. The key should shake, and a capsule should say deck 1 is playing, with a hand icon rather than a green tick. Record a short video if you can, to catch the shake. Swiping the row should say the same. Screenshot `a2-refused`. *Last time: no shake and no message on a tap, and a green tick on a swipe.*
3. **CPU.** Measure each state for 30 s, after 10 s of settling, on the pinned process. Stems must have finished first. *Last time: everything sat at 12 to 15%.*
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
2. **Crossfader centre.** Drag the crossfader slowly through the middle. It should catch at the centre within about 3 pt each way. *Last time: under 1 pt.*
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
11. **`DEPTH` bar.** On `FX`, drag along the `DEPTH` bar itself. Does it change? *The last report said not, but another touch tool moved it from 60% to 100%. Report which you see.*
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

Write `docs/COMPUTER_USE_RESULTS_9.md` like this:

```markdown
# Hands-on results, part 9, <date>

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
- Screenshot: docs/test-results-9/...
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
