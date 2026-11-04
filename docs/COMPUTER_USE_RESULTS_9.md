# Hands-on results, part 9, 2026-11-02 and 03

Commit tested: a9d454b
Device: iPhone Duo simulator, unfolded (951×669 pt, `hingeState` OpenFlat, read before starting), and `iPhone SE Cheeks` (667×375 on its side, 375×667 upright). iOS 27.2. Both fresh installs of `com.nikhilpatel.seguedj`, driven by real touches. The old `com.nikhilpatel.cheeks` is uninstalled from both.
Tooling limits:
- **The Mac slept in the middle.** The lid was closed from 22:16:24 until 10:52:40 next morning (`pmset`: Clamshell Sleep, on battery). Everything after that ran on AC, once the lid was open. See **After the Mac's sleep** below. Load average was over 700 at first, and I say what it was beside anything timed after it.
- **Not judged:** how anything sounds, haptics and the headphone output. Levels and gaps come from recordings and video, and nothing here says a move sounds good.
- **With two fingers:** both land together and the second slides. I say which way round where it matters.
- **Tool lag:** a tool call takes 1 to 4 s when chained, and 10 to 60 s when not, so I can't hit a chosen beat. A capsule can be gone before I reach it.
- **The Mac was busy:** on the first evening another project's jobs (`strip_kill`'s `diff_budget.py` and `llm_tcq_model.py`) were running, using 1 to 89% of a core each, and other simulators were booted. They couldn't be paused. Timings are noisy, and the CPU table says what was running beside each figure. The other session was also building on `iPad Air 13-inch (M4)` at low priority during the long run.
- **Files:** `On My iPhone` also holds `Cheeks Library 2026-10-30.json`, an old backup from round 1. That isn't the app's name showing.

## Summary
90 tests: **75 PASS, 6 FAIL, 0 BLOCKED, 9 just reported** (BD, the first-time user's five and three of the big library's, which ask for what I saw). No crashes: there are no Cheeks or Segue crash reports from this round.

Everything from round 8 is fixed: `AUTO` and `MIX` with a loop, `Mix off`, loading mid-move, pausing in the countdown, `REV`, the empty lists and the tracklist all pass. Undo worked 4 of 4 on the Duo and on the small iPhone. Both decks on the jog stay whole upright.

The problems, most important first:
1. **A3: idle CPU has come back on the decks page.** Nothing loaded is 12.9 to 15.5%, and two tracks paused is 16.4%. With the browser open over the same state it's 2.8 and 3.7%, and in round 2 the decks page was 3.6 and 4.5%. A video of the paused screen has one changed frame in 8 s.
2. **BA5: the app promises a Files folder that isn't there.** Three screens say to use the `Segue DJ` folder in Files, including the first thing a new user reads. Files has no such folder. The Import key does work.
3. **LR1: `AUTO` after a stopped move can run 15 dB quiet for 47 s.** It mixes out of what the stopped move left on the new deck, and the audition doesn't catch it.
4. **J3: Severe Tire Damage's tempo jumped from 178 to 148 while it played,** when its stems finished. It's the drums correcting the grid, by a much bigger step than a correction.
5. **BA4 and B2: the logo.** On the Duo the launch screen's logo crossfades to the app's, which sits about 17 pt higher, so it's doubled for a moment. The logo also now covers the meters' launch sweep: nothing to see in 4 of 5 launches, and only its tail in the fifth.

### After the Mac's sleep
This only says something about the simulator after a Mac sleep, not about a phone.
- **While asleep:** deck 2 was looping when the lid closed. Its clock stuck at 02:41.3 with `PLAY` lit and its meter part way up, and `AURemoteIO::IOThread` was waiting with no cycles arriving. Two presses of `PLAY` during a dark wake did nothing visible.
- **After waking:** at 10:54, within 2 minutes of the lid opening and with nothing pressed, the deck was running again by itself, going round its loop (02:41.5, 42.7, 41.7, 42.5, 41.5, 42.4), with the meters moving and the audio thread in `PerformIO`. Same process, no restart, no message, and the deck hadn't lost its loop. I couldn't time it any closer. The load average was 753 then, so if it came back slowly or stuttered, that could be the Mac.

## Failures

### A3: idle CPU is 13 to 16% on the decks page
- Steps: the method in the task, on this simulator's process. Stems were finished.
- Expected: low at rest, rising with the work, as in round 2.
- Actual: see the table under **Timings and measurements**. Every decks-page state is about 8 to 12 points over round 2. Opening the browser over the same state drops it to about 3%, so this isn't the Mac's load.
- Lead: while paused, 783 of the main thread's 2,983 samples were in `_UIHostingView.layoutSubviews` → `ViewGraph.render` and `beginTransaction` → `updateGraph`, with nothing visibly changing. The app's own frames there were led by `PadTabs.body` and `PadTabs.tab(_:)`, then `EngineLoad.body`. `PadTabs` isn't on screen with the browser open. I didn't go further than that.
- File: `docs/test-results-9/a3-idle-sample.txt`

### BA5: no `Segue DJ` folder in Files
- Steps: open Files, `On My iPhone`, on a fresh install with music imported and a recording made.
- Expected: a `Segue DJ` folder, as these say: the empty browser ("drop audio into the Segue DJ folder in the Files app or Finder"), the empty Recordings ("Recordings also appear in the Files app under Segue DJ › Recordings") and Settings ("Backups folder in the Files app").
- Actual: no such folder. The picker doesn't offer it either.
- Lead: `Info.plist` has `LSSupportsOpeningDocumentsInPlace` false and `UIFileSharingEnabled` true, which gives Finder sharing only.
- Otherwise the name's right: the home screen, the top bar, the empty lists, Settings, the backup's name (`Segue DJ Library 2026-11-02.json`), the `.cue`'s performer and the tracklist. `CFBundleName` and the executable are still `Cheeks`, which nobody sees.
- Screenshots: `ba5-files-on-my-iphone`, `fu-empty-browser`, `fu-se-recordings-empty`

