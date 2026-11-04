# Cheeks: hands-on task

**Who this is for:** a Claude session with computer use (it can see the screen, click and drag). This is the only document you need.

**Your job:** set up as below, then run **the retest**, **not run for a while**, **the first-time user** and **pressing harder**, and answer **Part 3**.

**Rules:**
- **Don't change any code**, even if you can see the fix. A precise description is what's wanted.
- Record every test as PASS, FAIL or BLOCKED, based on what you actually saw. If you couldn't check it, it's BLOCKED, and say why.
- If something's blocked or the app crashes, record it and carry on. Get the crash report with `ls -t ~/Library/Logs/DiagnosticReports | grep -i cheeks | head -1` and copy it to `docs/test-results-14/`.
- Also note anything that merely looks wrong, even if the test passes.
- The sentence after each test is what the last test found. It's there so you can tell whether it changed, not to tell you what to see.

**What to hand back:** `docs/COMPUTER_USE_RESULTS_14.md` in the format at the end, with screenshots in `docs/test-results-14/`. Commit only those to `master`, with the message `Add hands-on test results, part 14`. **Don't push.**

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
mkdir -p docs/test-results-14
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
- **Screenshots:** `xcrun simctl io "$SIM" screenshot --display=primary-1 docs/test-results-14/NAME.png` for the inner screen. Please downscale them to about 1600 px wide before committing, to keep the repo small.
- **Reading the meters from video:** crop widths must be even. An odd width gets rounded by ffmpeg on 4:2:0 video, which shears every frame, and round 6's first figures were wrong because of it. Run a control that's known to be red before believing a 0%.
- **Check a reload really happened:** `playCount` in `library.json` goes up by one each time. A very busy Mac can take over 1 s to open the browser, so a load key tap sent too soon lands on the old layout. Allow about 1.5 s after `BROWSE`, and at least 5 s after a load key before seeking.
- **Load average is unreliable on this Mac:** it read 40 to 940 while the busiest processes added up to a few cores. Go by what the processes use.
- **Stopping a video:** `simctl io recordVideo` stops on SIGINT, and a background job in a non-interactive shell ignores that unless you restore it. Never send SIGTERM: that left the Duo's render server recording with nothing attached, writing up to about 650 MB a minute with the screen moving and about 9 MB with its app closed, and only a shutdown clears it, which folds the Duo.
- **Your touches aren't a UI test's.** A press along the top of the screen set off iOS's scroll-to-top for your tool and not for XCUITest, so a UI test passing doesn't settle anything near the screen's edges.
- **Can't be tested here, so don't report as failed:** haptics, how anything sounds, and the headphone output. List them under Tooling limits.

**Where things are:**
- **Top bar:** `SEGUE DJ`, `BROWSE`, `REC`, a waveform icon (Recordings), `MASTER n` and the tempo in the middle, then messages, the clock, `?` and the gear (Settings).
- **Waveforms:** overview, deck 1, a strip of beat blocks, deck 2, overview.
- **Decks** left and right with the **mixer** between them. Each deck has a header, a tempo fader at the outer edge, the jog, a column of keys (`BEAT SYNC`, `MASTER`, `BEAT JUMP`, `Q`, `SLIP`, `KEY`, `REV`, `−`/`+`, `KEY SYNC`), a row of controls for the current pad page, the tabs (`CUE MEM LOOP ROLL SLICER JUMP STEMS FX SAMPLE`) and eight pads. Round `CUE` and `PLAY` are in the bottom outer corner.

Load one track on each deck through `BROWSE` and the `1` and `2` keys, then close the browser. Each load starts splitting stems in the background, which uses a lot of CPU for a minute or two. Let that finish before anything that measures.

---

## The retest
To see what these were, look in `docs/COMPUTER_USE_RESULTS_13.md`, which ends with what was done about them.

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
1. **The browser on video on the Duo.** With 2,000 tracks (before launching: `python3 tools/test-music/big_library.py "$DATA/Library/Application Support/library.json" 2000`) and both decks playing, open and close it ten times. Worst gap between changed frames, and how many? *iPad with 2 tracks last time: 0.16 s.*
2. **The logo, frame by frame,** on the Duo: it shouldn't double or jump at the handover.
3. **The launch sweep,** five launches on the Duo: the meters should run up and back once as the logo lifts.

