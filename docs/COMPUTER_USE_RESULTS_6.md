# Hands-on results, part 6, 2026-11-01 to 02

Commit tested: e78e56e
Device: iPhone Duo simulator, iOS 27.2, unfolded inner screen (951×669 pt)
Tooling limits:
- **Not testable here:** haptics, how anything sounds, and the headphone output. For audio I used the meters and the app's own recording. Nobody has listened to the changed flanger.
- **Touch:** synthetic only, with at most two fingers, and both land together. So "held" pads were only held from the same moment as the second finger. I can't hold `CUE` and add `PLAY` later, so that case is untested.
- **Reaching things with a pad held:** `DEL` and `SAVE LOOP` aren't on the `ROLL` page, so I pressed deck 2's while holding a deck 1 pad.
- **Backgrounding:** done with `simctl launch` of Settings from a shell job during the hold, and `simctl launch` of the app to return. Not a real home gesture or a real call.
- **Double-tap:** tool taps arrive over 0.3 s apart, so I can't double-tap. I reset knobs by dragging them back to the detent.
- **Run by two sessions:** the first stopped partway, and a new one finished it on 2 November. Everything below AG was run or re-run by the second.
- **Other sessions on this Mac:**
  - **Load:** the load average was 67 to 170 through AG, and 40 to 940 for much of the rest, though the busiest processes added up to only a few cores. Treat load average as unreliable here. `top` also hung for minutes at a time.
  - **Interruptions:** another project's session took the Duo's foreground from about 10:20 to 10:30, and a compile from the fix session ran from about 10:16 to 10:27. Free disk also fell from 30 GB to 1 GB at about 11:10, until the owner freed it. I never found what filled it. Cheeks wasn't the cause: 10 threads, 18.7% CPU and a 687 MB data folder at the time.
  - **What I re-ran:** every row affected by those was re-run or thrown out.

## Summary
25 tests: **24 PASS, 1 FAIL (Pressing harder 1), 0 BLOCKED.** No crash from this build. The app ran as one process (PID 31105) from 15:54 on 1 November to the end.

Every fix on the retest works: held controls let go when their view goes, saved loop pads light straight away, `SAVE LOOP` during a roll saves the right loop, `UNDO` works straight after a delete, and `REV` stops at the start. `FLANGER` on Severe Tire Damage now reads **0% red in all 3 runs**, and so does every other row on both tracks, with `LIM` never lit.

The 3 most important problems:
1. **One ordinary roll didn't return (Pressing harder 1).** After `EXIT` pressed with a held roll, the next plain roll held for 1.0 s and then carried on from where it was, so the deck lost that second. Seen once, in about 30 plain rolls. Three deliberate repeats didn't bring it back.
2. **A deck's meter can freeze after the app's been away.** It holds a level and a peak LED with the deck silent, until that deck next plays. I can reproduce it. See Looks wrong.
3. **`PLAY` straight after a load key does nothing, with no message.** See Looks wrong.

**The first session's AH figures were wrong, and are replaced here.** Its meter script misread the video, and almost none of its rows really reloaded. See Timings.

## Failures
Causes below are leads from reading the code, not confirmed diagnoses.

### Pressing harder 1: a plain roll after `EXIT` didn't go back
- Steps: deck 1 playing, on `ROLL`.
  1. `1/4` with `IN`, held 1.5 s. A plain roll.
  2. `1/4` with `OUT`, held 1.5 s, about 25 s later. This made a 63-beat loop with the deck inside it. A plain roll.
  3. `1/4` with `EXIT`, held 1.5 s. On the lift the deck jumped 1.8 s, as it should. `RELOOP` showed and the loop was off.
  4. About 2.4 s later, a plain roll: `1/4` held for 1.0 s.
- Expected: the clock holds, then jumps about 1.0 s on release, as it did for every other plain roll.
- Actual: the pad's lit from 5.3 to 6.4 s on the video, with `EXIT` and `1/4` on the key row. The clock holds at -02:49.4, then carries on from -02:49.3 with no jump. Over the clip the clock moved 6.7 s in 7.72 s, so the deck lost 1.0 s. `RELOOP` and `4` came back as they should, and nothing stayed stuck: the next rolls worked.
- Repeats that didn't show it:
  - The same `EXIT` on a loop brought back with `RELOOP`: rolls of +1.1 and +1.1.
  - `IN`, `OUT` and `EXIT` with a 4.7 s loop: +1.0, +1.0 and +1.1 and +1.1 after `EXIT`.
  - The same with a 16.9 s loop, including a roll inside the loop's span: all +1.0 or +1.1.