### BA4: the logo jumps at the handover on the Duo
- Steps: a normal launch on the Duo, on video, frame by frame.
- Expected: the logo stays put.
- Actual: the launch screen's logo crossfades to `OpeningCover`'s, which sits about 17 pt higher, label and platter both. Both show for about 0.1 s.
- No black or blank moment, fresh or normal. On the small iPhone, both ways up, I saw no doubling or jump. I only went frame by frame on a normal launch on the Duo.
- Screenshots: `ba4-logo-handover`, `ba4-logo`

### B2: the launch sweep can't be seen
- Steps: terminate and relaunch, on video, five times.
- Expected: the meters run up and back once, in the first second or so.
- Actual: on 4 of 5, no LED lights at any frame after the logo, which went between 1.1 and 5.5 s after launching. On the fifth, with the logo gone after about 1 s, only the falling tail shows, for about 0.6 s.
- Lead: the sweep is timed from launch (`WaveformLive.swift:653`, 1.1 s), so the logo now covers it. It passed in round 2, before there was a logo.
- Screenshot: `b2-launch-sweep-tail`

### J3: Severe Tire Damage's tempo jumped from 178 to 148 while it played
- Steps: play the two test tracks for the first time, and watch the readouts for 2 minutes.
- Expected: they stay still.
- Actual: Exhilarate stayed at 170.59, and Severe Tire Damage at 178.00 for the 1 min 48 s I sampled. Then at about 2:50 into the track, when its stems finished (99% at 11:03:54), it read 148.00 from then on. Nothing said so. The library has it as `gridSource` `drums` in place of `analysis`, with 5 sections in place of 11.
- This is one step and not a tempo map changing as it goes. It's what the drums correcting a grid looks like (`Deck.applyTrackMap`). What's new is the size, a 30 BPM change on a playing deck. 178 to 148 isn't a half or a double.
- Which is right: I can't say. Two rough checks of the file from its onsets didn't pick out either. `tools/autodj/compare_map.py` would be the way.
- Screenshots: `j3-readouts`, `j3-severe-before`, `j3-severe-99-percent`

### LR1: `AUTO` after a stopped move mixes out of what it left on the new deck
- Steps: both decks playing in a Bass swap (Skylander to Gepzene). Press `AUTO` before the handover, which says "Auto DJ stopped. The decks are yours." and leaves Gepzene on `DRUMS` only with `MID` down, as the screen shows. Press `EXIT` on Skylander's own loop and stop it. Press `AUTO`.
- Expected: as in BB2, everything the move left should go, and it should plan and get there sounding like one.
- Actual: "Bass swap in 9 bars", and `DRUMS` only and `MID` down stayed on Gepzene for the whole move. From the recording: -12.6 dB before stopping Skylander, then -25 to -28 dB for 47 s, until the swap landed at -12.7 dB. So that's 15 dB down for 47 s, with 0.42 s at -58 dB right before the landing, in a move that passed its audition. It finished properly, "Bass swap done. Deck 2 is on.", with Gepzene stopped and put back to neutral.
- Lead: only the old deck is remembered (`leftBehind = outgoing`, `AutoDJ.swift:717`), and `getReadyToLeave` only clears that one (`:408`). Here the deck being mixed out of was the stopped move's new deck. I ran this once.
- Screenshot: `lr1-auto-after-stop-drums-only`

## Looks wrong

**Auto DJ**
- **`AUTO…` gives up in silence.** Waiting for stems, the playing deck ran out, and the key went back to `AUTO` with no message (`AutoDJ.swift:578`). Someone who walked away would never know why nothing happened.
- **BB4 looks stuck.** With a mix waiting on a loop, the message goes after about 6 s and the key's a plain `MIX` with no number. Only the lit `EXIT` hints at why.
- **`DSP n%`** shows in amber or red in the top bar during plans and loads, up to 335% here. The Mac being busy is why it's that high, but it reads as a fault, and it means nothing to a DJ.
- **BC4:** in one of two runs, an Echo throw that ended with the old deck stopped, my log of the top bar never caught "Echo throw done". It caught it on other moves. I can't force this, and it may be the log. It also missed the last move of the long run, but the Mac's load jumped from 16 to 247 right then, so that one could easily be the log.
- **A seek on the old deck during a Loop build gets undone with no word.** 5 s into the move I tapped the overview, and the deck went to 2:16. It ended stopped at 1:17, in the score's loop, so the score took it back about a minute. It finished cleanly. In a mix's countdown, a seek just replans, which is better.
- **The crossfader stays where you put it after a move,** which is right and is what the rules say. It does mean a hand that dragged it to the old deck's side leaves the new deck at -33 dB when the move ends, and nothing says so beyond the cap's position.