### FB. What failed last time
1. **N6: `MIX` from part-way down a list.** Row 4 of 5 playing, `MIX`. It should go on to row 5 and then come back to rows 1, 2 and 3, leaving out any that's already been on air for 10 s or more since you opened the app. Run it to the end. The first message should say how many tracks that is, then what's up next, in one message. Then with everything else already played: it should refuse. Which list it's going through, and how many are left, were the first-time user's questions: is that answered now? *Last time: two tracks and then nothing.*
2. **N7: the crossfader shut on the playing deck.** Crossfader all the way to deck 2, deck 1 playing, deck 2 stopped with stems still to come.
   - `AUTO`: the crossfader should go to the middle at once, the master meters should come up, and the message should say so. `AUTO` again should put it back, with the master silent again, as you left it.
   - `MIX`: the same at once, and `MIX` again should put it back.
   - Crossfader already on the playing deck's side: it should stay there until a move needs it.
   - `MIX` with nothing playing, the crossfader away from deck 1 and deck 1's fader down: the first track should be heard from its first moment.
   - `MIX` with the next track on the list already on the waiting deck and splitting: the percentage should carry on, not go back to about 2%.
   - `MIX` with the first row already on deck 1, stopped, with a tempo set: it should start from there at that tempo.
   *Last time: up to about 100 s of silence.*
3. **N4: a track that goes quiet long before its end.** Make one as you did last time, with 55 s of silence after the music. `AUTO` with the other deck's stems still to come, and then the same with `MIX`, which wasn't tried. The next track should start as the music ends. Also with 3 minutes of silence, and try the same track twice in a row. *Last time: 25.1 s under -50 dB.*
4. **N8: the `FILTER` knobs and the key.** Set `DUB`, and check knobs and key at each step.
   - Press `AUTO`. Plan made, counting down: both should read `DUB`.
   - Once the move's started: knobs on a deck the move's sweeping a filter on should read `FILTER`. Which moves did that, and which didn't?
   - After the move: both knobs `DUB`, key `DUB`, and the next press goes on to `SPACE`.
   - During a `MIX`, a minute ahead of its move: `DUB`.
   - `AUTO` off before the move, stopping the new deck during it, and `AUTO` during it. In the last, if the filter's still swept the knob can stay on `FILTER`: say what you see.
   *Last time: knobs `FILTER`, key `DUB`, and it stayed.*
5. **N5: the slide.** Deck 1, the mixer and deck 2 now go right together, the same distance, and the browser comes in over deck 1, with no fade. So there should be nothing to see through and no black opening in the middle. Frame by frame on video on the iPad with two tracks playing (`CHEEKS_SELF_TOUR=browser`, starting about 15 s after launch), both ways, say the widest gap you measure each side of the mixer, and how many frames it lasts. The mixer moves with SwiftUI and the rest with UIKit, so expect them to be up to about 10 to 40 pt apart on a busy Mac, and I measured 173 pt for 4 frames on the first slide after launch. Say whether that first slide stands out for you too. Also:
   - **A flash or blank as a panel comes back.** The fade used to hide that: look at the jogs and the pads in the first frames of closing.
   - **Anything popping** about 0.7 s after it stops, when what's offstage leaves the window. Deck 1's under the browser until then.
   - **The small iPhone:** the browser comes up from the bottom over decks that stay where they are, and goes down the same way.
   - `BROWSE` twice quickly, and a press in the slide, as for FB1 last time: `PLAY`, a pad, and a row's `1`. Never a wrong cue.
   *Last time: 381 pt on the iPad, with both panels half see-through.*

