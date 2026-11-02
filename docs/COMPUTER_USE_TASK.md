# Cheeks: hands-on task

**Who this is for:** a Claude session with computer use (it can see the screen, click and drag). This is the only document you need.

**Your job:** check that the problems from the last hands-on test are really fixed. Set up as below, then run **the retest** in order and write down exactly what happens. Parts 1 to 3 passed last time: only run them if the owner asks, and use them to find your way around.

**Rules:**
- **Don't change any code**, even if you can see the fix. A precise description is what's wanted.
- Record every test as PASS, FAIL or BLOCKED, based on what you actually saw. If you couldn't check it, it's BLOCKED, and say why.
- If something's blocked or the app crashes, record it and carry on. Get the crash report with `ls -t ~/Library/Logs/DiagnosticReports | grep -i cheeks | head -1` and copy it to `docs/test-results-7/`.
- Also note anything that merely looks wrong, even if the test passes.
- The sentence after each test is what the last test found. It's there so you can tell whether it changed, not to tell you what to see.

**What to hand back:** `docs/COMPUTER_USE_RESULTS_7.md` in the format at the end, with screenshots in `docs/test-results-7/`. Commit only those to `master`, with the message `Add hands-on test results, part 7`. **Don't push.**

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
mkdir -p docs/test-results-7
```

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
- **Screenshots:** `xcrun simctl io "$SIM" screenshot --display=primary-1 docs/test-results-7/NAME.png` for the inner screen. Please downscale them to about 1600 px wide before committing, to keep the repo small.
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
Everything from the last retest passed apart from what's below. To see what those were, look in `docs/COMPUTER_USE_RESULTS_6.md`, which ends with what was done about them.

**Reading the library:** `library.json` is in the app's data folder at `Library/Application Support/`. It's written about half a second after a change.

**Other sessions:** the other session may be running low-priority jobs on this Mac for a separate feature, off the simulators. It'll pause them if you ask before measuring. Check which app's in the Duo's foreground before relying on a tap: another project's session took it for 10 minutes last time.

**With two fingers:** as last time, both land together and the second slides. Say which way round each test went.

### AT. Rolls come back
A plain roll sometimes carried on from where it was instead of going back. The cause was a race in the audio core, so it's more likely the busier the Mac is. Don't wait for a quiet Mac for this one.
1. **Sixty rolls.** Deck playing, on `ROLL`. Hold `1/4` for about 1 s, sixty times, about 2 s apart, with a video running. On each lift the clock should jump by what was held. A roll that's lost shows as no jump, and the clock falling a second behind the time that's passed. Compare the clock against the time at the end as well. Screenshot `at1-rolls`. *Last time: 1 lost in about 30.*
2. **Slices.** The same with a `SLICER` pad, twenty times.
3. **Pad to pad.** With one finger on `1/4` and the second landing on `1/8` as the first lifts, as near together as your tool allows. Ten times. The deck should end up where the track has got to. Say how close together they landed.
4. **`SLIP`.** With `SLIP` on, set an auto loop and press `EXIT`, ten times. The clock should jump each time.

### AU. Back from the background
1. **The frozen meter.** Deck playing with `SPIRAL` on. `PLAY` to stop it, send the app away within a second for 20 s, and bring it back. The deck's column should be dark within a moment. Screenshot `au1-meter`. *Last time: 15 LEDs and an amber peak, until that deck next played.*
2. **The same without an effect,** and for longer: 2 minutes away with both decks stopped.
3. **Everything else that's drawn.** With a deck playing when the app goes away, and with one stopped: waveforms, overviews, jogs and the phase strip should all be right on return, not an old picture.

### AV. `PLAY` straight after a load
`PLAY` pressed while a track's loading now waits for the track. Allow about 1.5 s after `BROWSE` for the browser to open.
1. **It starts.** In the browser, tap a deck's load key, then its compact `PLAY` about 0.3 s later. `PLAY` should light straight away, and the deck should start by itself from its cue once it's loaded. Screenshot `av1-play`. *Last time: the press was lost, with no message.*
2. **Changing your mind.** The same, then `PLAY` again before it's loaded: it goes out, and the deck stays stopped at its cue.
3. **`CUE`.** The same, then the compact `CUE` before it's loaded. It goes out, and the deck stays stopped.
4. **Another track.** The same, then another load key on that deck before it's finished. Nothing should start by itself.
5. **The big `PLAY`.** Close the browser while it's loading if you can, and press the round `PLAY` under the `Loading` cover.

### AW. The jog when the app goes away
Hold the jog's middle with the deck playing, and send the app away with `simctl launch` of Settings during the hold, for about 8 s. The clock should carry on from that moment, not a few seconds later. Bring it back: the deck runs normally. *Last time: it stayed held for about 5 s.*

### AM. Auto DJ: set up

Not run yet. Nobody but unit tests has pressed the real key. Copy three club tracks in as well as the usual two, then relaunch:

```sh
cp ~/Library/Caches/cheeks-autodj/music/jam1280420.mp3 ~/Library/Caches/cheeks-autodj/music/jam1072904.mp3 ~/Library/Caches/cheeks-autodj/music/jam1197771.mp3 "$DATA/Documents/"
```

Splitting stems runs on the CPU in the simulator, so allow a few minutes a track. Wait for each deck's stems to finish before pressing `AUTO`. A key has been added under the `FILTER` key on the mixer.

### AN. Corrected grids
1. Load `jam1197771` and wait for stems. Note the deck's BPM and where the beat lines sit before and after stems finish. It should end at 125.00, with lines on the kicks. Screenshot `an1-grid`.
2. Load `jam1280420` on the other deck and press `BEAT SYNC`. Do the waveforms' kicks line up? Screenshot `an2-sync`.
3. Do hand edits survive? On a track whose stems aren't done yet, use `Grid 10 ms later` in the BPM menu. When stems finish, the grid should stay where you put it.
4. Is a section's name still sensible after the grid moves? Note anything that changes to something odd.

### AO. `AUTO` says no
1. Press it with nothing playing. It should refuse and say why.
2. With both decks playing. Same.
3. With only one deck loaded and playing. Same.
4. With one deck playing, and the other still splitting stems: the key should read `AUTO…` and say it's waiting. Then it should carry on by itself when stems finish.

### AP. The whole thing
Play `jam1280420` from about 1:30, with `jam1072904` loaded on the other deck, stems done. Press `AUTO`.
1. **Planning:** how long from the press until it says what it's going to do, and how many bars away? Time it. The key should count down in bars.
2. **Waiting:** does the count fall in step with the music? Screenshot `ap2-armed`.
3. **The move:** do stem levels, EQ and filter visibly move on their own? Do the waveforms show stem colours? Screenshot `ap3-move` during it. Measure CPU on the pinned process during the move.
4. **The end:** the old deck should stop, the new one should play, with `AUTO` unlit and a green tick message. All knobs back at centre, all stems up, no loop lit, no FX dot, and the new deck's BPM matching what was playing. Screenshot `ap4-done`.
5. Press it again straight after, with the old deck reloaded. Does it pick a different move?
6. Repeat with `jam1197771` into `jam1280420`.

Record the move, and where it left and arrived, each time.

### AQ. Taking over
1. **Calling it off:** press `AUTO`, then press it again during the countdown. Nothing should have changed, and the track plays on.
2. **Grabbing a knob:** during a move, turn the outgoing deck's `HI`. It should stay where you put it while everything else carries on. At the end it goes back to centre.
3. **Stopping mid-move:** press `AUTO` during a move. It should say the decks are yours and leave everything where it is. Can you carry on and finish the mix by hand?
4. **Moving the deck:** during the countdown, seek the playing deck well past where the move was to start. It should say it lost its moment.
5. **Changing the plan:** during the countdown, load another track on the waiting deck, or press its `PLAY`. It should call itself off and say why.
6. **Leaving the page:** during a move, open `BROWSE` and come back, and put the app in the background and bring it back. Does the move carry on correctly?
7. **Rough stuff during a move:** press `CUE` or a hot cue on either deck, change tempo, press `REV`, or eject. Nothing should crash, and it should end with the decks usable. Describe what each does.

### AR. `MIX`: Auto DJ through a list
Not run yet, and nobody but unit tests has pressed it. The key is in the browser's toolbar, and it mixes through the list on screen, in the order it's showing. Make a playlist of the three club tracks from AM.
1. **From nothing playing.** Open `BROWSE`, pick the playlist, and press `MIX`. Deck 1 should load the first track and start it, and deck 2 should load the next, with an `Up next` message. The mixer's `AUTO` key should read `MIX` and stay lit. Screenshot `ar1-start`. Does `MIX` fit in the toolbar at this size?
2. **Waiting.** Once stems are done, the key should count down as `MIX n`, and it shouldn't leave the track early. Record the bar it leaves on and how far through the track that is.
3. **The handover.** When the move ends, the third track should load on the deck that's just been freed. Record each move, and any message that goes by too fast to read.
4. **The end.** After the last track plays out, it should say that's the end of the playlist with a green tick, with `AUTO` back and unlit. Screenshot `ar4-end`.
5. **Starting mid-track.** With a track from the list already playing, press `MIX`: it should carry on from there. With one not on the list: it should carry on into the top of the list. With the last track of the list playing: it should refuse and say why.
6. **Stopping.** Press `MIX` or the mixer's key while it's waiting, counting down and moving. Before a move, the track plays on. During one, the decks are yours.
7. **Taking over.** During the countdown, load another track on the waiting deck, start the waiting deck, or pause the deck that's playing. Each should end the mix and say why.
8. **All tracks.** With `All Tracks` showing, sort by `BPM` and press `MIX`. Does it follow the order on screen? Does a search or filter change what it plays?
9. **Running out.** Start a mix on tracks whose stems aren't split yet, and seek close to the end of the first. The next track should start when it runs out, with a message. Say what the gap's like.
10. **Bass swap.** If a move is a `Bass swap`, the old track should rise and lose its low end for its last bar, then everything stops for one beat, and the new track lands whole. Screenshot `ar10-air` during the beat, if you can catch it.

### AS. `NEXT`: what should I play next?
Also not run yet, in the browser's toolbar. It puts the list in the best order to play from the deck that's leading, by tempo and key.
1. With a track on a deck, press `NEXT`. The track on the deck should leave the list, and the first few should be close in BPM with a compatible key. Screenshot `as1-next`. Does the order look sensible, going by the BPM and key columns?
2. Change the deck's tempo, or load something else. Does the list follow?
3. Tap a column header: it should take over from `NEXT`, and `NEXT` should go out. Press `NEXT` again and it comes back.
4. With `NEXT` on and nothing loaded: the first track should stay first, and the rest follow on from it.
5. With `NEXT` on, press `MIX`. Does it play them in the order showing?
6. With `IN KEY` or `±6% BPM` on as well, or a search: only what's left gets ordered.
7. Scrolling and typing in the search box with `NEXT` on: any hitch? On a big library if there is one.
8. Does the toolbar still fit, with everything readable, on the Duo, the iPad, and a small iPhone held both ways?

### Pressing harder
**A long run.** 10 minutes of everything, with Auto DJ running where you can: the changes since last time, and two-finger holds on anything that hasn't had one. A recording running throughout, so you can check for gaps. Crashes, dropouts, or a stop you can't explain?

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

Write `docs/COMPUTER_USE_RESULTS_7.md` like this:

```markdown
# Hands-on results, part 7, <date>

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
- Screenshot: docs/test-results-7/...
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
