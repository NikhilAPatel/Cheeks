# Hands-on results, part 4, 2026-10-31

Commit tested: edd906b
Device: iPhone Duo simulator, iOS 27.2, unfolded inner screen (951×669 pt)
Tooling limits:
- **Not testable here:** haptics, how anything sounds, and the headphone output. Where a test needed audio, I used the meters and the app's own recordings.
- **Touch:** synthetic only, with at most two fingers at once. Nothing here confirms how a real finger behaves.
- **The tool's `swipe` isn't smooth.** A 20 pt swipe over 3 s seems to reach the app in 10 pt steps. That made my first Y5 pass useless, so I redid it with a path of 1 pt steps. See Y5.
- **Pace:** "Pressing harder" ran at the tool's pace, about one or two actions a second. A person can go faster, and press more things at once.
- **Dropouts:** the recording is taken ahead of the output, so a glitch in the output device itself wouldn't show in it. Meters and recordings are all I have.
- **Video:** the recorder only writes a frame when the screen changes.
- **Not checked:** anything at iPad size. Parts 1 to 3 weren't run, as the task says to run them only if the owner asks.
- **Other sessions:** nothing else ran on this simulator, and nothing reinstalled the app during the run. The other session told me near the end that it was running low-priority stem splitting and offline renders on this Mac, off the simulators, on the efficiency cores and some GPU. I don't know when they started, so treat the CPU figures as rough. Nothing I measured here looks affected: the audio figures come from the app's own recordings and the meters.

## Summary
24 tests: **23 PASS, 1 FAIL (P3), 0 BLOCKED.** No crashes and no crash reports.

Everything the retest covers from part 3 now passes: armed loops, rolls and slices over a running loop, and the deck meters. Exhilarate at 0:53 went from 92% of frames in the red to 0%. Y5, the likeliest new bug, is clean: no step as a knob leaves centre.

The 3 most important problems:
1. **The end of a track is a dead end (P3).** `PLAY` does nothing there and says nothing. `CUE` moves the cue point to the last frame, so the old cue is lost.
2. **A seek during a held `ROLL` throws the deck on release.** The deck plays on from the seek with `ROLL` still lit. Letting go jumps it to where the track would have got to from before the seek: 01:08.2 to 02:16.4 here.
3. **`REV` walks out of a running loop.** The key flips from `EXIT` to `ARMED`, and the deck comes back into the loop when `REV` goes off.

One thing I couldn't explain: deck 2 stopped by itself once, and three repeats, one of them exact, didn't do it again. See Looks wrong.

## Failures
Causes below are leads from reading the code, not confirmed diagnoses.

### P3: A deck that's run out can't be played again with `PLAY`, and `CUE` loses the cue point
- Steps: let a deck run to the end of its track. I did this on deck 2 with Exhilarate three ways: a 4-beat loop just before the end with `SLIP` and `ECHO` on, then `EXIT` once the slip position had passed the end, twice; and with no loop and no `SLIP`. Then press `PLAY`. Then press `CUE`, then `PLAY`.
- Expected: it stops cleanly, and can be played again straight after.
- Actual:
  - **The stop is clean every time:** -00:00.0, `PLAY` unlit, the meters fall, no crash. Deck 1 ran out cleanly too, twice.
  - **`PLAY` does nothing.** 1.5 s later it's still at -00:00.0 and unlit, with no message. Screenshot: p3-play-at-end.png
  - **`CUE` moves the cue point to the last frame.** The orange triangle goes to the end of the waveform, and `PLAY` still does nothing. It's normal behaviour on a paused deck, but here it means the key you'd reach for to get back wipes where you were going. Screenshot: p3-cue-at-end.png
  - **What does get out:** `RELOOP` when a loop's set, a hot cue, or loading the track again. `RELOOP` and a hot cue both start the deck. I didn't try tapping the overview from there.
