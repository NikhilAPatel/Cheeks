# Hands-on results, part 11, 2026-11-04

Commit tested: f264c0a
Device: iPhone Duo simulator, unfolded (951×669 pt; inner screen 2853×2007 px, read before starting), and `iPhone SE Cheeks` (375×667 upright, 667×375 on its side). iOS 27.2. Fresh installs of `com.nikhilpatel.seguedj` on both.
Tooling limits:
- **The Duo's stuck recorder is still running,** from my mistake in round 10: about 118 MB/min, with 91 GB free at 03:19, and about 35% of a core in `SimMetalHost`. A shutdown clears it, and then someone has to press Open in Device Hub. This session has no computer use, and the owner hasn't said they'll press Open, so I haven't shut it down. So **DA is blocked,** and everything timed on the Duo has it running beside it.
- **Beside the measuring:** only DC8 was measured. Beside it were the first-time user on the small iPhone and another project's `xcodebuild archive`. The other session stayed off the CPU. The Mac was 31 to 36% idle by `top`, and `pmset -g therm` recorded no warning.
- **Not judged:** how anything sounds, haptics and the headphone output. Levels and gaps come from the recordings.
- **Tool lag:** a tool call takes 1 to 4 s when chained, so a capsule can be gone before I look. Where it matters I ran a logger that keeps a frame each time the top bar's messages change, about once every 1.5 s.
- **The small iPhone opens on its side** from an upright Home Screen after a fresh install, as it did last round. With the app running, turning the tool right gives upright and left gives its side. I lost one run of DB1 to it and redid it.
- **My own doing on the Duo:** a library snapshot I restored after DD8 points at a Houston file I'd deleted, so it shows a warning triangle there. That isn't the app's fault, and a fresh install clears it. The long run's first 3:29 is nearly silent because a track ran out while I was reading screenshots, so about 11 of its 15 minutes have music on. See **Pressing harder**.
- **The first-time user** was a separate subagent on `iPhone SE Cheeks`, kept away from the repo's docs and code. Its project notes didn't describe `?`, but it had seen the git log line "Add ? to explain any control", and its notes did tell it what `AUTO` and `MIX` are. So its times for finding those aren't evidence that they're easy to find. It says what it couldn't un-know at the top of its report. It also lost about 9 minutes when images dropped out of what it could see. I checked its most serious claims myself, and say which.