**Decks and pads**
- **F2: `SAVE CUE` on a stopped deck saves the cue point, not where you've moved to.** Parked at 1:31 by the overview, it made a pad at 0:00, and a second press said "There's already a memory cue here." It's written to do that (`Deck+Performance.swift:87`), but the deck was nowhere near there.
- **H2: nothing says a pad slides.** Up and down is `DEPTH`, and left and right changes the beat length. A slide of 2 to 3 pt counts as a tap, which turned the effect off twice.
- **`DEPTH` and `VOLUME` go by how far you drag,** not where you touch (`PadSection.swift:703`). A drag from the middle can't reach the end, and tapping the bar does nothing. `VOLUME` at 10% still reads halfway up the meter. At 0 it's silent.
- **I2: `SPACE` lights `LIM` and the top of the meter** either way of the knob, for as long as it's away from centre, on a loud part. The meter also halved for about 0.5 s as it came back to centre, twice, which may be the music. `DUB` touches red briefly. The other four stay amber.
- **An empty deck takes presses and doesn't say so.** See FU5. `REV` stays red and `SLIP` blue on a deck with nothing on it.
- **A held tap on the BPM menu:** with the menu open, a tap in the top bar didn't close it (still up 12 s later). The next tap only closed the menu, and on the CUE page the one after fired a hot cue where I'd expected a stems pad.
- **A relaunch leaves both decks empty.** That may be deliberate. It's the first thing you see each time.

**Browser**
- **The list goes back to the top** each time the browser reopens. With 2,000 tracks that's a long way.
- **Search:** typing with 2,005 tracks showed a dim row of the old list (`Track 0`) for about 1 s before the results. The keyboard leaves about 2.5 rows on the Duo.
- **A partial swipe on a row** leaves a blue `Deck 1` action showing. Tapping it later did nothing I could see.
- **A new playlist isn't selected** after creating it. `Add to Playlist` also offers that day's History.
- **The file picker:** blank for 3 to 8 s here. Behind it the mixer shifts down about 170 pt and the deck strip goes, until it closes (`fu-picker-layout`).

**Small iPhone**
- **Upright, the status beside the gear is cut to "A…"** while analysing, and the browser's top bar has no name, on its side as well.
- **Upright, the browser shows no decks,** so nothing can be started from it. `IMPORT` is an icon with no word.