- Leads:
  - At the last frame the render thread stops the deck and sets `reachedEnd` (`Cheeks/DSP/Engine.cpp:419`). `Deck.play()` (`Cheeks/Audio/Deck.swift:461`) clears that and sets playing without moving the deck, so the next block stops it again.
  - Nothing outside `Deck` and `DeckRenderer` reads `reachedEnd`, and they only clear it.
  - `Deck.cueDown` (`Cheeks/Audio/Deck.swift:485`) sets the cue to the playhead when paused away from it.
- Crash report: none.

## Looks wrong
- **A seek during a held `ROLL`.** Steps: tap `ROLL` on the `FX` page so it stays lit, tap the overview, wait, tap `ROLL` again. The deck plays on normally from the seek, so there's no roll any more, with `ROLL` still lit: 00:53.1, then 01:08.2. Letting go jumps to 02:16.4, which is where the track would have got to from before the seek. I only tried this with the `FX` page's `ROLL`, not a held pad on the `ROLL` page. Lead: `leaveLoop(ifGoingTo:)` (`Cheeks/Audio/Deck+Performance.swift:54`) only cancels slip when `slipMode` is on, so the roll's own slip survives the seek, and `momentaryPadReleased` then releases it. Screenshot: roll-seek-frames.png, roll-seek-release.png
- **`REV` walks out of a running loop.** Steps: run a loop and turn `REV` on. The deck plays backwards straight through the loop's start, and the key changes from `EXIT` to `ARMED` with the marks now ahead of it. With `REV` off it plays forward and into the loop again, with `EXIT` lit. I'd expect a loop to hold in reverse too, but that's your call. Lead: the wrap in `advance` needs `rate > 0` (`Cheeks/DSP/Engine.cpp:414`). Screenshot: p4-rev-out-of-loop.png, p1-both-rev.png
- **A waiting loop's size pad is lit, and tapping it ends the loop.** With `ARMED` showing, the key and the length key are unlit as W1 asks, but the `4` pad on `LOOP` is lit. Tapping it doesn't start a loop where the deck is, as tapping `8` does in W6: the key goes to `RELOOP` and no new loop starts. Lead: `toggleBeatLoop` (`Cheeks/Audio/Deck+Performance.swift:188`) checks `loopActive` and the length, but not `isLoopAhead`. Screenshot: w-armed-pad-lit.png, w-tap-lit-pad.png
- **`SLIP` turned on during a loop does nothing for that loop.** Loop running at 01:57.2, `SLIP` on, a held roll, then `EXIT` about 14 s later. The deck played on from 01:56.9, not 14 s further on. With `SLIP` on before the loop starts it's exact (X3). Lead: slip is engaged when a loop starts, and `slipMode`'s `didSet` only ever cancels (`Cheeks/Audio/Deck.swift:163`). Screenshot: slip-on-in-loop.png
- **Deck 2 stopped by itself, once, and I can't say why.** At about 13:25, on Exhilarate with `ROLL` lit on the `FX` page: `ROLL` off, `PHASER` on, overview tap to 0:53. The deck sat at 00:52.7 with `PLAY` unlit and `CUE` lit. Three repeats played on: one with a 3 s roll, one with a 14 s roll, and one with those exact taps, including the seek during the roll that came before them. I have no cause, and it may have been something in my sequence, but an unexplained stop is worth knowing about. Screenshot: unexplained-stop.png
- **Beat FX can take a deck into the red at default levels.** This is the same spot that read 0% in Y1, Exhilarate at 0:53:

  | State | Deck column in red | Master L / R in red | `LIM` lit |
  |---|---|---|---|
  | Clean | 0% | 0% / 0% | 0% |
  | Key +1 | 0% | 0% / 0% | 0% |
  | Tempo +0.8% | 0% | 0% / 0% | 0% |
  | `ROLL` on the `FX` page | 0% | 0% / 0% | 0% |
  | `ROLL` again, straight after turning `PHASER` off | 8.6% | 8.1% / 8.0% | 0.5% |
  | `CRUSH` | 9.4% | 0% / 0.8% | 0% |
  | `CRUSH` and `PHASER` | 64.5% | 24.7% / 24.3% | 0.5% |
  | As left after the stress run: key +1, tempo +0.17%, FX unknown | 92.3% | 71.5% / 67.2% | 20.5% |

  The last row is probably the same thing, but I can't prove it. I'd left beat FX on from the stress run, and last saw `PHASER` and `CRUSH` lit before changing more of them. Loading the track again cleared them, and the reading went to 0%. It's worth a look if the crusher isn't meant to add level. Screenshot: y1-crush-phaser.png