- Leads: in `momentaryPadReleased` (`Cheeks/Audio/Deck+Performance.swift:320`), every path I can follow from a loop that's off ends in `releaseSlip`, which should jump. Carrying on from where it is looks like `cancelSlip`, which `endMomentaryPads` (`:357`) calls. I couldn't find what would have called that here. It happened at about 11:29, during the period of very high load averages, and the clip shows nothing else unusual.
- Screenshot: ph1-lost-second.png, with frames at 5.2, 6.2 and 6.6 s. Before 04:02.3, during 04:02.4, after 04:02.7. It would have been about 04:03.7.
- Crash report: none.

## Looks wrong
Causes below are leads, not confirmed diagnoses.

- **A deck's meter freezes after the app's been away.**
  - **Steps:** deck playing with `SPIRAL` on. `PLAY` to stop it, then send the app away within about a second, for 20 s, and bring it back.
  - **What it shows:** the deck's column holds 15 LEDs and an amber peak with the deck stopped and the master columns dark. It's the same at 2, 10 and 20 s, and it doesn't change when the other deck plays and stops, when the browser opens and closes, or when `SPIRAL` goes off. Playing that deck clears it.
  - **Other cases:** the same steps without going away are clean at 3, 15 and 40 s. It also happened by accident when another app took the foreground for 10 minutes. Not tried without an effect.
  - **Lead:** `LiveRenderer.frame` calls `view.update()` before `nextDrawable()` (`Cheeks/UI/Live/LiveRenderer.swift:76`). `MeterLiveView.update` moves `lastDrawn` on whether or not a drawable comes. So if the meter falls to nothing while the app's away, its uniforms already match on return, and the last frame stays up.
  - Screenshot: meter-frozen.png, at 2, 10 and 20 s.
- **`PLAY` straight after a load key is lost, with no message.** With the browser open, I tapped a deck's load key and its compact `PLAY` about 0.3 s later. 3 and 6 s on, the deck sat stopped at its cue with `PLAY` unlit and no capsule. Lead: `finishLoading` sets `isPlaying` false (`Cheeks/Audio/Deck.swift:373`). This replaces the first session's note on `PLAY` during a reload, which came from reloads that hadn't happened.
- **A seek during a load can be lost.** The first session's overview taps about 3 s after a load key lost their seek twice on deck 2, and started from the top of the track. Lead: `finishLoading` ends with `seek(to: cuePoint)`, so a slow load overrides a seek made while it ran. With 5 s or more after the load key, no seek was lost in about 30 rows. I didn't test this directly.
- **The jog stays held for about 5 s after the app goes to the background (AG8).** A held roll lets go at that moment, but the jog doesn't. With the jog held, the clock moved 1.4 s in 7.21 s away, and 3.8 s in 8.75 s away. It then lets go by itself, and on return the deck runs normally: 12.4 s of clock in 12.4 s. Lead: `TouchSurface` watches `willResignActive`, and `JogLiveView` only has `didMoveToWindow` (`Cheeks/UI/Live/JogLive.swift`), so the jog waits for the system to cancel the touch. Screenshot: ag8-background.png
- **`ECHO` and `PING PONG` together reach the red.** By accident, on a row that didn't reload, both were on at default depth on Exhilarate from 0:53. The deck 2 column was red for 15.5% of 16.6 s (5.47 to 8.01 s and at 16.48 s). Master and `LIM` stayed clear. The task doesn't ask for this pair, and I ran it only once. Screenshot: ah-echo-pingpong-red.png
- **`UNDO`'s touch area sits a little left of the key.** On the "Deleted hot cue A" capsule the drawn key is about x=746 to 785. Presses at x=736, 740, 784 and 788 work, and x=792 missed twice. So it reaches 10 pt past the left edge, and less than 7 pt past the right. It's harmless, as 3 pt past every edge works.
- **Deck 2's `BEAT JUMP` went from 4 to 8 with no press on it,** once, for the first session. It wasn't seen again in about 20 more reloads of that deck.

