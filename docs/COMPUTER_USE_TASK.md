# Cheeks: hands-on task

**Who this is for:** a Claude session with computer use (it can see the screen, click and drag). This is the only document you need.

**Your job:** set up as below, then run **the retest**, **not run for a while**, **the first-time user** and **pressing harder**, and answer **Part 3**.

**Rules:**
- **Don't change any code**, even if you can see the fix. A precise description is what's wanted.
- Record every test as PASS, FAIL or BLOCKED, based on what you actually saw. If you couldn't check it, it's BLOCKED, and say why.
- If something's blocked or the app crashes, record it and carry on. Get the crash report with `ls -t ~/Library/Logs/DiagnosticReports | grep -i cheeks | head -1` and copy it to `docs/test-results-19/`.
- Also note anything that merely looks wrong, even if the test passes.
- The sentence after each test is what the last test found. It's there so you can tell whether it changed, not to tell you what to see.

**What to hand back:** `docs/COMPUTER_USE_RESULTS_19.md` in the format at the end, with screenshots in `docs/test-results-19/`. Commit only those to `master`, with the message `Add hands-on test results, part 19`. **Don't push.**

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
mkdir -p docs/test-results-19
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
- **Screenshots:** `xcrun simctl io "$SIM" screenshot --display=primary-1 docs/test-results-19/NAME.png` for the inner screen. Please downscale them to about 1600 px wide before committing, to keep the repo small.
- **Reading the meters from video:** crop widths must be even. An odd width gets rounded by ffmpeg on 4:2:0 video, which shears every frame, and round 6's first figures were wrong because of it. Run a control that's known to be red before believing a 0%.
- **Check a reload really happened:** `playCount` in `library.json` goes up by one each time. A very busy Mac can take over 1 s to open the browser, so a load key tap sent too soon lands on the old layout. Allow about 1.5 s after `BROWSE`, and at least 5 s after a load key before seeking.
- **Load average is unreliable on this Mac:** it read 40 to 940 while the busiest processes added up to a few cores. Go by what the processes use.
- **Stopping a video:** `simctl io recordVideo` stops on SIGINT, and a background job in a non-interactive shell ignores that unless you restore it. Never send SIGTERM: that left the Duo's render server recording with nothing attached, writing up to about 650 MB a minute with the screen moving and about 9 MB with its app closed. Only a shutdown clears it, which folds the Duo, and that shutdown starts copying the temp file into a final video at about 300 MB/s, so it has to be followed at once by `kill -9` of that `SimRenderingServices` process. Find its PID first: `lsof -p PID` shows the recording's path. The space comes back within about 10 s.
- **Your touches aren't a UI test's.** A press along the top of the screen set off iOS's scroll-to-top for your tool and not for XCUITest, so a UI test passing doesn't settle anything near the screen's edges.
- **Can't be tested here, so don't report as failed:** haptics, how anything sounds, and the headphone output. List them under Tooling limits.