- **Nothing shows beat FX are on once you leave the `FX` page.** That's how I came to measure the row above with them still on: deck 2 was on `STEMS`, with nothing there to say so.
- **The same track on both decks splits twice, at once.** Both compact decks counted separately, 39% and 29%. Lead: `StemJob` is per deck, and the cache is only read when a job starts (`Cheeks/Stems/StemJob.swift:26`). Screenshot: p5-two-splits.png
- **`LIM` lights below the red.** With both decks at default, `LIM` was lit in 2 to 5% of frames while neither master column showed red. It's small, but the two disagree.
- **An on-at-load loop isn't armed if the deck loads past it.** After I saved a memory cue at 2:44.7, Severe Tire Damage loads there, past its loop at 2:00.3, so the key says `RELOOP`. That's what `armSavedLoops` says it does. I mention it because `LIST` says a loop switched on there "is waiting when the track loads".
- **Tab spacing is better, but still in two sizes.** See Z1. Screenshot: z1-tabs.png

**Seeking and `CUE` during a running loop, as asked in the handover: both seem right to me.** A seek from 02:45.9 to 04:48 plays on with the key at `RELOOP`, and `RELOOP` goes back. `CUE` from a loop at 4:50 goes to the cue at 2:44.7 and stops, with `RELOOP` unlit. If the cue is inside the loop, or at its start, `CUE` stays in the loop with `EXIT` lit, which also seems right. Screenshot: seek-and-cue-1.png, seek-and-cue-2.png

**Not a fault, but it caught me out:** `RELOOP` starts a stopped deck, and so does a hot cue, so a `PLAY` straight after pauses it. For a while I took that for a deck that wouldn't stay playing after running out.