## All results
| Test | Result | Notes |
|---|---|---|
| BA1 | PASS | Launch to logo about 0.6 s, logo to decks 5.6 s. Nothing "timed out". A fresh install opens on the browser, at "No music yet". |
| BA2 | PASS | Three launches: logo to decks 1.4, 1.4 and 2.1 s. Nothing "timed out". The SE upright took 5.3 s once on the busy Mac. |
| BA3 | PASS | Knobs, keys, fader caps, `CUE` and `PLAY` match round 8 up close, lit and unlit. Nothing blank. `ba3-parts`. |
| BA4 | FAIL | Doubles and jumps about 17 pt at the handover on the Duo. No black moment anywhere. |
| BA5 | FAIL | No `Segue DJ` folder in Files. A person sees "Cheeks" nowhere that's the app's. |
| BB1 | PASS | The loop goes, "Loop build in 4 bars", and it gets there. |
| BB2 | PASS | Stopped at about 24 s. `AUTO` again cleared the loop, `LOW` and filter, "Loop build in 8 bars" ran. `bb2-again`. |
| BB3 | PASS | "Auto DJ stopped: deck 1 is in a loop." `bb3-loop-in-countdown`. |
| BB4 | PASS | "The mix will carry on when deck 1's loop ends." `EXIT` planned again, `MIX 28`. It does look stuck while waiting. `bb4-mix-loop`. |
| BB5 | PASS | The loop goes at once, `MIX 70`. |
| BC1 | PASS | "Mix off. The decks are yours." before landing and in a Vocal ride. "Mix off. Deck 2 is on." after. In the countdown: "Mix off. The track playing just carries on." `bc1-mix-off-early`, `bc1-mix-off-late`. |
| BC2 | PASS | "Auto DJ stopped: the track changed. Deck 1 carries on." No loop, knobs centred, every stem on. `bc2-load-mid-move`. |
| BC3 | PASS | "Auto DJ stopped: deck 1 was stopped." In a mix: "Mix off: deck 1 was stopped." `bc3-paused-countdown`, `bc3-mix-off-paused`. |
| BC4 | PASS | 2 of 2: an Echo throw and a Loop build. `REV` off once the deck stopped. `bc4-rev-off`. |
| BC5 | PASS | `IN KEY` or `±6% BPM` emptying a list says to turn them off. An empty playlist says how to add. A search gets "No Results for…". `bc5-empty-playlist`. |
| BC6 | PASS | 00:00 Skylander, 00:24 Gepzene, 00:44 Skylander, all where the audio started. Stopping 2 s and restarting added no line. History rose by the same three. |
| BC7 | PASS | Upright on the SE. The rating and Undo capsules are readable. Thumbs up saved with a default tap, and `UNDO` brought the cue back. Taps under the capsule reached the overview and `±6%`, but it covers `KEY`, `±6%`, `NEXT` and part of the search field. Thumbs down I only pressed on the Duo: "Got it. Less like that.", saved. `bc7-rating-se`, `bc7-undo-se`, `bc7-browser-capsule-se`. |
| BC8 | PASS | Both whole, keys in two columns. `PLAY`, `CUE`, `Q`, `REV` and `KEY SYNC` all worked with the other jog moving. Pads and tabs back where they were. A very fast jog as the second finger (40 ms a step) didn't move it, 2 of 2, while 60 ms did, and so did a fast first finger. That may be the tool. `bc8-both-jogs`. |
| BD | Reported | Three matches. No hole in the two I recorded. Nothing said it couldn't find a way, in about 30 moves. See below. |
| FU1 | Reported | Got to a mix and to Auto DJ on both screens. See below. |
| FU2 | Reported | All clear except the promise of a Files folder. See below. |
| FU3 | Reported | Noticed, explained, no estimate. See below. |
| FU4 | Reported | See below. |
| FU5 | Reported | Refusals are clear, but a lot is silently ignored. See below. |
| BIG1 | PASS | Logo gone 1.0, 5.2 and 5.5 s after launch, with 2,005 tracks. With 5 tracks it was 1.1 to 2.8 s, so this is mostly the busy Mac's noise. |
| BIG2 | Reported | Stalls of 150 to 630 ms. See below. |
| BIG3 | Reported | Stalls of up to 800 ms. The recording has no dropouts. See below. |
| BIG4 | Reported | See **Timings and measurements**. |
| Pressing harder | PASS | 16 min 6 s with `MIX`, `AUTO` and 12 ways of taking over. No crash, no dropout, no stop I can't explain, and the decks stayed usable. See below. |
| LR1 | FAIL | Found in the long run: `AUTO` after a stopped move keeps that move's stems and EQ on the deck it's mixing out of. |
| A1 | PASS | 4 of 4: default tap and 0.2 s, paused and playing. The cue came back at 3:24 and the capsule went. `a1-undo`. |
| A2 | PASS | Tap and full swipe: not loaded, "Deck 1 is playing. Stop it first." with a hand. The shake shows on video. `a2-refused`. |
| A3 | FAIL | 13 to 16% at rest on the decks page, 3% with the browser open. |
| B1 | PASS | Four toggles on video: no LED lit in any frame, either place the mixer sits. A control with a pad playing found lit frames. `b1-meters`. |
| B2 | FAIL | The logo hides it. |
| B3 | PASS | Right of the `MASTER` readout, whole number readable. |
| B4 | PASS | 10 of 10 centred and green over 2 minutes, across a hot cue jump. The eleventh was white, as deck 1 had just run out. `b4-marker`. |
| B5 | PASS | The jog read 126.00 within 0.3 s of closing. |
| B6 | PASS | 130.92 on each deck's header and jog. The menu's title: "Beat grid: 126.00 BPM at normal speed". `b6-bpm`. |
| C1 | PASS | Index line within 1 px at 3× of the centre tick and the LED. `c1-caps`. |
| C2 | PASS | +2 pt stays on centre, +3 leaves it, the same each way. About 2.5 pt. |
| C3 | PASS | The mixer stayed, the search field's visible. `c3-keyboard`. |
| C4 | PASS | Both offered. `Keep recording` carried on, `Stop and save` saved with a tick. `c4-alert`. |
| C5 | PASS | Default taps at y 640 to 655: `PLAY` on both decks and bottom pads on both, first time each. Crossfader at y 635. No system gesture. `c5-bottom`. |
| C6 | PASS | Default 10 ms taps at y 6, the very edge: gear 1 of 1, `REC` 2 of 2. `BROWSE` 2 of 4: it missed twice last night, right after other screens closed, and worked twice this morning on a settled screen. A 0.2 s press always worked. No system gesture. |
| C7 | PASS | "Severe Tire Damage - Hi…" in the list, and two lines on the compact decks. `c7-titles`. |
| C8 | PASS | The counter sits on a dark pill, and the loop's line stops at the pill's edge, with no line through the text. `c8-counter`. |
| C9 | PASS | All nine the same size. `SAMPLE` and `DEL` are about 3 pt apart: tight but readable. |
| D1 | PASS | `SOLO` stays lit, and a second tap restores what was on. `d1-solo`. |
| D2 | PASS | On video at 6 frames a second: four quick taps flash white and settle in about 0.3 s. A slicer pad held 2.5 s stayed clearly brighter, with `EXIT` lit, and let go cleanly. |
| D3 | PASS | Lit for the sound's length: `RISER` about 4.5 s, `SIREN` about 2 s. |
| D4 | PASS | `IN` lit, with an orange mark on the overview before `OUT`. It had scrolled off the big waveform by my screenshot. |
| D5 | PASS | The new title was there in the first screenshot after the load key. |
| D6 | PASS | `Stems 2%` on the compact decks at once. |
| D7 | PASS | 32 before, during and after a `ROLL` held 1.2 s. |
| D8 | PASS | An 8-beat loop running, deck stopped, new track loaded: no loop on it, `RELOOP`, length back to 4. |
| D9 | PASS | `.m4a`, `.cue` and `.txt` all renamed. The `.cue`'s `TITLE` and `FILE` and the `.txt`'s heading use the new name. |
| D10 | PASS | The mint layer has the music's shape, though thin on Houston. `d10-stems`. |
| D11 | PASS | Dragging the bar moved it, 60% to about 20%. |
| D12 | PASS | Normal, then stem colours with a dim ghost, then normal again. `d12-muted`. |
| E | PASS | The log query lists nothing, with 905 other Cheeks lines in the same 5 minutes. Pause shows while playing, play once paused, and play again when a 0:23 mix ended. |
| F1 | PASS | As described. `f1-mem`. |
| F2 | PASS | One red pad, second press refused with a hand, triangles on the waveform and overview. See **Looks wrong** about 0:00. |
| F3 | PASS | "Set a loop first, then save it." Then an orange pad at 1:47, with the bar. |
| F4 | PASS | Jumped to it and held 4 s, lit. Tapped again: the loop ended and the deck ran on. |
| F5 | PASS | "Deleted memory cue" with `UNDO`. `UNDO` brought it back straight away. Tried 8 s later, the capsule had gone. |
| F6 | PASS | Name and colour reach the pad and flag. Reloaded with the loop's toggle on: `ARMED`, and the deck stayed at 0:00. The toggle and the colour well wanted a press of 0.3 s. `f6-list`. |
| F7 | PASS | Cue, colour, name, memory cue and armed loop all there after relaunching. |
| G1 | PASS | `SET`, `Q`, `VOLUME`, `STOP`, and all eight fire. |
| G2 | PASS | Grab offered for deck 1 with its loop, and not for deck 2 with none. `g2-sheet`. |
| G3 | PASS | Gate: sound only while held, at 0.3 and 0.8 s. Loop: one tap starts, the next stops. |
| G4 | PASS | `LOOP 1`, and it goes round. |
| G5 | PASS | Red timer in place of `SET`, then a pad named `REC 3`. The meters move with the deck stopped. |
| G6 | PASS | Back to `RISER`. |
| G7 | PASS | Silent at 0 on the meters. `STOP` stops a looping pad. |
| H1 | PASS | `ECHO` goes out on the fourth, the others stay lit. `h1-chain`. |
| H2 | PASS | Each keeps its own `DEPTH`: `CRUSH` 85%, `TRANS` 3%. |
| H3 | PASS | Lit, explained, meters dark within 3 s, clock running. Back further along, at full level. |
| H4 | PASS | "Echo out needs the deck playing." Paused and played during one: back at full level. |
| I1 | PASS | Cycles through all six, and both labels follow. `i1-color`. |
| I2 | PASS | Nothing silent and no crash, both ways on all six. Double-tap centres. See **Looks wrong** about `SPACE`. |
| I3 | PASS | The meters ran on about 3 s, falling. |
| J1 | PASS | Houston 6: CHORUS VERSE CHORUS VERSE CHORUS OUTRO. Gepzene 4: CHORUS UP CHORUS OUTRO. Severe Tire Damage 11: INTRO CHORUS UP CHORUS UP CHORUS VERSE CHORUS VERSE CHORUS OUTRO. Exhilarate 4: CHORUS VERSE CHORUS OUTRO. Skylander 6: INTRO CHORUS DOWN UP CHORUS OUTRO. `j1-phrases`. |
| J2 | PASS | Counts up, and each section starts again: Gepzene read CHORUS 54.4, then UP 6.4, then CHORUS 13.1, and Exhilarate VERSE 1.2, then 5.3. |
| J3 | FAIL | Exhilarate steady. Severe Tire Damage went from 178 to 148 once, as its stems finished. The club tracks stayed still throughout. |
| K1 | PASS | Saved through the picker, "Backup saved." |
| K2 | PASS | Deleted hot cue E, restored from the backup: "Restored 5 tracks and 3 playlists." The cue's back, on the pad and in the library. |
| K3 | PASS | Warning triangle and a dim title. "Houston's file is missing. Import it again and it'll get its cues back." with a hand. Not loaded. `k3-missing-file`. |
| K4 | PASS | Picked up from `Documents/` on relaunch. The triangle's gone, and both cues, the name, colour, memory cue and saved loop are still there. |
| K5 | PASS | `Documents/Backups/` has `Segue DJ Library 2026-11-02.json` and `2026-11-03.json`, one a day. |

