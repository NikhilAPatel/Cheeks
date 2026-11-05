# Hands-on results, part 16, 2026-11-04

Commit tested: cb51677

Device:
- **iPhone SE Cheeks:** 667×375 on its side, and 375×667 upright, for almost everything here, including the long run and CPU.
- **Folded iPhone Duo:** 466×678 pt, upright phone layout, for the first-time user and for checking what they found.

Tooling limits:
- **The full layout can't be pressed.** The Duo is still folded: its inner screen is black, and the last `hingeState:` in SpringBoard's log says closed. I didn't reboot it. I asked for the iPad's touch access at 20:29 and 21:40, and neither was answered. So all of GA is blocked, and `GC17` wasn't run.
- **Can't be checked here:** how anything sounds, haptics, the headphone output and a real finger. Knob turns are read from screenshots, and levels from recordings.
- **Double-tap on a knob:** two tool calls are too slow to count, and freezing the app so both arrive together didn't register either.
- **Screen reading:** a logger read the top of the screen by OCR about twice a second. It stalled at 21:31:09, after the long run's recording had stopped, and I restarted it for the rest.
- **Freezing the app:** I pressed inside the slide by stopping the app with SIGSTOP. A freeze also runs a recording's timer on, so I didn't do it during anything being measured for gaps, apart from one press at 21:16:29 in the long run, which caused no gap.
- **Busy Mac:** the first-time user was on the Duo until 20:57, while I ran the retest on the small iPhone. Mac idle was 53 to 73% during the CPU table.

## Summary

58 scripted tests including the long run: **51 PASS, 3 FAIL, 4 BLOCKED.** No crash reports. The first-time user and the long run also found faults outside the script, listed under Failures as `N17` to `N22`, with `N19` under `GC12`.

**Everything that failed last round is fixed.**
- **`N14`, the mixer sheet's knobs:** they turn now, at 1.9° per point, against 2° on the main screen. All five move both ways up, at every speed I tried last time, and the sheet still drags away by anything else.
- **`N15`, the sidebar under `?`:** the headings, `New Playlist` and the rows all explain themselves, and `New Playlist` no longer opens its prompt.
- **`N16`, the new deck's fader:** all three messages are there and true.

**The three most important problems:**
1. **`N21`: a 4.1 s hole in a mix.** Move a playing deck past its planned exit, and it says "No clean way in. Next track starts when this one ends." with 2 minutes of track left. It then does nothing until the file runs out, including the last 3.8 s of silence in the file. It came out the same both times: 4.1 s under -50 dB.
2. **`N17`: the first touch on the tempo fader after a narrower range jumps the live tempo.** On a deck synced beyond the new range, pressing the range key changes nothing, then a 5 pt touch takes it to the edge of that range. `SYNC` goes off and nothing's said: 129.53 to 159.80 BPM for the first-time user, twice, and 148 to 133.56 for me.
3. **`N22`: the Segue DJ folder won't open in the Files picker.** The first screen offers it as a way in. It doesn't respond to a press on either simulator, where `My Music` opens on one. It may be a simulator quirk, so it wants checking on the phone.

**The first-time user's question.** They could say what Auto DJ does at **+16:52**, against 34 minutes last round. The guide's tip to put both decks on `STEMS` got them there, not the marks above the tab. See below.

**The thumbs work.** I pressed each one straight away, and the answer stayed up about 5 s: up on both layouts and down on the small iPhone. The first-time user's three "no answer" presses came as the question was leaving, or after it had gone. See `GC9` and `N18`.

## Failures

### N21 (new, from the long run): a seek past the plan's exit leaves a mix with no move, then a 4.1 s hole
- Steps: small iPhone, fresh launch, Skylander playing on deck 1. `MIX` on All Tracks, so Fast Bird is next, with both split. It reads `MIX 86` at 0:59, so it means to leave at about 3:44. Touch the overview to go to about 3:58, with 2:00 left.
- Expected: it plans again from there, or, failing that, echoes out. If there's no move at all, the next track starts when the last one has nothing left to hear, as the music never just stops.
- Actual:

| | Long run | Reproduced |
|---|---|---|
| The seek | 21:18:27 | 21:35:14 |
| "No clean way in. Next track starts when this one ends." | Not caught by the logger | 21:35:15, about 0.3 s after the seek |
| The key reads `MIX…` | 21:18:34 to 21:20:47 | 21:35:15 to 21:37:28 |
| "No clean way in. Deck 2 just started." | 21:20:47 | 21:37:28 |
| Under -50 dB before Fast Bird | **4.13 s** (359.26 to 363.38 in `Mix 21.14.42`) | **4.10 s** (200.13 to 204.23 in `Mix 21.34.03`) |

  - The file's own last 3.77 s are under -50 dB, so the next track waited for the end of the file and not for the last sound. The levels fall from -18 dB to below -70 dB and stay there until Fast Bird's -18 dB. The rest of the 4.1 s is about 0.3 s more, which I can't place.
  - The app used 7.7% CPU during the wait, so it wasn't thinking about a plan. No screen says anything for 2:13 except `MIX…`.
  - **Not proved, for looking at first:** `AutoDJ.swift:483` takes the last sound from the stems, at half the threshold. A stem can stay above that when the mix has fallen below it, which would put "nothing left to hear" at the end of the file. And `MIX…` for 2 minutes looks like `plannedFor` or `lastResort` still being set from the seek, as line 401 and lines 407 to 411 won't plan again after that.
  - A seek that lands before the exit does plan again: the first-time user went from `MIX 88` to `MIX 9`.
- Screenshots: `n21-no-clean-way-with-2-minutes-left.png`, `n21-deck-2-just-started.png`.

### N17 (new, from the first-time user, reproduced): the first touch on the tempo fader after a narrower range jumps the live tempo
- Steps: a deck synced beyond ±6, reading `WIDE`. Press the range key to get ±6. Touch the fader and move it 5 pt.
- Expected: it holds until you move it, or the range key says it can't go narrower yet.
- Actual:
  - After the range key: the cap's pinned at the end of its slot, and it still reads the old number and the old tempo, so nothing looks wrong.
  - After the touch: it jumps to the edge of the new range, `BEAT SYNC` goes off, the strip goes yellow and nothing's said.
  - Mine, on the small iPhone: Houston synced to 148.00, at +17.5. After the touch, 133.56 and +6.0, with deck 1 at 148.
  - The first-time user's, on the folded Duo: 129.53 to 159.80 at 20:35:05, and again at 20:52:58.
  - The cap ignores that first drag and follows the next one. They were dragging down and it went the other way.
- Also: a track that comes with a deck left on `WIDE` keeps that range, so an 18 pt nudge was +45.1% for the first-time user at 20:52 (`fu-wide-fader.png`).
- Screenshots: `n17-synced-wide.png`, `n17-range-pressed.png`, `n17-after-a-touch.png`, `fu-tempo-jump-repro.png`.

### N22 (new, from the first-time user, reproduced): the Segue DJ folder won't open
- Steps: browser, `IMPORT`, `Music files…`, back to On My iPhone, and press the Segue DJ folder. I used a 0.2 s press.
- Expected: it opens. The first screen says "drop audio into the Segue DJ folder in the Files app or Finder" (`BrowserView.swift:622`).
- Actual: nothing happens. `My Music` beside it opens on one press. The first-time user tried three kinds of tap, in the picker and in the Files app itself. Both `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` are true in the built app.
- Not known: whether this is the simulator. Please try it on the phone. If it's real, one of the two ways in on the first screen doesn't work.
- Screenshots: `n22-segue-folder-wont-open.png`, `fu-picker-segue-folder.png`.

### N20 (new, from the first-time user, reproduced): stem pads say something that isn't happening yet
- Steps: a deck playing, its split at 24%. On `STEMS`, press `BEAT`.
- Expected: it takes effect, or the page says it's waiting for the split.
- Actual: `BEAT` lights, and `VOCAL` and `INST` dim, but the waveform stays whole and the meters don't change. There's only the small "24%" beside the keys. The first-time user thought it was broken until the split finished, 15 s later, and it all took effect.
- Screenshot: `n20-stem-pad-before-the-split.png`.

### N18 (new): a press where the thumb just was can move deck 1
- Steps: folded Duo. Wait for the question to go, with deck 1 loaded. Press where the thumb was.
- Actual: at (315,40) nothing happens, as that's the top of the waveform. At (315,34), still inside where the key was, deck 1 went from 1:08.5 to 4:01.0, because that's the overview. Deck 1 was stopped when I did it. It would have moved a playing deck the same way, and the question is often asking about a deck that's just gone on air.
- The first-time user's thumbs missed it only by being at y=40.
- Screenshot: `n18-late-thumb-jumps-deck-1.png`.

### GC12 / N19: nothing shows a preview's running, apart from the mark
- Steps: small iPhone, both ways up. Touch a row's picture.
- Expected: a stop mark, and you can tell from the meters or the position that it's previewing.
- Actual: the stop mark's right, the second touch stops it, and holding a row offers it. `?` on the picture explains it, and closing the browser ends it. But the browser has no meters or position on a phone, at either width, so the mark's the only sign.
- Related: with `SPLIT` off, it goes to the master at 0.7 (`DJEngine.swift:382`), so it's on the recording, and it's what the room hears over a mix. `REC` during a preview gave `Mix 20.17.02`, which matches Exhilarate at 49 s, at a mean of -14.4 dB and a peak of -2.7 dB, against -12.4 and 0.0 for that part of the track. That's about 3 dB down, as 0.7 should be. The note says "quietly on the main output", which is true, though "over the mix and on a recording" would say more.
- Screenshot: `gc12-preview-stop-mark.png`.

### C9: `STEMS` shrinks when `SAMPLE` is showing on the small iPhone
- Steps: small iPhone on its side, deck 1 on `SAMPLE`.
- Expected: the labels the same size.
- Actual: `STEMS` is visibly smaller than `CUE`, `LOOP`, `ROLL` and `FX`, to fit `SAMPLE ›`. On `ROLL` it nearly touches its neighbour too. The folded Duo's fine.
- Screenshot: `c9-stems-shrinks.png`.

### Long run: see N21
Everything else in it was clean. See its table below.

## Blocked

| Test | Why |
|---|---|
| GA1 | The Duo's folded. Last iPad stand-in 0.155 s, not rerun |
| GA2 | The Duo's folded |
| GA3 | The Duo's folded. `B2` passed on the small iPhone |
| GA4 | Nobody's pressed during the slide on a full layout yet. The presses on the small iPhone (`GC2`) all landed right, but that's a different layout |

## Looks wrong

- **The marks above `STEMS` are small for what they're asked to do.** About 6×3 pt each on the small iPhone. You can see they've changed, and that the blue one goes first. I couldn't tell which part was which at the size of a real phone without zooming in. Nothing else on the tab row moves. The first-time user never used them to follow a move. `gc1-marks-through-a-move.png`.
- **A hand-back's message goes to the screen's edges on the small iPhone.** "Auto DJ stopped: deck 1's loop was changed. The decks are yours. ALL brings back deck 1's stems." fits, just. It covers the section label and part of both waveforms for 8 s or so. `long-exit-in-last-bars.png`.
- **"No clean way in. Next track starts when this one ends." with Exhilarate 6 s from the end, and 2 minutes from it in `N21`.** Same words, very different weight. In the second, a person could still do plenty.
- **`Fast Bird`'s BPM wanders until its stems finish.** 140.60, 139.72, 140.65 while playing, from the first analysis. 140.06 and steady after. `J3` only asks about the two test tracks, which are steady.
- **Backups folder:** "Before restore 1793854445.json". The number's a raw timestamp, beside a dated name.
- **The stop-recording alert's red "Stop and save".** Red's the danger colour and this is the safe choice. From the first-time user, and I agree.
- **`MIX`'s words with a filter on:** "Mixing through all your tracks, 3 tracks to go" when `±6%` had the list down to 4 of 7. From the first-time user.
- **A big sync says nothing, and a half-tempo one does.** 170 to 128 is a quarter slower with no word, while "Deck 1 follows at half tempo" gets a message. From the first-time user.
- **Remaining time ignores tempo.** A track at 87% gained 20.0 s on its clock against 22.9 s on the deck at full speed, which the first-time user measured (`fu-clock-test.png`). The big red countdown isn't how long it has left.
- **The home indicator on the folded Duo** crosses deck 2's tempo readout on `JOG`, and the bottom edge of the `SOLO` row. `fu-rev-slip.png`. The mix line itself is clear of it.
- **A stray `SAVE CUE` moves where the track loads.** No message and no undo, and a swipe in `LIST` deletes with no undo either, where a pad gets one. `F2` and `F5` passed because they were using it on purpose. `fu-cue-swipe-delete.png`.
- **A sheet opens half-way and then rises.** Recordings and Settings do this. The first-time user's taps missed three times, though their tool's lag is part of that. A wrong track on deck 1 at 20:35:55 is more likely the tool: a screenshot taken during the slide, and the press after it had finished.