## All results
| Test | Result | Notes |
|---|---|---|
| W1 | PASS | `ARMED`, unlit, and the length key is unlit. The `4` pad is lit: see Looks wrong. Screenshot: w1-armed.png |
| W2 | PASS | Overview to 03:30, `PLAY`: plays on from 03:30.9 with `RELOOP`. `RELOOP` goes to 02:00.3 with `EXIT` lit. Screenshot: w2-past.png, w-frames-1.png |
| W3 | PASS | From 01:56.5 it stays `ARMED`. Six seconds later it's at 02:00.7 with `EXIT` lit, holding in the loop. Screenshot: w-frames-1.png |
| W4 | PASS | Tapping `ARMED` gives `RELOOP`. Played from just before the loop, it was past it at 02:05.3 without stopping. Screenshot: w-frames-1.png |
| W5 | PASS | From 01:56.3 the deck moves 4 beats a jump and the marks stay put. The third jump lands inside the loop and the key goes to `EXIT`. The fourth moves the running loop along with the deck, leaving the saved loop's bar where it was. Screenshot: w-frames-2.png |
| W6 | PASS | `<`: the deck stays at 00:01.2, the length goes to 2 and the waiting loop halves on the waveform. `8` starts a new loop at the deck, and the saved loop in `library.json` doesn't change. The same-size pad differs: see Looks wrong. Screenshot: w6-size-pad.png, w-frames-2.png |
| X1 | PASS | A `1/4` pad held 3 s. Afterwards: `EXIT` lit, `4` on the key, same marks, in the loop at 01:57.1. Screenshot: x1-roll.png, x-frames-1.png |
| X2 | PASS | A quick `ROLL` tap, then `SLICER` held 3 s: `EXIT` lit and in the loop both times, at 01:57.2 and 01:56.6. Screenshot: x-frames-1.png |
| X3 | PASS | `SLIP` on before the loop. After a 3 s roll it stays in the loop. `EXIT` lands at 02:42.2, 5.8 s after 02:36.4, in 5.8 s of clock. Screenshot: x3-slip-exit.png, x-frames-2.png |
| X4 | PASS | `SLIP` on, `Q` off, loop running at 03:05.6: hot cue `A` lands on the cue at 03:05.0, with `RELOOP`. Screenshot: x-frames-2.png |
| Y1 | PASS | 0% red on the playing deck's column, master columns and `LIM`, in all five clips. See below. Screenshot: y1-levels.png, y1-exhilarate-0-53.png |
| Y2 | PASS | `TRIM` up takes deck 2's column into the red in 100% of frames. Fader down: that column doesn't move and the master columns fall to nothing. Screenshot: y2-trim.png |
| Y3 | PASS | Both decks, `TRIM` and `MASTER` up: all four columns red and `LIM` lit in 100% of frames. Screenshot: y3-master.png |
| Y4 | PASS | One deck: `LIM` lit in 0% of frames in all five clips. Both decks: about 2.7% over 30 s. |
| Y5 | PASS | No jump as any knob leaves centre, in either direction. Kills still work. See below. |
| Z1 | PASS | Gaps are now 7.0 to 12.7 pt, from 6 to 14. `STEMS` to `FX` is closer to the others, but still the widest. Capitals are 19 px on all nine labels. See below. Screenshot: z1-tabs.png |
| Z2 | PASS | A spinner shows at the right of the row on `Save a Backup…`, `Restore from a Backup…` and `Choose a File…`, until the picker covers it. It's gone after `Save a Backup…`'s picker closes. I didn't recheck the other two rows after closing. Screenshot: z2-save-spinner.png, z2-restore-spinner.png, z2-file-spinner.png |
| Z3 | PASS | Loading split Exhilarate over Severe Tire Damage: all 36 frames the recorder wrote show no text under the title once it changes. No `Stems waiting`. Screenshot: z3-load-frames.png |
| P1 | PASS | 10 min 45 s, mostly with both decks playing, and stems split on both. Deck 2 ran out at about 2.5 min and again near the end, and stopped once after a backspin, restarting from a hot cue or `PLAY` each time I needed it. No crash, no control stopped responding, no dropout found. See below. Screenshot: p1-mid-run.png, p1-both-rev.png |
| P2 | PASS | Tempo moved during a running loop, from 188.61 to 171.25: the deck stays in the loop, with `EXIT` lit and the marks with the music. Syncing a deck in a loop keeps the loop, at 170.59. A roll during a tempo move and an echo out during one both come back fine. Header and jog agree. Screenshot: p2-tempo.png, p1-tempo-both-loops.png |
| P3 | **FAIL** | Stops cleanly, but `PLAY` does nothing at the end and `CUE` loses the cue point. See Failures. |
| P4 | PASS | No crash, and the marks stay put. `REV` and the jog in a loop, a roll with the jog, and a roll during `REV` all end with `EXIT` lit and in the loop. An armed loop stays `ARMED` through `REV` and the jog. `REV` leaving a loop: see Looks wrong. Screenshot: p4-rev-out-of-loop.png |
| P5 | PASS | Two and three quick loads on a stopped deck, with stems splitting on the other: the last tap wins each time, with that track's own cues on the overview. Two splits at once: see Looks wrong. Screenshot: p5-last-tap.png |
| P6 | PASS | 33:41 recorded, right to within a second. The `.cue` and `.txt` match what I did. Plays back in Recordings, with the key going to pause and no hang warning. See below. Screenshot: p6-recordings.png |

## Timings and measurements

