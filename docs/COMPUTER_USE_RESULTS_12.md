# Hands-on results, part 12, 2026-11-04

Commit tested: 6fc9a2c
Device: iPhone Duo simulator, unfolded (951×669 pt; inner screen 2853×2007 px), and `iPhone SE Cheeks` (375×667 upright, 667×375 on its side). iOS 27.2. Fresh installs of `com.nikhilpatel.seguedj` at the start, and again on the Duo for the first-time user.
Tooling limits:
- **The Duo's stuck recorder is still running,** from my mistake in round 10, so there's no video on the Duo. It uses about 35% of a core in `SimMetalHost`. **It grows faster than I told you:** 12.2 GB in the 27.6 minutes to 06:00, about 440 MB a minute with the screen moving, not 118. Free disk went from 88 GB at 04:22 to 54 GB at 06:00. A shutdown clears it, and then someone has to press Open in Device Hub.
- **So what needs video ran on the small iPhone:** the refused key's shake (A2), the meters during browser opens (B1), the launch sweep (B2) and the pad flash (D2). Each says so below.
- **Not judged:** how anything sounds, haptics and the headphone output. Levels and gaps come from the recording.
- **Double-tap can't be done here:** two tool calls don't land within `TouchSurface`'s 0.3 s, so a double-tap on a knob or fader is untested this round. Round 9 passed it.
- **Tool lag:** a tool call takes 1 to 4 s when chained. Where it matters, a logger kept a frame each time the top bar's messages changed, about every 1.5 s.
- **Beside the measuring:** the Duo's recorder, and the small iPhone's app closed. `cheeks-6d` stayed off the CPU. The Mac was 54 to 73% idle by `top`.

## Summary
77 scripted tests: **74 PASS, 3 BLOCKED** (EA1 to EA3, the stuck recorder), and none failed what it asked. **No crashes:** no Cheeks or Segue crash reports. On top of those there are **three new failures no test asked about,** one of them found by the first-time user and repeated by me.

The two you asked me to look at first both pass. **EB1:** every loop control during a Loop build now stays as pressed and says so, on the Duo and on the small iPhone's side, and after the new track's landed the move just plays out. **EB3:** the note in the phone's mixer sheet sits below the controls, both ways up.

The long run took 15:10 of `MIX` and `AUTO`, with a dozen takeovers, and an Echo throw, a Brake drop and a Bass swap as well as the Loop builds. Every takeover said what it did, and the decks were usable after each. The only silence that isn't in the music is the Bass swap's air and one 0.23 s when I stopped an old deck.

The problems, most important first:
1. **N3: `AUTO` can end in silence with the next track ready.** Pressed with the track about to end and the next one's stems still splitting, it waits, the track runs out, and it stops. 2 of 2. The first-time user hit it on their first real press.
2. **N2: a press just after closing the browser lands on what's sliding past.** `PLAY` didn't start the deck and set a hot cue instead, 4 of 5 presses, and the cue stays on the track. Pick a track, close the browser, press `PLAY` is the natural order.
3. **N1: on the Duo, the longest messages lose their ends,** even at their smallest size, and the end's often the part that matters: "The decks are…". The small iPhone shows them whole.
4. **`BEAT SYNC` lines up beats and not bars,** 3 of 3 by my reading, and the first-time user's whole first mix was a beat out. The note doesn't promise bars, so it's your decision whether that's wrong.
5. **`NEXT` and `MIX` put what's just been played first,** as the first-time user found. It follows from the order they promise, but it looks like a fault on first use.

## Failures
### N3: `AUTO` lets the track run out while it waits for stems, and leaves silence
Found by the first-time user, and I repeated it.
- Steps: a track playing near its end, a track with no stems yet on the other deck, then `AUTO`.
- Expected: a warning at the press if it can't make it, and music at the end. `MIX` has a rule for this, in that the next track starts when the last one has nothing left to hear. `AUTO` doesn't seem to.
- Actual:

  | Who | Left at the press | Stems at the press | What happened |
  |---|---:|---|---|
  | First-time user | About 1:20 | About 2:15 to go | "Auto DJ stopped: deck 1 stopped before the stems were ready." Silence, and the waiting track stays stopped |
  | Me | 0:16 | 16%, "1 min" | "Auto DJ is waiting for the stems to finish." `AUTO 16%`. Ran out with both decks stopped, the meters dark and `AUTO` off. Fast Bird at 55%. The message had gone when I looked, 27 s after the press |

- The screen showed both numbers at the press: "-00:16.2" and "Stems 16% · 1 min".
- The simulator splits stems on the CPU, so a phone's window is likely to be shorter, but a late press would still hit it.
- Where it's said: `AutoDJ.swift:626`.
- Screenshots: `n3-auto-waiting`, `n3-auto-silence`, `fu-auto-pressed`, `fu-auto-stopped-silence`

### N2: a press just after closing the browser lands on what's sliding past
- Steps: browser open. `BROWSE`, then `PLAY` at once, as my next tool call. I don't have the exact gap: it's under about 1 s. With a pause of 1.4 s or more, which is every other press this round, `PLAY` was fine.
- Expected: `PLAY` starts the deck, or nothing happens.
- Actual: 4 of 5 presses did something else. The deck doesn't start, and a hot cue is set at its current place and saved with the track.

  | Time | Pressed | What happened |
  |---|---|---|
  | 05:24:03 | `PLAY` on deck 1, at x 37 | Cue `F` at 0:00 on Exhilarate |
  | 05:24:03 | `PLAY` on deck 2, at x 914 | Cue `H` at 0:00 on Severe Tire Damage |
  | 05:25:50 | `PLAY` on deck 1 | Started |
  | 05:26:22 | `PLAY` on deck 2 | Cue `H` at 0:00 on Houston |
  | 06:12:05 | `PLAY` on deck 2 | Cue `H` at 0:00 on Gepzene |