## What the first-time user got wrong, checked against the app

These are in their report as they wrote them. I checked each:
- **"`MIX` throws out a playing track": it doesn't.** With a deck really playing, `MIX` carries on from it on both simulators (`mix-carries-on-with-a-deck-playing.png`), and their own 20:48:50 press was refused. At 20:24:57 nothing was playing: their screenshots at 20:23:45 and 20:24:01 have every `1` and `2` lit, where at 20:22:05 a deck was playing. Their last sight of Skylander's clock was 20:21:45. So `MIX` did what it says, from the top of the list. What I can't explain is **what stopped Skylander between 20:22:05 and 20:23:45**. They were closing Settings in that time, with two flicks that left it parked as a small bar. I tried flicks on the Duo with deck 2 playing, and it played on. It's the one thing here I'd call unexplained.
- **"`BRAKE` ends a running mix with no message": it says so.** One press at 21:05:16 on the Duo: "Mix off: deck 2 was stopped." (`brake-mix-off.png`). They were probably looking too late, after the capsule had gone. They needed two presses to stop it, and I needed one, and I don't know why.
- **"Thumbs up gives no acknowledgement": it does.** See `GC9`.
- **"The clock on a track at 0:11":** they say themselves that was elapsed play.

## All results

| Test | Result | Notes |
|---|---|---|
| GA1 to GA4 | BLOCKED | Above |
| GB1 | PASS | Table below. The sheet lifts about 2 pt as the touch starts, and stays there. On its side there's no half height to drag |
| GB2 | PASS | On its side: `PLAYLISTS`, `COLLECTION` and `New Playlist` show the note, and no prompt opens. A row chooses its list and shows the note (`gb2-sidebar-notes.png`, `gc16-history-chosen.png`) |
| GB3 | PASS | "Deck 1's fader up, to hear both." at `AUTO 2` (`gb3-fader-up-word.png`). "Crossfader to the middle and deck 2's fader up, to hear both." (`gb3-crossfader-and-fader-word.png`). "Crossfader to the middle, to hear both." "Deck 2's fader up, ready for what's next." in a `MIX` (`gb3-mix-fader-word.png`). Nothing with neither to move |
| GC1 | PASS | Above `STEMS` from `CUE`, on the old deck: they appear as the move starts, and dim one by one. The new deck's are all dim until its parts come up. They go when all are back. Tab labels don't move. "Loop build starting. STEMS shows what's in. A control you touch is yours." See Looks wrong for their size |
| GC2 | PASS | Same size and place, unlit, with the legends crossing in about 130 ms (`gc2-slide-frames.png`). Frozen straight after the key: `PLAY` on closing, a pad on closing (set cue A on the arriving deck), and a row's `2` on opening, all right. With both presses held back and delivered in one instant: `PLAY` lost once and landed once, which a finger can't do |
| GC3 | PASS | Play mark, stop mark while on, fits on the small iPhone, search types and clears (`gc3-upright-mix-on.png`) |
| GC4 | PASS | Outside track playing, list all played: "Mixing through Done, 2 tracks to go. Up next: Severe" (`gc4-outside-list-starts.png`). A track from the list playing with the rest played: "Everything else here has been played. To go round again, stop the deck and press MIX." (`gc4-everything-else-played.png`) |
| GC5 | PASS | Ticks match what `MIX` leaves out, with `NEXT` on or off (`gc5-ticks.png`). Nothing's slower with 7 tracks |
| GC6 | PASS | "Mixing through all your tracks, 4 tracks to go. Up next: Houston." and the line agrees (`gc6-counts-agree.png`) |
| GC7 | PASS | "Loop build next, with deck 2 cued at 126 BPM. AUTO's counting down the bars." Deck 2 shows 126.00 (`gc7-first-message.png`) |
| GC8 | PASS | "That's yours for this move. Auto DJ carries on with the rest." The knob goes back at the end. It reads right, as "for this move" says so |
| GC9 | PASS | See below |
| GC10 | PASS | "Deck 1 follows at half tempo: 85 against 170." with 85.00 on the deck (`gc10-half-tempo.png`). Nothing on an ordinary sync |
| GC11 | PASS | "ROLL pads play for as long as you hold them." once, and the same for `SLICER`, on a fresh install |
| GC12 | FAIL | Above. The mark, the stop, the menu, the note and the end at closing are all right |
| GC13 | PASS | The Name field shows `AIR HORN`, not renamed. `REC 1` after recording the master. Restore isn't red, and brings back `AIR HORN` (`gc13-restore-not-red.png`) |
| GC14 | PASS | "Gepzene – Can't be Serious (126.0 BPM, 6A)" at -1 from its 1A, and 8A on the long run's list, where a move had shifted it. The artist isn't repeated |
| GC15 | PASS | "Nothing here is both in key and close in tempo with what's on the deck. Turn off IN KEY or ±6% BPM to see more." with the labels on the keys at each width (`gc15-nothing-fits-both.png`, `gc15-nothing-fits-upright.png`). The empty library upright has the icon in its sentence. `?`'s note is true with a mix on. Settings has lines under Mixing and Display. The guide has **Start here**, and "how do I", "transition" and "blend" find things |
| GC16 | PASS | The mix line clears the home indicator on the folded Duo. "History Nov 4" in full on the small iPhone |
| GC17 | Not run | The task says to skip it unless the full layout can be pressed |
| A2 | PASS | Tap and swipe: a hand, "Deck 1 is playing. Stop it first." No load (`a2-refused.png`) |
| B2 | PASS | Up and back once as the logo lifts, on the small iPhone (`b2-launch-sweep.png`) |
| B3 | PASS | The capsule's below the top bar on a phone, and the number's clear |
| B4 | PASS | 11 of 11 green and centred, over 2:04, at 666.5 of 667 px (`b4-marker.png`). My first set stopped at 6 of 6, when a track ran out |
| B5 | PASS | 170.00 on the jog straight after a load with the browser closed at once |
| B6 | PASS | +2.7 on the fader: 174.59 in the header and on the jog, 87.29 on the half-tempo deck. The menu's title says "Beat grid: 170.00 BPM at normal speed" (`b6-bpm.png`) |
| C4 | PASS | Both choices, both work (`c4-alert.png`) |
| C7 | PASS | Whole title in the browser, two lines on a compact deck |
| C8 | PASS | A plate keeps the loop's line off the text (`c8-counter.png`) |
| C9 | FAIL | Above |
| D1 | PASS | Stays lit, and a second tap restores (`d1-solo.png`) |
| D5 | PASS | New title straight away |
| D6 | PASS | "Stems 16%" |
| D7 | PASS | Reads the roll's length while held, and 32 again after |
| D8 | PASS | The old loop doesn't follow |
| D9 | PASS | "Friday warmup" in the `.cue` and the `.txt` |
| D10 | PASS | The mint layer has shape: short bursts on Houston's intro (`d10-stems.png`) |
| D12 | PASS | Stem colours stay with a part down, and the marks show what's in. Normal colours come back (`d12-muted.png`) |
| E | PASS | Hang log empty. Pause shows while playing, and play comes back at the end |
| F1 to F5 | PASS | One red pad, then "There's already a memory cue here." "Set a loop first, then save it." Recall jumps, holds and lights. `DEL` gives `UNDO` and it works (`f1-mem.png`, `f4-saved-loop.png`) |
| F6 | PASS | Name and colour reach the pad and the flag. The loop's toggle makes it armed on load, without the deck jumping (`f6-list.png`, `f6-loop-armed-on-load.png`) |
| F7 | PASS | All there after a relaunch |
| J1 | PASS | Skylander 6 sections (INTRO, CHORUS ×2, DOWN, UP, OUTRO). Gepzene 6. Exhilarate 6. Houston 9. Severe 13 (`j1-phrases.png`) |
| J2 | PASS | Counts up, restarts at a boundary |
| J3 | PASS | The two test tracks' BPM stay still. See Looks wrong for Fast Bird |
| K1 | PASS | Saved in Files, "Backup saved." |
| K2 | PASS | "Restored 5 tracks and 3 playlists." and the cue's back |
| K3 | PASS | Triangle, and "…file is missing. Import it again and it'll get its cues back." (`k3-missing-file.png`) |
| K4 | PASS | Copied back to `Documents/` under its imported name: moved home, with its hot cue, memory cue and loop |
| K5 | PASS | A dated JSON. See Looks wrong for the other one |
| Long run | FAIL | `N21`, the rest clean |

### GB1: the mixer sheet's knobs

| Where | Knob | Drag | From | To |
|---|---|---|---|---|
| Upright | `TRIM 2` | Down 60 pt, 0.5 s | 1° | -112° |
| Upright | `TRIM 2` | Up 60 pt, 0.5 s | -112° | 1° |
| Upright | `TRIM 1` | Down 85 pt, 0.5 s | 133° | -23° |
| Upright | `MASTER` | Down 120 pt, 2 s | 107° | -117° |
| Upright | `MASTER` | Up 120 pt, 2 s | -117° | 107° |
| Upright | `CUE/MST` | Up 60 pt, 0.5 s | Moved about 59°, read before I'd tightened the reader | |
| Upright | `LEVEL` | Down 40 pt, 0.5 s | Moved about 42°, the same | |
| On its side | `TRIM 1` | Down 60 pt, 0.5 s | -26° | -137° |
| On its side | `TRIM 2` | Down 40 pt, 0.5 s | 1° | -77° |
| On its side | `MASTER` | Down 120 pt, 2 s | 113° | -114° |
| On its side | `LEVEL` | Down 120 pt, 2 s | 87° | -140° (its stop) |
| On its side | `CUE/MST` | Down 40 pt, then up 40 pt | -73° | -140°, then -73° |
| Main screen, for comparison | Deck 2's `HI` | Down 40 pt, 0.5 s | -2° | -81° |

- At about 1.9° per point, 75 pt takes a knob from the centre to its stop at 140°, so 85 pt is more than the whole travel, as on the main screen.
- **The sheet still drags away:** by its title, 300 pt, and by the empty part, a 160 pt flick. 140 pt in 0.3 s bounces back, which is fair.
- **The meters move while you set `TRIM`:** on its side, with Severe playing, deck 1's column fell from 0.84 to 0.64 of its height with `TRIM 1` down, and came back with it. `MASTER` down took the middle two from 0.8 to 0.4 with the deck's column unchanged. Screenshots: `gb1-mid-drag-upright.png`, `gb1-sheet-on-its-side.png`.
- My drag still isn't a finger's, so it's right to leave it in `docs/TEST_PLAN.md`.

### GC9: the thumbs

| Layout | Press | How soon | Answer up from | For |
|---|---|---|---|---|
| Small iPhone on its side | Up | About 1 s | 20:23:24.6 | 5.2 s, to 20:23:29.8 |
| Small iPhone on its side | Down | About 3 s | 20:27:52.0 | About 5 s |
| Small iPhone on its side | Down | 3 s | 21:25:13.8 | Still up 3 s later, when I looked last |
| Folded Duo | Up | Under 1 s | 21:03:42.7 | 5.3 s, gone by 21:03:48.0 |

So the answer's there (`gc9-thumb-answer.png`). The first-time user tapped up at (315 to 317, 40), with up to 6 s of tool lag, each time close to or after the question's 8 s. Their first press may have hit no capsule at all. Nothing here says a real fault. What's worth having from it is `N18`: a press that misses the capsule is a press on deck 1.

## The first-time user

On the folded Duo upright, 20:11:40 to 20:57:31, 45:51. No crash or restart. Their full report's at the end, with what they corrected afterwards.

| Stage | From opening |
|---|---|
| Music in | +0:44 |
| First sound | +1:10 |
| Two tracks together, synced | +1:37 |
| First move across, with the crossfader alone | +1:49 |
| First use of `?` | +2:00, because the "New to this?" message said to |
| First hand blend, bass swapped | +9:30 |
| Found the guide | +10:50, by nosing around |
| First real Auto DJ move finished | +16:52 |