**Y1, deck alone at default levels, about 13 s each:**
| Track | From | Deck column in red | Master columns in red | `LIM` lit | Last time |
|---|---|---|---|---|---|
| Exhilarate | 0:00 | 0% | 0% | 0% | |
| Exhilarate | 0:53 | 0% | 0% | 0% | 92% |
| Exhilarate | 1:02 | 0% | 0% | 0% | |
| Severe Tire Damage | 2:09 | 0% | 0% | 0% | 9% |
| Severe Tire Damage | about 3:05 | 0% | 0% | 0% | |

**Y2 and Y3, lit pixels in a column:**
- Deck 2 at default: about 6,100. With `TRIM` up: about 7,500, in the red in 100% of frames.
- Pulling deck 2's fader down at about 7 s: its column stays at 7,497 to 7,517, while master left goes from 7,352 to 0 by 12 s.

**Y4, both decks at default for 30 s, `LIM` lit per 5 s:** 2%, 4%, 2%, 0%, 3%, 5%. The master columns show no red after the first 5 s, where they read 18 to 19% just after I'd reset knobs that had been turned up.

**Y5, how it was measured.** Deck 1 alone at 0% tempo, on Severe Tire Damage from 0:59, recorded by the app and compared with the track decoded separately. With every knob centred the recording's low band sits at -1.17 dB against the track, to within 0.01 dB. That's what makes any change easy to see. Each knob went 10 pt off centre and back, in 1 pt steps every 150 ms, down and then up.
- **`LOW` down**, low band every 200 ms: -1.17, -1.84, -2.58, -3.26, -4.34, then back through -3.25, -2.67, -1.56, -1.17. A smooth ramp with no step. Ten points should be 3.47 dB, and this reached 3.17 dB.
- **`LOW` up**, low band: -1.17, -1.36, -1.41, -0.83, -0.66, -0.47, -0.42, then back to -1.17.
- **As the bands come in,** the whole level moves by 0.2 to 0.8 dB over a window or two of 200 ms, even going up, and wobbles by about that much while a knob is off centre. That looks like the phase turn the project notes describe, and it isn't a step. Someone should still listen to it.
- **Back at centre** the recording is at -1.17 again, for all six moves, so the isolator is out of the path again.
- **Clicks:** I compared the largest sample-to-sample step with the track's, in 5 ms windows:

  | Stretch | Worst step ratio | Worst excess | Highest peak |
  |---|---|---|---|
  | Knobs centred | 2.38 | 0.117 | 0.769 |
  | `HI` down | 1.12 | 0.007 | 0.803 |
  | `MID` down | 1.40 | 0.066 | 0.782 |
  | `LOW` down | 1.41 | 0.052 | 0.751 |
  | `HI` up | 2.04 | 0.096 | 0.772 |
  | `MID` up | 2.13 | 0.017 | 0.753 |
  | `LOW` up | 1.46 | 0.022 | 0.781 |

  Nothing around a move is worse than plain playback, so I found no click. My ears can't confirm that.
- **Meters:** in a video of `LOW` going 12 pt off centre and back, the deck column stays between 6,133 and 6,464 with no jump.
- **Kills, on the same track:** `LOW` takes the level from about -13 dB to -26 to -28 dB. `MID` takes off 2 to 3 dB. `HI` barely changes the level, but the largest sample step falls from about 0.7 to 0.04.
- **My first pass was no good.** It used the tool's `swipe`, which showed `LOW` dropping 3.4 dB in one go. That's the tool's 10 pt step (3.47 dB), not the app. I also measured `HI` at the wrong time. Neither result counts here.

**Z1, gaps between tab labels on a page showing `DEL`, in points, on both decks:**
| `CUE`-`MEM` | `MEM`-`LOOP` | `LOOP`-`ROLL` | `ROLL`-`SLICER` | `SLICER`-`JUMP` | `JUMP`-`STEMS` | `STEMS`-`FX` | `FX`-`SAMPLE` | `SAMPLE`-`DEL` |
|---|---|---|---|---|---|---|---|---|
| 9.3 | 8.3 | 7.3 to 7.7 | 7.0 to 7.3 | 7.0 to 7.3 | 7.3 to 7.7 | 12.7 | 12.0 | 11.7 |

