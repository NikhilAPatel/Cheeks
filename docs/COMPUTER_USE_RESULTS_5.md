# Hands-on results, part 5, 2026-10-31

Commit tested: c5eeab6
Device: iPhone Duo simulator, iOS 27.2, unfolded inner screen (951×669 pt)
Tooling limits:
- **Not testable here:** haptics, how anything sounds, and the headphone output. For audio I used the meters and the app's own recordings. Nobody has listened to the effects or the wrap in reverse.
- **Touch:** synthetic only, with at most two fingers. Both fingers go down together, so I can't press one and add a second later. For "hold a pad and tap with a second finger", the second finger lands with the first, then slides to a new place for a second touch about 1.5 s later.
- **Timing:** each action and each look at a screenshot takes time, so a control can stay on for much longer than I meant. See the `REV` note under Looks wrong.
- **Dropouts:** the recording is taken ahead of the output, so a glitch in the output device itself wouldn't show.
- **Other sessions:** nothing else ran on this simulator, and nothing reinstalled the app. The other session said its low-priority jobs might be running on this Mac. I didn't ask for quiet, so treat the CPU figures as rough. The audio figures come from the app's own recordings.
- **Not checked:** anything at iPad size. Parts 1 to 3 weren't run, as the task says to run them only if the owner asks.

## Summary
24 tests: **23 PASS, 1 FAIL (AB3), 0 BLOCKED.** No crashes and no crash reports. The app ran as one process from 14:09 to the end.

Every fix from part 4 that the retest covers works: the end of a track, a seek during a roll, loops in reverse, the waiting loop's size pad, `SLIP` during a loop, `CRUSH` levels and the shared split. The reverse wrap, the likeliest new bug, is clean: 7 wraps with no step beyond what the music has at that spot.

The 3 most important problems:
1. **A held roll or slice sticks if its pad leaves the screen (AB3).** Hold a `ROLL` pad and change tab, or press `BROWSE`, with a second finger. When both fingers lift, the deck stays in the 1/4-beat roll. `EXIT` doesn't really clear it: the track's place is lost, and the next ordinary roll sticks too. This is easy to do with a real finger.
2. **Saved loop pads light the wrong one.** Go straight from one running saved loop to another and the old pad stays lit, with the new one dark, until something redraws them.
3. **`SAVE LOOP` during a latched `ROLL` saves the roll's own half-beat loop,** not the loop that was running.

`CRUSH` alone and `CRUSH` with `PHASER` now read 0% on both tracks. `FLANGER` on Severe Tire Damage still reaches the red on the deck column: 16.2% and 8.2% in two runs, against the under 1% measured offline.

No stop I couldn't explain this round. Deck 2's old stop didn't come back, either way round.

## Failures
Causes below are leads from reading the code, not confirmed diagnoses.

### AB3: A held `ROLL` or `SLICER` pad sticks when its pad leaves the screen
- Steps: deck playing, on the `ROLL` page. Put one finger on the `1/4` pad and a second on the `CUE` tab, hold 2 to 3 s, then lift both.
- Expected: the roll ends with the finger, and a hot cue can then be pressed.
- Actual:
  - **The deck stays in the roll with nothing held.** `EXIT` lit, `1/4` on the length key, the clock stuck at 03:22.3 to 03:22.4 for at least 16 s after the lift. Screenshot: stuck-roll-frames.png, stuck-roll-16s.png, stuck-roll-after-tab.png
  - **The same with a held `SLICER` pad** and a second finger on the `CUE` tab. Screenshot: stuck-slice-after-tab.png
  - **The same with the `ROLL` pad and a second finger on `BROWSE`.** It's still stuck after the browser closes. Screenshot: stuck-roll-after-browse.png
  - **The same going to `MEM`.** Screenshot: stuck-roll-mem-recall.png