**How long until they could say what Auto DJ does?** About **+16:52** (20:28:32), against 34 minutes last round. In their words: "It picks a moment, brings the next track in with a named move by working the stems, EQ and filter itself, then drops the old track, usually before it ends, and any control you grab stays yours." The guide's tip to put both decks on `STEMS` got them there, along with the message naming the move. Their first `AUTO` at +5:28 taught them nothing, as the stems weren't ready and the track had 47 s left.

**Did they notice the marks above `STEMS`?** Yes, at 20:19:05, after pressing stem pads themselves. By 20:36:45 they read them as "which stems are on now", and they saw them on `SLICER` and `MEM`. They never followed a move from them: "they showed a stem was off, but not the move or how far along it was." So the marks are understood, but they didn't do the job they were made for. `STEMS` on both decks did, and that's only in the guide.

**Does `DECKS` get them back straight away?** Yes. First press at 20:12:42, and they never doubted it.

**What still does nothing with no word?** Stem pads before the split's ready (`N20`), the first fader drag after a range change, though the tempo does jump (`N17`), the Segue DJ folder (`N22`), a drag that starts just off a knob, and `SPLIT`, which only lights. They didn't drag the mixer sheet's knobs, so they can't say. They only held `ROLL` and `SLICER` pads, and I saw the message for those myself.

**Best:** `?`, and the app explaining itself at the moment it matters. "That's yours for this move" is their favourite line.

**Worst:** one stray touch can change the live mix, with no warning and no way back. The overview jumps the deck, `BRAKE` stops it, the range change leaps 30 BPM, `SAVE CUE` sits where `IN` was. Only hot cues have an `UNDO`. Their first example, `MIX`, was wrong (see above), but I think the point stands.

## The long run

Small iPhone on its side, `DUB` chosen on both, recording from 21:14:42 to 21:30:09: **15:26**. Mean -15.2 dB, peak -0.1 dB.

| Time | What | What it said |
|---|---|---|
| 21:14:43 | `AUTO` with both decks playing | "Auto DJ brings in a stopped deck. Stop the one you want next." |
| 21:15:07 | Deck 2 stopped, `MIX` | "Mixing through all your tracks, 5 tracks to go. Up next: Exhilarate." |
| 21:15:22 to 21:16:01 | Loop build into Exhilarate, 126 to 170 BPM | "Loop build done. Deck 2 is on." |
| 21:16:15 | `DUB` up and back | |
| 21:16:29 | `BROWSE`, and `DECKS` pressed frozen in the slide | Landed |
| 21:16:50 | Hot cue on deck 2, a `ROLL` held 1.5 s, `ECHO`, `OUT`, and back | "Echo out on deck 2. Press OUT again to bring it back." |
| 21:18:09 | Skylander's stems came with Exhilarate 6 s from its end | "No clean way in. Next track starts when this one ends." |
| 21:18:12 | Deck 1 starts | "No clean way in. Deck 1 just started." |
| 21:18:27 | Overview seek on Skylander | `N21` |
| 21:20:47 | Fast Bird, after the hole | "No clean way in. Deck 2 just started." |
| 21:21:18 | Houston loaded on the waiting deck | "Mix off: deck 1 has something else on it now." |
| 21:21:44 to 21:22:10 | Loop build, `AUTO` in its last bars | "Auto DJ stopped. The decks are yours. Deck 2 is still looping. ALL brings back deck 2's stems." (`long-auto-in-last-bars.png`) |
| 21:22:53 to 21:23:20 | Loop build, `EXIT` in its last bars | "Auto DJ stopped: deck 2's loop was changed. The decks are yours. ALL brings back deck 2's stems." (`long-exit-in-last-bars.png`) |
| 21:24:32 to 21:25:10 | Loop build, crossfader taken 27 pt at 21:24:40 | It stayed where I put it. No word, as it's towards the new deck (`long-crossfader-taken.png`) |
| 21:25:29 to 21:25:56 | Echo throw | "Crossfader to the middle, to hear both." |
| 21:26:12 to 21:26:39 | Loop build, `EXIT` in its last bars | "Auto DJ stopped: deck 1's loop was changed…" The new deck goes back as it was (`long-exit-in-last-bars-2.png`) |
| 21:27:13 to 21:27:43 | Vocal ride, after a seek | "Vocal ride done. Deck 2 is on." |
| 21:27:51 to 21:28:36 | **Bass swap,** after a seek | "Bass swap done. Deck 1 is on." (`long-bass-swap-done.png`) |
| 21:28:44 | `MIX` with a deck playing | "Mixing through all your tracks, 2 tracks to go. Up next: DJ Karda - Alone." |

After each hand-back, the old deck played on at full level once I'd pressed `ALL` and set its knobs back, and `AUTO` worked again straight away. Nothing was left silent, looping or filtered without the screen showing it: the message said `ALL`, the loop key was lit, and the knobs' arcs were up. The score's filter sweep took `DUB`'s knobs to `FILTER` for the move and gave them back.

**Every stretch under -50 dB on the recording, 0.15 s or longer:**

| On the recording | How long | What it is |
|---|---|---|
| 149.1 to 151.2 | 2.1 s | My echo out, which I'd asked for |
| 351.4 to 352.6 | Three of 0.17 to 0.30 s | Skylander's own, near the end of the track |
| 359.3 to 363.4 | **4.13 s** | **`N21`** |
| 624 to 640 | Five of about 0.25 s, 3.8 s apart | Gepzene's own, at 0:15 to 0:30 |
| 731 to 738 | Eight of about 0.25 s | Houston's own, at 1:10 to 1:16 |
| 766.0 to 766.2 | 0.25 s | **A Vocal ride's breath, at its landing.** About -60 to -77 dB, then -16 dB. The task only lists a Bass swap and a Loop build for this, so it's for you to say whether it's meant |
| 816.5 to 816.9 | 0.41 s | The Bass swap's breath |
| 864 to 870 | Eight of about 0.23 s | Houston's own again, same place |

The Loop builds' breaths didn't show up under -50 dB this time. No dropouts, and the recording's timer agreed with its length.

## Timings and measurements

CPU, small iPhone, RGB waveforms. Not asked for this round, but the tab row and top bar changed, so I ran it. Mac idle 53 to 73%.

| State | This round | Last round |
|---|---|---|
| Idle, nothing loaded | 3.7% | 3.7% |
| Two tracks loaded, paused | 4.2% | 3.9% |
| One deck playing | 9.4% | 9.1% |
| Both playing, synced, tempo offset | 16.1% | 16.3% |
| Both of those, plus stems and an echo | 16.6% | 17.0% |

Memory with two tracks loaded: 422 to 431 MB. So the marks above `STEMS` cost nothing I can measure.

## First impressions

**Does it look like $1000 pro software?** Close, on the wider screen, and on a phone at a glance. Three things break it most:
1. **Messages sit on top of the waveform.** They're well written, and they're over the section label and the part you're watching, on nearly every press. On the small iPhone a long one covers both decks' labels.
2. **The tab row changes under you.** `MORE` becomes whatever you last chose and never comes back, and the keys above it change meaning with the page. With `STEMS` shrinking beside `SAMPLE` on the small iPhone, this is the least finished-looking part of the screen.
3. **System forms inside a club controller.** Settings, Recordings and the mixer sheet rise half-way, then the rest. They work, and they read as a different app.

**What felt slow, confusing or surprising?**
- `MIX…` for 2 minutes with nothing to do and nothing more said (`N21`).
- The overview jumping a live deck on one touch. I used it on purpose in the long run, and it's good, but nothing asks.
- `+1` on the key taking 1B to 8B. Correct, and it reads as a bug.
- `< 1/2 >` on `FX` is a rate, and `1/1` on `MEM` is a page, in the same shape.
- How much of a track Auto DJ leaves unplayed: a minute or more on most moves here. It may well be right, but nothing says why.

**Which control was hardest to find or hit?**
- **Find:** the guide, under the gear. It's the best thing to read in the app, and the first-time user found it by accident. Nothing points there, including "New to this?".
- **Hit:** the thumbs, for being up 8 s, small, and over the overview. Then a knob's centre, as I can't test a double-tap.

---

# The first-time user's report

Unchanged, apart from this heading. Their screenshots here are the ones in `docs/test-results-16/` named `fu-*`, cut to 640 px wide. The other 37 stayed out of the repo.

**What they corrected when I asked afterwards.** They didn't edit the report for these, so where this differs, believe this:
- **Marks above `STEMS`:** first noticed at 20:19:05. They read them as "which stems are on now" by 20:36:45, and never tried following a move from them alone, or on `CUE`.
- **The mixer sheet's knobs:** never dragged. "Can't test without sound" undersells that.
- **`ROLL` and `SLICER`:** only held, never tapped.
- **Thumbs up:** tapped at (317,40), (315,40) and (317,40), each with up to 6 s of lag. `fu-mix-done-thumbs.png` shows no capsule, so that press may have hit none. `fu-thumbs-down.png` was saved about 14 s later, so "Got it" is only in their notes. "No acknowledgement" should read "none seen".
- **`MIX` at 20:24:57:** going by what they'd left it doing. They last saw Skylander's clock at about 20:21:45, and "2.5 min left" was their own arithmetic. They now call "`MIX` replaces a playing track" unconfirmed. I've checked it, under **What the first-time user got wrong**.
- **Gepzene at 0:11:** they looked about 13 s after pressing, so that's elapsed play and not a late start.

# Segue DJ - first-time user report (fu16)

Opened the app at 20:11:40. Notes written as I go.
The six numbered sections are at the end of this file, under "The report". The running notes come first.