**P1, what ran.** From 12:50:40 to 13:01:25, with a recording going throughout:
- Stem mutes, solos and presets; loops of every size; held rolls and slices, including one on each deck at once.
- Hot cues set and fired quickly on both decks; a memory cue and a loop saved. I didn't recall them from `MEM` during this run.
- FX chains of three, echo outs, the `FX` page's `ROLL`, and backspin. I never hit `BRAKE`. Color FX cycled through all six, with the knob turned on `DUB`, `SPACE`, `CRUSH` and `FILTER`. Sampler pads.
- `KEY SYNC`, `SPLIT`, beat jump size, `SLIP`, `REV` on both decks, both jogs together, the crossfader and tempo moves.
- The browser opened mid-run, a refused load, and `REC`'s alert with `Keep recording`.

**P1, results:**
- **CPU on this simulator's process, 72 samples of 2 s:** average 17.3%, highest 69.3%, and that was while the mix was saving. The highest before that was 39.9%. This is a simulator on a Mac, not the phone, and the other session's background jobs may have been running: see Tooling limits.
- **Memory:** between 700 and 723 MB, ending at 705 MB, so no growth.
- **Master meters over the last 140 s of video:** never below 15% of their usual reading, with no frame gap over 0.045 s.
- **Log:** the only audio overload message was at launch, at 12:09:12, with nothing playing.

**P6, the mix:**
- **Length:** 33:41.6, or 2021.6 s, 63 MB. `REC` went on at 12:27:45 and stop was at about 13:01:26. It saved within about 30 s, with the deck still playing.
- **`.cue`:** `TRACK 01` Severe Tire Damage at 00:21:37, and the first sound in the file is at 21.55 s. `TRACK 02` Exhilarate at 08:51:05, which is deck 2's first `PLAY`. Reloading the same track on a deck later adds no entry, and tracks loaded but not played aren't listed, both of which seem right.
- **Silences of 0.15 s or more, below -55 dB.** All four are explained:

  | From | Length | Why |
  |---|---|---|
  | 0:00 | 21.5 s | Before the first `PLAY` |
  | 4:11 | 234.9 s | Deck 1 ran out during Z, until the next `PLAY` |
  | 9:56 | 0.16 s | The tail of an echo out, with deck 2 in its outro |
  | 15:58 | 16.5 s | Both decks stopped for the load test |
- **Gaps of 30 ms or more, below -50 dB, over the last 646 s:** none.

There's a second, short mix in Recordings from 13:16, from the Y5 rerun.

## First impressions
Not run, as the task says to run part 3 only if the owner asks.

## What happened next

Every lead was checked against the code first. All of them were right, apart from `CRUSH`, below. Each fix has a test, and the new tests were run against the old code first: 81 failed assertions on the loops, the end of a track and FX levels, and 8 on the shared split.

**Fixed**
- **The end of a track (P3):** `PLAY` now goes back to the cue and plays. `CUE` goes back to the cue and leaves it where it was. If the cue is in the last half second too, `PLAY` starts from the top of the track. Hot cues and `RELOOP` still go where they say.
- **A seek during a roll:** a seek, a hot cue, a memory cue or a recalled loop now ends a roll or slice. `ROLL` goes out, the way back is forgotten, whatever loop was set before comes back, and letting go of a held pad afterwards does nothing. The lead was right about the slip surviving, and a held `ROLL` pad and a slice had the same bug.
- **`REV` in a running loop:** it now holds, wrapping from the loop's start back to its end, through the declicker. A loop waiting further on doesn't catch the deck, and the jog still goes where the hand takes it. A roll during `REV` carries on backwards underneath. Turning `REV` off in a slip loop no longer throws the deck out of it.
- **A waiting loop's size pad:** no longer lit, and tapping it starts a loop where the deck is.
- **`SLIP` during a running loop:** starts the slip timeline from that moment, so leaving the loop returns to where the track's got to.
- **Beat FX levels:** the phaser was the worst, because of its resonance, with flanger, filter, reverb and the echoes after it. All have been turned down to suit. An echo out's tail stays at its old level, since there's nothing left playing to make room for.
- **Nothing shows FX are on:** the `FX` tab has a small blue dot while effects are on. VoiceOver reads "effects on".
- **The same track on both decks:** shares one split and its memory. It stops only when both decks have let go of it.