- What gets out:

  | From the stuck roll | Result |
  |---|---|
  | `EXIT` | The loop ends, but the deck plays on from the roll's spot (03:23.3), at least 20 s behind where the track had got to. Screenshot: stuck-exit-then-roll.png |
  | A new `ROLL` pad, pressed and lifted, after that `EXIT` | **Sticks again:** `EXIT` lit at 03:26.6, with the same reading 2 s later. Screenshot: stuck-exit-then-roll.png |
  | Overview | Clears it. An ordinary roll then works (02:10.9, and 02:13.3 after a 1 s roll). Screenshot: stuck-seek-clears.png |
  | Hot cue | Clears it. The deck goes to the cue and plays. Screenshot: ab4-running-loop.png, first frame |
  | Memory cue | Clears it. Screenshot: stuck-roll-mem-recall.png |

  So the first half of the test works: a hot cue reached this way lands on the cue. I've failed the test because the tab change gets there by leaving a stuck roll.
- Leads:
  - `pad(_:)` swaps the whole page on `padMode` (`Cheeks/UI/Deck/PadSection.swift:185`), so the held pad's view goes away. I'd guess its `touchesEnded` never arrives, so `onRelease` and `rollEnd` don't run.
  - `TouchSurface` only ends a touch from `touchesEnded` and `touchesCancelled` (`Cheeks/UI/Controls/TouchSurface.swift:76`), with nothing for leaving the window.
  - `heldMomentaryPads` then stays at 1. That fits a new press going to 2 and its lift to 1, which never reaches the release. `endMomentaryPads` (`Cheeks/Audio/Deck+Performance.swift:354`) resets it, which fits a seek or cue clearing it. `exitLoop` (`:254`) doesn't.
- Not tried: other things that could take a held pad away, such as a sheet opening from Settings, or anything other than `ROLL` and `SLICER` that acts on release.
- Crash report: none.

## Looks wrong
- **Saved loop pads light the wrong one.** On `MEM`, with the 2:18 saved loop running, tap the 3:11 one. The deck goes to 3:11 and loops, but the 2:18 pad stays lit and 3:11 stays dark. The reverse is the same. Changing tab and coming back corrects it. Tapping the dark pad works properly, since it ends the loop that's really running. Lead: `MemoryPad.isOn` (`Cheeks/UI/Deck/PadSection.swift:313`) reads the renderer's loop points through `isCurrentLoop`, which aren't observed, and `loopActive` stays true across the change, so nothing redraws. Screenshot: mem-pad-lights-1.png, frames 1 and 4. mem-pad-lights-2.png, frames 2 and 4.
- **`SAVE LOOP` during a latched `ROLL` saves the roll's loop.** Deck 2 in its 4-beat saved loop at 1:04, `ROLL` on at `1/2` on the `FX` page, then `MEM` and `SAVE LOOP`. A new `1:05` pad appears, and `library.json` has it at 65.666 s, half a beat long. After the roll, the deck is back in the 4-beat loop. Lead: `saveCurrentLoop` (`Cheeks/Audio/Deck+Performance.swift:100`) reads the renderer's loop, while the real one is in `BorrowedLoop`. Screenshot: save-loop-in-roll.png
- **`UNDO` is ignored if pressed straight after the delete.** It looks like timing, not press length. The capsule is up each time:

  | What was deleted | Gap after the delete | Press | Result |
  |---|---|---|---|
  | Saved loop | None | 0.1 s | Ignored |
  | Memory cue | None | 0.1 s | Ignored |
  | Memory cue | None | 0.2 s | Ignored. A second 0.1 s press 1 s later worked |
  | Memory cue | About 0.4 s | 0.1 s | Worked |
  | Memory cue | About 1.6 s | 0.1 s | Worked |
  | Saved loop | About 2 s | 0.2 s | Worked |

  "None" means sent as soon as the last tap returned. A hand has to travel from the pad to the top of the screen, so this may never happen in use. Each cue came back with the same ID. Lead: the capsule scales in from half size for about 0.4 s (`Cheeks/UI/Shell/ContentView.swift:410`), which could move the key while it's arriving. Two more presses of mine came after the 8 s and don't count. Screenshot: undo-missed.png, undo-works.png