## Summary
33 tests: **23 PASS, 4 FAIL, 3 BLOCKED, 3 just reported** (the first-time user's three). **No crashes:** no Cheeks or Segue crash reports.

The two you most wanted confirmed both hold, with my touches, which are the only ones that showed them. **The list keeps its place** on the Duo and on the small iPhone upright: close and reopen, blank parts of the top bar and `?`, including (265,29), which jumped last time. **Nothing moves behind the file picker** on the Duo, with or without the keyboard up, and typing a search still pushes the list up. `?` works well: nothing changed under it with a track playing and a recording running, across 35 controls. It didn't freeze, and costs nothing with it off.

The problems, most important first:
1. **LR3: a move takes `EXIT` back.** During a Loop build, which has just said "Touch a control to take it back", pressing `EXIT` on the old deck lets it run on, and about 16 s later the deck jumps back about 14 s into the loop with no word. 2 of 2, once on each simulator. Found by the first-time user, and repeated by me on the Duo.
2. **DC6: so `AUTO`'s note isn't true for that control,** and "Loop build", "Echo throw" and the thumbs have no note at all. A search for any of them in `What everything does` gives a blank page, with no "no results" line.
3. **DD9: importing tracks already in the library from inside a playlist doesn't add them to it.** New tracks go in. It says "already in your library", and the track stays out.
4. **DC3: on a phone, inside the mixer's sheet, the note covers controls.** Upright it hides part of the `MASTER` knob you touched. On its side it hides `CUE/MST` and `LEVEL` and overlaps `Done`. On the Duo it's clean.
5. **New, small: a search from a scrolled list opens partway down its results,** a side effect of the list keeping its place. And `MIX…` reads as if it's still planning for the whole of the list's last track.

## Failures

### LR3: pressing `EXIT` during a Loop build gets undone with no word
- Steps: Skylander playing, Gepzene loaded and stopped, stems ready, `AUTO`. "Loop build in 5 bars", then "Loop build starting. Touch a control to take it back." When the old deck's `EXIT` lights, press it.
- Expected: the loop's off and stays off, or the move says why not. It's the same family as round 10's CC12, where moving the old deck now hands the decks back and says so.
- Actual, on the Duo:

  | Time | Skylander | Keys |
  |---|---:|---|
  | 03:16:40 | 0:46.9 | `EXIT` and `4` lit, in the score's loop |
  | 03:16:41 | | I press `EXIT` |
  | 03:16:42 to 03:16:56 | Runs on to 1:01.1 | `RELOOP`, as if it took |
  | 03:16:58 | **0:47.9** | `EXIT` and `4` lit again, no message |
  | 03:17:36 | Stopped at 0:46.5 | Move finished. Gepzene on at 0:34.4 |

- The subagent saw the same on the small iPhone on its side, with deck 2 as the old deck: `EXIT` at 00:21, ran on to about 00:29.9, back to 00:17 and looping, no message.
- Lead, from reading and not tested: `Deck.exitLoop` (`Deck+Performance.swift:267`) tells nobody, and `writeLoopDrop` fires each smaller loop at its planned place (`TransitionScore.swift:179`), so the next one takes the deck back there.
- Screenshots: `lr3-exit-undone`, `fu-side-exit-1-loop-running`, `fu-side-exit-2-pressed`, `fu-side-exit-3-undone`, `fu-side-exit-4-move-over`

### DC6: `AUTO`'s note and message aren't true of every control, and Auto DJ's own words have no note
- **Wrong:** `AUTO`'s note and "Loop build starting" both say "Touch a control to take it back". `EXIT` can't be: see LR3. The crossfader, knobs and stems can, as far as I tried.
- **Missing:** "Loop build", "Echo throw" and the thumbs up and down have no note. Searching `What everything does` for "echo throw", "transition" or "thumb" gives an entirely blank page, where the browser's search says "No Results for…". `fu-help-search-empty`, `fu-help-search-thumb`, which I've looked at.
- **Incomplete, the subagent's:** `?` says "touching a control only explains it", and `JOG`, `MIXER`, the tabs and `BROWSE` really act, as DC2 wants, so the note leaves out the exception. "Tap to leave one on" on the FX pads doesn't say three is the most, with no message as one drops, though three is by design (H1). `LIM`'s "turn TRIM down" doesn't say that on a phone `TRIM` is inside `MIXER`. I haven't repeated these. `fu-help-jog-really-swaps`, `fu-fx-only-three`.
- **True when I tried them,** on the Duo: tempo fader (down is faster: +2.06% at 127.57), range key (±6, ±10, ±16, WIDE), jump size (1, 2, 4, 8, 16, 32), `BEAT SYNC` (the fader takes it off), `MASTER` (the press leads, and when it stops the other takes over), `REV`, `KEY SYNC` (11A to 1A at +2 against 1A), the `MASTER` knob (the recording's level didn't change), time going red in the last 30 s, `CUE`, `OUT`, `IN`, the delete notes, and the `LOOP`, `ROLL`, `JUMP` and `FX` pad pages. I read about 130 notes in all, and tried about 25. The list and its search work when there's a match: "slip" finds `SLIP` and `JOG / PADS`. `dc6-search`, `dc6-pad-pages`.

### DD9: known tracks imported from a playlist don't go into it
- Steps: a new playlist, `IMPORT`, `Music files`, choose tracks.
- Expected: "From a playlist, they should appear in it."
- Actual:

  | From | Chosen | Message | In the playlist |
  |---|---|---|---|
  | All Tracks | One new, one known | "Added 1 track. 1 track already in your library." | Not applicable |
  | An empty playlist | Two known | "Those tracks are already in your library." | Nothing |
  | The same playlist | One new, one known | "Added 1 track. 1 track already in your library." | Only the new one |

- The messages are clear, and a new playlist does open. But someone importing into a playlist asked for those tracks to be in it.
- The capsule is also squeezed for about a second beside "Analysing Houston": "Added 1 track. 1 track al…", then whole. 2 of 2.
- Screenshots: `dd9-playlist-new-only`, `lw-import-capsule-squeezed`

### DC3: on a phone, inside the mixer's sheet, the note covers controls
- Steps: `iPhone SE Cheeks`, `?` on, `MIXER`, touch `MASTER`.
- Expected: it never covers what you touched.
- Actual: on its side, the note leaves the `MASTER` knob clear but hides `CUE/MST` and `LEVEL`, and overlaps the bottom of `Done`. Upright, it hides part of the `MASTER` knob, the label reading "MASTI". A second note about the sheet can show at the top of the screen at the same time, and the last note stays up over the waveforms after the sheet closes.
- On the Duo it's clean: touches at x 440 and 475 put the note right of the crease, and 510 and 800 put it left. It never sat across the crease or over what I touched.
- Screenshots: `dc3-se-covers-master`, `dc3-se-b`, `fu-help-text-twice`, `fu-help-mixer-bubble-covers`, `dc3-where-the-note-goes`

## Blocked

### DA1, DA2, DA3: the browser on video, the logo and the launch sweep on the Duo
The Duo hasn't been restarted, so its stuck recorder blocks video there. Round 10's small iPhone results stand: the slide on video had a worst gap of 162 ms, and the launch sweep and logo were fine on 5 of 5.

## Looks wrong

**New this round**
- **A search from a scrolled list opens partway down its results.** Flicked down a 2,005-track list, then typed "Artist 7": 110 matches, with Track 1279 at the top rather than the first. The same with "Track 19" showing Track 1921. The list keeps its place, which is now right, but nothing brings new results to the top. 2 of 2. `lw-search-opens-mid-results`.
- **`MIX…` for the whole of the list's last track,** with nothing queued. It reads as still planning, and nothing says there's nothing after this until it runs out. `lw-mix-last-track`.
- **A waiting deck's tempo visibly swings.** In a mix's countdown, setting a loop put the waiting Skylander back to 125.00 +0.00, and `EXIT` took it to 128.00 +2.40 again, on a stopped deck. It comes out right. `dd12-waiting`, `dd12-replanned`.
- **Stopping the new deck just after the handover** says "Auto DJ stopped: deck 2 was stopped." Both decks stop, as the table says, but the message only names one, and the stopped new deck keeps the move's +2.40%. A new track loaded there does start at its own speed.
- **The hint shows even if you've already pressed `?`.** "New to this?" came after my first load, when I'd used `?` before it. It's once only, and didn't repeat. `dc7-hint`.
- **`SPACE` anticlockwise still takes the top LED red** on 16 of 25 samples on a loud loop, with `LIM` on 4 of them, though it passes DB3. `LIM` also lights with two loud tracks and both faders up, which is what a first mix looks like, and its note says to turn `TRIM` down. `lw-lim-two-decks`, `db3-space-ccw`.

**From the first-time user, checked by me**
- **`RELOOP` with no loop and `DEL` then an empty pad** do nothing and say nothing. `OUT` in the same state explains itself. `fu3-silent-checked`.

**From the first-time user, not repeated by me.** The report's at the end.
- **The first import picker** opens on "Folder is Empty", in the app's own folder, on a fresh small iPhone. On the Duo this round it opened on `On My iPhone`, so it may depend on what it remembers.
- **The crossfader moves by itself,** from hard over to centre, when a countdown begins, with no message. It's been reported three rounds in a row. `fu-auto-waiting-stems`, `fu-auto-countdown`.
- **`AUTO` to call off a Loop build leaves the deck looping,** as the table says it should. But upright that deck may be on its jog page, which has no `EXIT`, and only the shading says so. `fu-auto-loop-before-calloff`, `fu-auto-stopped-yours`.
- **`SYNC` on a lone deck** does nothing and says nothing, with the top bar reading "MASTER 2 —" for an empty deck. `fu-sync-no-other-master2`.
- **`NEXT`:** with 148 leading it gave 126, 128, 125, 170, which doesn't read as "by tempo first". A track on the other deck stays on the list. `fu-next-order`.
- **`AUTO` and `MIX` don't mention each other,** and nothing says `MIX` is the quickest way to an automatic mix.
- **Words with two jobs:** `MASTER`, `KEY`, `CUE`, `OUT`, `FILTER`, `ROLL`, and `SYNC` and `BEAT SYNC` for one control.

## All results
| Test | Result | Notes |
|---|---|---|
| DA1 | BLOCKED | No video on the Duo. |
| DA2 | BLOCKED | The same. |
| DA3 | BLOCKED | The same. |
| DB1 | PASS | Duo, 2,005 tracks, scrolled to Track 1926: `BROWSE`, 3 s, `BROWSE`, then presses at (250,13), (400,13), (700,13) and `?`: it stays. SE upright, Track 1915: the same, with (265,13), (265,29) and `?`. One touch tool on two simulators, so a real finger is untried. `db1-duo-stays`, `db1-se-stays`, `db1-se-question-on`. |
| DB2 | PASS | Duo: nothing moves behind the picker. With "Track 19" typed and the keyboard up: the same, and the keyboard goes as it opens and the search is there when it closes. Typing normally: the mixer stays, and about 2.5 rows show. First keyboard after launching: freezes of 461 and 253 ms. `db2-picker`, `db2-picker-keyboard`, `db2-keyboard`. |
| DB3 | PASS | `SPACE` anticlockwise 4 of 37, against 9 of 17. `DUB` and `NOISE` 0 of 82. See below. `db3-dry`, `db3-space-ccw`. |
| DB4 | PASS | On its side: "Skylander", "Exhilarate" and "Houston" whole, "Severe / Tire Dam…" and "Gepzene - / Can't be…". *Last time: "Skyl / an…".* `db4-side-titles`, `dd10-capsule-side`, `fu-side-exit-1-loop-running`. |
| DB5 | PASS | By hand: +2.06%, load Exhilarate, reads 170.00 +0.00 at once. After a move: Skylander as the old deck went from +2.40 to +0.00, 125.00. `db5-by-hand`, `db5-after-move`. |
| DC1 | PASS | Duo, with a track playing and a recording: see below. `dc1-notes-a`, `dc1-notes-b`, `dc1-notes-c`. |
| DC2 | PASS | `BROWSE`, the tabs, and on the phone `MORE >`, `JOG` and `MIXER` still work and say what they are. A load key explains and loads nothing. `dc2-browser-note`. |
| DC3 | FAIL | On a phone, in the mixer's sheet. Clean on the Duo. |
| DC4 | PASS | On an empty deck `PLAY`, a pad and the jog explain themselves. `dc4-empty-deck-note`. |
| DC5 | PASS | `?` off: `REC` asks as normal. On, Home, back: it's off. |
| DC6 | FAIL | `AUTO`'s note, and what has no note. |
| DC7 | PASS | "New to this? Press ? and tap anything to see what it does." On the first load only, on the Duo and the SE. |
| DC8 | PASS | Five toggles with both decks playing: no freeze of 100 ms or more. CPU 20.2% off, 20.6% on, 20.1% off. |
| DD1 | PASS | Stop a move, then the old deck: "Deck 2 is on." at once, in full colour, `MASTER` moved. On the recording: -22 dB, one tenth of a second at -73, then -13 dB. *Last time: 7.96 s of silence.* `dd1-before`, `dd1-new-deck-comes-in`. |
| DD2 | PASS | "Press IN first, to mark where the loop starts." "A loop needs some length: play on from IN, then press OUT." Both with a hand. `IN`, 3 s, `OUT`: a 6-beat loop. `OUT` in a running loop shortened it to 5. `dd2-messages`. |
| DD3 | PASS | Four presses at 4.5 s: it stays up, and goes about 5 s after the last. `dd3-capsule-stays`. |
| DD4 | PASS | All dim. `dd4-empty-deck`, `dd4-empty-stems`. |
| DD5 | PASS | `AUTO 10%`, 15%, 20%. `MIX 8%`, 14%. "Loop build starting. Touch a control to take it back." `dd5-auto-percent`, `dd5-mix-percent`. |
| DD6 | PASS | Setting off: "Auto DJ is waiting for the stems to finish.", `AUTO 1%`, `Stems 1%`. Already split: "Loop build in 16 bars." at once. `dd6-stems-off`, `dd6-already-split`. |
| DD7 | PASS | "A mix carries on from one playing deck. Stop the other." `dd7-dd8-messages`. |
| DD8 | PASS | "Delete Houston? This removes its file from Segue DJ, along with its cues, loops and stems." On a playing track: "Deck 1 is playing this. Stop it first." `dd8-delete-asks`, `dd8-delete-refused`. |
| DD9 | FAIL | Known tracks stay out of the playlist. New ones go in, the messages are clear, and a new playlist opens. |
| DD10 | PASS | On its side it hangs below the bar, whole, and goes properly. It covers deck 1's section label while it's up. `dd10-capsule-side`. |
| DD11 | PASS | "You'll hear the cue with SPLIT on and a splitter cable." |
| DD12 | PASS | `MIX 59`, a real loop, "The mix will carry on when deck 1's loop ends.", `MIX…`. `EXIT`: `MIX 51`, then "Echo throw into Skylander." |
| FU1 | Reported | Nothing to a mix in 1:33 upright. See the end. |
| FU2 | Reported | It found `?` from the hint. See the end. |
| FU3 | Reported | See the end. |
| Pressing harder | PASS | 14:58, about 11 minutes of it with music on, no crash, no dropout, and the decks stayed usable. See below. `lr-question-in-countdown`. |
| LR3 | FAIL | Found by the first-time user: `EXIT` in a Loop build. |

### DC1: what I touched with `?` lit
On the Duo, with Skylander playing and a recording running from 02:35:01. SLIP, PLAY, a hot cue pad, a drag on `LOW`, a drag on the tempo fader, the jog, the waveform, the overview, the strip of blocks, `LIM`, the meters, `BEAT SYNC`, `MASTER`, the jump size, `Q`, `KEY`, `REV`, `KEY SYNC`, `−`, the range key, the `MASTER` knob, `CUE/MST`, `SPLIT`, the `FILTER` key, `AUTO`, the headphone `CUE`, the crossfader, a stem pad, a `SOLO` pad, `ACAPELLA`, an FX pad, `DEPTH`, a sampler pad, `REC`, and the gear.

Each said what it was. Nothing changed: the deck ran on, the knob and the fader didn't move, no pad fired, and no settings opened. The recording of it is 219 s with no run of 30 ms or more under -50 dB until the last half second, which is the track's own end. `library.json` shows no cues, memory cues or loops afterwards.

### DB3: the spot samples
Skylander, a 16-beat loop on its loud part at 4:03. The method's the same as last round's, at about 1 sample a second or better.

| State | `LIM` lit | Top LED red | Last time |
|---|---:|---:|---|
| Centred | 0 of 23 | 0 of 23 | 0 of 11, and 1 of 8 elsewhere |
| `SPACE` anticlockwise, looped | **4 of 25** | 16 of 25 | 3 of 9 |
| `SPACE` anticlockwise, from 3:55 unlooped | 0 of 12 | 2 of 12 | 6 of 8 |
| `SPACE` clockwise | 0 of 25 | 2 of 25 | 0 of 9 |
| `NOISE` clockwise | 0 of 27 | 0 of 27 | 0 of 14 |
| `NOISE` anticlockwise | 0 of 19 | 0 of 19 | 0 of 21 |
| `DUB` anticlockwise | 0 of 19 | 0 of 19 | 0 of 17 |
| `DUB` clockwise | 0 of 17 | 0 of 17 | 0 of 13 |

`DUB` and `NOISE` are clean. `SPACE` anticlockwise is 4 of 37 across both, against 9 of 17 last time. The top LED is still red on 16 of 25 on the loop, so it's better and not gone. Levels only: nobody can judge here how it sounds.

### Pressing harder
02:49:24 to 03:04:22, so 14:58, with a recording throughout, on the Duo.

| Time | What I did | What it did |
|---|---|---|
| 02:49:31 | `AUTO` on a deck 9 s from its end, and again after it had run out | "Play a track first, then Auto DJ can mix out of it." Fair: my own set-up, as a press of `CUE` had moved the cue near the end |
| 02:53:14 | `AUTO`, pressed again as the new deck started, then stopped the old deck | DD1: "Auto DJ stopped. The decks are yours.", then "Deck 2 is on." |
| 02:54:48 | `AUTO`, with `?` on in its countdown, touching `PLAY` and `AUTO` | Notes only, and the move played on. "Loop build starting. Touch a control to take it back.", "Loop build done. Deck 1 is on." The old deck back to +0.00 |
| 02:56:23 | `MIX`, then `IN`, `OUT`, `OUT` again, `EXIT` in its countdown | DD12: "The mix will carry on when deck 1's loop ends", `MIX…`, then `MIX 51`, and "Echo throw into Skylander." at 02:58:38 |
| 02:57:20 | Settings and its list and search, in the countdown | Nothing disturbed |
| 02:58:09 | The `MASTER` knob down and back | The recording's level didn't change, as the note says |
| 02:58:52 | `?` on during the Echo throw, touching `MID` | Note only. "Echo throw done. Deck 2 is on." |
| 02:59:25 | Home for 12 s | Back with the deck running and the recording on |
| 03:00:28 | `MIX` off | "Mix off. The track playing just carries on." |
| 03:01:11 | `AUTO` with "Prepare stems on load" off, then off again, then on a split track | DD6 |
| 03:02:23 | Crossfader dragged to the old deck's side during a Loop build | The move finished, and the crossfader stayed. Nothing to hear from the new deck until I moved it back, as decided in round 9 |
| 03:03:06 | Stopped the new deck 2 s into an Echo throw | "Auto DJ stopped: deck 2 was stopped." Both stopped, which is the table's "after", though the message only names deck 2 |
| 03:03:32 | `?` on and off four times | Nothing |

- **Gaps:** 108 runs of 30 ms or more under -50 dB in 898 s.

  | Where | Runs | Longest |
  |---|---:|---|
  | Before the first `PLAY` | 1 | 4.17 s |
  | Gepzene ran out and stopped, my doing, twice | 2 | 88.84 s and 105.64 s |
  | Crossfader at the stopped deck's side, my doing | 1 | 27.11 s |
  | Both stopped, my doing | 1 | 13.82 s |
  | Gepzene on its own | The rest | 0.33 s |

  Gepzene's fall into the same pattern each time it plays, as they did last round, so I read them as its own. Skylander has none. I didn't compare them with its file this time, so a very short dropout on a track this sparse could hide. There was no Bass swap in this recording, so no deliberate beat of silence.
- **The tracklist:** 5 lines, matching each change of track.
- **Afterwards:** deck 1's `PLAY` and clock work, with no loop, the knobs centred and every stem on. Nothing's silent, looping or filtered that the screen doesn't show.
- **The freeze log:** 36 freezes of 100 ms or more since that launch, 20 minutes earlier. I only kept the last 8 before a later relaunch overwrote the log, so I can't place the other 28. By their times, those 8 fall on Settings and its list opening, its first search keyboard (431 and 504 ms), Home (1,469 ms) and Settings again. None of them is on a `?` press.
- **The app's log:** no crash report.

## Timings and measurements
CPU by `top` on this simulator's own process, 30 s after settling, stems finished, both decks playing and synced with an offset. Only DC8 was measured this round: last round's table stands for the rest. Beside it: the Duo's stuck recorder, the first-time user on the small iPhone, and another project's `xcodebuild archive`.

| State | Average | Peak | Memory | Mac idle |
|---|---:|---:|---:|---:|
| `?` off, before | 20.2% | 20.9% | 505 MB | 31% |
| `?` on | 20.6% | 21.5% | 506 MB | 34% |
| `?` off, after | 20.1% | 21.3% | 505 MB | 36% |

- Round 10 had 18.6% for the same state, with different things beside it, so I wouldn't read anything into the 2 points.
- **At the end of the long run,** about 19 minutes after that launch, the app's log read 12 to 13% of a core and 533 MB, with one deck playing and a recording running.
- **Press to plan:** about 2 to 6 s, as before.

## First impressions
**1. Does it look like $1000 pro software?** On the wide layout, yes, and `?` adds to that: a key that makes everything answer for itself, with the music running on, feels like more care than most pro tools take. What most breaks the illusion:
- **A move that takes back what you did.** You press `EXIT`, it works, and 16 s later the track's somewhere else with no word. It's the only time this round the app felt like it wasn't listening.
- **Words the app uses and can't explain.** It announces an "Echo throw" and then searching for it gives a blank page.
- **The phone's mixer sheet:** five small controls at the top of an otherwise black page, with a note over some of them.

**2. What felt slow, confusing or surprising?**
- **Slow:** only the stems, about 3 to 4 minutes a track here on the CPU. `AUTO 42%` makes the wait much easier to read.
- **Confusing:** `AUTO` and `MIX` being two doors to one thing. The crossfader moving by itself. A search opening partway down its results. `MIX…` on the last track.
- **Surprising, in a good way:** how much the first-time user got done, from nothing to a mix in 1:33 on the smallest screen, though it knew general DJ words going in. Stopping a move and then the old deck, which now just brings the new one in. And the list staying put, which makes 2,000 tracks feel usable.

**3. Which control was hardest to find or hit?** To find: `MIX`, since nothing says it's the quickest way to an automatic mix. To hit: the crossfader on a phone's side, about 115 pt of travel against about 335 upright. `DEL` is still tight, at the end of the tab row.

## The first-time user: the subagent's full report
Written by the subagent on `iPhone SE Cheeks`, from 02:30 to 03:11, with its own caveats first. Its screenshots are the `fu-*` files, given as `[short-name]`.

#### What I couldn't un-know

Project notes were loaded into my context before I started. I didn't open anything in the repo, but these stuck.

**About how the app explains itself**
- The git log line "Add ? to explain any control" told me a `?` exists before I saw it.
- The notes say an empty deck's controls are dim and a press says why, that refusals show a hand and successes a green tick, that `PLAY` says why it can't start from the start while in reverse, and that the capsule is a short-lived message.
- They do not describe the `?` mode or the "What everything does" list. I found that list from the app.

**About Auto DJ**
- `AUTO` needs stems and a stopped second deck.
- It counts down in bars and shows % while waiting.
- `MIX` in the browser is Auto DJ through the list on screen.
- There's a rating question in the capsule, and an echo-out fallback.
- A control the move is using belongs to whoever touched it last.

**About layout and behaviour**
- `JOG` swaps pads for the jog upright, and `MIXER` holds what doesn't fit.
- The browser and decks take turns, so `BROWSE` goes back.
- `NEXT` sorts by tempo, then key.
- Other rules I went in knowing: a loop holds a deck back, a deck that's run out restarts from its cue, a playing deck refuses a load.
- They also cover much I never used in my choices: how slip, rolls and slices return, loops waiting up ahead (`ARMED`), that the browser remembers its sort and filters, what the meters and `LIM` read, stems taking minutes on the CPU, that every Auto DJ plan is rendered and checked first, and audio engine internals.

**Which choices it affected**
- **Finding `AUTO`, `MIX` and `?`:** I pressed `AUTO` first time, and went to `MIX` knowing it was Auto DJ, so those "finding" times (18 s, 4 min) are not naive. A real newcomer might never link `MIX` to Auto DJ, because nothing on screen says so. The "New to this?" hint would have sent me to `?` anyway, but I can't prove that.
- **Back from the browser:** pressing `BROWSE` to return (12 s) was helped by the notes.
- **Which wrong things I tried:** many were chosen because the notes named them (REV at the start, a load on a playing deck, AUTO with both playing). The ones the notes don't mention gave the worst results: `RELOOP` with no loop, `SYNC` on a lone deck, an empty pad under `DEL`, six effects in a row, and `EXIT` during a move.
- **General DJ vocabulary:** I also know BPM, SYNC, cue and stems from general knowledge. So I understate how foreign those words are to someone new.

#### Tooling limits that affect this report

- No sound and no haptics. Nothing here says how anything sounds, including whether the second track was really in time. I can only say both decks read the same BPM.
- A tool call took 1 to 5 s, so short messages may have vanished unseen. Where I saw no message I say "none seen". The clearest gap: I never saw the "done" message at the end of the side-on move.
- Partway through, images fell out of what I could see and I re-read them from disk, so about 02:43 to 02:52 went on that. That's why both tracks ran out with nothing happening. Some notes were written minutes after the event from saved shots. The clock times are real.
- I closed the app three times with `simctl terminate` to get empty decks. None of those was a crash.
- **Crashes:** none. The `ls -t ~/Library/Logs/DiagnosticReports | grep -iE "cheeks|segue" | head -1` check came back empty.

---

### FU1: from nothing to a mix

#### Upright

| Stage | Clock | Took | Unsure? |
|---|---|---|---|
| Open app from the icon | 02:30:46 to 02:30:50 | 4 s | No |
| Find how to add music | to 02:31:07 | 17 s | Text says "the blue button above". It's an icon with no word, but it's the only blue thing. A menu then asks `Music files...` or `DJ library (XML)...`. |
| Find the music in the picker | to 02:31:19 | 12 s | Picker opens in the app's own empty folder ("Folder is Empty"). Back took me straight to My Music, so this is flattered by the picker's memory. Tapping a file ticks it rather than opening it. |
| Import | to about 02:31:25 | 6 s | BPM column shows dots at first. |
| Get a track on a deck | to 02:31:29 | 4 s | The `1` and `2` buttons are obvious. **The browser stays open after a load**, with nothing saying where the deck went. |
| Back to the decks | to 02:31:41 | 12 s | No back button, and a large empty area under the list. `BROWSE` is lit, and pressing it again is the only way. |
| Playing | 02:31:45 | 4 s | No. |
| Second track on deck 2 | to 02:31:55 | 10 s | Same browse and back again. |
| In time | to about 02:32:05 | 10 s | `SYNC` is small, beside the track name. My first tap landed on the name and nothing happened. It lit, and deck 2 went from 128 to 126. |
| Deck 2 playing | 02:32:11 | 6 s | Wasn't sure whether to press PLAY first or SYNC first. Both worked. |
| Mixed across | 02:32:19 | 8 s | The crossfader is big and clear upright. |
| **Nothing to a mix** | | **1 min 33 s** | |
| Press `AUTO` (refused) | 02:32:37 | 18 s | Both decks were playing. |
| Stop deck 1, press `AUTO` again | 02:32:44 | 7 s | Accepted, but `AUTO 35%` means a wait. |
| Stems finish | about 02:35:05 | 2 min 20 s | Deck headers count down ("Stems 54% · 1 min"). |
| Countdown to end of move | 02:35:13 to 02:36:00 | 47 s | |
| **First `AUTO` press to finished move** | | **3 min 23 s** | |
| Find `MIX` in the browser and press it | 02:36:47 | | Stems for the next track took until about 02:39:30. |
| Mix's move starts | 02:39:49 | 3 min | With about 24 s left on the old track. |

#### On its side

| Stage | Clock | Took |
|---|---|---|
| Start, both decks empty | 02:55:06 | |
| Tap "No track loaded", browser opens (a good shortcut, which I only knew from `?`) | 02:55:11 | 5 s |
| Load both decks | 02:55:17 | 6 s |
| Back to decks, deck 1 playing | 02:55:21 | 4 s |
| SYNC, PLAY and crossfade on deck 2 | 02:55:31 | 10 s |
| Stop deck 1, `AUTO` | 02:55:38 | 7 s |
| Countdown starts at once (stems kept from earlier) | 02:55:38 | 0 s |
| Move finished by | 02:56:39 | about 1 min, with my interference |

**Different on its side**
- **Easier:** browser keys have words (`IN KEY`, `±6% BPM`, `IMPORT`) and the playlists column is always there. Upright they're `KEY`, `±6%` and two bare icons. Both jogs fit at once with room to spare [side-two-jogs].
- **Harder:**
  - The crossfader is short, about 115 pt of travel against about 335 upright, and easy to overshoot.
  - Titles get cut to two lines ("Gepzene - Can't be...").
  - The keyboard leaves under 100 pt for search results.
  - The capsule covers deck 1's section label.
- **Rotating with both decks playing:** nothing stopped. Each layout keeps its own page, so a deck on the jog side-on came back on its pads upright.

#### Every message I saw, word for word

**Getting started**
- "No music yet" / "Tap the blue button above to add music from Files, or drop audio into the Segue DJ folder in the Files app or Finder." [first-open]
- "Added 5 tracks." with a green tick [added-tracks]
- "New to this? Press ? and tap anything to see what it does." It appears over the filter row, after the first load, and not on the decks. I saw it once and never again [new-to-this].

**Auto DJ**
- "Auto DJ brings in a stopped deck. Stop the one you want next." [auto-both-playing]
- "Auto DJ is waiting for the stems to finish." [auto-waiting-stems]
- "Loop build in 5 bars." and "Loop build in 4 bars." and "Loop build in 10 bars." [auto-countdown]
- "Loop build starting. Touch a control to take it back." [auto-take-it-back]
- "Loop build done. Deck 1 is on." with a thumbs up and a thumbs down [auto-done-thumbs]
- "Echo throw in 10 bars." and "Echo throw done. Deck 2 is on."
- "Got it. Less like that." after thumbs down [thumbs-down-reply]
- "Auto DJ stopped. The decks are yours." [auto-stopped-yours]
- "Load the next track on the other deck first." [auto-one-deck]
- "Play a track first, then Auto DJ can mix out of it."

**Mix**
- "Up next: Severe Tire Damage - High Quality."
- "Echo throw into Severe Tire Damage - High Quality." [mix-echo-throw]
- "Mix off. The track playing just carries on." [mix-off-stems-gone]
- "Mix off: the track changed." [mix-load-other]
- "A mix needs at least two tracks." [mix-empty-list]

**Refusals and everything else**
- "There's no track on deck 1 yet. Load one from the browser."
- "Deck 1 is playing. Stop it first." and "Deck 2 is playing. Stop it first."
- "Press IN first, to mark where the loop starts."
- "Deck 1 is at the start. Turn REV off to play it forward." [rev-at-start]
- "Echo out on deck 2. Press OUT again to bring it back." [fx-out-message]
- "Deleted hot cue A" with UNDO
- "Stop recording?" / "Stop and save" / "Keep recording", then "Saving your mix..."
- No Results for "zzzz" / "Check the spelling or try a new search."

#### What I saw with Auto DJ and Mix

- **The route to the first move has three gates, met one at a time.** Load two tracks, stop one, wait for stems. Each is explained only after you hit it. Stopping a deck to get Auto DJ going is odd if you have both up: the message asks you to cut one off first.
- **The crossfader moved by itself.** I had it hard over to deck 2. It stayed there while `AUTO` waited [auto-waiting-stems], then sat at centre by "Loop build in 5 bars." with no message [auto-countdown]. *Guess:* the plan takes the crossfader when the countdown begins.
- **Words nobody told me.** "Loop build" and "Echo throw" arrive with no explanation (see FU2).
- **`MIX` is the fastest way to a mix, and nothing says so.** With both decks empty, `MIX` in the browser loaded Houston, started it, and loaded the next track, with no other step. Going through `AUTO` takes at least five taps (two loads, `BROWSE`, `PLAY`, `AUTO`). Both then wait for stems. The `MIX` label doesn't mention Auto DJ, and neither does its explanation.
- **`AUTO` left a deck where it wanted, not where I'd left it.** Houston was stopped at 02:09 [auto-stopped-yours]. The next move brought it in at about 00:31 [thumbs-down-reply], with no word about it. *Guess:* it chooses its own entry point. I didn't test whether a cue I'd set would be kept.
- **It accepts the same track on both decks.** "Loop build in 10 bars." with Houston on both [same-track-both-decks]. No refusal.
- **`AUTO` is quick to act.** Pressed with deck 2 at 00:10, it looped at 00:21 and stopped that deck by 00:17 [side-exit-4-move-over]. *Guess:* that's intended, since I pressed it, but a newcomer might expect it to wait for the end of the track.
- **`MIX` waited well.** It held back until about 24 s from the end of Houston, then moved [mix-echo-throw].

---

### FU2: controls I didn't understand, and finding out

#### How I went about it

**What I tried first:** I pressed `?`, because the hint had told me to. It's a key in the top bar, there on the decks and in the browser.
- Time to help: 2 min 25 s after opening. I saw the hint at 45 s and pressed it 1 min 40 s later, once I had a list of things to ask.
- Nothing in the first screens points at it except that one hint.
- Second source: the Settings explanation ends "and a list of all these notes". That led me to **"What everything does"**, a searchable list in Settings [help-list-page], at about 9 minutes. Its search for "ech" gives five useful results [help-search-ech], but see below for its gaps.

**What I couldn't work out by looking** (before any help):
- Top bar: the waveform icon beside `REC`.
- Mixer: the two headphone keys, `MIXER`, `LIM`.
- Deck: `‹ 4 ›`, `RELOOP`, `DEL`, `MORE >`, `SYNC` beside `JOG`.
- Waveforms: the strip of tiny blocks between them, the coloured strips along them, and the numbers in "CHORUS 30.1".
- Browser: `KEY`, `±6%`, `NEXT`, `MIX`, the sidebar icon and the key column (5A, 12B, sometimes on a coloured chip).
- Jog page: `Q`, `SLIP`, `KEY`, `REV`, `KEY SYNC`, `− ±0 +`, `±10`, `MASTER`.
- Stems page: `VOX`, `INST`, `BEAT`, `ALL`, "AI" with a dot.
- FX page: `V I B D`, `OUT`, `DEPTH`.
- Messages: "Stems 8% · 2 min", and thumbs up and down.

#### Which explanations helped

**Clear, and true when I tried them:**
- **Tempo fader**, including "Down is faster": I dragged it down and got +7.0 and 158.29.
- **`BEAT SYNC`**, including "Moving the tempo fader takes it off": it did. It also silently moved the range from ±10 to ±16, which the note doesn't mention.
- **`KEY SYNC`:** moved −1 to 10A beside the leading deck's 11A.
- **Big `CUE`:** goes back to the mark and stops.
- **`REV`.**
- **Stem pads:** a tap mutes, a slide sets a level, `SOLO` comes back to what you had including my mute and level [not separately shot].
- **`DEL`:** "You get an Undo": yes.
- **Hot cue pad.**
- **`RELOOP`/`EXIT`/`ARMED`** in one note.
- **FX `OUT`.**
- **`BPM` menu:** "double or halve the BPM, shift the grid, or set where the 1 is" [bpm-menu]. "Grid" and "downbeat" are still jargon.

**Clear, and I didn't try them:** jog wheel, waveform, overview, beat blocks, `KEY` column, `SPLIT`, `Q`, `SLIP`, the FX pads, `V I B D`, sampler pads.

**Didn't help much:**
- **`AUTO`:** "A number means bars to go, a % the stems. Touch a control to take it back, or press AUTO to call it off." It's true in part (see below), and dense. "Take it back" reads like "undo".
- **`LIM`:** "If it stays on, turn TRIM down." `TRIM` isn't on the screen. It's inside `MIXER`, and the note doesn't say so.
- **Stem status:** "AI with a green dot means it's ready. ≈EQ is a rougher split..." I was looking at a % and a bar, not either of those.
- **`MIXER`:** "The mixer controls with no room here": tells you what's there, not why you'd go.
- **`FILTER ↻`:** lists `DUB`, `SPACE`, `NOISE`, `CRUSH`, `PITCH` with barely a word about each.
- **`KEY` column:** "Numbers next to each other, or the same number, go together." It doesn't say what the letter means.

#### Explanations that turned out wrong

- **`?` itself: "touching a control only explains it".** `JOG`/`PADS` really swaps the deck's page [help-jog-really-swaps]. `MIXER` really opens the sheet. Tabs and `MORE >` really change the page. The music doesn't change, and seeing the page is sometimes useful, but it isn't "only explains", and the deck stays swapped when you leave `?`.
- **`AUTO`: "Touch a control to take it back".** I pressed `EXIT` during a Loop build, and the loop key changed to `RELOOP` while the track ran on from 00:21 to 00:29.9 [side-exit-1-loop-running, side-exit-2-pressed]. By 02:56:13 the track had jumped back to 00:17 and was looping again, `EXIT` lit, with no message [side-exit-3-undone]. It then stopped the deck at 00:17 as planned [side-exit-4-move-over]. So that control couldn't be taken back. The crossfader could: moved during a countdown, it stayed where I put it.
- **`AUTO`: "press AUTO to call it off".** It does, but during a Loop build deck 2 kept looping. Before the call-off it was in a 4-bar loop at 00:52.5 [auto-loop-before-calloff]. "Auto DJ stopped. The decks are yours." showed 00:54.2 with the shading still there [auto-stopped-yours], and five seconds later the track read 00:52.2. That deck was on its jog page, which has no `EXIT`, so nothing says you're still in a loop except the shading.
- **FX pads: "Tap to leave one on".** I tapped six in a row. Only the last three stayed lit, `REVERB`, `FLANGER` and `PHASER` [fx-only-three]. Nothing says there's a limit, and no message when one drops.
- **`NEXT`: "by tempo first, and then key... The track on the deck drops off the list".** With 148 leading, it gave Houston 126, Gepzene 128, Skylander 125, Exhilarate 170 [next-order]. 128 is nearest but came second. And Exhilarate is on deck 1 and stayed on the list; only the leading deck's track went. I couldn't predict that order from the note.
- **`REC`: "Press it again to stop and save".** It asks first, "Stop recording?" (minor, and I think the question is right).
- **`MIX`: "loading each track onto the stopped deck".** With nothing playing, it also starts the first one. Not said (minor).

#### The `?` mode itself

- Bubbles sit over things you may want to read next. With the mixer open, the same text shows **twice at once**, at the top of the screen and in the sheet, and the bubble hides the `MASTER` knob it's describing and part of `FILTER`, and clips `Done` [help-text-twice, help-mixer-bubble-covers].
- Side-on the bubble butts against `Done`. My first tap, low on the word, hit the bubble and did nothing [side-help-covers-done].
- In the browser, the intro bubble covers the filter row and the first track for as long as it's up [help-bubble-over-browser]. Touches do go through it, so I tapped keys I couldn't see.
- A bubble stays after you close the sheet it was about, over the waveforms.

#### "What everything does"

- It's good once you find it: grouped by area, with search.
- **No result shows a blank page, with no words at all** [help-search-empty, help-search-thumb]. The browser's own search says "No Results for...". I took the blank for a fault.
- Blank for "echo throw", "transition" and "thumb". So the app's own words have no entry.
- Searching "mix" leads with `REC`, `RECORDINGS` and the sample pads. Searching "auto" returns only `AUTO`.

#### Still a mystery after all of that

- **"Loop build" and "Echo throw":** the names of what Auto DJ does. No entry anywhere I could find.
- **Thumbs up and down:** no entry. "Got it. Less like that." doesn't say less like what.
- **`AUTO` vs `MIX`:** neither entry mentions the other, or the phrase "Auto DJ" for `MIX`. I only knew from the notes.
- **Words used twice or more, each meaning something different:**
  - `MASTER`: the leading deck in the top bar and on the jog page, and the volume knob in the mixer.
  - `KEY`: the filter in the browser, the column, and key lock on the jog page.
  - `CUE`: the big button, a pads tab, and the note on the headphone key.
  - `OUT`: closing a loop, and ending a track on its echo.
  - `FILTER`: the knob, the key that changes it, and an FX pad.
  - `ROLL`: a pads tab and an FX pad.
  - `SYNC` and `BEAT SYNC` are the same control with two names.
  - The notes do separate them, but you have to already know which one you've got.
- **`MORE >`:** cycles one page a tap (`MEM`, `SLICER`, `JUMP`, `SAMPLE`), with no way to see the list first.
- **Waveform colours, the small orange triangle, the disc going red:** nothing I found explains them. I don't know if an entry exists, since I didn't read the whole list.
- **"Echo out" and "Echo throw":** are they the same? Different messages use each.

---

### FU3: doing it wrong

#### Refused clearly, with a reason

| What I did | What came back |
|---|---|
| PLAY, CUE, SYNC, IN or a pad on an empty deck | "There's no track on deck 1 yet. Load one from the browser." Clear. The app's button says `BROWSE`, not browser, which is small. |
| ROLL pad on an empty deck | Same. |
| AUTO with both decks empty | "Play a track first, then Auto DJ can mix out of it." |
| AUTO with one deck loaded and playing | "Load the next track on the other deck first." [auto-one-deck] |
| AUTO with both loaded, both stopped | "Play a track first..." |
| AUTO with both playing | "Auto DJ brings in a stopped deck. Stop the one you want next." The instruction works, but it's a strange thing to be asked. |
| `OUT` with no `IN` | "Press IN first, to mark where the loop starts." |
| Load on a playing deck | "Deck 1 is playing. Stop it first." The `1` is also dimmed. The capsule covers `KEY`, `±6%` and `NEXT` in the browser while it's up. |
| `MIX` with an empty list | "A mix needs at least two tracks." True, though the sidebar says 5 [mix-empty-list]. |
| PLAY with `REV` on at the start | "Deck 1 is at the start. Turn REV off to play it forward." The best message in the app [rev-at-start]. |
| Search for nothing in the browser | "No Results..." Fine. |

#### Silently ignored

- **`RELOOP` with no loop:** no message, nothing changes. Tested three times, once right after `IN` [reloop-silent, reloop-silent-2, reloop-after-in-silent]. (`OUT` in the same state explains itself, so this one stands out.)
- **`SYNC` on a lone deck:** nothing lights, no message, twice in a row. The top bar read "MASTER 2 —", naming an empty deck, while Houston sat loaded and stopped on deck 1 [sync-no-other-master2]. I don't know whether the press or the load moved it.
- **`DEL`, then an empty pad:** `DEL` goes out, no message [del-empty-silent].
- **A dim `IN KEY` or `±6% BPM` with nothing playing:** nothing happens. It's dim, so it's fair, but it gives no reason where dim deck controls do.
- **Fourth, fifth, sixth effect:** older ones drop off silently (see FU2) [fx-only-three].
- **`EXIT` during a Loop build:** looks accepted, then undone later (see FU2).

#### Accepted without a word, which may be fine

- `SYNC` on a stopped deck: 170 jumps to 148 [sync-stopped-deck].
- `IN` pressed twice: stays lit, no message.
- `IN` then `OUT` by hand: a 13-beat loop, and the box reads 13 [loop-13]. Not wrong, just surprising next to the 1, 2, 4, 8 it offers.
- Two loads in a row on a stopped deck: last wins, and the track on it goes without asking.
- `NEXT` with both decks empty: reorders the list by no visible reference.
- `REC`: starts at once with no question, and a 5-second test saved as "Mix 2026-11-04 02.54.45". I had music playing, so I didn't test recording with nothing playing.
- `PLAY` on a track that's run out: restarts it from the start.

#### Mid-mix

- **Loading another track on the waiting deck during `MIX`:** "Mix off: the track changed." No warning first and no undo, and it fades fast [mix-load-other].
- **Pressing the deck's `AUTO` key while it reads `MIX 40%`:** "Mix off. The track playing just carries on." Clear. But Exhilarate's "Stems 40%" line had gone from the header too, with nothing said [mix-off-stems-gone]. I don't know whether its split stopped or carried on hidden.
- **Crossfader moved during a countdown:** kept. The move finished with deck 2 on and my crossfader still over on deck 1's side. The master meters sat at half [side-after-move-xfade-left], and hard over they read nothing with deck 2 at full [side-xfade-full-left-silent]. Nothing warned me. I'd moved it myself, so that's arguable, but the app had just said a deck "is on".

#### During a load

I couldn't get a press inside a load: my quickest was load, `BROWSE`, `PLAY` in about 3 s, and the deck simply played. Both orientations. That doesn't show what a real press during a load does.

---

### Things that merely looked wrong

- The first section of Houston reads `CHORUS 1.1` at 00:00, and counts up past 35 bars. Severe Tire reaches `CHORUS 91`. I can't check by ear, but one chorus for most of a track looks unlikely.
- Meters showed green to half with red tips about 2 s after launch, with both decks empty. Gone in the next shot. *Guess:* a launch sweep.
- `LIM` showed lit in shots with both decks at full and the crossfader centred, which is what a first mix looks like.
- The waiting deck's waveform goes almost black during a move [side-exit-1-loop-running], with no explanation. It's a nice signal once you know.
- `DEPTH`'s bar grew by itself when `OUT` went on [fx-only-three, fx-out-message].
- `AUTO…` while it plans [auto-planning-dots]: three dots and no message.
- The capsule often covers the section label on deck 1, and other controls in the browser.

### What I didn't get to

`SLIP`, scratching and the jog ring, `ROLL` and `SLICER` in use, the sampler and `SET`, playlists, DJ library import, sharing a recording, the FILTER knob's other effects, headphone routing and `SPLIT`, halving a running loop, reading the whole "What everything does" list, or whether a rating changes what Auto DJ does later. I also never saw the "done" message at the end of the side-on move. The Duo and other screen sizes weren't part of this run.