### BD: when nothing else will do
About 30 moves in every order I could. Nothing said it couldn't find a way, and I never saw "No clean way in".

**Echo throws where the new track starts in its first third with its tempo at +0.00:**

| Pair | When | New track at the end | Recorded? |
|---|---|---|---|
| Skylander (125) to Severe Tire Damage (148) | `AUTO` | 0:15.9 at the end of a move of about 15 s, so from its top | Yes |
| Severe Tire Damage (148) to Houston (126) | `AUTO` | 0:13.6 likewise | No |
| Exhilarate (170) to Gepzene (128) | `MIX` | 0:23.9, 3 s after the end | Yes |

Screenshots: `bd-echo-from-top-severe`, `bd-echo-from-top-houston`

- **The first join, against the file:** -12 to -13 dB before, up to -9 or -10 dB for about 1 s where they meet, and then the old track's echo falls to -27 dB within about 1 s. From there the levels follow Severe Tire Damage's own opening second by second (-25, -26, -17, -16, -23…), so what looks like a dip is the track's quiet intro. No gaps. It does leave people at -16 to -26 dB for 11 s, until that track's chorus.
- **The third join:** -16 dB under the throw, then -13 to -14 dB as Gepzene comes in. Gepzene's own drop-out at 0:14 shows at -30.9 dB, as it does in the file (-26 dB). No hole.
- **Two near-matches from the top but not at +0.0:** Skylander to Exhilarate (38 bars, 0:00.4, tempo -0.35%, 170.00), whose join went -16 dB, then -12 to -13 dB for about 9 s, then -16 dB, so a 3 to 4 dB bump with no gaps. And a Loop build from Severe Tire Damage to Exhilarate at the same -0.35%. Exhilarate reads 170.59 on its own, so that looks like a small correction and not stretching to match.
- **What else it chose:** it varied, with one rating at most: Loop build, Bass swap, Echo throw, Vocal ride and Brake drop (Exhilarate to Gepzene, and Severe Tire Damage to Houston). I never saw a Vocal tease. Big gaps in tempo mostly got a Loop build or an Echo throw, and both worked.

### Pressing harder
11:23:14 to 11:39:20, so 16 min 6 s, with a recording running throughout. Load average 10 to 23 until 11:37:47, then 247 at 11:38:47 (another simulator running at 89%, not one of mine), which only touches the last move.