- **`FLANGER` on Severe Tire Damage still reaches the red** on the deck column at default levels: 16.2%, then 8.2% on a repeat, reloading first each time. Master columns 0%, `LIM` 1.6% and 0.8%. See AE1 below. Screenshot: ae1-flanger.png
- **`LIM` still lights below the red,** at 0.1 to 1.6% of frames on three of the Severe Tire Damage rows, with one deck playing and no red on the master columns. It's already noted in part 4's follow-up.
- **`REV` reaching the start of a track doesn't stop.** It sits at 00:00.0 with `PLAY` lit, and carries on forward when `REV` goes off. It's harmless, and there's nothing to hear. Screenshot: runout-rev-at-start.png
- **The first two frames of one AB2 run barely moved:** 02:09.7 and 02:09.8, stamped 0.9 s apart, with the pad held and the key at `RELOOP`. Every frame after that ran at normal speed. Most likely it's screenshot timing, but I can't rule out a brief hold.

**Not faults, but they caught me out:**
- During the stress run deck 1 looked to have jumped back about a minute. It hadn't. `REV` was still on while I read a screenshot: 02:16.5 at 49:06, less 33 s in reverse, plus 5 s forward, is the 01:48.5 I then saw at 49:44. Screenshot: stress-rev-left-on.png
- My first TRIM control read 0% because deck 2 had run out by then. With the deck playing it read 100%.
- My first AC2 attempt set a loop at the very last frame, and is why I checked that case. `PLAY` got out of it, starting from the cue with the loop dropped.