**Where things are:**
- **Top bar:** `SEGUE DJ`, `BROWSE` (it reads `DECKS` while the browser's open), a waveform icon (Recordings), `REC`, `MASTER n` and the tempo in the middle, then messages, the clock, `?` and the gear (Settings).
- **Waveforms:** overview, deck 1, a strip of beat blocks, deck 2, overview.
- **Decks** left and right with the **mixer** between them. Each deck has a header, a tempo fader at the outer edge, the jog, a column of keys (`BEAT SYNC`, `MASTER`, `BEAT JUMP`, `Q`, `SLIP`, `KEY`, `REV`, `−`/`+`, `KEY SYNC`), a row of controls for the current pad page, the tabs (`CUE MEM LOOP ROLL SLICER JUMP STEMS FX SAMPLE`) and eight pads. Round `CUE` and `PLAY` are in the bottom outer corner.

Load one track on each deck through `BROWSE` and the `1` and `2` keys, then close the browser. Each load starts splitting stems in the background, which uses a lot of CPU for a minute or two. Let that finish before anything that measures.

---

## The retest
To see what these were, look in `docs/COMPUTER_USE_RESULTS_18.md`, which ends with what was done about them.

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
1. **GB4: the tip, upright on the folded Duo.** The first time both decks play: "Two basslines clash. Turn the new track's LOW down, and swap the two LOWs as you crossfade." All of it. Is anything else cut, now that a message can take three lines? Does a third line cover anything that matters? *Last time: "The gear's guide h..."*
2. **N28: a mix from nothing on a track with its saved loop on.** Severe on deck 2 with its saved loop switched on in `LIST`, reloaded, nothing playing, `MIX`. The loop comes off, and it plans as usual. Set a loop by hand on a mix's track before it has a plan: "The mix will carry on when deck 2's loop ends." once, and `EXIT` lets it go on. *Last time: `MIX…` with no plan and no word for 2:30.*
3. **N29: `SYNC` and what's left over.**
   - Your own steps: Exhilarate playing on deck 1, `SYNC` on a stopped Gepzene on deck 2, stop deck 1, load Houston on it. Gepzene should go back to 128 and come off `SYNC`, and `SYNC` on deck 1 brings Houston to 128.
   - A deck that's run out: `SYNC` on the other, stopped deck says "Deck 2's track has finished, so there's no tempo to follow. Load the next one first." with a hand. Nothing moves.
   - A deck that's only paused still leads.
   - Both playing, the leader stopped by hand, the other 12% or more from its own speed: it stays at that speed, and says so.
   *Last time: 85 and 170, with two tracks 2 BPM apart.*
4. **N30: `Done`.** Upright on the folded Duo: scroll Settings, the guide, Recordings, a deck's `LIST` and a sampler pad's sheet. The title, and `Done` or the way back, stay. *Last time: gone from Settings on scrolling.*
5. **N31: an Echo throw's words.** No `STEMS` tip on one, by `AUTO` or `MIX`. In a mix, the tip waits for the first move it's true of. A Loop build still has it.

### GC. New this round
1. **The way back from `SYNC`.** On `UNDO`: "follows at half tempo" and "33% faster than its own" both offer it, and it puts the speed and the range back, with `SYNC` off. An ordinary small `SYNC` has none. In the `BPM` menu: `Back to Its Own Speed`, only when the deck's away from it. Under the BPM on a phone: `+33.3%` in blue while it's away. Does it fit at `WIDE`? Is it readable? Does it tell you what you want to know?
2. **`MIXER` says `SPLIT`.** On a phone it lights and says so under its name while that's on. Readable? Then the sheet: 280 pt upright, with its last line on the screen, and it says what the key with the arrows does. Is what's left showing above it useful?
3. **Nothing coming out.** Crossfader on deck 1, both playing, then stop deck 1, or let it run out: "Deck 1 has stopped, and deck 2 is playing with the crossfader away from it. Nothing's coming out." Moving the crossfader yourself gets no word. Nor should a move or a mix.
4. **Running out behind the browser.** On a phone, one deck playing and the browser open: "Deck 1 runs out in 29 s." at the last 30 s. Once a track. Nothing with the other deck playing, in a mix, or on a loop. Is that when you'd want it?
5. **The thumbs.** A tap counts. Pressing a thumb for over 0.25 s does nothing: no rating, and no seek. Does a tap ever fail? *Last time: a hold meant for the overview gave "Got it. Less like that."*
6. **`-00:00.4`.** `AUTO` waiting for stems on a track with silence at its end: it stops there and reads `00:00.0`. `PLAY` starts it again from its cue.
7. **`LIST`'s switch.** Off, with that loop still up ahead: it's gone from this load, and the deck runs past it. Off, with the deck in the loop: it stays in it.
8. **Messages that outlived their page.** `SLICE`'s tip goes as you leave its page. "Everything else here has been played" goes when the list changes.
9. **Words.**
   - "Moved the crossfader to the middle, to hear both."
   - "Mixing through all your tracks, 2 not played yet." with a track playing and some played. "2 tracks to go" with none played.
   - The first load's tip: "It's on the deck: DECKS takes you there. New to this? ..." Does three lines upright get in the way?
   - The notes for `HI`, `MID`, `LOW`, `FILTER KNOB` and `CUE/MST` say down and up.
   - `MIX TWO TRACKS`: "With one deck playing and the crossfader over on it".
   - Column headings with `?` on: a note, and no sort.
   - The playlist icon, upright: does it read as playlists?
   - `Stems 99% · a moment`.
10. **The tempo fader only moves from its cap,** or within 8 pt of it. On the small iPhone on its side: a drag up its column away from the cap moves nothing, keeps `SYNC` on, and says "Drag the tempo fader by its cap. A stray touch can't change the speed." A drag from the cap moves it, as before. Double-tap isn't something your tool can do. Did you ever miss it when you meant to grab it? And can a drag meant for the platter still take it? *Last round but one: 125 to 141.77 by accident.*
11. **`RELOOP` during a held `SLICE` or `ROLL` pad.** The first-time user saw it orange on orange and hard to read, at 03:00:50 last time. A screenshot, please, on the small iPhone. I'd expect `EXIT`.

## Not run for a while
These weren't asked for last round. From **Part 1**: **A1, B1, C1, C2, C3, C5, C6, D2, D3, D4** and **D11**. From **Part 2**: **G, H** and **I**. The rest passed last round.

## The first-time user
Forget everything above. Uninstall, install, and open the app as someone who's never seen it and has some music in Files. Stay away from the repo's docs and code, and say what you can't un-know.

**How to start it:** the `Explore` subagent type gets no CLAUDE.md or memories, and it has Bash and the touch tool. Say in its first brief that it may write screenshots and a report to one folder, or it won't. Keep its early screenshots, as it can't look back at them itself. **On `iPhone 17` on its side this time,** if it's free, or on the Duo unfolded if that's open: nobody's learned the app on an ordinary phone, which is what most people have. Make sure no backups are in its Files.

**Give it the full 45 minutes.** Let it find its own way, and look out for these:
- How long until it can say what Auto DJ does to a track? Last time 13:25, from the `STEMS` tip.
- Does anything still stay changed with nothing on the main screen to show it? That was the worst thing last time.
- What's still doing nothing with no word?

1. Every moment you weren't sure what to do, what you tried first, and how long each stage took. Screenshot each, as `fu-*`.
2. **Use `?` as you go.** What's still a mystery after it? Which note was wrong, or didn't help?

### Pressing harder
**A long run.** 15 minutes, with `MIX` and `AUTO` running, and taking over as many ways as you can, including pressing things just as a panel slides, and with `DUB` chosen throughout. **Hand back in a build's last bars at least twice,** with `AUTO` and with `EXIT`, and a Bass swap at least once. A recording running throughout, so you can check for gaps, and music on throughout. Afterwards the decks should always be usable, with nothing left silent, looping or filtered that the screen doesn't show. Crashes, dropouts, or a stop you can't explain? On the Duo if it's open, and on the small iPhone if not. **At least one seek past a mix's exit,** one load on the waiting deck, one load on a mix's last track, and one mix started on a track with its saved loop on.

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

Write `docs/COMPUTER_USE_RESULTS_19.md` like this:

```markdown
# Hands-on results, part 19, <date>

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
- Screenshot: docs/test-results-19/...
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