| Time | What I did | What it did |
|---|---|---|
| 11:23:15 | `MIX` with Severe Tire Damage playing | Skylander loaded by itself, `MIX 103` |
| 11:23:45 | `IN`, `OUT` in its countdown | "The mix will carry on when deck 1's loop ends." |
| 11:24:01 | `EXIT`, then the key, then `AUTO` | "Mix off. The track playing just carries on." "Loop build in 23 bars." |
| 11:24:58 | Turned the old deck's `MID` down during the build | It stayed where I put it. Ended "Loop build done. Deck 2 is on.", with the knob back to centre and the deck stopped |
| 11:26:02 | Bass swap, stopped the new deck 3 s in | "Auto DJ stopped: deck 1 was stopped. Deck 2 carries on." The new deck's tempo and `MID` went back |
| 11:26:31 | Bass swap, stopped the old deck 4 s in | "Auto DJ stopped: deck 2 was stopped. Deck 1 is on." |
| 11:27:17 | Echo throw, pressed Home 4 s in, back 10 s later | It finished while away, and the recording carried on |
| 11:28:27 | Loop build, dragged the crossfader over and moved the old deck | Finished. See **Looks wrong** |
| 11:29:26 | `MIX` again | "Up next: Gepzene", then an Echo throw with thumbs down, "Got it. Less like that." |
| 11:31:30 | In its countdown: `ECHO` on, `HI` down, seek on the old deck | It planned again from there. A Loop build ended with the effect off and the knob centred |
| 11:32:20 | `PLAY` on the waiting deck in its countdown | "Mix off: you started deck 2 yourself." |
| 11:32:40 | Muted the waiting deck's vocal, then a Brake drop | My mute stayed on the new deck, shown in stem colours |
| 11:33:33 | Loop build: jog and tempo fader on the old deck, `BEAT SYNC` on the new | Finished. The tempo I set stayed |
| 11:35:01 | Bass swap: my own loop on the old deck, then `AUTO` | "Auto DJ stopped. The decks are yours." My loop and what the move had left all stayed, shown |
| 11:35:20 | `AUTO` with both playing | "Auto DJ brings in a stopped deck. Stop the one you want next." with a hand |
| 11:35:29 | `EXIT`, stop, `AUTO` | LR1 |
| 11:36:44 | `MIX` from the list's last track, and in a one-track playlist | "There's nothing after this track in all your tracks." and "…in One." with a hand |
| 11:37:17 | `AUTO`, a Loop build | Finished cleanly, with the old deck stopped. My log missed its message during the load spike |

- **Gaps:** 966 s, with 241 runs of 30 ms or more under -50 dB.

  | Where | Runs | Longest |
  |---|---:|---:|
  | Before the first `PLAY` | 1 | 1.11 s |
  | Houston, in a Bass swap's tail | 1 | 0.08 s |
  | Gepzene, on its own | 101 | 0.35 s |
  | Gepzene on drums only (LR1) | 138 | 0.42 s |
  | Severe Tire Damage, Skylander, Exhilarate | 0 | |

  Gepzene's own file has the same pattern, 52 runs in its first 40 s, because it stops between hits. So I found no dropout, though on a track this sparse a very short one could hide.
- **The tracklist:** 13 lines, each matching a change of track and with its tempo at the time. Going back to a track gets a line every time.
- **Afterwards:** deck 2's `PLAY` and clock were fine (1:55.7, 1:57.8, 1:59.7, 2:01.8 at 2 s apart), meters moving, knobs centred, no loop, and every stem on. `lr-after-usable`, `lr-end-of-move-clean`.
- **Nothing was left silent, looping or filtered that the screen didn't show.** The closest is LR1, and the screen does show that.
- **The app's log:** only 4 `CVPixelBufferCreate` errors in the 16 minutes. No crash report.
- **CPU and memory:** see **Timings and measurements**.

### The first-time user
**FU1: from nothing to a mix.**

| Stage | Duo | SE upright |
|---|---|---|
| Open | 20:28, on the browser, told to import | 21:24, the same |
| Music in | 20:31, about 3 min including looking for the folder it promises | 21:25:43, about 1 min |
| On a deck | Obvious: `1` and `2` on each row | Obvious |
| Playing | 20:32 | 21:28 |
| Second one in time, mix across | Straight away: `BEAT SYNC`, crossfader | Stuck: `BEAT SYNC` isn't on the pads view |
| Auto DJ | 20:32, then waited for stems | 21:29, then waited for stems. Loop build done 21:33 |

Where I wasn't sure:
- **Files (both):** the message sends you to a folder that doesn't exist. `IMPORT` is the way, and its picker opens on an empty Recents, so you have to find `Browse` yourself.
- **Sync (SE upright):** `BEAT SYNC`, the tempo fader, `Q` and `KEY` are behind `JOG`, which says nothing about them. `fu-se-sync-behind-jog`.
- **The mixer (SE upright):** `TRIM`, `MASTER`, `SPLIT` and `FILTER` are in a sheet behind an unlabelled icon under `AUTO`. `fu-se-mixer-sheet`.
- **`AUTO` (both):** my crossfader moved back to the centre by itself with no word about it.

On its side, the SE is much the easiest of the small layouts: both decks with pads, and the browser's toolbar has its words. `fu-se-side`.

**FU2: empty screens.** The browser, Recordings and a playlist each say what to do next, though two promise the Files folder. The decks say "No track loaded / Open the browser to load one", and the jog "NO TRACK". The pads with no track are just dark. `fu-empty-browser`, `bc5-empty-playlist`, `fu-se-recordings-empty`.