## All results
| Test | Result | Notes |
|---|---|---|
| AA1 | PASS | Stops at -00:00.0. `PLAY`: 00:21.5 one second later, from the cue at 00:20.1. Screenshot: aa1-play.png |
| AA2 | PASS | `CUE` held 3.5 s: plays from the cue (00:22.8 at 2.5 s). Let go: back to 00:20.1, so the cue didn't move. Screenshot: aa2-cue.png, aa2-frames.png |
| AA3 | PASS | Hot cue at 0:41.2: 00:42.6 about a second later, playing. `RELOOP`: 00:43.0 with `EXIT` lit, playing. Overview: 01:16.4, stopped. Screenshot: aa3-hot-cue-reloop.png, aa3-overview-aa4-cue.png |
| AA4 | PASS | Paused at 01:19.2, `CUE`: it stays there, rather than going back to the old cue at 01:16.3. Screenshot: aa3-overview-aa4-cue.png |
| AB1 | PASS | `ROLL` and the dot go out at once. The deck plays on from 02:00.7 to 02:05.4 with no jump. `ROLL` works again from there: held at 02:19.1, then 02:24.1 after letting go. Screenshot: ab1-roll.png, ab1-frames.png, ab1-roll-again.png |
| AB2 | PASS | Held `1/4` pad with the second finger on the overview, in both finger orders. The deck plays on from the overview, a slide seeks again, and the lift moves nothing: 02:28.9, then 02:29.8 across it. Screenshot: ab2-held-roll.png, ab2-held-roll-2.png |
| AB3 | **FAIL** | Changing tab or opening the browser with a pad held leaves the roll stuck. See Failures. Held `SLICER` with the overview is fine: lift moves nothing. Hot cue during a latched `ROLL` is fine: 04:15.4, then 04:19.1. Screenshot: ab3-held-slicer-overview.png, ab3-hot-cue-latched.png |
| AB4 | PASS | 4-beat loop at 02:10. Held roll and overview: 03:39.0 with `RELOOP`, playing on. `RELOOP`: 02:10.8 with `EXIT` lit and `4` on the key. Screenshot: ab4-running-loop.png |
| AC1 | PASS | 8.75 s in `REV` on Severe Tire Damage, about 6 times round, read back from the recording. `EXIT` stays lit. `REV` off: forward, still in the loop. On Exhilarate: 7 wraps. Screenshot: ac1-rev.png |
| AC2 | PASS | `REV` on and off in a `SLIP` loop stays in the loop. `EXIT` lands at 02:11.6, which is 10.8 s after 02:00.8, in 10.8 s of clock. Screenshot: ac2-slip-frames.png |
| AC3 | PASS | `ARMED` with the deck before the loop. `REV`: 01:56.3 to 01:53.0 in 3 s, still `ARMED`. Screenshot: ac3-waiting-loop.png |
| AC4 | PASS | In a loop at 01:35, jogging back past the start: 01:32.2 with the key at `ARMED`. It plays forward, and at 01:35.5 it's in the loop with `EXIT` lit. Screenshot: ac4-jog.png, ac4-jog-frames.png |
| AC5 | PASS | No step at a wrap beyond the music's own. See below. |
| AD1 | PASS | `ARMED` with the `4` pad unlit. Tapping it starts a loop at the deck, with `EXIT` lit. The saved loop in `library.json` is unchanged. Screenshot: ad1-pad.png |
| AD2 | PASS | Loop at 01:35 with `SLIP` off. `SLIP` on, a 3 s roll, `EXIT` 14.1 s after `SLIP` went on: 01:50.5. Allowing for where in the 1.3 s loop it was, that's about 14 s on. Screenshot: ad2-slip.png |
| AE1 | PASS | `CRUSH` 0% and `CRUSH` with `PHASER` 0%, on both tracks. Nothing ran before them: I reloaded before each row, and the effect went on before `PLAY`. `FLANGER` on Severe Tire Damage: see Looks wrong. Table below. Screenshot: ae1-levels.png |
| AE2 | PASS | The dot shows on `STEMS` and goes with the last effect. `FX` starts at 789.7 pt and `SAMPLE` at 810.7 pt, with or without it. `STEMS` to `FX` is 12.3 to 12.7 pt with it and 12.7 without. Screenshot: ae2-dot.png, ae2-dot-goes.png |
| AE3 | PASS | The tail is there, and it falls no faster than an echo stopped by a pause. See below. Screenshot: ae3-echo-out.png |
| AF1 | PASS | Both counters match at every sample: 1, 17, 32, 48, 63, 80, 96%. They finish together, leaving one stems file. Screenshot: af1-split.png, af1-counters.png |
| AF2 | PASS | Exhilarate on both, 28% on both. Deck 1 loads the other track, and deck 2 carries on: 32%, 76%, done, and its file is written. Screenshot: af2-counters.png |
| P1 | PASS | `BRAKE` plain, in a loop, during a latched `ROLL` and with `SLIP`: each stops cleanly and `PLAY` restarts it. In a loop it stops in the loop with `EXIT` lit, and carries on inside it. The roll keeps its place while stopped. Screenshot: brake-plain.png, brake-loop.png, brake-roll.png, brake-slip.png |
| P2 | PASS | 10 min 26 s with memory cues and saved loops recalled over running loops, latched rolls, `REV` and an echo out. No crash, no dropout found, no control stopped responding. It did turn up the wrong pad lights, `SAVE LOOP` and `UNDO` above. See below. Screenshot: recall-during-roll.png, stress-mem-rev.png |
| P3 | PASS | Latched at 02:15.3, 13 s later let go: stops at -00:00.0, as it should. `PLAY` gets out. The old way round: latched, seek to 00:53.1, 13 s later still playing at 01:06.7. `ROLL` tapped twice from there works, and it never stops. Screenshot: deck2-stop-both-ways.png |
| P4 | PASS | Ran out with `SLIP`, `ECHO`, an echo out, a loop left by `EXIT` and a loop crossing the end, and `REV` back to the start. Each stops cleanly, or holds in the loop, and `PLAY` gets out every time, not silently. Screenshot: runout-slip-echo.png, runout-echo-out.png, runout-loop.png, runout-loop-over-end.png, runout-rev-at-start.png |

## Timings and measurements

**AC5, sample steps at the wraps.** Exhilarate from a plain path, with 4 beats at 170.59 BPM, which is a 1.407 s loop at 69.92 to 71.33 s. I followed the recording through the decoded track sample by sample, and it found 16 wraps and both `REV` changes, each at the expected place.

| Stretch | Wraps | Largest step within about 12 ms of a wrap |
|---|---|---|
| Forward, in the loop | 9 | 0.226 to 0.251 |
| `REV`, in the loop | 7 | 0.226 to 0.251 |
| The same spot on a clean pass, no wrap | | 0.227 |

Across a wrap, per millisecond, 6 ms before to 6 ms after:

| | -6 | -5 | -4 | -3 | -2 | -1 | 0 | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Forward | .032 | .033 | .033 | .030 | .029 | .098 | .128 | .174 | .190 | .187 | .149 | .201 | .166 |
| `REV` | .173 | .150 | .169 | .125 | .133 | .108 | .090 | .052 | .036 | .050 | .055 | .048 | .048 |

