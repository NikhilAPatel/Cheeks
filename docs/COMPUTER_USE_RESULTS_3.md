# Hands-on results, part 3, 2026-10-30

Commit tested: 05feeed
Device: iPhone Duo simulator, iOS 27.2, unfolded inner screen (951×669 pt)
Tooling limits:
- **Not testable here:** haptics, how anything sounds, and the headphone output. Where a test needed audio, I used the master meters.
- **Touch:** synthetic only, so nothing here confirms how a real finger behaves. That matters most for `UNDO` and the tab-then-pad race.
- **Timing:** each tool call takes a moment, and I can't set the gap between two taps exactly. "No pause" means the second tap was sent as soon as the first returned.
- **Video:** the recorder only writes a frame when the screen changes, so tail lengths are approximate.
- **Not checked:** anything at iPad size.
- **Scope:** this is the retest only (R, S, T, U, V). Parts 1 to 3 weren't run, as the task says to run them only if the owner asks.
- **Task doc:** its "Results format" section still names `COMPUTER_USE_RESULTS_2.md`. I followed the instructions at the top, which say `_3`.
- **Other sessions:** nothing else ran on this simulator during this run, and the other session confirmed it ran nothing on any simulator.

## Summary
22 tests: **21 PASS, 1 FAIL (T5), 0 BLOCKED.** No crashes and no crash reports.

All five failures from part 2 are fixed here, and so is the tab-then-pad race under this touch tool: 29 of 29 pads belonged to the new page and responded, against 0 of 3 last time.

The 3 most important problems. The first two are new, and neither is a test in the retest:
1. **A loop armed for load pulls the deck back.** With a saved loop switched on, I tapped the overview to 3:36, past the loop at 2:09. Pressing `PLAY` jumped the deck back into the loop. In a set that's a 90-second jump with no warning.
2. **A held `ROLL` or `SLICER` pad ends a running loop.** The key goes to `RELOOP` and the deck plays on out of the loop. R5 passes because it covers a loop that had already been exited.
3. **One deck at default levels still reaches the red on its own meter column (T5).** Exhilarate's column was in the red in 92% of frames. The master columns stayed clear, and `LIM` stayed off.

## Failures
Causes below are leads from reading the code, not confirmed diagnoses.

### T5: One deck at default levels reaches the red on its own column
- Steps: leave `TRIM`, `MASTER` and the faders at their defaults. Play one deck and record the meters for about 12 s.
- Expected: one deck stays out of the red.
- Actual: the four columns are deck 1, master left, master right, deck 2. Only the playing deck's own column went red, and it reached the top segment:

  | Playing | Deck's own column in red | Master columns in red | `LIM` lit |
  |---|---|---|---|
  | Deck 2 alone, Exhilarate at 0:53 | 92% of frames | 0% | 0% |
  | Deck 1 alone, Severe Tire Damage in its loop at 2:09 | 9% of frames | 0% | 0% |

  Last run's red was also in the deck's own column, then on the lowest red segment. The red zone is smaller now, so these aren't directly comparable. The master half of the fix works.
- The second half of T5 passes: with both decks playing and `TRIM` and `MASTER` turned up, both master columns were in the red and `LIM` was lit in 100% of frames.
- Lead: the deck column reads `peak` in `renderChannel` (`Cheeks/DSP/Engine.cpp:168`), after the filter and Color FX but ahead of trim and the fader. That would make it the track's own peaks, so a loudly mastered track reads red whatever the mix is doing. Exhilarate's loudness is -8.6 and Severe Tire Damage's -12.7, which fits. Turning `TRIM` up didn't raise those columns either: 92% became 71%, and 9% became 14%, on different passages.
- Screenshot: docs/test-results-3/t5-one-deck-frames.png, t5-meters.png