| Default levels, about 13 s from the same spots as Y1 | Meter top before | After | In the red before | After | Level against dry, before | After |
|---|---|---|---|---|---|---|
| Exhilarate, dry | -5.4 dB | -5.4 dB | 0% | 0% | | |
| Exhilarate, `PHASER` | +1.1 dB | -2.1 dB | under 1% | 0% | +2.7 dB | -0.4 dB |
| Exhilarate, `CRUSH` and `PHASER` | +1.3 dB | -1.8 dB | under 1% | 0% | +2.4 dB | -0.7 dB |
| Exhilarate, `SPIRAL` | +1.3 dB | -2.7 dB | 2% | 0% | +3.3 dB | +0.8 dB |
| Severe Tire Damage, dry | -1.8 dB | -1.8 dB | 0% | 0% | | |
| Severe Tire Damage, `PHASER` | +3.0 dB | -0.2 dB | 14% | 0% | +3.0 dB | +0.7 dB |
| Severe Tire Damage, `FLANGER` | +3.0 dB | +0.9 dB | 4% | under 1% | +1.7 dB | -0.1 dB |
| Severe Tire Damage, `CRUSH` and `PHASER` | +2.8 dB | -0.4 dB | 10% | 0% | +3.1 dB | +0.6 dB |

At full depth some still reach the red, at most 5% of the time on these tracks, for `PHASER` alone and for `CRUSH`, `PHASER` and `FLANGER` together, which was 62%. The limiter is what those have left.

**The `CRUSH` reading wasn't reproduced.** Alone, at the default depth and at full depth, it adds nothing here: the meter top is the same as dry, or lower, on both tracks, and the level's the same. A likely reason for the 9.4%: an effect let go with quantize on keeps running until its beat, and up to 3 s if a roll means that beat never comes, which would also explain the row with `ROLL` straight after `PHASER`. That isn't confirmed. This measurement used the full mix rather than stems, and an offline render instead of the screen.

**Deck 2 stopping by itself: a likely cause, not a confirmed one.** Exhilarate is 2:25 long. With a seek during a held roll, the roll's slip timeline carried on from where it was, and letting go jumped there: 02:16.4 in the report's example. A bit later and that's past the end, which stops the deck where it is, and the next overview tap then moves a stopped deck to 0:53. That fits what the report saw: `ROLL` lit, `ROLL` off, then a stopped deck at 00:52.7. It also fits the repeats not doing it, since they'd have had less time on that timeline. A test shows the stop happens when a roll outlasts the track. The seek fix removes this route, since the slip timeline no longer survives a seek. Nothing proves it's what happened on that run.

**Worth knowing:**
- A roll held until the track would have finished still stops the deck when it's let go. That's what slip means, and `PLAY` now gets out of it.
- If a new roll starts while a finger is still down on a pad whose roll a seek ended, lifting the old finger ends the new roll. It takes three fingers and a seek, so it's been left.
- `BEAT JUMP` during a held roll still moves the roll's loop and not the way back. That wasn't in the report, and it isn't obviously wrong.

**Not fixed**
- **`LIM` lighting below the red, tab spacing in two sizes, and `LIST`'s wording about a loop past the load point:** none were in this batch. They're small, and the first needs a decision about what the two should agree on.
- **Nobody has heard any of this:** turning effects down could leave some too weak, and the wrap in reverse is new. Both are on the owner's listening list in `docs/TEST_PLAN.md` §2.

