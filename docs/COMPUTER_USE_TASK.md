# Cheeks: hands-on task

**Who this is for:** a Claude session with computer use (it can see the screen, click and drag). This is the only document you need.

**Your job:** set up as below, then run **the retest**, **not run for a while**, **the first-time user** and **pressing harder**, and answer **Part 3**.

**Rules:**
- **Don't change any code**, even if you can see the fix. A precise description is what's wanted.
- Record every test as PASS, FAIL or BLOCKED, based on what you actually saw. If you couldn't check it, it's BLOCKED, and say why.
- If something's blocked or the app crashes, record it and carry on. Get the crash report with `ls -t ~/Library/Logs/DiagnosticReports | grep -i cheeks | head -1` and copy it to `docs/test-results-20/`.
- Also note anything that merely looks wrong, even if the test passes.
- The sentence after each test is what the last test found. It's there so you can tell whether it changed, not to tell you what to see.

**What to hand back:** `docs/COMPUTER_USE_RESULTS_20.md` in the format at the end, with screenshots in `docs/test-results-20/`. Commit only those to `master`, with the message `Add hands-on test results, part 20`. **Don't push.**

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
mkdir -p docs/test-results-20
```

**The small iPhone:** use `iPhone SE Cheeks` (59B64076-E0E9-491A-AA6F-A82A60C3D2D2, iOS 27.2), which the owner's given the touch tool access to. It needs a fresh install. Never use `iPhone SE (3rd generation)`: by name that's another project's simulator.

**Things the last run learned about this setup:**
- **Use the iPhone Duo, unfolded (951×669 pt), if it's open.** The simulator tool can report a 678×466 space, but taps land in 951×669. Don't reboot it: that folds it, and only Device Hub can open it again. It was folded at the end of last round, so check `hingeState:` in SpringBoard's log first. If it says `Closed`, use the small iPhone, and the iPad for video.
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
- **Screenshots:** `xcrun simctl io "$SIM" screenshot --display=primary-1 docs/test-results-20/NAME.png` for the inner screen. Please downscale them to about 1600 px wide before committing, to keep the repo small.
- **Reading the meters from video:** crop widths must be even. An odd width gets rounded by ffmpeg on 4:2:0 video, which shears every frame, and round 6's first figures were wrong because of it. Run a control that's known to be red before believing a 0%.
- **Check a reload really happened:** `playCount` in `library.json` goes up by one each time. A very busy Mac can take over 1 s to open the browser, so a load key tap sent too soon lands on the old layout. Allow about 1.5 s after `BROWSE`, and at least 5 s after a load key before seeking.
- **Load average is unreliable on this Mac:** it read 40 to 940 while the busiest processes added up to a few cores. Go by what the processes use.
- **Stopping a video:** `simctl io recordVideo` stops on SIGINT, and a background job in a non-interactive shell ignores that unless you restore it. Never send SIGTERM: that left the Duo's render server recording with nothing attached, writing up to about 650 MB a minute with the screen moving and about 9 MB with its app closed. Only a shutdown clears it, which folds the Duo, and that shutdown starts copying the temp file into a final video at about 300 MB/s, so it has to be followed at once by `kill -9` of that `SimRenderingServices` process. Find its PID first: `lsof -p PID` shows the recording's path. The space comes back within about 10 s.
- **Your touches aren't a UI test's.** A press along the top of the screen set off iOS's scroll-to-top for your tool and not for XCUITest, so a UI test passing doesn't settle anything near the screen's edges.
- **Can't be tested here, so don't report as failed:** haptics, how anything sounds, and the headphone output. List them under Tooling limits.

**Where things are:**
- **Top bar:** `SEGUE DJ`, `BROWSE` (it reads `DECKS` while the browser's open), a waveform icon (Recordings), `REC`, `MASTER n` and the tempo in the middle, then messages, the clock, `?` and the gear (Settings).
- **Waveforms:** overview, deck 1, a strip of beat blocks, deck 2, overview.
- **Decks** left and right with the **mixer** between them. Each deck has a header, a tempo fader at the outer edge, the jog, a column of keys (`SYNC`, `MASTER`, `BEAT JUMP`, `Q`, `SLIP`, `KEY`, `REV`, `−`/`+`, `KEY SYNC`), a row of controls for the current pad page, the tabs (`CUE MEM LOOP ROLL SLICER JUMP STEMS FX SAMPLE`) and eight pads. Round `CUE` and `PLAY` are in the bottom outer corner.

Load one track on each deck through `BROWSE` and the `1` and `2` keys, then close the browser. Each load starts splitting stems in the background, which uses a lot of CPU for a minute or two. Let that finish before anything that measures.

---

## The retest
To see what these were, look in `docs/COMPUTER_USE_RESULTS_19.md`, which ends with what was done about them.

**Reading the library:** `library.json` is in the app's data folder at `Library/Application Support/`. It's written about half a second after a change.

**Other sessions:** the other session may be building at low priority on `iPad Air 13-inch (M4)`, and it'll hold off if you ask before measuring. Other projects' jobs may be running as well, so say what was running beside anything you measure. Check which app's in the simulator's foreground before relying on a tap.

**The tracks:** copy in the three club tracks as well as the usual two, then relaunch. Splitting stems runs on the CPU in the simulator, so allow a few minutes a track, and wait for each deck's stems before pressing `AUTO`.

```sh
cp ~/Library/Caches/cheeks-autodj/music/jam1280420.mp3 ~/Library/Caches/cheeks-autodj/music/jam1072904.mp3 ~/Library/Caches/cheeks-autodj/music/jam1197771.mp3 "$DATA/Documents/"
```

`jam1197771` is Skylander (125), `jam1072904` is Gepzene (128) and `jam1280420` is Houston (126). The `AUTO` key is under the `FILTER` key on the mixer, and `MIX` and `NEXT` are in the browser's toolbar. The rules for taking over are in the table under **In the app** in `docs/AUTO_DJ.md`.

**A Bass swap and a Loop build each have a beat of silence in them on purpose,** just before the new track lands (`TransitionScore.breath`): about 0.45 s under -50 dB on a Bass swap's recording, and on a Loop build as well if the new track has a gap of its own there, as Gepzene does at 0:15. That isn't a hole. Anywhere else, it is. Gepzene and Houston have gaps of their own of about 0.25 s, at 0:15 to 0:30 and 1:10 to 1:16.

**The disk:** the Duo's stuck recorder is gone. Keep an eye on free disk all the same, and stop at 40 GB, as before.

### GA. Blocked last time
These need a full layout you can press: the Duo opened in Device Hub (the last `hingeState:` in SpringBoard's log says `OpenFlat`), or touch access to the iPad, which is the owner's to grant. If you have neither, say BLOCKED and carry on. Don't reboot the Duo to try.
1. **The browser on video on the Duo.** With 2,000 tracks (before launching: `python3 tools/test-music/big_library.py "$DATA/Library/Application Support/library.json" 2000`, and copy two real files in as well, or the tour stops) and both decks playing, open and close it ten times. Worst gap between changed frames, and how many? *iPad stand-in last time: 0.155 s.*
2. **The logo, frame by frame,** on the Duo: it shouldn't double or jump at the handover.
3. **The launch sweep,** five launches on the Duo: the meters should run up and back once as the logo lifts.
4. **Pressing during the slide on the full layout.** `BROWSE` twice quickly, and a press in the slide: `PLAY`, a pad, and a row's `1`, freezing the app with SIGSTOP to land inside it, as before. Never a wrong cue. *Nobody's pressed on this since the slide changed.*

### GB. What failed last time
1. **N32: the capsule grows with its words.** The first load's tip on a clean install, upright on the folded Duo: three lines, all inside the capsule, with nothing coming out of it. Two-line messages on each phone: clear of its edges. Look for the longest you can get: `AUTO`'s message with a lot taken over (`GC` below), and `Moved the crossfader to the middle.` in front of "Auto DJ is waiting for the stems...". Is what it covers for its few seconds a problem? *Last time: 25 pt tall on one line or three.*
2. **N33: the fader says when it takes a deck off `SYNC`.** Your own steps: Exhilarate on deck 1, Gepzene synced at 170, drag the cap 12 pt. "Deck 2's off SYNC: you moved its tempo fader." with `UNDO`. `UNDO` puts the speed and `SYNC` back, and they stay in step. Moving it further says nothing more. *Last time: 170 to 149.28 with no word.*
3. **N34: `AUTO` says what it's taken over.** Your own steps: Houston on deck 1 with `FLANGER` on, Gepzene stopped on deck 2 with `VOCAL` muted, `LOW` down and `SYNC` on, `AUTO`. "Loop build next, with deck 2 cued at 126 BPM. It's taken over deck 2's SYNC, EQ and stems, and deck 1's effects. AUTO's counting down the bars." With everything neutral, no such sentence. When it starts: "From here, a control you touch is yours." Does that settle "who's in charge" for you?
4. **N35: `Back to Its Own Speed`** first in the `BPM` menu, on screen without scrolling, on the small iPhone on its side.
5. **N36: `AUTO` just after a move.** Within 3 s of a move ending, with the question up: a buzz, nothing else, and the question stays. With no question up: "That move's just finished. Press AUTO again for the next one." A second press starts the next one. After 3 s the first press does. Stopping a move yourself and pressing straight away starts again, with no refusal.

### GC. New this round
1. **The key says what it's counting.** Under `AUTO` or `MIX`: `128 BARS`, `1 BAR`, `STEMS 14%`, `CHOOSING`, `WAITING`, `AT THE END`. Do they fit, on the small iPhone and upright? Are they readable at that size? Do they cover it? *Last time: `MIX 78` read as a percentage, even after its note.*
2. **`SYNC`.** One name on every page. On a phone, `MASTER` under it on the deck the other follows, on both pages. Does that tell you who's following whom?
3. **The Mixer sheet on a phone on its side.** It stays on the bottom edge at 220 pt, with both waveforms and the deck headers showing above it. All of it's there, the knobs turn, a drag on them doesn't move the sheet, and `?`'s note fits. On `iPhone 17` too, as it has a home bar. Upright, as before. *Last time: a row of knobs and half a screen of nothing.*
4. **Changing a playlist's order.** Hold a row in a playlist: `Change the Order`. Handles, a line along the bottom, and `DONE`. Drag some rows, including a long way in a long list. `DONE`. Reopen it, and relaunch: it stays. `MIX` plays that order. From a sort, `NEXT` or a filter, it goes back to the playlist's own order first. Changing list or closing the browser ends it. History doesn't offer it. Dropping a lifted row in a playlist says "To change the order, hold a row and choose Change the Order." On a phone, a row in All Tracks doesn't lift. What does sliding to a menu item do there? Anything you could do by accident?
5. **A filter says what it's leaving out.** "4 of 7 showing, with ±6% BPM on." along the bottom of the list. With a mix on as well, both lines.
6. **`?`'s note and a message.** With `?` on and a note up, get a message: the note goes to the bottom, and you can read both. *Last time: a warning behind the note, for a first-time user.*
7. **Words.**
   - A mix with stems not ready when the track runs out: "The stems didn't get there in time. Deck 1 just started."
   - Re-analyse: "Analysed Fast Bird again: 140.1 BPM, 10A."
   - `Set downbeat here`: "The bar starts here now." with `UNDO`. The grid's 10 ms keys say so.
   - Deleting a track: "A file you picked in Files stays there." The backup's alert is titled Backup.
   - "Deck 2 is now 26% slower than its own 170 BPM, to follow."
   - "That's yours for this move. The mix carries on with the rest." in a mix.
   - `NEXT`'s note against the order you see. Does it explain it now?
   - `TIME`'s note on why a new track reads a little way in.
   - On a phone, a dim load key for a playing deck: "Deck 1 is playing. Stop it first."
8. **Pads.** With Prepare stems off, `START` on `STEMS` splits that track. `SET`: "Now press the pad you want to change." The sampler's sheet says what One shot, Gate and Loop do, and fits on its side. The first time on `STEMS` and on `MEM`, a tip, once. Pressing `MORE` round: do the tabs beside it stay still?
9. **Renaming a playing recording.** It carries on from where it was, and stays paused if it was. *Last time: it stopped and lost its place.*
10. **The guide's search,** scrolled, on a phone on its side and upright: does the text still show through its bar?

## Not run for a while
These weren't asked for last round. From **Part 1**: **A2, A3, B2 to B6, C4, C7 to C9, D1, D5 to D10, D12** and **E**. From **Part 2**: **F, J** and **K**. The rest passed last round.

## The first-time user
Forget everything above. Uninstall, install, and open the app as someone who's never seen it and has some music in Files. Stay away from the repo's docs and code, and say what you can't un-know.

**How to start it:** the `Explore` subagent type gets no CLAUDE.md or memories, and it has Bash and the touch tool. Say in its first brief that it may write screenshots and a report to one folder, or it won't. Keep its early screenshots, as it can't look back at them itself. **On `iPhone 17` upright this time,** if it's free, or on the Duo unfolded if that's open: that's how most people hold a phone, and nobody's learned the app that way on an ordinary one. Make sure no backups are in its Files.

**Give it the full 45 minutes.** Let it find its own way, and look out for these:
- How long until it can say what Auto DJ does to a track? Last time 15:32, from watching `STEMS` as a message told it to.
- Is it clear who's in charge of what? "It's hard to tell" was the worst thing last time.
- What's still doing nothing with no word?

1. Every moment you weren't sure what to do, what you tried first, and how long each stage took. Screenshot each, as `fu-*`.
2. **Use `?` as you go.** What's still a mystery after it? Which note was wrong, or didn't help?

### Pressing harder
**A long run.** 15 minutes, with `MIX` and `AUTO` running, and taking over as many ways as you can, including pressing things just as a panel slides, and with `DUB` chosen throughout. **Hand back in a build's last bars at least twice,** with `AUTO` and with `EXIT`, and a Bass swap at least once. A recording running throughout, so you can check for gaps, and music on throughout. Afterwards the decks should always be usable, with nothing left silent, looping or filtered that the screen doesn't show. Crashes, dropouts, or a stop you can't explain? On the Duo if it's open, and on the small iPhone if not. **At least one seek past a mix's exit,** one load on the waiting deck, one load on a mix's last track, one mix started on a track with its saved loop on, and `AUTO` pressed just after a move ends.

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
1. Open the `MEM` tab. It should show `SAVE CUE`, `SAVE LOOP`, `LIST` and eight pads, with `DEL` on the tab row, and a page count once there's a second page. Screenshot `f1-mem`.
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

**Don't report these:** they're deliberate. White arcs on the level knobs (`TRIM`, `MASTER`, `CUE/MST`, `LEVEL`), stem colours not showing on other tabs while every stem is on at full level, and the first analysis's section names changing when the stems finish.

---

## Results format

Write `docs/COMPUTER_USE_RESULTS_20.md` like this:

```markdown
# Hands-on results, part 20, <date>

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
- Screenshot: docs/test-results-20/...
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