## Looks wrong
- **A loop armed for load pulls the deck back after a seek.** Steps: switch a saved loop on in `LIST` and load the track. The deck waits at 00:01.2 with the key showing `EXIT`. Tap the overview past the loop: the time goes to 03:36.6. Press `PLAY`: 1.5 s later it reads 02:09.4, inside the loop. Lead: `armSavedLoops` (`Cheeks/Audio/Deck+Performance.swift:167`) already avoids this when a track loads past the loop, and its comment names the same pull-back, but nothing handles a seek made after the load. Screenshot: v-seek-past-armed-loop.png
- **A held `ROLL` or `SLICER` pad ends a running loop.** Steps: set a 4-beat loop and let it run, with `EXIT` lit. Hold a `ROLL` pad for 1 s and let go. The key goes to `RELOOP` and the deck plays on: -04:03.4 in the loop, -04:03.0 at release, -03:59.9 another 2.5 s later. `RELOOP` brings the same loop back. A held `SLICER` pad does the same, and so does a quick `ROLL` tap (S1 pair 1). Lead: `momentaryPadReleased` (`Cheeks/Audio/Deck+Performance.swift:296`) gives the borrowed loop back with `active: false`, whether or not it was running. Screenshot: v-roll-ends-running-loop.png, v-slice-ends-running-loop.png
- **`EXIT` lights for a loop you haven't reached.** With a loop armed, the key reads `EXIT` from the moment the track loads, while the deck is still minutes away from it. Screenshot: t3-bpm.png
- **Section names are still unproven.** See T6 in the table. `UP` is a new name on Severe Tire Damage. Screenshot: t6-sections.png
- **The tab row's spacing is uneven.** `SLICER` to `JUMP` is about 6 pt, and `STEMS` to `FX` about 14 pt. That comes from `SAMPLE` having more room. It's the price of equal label sizes, and it's only a look. Screenshot: s2-tabs.png
- **The file picker is slow to appear, with no sign anything is happening.** After `Save a Backup…` it took between 2.5 and 6.5 s. This corrects part 2, where I reported a press there as possibly ignored: the likely explanation is that I looked too soon.
- **A muted stem can look the same as an unmuted one.** Muting `BASS` on Exhilarate at 0:53 changed nothing visible, because no blue shows there even with it on. `DRUMS` shows the ghost clearly. It's the music, not a fault, but someone muting the bass may wonder if it worked. Screenshot: t4-muted.png
- **`Stems waiting` flashes under the title for a moment** when loading a track that's already split. Screenshot: t2-load-frames.png
- **Logs over 30 minutes, none from an engine:** 14 `UIKit.AnimationKit` DebugAssertion faults (7 each for `position` and `bounds`), 31 `renderbox` "image provider timed out" errors, and simulator audio-device messages. No hang-risk lines.