## Running notes
- 20:11:41 Splash: spinning-platter logo + SEGUE DJ. Fine. (fu-splash.png may have caught the next screen.)
- 20:11:46 Opens straight on an empty library: "No music yet. Tap [import icon] above to add music from Files, or drop audio into the Segue DJ folder in the Files app or Finder. If Files opens on an empty folder, go back from there to find your music." Clear. The blue button stands out. (fu-empty-library.png)
- Row of buttons I do not understand yet: DECKS, a waveform-looking icon, REC, "MASTER 1 -", ?, gear, KEY, ±6%, NEXT, MIX, a sidebar icon. Lots at once. The right-hand ~19% of the screen is just black (camera cut-out strip).
- 20:12:00-20:12:06 Tapped import > "Music files..." The menu shut and nothing visible happened for about 5-8 seconds, then Files picker slid up. No spinner. Mild "did it work?" moment.
- 20:12:10 Files picker opened at "On My iPhone" with folders My Music (7 items) and Segue DJ (2 items), plus greyed json files including "Cheeks Library 2026-...json" and "Segue DJ Library...json". "Cheeks" means nothing to me as a newcomer. (Seen in fu-files? see below.)
- 20:12:24 Picked 7 files. "Added 7 tracks." toast. Music in at +44s. BPM and KEY columns show "..." with no label saying it is working. (fu-added7.png)
- 20:12:33 Tapped "1" on the first track. Row went blue, "MASTER 1 128.00" appeared. A toast says "New to this? Press ? and tap anything to see what it does." Nice and short. BPM/keys filled in about 10s after import. "1B" on DJ Karda is highlighted with a filled turquoise chip and I do not know why (probably key match to the loaded 1A?). (fu-loaded1.png)
- 20:12:42 Tapped DECKS. Enormous panel: two waveforms, two deck strips, mixer, jog wheels not visible, 8 pads per deck, loop controls. Everything fits but is tiny and dense. The word "CHORUS 1.1" in blue on the waveform. "Stems 10% - 1 min" under the title. Did not know what that was at first; clearly something is processing. (fu-decks-first.png)
- 20:12:50 Tapped green Play on deck 1. Clock counting down, meters moving. FIRST SOUND at +70s. (fu-first-play.png)
- 20:13:05 Back in BROWSE, the "1" column is dimmed because deck 1 is playing; "2" stays lit. Good hint without words. Tapped 2 on DJ Karda. Artwork filled in across the list by itself.
- 20:13:17 Tapped SYNC on deck 2 (lit blue, BPM went 129.53 -> 128.00) and Play. TWO TRACKS PLAYING TOGETHER at +97s. (fu-both-playing.png)
- 20:13:29 Dragged crossfader from middle to far right. Slid smoothly and stayed. FIRST MOVE FROM ONE TRACK TO THE OTHER at +109s. Top bar still says "MASTER 1" even though I have faded completely to deck 2. Meter columns 1 and 4 (which I am guessing are the decks) both still bounce, so I cannot confirm by eye that deck 1 went silent. Section label on deck 2 now "UP 3.3" - "UP" means nothing as a word. (fu-xfade-right.png)
- 20:13:40 Pressed ? as the toast suggested. Button lights blue; explains "touches won't change the music". Tried AUTO, MIXER (opens a sheet: TRIM 1/2, MASTER, CUE/MST, LEVEL, SPLIT, FILTER ↻ ), SPLIT, FILTER, CUE/MST, waveform icon = "RECORDINGS", beat strip = "BEAT BLOCKS", waveform, track title, STEMS tab. All clear, plain-English. This is the best thing so far. "UP's a build-up, DOWN a breakdown" answers my question about UP.
- AUTO help: "...Shows bars to go, % while the stems split, or ... while it chooses. A control you touch is yours. Press to stop. MIX does a list." The last three sentences are telegraphic. "MIX does a list" - a list of what? (need to try)
- TRACK help says "What's on this deck, and who it's by" but the second line actually shows "Stems 97% - 5 s", not the artist. It never explains what the percentage is; I only worked that out by reading STEMS PADS help. (fu-help-stems.png)
- 20:14:50-20:15:30 Walked the tabs in help mode. Stems for deck 1 finished at about 20:14:48 (started at load 20:12:33, so ~2m15s for a 3:50 track); once the split is ready the waveform re-colours while the stems are toggled... STEM STATUS: "AI with a green dot means it's ready."
- MORE is not a menu: tapping it cycles the tab through MEM -> SLICER -> JUMP -> SAMPLE -> MEM, and the label changes in place. I only found this because I kept tapping. The word "MORE" never returns once you've used it on that deck and there's no hint of how many pages there are. (fu-help-mem.png)
- Help toasts ("FX pads slide...") hang around after I've moved tab, so the FX tip was on screen over the MEM page and hides the section label on the waveform.
- 20:15:40 JOG on a deck swaps its pads for a platter, tempo fader (±10), BEAT SYNC, MASTER, BEAT JUMP, Q, SLIP, KEY, REV, ±0, KEY SYNC. Help says so. Good.
- MASTER help answered my earlier worry: top-bar "MASTER 1" is the tempo leader, not what's being heard. But the MIXER sheet also has a knob called MASTER that is a volume, so the same word means two different things. And there is also "SYNC" (top strip) and "BEAT SYNC" (jog page).
- 20:16:00 Help in BROWSE: MIX = "Auto DJ through the list on screen, in the order showing"; NEXT = re-order by tempo and key; KEY = only tracks in a matching key. KEY chip: "A is minor and B is major. The same number, or numbers next to each other, go together. It lights up when it goes with the deck that's leading." Solved the highlighted 1B mystery. But by that wording I'd have expected 12B (12 next to 1?) to light up with 1A and it doesn't; the wording doesn't say whether numbers wrap round or whether the letter must match. (fu-help-key.png)
- Note: with both decks playing, every 1 and 2 button in the list goes dim. I read that as "can't load onto a playing deck". Will test.
- 20:16:42 Deck 1 ran out. Time reads -00:00.0 in red, the deck stops by itself (Play icon back, CUE lit), top bar flips to "MASTER 2", and deck 2's blue SYNC button turned itself off. I had not asked for that. Makes sense after reading the MASTER help (the follower became the leader) but it looks like my sync was lost. (fu-track-ended.png)
- 20:16:55 NEXT lit blue and re-sorted (Houston, Skylander, Fast Bird, Severe Tire, Exhilarate, ticked Gepzene last; DJ Karda vanished from the list while on the leading deck). 12B and 1A chips light for 1B leader, so the numbers do wrap round: 12 and 1 are neighbours. Help never says so, but the highlight taught me.
  But the top NEXT pick (Houston, 5A) is not lit as a key match; it is just the closest tempo. And Exhilarate (170 BPM) is lit. So "good order" isn't obvious.