**Not faults, but they caught me out:**
- **A very busy Mac loses load key taps.** The browser can take over 1 s to open, so a tap sent 1 s after `BROWSE` lands on the old layout. That's the likely reason the first session's reloads mostly didn't happen.
- **`OUT` turns `ECHO` off,** if it was on, and it stays off after the second `OUT`. That's what `toggleEchoOut` does (`Cheeks/Audio/Deck+Performance.swift:630`).
- **`BRAKE` leaves the deck stopped.** `PLAY` starts it again.
- **A `SLICER` pad pressed on a deck that's run out starts it from the cue,** because `sliceBegin` calls `play()`.
- **`CUE` on a paused deck sets the cue where it is,** so my later `CUE` tests were at 03:29.6, not the track's first beat. It's CDJ behaviour, and it's in the code's comment.
- **A second finger resting on the overview can seek again.** My tool's still sample 0.8 s after landing moved the deck back 0.8 s to the same spot, with the pad finger listed first. A real finger's small slide would do the same.

**Two more reports exist, and they aren't from this build.** `Cheeks-2026-11-02-103257.ips` and `-103308.ips` are from simulator 40DDC0B7, in `AutoDJTests`: an exclusivity conflict in `AutoDJ.mixSet` from `AutoDJ.stopForTesting()`. That's the fix session's Auto DJ work.