## All results
| Test | Result | Notes |
|---|---|---|
| R1 | PASS | `SAVE CUE` wrote one cue. `DEL`, then the pad: gone from the file. `UNDO`: exactly one back, with the same ID. Reload: one pad. One earlier `UNDO` tap arrived after the capsule's 8 s, which was my timing |
| R2 | PASS | The file says `true` straight away. After a reload with no relaunch the deck stays at 00:01.2 with the loop armed. Played up to it, the deck holds between 2:09.4 and 2:10.2 |
| R3 | PASS | After a 2 s `1/16` roll: `SAVE LOOP` refuses with a hand, "Set a loop first, then save it." Nothing saved. `RELOOP` did nothing, playing or paused. No loop on the waveform |
| R4 | PASS | After a slicer hold and pause, no grab for that deck. `Grab Deck 1's Loop` still shows, correctly, as deck 1 had a real loop |
| R5 | PASS | `RELOOP` brought back the 4-beat loop after a roll. With `IN` waiting, the marker and lit key survive the roll, and `OUT` makes the loop |
| R6 | PASS | 5, back to 4 on exit, 5 again on `RELOOP`. Took two tries to hit exactly 5 beats by tool timing, and the key tracked each try: 6, then 3, then 5 |
| R7 | PASS | With Exhilarate on both decks, deck 2's hot cue and memory cue appeared on deck 1's pads and waveform with no reload |
| S1 | PASS | 29 of 29 tab-then-pad pairs used the new page and responded, on both decks, across every page but `JUMP`. See below. Synthetic, so confirm with a real finger |
| S2 | PASS | All nine labels have 19 px capitals (`CUE`'s round C measures 20). `SAMPLE` is 2.7 pt from `DEL`'s outline and 4 pt from its face, up from 0.5 and 1.7 |
| S3 | PASS | `DEPTH` went from 60% to about 85%, and `ECHO` stayed lit at the new depth after letting go. A plain tap let it go |
| S4 | PASS | Worked from 4 pt above (y = 0, the top of the screen), 4 pt below, 4 pt left and 4 pt right of the key's face. See the table below |
| S5 | PASS | A held `SLICER` pad lights purple and a held `ROLL` pad cyan, each like any other lit pad |
| T1 | PASS | A hand and "Echo out needs the deck playing." |
| T2 | PASS | No old picture in any frame. The compact deck has an empty picture box and the new title at once, and the jog says `Loading` with a spinner, not `NO TRACK` |
| T3 | PASS | Deck 1 at +2.2% and deck 2 synced at +6.6% both read 181.86 in header and jog. The menu's title reads "Beat grid: 178.00 BPM at normal speed" |
| T4 | PASS | Normal colours with every stem on. With `DRUMS` muted, stem colours stay with the drums a dim ghost on `CUE`. Unmuted, normal colours return |
| T5 | FAIL | See Failures. Master and `LIM` behave. The deck's own column doesn't stay out of the red |
| T6 | PASS | Report only, no right answer to compare with. Sections are listed below |
| T7 | PASS | Meters kept moving for 3.8 s and 4.2 s after pausing, one for each direction of the knob. Without `DUB` the body was gone by 0.4 s. Sound not judged |
| U1 | PASS | Alert: "Backup saved." |
| U2 | PASS | "Restored 2 tracks and 1 playlist." Rows kept their order, and the saved loop's switch survived |
| U3 | PASS | The restore wrote the copy at 22:23:22. A cue at 22:24:32 stayed out of it, as designed. A second cue at 22:32:53, over 8 minutes later, updated the copy with both. A third seconds later stayed out while in the foreground, then went in at 22:32:57 on going to the background. The app came back with the same process |

### S1: each pair
**The question was whether the old pad fires or the new pad fails to respond. Neither happened in 29 pairs.**
- **Old pad firing:** no pad on the old page lights in the frame before any page change, and no old-page action happened: no deck jump, no effect latched, no sample fired.
- **New pad not responding:** all 29 flashed and did their action on the new page.
- **Limits:** these are on-screen gaps, as the video can't give the touch times and the display can bunch updates. Touch was synthetic. I didn't try a truly simultaneous press, where the old page is still what's on screen.

There were three runs. All the gaps are inside the old 120 ms fade.

| Run | Pairs | Page change to pad reacting |
|---|---|---|
| First, deck 1 playing, no pause | 7 | 13 to 28 ms |
| Second, deck 1 in a loop, both decks, no pause | 16 | 0 to 73 ms, mostly 12 to 15 ms. In pair 8 the pad fired in the same display frame as the page change |
| Third, deck 1, `sleep 0.01` between the taps | 6 | 37 to 57 ms |

The first run, with what each pad did:

| Pair | Pad pressed | What happened | Old page would have |
|---|---|---|---|
| `CUE` to `LOOP` | Row 2, 1st | Loop of 4 set | Hot cue E |
| `LOOP` to `CUE` | Row 2, 2nd | Hot cue F set, confirmed in the file | Loop of 8 |
| `CUE` to `STEMS` | Row 2, 2nd | `SOLO I` lit | Jump to hot cue F |
| `STEMS` to `FX` | Row 1, 1st | `ECHO` lit | `VOCAL` muted |
| `FX` to `SAMPLE` | Row 1, 1st | `AIR HORN` fired | `ECHO` off |
| `SAMPLE` to `MEM` | Row 1, 1st | Memory cue recalled, time jumped to the start | `AIR HORN` |
| `MEM` to `CUE` | Row 1, 1st | Jumped to hot cue A at 0:50 | Memory cue recalled |

The second and third runs, in order:

| Pair | Deck | Page change | Pad | Reacted after |
|---|---|---|---|---|
| 1 | 1 | `CUE` to `ROLL` | 1/8 | 15 ms |
| 2 | 1 | `ROLL` to `SLICER` | 3 | 52 ms |
| 3 | 1 | `SLICER` to `FX` | `PING PONG` | 25 ms |
| 4 | 1 | `FX` to `STEMS` | `SOLO D` | 13 ms |
| 5 | 1 | `STEMS` to `SAMPLE` | `RIM` | 12 ms |
| 6 | 1 | `SAMPLE` to `LOOP` | 1 | 12 ms |
| 7 | 1 | `LOOP` to `CUE` | Hot cue B | 73 ms |
| 8 | 1 | `CUE` to `FX` | `FLANGER` | Same frame |
| 9 | 1 | `FX` to `ROLL` | 1 | 12 ms |
| 10 | 1 | `ROLL` to `STEMS` | `SOLO I` | 13 ms |
| 11 | 1 | `STEMS` to `SLICER` | 1 | 12 ms |
| 12 | 1 | `SLICER` to `SAMPLE` | `LASER` | 13 ms |
| 13 | 2 | `CUE` to `LOOP` | 1 | 13 ms |
| 14 | 2 | `LOOP` to `FX` | `PING PONG` | 13 ms |
| 15 | 2 | `FX` to `STEMS` | `SOLO B` | 13 ms |
| 16 | 2 | `STEMS` to `CUE` | Hot cue A | 28 ms |
| 17 | 1 | `SAMPLE` to `FX`, with the gap | `REVERB` | 43 ms |
| 18 | 1 | `FX` to `SAMPLE`, with the gap | `SIREN` | 55 ms |
| 19 | 1 | `SAMPLE` to `ROLL`, with the gap | 4 | 57 ms |
| 20 | 1 | `ROLL` to `STEMS`, with the gap | `SOLO V` | 57 ms |
| 21 | 1 | `STEMS` to `LOOP`, with the gap | 1/4 | 48 ms |
| 22 | 1 | `LOOP` to `CUE`, with the gap | Hot cue B | 37 ms |

Each row of the frame tiles runs from the frame before the page change, through the change, to about 150 ms after. Screenshot: s1-tab.png, s1-first-seven-frames.png, s1-pairs-1-to-8.png, s1-pairs-9-to-16.png, s1-pairs-17-to-22-gapped.png

### S4: where each press landed
The key's face is x 737 to 782 pt, y 4 to 21 pt. Each row deleted hot cue F first, then read `library.json`.

| Press at | Off the face by | Cue back? |
|---|---|---|
| (760, 0) | 4 pt above | Yes |
| (760, 25) | 4 pt below | Yes |
| (786, 12) | 4 pt right | Yes |
| (733, 12) | 4 pt left | Yes |
| (760, 33) | 12 pt below | No, as it should: the capsule stayed, and the tap moved deck 1 on its overview |
| (760, 12) | On the key | Yes |

Screenshot: s4-undo-key.png

### T6: every section
From `library.json`, and matching the strips. Also in t6-sections.txt.

**Exhilarate, 2:25, 4 sections**
| Section | Start | Length |
|---|---|---|
| `CHORUS` | 0:00 | 35.6 s |
| `VERSE` | 0:35.6 | 22.5 s |
| `CHORUS` | 0:58.1 | 78.8 s |
| `OUTRO` | 2:16.9 | 8.6 s |

**Severe Tire Damage, 6:52, 11 sections**
| Section | Start | Length |
|---|---|---|
| `INTRO` | 0:00 | 16.1 s |
| `CHORUS` | 0:16.1 | 118.7 s |
| `UP` | 2:14.8 | 10.8 s |
| `CHORUS` | 2:25.6 | 75.5 s |
| `UP` | 3:41.1 | 16.2 s |
| `CHORUS` | 3:57.2 | 24.3 s |
| `VERSE` | 4:21.5 | 35.1 s |
| `CHORUS` | 4:56.6 | 27.0 s |
| `VERSE` | 5:23.5 | 48.5 s |
| `CHORUS` | 6:12.1 | 27.0 s |
| `OUTRO` | 6:39.0 | 12.9 s |

## Timings and measurements
CPU wasn't part of the retest, so there's no CPU table this time.

| Measure | Result |
|---|---|
| Tab change to pad reacting | 0 to 73 ms over 29 pairs |
| Tab labels, capital height | 19 px on all nine (`CUE` 20), against 16 px on `SAMPLE` last time |
| `SAMPLE` to `DEL` | 2.7 pt to the outline, 4 pt to the face |
| `DUB` tail, knob one way | Meters moving for 3.8 s after pausing |
| `DUB` tail, knob the other way | Meters moving for 4.2 s after pausing |
| No `DUB` | Body of the meter gone by 0.4 s. One held segment lasted until 2.6 s |
| Meters with one deck | See T5 |
| Both decks, `TRIM` and `MASTER` up | Both master columns in the red and `LIM` lit in 100% of frames. Deck columns 14% and 71% |
| Backup picker appearing | Between 2.5 and 6.5 s |

The `DUB` figures use a new measure, the last frame with any lit LED, so compare them with each other and not directly with part 2's 2.3 to 2.6 s.

## First impressions
Not run: part 3 of the task is only for when the owner asks.