- 20:17:03 Loaded Houston onto stopped deck 1. No prompt, it just loads. Crossfader was still fully at 2. The deck 1 centre label shows artwork; a small yellow marker at the top of the platter - not sure what it is.
- 20:17:08 Pressed AUTO at 47s left on deck 2. Button turned blue "AUTO 6%". Toast: "Auto DJ is waiting for the stems. If this track ends first, deck 1 starts." Honest and clear, but means no blend is coming because the stems need 2 min and the song has 47 s. I would have liked to know this BEFORE pressing. (fu-auto-waiting.png)
- 20:18:00 AUTO gave up waiting: deck 1 (Houston) started on its own about 6 s before deck 2 ended (the toast said "If this track ends first", so I expected it at the end, not 6 s early). Crossfader had jumped back to the centre; AUTO went dark; MASTER 1. No message on how it went. Deck 1 was at 126.00 and deck 2 at 128.00, not synced, so those 6 s were two tempos at once. (fu-auto-fallback.png)
- 20:18:45 Came back from the JOG page and pressed where I remembered IN being. Because the deck had remembered the last MORE page (MEM), the same spot was SAVE CUE and I saved a cue at 0:32 by accident. Nothing warned me and there's no undo. The top row of buttons changes meaning with every tab, so muscle memory misleads.
- 20:18:55 LOOP tab, pad "4": pad lights, RELOOP turns to EXIT, region shaded on waveform. Clear. Pads have no unit: 1/4, 1/2, 1, 2, 4... of what? I assume beats. The help for jump pads said beats. (fu-loop4.png)
- 20:19:05 STEMS on deck 1 while the split was still at 92-94%. The pads still responded: VOCAL off dims the pad and lights NO VOCAL; BEAT dims VOCAL + INST. Row of 4 little coloured dots appears over the STEMS tab. I don't know what a pad does while the split's unfinished; nothing says "not yet". STEMS PADS help says "The split takes a while the first time". Waveform doesn't visibly change with stem mutes, and the meters don't noticeably drop, so by eye I can't confirm it did anything.
- 20:19:20 Stems reached "AI" (green dot). NOW the BEAT I had pressed 15 s earlier took effect: waveform went yellow+blue only, and the meters dropped. So before the split's ready the stem buttons look on but don't change anything by eye. Pad state lies for a few seconds. Also the section label changed underneath me: was "CHORUS 31.3" at 0:58, is now "VERSE 18.4" at 1:12 (18 bars back from 1:12 is about 0:38, when the old label still said CHORUS), and the colour strip under the overview re-drew. So the analysis of the song's sections changes when the stems finish, with no word about it. (fu-stems-beat.png)
- 20:19:45 ACAPELLA lights VOCAL + SOLO V; meters drop to almost nothing and the waveform goes nearly black, with an empty deck; that's odd: if vocals are all I'd asked for and the verse has no vocal right here, this looks like the deck has died. Fine once you think about it. ALL put it back.
- 20:19:50 FX tab. Tapped ECHO and the pad stayed lit (blue dot on FX tab). Is it a latch or hold? Tap again turned it off. 12 named effects on page 1/2 + DEPTH + V I B D + OUT. Help on OUT: "Ends the track on its own echo: on the next beat it cuts, and only the repeats are left. Press it again to bring the track back." V I B D: "Which parts of the track the effect goes on... Echo just the vocal and then mute it, and the echo rings out over the rest." Lovely tips, the second one is a real technique explained in one line.
- 20:20:05 REC help: "Records the mix, with a list of the tracks you played. While it's on, it shows the time and how many tracks so far. Press it again to stop and save, and it checks first."
- 20:20:11 Pressed REC. Button widens to a red "0:00". The top bar shifts and MASTER moves to the right. No toast. (fu-rec-on.png)
- 20:20:36 First manual beat-matched blend, while recording: SYNC + Play deck 2 (125 -> 126). Beat strip's centre square turned GREEN: I now read that as "beats line up" - it did stay green all through. Help called it BEAT BLOCKS (seen in help at 20:14:20) so I had a hint. REC counter went "0:24 . 1" then "0:35 . 2", counts tracks as they come in. 
- 20:20:50 LOW knob on deck 2: vertical drag worked, blue arc shows it's away from centre. Two separate taps to reset did nothing (taps too slow to be a double-tap, tool latency; not fair on the app). Tried a drag that started just below the knob and nothing happened: must start on the knob (reasonable). The knob snapped back to dead centre on a long upward drag (no arc): I read that as a centre detent or reset.
- 20:21:10 Swapped lows (deck 1 LOW down, deck 2 LOW up), then swept crossfader to 2. Deck 1's waveform visibly slimmed (bass gone), and that's how I can SEE the EQ working. Lovely. "CHORUS 6.3" on deck 2 and meters now at top: full manual blend done at +9m30s. (fu-manual-mix.png)
- Still: top bar says MASTER 1 even though the crossfader is fully on 2. Explained by MASTER help, but it trips me every time because it reads like 'what the room hears'.
- 20:21:32 Paused deck 1 with a recording still running. Deck 2's SYNC switched itself off and MASTER moved to 2. Pressed REC to stop: dialog "Stop recording?" with "Stop and save" (in red) / "Keep recording". The red colour is the danger colour but saving is the safe choice. After tap, the REC button stayed "1:23 . 2" for a moment, then "Saved Mix 2026-11-04 20.20.11" green tick toast covering the deck 1 section label. No clue where it went (fu-rec-saved.png)
- Deck 1 LOW knob still showing turned down with the arc when I moved on: a nice reminder, but I'd normally forget to reset.
- 20:21:40 Meter top on deck 2 touched a red segment briefly (the far-right column). LIM light stayed dark.
- 20:21:50 RECORDINGS sheet: warning "A recording plays out loud, over the mix. To listen to one, stop both decks." Good warning. First tap on the tracklist icon only expanded the half-height sheet to full height (the icon moved from under my finger); second tap opened the tracklist. Tracklist: 00:00 Solxis - Houston (126.0 BPM, 5A), 00:23 Igor O. Vlasov - Skylander (126.0 BPM, 11A). Skylander's own tempo is 125; it records the synced tempo. Nice to have: exactly what a mix listing should be. (fu-recordings-list.png)
- 20:22:10 Sheet shuffle: Recordings and Settings both open at about half height, then rise to full height a beat later. A row I'd aimed at was under my finger when I saw it but a different row by the time the touch landed. On Settings, aiming at "What everything does" opened the Crossfader curve menu (fu-settings-mistap.png). On Recordings, the same thing cost me one tap. It may be partly tool latency, but it happened twice.
- 20:22:30 Found the full help under gear > "What everything does" at +10m50s, because I was nosing around, not because the app pointed me there. Top section "Start here" is exactly what a beginner needs: LOAD AND PLAY, MIX TWO TRACKS (SYNC, PLAY, LOW down, crossfader across, swap LOWs at new section), LET IT MIX (AUTO, MIX, and "To see how it's done, put both decks on STEMS"). I'd love this as the opening screen. Back chevron sits oddly to the right of the search field, level with it, not top-left where iOS usually has it; Done has gone. (fu-help-page-start.png)
- 20:22:50 Help search: typing "slip" jumped to a filtered list (SLIP, JOG/PADS). "auto" found LET IT MIX, FILTER KNOB, AUTO, MIX. Worked well. After clearing with the x at the right (only the x beside the search field closes it, the circled x in the field empties text), the back chevron stays put. Two "x" controls side by side.
- The help has no way to jump from a mention of a term to its entry, but search more than makes up for it.
- 20:23:00 Settings: scrolled to the bottom. Sensible plain-English captions: "Smooth fades a deck out... Scratch keeps both at full until the very end". "Prepare stems on load" explained well, but I'd have liked this at the moment I saw the "Stems 10%" message. Backup text is honest about what's kept. "Last automatic copy November 4, 2026". "Format AAC (small)" has no caption. Done button scrolls away with the content, so once scrolled there's nothing to tap but scroll back.
- "beat grids" appears in the backup text; I have no idea yet where I can see or change a beat grid.
- 20:23:45 Dragging Settings down in two flicks left it parked as a little bar at the bottom ("Settings / Done") rather than closing; deck controls are partly behind it. Tapped Done. Fine, just unexpected.
- 20:23:50 BROWSE list now: ticks beside tracks I've played (Houston, Gepzene, DJ Karda) and NEXT has pushed those to the bottom. Nothing says that's what a tick is, though I guessed. Skylander, on the leading deck, is missing from the list entirely. At first glance I thought I'd lost a track (7 imported, 6 showing). (fu-browse-next-ticks.png)
- 20:24:00 Playlist-looking icon: menu of All tracks / History Nov 4 / New playlist... History holds what I played, correctly in play order once NEXT is off. NEXT stays on when you switch lists and re-sorts the history, so with NEXT on it wasn't in the order I played them. I noticed the blue lit playlist button sat a couple of pixels higher than the row for a moment after the menu closed. Trivial. (fu-history.png)
- Mine, I was expecting playlists to be on the sidebar; the icon is a sidebar icon but opens a drop-down.
- 20:24:05 Long press on a track row: Load on Deck 1/2, Preview, Remove from Playlist, Re-analyse, Delete from Library. Nothing on the visible page says a long press exists. In a History list "Remove from Playlist" is an odd word for a history. (fu-track-menu.png)
- 20:24:20 Preview: tapping "Preview" in the menu puts a white stop square on the artwork; tapping the artwork stops it. So tap-on-artwork is presumably preview too, but nothing says so. No progress or seek visible while previewing, and I don't know whether it's through the main output.
- 20:24:40 Created playlist "Friday set". After Create the list still showed History for a beat (no confirmation), and it then switched to the new empty list: "Nothing in this playlist yet. Go to All Tracks, press and hold a track, and add it from there." Very good empty-state. "All tracks" in the menu vs "All Tracks" here. Delete Playlist is offered on the History list too, which surprised me. Half-rendered playlist button (rounded blue shape poking up) visible behind the dialog as the menu closes. (fu-playlist-empty.png)
- 20:24:57 Pressed MIX in BROWSE with ±6% lit. WITHOUT ANY WARNING it replaced what was going on: Skylander was playing on deck 2 with ~2.5 min left and the leader flipped to "MASTER 1 128.00". The list now shows Gepzene lit on 1, Houston lit on 2. Toast: "Mixing through all your tracks, 3 tracks to go. Up next: Houston." Banner along the bottom same. "All your tracks" is wrong: there are 7, I filtered to 4 with ±6%. So "3 to go" is correct, "all" isn't. Toast sits on top of the column header and clips the first row. (fu-mix-start.png)
- 20:25:10 On DECKS: Skylander is gone. Gepzene on deck 1 started at 0:11 and playing, Houston cued on deck 2 at 0:22 (not at its start, 128.00 synced though the SYNC key isn't lit). AUTO now reads "MIX 84" (84 bars to next move, per help). Crossfader had snapped back to centre. My deck 1 LOW stayed turned right down from earlier, so the Auto DJ's first track is playing with its bass cut unless I notice. Nothing told me. (fu-mix-decks.png)
- 20:25:30 Took the help's tip ("To see how it's done, put both decks on STEMS"). Both STEMS pages up; both waveforms re-coloured into the 4 stems (pink vocal, green inst, blue bass, yellow drums). These split tracks were ready instantly ("AI" green on both), as Settings promised. Lovely to look at. Bar counter counting down MIX 76. Watching for the blend. (fu-mix-stems-both.png)
- 20:27:42-48 The Auto DJ's move, watched on both STEMS pages: two bars before, all deck 2 pads dim and its waveform goes black; deck 1 goes into a shaded orange loop and toast says "Loop build into Houston." Good words; I could actually follow it. The time on deck 1 now jumps back every 4 bars, as it would in a loop. The FILTER knob and the BASS pad's level are visibly moved by the app. (fu-mix-loopbuild.png)
- 20:28:15-20:28:32 Deck 2 started on its own with stems muted (waveform black, Play lit, meter silent), jumped back 3 s as it started, then pads lit up in turn while deck 1 shrank its loop and lost BASS. MASTER went to 2 and deck 1 was already showing DJ Karda loaded, cued at 0:23. Whole move took about 50 s of clock; 34 s of it was looping 1 min before the end of the Gepzene track, so the last minute of it was never played. Is that intended? It wasn't explained. Crossfader stayed in the middle the whole time, and my turned-down deck 1 LOW was silently reset by the new load. (fu-mix-deck2-silent.png)
- 20:28:30 Toast: "Loop build done. Deck 2 is on. More like that?" with thumbs up/down. Nice honest phrase. I pressed thumbs up and it just vanished with no acknowledgement. I do not know what "more like that" does to my future mixes, and "?" help doesn't cover it. (fu-mix-done-thumbs.png)
- MIX 91 counter is now the distance to the next move. Very clear. "MIX" also means two different things: the button in BROWSE and this indicator in the mixer. Fine.
- 20:29:00 Hot cue A: tap empty pad while deck paused: lights red "A 0:22" and a red flag on the waveform. Deck was at 0:23.1; the cue landed at 0:22 (snapped back to a beat?). DEL goes red, tap A: "Deleted hot cue A" with UNDO. UNDO worked. Exactly how an undo should be, and a contrast with the accidental SAVE CUE on the MEM page earlier.
- 20:29:15 Dragged deck 1 waveform with my finger, paused deck: moved 0:23.1 -> 0:25.0. Deck 1 meter stayed up after I lifted my finger and the deck is still paused, so I don't know if that's sound or a stuck meter. Will check.
- 20:29:25 The meter on the paused deck was only the scrub noise; it dropped once I let go. Not broken. Scrubbing a paused deck did not disturb the Auto DJ's plan or light up as "yours".
- 20:29:35 Tapped BPM. Menu took about 2 s to appear (the first screenshot showed nothing). This is where "beat grids" live: "Beat grid: 129.53 BPM at normal speed", Double, Halve, +/-0.1, 10 ms earlier/later, Set downbeat here, Save cue as memory cue, Cues and loops... The little chevron next to BPM is the only clue a whole grid editor lives here, and in help the word was "tempo". I'd never have guessed. "at normal speed" is a nice touch: the deck is showing 128.00 synced, this says its true speed. (fu-bpm-menu.png)
- 20:30:05 "Cues and loops..." gives a clean sheet: name field, time, colour dot. Named A "Before drop", made it green. Pad and waveform flag updated at once. But the name then REPLACED the "0:22" time on the pad, fine. The sheet covers the whole mix. Auto DJ kept running behind it without trouble. Nothing shows bars-to-go on the sheet, so if I'd sat here I could have missed a transition. (fu-cue-named.png)
- 20:30:30 JOG on deck 1 (paused, Auto DJ's next track). Dragging the platter round moved the position 0:25 -> 0:26 and the needle followed. It's cued/silent to my mind, but the meter for that deck leapt and the red LIM lit: I just scratched into the live mix without meaning to, with no headphone-only safety. Fair enough on a real deck, surprising for a newcomer. Also, does it wreck the Auto DJ's plan? Will see.
- 20:30:40 Key: "+" went 1B -> 8B at "+1". Correct if you know the wheel: a semitone up is 7 steps round. A newcomer reads "+1" and expects 2B. The numbers look like a bug. No note anywhere (the ± row has no help beyond "transpose"). KEY SYNC: went straight to "+4 / 5B", same number as Houston's 5A. Worked, instant. There's no visible "I changed your key by 4 semitones" warning. (fu-jog-keysync.png)
- 20:31:15 MIXER sheet's FILTER button cycles FILTER > DUB > SPACE > NOISE > CRUSH. I was cycling inside the sheet expecting to come back round, closed it, and the deck knobs now say CRUSH, not FILTER. The help had said the knob's kind is set here, but nothing says the mixer's own knob label changed until you close the sheet. Effect names DUB, SPACE, NOISE, CRUSH have no captions on this sheet. (fu-crush-knob.png)
- 20:31:15 Second Auto DJ move fired while the sheet was hiding the bars counter and I missed the start. Toast "Echo throw into DJ Karda - Alone." Good. My scratch to 0:26 was ignored: deck 1 went back to 0:19 for its own entry point. My +4 key stayed on, so the track plays 4 semitones up for the rest of its run unless I notice. Next time I look, "VERSE 8.3" and deck 2 is still running while deck 1 is at full level.
- 20:31:30 Echo throw done in about 30 s. Houston was thrown out with 1:17 still to play. Toast "Echo throw done. Deck 1 is on. More like that?" and Skylander appeared on deck 2. "MIX..." while choosing. 20:31:40 Thumbs down: "Got it. Less like that." So there IS an acknowledgement. My thumbs-up at 20:28:33 got none: either the toast had already timed out (they don't last long: about 3-5 s) or thumbs-up doesn't confirm. Can't tell which, will try again. Also I don't know if "that" means the kind of move, the track, or the pairing. (fu-thumbs-down.png)
- Skylander's waveform shows no sign of my earlier "low" adjustments or anything. Fine.
- 20:32:00-20:32:30 ROLL and SLICER on deck 1. Holding "1/4" repeats the same bit (waveform visibly stutters, "1/4" shown beside the arrows), track position carries on in the background, and on release it jumps forward to where it would've been. So that's what "roll" is: I got it from watching the clock. SLICER: I held pad 3 for a second, the deck loops a slice while I hold. Eight numbered purple pads and nothing tells you what each one is. Help says they cut the next 8 beats (of bars?). When a pad lets go, "RELOOP" and "EXIT" overlap for a moment during the fade (fu-slicer-overlap.png): just transient, reads as "REEXITOP".
- MEM page on DJ Karda, a track I've never saved anything on, says 1/1 but all 8 pads are empty. "1/1" of what? Not "0". Explained later? (to check)
- 20:32:50 Dimmed "1" while deck 1 is playing: "Deck 1 is playing. Stop it first." (hand icon). Clear refusal, and no accidental load. Good.
- 20:33:00 Wanted to change my mind about the next track. During MIX, tapped "2" on Gepzene. Skylander left, Gepzene loaded, and the whole mix turned itself off: "Mix off: the track changed." (fades over the BPM header). The banner vanished and MIX went back to Play. So you can't swap the next song and keep the mix running, you have to start again, and that restart would dump the playing song. Mix text didn't warn. (fu-mix-off-loaded.png)
- 20:33:05 Search box: "vlas" finds the artist, "zzz" gives the standard "No Results" page. Works. Filters can't be seen when the keyboard's up... fine.
- 20:33:20 Long press > Add to Playlist > Friday set: submenu, tick toast "Added to Friday set." Clean. Took me 20 s because the empty-state had already told me how. Excellent.
- 20:33:40 Loaded Exhilarate (170 BPM). SYNC straight to 128.00: slowed by 25% without a word or warning, no "that's a long way" nudge. Beat strip went green, so by every sign on screen it's a good match. Its clock still reads the track's own time, so "-02:20" isn't really 2 min 20 at this speed: from the clock on deck 1 I measured about 3 min at this speed. Remaining-time counters don't tell you when the track will really end if synced far from its own tempo.
- 20:34:10 JOG on deck 2: the page is mirrored, so Play and CUE stay on the outside edge. Nice. The tempo fader's readout "-24.7" is half-hidden by the home bar at the bottom of the screen, and "WIDE" replaces the "±10" label. REV lit red: position ran backward (00:21.4 -> 00:17 -> 00:13.3) and the section count "16.1 -> 13.1 -> 10.2" ran down. Beat strip went yellow while reversed. Then SLIP on + REV off: jumped ahead to 00:19.3 as if it had been running all along, and a new orange colouring appears. REV stayed dim red and the deck went forward. SLIP with REV is what a DJ would call a censor; the help mentions neither. Can't confirm by ear. (fu-rev-slip.png)
- Exhilarate's waveform changed from orange to colours part-way through while I was on JOG. No percentage visible on this page: the page swaps out the Stems progress line and tells you nothing, so colour change is the only sign that stems finished.
- 20:34:55 WIDE button cycles the tempo range (WIDE -> ±6 ...). Switched to ±6 while the deck was synced at -24.7%. The fader thumb pinned itself at the top (out of range) but kept showing -24.7 and 128.00, so nothing moved yet.
- 20:35:05 Then I touched the fader to nudge it. The tempo leapt from 128.00 to 159.80 BPM at once, a 32 BPM jump in the live mix, SYNC dropped out with no message, and the thumb stayed pinned at the top reading -6.0. I had moved it about 60 points downward, and it didn't follow my finger. A newcomer would have no way to foresee this. Reads as a real trap: the range button is one tap away from the fader. (fu-tempo-jump.png)
- 20:35:20 Tapped a headphone button. Toast: "You'll hear the cue with SPLIT on and a splitter cable." The exact thing I needed to know, at the moment I needed it. One catch: the toast sits on top of the waveform's section label and the overview, as they all do. (fu-headphone-tip.png)
- 20:35:40 MIXER sheet's knob-kind button cycles FILTER > DUB > SPACE > NOISE > CRUSH > PITCH > back. Six stops; nothing lists them. SPLIT lights, no explanation on the sheet. Meter sussed by now, after deck 1 ended: left column = deck 1, right column = deck 2, the two middle = the master, I think. Nothing says so. (LIM never lit except when I scratched by accident.)
- 20:35:55 Mis-load: BROWSE slides in over the decks as a half-height panel first (waveform 2 and the list share the screen), then the list rises to full height. I aimed at Fast Bird from the half-way view and the row under my finger had become Skylander; Skylander loaded on deck 1 with no confirmation and the deck lost its last-played position (it starts back at 00:00.5). My tool is slow, so this is partly on me, but it's the third time a sheet moving in has moved my target. (browse mid-animation)
- 20:36:05 Pressed AUTO with 43 s left on Exhilarate, at 159.80 (my accidental tempo) and Skylander cued at 125. Button reads "AUTO..." (choosing). No toast on this one since Skylander's stems are done. (fu-auto-choosing.png)
- 20:36:28 AUTO counted bars (AUTO 3, 2, 1). Toast at the start: "Loop build starting. STEMS shows what's in. A control you touch is yours." Two lines; covers the Skylander section label and top of the deck 1 waveform. (fu-auto-loopbuild2.png)
- 20:36:33 Mid-move I dragged deck 2's FILTER knob. Toast: "That's yours for this move. Auto DJ carries on with the rest." Best message in the app. It explains itself the very moment it matters, and it lets me play along. The platter ring also went from blue to pink, and I don't know why. (fu-auto-yours.png)
- 20:36:45 Back on PADS during the move, STEMS page. The BASS pad on deck 2 has a slow-moving bar in it, the LOW knob turned itself, and the 4 small dots above the STEMS tab show the mix state. So you can watch a knob do things by itself. That's lovely. The little dot row works from other tabs too: I saw it dim on deck 1 while on SLICER.
- 20:36:58 Loop build #3: "Loop build done. Deck 1 is on. More like that?" Pressed thumbs-up within 1 s this time: toast vanished, no words of thanks. Thumbs down got "Got it. Less like that." So thumbs up silently does nothing visible. I can't tell if it was recorded. Also Auto DJ stopped after the move, since I'd started it with AUTO (one move) rather than MIX. Skylander is synced to 125 and Exhilarate went back to 170 and stopped. Deck 1 got its bass back on its own. All good.
- 20:37:15 JUMP: forward 32: position jumps from 00:53 to 01:12. Labels have no unit but it's 32 beats at 125. The "Done" pad in help said "1, 4, 16, 32 beats". OK. Waveform kept up at once.
- 20:37:25 SAMPLE page: AIR HORN, SIREN, RISER, IMPACT, LASER, CLAP, RIM, REWIND. Air horn lights red. SET + pad opens "Pad 2": One shot / Gate / Loop, Choose a File, Record the Master. Clear. "Samples can be up to a minute long, and recordings stop at 30 seconds." Terms are clear enough. The name field is editable. Nothing explains Q or VOLUME (the VOLUME bar is a slider, not a title). (fu-sample-pad.png)
- Observed: the SET button stays lit behind the sheet. I don't yet know if it's switched off when I return.
- 20:37:50 "Record the Master" started the moment I tapped it, no count-in, and overwrote SIREN with no warning. Pad turned red with a record dot and the SET key became a red stop with a count "0:00". Stopped with the same key at about 6 s: pad now reads "REC 2" and tapping plays it. Works! But SIREN is gone and the Pad sheet (that I saw) doesn't offer to put it back. The meters on the far-right column (deck 2) stay dark: I saw no change on the meter when playing the sample. The sample goes straight to master, presumably.
- Sheet rising again cost me a tap: at half height "Record the Master" was at y≈490; the sheet rose before my tap landed, and I hit empty space. Harmless this time. (fu-rec2-pad.png)
- 20:38:50 Re-imported one track on purpose: "That track's already in your library." Good. (fu-dupe-toast.png) In the Files picker I could not open the Segue DJ folder with 2 attempts, plain and firm: the app's own folder (which the empty-state says to drop audio into) didn't respond to a tap while My Music did. Item count went from 2 to 4 during this session, so something was added to it: I wonder if it's my recordings. Greyed .json backups clutter the "On My iPhone" root in the picker.
- 20:39:10 Playlist "Friday set" (2 tracks), MIX from a stopped state. "Mixing through Friday set, 1 track to go. Up next: Severe Tire Damage - High Quality." MIX button shows a stop square while running. Clean. It swapped both of my loaded decks without asking, which is fine as nothing was playing. Deck 1 started playing at once and went straight to 0:00 this time. (Earlier from a running deck it started the first track at 0:11; I don't know why.) Fresh track shows a stem percentage, and AUTO reads "MIX 1%" (waiting). My crossfader, knobs etc. stayed centred. (fu-mix-friday.png)
- 20:39:40 Pinch-zoom on a waveform works, and zooms BOTH waveforms together. Nothing suggested it; I just tried it. Nice.
- 20:39:45 MISREAD: on the FX tab the "< 1/2 >" at the top I took for "page 1 of 2", expecting a second page of effects. It's the effect rate (1/2 -> 3/4 beat). The same 12 effects stay on. I said "page 1/2" in my earlier notes: I was wrong for ~20 minutes. A newcomer's natural reading of "< 1/2 >" is pagination. (fu-fx-fraction.png)
- 20:39:55 FX: BRAKE. First tap lit it and the track carried on. Second tap (turning it off, as I thought) stopped the deck dead at 00:40.0. Meters flat, Play icon back. The running MIX went with it: the "MIX 24%" indicator became plain "AUTO" and no message told me the mix had stopped. I then tried ECHO + OUT to see what they'd do and got "Echo out needs the deck playing." (hand icon). That one's clear. ECHO stays lit on a stopped deck. So BRAKE is the one FX pad that can stop the music entirely, and it sits in the same grid as the harmless ones, one tap from REVERB. Might be meant, but on a first go I thought the app had broken. (fu-brake-killed-mix.png)
- 20:40:25 Bring-back of OUT: toast "Echo out on deck 1. Press OUT again to bring it back." OUT lights red, meters decay to nothing while the clock keeps going, second press brings it straight back. Very well explained; I'd use this.
- 20:40:35 Column heads TITLE, BPM, KEY sort when tapped (chevron shows). Undiscoverable until you try, but standard.
- 20:40:50 "Delete Fast Bird?" "This removes its file from Segue DJ, along with its cues, loops and stems." Clear. I cancelled.
- 20:41:05 CUE on a playing deck: back to the start and stopped. Standard. Held CUE for 3 s: plays while held, returns on release. Standard. For a moment after release the transport shows a dim green pause icon rather than a play icon.
- 20:41:30 Recording plays with a slider. Meters on the decks don't show it, so with sound off I only have the clock. ... menu offers Rename / Delete. Closing the sheet while it plays: I can't tell if it stops (no meter, no indicator on the REC or waveform buttons).
- 20:42:30 Help search at last answered the questions I'd collected. "brake": "Slows the track to a stop... The deck stays stopped until you press PLAY." So my 'broken' BRAKE is by design; it should say so on the pad. "thumb": "Auto DJ leans towards what you like, though it never rules a move out. Ratings stay on your device." CORRECTION to my note at 20:28: the help does cover thumbs, but under a search word ("thumb") I had to guess. "Auto DJ's moves" section: LOOP BUILD, ECHO THROW, BRAKE DROP, VOCAL TEASE. Each is two lines, exact and vivid. I saw two of the four, and the description matches what I watched. There's no tip to look here from the toast itself. (fu-help-moves.png)
- Search field auto-capitalises my word; harmless. Clearing it is two taps because the first x clears text and the second closes search.
- 20:42:30 "AUTO" with a stopped deck: "Play a track first, then Auto DJ can mix out of it." Clear refusal.
- 20:42:35 Tap on the thin overview strip at the top of the waveforms jumped deck 1 straight to 2:18 of the track, while playing and mid-mix. No hold or confirm. It is a useful seek, but a slip of the finger there is a jump in the live mix. Nothing says tap-to-seek exists except the help.
- 20:42:39 AUTO with stems ready: "Brake drop next, with deck 2 cued at 148 BPM. AUTO's counting down the bars." Tells me the plan ahead of time. This is what I wanted at 20:17. AUTO 13 counter. Deck 2's Stems ready shows "AI" and it shows the section map below the strip. Good. (fu-brake-drop-announce.png)
- 20:43:01-03 Brake drop: exactly what help said. Deck 1 stopped with 1:02 left and deck 2 came in at its chorus at 148 BPM, in about 2 s, MASTER changing to 2 and meter columns swapping over. Plan was announced 24 s in advance. Very cool to watch. The announcement toast is covering the deck 1 section label throughout. Its "cue" is at the chorus (0:38.9), I never picked it. Deck 1's unplayed last minute is gone. (fu-brake-drop-done.png)
- 20:43:15 Third thumbs-up test: the very next screenshot shows the banner gone and no words. Thumbs-down had said "Got it. Less like that." So the up button looks like it did nothing, every time. I can't tell whether the rating landed.
- CORRECTION to my 20:33:40 note: I wrote that I had "measured about 3 min" for Exhilarate's remaining time at 128. I did not measure that. It was arithmetic (2:20 x 170/128) at the time. I will test it properly now.
- 20:44:22 Clock test, measured. Exhilarate synced down to 148 on deck 1, Severe Tire at its own 148 on deck 2, both running. Between two screenshots deck 1's elapsed went 0:01.5 -> 0:21.5 (+20.0 s), deck 2's went 1:35.8 -> 1:58.7 (+22.9 s). Ratio 0.87, the same as 148/170. So the big countdown is in the track's own time: a slowed track's "-02:03" will really take about 2:22. Nothing on screen says so. For timing the next move that matters, and it's the biggest number on the deck. (fu-clock-test.png)
- Exhilarate is labelled CHORUS 1.1 from the very first bar, with an empty waveform for the first few bars. I can't judge by ear, but "chorus" at bar 1 reads wrong. Severe Tire's label went CHORUS 52 -> VERSE 2 mid-track, so the labels do move on.
- 20:44:40-20:45:33 Pressed Home and spent 54 s in the Files app. Came back: both decks had kept playing, still green on the beat strip, clocks moved on the right amount (deck 1 0:21.5 -> 1:23.1 at 87%). So background play works and sync held. No lost state. (fu-back-from-background.png)
- In the Files app itself, the "Segue DJ" folder (the one the empty-library screen tells you to drop music into, now 4 items) will not open. Plain tap, firm tap and a tap on its name all did nothing. The "My Music" folder next to it opens on one plain tap and a file in the same column opens too, so it isn't my aim. Same in the app's own picker at 20:38. It might be a simulator thing, I can't tell. If it's real, the second way in on the opening screen doesn't work. (The 4 items: I assume my recording is in there, but I can't look.)
- Files named jam1051513 etc. appear in the app with proper title and artist. Good: the app read the tags. It also picked up the artwork.
- 20:46:10 Manual loop on the LOOP tab: IN lights orange and a line appears on the waveform; OUT makes the region shade and RELOOP turn to EXIT, and the number box shows the length in beats ("9"). "<" halved it to 4.5. Clean. While the half-size loop ran, the beat strip's centre square went from green to yellow, which I read as "you've drifted off the beat", and it's the only warning of that I've seen. (fu-manual-loop.png)
- 20:47:05 Reloaded Houston to see what became of my accidental SAVE CUE from 20:18:45. It's still there and the track now LOADS parked on it, at 0:32.8, rather than at the start. So one stray tap on SAVE CUE changed where this song starts from, for good, and nothing said so. MEM's "1/1" turns out to mean page 1 of 1 (help: "as many as you like, a page at a time"), which answers my 20:32 question, though an empty page saying 1/1 still reads like "1 of 1 saved".
- 20:47:20 LIST opens a sheet with the cue name, colour and time. A full swipe left on the row deleted it at once. No confirm, no red button stage, and the list went straight to "Nothing saved yet. Set hot cues on the CUE pads, and save cues and loops on the MEM pads." Good empty-state, but the same action on a hot cue pad gave me UNDO at 20:29. The screenshot caught the row mid-slide with "0:32" sitting half-clipped on the left. (fu-cue-swipe-delete.png)
- 20:47:45 Tested it: with the memory cue deleted, Houston reloads at 00:00.0 INTRO 1.1. So the first memory cue really is the load point, and my "for good" at 20:47:05 is only until you find and delete it. Deleting a cue from LIST gave no toast or undo once I was back on the decks. (Auto DJ ignores this: at 20:25 it cued Houston at 0:22 after the 0:32 cue existed.)
- 20:48:05 SOLO I on deck 2: the waveform drops to just the green part, three pads dim, meters fall by half. ALL brings it back. The clearest cause-and-effect on any control. Home bar sits over the bottom edge of the SOLO row.
- 20:48:17 Beat grid menu on Houston: Halve BPM, instant 126 -> 63, no confirm. Then SYNC: "Deck 1 follows at half tempo: 74 against 148." Exactly the sentence I needed; it makes the 74 on screen make sense. So SYNC is smarter than "match the number". It also moved the paused deck from 0:00.0 to 0:00.4, off its cue triangle, with no mention. (fu-half-tempo.png)
- Why that SYNC message exists but the 170 -> 128 sync at 20:33:40 (a 25% slowdown) got no message at all, I can't say. I would have expected the bigger stretch to be the one worth flagging.
- 20:48:50 MIX on Friday set while Severe Tire was playing: "Everything else here has been played. To go round again, stop the deck and press MIX." Clear, and it tells me what to do. It also tells me the ticks matter: MIX skips ticked tracks while something's playing. That's the first I've heard of that. It covers the column headers, as usual. (fu-mix-all-played.png)
- 20:49:15 Stopped the deck and pressed MIX: "Mixing through Friday set, 1 track to go." It started from the top of the list on deck 1 and put Severe Tire on deck 2, cued at its chorus. Tapping the overview strip to jump Gepzene forward moved the counter from MIX 88 to MIX 9 at once, so the plan re-works itself. I now want to see what happens when the list runs out.
- 20:49:38-20:50:20 Same pair of tracks as the brake drop at 20:43, but this time "Loop build into Severe Tire Damage". Help says brake drop is "for tracks nothing else can join", so seeing a loop build across the same 128/148 pair seven minutes later makes me unsure what decides. Could be my thumbs-up on loop builds, I can't tell. During the build the top bar stayed 128 while deck 2 ran at 148, and deck 1's LOW and FILTER knobs visibly turned on their own. (fu-loop-build-two-tempos.png)
- 20:50:24 Time-left readout turns red below 30 s. Nice, and nothing else tells you.
- 20:50:56 "That's the end of Friday set." A proper ending: Severe Tire ran out at 00:00.0, MIX went back to AUTO, deck 1's Gepzene sat cued at 2:47 where the loop build left it, meters dark. No thumbs on this one. Clean. (fu-end-of-set.png)
- 20:51:35 Reloaded DJ Karda. Hot cue A "Before drop" is still green and named, with a green flag on the overview. Cues persist per track, which is what I hoped.
- 20:52:00 Fresh track on deck 1, deck still showing WIDE (carried over from the earlier track; I never pressed WIDE on this deck, so something moved it there). KEY off, then a small drag of the tempo fader, about 18 points DOWN: 129.53 -> 187.91, +45.1%. So a tiny nudge is a huge jump, and pulling down makes it faster, which is how a real deck works but not what a newcomer will guess. The key chip went 1B -> 7B and turned pink, which is the sign that key has moved. Nice. (fu-wide-fader.png)
- 20:52:10 Second go at the fader: dragged back the same 18 points and it landed on exactly +0.0 / 129.53. WIDE -> ±6 is safe when the tempo is inside the range. (No screenshot.)
- 20:52:30 SPLIT in the Mixer sheet lights blue. Nothing else changes that I can see, and with no sound I can't test it. Turned it off again.
- 20:52:53-58 REPRODUCED the tempo jump. Deck 2 synced from 170 to 129.53 (-23.81%, range showed WIDE by itself). Tapped WIDE -> ±6: thumb pins at top, readout still -23.8, tempo still 129.53. Touched the fader and moved 5 points: 159.80 BPM, -6.00%, BEAT SYNC off, beat strip yellow, no message. 159.80 is 170 x 0.94, so it clamps to the edge of the new range. A second drag then moved the thumb normally (-6.0 -> -1.2). CORRECTION to my 20:35:05 note: the thumb only ignores the FIRST drag after the range change. (fu-tempo-jump-repro.png)
- 20:52:50 Noticed deck 2's SLIP is still on from when I pressed it at 20:34, through several loads and Auto DJ moves. It's only visible on the JOG page.
- 20:53:56 Picker again: third round of tapping the Segue DJ folder, still doesn't open. (fu-picker-segue-folder.png)
- 20:54:48 Checked Settings: crossfader curve is still Smooth, so my mistap at 20:22 changed nothing.

---

# The report

Started 20:11:40 (launch command). No crash at any point; I never had to restart the app.

Two things to keep in mind when reading. Every action goes through a tool that takes a few seconds, so all times below are upper limits, not what a finger would take, and a few of the mistaps are partly the tool's fault (I say which). And I can't hear: "worked" only ever means keys, numbers, waveforms and meters did what I'd expect.

Corrections I made during the session are in the running notes above, marked CORRECTION. Where they differ, this section is the one to believe.

## 1. Every moment I wasn't sure what to do

Times are clock times. Elapsed is how long until I'd got past it. "No shot" means I didn't save a screenshot of that moment.

1. **Did the import work?** Wanted to open Files. Tapped the blue import button, then "Music files...". The menu shut and nothing showed for 5-8 s, with no spinner. It then opened by itself. About 10 s, 20:11:54-20:12:06. No shot of the wait. The picker it opens is in fu-picker-segue-folder.png (taken later).
2. **I've got tracks, how do I get sound?** Tapped "1" on a row, expecting it might play. It only loaded, and the list shows no clock or meters, so I had to spot DECKS, top left. Then green Play. 17 s, 20:12:33-20:12:50. fu-loaded1.png, fu-decks-first.png. A short toast at this moment pointed me at the ? button, which was the most useful thing that happened all session.
3. **What's the highlighted 1B chip?** One key in the list lit up as a solid chip and I didn't know why. Guessed key match. The ? help on KEY confirmed it, and NEXT lighting 12B and 1A against 1B showed me numbers wrap round. About 3.5 min, 20:12:33-20:16:55. fu-loaded1.png, fu-help-key.png.
4. **What's "Stems 10% - 1 min" under the title?** Something was clearly running. I didn't know what, or whether to wait. Help on the STEMS pads explained it; help on the track title, where it actually appears, did not. About 2 min, 20:12:42-20:14:44. fu-decks-first.png, fu-help-stems.png.
5. **Faded fully to deck 2 and the top still says MASTER 1. Did it work?** Read MASTER as "what's being heard". Meter columns 1 and 4 both still moved, so I couldn't confirm by eye. Help said MASTER is the tempo leader. About 45 s to explain, but it kept tripping me for the whole session. fu-xfade-right.png.
6. **Where's the rest of MORE?** Tapped MORE, expecting a menu. It changed the tab label to MEM. Kept tapping and it cycled MEM, SLICER, JUMP, SAMPLE. Nothing says how many pages there are, and the word MORE doesn't come back. About 25 s, 20:15:00-20:15:26. fu-help-mem.png.
7. **Why are the 1 and 2 buttons dim?** Both decks playing, so every load button dimmed. Guessed "can't load onto a playing deck". Finally tested at 20:32:50: "Deck 1 is playing. Stop it first." Clear once tried. No shot.
8. **Why did my SYNC turn off?** Deck 1 ended and deck 2's SYNC went dark by itself, MASTER moved to 2. Makes sense after the MASTER help, but looks like losing something. 20:16:42. fu-track-ended.png.
9. **AUTO with 47 s left.** Wanted to see it mix. Got "Auto DJ is waiting for the stems. If this track ends first, deck 1 starts." Waited 52 s. Deck 1 started about 6 s before deck 2 ended, at a different tempo, with nothing said. I'd have liked the warning before pressing. 20:17:08-20:18:00. fu-auto-waiting.png, fu-auto-fallback.png.
10. **Accidental SAVE CUE.** Came back to a deck and pressed where IN had been. The deck had remembered the MEM page, so that spot was SAVE CUE, and it saved one at 0:32 with no message. I only learned the consequence half an hour later: the track then loaded parked at 0:32. Found the fix through LIST at 20:47. 20:18:45 to 20:47:45. No shot of the moment; fu-cue-swipe-delete.png shows the delete.
11. **Do the stem pads do anything?** Pressed BEAT while the split was at 92-94%. Pads changed, waveform and meters didn't. I thought it was broken until the split finished 15 s later and it all took effect. 20:19:05-20:19:20. fu-stems-beat.png.
12. **How do I reset a knob?** Turned LOW down, then tried two taps to reset. Nothing (my taps may be too slow to count as a double tap, so not fair on the app). A long drag upward stopped dead at centre. I never learned if there's a proper reset. About 20 s, 20:20:50-20:21:10. fu-manual-mix.png.
13. **Where did my recording go?** Toast: "Saved Mix 2026-11-04 20.20.11", no location. I'd seen the waveform icon called RECORDINGS in help mode, so I tried that. 15 s, 20:21:35-20:21:50. fu-rec-saved.png, fu-recordings-list.png.
14. **Aimed at "What everything does", got the crossfader menu.** Settings opens part way up, then rises under your finger. Same thing cost me taps on Recordings (20:21:55) and the Pad sheet (20:37:41). The worst was BROWSE at 20:35:55, where it loaded the wrong track on deck 1 (Skylander instead of Fast Bird). Tool lag is part of this. fu-settings-mistap.png; no shot of the wrong load.
15. **Wanted to learn the app; where's the manual?** "What everything does" is under the gear. I found it at +10:50 by nosing around, and nothing pointed there. fu-help-page-start.png.
16. **Pressed MIX to see what it did.** It threw out the track I was playing, with about 2.5 min left and no warning, and started another. 20:24:57. fu-mix-start.png, fu-mix-decks.png.
17. **What does "More like that?" do?** Thumbs up made the toast vanish with no word. Thumbs down said "Got it. Less like that." Found the explanation only when I searched help for "thumb". 14 min, 20:28:33-20:42:30. fu-mix-done-thumbs.png, fu-thumbs-down.png, fu-help-moves.png.
18. **Key +1 turned 1B into 8B.** Looked like a bug. It's correct if you already know how the numbers work, and nothing in the app says so. 20:30:40. Never explained. fu-jog-keysync.png.
19. **FILTER button in the Mixer.** Cycled it hoping to see what it did, closed the sheet, and my deck knobs now said CRUSH. Took me a while to go back and cycle all the way round. 20:31:15-20:35:40. fu-crush-knob.png.
20. **I changed my mind about the next track.** Loaded a different one during MIX. "Mix off: the track changed." So you can't swap the next track and keep going. 20:33:00. fu-mix-off-loaded.png.
21. **Tried a narrower tempo range on a synced deck.** Tempo leapt, see section 4. 20:34:55-20:35:19. fu-tempo-jump.png, fu-tempo-jump-repro.png.
22. **"< 1/2 >" on the FX tab.** Read it as "page 1 of 2" and went looking for page 2. It's the effect's rate. I carried that wrong belief for 20 minutes, 20:19:50-20:39:45. fu-fx-fraction.png.
23. **BRAKE stopped everything.** First tap lit it, second tap (I thought, off) stopped the deck dead, and the running mix quietly went away. Thought the app had broken. Help search: "The deck stays stopped until you press PLAY." 2 min, 20:39:55-20:42:00. fu-brake-killed-mix.png.
24. **The Segue DJ folder won't open.** The first screen offers that folder as a way in. Plain tap, firm tap and tap on the name: nothing, in the picker and in the Files app. My Music opens on one tap. Never solved. 20:38:40, 20:45:00, 20:53:56. fu-picker-segue-folder.png. It may be a simulator quirk, I can't tell.

Moments that looked confusing but weren't, because the app caught me first: the empty playlist ("Go to All Tracks, press and hold a track"), re-importing a track, MIX with everything played, AUTO on a stopped deck, Echo OUT on a stopped deck, and the headphone button's "You'll hear the cue with SPLIT on and a splitter cable."

### Help: what it did and didn't do
- **? mode.** Used at +2:00 because the first toast told me to. It answered MASTER, stems, UP/DOWN, KEY colours, NEXT, MIX and SLIP, in plain English and without touching the music. It's my main way of learning the app. It doesn't help with gestures you don't know exist (long press, pinch, overview tap) or say what happens if you do something twice (BRAKE).
- **"What everything does".** "Start here" is exactly right. Search is good. "Auto DJ's moves" is the best two minutes of reading in the app. Too hard to find, and the toasts never link to it.
- Not found anywhere I looked: what the numbers do when you transpose, what the WIDE range is, and what the meter columns are.

## 2. How long each stage took, from opening the app

| Stage | Clock | From opening |
|---|---|---|
| Empty library on screen | 20:11:46 or sooner | +0:06 |
| Files picker open | about 20:12:06 | +0:26 |
| **Music in (7 tracks)** | 20:12:24 | +0:44 |
| BPM and keys filled in | about 20:12:34 | +0:54 |
| First track loaded on a deck | 20:12:33 | +0:53 |
| **First sound (meters and clock running)** | 20:12:50 | +1:10 |
| **Two tracks playing together, synced** | 20:13:17 | +1:37 |
| **First move from one to the other (crossfader only)** | 20:13:29 | +1:49 |
| First used ? help | 20:13:40 | +2:00 |
| First stem split finished (a 3:50 track, 2:15 after loading) | about 20:14:48 | +3:08 |
| First AUTO press (it gave up, no real blend) | 20:17:08 | +5:28 |
| First recording started | 20:20:11 | +8:31 |
| First proper blend by hand: synced, bass swapped, faded across | 20:21:10 | +9:30 |
| First recording saved, tracklist read | 20:21:50 | +10:10 |
| Found the full help page | 20:22:30 | +10:50 |
| Playlist made | 20:24:40 | +13:00 |
| First MIX | 20:24:57 | +13:17 |
| **First real Auto DJ move finished (loop build)** | 20:28:32 | +16:52 |
| Playlist played start to finish by Auto DJ, ending cleanly | 20:50:56 | +39:16 |

The last row is flattered: I jumped to the last 30 s of the final track on purpose (20:50:24, tapped the overview strip), so that jump in the logs is me.

## 3. What I still can't explain, and wording that was wrong, misleading or no help

**Still can't explain**
- What decides Auto DJ's move. The same two tracks (Gepzene into Severe Tire) got a brake drop at 20:43 and a loop build at 20:49. Help says brake drop is for tracks nothing else can join. Could be my thumbs-up, could be something else.
- Why Auto DJ leaves so much unplayed: loop build at about 1 min left, echo throw with 1:17 left, brake drop with 1:02 left. Possibly intended, but nothing says so.
- Why MIX started Gepzene at 0:11 and cued Houston at 0:22 the first time, but started from 0:00 at 20:39.
- Why half-tempo sync gets a sentence ("Deck 1 follows at half tempo: 74 against 148") but a 25% slowdown (170 to 128) gets nothing.
- Whether my thumbs-ups count at all.
- The meter's four columns. My guess, from watching: outer two are the decks, middle two the master. And why LIM lit only when I scratched by accident.
- SPLIT, CUE/MST and LEVEL: I can't test without sound. The Q button: lit from the start, and I never found out by experiment what turning it off does.
- What DUB, SPACE, NOISE, CRUSH and PITCH do. No caption on the sheet, and I can't hear them. Same for most FX names.
- The small green tick on the tempo fader, the yellow marker on the platter, and the colour of the platter ring, which looked different at different times. My note about it going pink (20:36:33) may just be artwork colour.
- Where recordings live on the phone. The Segue DJ folder went from 2 to 4 items during my session, and I can't open it to see.
- Whether a preview plays through the main output, and whether a recording stops playing when you close its sheet.

**Wording that was wrong or misleading**
- **"Mixing through all your tracks, 3 tracks to go"** when I had filtered the list to 4 of 7. fu-mix-start.png.
- **"If this track ends first, deck 1 starts."** It started about 6 s before the end. fu-auto-waiting.png.
- **"< 1/2 >" means two different things.** On FX it's the rate, on MEM ("1/1") it's the page. Same shape of control. fu-fx-fraction.png.
- **MASTER means two things:** tempo leader on the top bar and JOG page, volume in the Mixer sheet. **SYNC** and **BEAT SYNC** look like two things and appear to be one. **MIX** is both a button and a status readout.
- **Track-title help** says it shows "who it's by", but the line it means actually showed "Stems 97% - 5 s". fu-help-stems.png.
- **"Remove from Playlist"** and **"Delete Playlist"** on the History list. fu-track-menu.png, fu-history.png.
- **"All tracks"** in the menu, **"All Tracks"** in the empty-state text. Trivial.
- **"Stop and save" in red.** It's the safe choice, but in the danger colour.
- **"More like that?"** "That" could be the kind of move, the track or the pair.
- **"MIX does a list."** Help text on AUTO. Doesn't say a list of what.
- **"UP" and "DOWN" on the waveform.** Meaningless until you read help.
- **CHORUS 1.1 at the very first bar** of Gepzene and Exhilarate, the latter over an almost empty waveform. I can't judge by ear, but it reads wrong. Labels also changed when the split finished (see 4).
- **"Cheeks Library 2026-...json"** among the files in the picker. A name I can't connect to this app. fu-picker-segue-folder.png.

**No help**
- WIDE, no caption, no explanation of the range.
- The "+1" key step, as above.
- MORE, as above.

## 4. Anything that looked broken, however small

**Matters**
- **20:34:55-20:35:05, reproduced 20:52:53-20:52:58. Tempo jump.** On a deck synced beyond the range, switching range to ±6 looks harmless, then the first touch of the fader jumps the tempo to the edge of the new range. 129.53 to 159.80 BPM in the live mix, SYNC drops, the beat strip goes yellow, no message. The thumb ignores that first drag and works on the next one. fu-tempo-jump.png, fu-tempo-jump-repro.png.
- **20:38:40, 20:45:00, 20:53:56. Segue DJ folder doesn't open**, in the picker or in Files, from three kinds of tap. fu-picker-segue-folder.png. Might be simulator-only.
- **20:24:57. MIX replaces a playing track with no warning.** Looks deliberate, reads as broken. fu-mix-start.png.
- **20:39:55. BRAKE ends a running MIX with no message.** "MIX 24%" just becomes "AUTO". fu-brake-killed-mix.png.
- **20:19:05-20:19:20. Stem pads show a state that isn't in effect** until the split finishes. Pads say BEAT, waveform says everything. fu-stems-beat.png.
- **20:19:20. Section labels change when the split finishes.** CHORUS 31.3 at 0:58 became VERSE 18.4 at 1:12, and the colour strip redrew. No word. Same screenshot.
- **20:18:45 and 20:47:05. A stray SAVE CUE moves the track's load point.** No toast, no undo. **20:47:20:** deleting it by swipe has no undo either, while deleting a hot cue pad at 20:29 does. fu-cue-swipe-delete.png.
- **20:17:50-20:18:00. AUTO's fallback** ran deck 1 at 126 and deck 2 at 128 together for about 6 s. fu-auto-fallback.png.
- **20:35:55, also 20:21:55, 20:22:10, 20:37:41. Sheets rising under your finger.** One wrong track loaded. Partly tool lag, but it happened four times. fu-settings-mistap.png.

**Small**
- 20:43:15, 20:36:58, 20:28:33. Thumbs up gives no acknowledgement; thumbs down does. fu-mix-done-thumbs.png, fu-thumbs-down.png.
- About 20:48:20. SYNC moved a paused deck from 0:00.0 to 0:00.4, off its cue marker, without saying so. fu-half-tempo.png.
- 20:33:40. Remaining time doesn't allow for tempo. Measured at 20:44:22: a track at 87% speed gained 20.0 s on its clock while one at full speed gained 22.9 s. fu-clock-test.png.
- 20:32:26. RELOOP and EXIT overlap during the fade. fu-slicer-overlap.png.
- 20:34:10 onward. The tempo readout on deck 2's JOG page sits under the home indicator (-23.8, -6.0). fu-rev-slip.png, fu-tempo-jump-repro.png. The bottom edge of the SOLO row does too, 20:48:05.
- 20:29:35, 20:48:12. The BPM menu takes about 2 s to appear. fu-bpm-menu.png.
- All session. Toasts cover the deck 1 section label or the list's column heads, and help toasts stay after you've changed tab. fu-brake-drop-done.png, fu-help-mem.png.
- 20:24:00, 20:24:37. Playlist button sat slightly out of line after the menu closed, and a half-drawn blue shape was visible behind the new-playlist dialog. No saved shot catches it clearly, and I couldn't swear it isn't just the animation.
- 20:23:45. Flicking Settings down parked it as a small bar instead of closing it. No shot.
- 20:16:42, 20:50:56. The clock reads "-00:00.0". fu-track-ended.png, fu-end-of-set.png.
- 20:22:40. Help's back chevron and two different close "x"s sit oddly beside the search field. fu-help-page-start.png.
- 20:52:00. A deck kept WIDE on a new track, so an 18-point nudge was +45.1%. fu-wide-fader.png. SLIP also stayed on across tracks from 20:34 to 20:53, visible only on the JOG page.

No crashes, and no state lost after 54 s away in Files (20:44:40-20:45:33): both decks played on and stayed in sync. fu-back-from-background.png.

## 5. Best and worst thing for a newcomer

**Best: the ? button, and the app's habit of explaining itself at the moment it matters.** One short toast sent me to ?, and from there I could touch anything safely and get a straight answer. The same voice carries through to live messages. "That's yours for this move. Auto DJ carries on with the rest." (fu-auto-yours.png) and "You'll hear the cue with SPLIT on and a splitter cable." (fu-headphone-tip.png) both told me what I needed before I'd finished wondering. Watching Auto DJ on both STEMS pages, with knobs turning by themselves and a toast naming the move, is a real lesson in how a transition is built.

**Worst: a single stray touch can change the live mix with no warning and no way back.** MIX throws out the playing track, the overview strip jumps it, BRAKE stops it, the tempo range change above can leap 30 BPM, SAVE CUE sits where IN was. On a screen this dense, with buttons that change meaning by tab and sheets that move under your finger, a newcomer will hit these. I did, repeatedly. Only hot cues had an UNDO.

## 6. What I can't un-know

- **Before I opened the app, my session setup showed me a working folder called "Cheeks" and two cache folders named "cheeks-autodj" and "cheeks-stems".** I didn't open them, but it meant I knew the words "stems" and "autodj" were likely to matter, and that "Cheeks" in the Files picker was probably related. I reported that file name as meaningless, which is true for a newcomer but not quite for me.
- **The brief** gave me the app's bundle name, that this is a folding phone on its outer screen, and that the black strip on the right is normal. A real user might wonder about that strip.
- **I know more about DJing than "roughly what a DJ does".** I recognised the key codes as the Camelot wheel and knew a semitone is 7 steps round it, which is why I could call 1B to 8B "correct". I knew hot cues, loops, slip, quantise and "pull down is faster" from real gear. I did the bass-swap blend at 20:21 before I'd read the app's "Start here", from prior knowledge. A true beginner would be slower at all of this, and more confused by the deck screen, than my times suggest.
- **I knew I was testing.** So I tried brakes, deletes, range changes and repeated taps that a real person wouldn't go looking for, and read help more thoroughly. My 2-minute start on ? is also because the brief told me to use help when I'd want it.
- **The phone wasn't clean.** The picker showed backup files dated 10/30, 11/2, yesterday and 1:53 PM today, and the Segue DJ folder had 2 items before I did anything. The empty library looked first-run, but those files suggest earlier use.
- **The app's name for itself:** "Segue DJ" everywhere I looked (splash, first-screen text, folder, backup files), apart from that one "Cheeks Library" file. For its own parts it says Auto DJ, MIX, stems, BEAT BLOCKS, RECORDINGS.
- **fu-splash.png is misnamed.** I took it too late and it shows the empty library. I did see a splash in my first look at 20:11:41, but it isn't saved.

**What I left behind on the phone:** one recording (Mix 2026-11-04 20.20.11), the playlist "Friday set", History, hot cue A "Before drop" on DJ Karda, SIREN on deck 1's sample pads replaced by "REC 2", my thumbs ratings, SLIP on and range ±6 on deck 2, KEY off and range ±6 on deck 1, both decks stopped at the end of their tracks by the time I finished (DJ Karda and Exhilarate still loaded, MASTER 1). Houston's beat grid is back at 126 after I halved and doubled it. Crossfader curve untouched.

Stopped 20:57:31, 45 minutes 51 seconds after opening.