## All results
| Test | Result | Notes |
|---|---|---|
| AG1 | PASS | Held `1/4` with a finger on the `CUE` tab, both finger orders. The roll ends with the fingers still down, about 0.57 s after the page changes, and the deck lands where the track has got to. The key's back at `RELOOP`. A plain 1.5 s roll afterwards ends when let go: the clock jumps 1.6 s. Screenshot: ag1-roll-tab.png |
| AG2 | PASS | Held `SLICER` pad with `MEM`: ends 0.59 s after the page changes, landing at 147.5 s remaining against 147.57 expected. With `BROWSE`: 02:24.6, then 02:30.0 in the browser 5.3 s later, 02:32.6 after 2.6 s more, and 02:36.3 after closing 3.7 s later. Screenshot: ag2-browse.png |
| AG3 | PASS | Paused at the cue, 02:53.1. Round `CUE` with `BROWSE`, held 2 s: 02:53.1 and stopped after the lift, with `PLAY` unlit, and the same after closing. Screenshot: ag3-cue-browse.png |
| AG4 | PASS | `ECHO` with the `CUE` tab, held 2 s: no dot, and `ECHO` unlit back on the page. Checked twice, the second time on the quieter Mac. Tapped quickly: the dot shows on `CUE`, and `ECHO` is lit back on the page. At about 0.57 s of delay, the same press counts as held, not as a tap. Screenshot: ag4-fx.png |
| AG5 | PASS | `RISER` set to gate. Held 3 s alone: 2.9 s of sound in the recording. Held 3 s with the `CUE` tab: about 0.4 to 0.5 s of sound, then nothing. |
| AG6 | PASS | Jog's middle with `BROWSE`, held 2 s. The deck runs normally in the browser (2.7 s of clock in 2.64 s) and after closing (2.8 s in 2.74 s), and isn't stuck. It lost about 1.04 s overall, so the jog let go about 1 s after the press. Screenshot: ag6-jog.png |
| AG7 | PASS | Deck 2, `1/4` with the gear, held 3 s. The clock holds for 3.2 s and jumps exactly 3.2 s on the lift, with the sheet still up. `RELOOP` unlit after closing. I can't close the sheet with a finger still down, so the order differs from the task's. Screenshot: ag7-sheet.png |
| AG8 | PASS | A held roll lets go the moment the app goes away: held 13.4 s and 12.7 s, jumping by exactly that each time. On return the clock is where it should be (313.3 s remaining against 320.8 less 7.47 s), so the audio ran on in the background. Same PID. The jog is different: see Looks wrong. Screenshot: ag8-background.png |
| AH1 | PASS | `FLANGER` on Severe Tire Damage, 3 runs from 02:07.2, 02:11.1 and 02:15.1: 0% red on every column. Each with a real reload, and the deck's first moments on video. Screenshot: ah1-flanger.png |
| AH2 | PASS | `PHASER`, `PING PONG`, and `CRUSH` with `PHASER`, 3 runs each on Severe Tire Damage, and the rest once each on both tracks: all 0%. Table below. |
| AH3 | PASS | `LIM` never lit on any row, against 0.1 to 1.6% on three rows last time. |
| AH4 | PASS | The tail is unchanged, within about 1 dB of last time. Table below. Screenshot: ah4-echo-out.png |
| AI | PASS | Two saved loops, 2:18 and 3:11. On video, the old pad goes dark and the new one lights within 30 ms, in both directions, over 3 changes. No hot loop was set, and only a rekordbox import can set one, so that part wasn't run. Screenshot: ai1-pads.png |
| AJ1 | PASS | 4-beat loop, `ROLL` on at `1/2`, then `MEM` and `SAVE LOOP`: `library.json` gets 218.03 to 219.38 s, which is 4 beats. Pressed again: a hand and "This loop's already saved." With the roll off, the deck's in the 4-beat loop at 03:39 with its pad lit. Screenshot: aj1-saved.png |
| AJ2 | PASS | Reloaded, so no loop, the same steps: a hand and "Set a loop first, then save it." The file still has 3 loops. |
| AK | PASS | Memory cue, saved loop and hot cue, 5 times each at 0.1 s and 5 at 0.2 s: 30 of 30 back on the first press, each confirmed on video. Pad gone to pad back was about 0.55 to 0.93 s, including the tool's own delay, so this is as soon as the tool can press. Gaps of 0.4 s and 2 s: 6 of 6. Just past the key: 3 pt past each edge works. See Looks wrong. One press of mine came after the capsule's 8 s and doesn't count. Screenshot: ak1-undo.png |
| AL1 | PASS | Stops at 00:00.0 with `PLAY` unlit and `REV` still lit. Screenshot: al1-rev-start.png |
| AL2 | PASS | A hand and "Deck 1 is at the start. Turn REV off to play it forward." `REV` off and `PLAY`: it read 00:05.2 a few seconds later, so it plays forward. |
| AL3 | PASS | Hot cue at 02:37.9 with `REV` on, from a stopped deck: 02:37.7, then 02:33.2. |
| AL4 | PASS | With `SLIP` on, the same stop and the same refusal. `REV` off jumps to where slip had got to when the deck stopped (00:07.4) and stays stopped, with `PLAY` unlit. `PLAY` then plays on. Hot cue with `REV` and `SLIP`: runs back from 02:37.9, and `REV` off jumps to 00:21.7, the old timeline, playing on from there. |
| AL5 | PASS | Q off, loop from 00:00.0 to about 1.55 s. With `REV` on it reads 1.4, 0.8, 0.2, 1.2, 0.7, 0.2, with `PLAY` and `EXIT` lit, for over 15 s, and doesn't stop. |
| Pressing harder 1 | **FAIL** | One plain roll lost 1.0 s, once: see Failures. Nothing stuck on any target, and every other return was right. Table below. |
| Pressing harder 2 | PASS | `CUE` with `LOOP`, `FX` and `BROWSE`: parked at the cue and stopped each time. `CUE` with `PLAY`, either way round in the tool: stops at the cue, as the app takes `PLAY` first. So I couldn't try `CUE` first with `PLAY` added later. Hot cue pad with `LOOP`, `BROWSE` and `PLAY`: lands on the cue and plays on, nothing stuck. |
| Pressing harder 3 | PASS | 4 videos of a held roll with the overview, both finger orders and a slide. The clock runs at normal speed from the first frame after the jump: 04:44.5, 44.4, 44.3 in steps of 0.08 s. Nothing like last round's slow frames. The lift moves nothing. |
| Pressing harder 4 | PASS | About 10 minutes, 11:48:30 to 11:58:40. No crash, no dropout in the recording, no stop I can't explain. See below. |

## Timings and measurements

**How the first session's AH figures went wrong.**
- **The script:** `meter2.py` cropped to an odd width of 95. ffmpeg rounds that to 94 on 4:2:0 video, so each frame was read at the wrong width, and its reading drifted across the whole meter about every 0.85 s. Its "red" repeated on that beat whatever the music did, and it showed 12.9% red on a paused deck.
- **The fix:** `meter3.py` uses an even width and stops if the bytes don't divide into frames. On the same `TRIM`-up video it reads deck 2 and the master at 100%, `LIM` at 99.3%, and the paused deck 1 at 0%. It also caught deck 2 red alone, checked on the frame by eye. Screenshot: ah-control-trim-up.png, ah-echo-pingpong-red.png
- **The reloads:** `playCount` was 1 for Severe Tire Damage and 2 for Exhilarate after dozens of attempted reloads. Every row below shows the count going up by one.
- **Last round's scripts:** `meter.py` and `drop.py` from round 5 also use an odd width of 17. Their crops are narrow, so the effect is smaller, and that round's control looked right, but its percentages, such as `FLANGER`'s 16.2% and 8.2%, are approximate.