### FC. What looked wrong last time
1. **`RELOOP` after handing back a Loop build.** `AUTO` during a build: the key beside it should show the loop's real length, and `EXIT` then `RELOOP` should come back to that. *Last time: the key read 4 and it came back as 16.*
2. **"starting":** on a Brake drop it should come as the brake starts, and on an Echo throw as the echo does. Loop builds should be as they were. *Last time: after the brake and after the new track.*
3. **The first message:** "Loop build in about 6 bars". The key counts on from there.
4. **History with a track in it twice:** no SwiftUI lines about repeated IDs, and each row's `1`, `2` and long press still do the right one.
5. **`NEXT` and loading.** With `NEXT` on, load a track, and press another row's `1` or `2` within a second. It should land on the row you aimed at, and the list should reorder about 2 s later. Turning `NEXT` on, and reopening the browser, should order it straight away. *Last time: it landed on another row.*
6. **A held slice or roll during a mix.** No word about a loop, and the mix's plan stays. What happens if you hold one past the moment the move's due?
7. **Taking a control during a move.** Turn a knob the move's using: "That's yours now. Auto DJ carries on with the rest.", once a move. A knob it isn't using says nothing. Then the crossfader, all the way away from the new deck during a move: at the end it should say it's turned away.
8. **The thumbs:** "Echo throw done. Deck 2 is on. More like that?" beside them.
9. **Sorting.** Sort All Tracks by BPM, open a playlist: it should be in the order you built it, with no column lit. Sort the playlist, go back to All Tracks: BPM again. Then `MIX` on the playlist plays that order.
10. **Renaming a playlist:** press and hold it in the sidebar. History shouldn't offer it.
11. **A recording's playback.** A time, a length and a slider while it plays. Pause should hold its place, and play should go on from there, where before it started again from the top. Drag the slider. Let one play to its end. And while recording with none saved yet, the sheet should say you're recording, not to tap `REC`.
12. **`MORE` on a phone:** after reaching `SAMPLE`, leave for `CUE` and press `MORE`: it should go straight back to `SAMPLE`.
13. **How long a message stays up.** Time "FX pads slide…" and a long one, on the Duo or the small iPhone. Nothing should be up for under 5 s unless another took its place. *Last time: about 2.5 s for the first, which I can't explain from the code, so if it's short again please say what took it away.*
14. **The notes** for `MIX`, `AUTO` (lit, during a mix too), `NEXT`, `WAVEFORM`, the `FILTER` knob, `PLAYLISTS`, `IMPORT` and `REC`: true, as far as you can try them?
15. **Section names:** Houston should now read something like `INTRO`, `CHORUS` 0:22, `VERSE` 0:38, `CHORUS` 1:46, `VERSE` 2:09, `CHORUS` 2:55, `VERSE` 3:18, `CHORUS` 3:56, `OUTRO` 4:26. List the others as before, and say what looks unlikely.
16. **The empty library:** its text now says to go back if Files opens on an empty folder. Does the picker do that on a fresh install?

## Not run for a while
These haven't been run lately, and a recording's playback has changed. From **Part 1**: **B2, B5, B6, C4, C7, C8, C9, D1, D5, D6, D7, D8, D9, D10, D12** and **E**. From **Part 2**: **F, J** and **K**. Also `A2` and `B1`, as the slide's changed again. The rest passed last round.

## The first-time user
Forget everything above. Uninstall, install, and open the app as someone who's never seen it and has some music in Files. Stay away from the repo's docs and code, and say what you can't un-know.

**Last time it had been shown the project's notes before it began,** as that session started in the repo, and that spoiled finding `MIX`, `?` and the tempo fader. So please start it from a folder outside the repo if you can, with only what it needs to reach the simulator. On the Duo if it's been restarted, and on the small iPhone on its side if not.

**Give it the full 45 minutes.** Let it find its own way, and look out for these, which nobody has seen yet:
- Would it find `MIX` at all, and does it read as one more filter?
- What does it make of the moves, the thumbs, and `MEM` beside `CUE`?
- Does it know what's left in a mix, and that a mix has ended?

1. Every moment you weren't sure what to do, what you tried first, and how long each stage took. Screenshot each, as `fu-*`.
2. **Use `?` as you go.** What's still a mystery after it? Which note was wrong, or didn't help?

### Pressing harder
**A long run.** 15 minutes, with `MIX` and `AUTO` running, and taking over as many ways as you can, including pressing things just as a panel slides, and with `DUB` chosen throughout. **A Bass swap has to play this time:** none did last round, and its beat of silence wants checking on a recording. A recording running throughout, so you can check for gaps, and music on throughout. Afterwards the decks should always be usable, with nothing left silent, looping or filtered that the screen doesn't show. Crashes, dropouts, or a stop you can't explain? On the small iPhone if the Duo hasn't been restarted.

---

## Part 1: was it fixed?

### A. The three failures
1. **Undo (the top priority).** Set a hot cue with an empty pad on the `CUE` tab. Tap `DEL`, then the cue. The capsule offers an `UNDO` key. Tap it. The cue should come back and the capsule should go. Try it with a default tap and a 0.2 s press, with the deck paused and playing. Screenshot `a1-undo`. *Last time: five taps did nothing. The control has been rebuilt, and it couldn't be reproduced with another touch tool, so this result is the one that matters.* Report exactly which attempts worked.
2. **Refused load.** With deck 1 playing, open the browser and tap `1` on the other track. It must not load. The key should shake, and a capsule should say deck 1 is playing, with a hand icon rather than a green tick. Record a short video if you can, to catch the shake. Swiping the row shows a `Deck 1` action, and tapping that should say the same. Screenshot `a2-refused`. *Last time: no shake and no message on a tap, and a green tick on a swipe.*
3. **CPU.** Measure each state for 30 s, after 10 s of settling, on the pinned process. Stems must have finished first. *Last time, on the small iPhone: 4.1%, 4.3%, 9.4%, 14.6% and 14.9%.*
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

Write `docs/COMPUTER_USE_RESULTS_14.md` like this:

```markdown
# Hands-on results, part 14, <date>

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
- Screenshot: docs/test-results-14/...
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