- The two runs are the same music in opposite directions, and neither has a spike at the crossing. The step grows or falls with the music.
- `REV` going on has a largest step of 0.129 nearby, and going off 0.078.
- The direction changes in place: 71.067 s forward becomes 71.072 s backward.
- Plain playback reaches 0.413 elsewhere in the same track.

**AE1, default levels, about 13 s per row.** Red share by column, reloaded first each time. Severe Tire Damage is on deck 1 from about 2:09, Exhilarate on deck 2 from 0:53.

| Effect | Severe Tire Damage: deck / master L / R / `LIM` | Exhilarate: deck / master L / R / `LIM` |
|---|---|---|
| None | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 |
| `ECHO` | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 |
| `PING PONG` | 0 / 0 / 0 / 0.1 | 0 / 0 / 0 / 0 |
| `SPIRAL` | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 |
| `REVERB` | 0 / 0 / 0 / 0.9 | 0 / 0 / 0 / 0 |
| `FLANGER` | **16.2** / 0 / 0 / 1.6, repeat **8.2** / 0 / 0 / 0.8 | 0 / 0 / 0 / 0 |
| `PHASER` | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 |
| `FILTER` | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 |
| `CRUSH` | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 |
| `CRUSH` and `PHASER` | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 |

- Each row's end screenshot was checked by brightness at each pad: only the intended pads were lit.
- Control: Exhilarate with `TRIM` up reads 100 / 100 / 95.6, with `LIM` lit in 81.4% of frames, so the method does see red.
- Last round's `CRUSH` row was measured straight after other effects. This round, nothing ran before it.

**AE3, echo out.** On Exhilarate, in 0.25 s windows from the recording. `OUT` on a dry deck, against a pause with `ECHO` on:

| | Before | Tail, dB per window |
|---|---|---|
| `OUT` | -15 | -21.6, -28.8, -34.3, -40.4, -45.5, -51.4, -56.4 |
| Pause with `ECHO` on | -14 | -19.5, -26.7, -32.2, -38.2, -43.8, -49.8, -55.1 |

The two fall at the same 5.5 to 6 dB per window and sit within about 2 dB, though the windows aren't lined up with the events. On the meters, the master left column goes from about 5,870 lit pixels to 920, 148 and then nothing, a second apart. Whether that's long enough is for someone listening.

**P2, the stress run, 15:12:12 to 15:22:38:**
- **What ran:** memory cues and saved loops from `MEM` on both decks, over running loops, latched rolls and an echo out, and in `REV`. Deleting a running saved loop, and `UNDO`. Held rolls and slices on both decks at once, stem presets, FX chains, `BRAKE`, `BACKSPIN`, Color FX with knobs, tempo moves, both jogs, sampler pads, `SLIP`, `SYNC` and a recording. Deck 2 ran out once and I restarted it.
- **Time stays right:** after rolls and slices on both decks, deck 1 reads 01:48.5, 01:52.9 and 01:54.7 at 49:44, 49:48 and 49:50 on the recording timer.
- **CPU on this simulator's process:** 58 samples of 2 s, average 17.7%, highest 27.1%. This is a simulator on a Mac, not the phone.
- **Memory:** 436 MB at the start, rising to about 510 MB by 15:19, then flat for the last 3 minutes.
- **Master meters over the last 141 s of video:** never below 15% of their usual reading, with no frame gap over 0.095 s.
- **Log:** no audio overload message and no hang warning, from launch to the end. The errors logged are all system framework lines, mostly `image provider timed out`, as in earlier rounds.

**The mix.** Not asked for, but it was running from 14:27:34 to 15:22:38.
- 55:05.4 long, against about 55:04 by the clock.
- `.cue` and `.txt`: Severe Tire Damage at 00:00, which was already playing. Exhilarate at 23:16.97, which is 14:50:51, when the first Exhilarate row of AE started.
- Over the 625 s of the stress run: no gap of 30 ms or more below -50 dB.

**AF, the split:** a little over 2 minutes for Severe Tire Damage in the simulator, at about 160% CPU, with both decks loaded.

## First impressions
Not run, as the task says to run part 3 only if the owner asks.