**AH, default levels, 17 s per row.** Each row reloaded first, with the effect on before `PLAY`, and the video started before `PLAY`. Each entry is where the deck started. Every row read 0% red on all four columns and 0% `LIM`.

| Effect | Severe Tire Damage (deck 1) | Exhilarate (deck 2) |
|---|---|---|
| None | 02:07.2 | 00:53.0 |
| `ECHO` | 02:07.2 | 00:53.0 |
| `PING PONG` | 02:07.2, 02:11.1, 02:15.1 | 00:53.0 |
| `SPIRAL` | 02:07.2 | 00:53.0 |
| `REVERB` | 02:07.2 | 00:53.0 |
| `FLANGER` | 02:07.2, 02:11.1, 02:15.1 | 00:53.0 |
| `PHASER` | 02:07.2, 02:11.1, 02:15.1 | 00:53.0 |
| `FILTER` | 02:07.2 | 00:53.0 |
| `CRUSH` | 02:07.2 | 00:53.0 |
| `CRUSH` and `PHASER` | 02:07.2, 02:11.1, 02:15.1 | 00:53.0 |

`FLANGER` and `PHASER` on Severe Tire Damage ran before the load trouble began. The rest of that column was run twice, and these are the runs after it cleared. All of the first runs also read 0%.

**AH4, echo out.** On Exhilarate, in 0.25 s windows from the recording.

| | Before | Tail, dB per window |
|---|---|---|
| `OUT` | -19.5 | -21.2, -28.1, -33.1, -39.8, -44.6, -50.0, -56.0 |
| `OUT`, last time | -15 | -21.6, -28.8, -34.3, -40.4, -45.5, -51.4, -56.4 |
| Pause with `ECHO` on | -13.5 | -18.0, -26.8, -32.7, -39.0, -44.5, -49.6, -55.8 |
| Pause with `ECHO` on, last time | -14 | -19.5, -26.7, -32.2, -38.2, -43.8, -49.8, -55.1 |

**How long a held control lasts after its page changes.** From video frames. The fix session asked for this to be repeated on a quieter Mac, and it didn't change, so it isn't caused by load. The second table's Mac wasn't idle either.

| First session, load average 67 to 170 | Delay |
|---|---|
| `1/4` and `CUE` tab, pad finger first | 0.465 s |
| `1/4` and `CUE` tab, tab finger first | 0.563 s |
| `SLICER` pad and `MEM` | 0.57 s |
| Gate sample and `CUE` tab | About 0.4 to 0.5 s, from the recording |

| Second session | Page changes at | Ends at | Delay |
|---|---|---|---|
| `1/4` and `CUE` tab, pad finger first | 1.123 s | 1.673 s | 0.550 s |
| The same, again | 0.953 s | 1.527 s | 0.574 s |
| `1/4` and `CUE` tab, tab finger first | 1.093 s | 1.668 s | 0.575 s |
| `SLICER` pad and `MEM` | 0.930 s | 1.520 s | 0.590 s |

**Pressing harder 1.** Deck 1 playing, `1/4` held about 1.5 s with a second finger on each of these, then a plain 1 s roll. Times are from video.