- `F` is about 150 pt from where `PLAY` ends up, so deck 1 still had that far to come. It looks like the rule in `CLAUDE.md`, that a control's touch can't be in anything that animates. The decks slide on `Theme.panel` (`Offstage`, `ContentView.swift:69` and `:73`). That reading's from the positions, not from tracing the touch.
- Screenshots: `nb1-play-lands-on-pad`, `nb1-play-lands-on-pad-2`, and `j1-phrases` has the first two

### N1: on the Duo, long messages lose their ends
- Steps: any of the messages below on the wide layout.
- Expected: the whole message, as EC7 asks of another one. The small iPhone's capsule hangs below the bar and showed them whole.
- Actual: the capsule has what's left of half the bar after the clock, `?` and the gear. `minimumScaleFactor(0.75)` shrinks the text and it still doesn't fit, from about 60 characters.

  | The message (bold is what's lost) | Where |
  |---|---|
  | "Auto DJ stopped: deck 2's loop was changed. The decks are **yours.**" | EB1, the point of that fix |
  | "Auto DJ stopped: deck 2 was stopped. Deck 1 has stopped **too.**" | EC4 |
  | "There's no loop to go back to yet. Press a loop size, or IN **and OUT.**" | EC6 |
  | "Exhilarate's file is missing. Import it again and it'll get its **cues back.**" | K3, longer with a longer title |
  | "FX pads slide: up and down for depth, left and right for the **beat.**" | The first visit to `FX` |

- These fit: "Mix off: deck 2 was moved. The decks are yours." and "Loop build in 15 bars. Crossfader to the middle, to hear both."
- Where: `StatusCapsule`, `ContentView.swift:556`, in the overlay at `:377`.
- Screenshots: `n1-cut-messages`, `eb1-exit-a`, `ec6-messages`, `ec4-after-handover`, `k3-missing`

## Blocked
- **EA1, EA2, EA3:** the Duo hasn't been restarted, as that needs someone to press Open. B1 and B2 ran on the small iPhone instead, which doesn't cover the Duo's logo or its browser with 2,000 tracks.

## Looks wrong
- **`BEAT SYNC` lines up beats, not bars.** The first-time user's bars stayed a beat apart for a whole mix. So I tried it with both tracks' stems finished: Gepzene playing, Karda on `BEAT SYNC`, then `PLAY`, three times with `CUE` between. I read CHORUS 39.1 and INTRO 4.2, CHORUS 46.4 and UP 4.2, then CHORUS 50.1 and CHORUS 2.3. The marker was green and centred each time. The note says "tempo and beat", so it's true as written. Whether a new DJ should get bars is your call. `sync-bars`, `sync-bars-first`
- **`NEXT` and `MIX` put what's just been played first.** From the first-time user: Gepzene first while still on the other deck, and "Up next: Houston." 40 s after fading Houston out. `NEXT` was on, and it orders by tempo first, so that's what it promises. `fu-mix-pressed`
- **Stopping the old deck in a Loop build leaves 0.23 s of silence** at 6:13.5 of the long run, about 0.1 s of it digital silence, before the new deck's heard. The table says it comes in "at once". Houston's file has no gap there. I found no other like it, but this was the only time I stopped an old deck with a recording on.
- **`RELOOP` after a stopped build goes to a loop nobody set.** In EB1 the deck was at about 3:47, and `RELOOP` took it back about 1:35, to the score's 16-beat loop at 2:12. `eb1-reloop`
- **Two `BROWSE` presses did nothing, once.** At about 05:24:47 and 05:24:52, with stems splitting on both decks: frames about 0.5 s apart show the decks throughout, and the stems percentages moving, so the app wasn't frozen. The third, at 05:25:16, opened it. It came about 45 s after the first N2 presses. After the later N2 presses, `BROWSE` worked, and all the rest this round did too. It could be my tool. `browse-no-response`
- **A press on a saved loop's pad starts a stopped deck playing,** which F4 doesn't say either way. Say if that's not what you want. `toggleLoop` plays it (`Deck+Performance.swift:156`).
- **An 8 pt slide on a lit FX pad counts as a tap, and turns it off.** 15 pt counts as a slide. Trying to nudge the depth by a little can lose the effect.
- **`starting` comes with about 2 bars still to go.** By the logger's frames: "in 17 bars" to "starting" took 27 s, where 17 bars would be 33 s. Also 9 bars in 12 s, 7 in 9 s, 26 in 44 s, 4 in 3 s and 6 in 7 s, always 4 to 6 s short, at 125 BPM. `AUTO 3` was still lit 2 s before "starting". It may be that the number counts to the handover and not the start, so this is only a mismatch of words.
- **`AUTO…` isn't in `AUTO`'s note,** from the first-time user, which explains a number and a %. For up to 13 s it read `AUTO…` with "waiting for the stems" still showing, after the stems had finished.
- **`BEAT JUMP`'s size only goes one way,** from the first-time user: 4, 8, 16, 32, 1, so four presses to get from 4 to 1 when fixing a bar.
- **The `?` hint** was gone in under 10 s for the first-time user, who was by then loading a second track.
- **Fault-level log lines:** 22 from UIKit's `AnimationKit` in the first-time user's run, at 05:54:53, 05:55:01, 05:59:35 and 05:59:46, about 'bounds' and 'position' being decomposed while a composite animation runs. Nothing visible went with them, by that run's account or the screenshots. The first two times are around its first import, and I can't place them more closely. Everything else in the error log is the simulator's own: `CVPixelBufferCreate`, `LoudnessManager`.
- **Not the app:** the first-time user's file picker shows `Cheeks Library 2026-10-30.json`. That's a backup from an earlier round in the simulator's Files, which outlives a reinstall.

## Stale sentences in the task
None of these failed anything, as you said they might be out of date.
- **The results format** still says part 10. I used 12.
- **A2** says "swiping the row should say the same". A swipe now only shows a `Deck 1` action, and it's a tap on that which says it.
- **A3's** "12 to 15%", **C2's** "under 1 pt", **D11's** "the last report said not" and **EA2's** "about 17 pt" are from much earlier rounds.

## All results
| Test | Result | Notes |
|---|---|---|
| EA1 | BLOCKED | Stuck recorder. |
| EA2 | BLOCKED | Stuck recorder. |
| EA3 | BLOCKED | Stuck recorder. B2 on the small iPhone instead. |
| EB1 | PASS | Everything on the Duo, 7 of 7. `EXIT`: ran 0:49 to 1:18 with no loop, and the new deck stopped. `›`: 8 beats, stays. `‹`: 4 beats, stays. Size key: leaves the loop, ran on to 2:34. `RELOOP`: says so, stays. `LOOP` pad: stays. A pad 9 s after the new track landed changed nothing, and "Loop build done. Deck 2 is on." followed. On the small iPhone's side, `EXIT`: the whole message, ran 0:47.8 to 1:10.7, and the new deck went back to 128.00. **On the Duo the message is cut,** see N1. |
| EB2 | PASS | "Bass swap in 7 bars" from Skylander at about 1:10 into Gepzene at 3:01. A 4-beat pad on the old deck 30 s in stayed a loop with no message, the move carried on, "Bass swap done. Deck 2 is on.", and the old deck stopped clean at 1:48.0 with its loop off. |
| EB3 | PASS | Both ways up: below the controls, one at a time, and back to the opening words after `Done`. |
| EB4 | PASS | An empty playlist, two known: both in, "Added 2 tracks you already had to this playlist." One new and one known: both in, "Added 1 track. 1 track already in your library." From All Tracks: "That track's already in your library.", count unchanged. |
| EB5 | PASS | Loop build, Echo throw, Bass swap and the thumbs are all there. A search for nothing says "No Results for xyzzy". The notes for `?`, `AUTO`, `MIX`, `NEXT` and the key column were true as far as I tried. `LIM` wasn't lit in 14 stills from the long run. The first-time user saw it red during a two-deck overlap, as its note says. |
| EC1 | PASS | From far down 2,000 tracks: a search, `IN KEY`, `±6% BPM`, `NEXT`, a column, another playlist and back each open on the first row. Closing and reopening, `?` and Recordings leave it where it was, at Track 1814. A column's third tap goes back to the list's order. |
| EC2 | PASS | Reads `MIX`, "There's nothing after this track in Round 12." |
| EC3 | PASS | "Loop build in 15 bars. Crossfader to the middle, to hear both.", whole. |
| EC4 | PASS | 6 s after the new deck's clock moved: both stopped, deck 2 at 125 and +0.00, names both, but cut: "Deck 1 has stopped t…". Before the handover: "Auto DJ stopped: deck 2 was stopped. Deck 1 carries on." |
| EC5 | PASS | "Auto DJ stopped. The decks are yours. Deck 2 is still looping." |
| EC6 | PASS | Each says why: "There's nothing to sync to yet: the other deck's empty.", "There's no cue on that pad to delete.", "There's nothing on that pad to delete.", and `RELOOP`'s, cut on the Duo (N1). Top bar `MASTER 1` with only deck 1 loaded, and `MASTER 2` with only deck 2. |
| EC7 | PASS | Whole from the first frame, sampled every 0.5 s: "Added 2 tracks. 1 track already in your library." `AnalysisIndicator` gives way to a message. |
| EC8 | PASS | No hint after pressing `?` first on the Duo. Without pressing it on the small iPhone, the hint showed. |
| A1 | PASS | 4 of 4: default tap and 0.2 s press, paused and playing. The cue comes back and the capsule goes each time. |
| A2 | PASS | Not loaded, "Deck 1 is playing. Stop it first." with a hand, on the key and on the row's swipe action. On video on the small iPhone, the key shakes about 3.5 pt each way for about 0.2 s. |
| A3 | PASS | See the table. |
| B1 | PASS | On video on the small iPhone: 8 opens and closes, with no LED lit in any frame, where the launch sweep in the same video lit them. The compact browser hides the mixer, so that's a weaker check, and so on the Duo I took 22 stills about 0.5 s apart across 4 presses: dark in all of them. A flicker between stills could hide. `b1-meters`, `b1-meters-duo` |
| B2 | PASS | On video on the small iPhone: up and back once, over about 1.5 s after the app appears. |
| B3 | PASS | To the right of `MASTER 1 128.00`, which stays readable. |
| B4 | PASS | 11 of 11, green and centred, 05:03:12 to 05:05:20. |
| B5 | PASS | Loaded and closed at once: the jog read 126.00. |
| B6 | PASS | 130.08 in the header and on the jog, both decks. The menu's title: "Beat grid: 125.00 BPM at normal speed". |
| C1 | PASS | All three index lines are within a pixel of their ticks and LEDs. |
| C2 | PASS | A 2 pt drag stays at centre, either way, and 3 pt leaves. Coming back from 484 to 477 catches. |
| C3 | PASS | The mixer stays and the field's visible. |
| C4 | PASS | **Keep recording** carries on, and **Stop and save** saves. |
| C5 | PASS | Pads at y 652 and `PLAY` at y 640 registered first time, with no system gesture. No empty strip. |
| C6 | PASS | `BROWSE`, `REC` and the gear. See **Looks wrong** for one exception. |
| C7 | PASS | Two lines in the compact decks. "Severe Tire Damage - Hi…" in the browser. |
| C8 | PASS | A plate behind the counter dims the loop's line under the text. |
| C9 | PASS | Same size, and `SAMPLE` is clear of `DEL`. |
| D1 | PASS | `SOLO` stays lit, the others dim, and a tap restores. |
| D2 | PASS | On video on the small iPhone: flash, then settle. Held on the Duo, a slicer pad is clearly brighter, with `EXIT` lit, and gives back on release. |
| D3 | PASS | `RISER` stayed lit in 5 frames, while the meters showed sound. |
| D4 | PASS | Lights, with an orange marker. |
| D5 | PASS | The new title straight away. |
| D6 | PASS | `Stems 0%`, then 6%, in the compact deck. |
| D7 | PASS | 32 before and after a held 1/16 roll. |
| D8 | PASS | No loop on the new track. |
| D9 | PASS | `Round Twelve.m4a`, `.cue` and `.txt`, and both use the name inside. |
| D10 | PASS | The mint layer has the music's shape. |
| D11 | PASS | Dragging along the bar moves it relative to the touch: about 60% to 85% to 23%. |
| D12 | PASS | Normal, then stem colours with vocal gone, then normal. |
| E | PASS | The `Hang` log has a header and nothing else. Pause while playing, play after pausing and at the end. |
| F1 | PASS | |
| F2 | PASS | "There's already a memory cue here." with a hand. A triangle on the waveform and overview. |
| F3 | PASS | "Set a loop first, then save it." Then an orange pad and bar. |
| F4 | PASS | Jumps to it, stays, and the pad lights. A tap ends it. See **Looks wrong** about a stopped deck. |
| F5 | PASS | "Deleted memory cue" with `UNDO`, and it comes back. |
| F6 | PASS | Name and colour reach the pad and the flags. Switched on and reloaded: waiting ahead, no jump. |
| F7 | PASS | Everything's there. `RELOOP` reads `ARMED`. |
| G1 | PASS | |
| G2 | PASS | Only `Grab Deck 1's Loop` shows, with only deck 1 having a loop. |
| G3 | PASS | Gate stops at release, and Loop goes on and off by taps. |
| G4 | PASS | `LOOP 1`, and it goes round. |
| G5 | PASS | A red timer replaces `SET`, and the pad plays it back with the meters full, deck stopped. |
| G6 | PASS | `CLAP` back. |
| G7 | PASS | Lit with the meters dark at the bottom, and `STOP` stops. |
| H1 | PASS | |
| H2 | PASS | Each effect keeps its own depth. See **Looks wrong** about a small slide. |
| H3 | PASS | "Echo out on deck 2. Press OUT again to bring it back." The meters fall in about 2 s, and it comes back further along. |
| H4 | PASS | "Echo out needs the deck playing." After a pause, `PLAY` comes back with sound. |
| I1 | PASS | `DUB`, `SPACE`, `NOISE`, `CRUSH`, `PITCH`, `FILTER`, and both labels change. |
| I2 | PASS | Nothing silent, red or crashing, both ways on all six. Double-tap not checked, see **Tooling limits**. |
| I3 | PASS | The meters fall over about 2 to 3 s, 2 of 2. |
| J1 | PASS | Exhilarate: CHORUS, VERSE, CHORUS, UP, CHORUS, OUTRO. Severe Tire Damage: INTRO, CHORUS, VERSE, CHORUS, OUTRO. |
| J2 | PASS | CHORUS 15.1, then UP 1.4 to UP 7.4, then CHORUS 2.4. |
| J3 | PASS | 170.00 and 148.00 for 47 s. |
| K1 | PASS | The picker can be driven. "Backup saved." |
| K2 | PASS | "Restored 7 tracks and 2 playlists." The cue's back on the loaded deck. |
| K3 | PASS | A triangle, and refused with a hand. Its message is cut on the Duo (N1). |
| K4 | PASS | The triangle goes and the cue's there. |
| K5 | PASS | `Documents/Backups/Segue DJ Library 2026-11-04.json`. |
| Long run | PASS | See below. |
| First-time user | Reported | See below. |

## The long run
05:37:03 to 05:52:13: a recording of 15:10, with music on throughout, on the Duo, beside the stuck recorder. No crash reports.

| Recording | What I did | What happened |
|---:|---|---|
| 0:07 | `AUTO` | "Loop build in 17 bars", played out, done at 1:16 |
| 1:33 | `MIX` on All Tracks, sorted by title | "Up next: Houston." |
| 1:45 | A 4-beat `LOOP` pad on the playing deck | "The mix will carry on when deck 2's loop ends." |
| 2:15 | `EXIT`, then a seek | "Echo throw into Houston." at 2:48 |
| 3:04 | `MIX` during the move | "Mix off. Deck 1 is on." The old deck stopped, at 128 and +0.00 |
| 3:15 | `AUTO` | Echo throw, done at 3:37. I took the new deck's `HI`, and it stayed where I left it |
| 4:16 | `AUTO`, then the size key on the old deck in the Loop build, at 4:33 | Stops, cut message (N1), runs on. The new deck stays stopped |
| 4:57 | `MIX` | "Up next: Houston." |
| 6:13 | Stopped the old deck in a Loop build | "Mix off: deck 2 was stopped. Deck 1 is on." |
| 6:31 | `AUTO`, then `PLAY` on the waiting deck at 6:39 | "Auto DJ stopped: you started deck 2 yourself." Both play, deck 2 at +0.00 |
| 7:03 | `AUTO` into DJ Karda, which has a loop switched on at 1.6 s | Loop build, played out. The new deck wasn't caught by its loop |
| 8:23 | `AUTO`, then a `LOOP` pad in the countdown | "Auto DJ stopped: deck 2 is in a loop." |
| 8:36 | `AUTO`, then a beat jump in the countdown | It takes the loop off and counts on, and the jump doesn't stop it |
| 9:20 | | Brake drop, played out |
| 10:18 | `AUTO` with Skylander about 1:10 and Gepzene about 3:01 | **Bass swap,** played out, done at 11:11 |
| 11:24 | `MIX`, then loaded the waiting deck | "Mix off: the track changed." |
| 11:38 | `MIX` on the playlist | "Up next: Houston." |
| 13:05 | A saved loop's pad on the old deck in a Loop build | "Mix off: deck 2 was moved. The decks are yours." It holds the saved loop |
| 13:24 | `AUTO`, and I took the old deck's `FILTER` at 13:46 | Loop build, played out, done at 14:13. The old deck's knob went back to centre |
| 15:10 | Stop and save | "Saving your mix…" for about 13 s |

- **Gaps:** 123 runs of 30 ms or more under -50 dB in 910.6 s.

  | Where | Runs | Longest |
  |---|---:|---|
  | The very start | 1 | 0.25 s |
  | **The Bass swap's air,** at 10:55 | 1 | 0.43 s |
  | **Stopping the old deck,** at 6:13.5: see **Looks wrong** | 1 | 0.23 s |
  | The tracks' own, repeating each time they play | 120 | 0.33 s |

  Gepzene's and Houston's fall in the same pattern each time they play. This round I compared Gepzene's with its file, which has the same runs, up to 0.31 s at about 15 s. I didn't compare the others one by one, so a very short dropout in among them could hide.
- **Level:** peak -0.1 dB, mean -14.4 dB.
- **The tracklist:** 10 lines, one for each time a track took over. Each is within a few seconds of the change on screen.

  ```
  00:00  Igor O. Vlasov – Skylander  (125.0 BPM, 11A)
  01:04  Gepzene – Gepzene - Can't be Serious  (125.0 BPM, 1A)
  02:47  Solxis – Houston  (125.0 BPM, 5A)
  03:18  Gepzene – Gepzene - Can't be Serious  (125.0 BPM, 1A)
  06:13  Solxis – Houston  (125.0 BPM, 5A)
  06:39  Gepzene – Gepzene - Can't be Serious  (128.0 BPM, 1A)
  07:41  DJ Karda – DJ Karda - Alone  (125.0 BPM, 1B)
  09:19  Igor O. Vlasov – Skylander  (125.0 BPM, 11A)
  10:20  Gepzene – Gepzene - Can't be Serious  (125.0 BPM, 1A)
  14:01  Solxis – Houston  (125.0 BPM, 5A)
  ```

- **Afterwards:** after each move and each takeover the decks worked, and the knobs, loops and stems matched the screen. Nothing was left silent, looping or filtered that the screen didn't show. All the messages are in the logger's frames, and the only ones cut were N1's.

## Timings and measurements
CPU by `top` on this simulator's own process, 30 s after 10 s of settling. Stems finished. Beside it: the Duo's stuck recorder, nothing of `cheeks-6d`'s, and the small iPhone's app closed. "Stems" means bass muted on one deck.

| State | Average | Peak | Memory | Mac idle |
|---|---:|---:|---:|---:|
| Idle, nothing loaded | 4.5% | 5.0% | 98 MB | 73% |
| Two tracks loaded, paused | 5.4% | 5.7% | 499 MB | 73% |
| One deck playing | 10.6% | 11.1% | 501 MB | 58% |
| Both playing, synced, tempo offset | 20.2% | 21.2% | 501 MB | 55% |
| Both of those, plus stems and an echo | 20.4% | 21.7% | 508 MB | 54% |

- **The app's own `Hang` log:** nothing, in test E.
- **Saving 15:10 of mix:** about 13 s.
- **Disk, for the stuck recorder:** 88 GB free at 04:22, and 54 GB at 06:00.

## First impressions
**1. Does it look like $1000 pro software?** On the wide layout, at a glance, yes. What's changed this round is how it behaves when you interfere: through 15 minutes of taking over `AUTO` and `MIX`, it told me what it had done every time, and it was right. That's what expensive software feels like. Three things break the illusion:
- **Messages that stop mid-word on the screen it's designed for.** It's a small thing, but it's the app talking to you, and it's cut off just where it says what to do. See N1.
- **Pressing `PLAY` and getting a hot cue.** See N2. A control that does something else, and leaves a mark on the track, is the worst kind of surprise in a performance tool.
- **The jog's centre on busy artwork.** White digits and small `+0.00%` and key text sit straight on the cover, and on a detailed one like Houston's, the small text is hard to read.

**2. What felt slow, confusing or surprising?**
- **Slow:** only the stems, as before, at 1:45 to 2:40 a track here on the CPU. Saving a 15-minute mix took 13 s with a clear message.
- **Confusing:** `AUTO` and `MIX` still look like two doors to one thing, though the note now separates them. `MIX 80` needs `AUTO`'s note to make sense. `ARMED` is explained, but only if you ask.
- **Surprising, in a bad way:** `AUTO` waiting patiently into silence, N3. It's the one thing here a crowd would notice.
- **Surprising, in a good way:** a loop on the playing deck gets "The mix will carry on when deck 2's loop ends." A beat jump in the countdown just counts on. A track with a saved loop right at its start didn't catch a move.

**3. Which control was hardest to find or hit?** `SPLIT`, `FILTER ↻` and `AUTO`: three small keys stacked in the mixer's middle column. `AUTO` is the most important of them and looks the same as the others, and a slip changes what both `FILTER` knobs do. `AUTO` also moves when the browser opens, which caught the first-time user out six times, though they were reusing coordinates and a person would look. Next: `UNDO` and the thumbs, which are only there for a few seconds at the far top.

## The first-time user
A general-purpose subagent, on the Duo after a fresh install, with its helpers kept apart from mine. **I cut it short:** the stuck recorder was filling the disk faster than I'd reckoned, so it had about 13 minutes of the 45 I'd given it. `MIX` got a press and little more, and the long run covers that.

What I checked of it myself: the silence (N3, repeated), the bars (repeated, under **Looks wrong**), and the `LIM` note, by its report only. It's written in its own words below, including its own mistake with `AUTO`'s position.

**The time limit cut this short.** The limit went from 45 minutes to 06:25, then to 06:08. I stopped touching the simulator at 06:07:33, after about 13 minutes.

- **Reached:** a hand mix (twice) and one full AUTO move.
- **Barely tested:** `MIX`. I started it and stopped it, and it never reached a transition.
- **Not touched:** pads, FX, stems pages, `REC`, settings and playlists.
- **Sound:** I can't hear anything here, so everything below comes from meters, waveforms and on-screen text. I can't say whether any mix sounded good.
- **State left behind:** browser open, Houston on deck 1, Skylander paused on deck 2, `MIX` off.

### 1. What I can't un-know

**Project notes.** These were shown to me automatically: the whole of `CLAUDE.md` and the index of the auto-memory. So this was not a clean first-time run. In particular, I already knew:
- `?` explains controls, and `MIX` and `AUTO` exist and differ.
- `AUTO` needs stems, shows bars and %, and that stems take minutes on the CPU here.
- The names of Auto DJ moves ("Loop build", "bass swap"), and that notes sit away from the finger.
- Deck 2 is mirrored and the mixer is in the middle of the decks page. I still got caught by the mixer's position (section 5).
- The fixture names (Exhilarate, Severe Tire Damage) and the rating capsule's 8 s.

**Git log lines I saw:**
- `6fc9a2c Hand the decks back when a Loop build's loop is touched, and fix what round 11 found`
- `d20bb16 Add hands-on test results, part 11`
- `f264c0a Add ? to explain any control, and fix what hands-on round 10 found`
- `6140da6 Add hands-on test results, part 10`
- `53a0201 Hand the decks back when the old one's moved, and make room for Color FX`

**One thing I did against the brief.** I ran `ls | head -30` on `docs/test-results-12/` before saving my first screenshot, so I saw 30 filenames, such as `a1-undo.png`, `a2-refused.png` and `eb1-loop-pad.png`. I didn't open any of them.

**How this affects the results.** Going to `?` early and pressing `AUTO` straight away are not fair tests of whether someone would find them. The on-screen hint is what a real newcomer would get (section 4).

### 2. From nothing to a mix by hand

Clock started at launch, 05:54:42.

| Stage | Time (from launch) | Screenshot |
|---|---|---|
| First screen up | 4 s or less | `fu-first-screen.png` |
| Import, picker, 5 tracks chosen, "Added 5 tracks." | 55 s (05:55:37) | `fu-imported.png` |
| All 5 show BPM and key | by 1:08 (05:55:50) | none |
| Two tracks loaded | 1:26 (05:56:08) | `fu-both-loaded.png` |
| Reading help (`SYNC`, `AUTO`, `MIX`, `NEXT`, `SPLIT`, `FILTER`, `CUE`, `CUE/MST`, crossfader) | about 1:15 of the total | `fu-help-auto-note.png` |
| Decks page open | 2:59 (05:57:41) | `fu-decks-page.png` |
| Mix 1 done: `BEAT SYNC`, `PLAY`, crossfader left to right | 4:00 (05:58:42) | `fu-hand-mix-done.png` |
| Mix 2 done: tempo fader only, channel faders | 7:26 (06:02:08) | `fu-hand-mix-faders.png` |

This was the best part of the app. Getting from nothing to two loaded tracks was fast and I never wondered what to do. The `1` and `2` keys on each row are obvious, and the empty screen's "Tap Import" is clear.

**Moments I wasn't sure:**

- **First sight of the screen.** It's very dense, with about 20 knobs and keys and no focus, but the blue `IMPORT` and "No music yet" told me where to start.
- **The Files picker.** My tap on `Music files…` was followed by a narrow blank panel with its title colliding with the back and forward pill (05:55:05). By 05:55:11 it was the normal full-size picker. This may be the system's picker animation and not the app.
- **What's in the picker.** The "fresh" install's picker shows a greyed `Cheeks Library 2026-1…0.json`, dated 10/30/26, and a `Segue DJ` folder with 2 items. These look left over from earlier runs. I didn't check, and I don't know if a new user could ever see them.
- **Stems at load.** "Stems 0%" appeared the moment I loaded a track, without my asking. I didn't know what it was doing or whether I had to wait. I didn't, as the hand mix worked regardless. Nothing tells a newcomer that.
- **Starting the mix.** Faders and crossfader sit in positions where both decks would be heard. I moved the crossfader left first, from DJ habit. A true beginner pressing `PLAY` on both would just get both.
- **Decks page.** I expected the browser to give way to the full decks, but there's no prompt. I found it because `BROWSE` was lit and I pressed it to close the browser. That worked first time.
- **`BEAT SYNC` then `PLAY`, with `Q` on.** Tempo matched at once (129.53 to 128.00). The beats lined up, but the bars were one beat apart for the whole mix: `12.3/3.4`, `20.4/3.1`, `29.3/11.4`. I expected `SYNC` to line up bars, or at least to say it hadn't. Nothing mentions it.
- **`NEXT`.** I pressed it to choose my next track. The first suggestion was Gepzene, the track I had just mixed out of, still on deck 1.
- **Matching tempo by hand.**
  - The fader drag was easy: Houston went to +1.62%, 128.05 against 128.00, on the first try.
  - I opened the `BPM ⌄` menu looking for a fine adjustment. Its `BPM + 0.1` looks like that, but the heading "Beat grid: 126.00 BPM at normal speed" suggests it edits the grid. I didn't press it.
  - I never got to exactly 128.00. I didn't try the narrower fader range.
- **`PLAY` with `Q` on and no sync.** It started off the beat, and I expected a snap. The `Q` note doesn't promise one, so the app is consistent with its note, but it surprised me.
- **Fixing the phase.** The note on the beat blocks and the jog note gave me enough. A 40 pt drag up the left of the metal ring moved the yellow mark further from centre (deck 1 ahead). A 70 pt drag down brought it nearly to centre.
- **Fixing the bar (about 1:15).** I needed to jump one beat. The `BEAT JUMP` number only cycles upward, 4 → 8 → 16 → 32 → 1, so it took four taps to reach 1. Going back one beat then put both decks on a red downbeat.
- **`MASTER` stayed on deck 2** at the end of mix 2, with its fader all the way down, so the top bar named a silent deck as master. I'm not sure that matters.

### 3. With Auto DJ

| Stage | Time | Screenshot |
|---|---|---|
| Real `AUTO` press 1 (browser page), Skylander just loaded on deck 2, Houston with 1:20 left | about 06:03:20 | `fu-auto-pressed.png` |
| Houston ran out at 06:04:42 with stems at 60%: silence, "Auto DJ stopped: deck 1 stopped before the stems were ready." | 1:22 after pressing | `fu-auto-stopped-silence.png` |
| Stems for Skylander (6:00 long) finished | about 2:15 after loading | none |
| Real `AUTO` press 2 (Houston restarted): `AUTO…`, then `AUTO 6` | pressed about 06:05:33, `AUTO 6` by 06:05:49 | none |
| Loop build under way (`EXIT` lit, deck 1's `MID` and `LOW` turned, stem colours on the waveform) | 06:06:10 to 06:06:25 | `fu-auto-loop-build.png` |
| "Loop build done. Deck 2 is on." with thumbs up and down | by 06:06:40, about 1:07 after press 2 | `fu-auto-done.png` |
| `MIX` pressed: "Up next: Houston.", `MIX 80` | about 06:07:14 | `fu-mix-pressed.png` |
| `MIX` pressed again: "Mix off. The track playing just carries on." | 06:07:30 | none |

**Stem times in this simulator.** Four other simulators were booted, so a phone may well differ.

| Track | Length | Time to split |
|---|---|---|
| Gepzene | 3:48 | about 2:20 |
| DJ Karda | 4:37 | about 2:40 |
| Houston | 4:50 | about 1:45 |
| Skylander | 6:00 | about 2:15 |

The "27% · 2 min" estimates were roughly right, if a little long.

**Moments I wasn't sure:**

- **Which one?** `AUTO` and `MIX` are both on screen, far apart, and the labels alone don't separate them. The `MIX` note does this well: "It's the quickest way to an automatic mix. AUTO on the mixer does just one move."
- **The first real press ended in silence.** See section 5. It's the worst thing I saw.
- **`AUTO…` versus the message.** At 06:05:36 the deck header no longer showed a stems % (it had finished). The key read `AUTO…` and the capsule still said "Auto DJ is waiting for the stems to finish." That lasted 13 s at most. The note explains a number and a %, but not `…`.
- **What Auto DJ moved.**
  - It raised deck 2's fader, which I had left down.
  - It set deck 2's tempo to +2.44%.
  - It turned deck 1's `MID` and `LOW`, and looped deck 1.
  - Afterwards deck 1 went back to +0.00%. This matches the note's "moving the controls you can see".
- **It ignored where deck 2 was cued.** Skylander read 00:01.8 at 06:06:25 and 00:41.2 at 06:06:40, 39 s of track in 15 s of clock. So it must have jumped in, and I'd guess it skipped the intro. Nothing said it would. I don't know what the plan was.
- **It left Houston early.** I pressed `AUTO` 28 s into Houston and it moved within 6 bars, stopping Houston at 00:53 with 3:57 left. I pressed it, so this is fair, but I'd half expected it to wait for a good moment later in the track.
- **The thumbs.** The capsule doesn't say what's being rated. I assumed the transition. I didn't press either one.
- **`MIX`'s first choice** was Houston, the track it had just faded out 40 s before (section 5).

### 4. Using the help

**How I found it.** `?` is visible at the top right from the first second. The capsule "New to this? Press ? and tap anything to see what it does." appeared when I loaded my first track, and was gone by the time I loaded the second, under 10 s later. Someone looking at the waveform that had just appeared could miss it, though `?` itself stays. I'd known about `?` from the notes, so my going straight to it proves nothing. The hint itself is well written.

**What worked:**
- The notes appear away from the finger and were all readable.
- The music carried on underneath, and `AUTO`'s count kept going during help.
- `BROWSE` still worked in help mode, as the first note promises.

**Checked against what really happens, and right:**
- `AUTO`: a number means bars, a % means stems.
- `MIX`: "loading each track as it goes" and "Press it again to stop".
- `BEAT SYNC`: tempo and beat.
- Jog wheel: "Turn the metal ring to push a playing track ahead or hold it back".
- `MASTER`: "the first one to start playing takes over". Deck 2 took over after I stopped deck 1 and started nothing.
- `NEXT`: "That deck's own track drops off the list".
- The red `LIM` during a two-deck overlap, which matches its note.

**Not checked against behaviour:**
- `BEAT SYNC`'s "Moving the tempo fader takes it off".
- Crossfader's "Double-tap for the centre".
- `AUTO`'s "Touch a control to take it back" and "press AUTO to call it off".
- `FILTER`, `±6% BPM`, Recordings, `KEY`, `Q` loops and cues, and `TRIM` as the `LIM` note suggests.

**Notes that were confusing or didn't help (none was plainly false):**

1. **`SPLIT` and `CUE/MST` use left and right in opposite senses.**
   - `SPLIT`: "the mix in the left ear and your cue in the right."
   - `CUE/MST`: "left for the decks you've cued, right for the mix".
   - One means ears and the other means the knob's direction, but read together they sound contradictory.
2. **`CUE` (headphones).** "It plays in the right ear with SPLIT on and a splitter cable." I have a phone and maybe AirPods. Can I preview a track at all? The note implies no, but doesn't say so, and doesn't offer another way. This was my biggest unanswered question about hand mixing. I can't test it without sound.
3. **`BEAT SYNC`.** "Locks this deck to the other's tempo and beat, so the two stay in time." True, but my bars stayed a beat apart for the whole mix. A newcomer will take it to mean everything lines up.
4. **Beat blocks.** "Four blocks for each deck, one lit for each beat of the bar, so you can see whether the two line up."
   - Deck 1's blocks count outward from the centre, so its beat 1 is the block nearest the middle. When the decks line up, they light at mirrored positions, not matching ones. I only worked this out by comparing the blocks with the bar labels across several screenshots.
   - The note doesn't explain red versus blue, or which way the yellow or green mark means ahead.
5. **`AUTO`.** "Mixes from the playing deck into the other by itself, once stems are split". It doesn't say what happens if the track ends first, which is what happened to me.

**Still a mystery after using help (I didn't ask the app about these, as I ran out of time):**
- The section labels. What is `UP`?
- Why do Gepzene and Houston start as `CHORUS 1.1`? Gepzene's first bars look like sparse kicks, more like an intro. I can't confirm that without hearing it.
- DJ Karda's labels changed often, through `CHORUS`, `VERSE`, `UP`, `CHORUS`, `UP`, `CHORUS`. I can't say if that's right.
- The filled key cell in the list. I guessed it means "goes with the leading deck", from seeing `1B` with `1A` playing, `1A` with `1B`, and `10A` with `11A`.
- Whether "Loop build" means anything to a newcomer.

### 5. What surprised me, or felt slow or broken

**Auto DJ can end in silence, with the next track ready (app behaviour).** Repeat:
1. Have a track playing with about 1:20 left.
2. Load a 6:00 track with no stems yet on the other deck.
3. Press `AUTO`.

It lights `AUTO 1%` and says "Auto DJ is waiting for the stems to finish." Stems needed about 2:15. At the end of the track the deck stops, the master meter drops to nothing, and "Auto DJ stopped: deck 1 stopped before the stems were ready." appears, gone within 17 s. Deck 2 was still sitting ready. The app showed both numbers beforehand (time left, stems ETA) but gave no warning. A phone may split faster, but a late press would run into the same thing.

**`NEXT` and `MIX` put what you've just played first (app behaviour).**
- At 05:59:07, with Karda leading, `NEXT` listed Gepzene first, the track still on the other deck.
- At 06:07:16, with Skylander leading, `MIX` announced "Up next: Houston.", the track it had faded out 40 s earlier.
- Houston (5A) is six steps from Skylander's 11A. Fast Bird (10A) has the highlighted key cell but is last at 139.7 BPM.

The note says order is "by how close the tempo is and how well the key goes", so tempo seems to win. It's defensible, but as a first experience of a mix it would feel like a bug.

**My own error: six `AUTO` taps went to the wrong place (touch-coordinate mistake, not the app).** I tapped x=859, where `AUTO` sits on the browser page, while on the decks page, where the mixer is in the centre (x=475). They hit deck 2's jog wheel at about 06:02:14, 06:02:28, 06:02:52, 06:03:00, 06:05:10 and 06:05:20. For a few minutes I thought `AUTO` silently refused, and it doesn't. Please discount two things from this:
- There was no "silent refusal".
- The yellow phase mark jumping right between 06:02:20 and 06:02:30 was probably my taps on deck 2's record. It could also be the 0.05 BPM mismatch. I can't tell which, so don't treat it as drift.

The mixer moving between pages is weak evidence of a real muscle-memory trap. A person would look before pressing, and I was reusing coordinates.

**The bar misalignment after `SYNC` and `PLAY`** is described in section 2. I don't know if it's by design. The `Q` note only promises cues, loops and jumps.

**Smaller things:**
- Titles truncate hard in the browser's deck strip ("Gepzene - …") with space left around them.
- `MIX 80` has no explanation of its own. The number makes sense if you read `AUTO`'s note.

**Things that felt good:**
- Analysis of five tracks took under 15 s after import, on this simulator.
- The last 30 s of a track go red everywhere.
- The list keeps your place.
- Stem % and ETA sit in the deck header.
- `Up next` and `Mix off` read clearly.

### 6. The three things I'd fix first

1. **Don't let `AUTO` or `MIX` end in silence while stems are pending.** Warn at the press if the track will end before stems are done, and when it does run out, bring the waiting track in, not nothing. This is the only moment where the app did something a person at a party would really notice.
2. **Sink recently played tracks in `NEXT` and `MIX`.** A mix that replays what it just faded out breaks trust in the feature on first use. Whatever's on the other deck, or in History, shouldn't be first.
3. **Make bar alignment visible and easy to fix.** After `BEAT SYNC` and `PLAY`, either line up the bars or say they're a beat apart. Make the blocks easier to read as lined up or not, and offer a one-beat nudge without cycling through 8, 16 and 32. It took me over a minute, and I knew what I was looking for.

### Screenshots

All in `/Users/nikhil/Cheeks/docs/test-results-12/`: `fu-first-screen.png`, `fu-imported.png`, `fu-both-loaded.png`, `fu-help-auto-note.png`, `fu-decks-page.png`, `fu-hand-mix-done.png`, `fu-hand-mix-faders.png`, `fu-auto-pressed.png`, `fu-auto-stopped-silence.png`, `fu-auto-loop-build.png`, `fu-auto-done.png`, `fu-mix-pressed.png`.