**FU3: stems.** You notice: `Stems 2%` is in the deck header straight after loading. `AUTO` says "Auto DJ is waiting for the stems to finish." and reads `AUTO…`. There's no estimate. The header's percentage is all you get, and it's slow here: 12% at 40 s, 28% at 55 s, about 3 minutes for two. `fu-auto-waiting-stems`.

**FU4: what I couldn't work out by looking.** `Q`. `SLIP`. `KEY` beside `KEY SYNC`. `MASTER` on a deck next to `MASTER` on the mixer. `BEAT JUMP`'s 4. `MEM`, `SLICER`, `ROLL` and `JUMP` until tried. `DEL`, which is only on two pages. `SPLIT`. `CUE/MST` and `LEVEL`. `LIM`. The ↻ on `FILTER`, and that it changes both knobs' job. `±10`. `ARMED`. `AI` on the stems page. The strip of blocks between the waveforms. `NEXT`. On `FX`: `V I B D`, `OUT`, `1/2`, and that pads slide. `DSP`.

**FU5: doing it wrong.** With nothing loaded: `PLAY`, `CUE`, `IN`, a hot cue pad and `BEAT SYNC` do nothing and say nothing, and I saw the same from `OUT`, `RELOOP`, `MASTER`, `BEAT JUMP` and `KEY SYNC`. `NEXT` gives no message either. `AUTO` is the exception: "Play a track first, then Auto DJ can mix out of it." with a hand. Each refusal I did get is clear: loading a playing deck, `AUTO` with both playing ("Auto DJ brings in a stopped deck. Stop the one you want next."), `REV` at the start of a track ("Deck 2 is at the start. Turn REV off to play it forward."), `OUT` when stopped, and a missing file. `PLAY` during a load waited and played. Same track on both decks shared one split.

### A big library
5 real tracks kept, plus 2,000 from `big_library.py`. Stalls are gaps between changed frames on video, with the Mac busy.

| | Where | How long |
|---|---|---|
| Nothing playing | Opening the browser and the first flicks | 150 to 630 ms, several in the first 5 s |
| | Typing in the search box, then the results | 500 to 630 ms |
| Both playing, recording | Scrolling hard | Smooth, apart from 2 gaps of 220 to 250 ms |
| | Turning `IN KEY` and `±6% BPM` on and off | 2 to 3 stalls of 400 to 620 ms |
| | Closing the browser | 340 to 470 ms |
| | Opening the browser | 620 to 800 ms, with the waveforms stopped too |

- **The recording:** 84 s, and no dropout. The only runs under -50 dB are three of 30 to 50 ms in its first 2.2 s, between hits on quieter parts, which look like the track's own.
- **Columns, `NEXT` and the filters** all gave the right lists. With a track with no file: the warning triangle, and the refusal under K3.

## Timings and measurements
CPU by `top` on this simulator's process, 30 s after 10 s of settling (30 s after launch for idle), stems finished. "Beside it" is the other project's two jobs at the end of each measurement, in % of a core.

| State | Average | Peak | Round 2 | Memory | Beside it |
|---|---:|---:|---:|---:|---|
| Idle, nothing loaded | 12.9% | 16.1% | 3.6% | 87 MB | 10, 6 |
| Idle again, 2 minutes after launch | 15.5% | 16.8% | | 93 MB | 11, 38 |
| Two tracks loaded, paused | 16.4% | 19.4% | 4.5% | 448 MB | 1, 4 |
| One deck playing | 17.0% | 18.7% | 9.1% | 450 MB | 64, 6 |
| Both playing and synced, tempo offset | 23.4% | 24.4% | 17.8% | 450 MB | 89, 17 |
| Both, plus a muted stem and an echo | 28.5% | 34.1% | 20.6% | 453 MB | 49, 12 |

With the browser open, for comparison:

| State | Average | Peak | Memory |
|---|---:|---:|---:|
| Nothing loaded, 5 tracks | 2.8% | 3.0% | 81 MB |
| Two loaded, stopped, 2,005 tracks | 3.7% | 3.9% | 461 MB |
| Two loaded, stopped, 2,005 tracks, scrolling hard | 26.2% | 29.9% | 465 MB |

- **During the long run, one deck playing, `MIX` counting down, recording:** 19.1%, 357 MB, load about 23. **Straight after it, one deck playing:** 17.0%, 509 MB, load 177. So I can't see memory running away, as round 8's figure after its long run was 546 MB.
- **Nothing loaded with 2,005 tracks, decks page:** 14.2%, 88 MB. So the library's size adds about 1 MB, and nothing I can tell apart from noise to the CPU.
- **Launch to a control:** see BA1, BA2 and BIG1.
- **Press to plan:** about 2 to 6 s here.

## First impressions
**1. Does it look like $1000 pro software?** On the wide layout, yes, more than I expected: the jogs, the density, and the way it's one black-and-metal surface with small precise type. What breaks it, most first:
- **`DSP 135%` in red in the top bar.** It looks like a warning light from a tool that's in trouble, and the DJ can't do anything about it.
- **The sheets.** Open `LIST`, `SET` or the colour well and you're in iOS Settings, with type twice the size of anything behind it, and a colour picker offering Grid, Spectrum and Sliders.
- **Controls that glow and do nothing.** With an empty deck, `PLAY` looks ready and a press gets no response at all, while `REV` stays lit red. Hardware would be dark.