| Second finger | On the lift | Plain roll | Clock against time |
|---|---|---|---|
| `LOOP`, `SLICER`, `JUMP`, `STEMS`, `FX`, `SAMPLE`, `MEM` tabs | The roll ended about 0.5 s in, jump +0.5 to +0.6 | +1.0 to +1.2 | 8.6 to 8.8 s in 8.6 to 8.8 s, every one |
| `BROWSE`, then closed | Right on return | +1.0 | 13.8 s in 13.80 s |
| Gear, then `Done` | Right on return | +0.9 | 13.6 s in 13.60 s |
| `REC`, then `Keep recording` | Right on return | +1.0 | 10.8 s in 10.76 s |
| `IN` | +1.6, `IN` lit | +1.0 | 7.7 s in 7.76 s |
| `OUT` | -19.6, landing 1.6 s into the new 63-beat loop, which is right | +1.1 | Right, allowing for the loop |
| `EXIT` | +1.8 | **No jump, once.** See Failures | 6.7 s in 7.72 s |
| `RELOOP` | Back into the loop at the press (-47.3), +1.7 on the lift | +1.0 | Right, allowing for the loop |
| Length `<` | +1.5, the key read 2 afterwards | +1.0 | 7.7 s in 7.76 s |
| `REV` | +1.6 | +1.0, with `REV` turned off first | Right, allowing for the time in reverse |
| `SLIP` | +1.6 | +1.0, with `SLIP` turned off first | 9.7 s in 9.68 s |
| `Q` | +1.5 | +1.2 | 9.4 s in 9.40 s |
| `PLAY` | Stopped, no jump, then started again | +1.0 | Right, allowing for the stop |
| `CUE` | Back to the cue and stopped | +1.0 | Right, allowing for the stop |
| Crossfader, out and back | +1.5, and it caught the centre | +1.0 | 9.4 s in 9.36 s |
| Deck 2's `SAVE LOOP`, then its `DEL` | +1.6 and +1.7 | +1.1 | 9.8 s in 9.76 s |

**Pressing harder 4, 11:48:30 to 11:58:40.**
- **What ran:**
  - **Loops:** saved loops running and swapped on both decks, including in `REV`; `SAVE LOOP` and `SAVE CUE`; `RELOOP` and `EXIT`; loop length keys.
  - **Rolls and pads:** plain and two-finger rolls, slices, beat jumps, hot cues, `DEL` and `UNDO`.
  - **Effects:** stem mutes, solos and presets; FX chains with `DEPTH`; `BRAKE`, `BACKSPIN` and `ROLL`; two echo outs, one pausing during it and one left on for 90 s; Color FX with knobs.
  - **Deck moves:** jogs, tempo faders, sync, the crossfader.
  - **Screens:** sampler pads, `LIST`, a refused load.
  - **Tracks:** a deck run out and restarted, and the same track loaded on both decks.
- **Time stays right:**
  - After 90 s of echo out, deck 1 came back at 01:40.5 against 01:40.7 expected at -6.66%.
  - Deck 2 read 05:46.7 against 05:46.8 expected.
  - 76 s and two more plain rolls later, deck 1 read 02:51.5 against 02:51.4.
- **Recording:** 615.8 s of the stress run had no gap of 30 ms or more below -50 dB. It's taken ahead of the output, so a glitch in the output device wouldn't show. The saved mix is 38:01.4 long, against about 38:01 by the clock. Its `.cue` has Exhilarate at 00:00, Severe Tire Damage at 01:22 and the same track's second load at 32:53, which is when deck 2 loaded it.
- **CPU on this simulator's process:** from 11:52:51 to the end, in 5 s steps from the process's CPU time: average 23.1%, median 20.8%. The highest was 106.6%, at 11:58:58, while saving the mix. `top` hung for the first part, and read 20 to 26% at 11:49. This is a simulator on a Mac, not the phone.
- **Memory:** 255 MB at 11:52:51, 545 MB at the highest with the same track on both decks, and 186 MB after the mix was saved.
- **Log, 2 hours to the end:**
  - 11 lines of `HALC_ProxyIOContext::IOWorkLoop: skipping cycle due to overload` at 10:20:57, 10:24:08, 10:32:00, 10:36:09, 10:40:35, 10:52:31, 11:06:41, 11:24:34, 11:24:50, 11:26:54 and 11:50:16. Only the last is inside the stress run. I can't say whether these were audible.
  - 4 lines of `System gesture gate timed out`.
  - No hang warning.

**The mixes.** The first ran from 15:55:47 on 1 November to about 00:27 the next day, when it was stopped for disk space. `Stop and save` wrote a 192 MB `.m4a`, a `.cue` and a `.txt` within about 2 minutes. I didn't check inside them.

**State left behind.** The Duo's free, with both decks stopped and no recording running. Exhilarate is on deck 1 and Severe Tire Damage on deck 2, and both tracks hold test cues and loops from this round. Deck 1's tempo is at -6.7%, and Color FX is on `SPACE`.

## First impressions
Not run, as the task says to run part 3 only if the owner asks.