**2. What felt slow, confusing or surprising?**
- **Slow:** the wait for stems before `AUTO` will start, with no estimate. The browser's open and close with 2,000 tracks.
- **Confusing:** the folder in Files. Sliding on FX pads. `SAVE CUE` going somewhere other than where the deck is. `AUTO…` dropping back with no word.
- **Surprising, in a good way:** how well `AUTO` hands the decks back. Every way I took over ended somewhere sensible and said what had happened. Two very different tempos still got a move and no hole.

**3. Which control was hardest to find or hit?** `BEAT SYNC` upright on the small iPhone: it took a wrong guess to find it behind `JOG`, and it's the second thing anyone needs. To hit: `DEL`, 30 pt wide at the end of the tab row, jammed up beside `SAMPLE`.

## What happened next

**Fixed**
- **A3, idle CPU.** `Deck.tick` called `activeFX.removeAll` 30 times a second on each deck. Removing nothing still counts as a change to an observed array, so `PadTabs` and everything else looking at the effects redrew all the time. It now only does that when there's something to remove. `QuietTickTests`.
- **BA5, the Files folder.** `LSSupportsOpeningDocumentsInPlace` is on, so the promised `Segue DJ` folder should be there.
- **LR1.** Pressing `AUTO` after a stopped move now clears what it left on both decks, whichever one gets mixed out of next. `testPressingAgainClearsWhatAStoppedMoveLeftOnTheNewDeckToo`.
- **J3.** The drums were right: 148 is the tempo, in every 40 s of the track, by a separate check of its onsets (8 to 9, against 1.3 for 178). The bug was the first analysis, which took the slope at the edge of its range for a tempo. It now uses autocorrelation at a beat and its multiples, gets near from the highs as well as the kick and the level, and takes the phase from those two alone. On 40 tracks, right to 0.15 BPM went from 34 to 39, and all 40 are within reach of the right one. A change of more than 0.5% when the stems finish now says so.
- **BA4.** `OpeningCover` centred the logo in the safe area, and the launch screen centres it in the whole screen.
- **B2.** The sweep and the jog's wake-up are timed from the logo lifting.
- **`DSP n%`** is gone from the top bar. It's in `LaunchLog`'s `PERF:` lines, for measuring.
- **An empty deck** is dim, and a press says there's no track on it, apart from the tabs and the sampler's pads.
- **`BEAT SYNC` behind `JOG`.** A phone's pads page has a `SYNC` key beside `JOG`.
- **The unlabelled icon** on a phone's mixer says `MORE`.
- **`AUTO…` giving up in silence** says why. `testRunningOutWhileWaitingForStemsSaysSo`.
- **BB4.** A mix with no plan yet reads `MIX…`.
- **F2.** `SAVE CUE` saves where the deck is, and on its cue when it's stopped there.
- **`DEPTH` and `VOLUME`** go to where you touch.
- **`Add to Playlist`** doesn't offer History.
- **The stems wait** has a rough time left in the header, once a split's been going for a few seconds.
- **"A…"** upright is just the spinner.

**Found while fixing those**
- **Opening and closing the browser.** BIG3 and the owner's priorities pointed here, as it was the slowest thing left. Nearly all the time went on building a screenful of views. The browser and the decks now stay built and take turns out of sight (`Offstage` in `CLAUDE.md`). Measured on the old and new code one after the other on the same Mac, over 24 rounds with 2,000 tracks and both decks playing: opening went from about 4 freezes and 380 ms frozen in all to usually none of 50 ms or more, worst 52 ms. Closing went from about 230 ms to usually none, worst 96 ms. It costs about 16 to 20 MB. So the list keeps its place too, and a phone deck stays on `JOG`.
- **An audition kept playing after closing the browser,** with nothing on screen to stop it, through the master without a split cable. Nobody had tried it. Closing the browser now stops it, and the search goes as well. `testClosingTheBrowserEndsAnAuditionAndASearch`.
- **Searching and filtering a long list** animated the whole change, which is where the dim row and the 400 to 620 ms stalls came from. Lists over 200 tracks don't animate now.
- **A preview's marker** was on a 0.1 s `TimelineView`, against the rules. Twice a second's plenty at a third of a point a second.

**Decided against changing**
- **A relaunch leaves both decks empty.** That's what DJ software does, and loading two tracks' audio and stems at launch would cost a lot for little.
- **The crossfader stays where you put it after a move,** as the rules say.
- **A new playlist isn't selected.** You make one to add to it, and that happens from All Tracks.
- **The menu needing a tap to close and the partial swipe action** are the system's own behaviour.

**Fixed straight after**
- **A seek or hot cue on the old deck during a move,** before the new track lands, now hands the decks back and says so. `testMovingTheOldDeckDuringAMoveHandsItBack`.
- **`SPACE`, `DUB` and `NOISE`** make room for what they add. At full on the test tracks, `SPACE`'s limiting went from about 6 dB to about 1, by `LevelTests.testColorFXLevels`. Nobody's heard it yet.
- **The sheets:** the cue list and a sampler pad's sheet have smaller type on a dark ground, and the colour well offers the eight colours pads use.
- **H2:** the first time on the `FX` page, it says the pads slide.

**Not done yet**
- **What needs explaining (FU4).** Many controls still rely on someone knowing DJ gear. It needs a proper think about where help should go. Done next, after this list: `?` on the top bar, and touching a control says what it does (`UI/Shell/WhatsThis.swift`), with the same notes in Settings. Every control FU4 named has one. Nobody who doesn't know DJ gear has read them yet.
- **The file picker's blank 3 to 8 s** is the system's. Whether what's behind it still shifts is in the next round.
- **BC4,** one missed "Echo throw done" that couldn't be forced.
