# Hands-on results, part 14, 2026-11-04

Commit tested: f20dbe9

Device:
- **iPhone SE Cheeks** (667×375 on its side): the first-time user, the long run, and the slide's phone checks.
- **iPhone Duo, unfolded** (951×669), until 13:00. **Folded** (466×678, the upright phone layout) after that, because the disk rule made me shut it down.
- **iPad Air 13-inch (M4)**: video only, using `CHEEKS_SELF_TOUR=browser`.

Tooling limits:
- I can't hear anything or feel haptics. "Worked" means what the keys, numbers, waveforms and meters did, and what the recordings measure.
- **Touch access to the iPad was never granted.** I asked twice and nobody was there to answer. With the Duo folded, that left me no full layout to press on after 13:00. So the slide's video is on the iPad, and **pressing during the full layout's slide wasn't tested**. That's the case this round's slide change affects most.
- A tool press lands about 0.8 s after the one before. To land inside a slide I froze the app with SIGSTOP, sent both presses, then let it go, as in round 13.
- Video can only be read frame by frame after the event, so nothing here says how a slide feels at full speed.
- The Mac was busy during the slide video: the first-time user was running on the small iPhone, and other simulators were booted.

## Summary
**68 scripted tests: 62 PASS, 2 FAIL, 4 BLOCKED.** No crash reports. The first-time user ran 46:54 without the project's notes, and the long run ran 15:17 with a Bass swap on the recording.

**All five failures from round 13 are fixed as far as I can test them:** `MIX` from part-way down, the crossfader shut on the playing deck, silence long before a track's end, the `FILTER` knobs, and the slide's wide gap. One step of the first is still wrong (N9).

**The stuck recorder on the Duo is gone.** Free disk fell under the 40 GB line at 12:59, so I shut the Duo down as agreed. Free disk is now 124 GiB. The Duo is booted but folded, so **the owner needs to press Open in Device Hub** before FA can run or anything can be pressed in its full layout.

**The most important problems, worst first:**
1. **N10: `AUTO` during a Loop build, before the handover, can leave the new deck playing in silence.** Its `PLAY` was lit, all four stems were at 0, and the old deck had lost its bass. The only signs are a dark waveform and the `STEMS` page.
2. **N11: `MIX` refuses with "A mix needs at least two tracks" while the sidebar says the playlist has 2.** `NEXT` is hiding the track on the deck. The first-time user hit this, and I reproduced it.
3. **N12: A recording's play button goes grey with no reason while a deck plays.** The first-time user lost about 11 minutes to this, on and off.
4. **N9: With everything played, `MIX` only refuses from the bottom row.** From row 3 of 5 it goes on and replays what's below.
5. **N13: The `PLAYLISTS` note says to press and hold a playlist to rename it, and that does nothing on an upright phone.** Holding one in the menu just chooses it, and I found no other way to rename there.

**The slide:** nothing is see-through any more, and I saw no flash or pop. The gap isn't gone, though: 32 of 50 slides had 40 pt or more of black for a few frames, and the widest was 124 pt, on the first slide after launch. See FB5.

## Failures

### N9 (FB1, last step): with everything played, `MIX` only refuses from the bottom row
- **Steps:** All Tracks by BPM, 5 tracks, all on air for over 10 s since opening the app. Gepzene on deck 1, row 3 of 5, playing. `MIX`. Then the same with Skylander, row 5.
- **Expected:** "with everything else already played: it should refuse."
- **Actual:** From row 3: "Mixing through all your tracks, 2 tracks to go. Up next: Houston." Both rows below had already played. From row 5 it refuses: "There's nothing left in all your tracks to mix into."
- **Why:** `Cheeks/AutoDJ/AutoDJ.swift` leaves out what's been heard only among the rows above the playing one. The rows below always go in.
- **Screenshots:** `fb1-row3-all-heard`, `fb1-row5-refused`

### N10: `AUTO` during a Loop build can leave the new deck playing in silence
- **Steps (long run, small iPhone):** Severe on deck 1 playing, Skylander on deck 2, `AUTO`. The Loop build started at 14:11:43. I pressed `AUTO` at 14:12:08, with deck 1 still in the build's 1-beat loop. Then `EXIT`.
- **Expected:** "Auto DJ stopped. The decks are yours. Deck 1 is still looping." is right. CLAUDE.md says "a new deck nobody's heard goes back as it was", and the long-run test asks for nothing left silent that the screen doesn't show.
- **Actual:**
  - Deck 2's `PLAY` stayed lit with the deck running at 0:31 and on, with **all four stems at 0**, its fader up and the crossfader in the middle. It was playing in silence.
  - Deck 1 was left with `BASS` off, and `LOW` and `FILTER` swept, which the arcs do show.
  - On the `CUE` or `FX` page the only sign is deck 2's dark waveform. The stems pads only show it on the `STEMS` page.
  - `ALL` on each deck brought everything back, so the decks are usable once you know. Nothing says so.
- **Screenshots:** `n10-handback` (at the press), `n10-new-deck-silent` (the `STEMS` page 30 s later)
- **Not checked:** other moves, other moments in the build, and whether anything on the recording shows deck 2 entering. I only ran this once at this point in a build.

### N11: "A mix needs at least two tracks" when the playlist has two
- **Steps:** Warmup holds Houston and Gepzene, and the sidebar says 2. Houston on deck 1. `NEXT` on. `MIX`.
- **Actual:** `NEXT` drops the leading deck's own track from the list, so one row shows, and `MIX` refuses with a hand. The first-time user worked it out and got past it in 6 s, by turning `NEXT` off.
- **Expected:** The refusal should say why, or `MIX` should count what's on the deck.
- **Code:** `AutoDJ.swift:261`
- **Screenshots:** `fu-mix-refused-next-on`, `n11-mix-next-hides`

### N12: A recording's play button goes grey and says nothing
- **Steps:** A deck playing. Open Recordings and press play on a mix.
- **Actual:** The button is grey and the press does nothing: no message, no buzz. With both decks stopped it's white and works. The first-time user pressed it at 13:00:14, tried a firm press, and only linked it to the decks at 13:11:40.
- **Why:** `.disabled(decksPlaying && !isPlaying)` at `Cheeks/UI/Browser/RecordingsView.swift:63`. Every other refusal in the app says why, through `dj.say`.
- **Screenshot:** `n12-recordings-grey`

### N13 (FC14): the `PLAYLISTS` note isn't true on an upright phone
- **Steps:** Upright phone layout (the Duo folded). Press `PLAYLISTS` with `?` on, then press and hold Set B in the menu it opens.
- **Note says:** "To rename one, press and hold the playlist."
- **Actual:** Holding it just chooses it, and I found no other way to rename one in that layout. On the small iPhone on its side, and on the unfolded Duo, holding it in the sidebar works and offers Rename and Delete.
- **Screenshot:** `n13-upright-playlists`

## Blocked
- **FA1 to FA3:** these need the Duo restarted and unfolded. It's restarted but folded. Stand-ins on the iPad and small iPhone are below, and I don't count them as passes.
  - **FA1 on the iPad, 2,000 tracks, both decks playing, 14 slides:** worst gap between changed frames 0.155 s, and 15 gaps over 0.1 s. Same as last round's 0.16 s with 2 tracks. `big_library.py` alone leaves no real tracks, so the tour stops with "it needs two tracks with audio". I copied two real files in first.
  - **FA2 on the iPad:** the logo holds its size and place, then cuts to the decks. No doubling or jump.
  - **FA3 on the iPad, 5 launches:** one sweep each. The meters are at about 46% on the first frame after the logo, so you only see them coming down, under 2% in 0.85 to 1.25 s. On the small iPhone they climb visibly, from about 60% to red in about 130 ms, and they're down by 2.3 to 2.8 s.
- **FB5, pressing during the slide on the full layout:** no touch access to anything with that layout after 13:00.

## Looks wrong
- **The Recordings icon moves when a recording starts.** The `REC` key grows to hold the timer and pushes it right, from about x 143 to x 187 on the small iPhone, and from 230 to 272 on the Duo. I pressed where it had been three times and got "Stop recording?" each time. It's one press from stopping someone's recording, though the alert does catch it.
- **A mix went through Warmup when I thought All Tracks was showing.** At 14:06:09 in the long run: "Mixing through Warmup, 1 track to go." The only press I can link to it was on the `LOOP` tab just after `BROWSE` twice, at the place Warmup sits in the sidebar. Three tries to repeat that all landed on the deck, so I can't say what did it. From the decks, nothing shows which list is on.
- **Which list, and how many are left, are only said once.** They're in the first message, for about 8 to 12 s, and then nowhere. The first-time user says so too, and at 13:18:19 it changed list with `MIX` still lit, which read as though `MIX` applied to the new one.
- **`PLAY` on the new deck during a Loop build's first seconds gets no reply.** At 13:36:38 it started deck 2 from where it sat, with `AUTO` still lit and no word. A second press stopped it. The score then took it from 2:34 to 0:35 by itself. Stopping it later gets a message.
- **A deck at its very end during a move.** With deck 2 at -00:00.0 in red and `PLAY` unlit, "Loop build starting" comes at once and deck 2 sits there for about 30 s. It then moves to 0:31 and the move finishes properly. This is what puzzled the first-time user at 13:06. It works, but nothing says deck 2's coming. `fu-deck2-at-end-explained`
- **The message and the key disagree by up to 3 bars at the press.** Message then key, about a second apart: 16 then 14, 12 then 10, 9 then 7, 9 then 6, 18 then 15, 7 then 5. Some do agree (12 and 12, 13 and 13). "About" helps, but the gap is in one direction, as if they count to different points.
- **A `FILTER` knob can stay on `FILTER` at the centre after the decks come back.** After `EXIT` during a build at 14:05:44, deck 1's knob read `FILTER` with a tiny blue dot and no visible sweep, and the key said `DUB`. It went back at the next `MIX`, 23 s later.
- **A plan moves the crossfader at the press, however far ahead.** Crossfader on the playing side, stems ready: "Loop build in about 9 bars. Crossfader to the middle, to hear both." It went there at once, 9 bars early. It says so, and goes back if called off. With stems still to come it stays, as asked.
- **A track parked by a mix stays parked.** After "Mix off: deck 2 was stopped." Severe stayed at 2:23.9 on deck 1, where the mix had put it. Pressing `PLAY` starts it there. Not wrong, but it's a surprise if you didn't see it being cued.
- **The same music gets a different BPM with silence after it.** Fade Test reads 170.0, and Fade Long, the same audio with 3 minutes of silence added, reads 162.7. Only made-up tracks do this so far.
- **Fast Bird's header read 140.59 at load and 139.71 by 0:10,** with 139.7 in the list. Seen once. I didn't look further.
- **`AUTO`'s note during a mix** is titled `AUTO` while the key reads `MIX 53`. The text does cover it, but only in its last sentence.
- **Slides can hold, then jump.** On 27 of 49 slides the whole screen held for 90 to 180 ms early on, then jumped up to 464 pt. That may be the recorder and the busy Mac as much as the app, since FA1's worst gap is the same size. Worth a look on the phone.
- **118 `AnimationKit` lines** from last round are still there, now 78 in an hour on the Duo, and they come with a row's or playlist's long-press menu. There are also 4 "updateVisibleMenuWithBlock while no context menu is visible". History's repeated-ID lines have gone.

## The stuck recorder, and the setup notes
- **`simctl shutdown` doesn't end an orphan recording.** The recorder stayed alive and started copying its 96.7 GB temp file into a final video at about 300 MB/s, and free disk fell from 39.6 to 30.7 GiB in 30 s. `kill -9` on that one `SimRenderingServices` process (pid 81303) stopped it, and 130 GiB was free 10 s later. The line in the task that says "only a shutdown clears it" needs that added. I've saved it in memory too.
- **Disk use otherwise:** 44 GiB free at 12:32 and 124 GiB now. I took my own old frames out of my scratchpad. Other sessions' scratchpads hold 13 GB, which I left alone.
- **The first-time user without the notes:** the `Explore` subagent type gets no CLAUDE.md or memories, and it has Bash and the touch tool. It only saved files once told it could, and it can't look back at its early screenshots, so I recovered 20 of them for you from the session's files.

## All results
| Test | Result | Notes |
|---|---|---|
| FA1 | BLOCKED | Needs the Duo open. iPad stand-in: 0.155 s |
| FA2 | BLOCKED | iPad stand-in: no doubling or jump |
| FA3 | BLOCKED | iPad and small iPhone stand-ins: one sweep each |
| FB1 order | PASS | Row 4 of 5: "Mixing through all your tracks, 4 tracks to go. Up next: Skylander." One message. Played rows 5, 1, 2, 3, then "That's the end of all your tracks." Key back to `AUTO`. Recording 18:12, no hole at a handover |
| FB1 refusal | FAIL | N9 |
| FB2 `AUTO`, shut | PASS | Master up at the press, "Crossfader to the middle. Auto DJ is waiting for the stems…". `AUTO` again: "Auto DJ off.", crossfader back, master silent |
| FB2 `MIX`, shut | PASS | Same, in one message with the count. Mix off with the mixer's key puts it back |
| FB2 on its side | PASS | Stems to come: stays, and no word. Stems ready: see Looks wrong |
| FB2 from nothing | PASS | Crossfader away and fader down: both opened. `PLAY` and the meters came up together on video |
| FB2 splitting | PASS | So high 14%, `MIX`, 25%, 34%. Not reloaded |
| FB2 first row | PASS | Fade Test at -7.5: started from there at 157.23 |
| FB3 | PASS | 55 s of silence: `AUTO` twice with the same track, and `MIX`. 3 minutes: `AUTO` and `MIX`. The next track started as the music ended each time, and the deck read 0:54.9 where I looked. Recordings show no silence between them, beyond Igor Pumphonia's own opening |
| FB4 | PASS | See Timings. Which moves took a knob: Loop build and Bass swap, the old deck's only. Echo throw and "No clean way in" took none. Brake drop not watched |
| FB5 gap | PASS | Smaller, not gone: 124 pt at worst. See Timings |
| FB5 flash | PASS | Jogs and pads fully drawn in the first frames of closing. `fb5-first-close` |
| FB5 pop | PASS | Nothing at 0.7 s. The biggest change after arriving is at 0.23 to 0.28 s and is tiny, the browser settling |
| FB5 small iPhone | PASS | Comes up from the bottom over still decks, and goes down the same way |
| FB5 presses, small iPhone | PASS | Frozen: `BROWSE` twice ends open, second lost, no cue. Close plus `PLAY` started. Close plus pad F set F. Open plus a row's `2`: nothing, twice. Next call: loaded. Never a wrong cue |
| FB5 presses, full layout | BLOCKED | No touch access |
| FC1 | PASS | Key went from 4 to 16 at the hand-back. `EXIT` shows 4 with `RELOOP`. `RELOOP` shows 16 and goes back in. "Deck 1 is still looping." |
| FC2 | PASS | Brake drop: "starting" within 1.3 s of the press, near a track's end, and the new track was on then. Echo throw: "starting" as the key goes to `AUTO`. I didn't check that against the echo's audio. Loop builds as before |
| FC3 | PASS | "Loop build in about 6 bars." See Looks wrong |
| FC4 | PASS | No repeated-ID lines. Both rows of a repeated track lit. `1`, `2` and hold land on the row aimed at |
| FC5 | PASS | `1` then a `2` on the next call both landed. Reorders after |
| FC6 | PASS | 3 s roll: no word, and the count carried on. 12 s past the moment: the key held at `MIX 5`, then `MIX 12` after release, with no word |
| FC7 | PASS | Knob it's using: said once. One it isn't: nothing. Crossfader: "…The crossfader's still turned away from it." |
| FC8 | PASS | "Echo throw done. Deck 1 is on. More like that?" with thumbs |
| FC9 | PASS | Built order with no column lit, sort kept per list, `MIX` plays that order |
| FC10 | PASS | Rename and Delete on hold, History only offers Delete. Not on an upright phone: N13 |
| FC11 | PASS | Time, length and slider. Pause holds, play goes on, drag lands, the end resets. "You're recording now…" |
| FC12 | PASS | `MORE` goes straight back to `SAMPLE` |
| FC13 | PASS | "FX pads slide…" 6.4 s, and a long one 9.4 s. Nothing took either away. I can't reproduce last round's 2.5 s |
| FC14 | FAIL | N13. The rest are true as far as I tried. Pinch and double-tap not tried |
| FC15 | PASS | Houston exactly as you listed. Others in Timings |
| FC16 | PASS | Small iPhone, fresh: opened on "Segue DJ, Folder is Empty". The first-time user got out in 18 s. The Duo opened on On My iPhone, as it remembers |
| A2 | PASS | Tap and swipe both: "Deck 1 is playing. Stop it first." with a hand. Shake not checked on video |
| B1 | PASS | 8 presses, both decks stopped, meters never moved |
| B2 | PASS | Up and back once |
| B5 | PASS | Tempo at once, not `NO TRACK` |
| B6 | PASS | 132.16 on header and jog, both decks. Menu: "Beat grid: 126.00 BPM at normal speed" |
| C4 | PASS | Both choices work |
| C7 | PASS | Full title in the browser where there's room, two lines on compact decks |
| C8 | PASS | Counter clear of the loop's line |
| C9 | PASS | All nine the same size. `SAMPLE` clear of `DEL` |
| D1 | PASS | Stays lit, restores |
| D5 | PASS | New title at once |
| D6 | PASS | "Stems 28%" |
| D7 | PASS | Still 32 |
| D8 | PASS | No loop on the new track |
| D9 | PASS | `.cue` and `.txt` both use the new name |
| D10 | PASS | Shape, not a flat band |
| D12 | PASS | Normal, stem colours with a ghost, normal |
| E | PASS | Hang log empty, pause icon while playing, play icon at the end |
| F1 | PASS | All there |
| F2 | PASS | Second refused, triangle shown |
| F3 | PASS | Refused, then an orange pad and bar |
| F4 | PASS | Jumps in and stays, and it starts the deck if stopped. Second tap ends it |
| F5 | PASS | `UNDO` brings it back |
| F6 | PASS | Name and colour reach pad and flag. Loop waits on reload without moving the deck |
| F7 | PASS | All there after relaunch |
| J1 | PASS | Strip shown. Sections in Timings |
| J2 | PASS | Counts up, restarts at a boundary |
| J3 | PASS | Exhilarate and Severe steady |
| K1 | PASS | Saved through the picker, including Replace or Keep Both |
| K2 | PASS | "Restored 12 tracks and 2 playlists." Cue back |
| K3 | PASS | Triangle. "Exhilarate's file is missing. Import it again and it'll get its cues back." |
| K4 | PASS | Warning gone, cues kept, same ID, no duplicate |
| K5 | PASS | Dated file in `Documents/Backups/` |

## Timings and measurements

### FB4, with `DUB` chosen, on the folded Duo and small iPhone
| Step | Knobs | Key |
|---|---|---|
| `AUTO` pressed, counting | `DUB`, `DUB` | `DUB` |
| Loop build's clock starts, about 4 s before "starting" | Old deck `FILTER`, new deck `DUB` | |
| Loop build over | `DUB`, `DUB` | `DUB`, next press `SPACE` |
| Bass swap's clock starts, about 7 s before "starting" | Old deck `FILTER`, new deck `DUB` | |
| Bass swap over | `DUB`, `DUB` | |
| Echo throw, 6 times, and "No clean way in" | `DUB`, `DUB` throughout | |
| `MIX`, 101 bars ahead | `DUB`, `DUB` | |
| `AUTO` off before the clock | `DUB`, `DUB` | |
| New deck stopped during an Echo throw | `DUB`, `DUB`, "Auto DJ stopped: deck 2 was stopped. Deck 1 carries on." | |
| `AUTO` during a Bass swap, 3 s after the clock, nothing swept | Old deck back to `DUB` at once | |
| `AUTO` during a Loop build, 25 s in, swept | Stays `FILTER` until the next `AUTO` or `MIX` | |

### FB5, the slide, iPad with two tracks, 50 slides, Debug, busy Mac
| | Left of the mixer, worst | Left, median | Right of the mixer, worst | Right, median | Frames of 20 pt or more, worst and median |
|---|---|---|---|---|---|
| Opening (25) | 72 pt | 14 pt | **124 pt** | 44 pt | 24 and 5 |
| Closing (25) | 58 pt | 44 pt | 70 pt | 18 pt | 9 and 4 |

- **The widest six:** 124 (first slide after launch), 98, 80, 72, 70 and 68 pt.
- **32 of 50 slides had 40 pt or more.** That's above your 10 to 40 pt guess, on a Mac busy with the first-time user.
- **The first slide does stand out:** 24 frames at 20 pt or more, about 240 ms. But the 98 pt one, at 81 s, lasted 18 frames, so later ones can be nearly as bad.
- **A 4 to 8 pt sliver at the screen's left edge** shows for about 0.2 s at the end of opening, while the browser eases in.
- **Last round was 381 pt with both panels see-through.** This is much better. The sheet is `fb5-first-open`.

### Bass swap
Its beat of silence on the recordings: **0.42 s under -50 dB** on both, on the Duo at 13:34 and in the long run at 2:00.5. No other gap in either swap.

### Long run, small iPhone
14:01:15 to 14:16:33, 15:17.6 of recording, about 31 presses, `DUB` chosen throughout. Tracklist 10 lines. Peak 0.0 dB, mean -14.6 dB. No crash and no dropout. The decks were usable afterwards.

| Time | What I did | What it said |
|---|---|---|
| 14:01:24 | `AUTO`, Houston into Skylander | Loop build, finished 14:02:23 |
| 14:02:50 | `AUTO` | **Bass swap** in about 7 bars, finished 14:03:31 |
| 14:03:56 | `MIX`, then a pad and a loop | "4 tracks to go". Pad moved the count. "The mix will carry on when deck 1's loop ends." |
| 14:04:50 | Loaded the waiting deck | "Mix off: the track changed." |
| 14:05:44 | `EXIT` during a build | "Auto DJ stopped: deck 1's loop was changed. The decks are yours." |
| 14:06:14 | Started the waiting deck | "Mix off: you started deck 2 yourself." |
| 14:07:01 | Stopped the old deck in a build | "Auto DJ stopped: deck 2 was stopped. Deck 1 is on." |
| 14:07:33 | A loop in the countdown | "Auto DJ stopped: deck 1's loop was changed…" |
| 14:07:42 | `AUTO` with that loop on | Took it off, finished 14:08:31 |
| 14:08:56 | `CUE` on the only playing deck | "Mix off: deck 2 was stopped." Silent until my `PLAY`, as you'd expect |
| 14:09:20 | An `ECHO` pad in the countdown | Echo throw finished 14:09:44 |
| 14:12:08 | `AUTO` during a build | N10 |
| 14:13:15 | `AUTO`, with a stem press during it | Finished 14:14:05 |
| 14:14:31 | `MIX`, then seeks | Echo throw finished 14:15:34, `MIX 79` on the next |

Gaps of 0.25 s or more, all explained:
- 0:00 to 0:06.7: before `PLAY`.
- 2:00.5, 0.42 s: the Bass swap's beat.
- 7:40 to 7:53: my `CUE`, then Exhilarate's own quiet opening.
- 12:46.7 and 13:02: Gepzene's own dips.

### FC15, sections
| Track | Sections |
|---|---|
| Houston | `INTRO`, `CHORUS` 0:22, `VERSE` 0:38, `CHORUS` 1:46, `VERSE` 2:09, `CHORUS` 2:55, `VERSE` 3:18, `CHORUS` 3:56, `OUTRO` 4:26 |
| Skylander | `INTRO`, `UP` 0:23, `CHORUS` 0:31, `DOWN` 2:18, `VERSE` 3:12, `UP` 3:27, `CHORUS` 3:35, `OUTRO` 5:23 |
| Gepzene | `INTRO`, `UP` 0:09, `CHORUS` 0:17, `DOWN` 1:47, `UP` 2:02, `CHORUS` 2:09 |
| Exhilarate | `CHORUS`, `VERSE` 0:36, `UP` 0:53, `CHORUS` 0:59, `OUTRO` 2:18 |
| Severe | `INTRO`, `UP` 0:06, `CHORUS` 0:12, `VERSE` 1:56, `CHORUS` 2:48, `VERSE` 3:40, `CHORUS` 4:06, `VERSE` 4:32, `CHORUS` 5:11, `VERSE` 5:24, `UP` 5:43, `CHORUS` 5:50, `OUTRO` 6:42 |

**What looks unlikely:** Gepzene has no `OUTRO` and stays `CHORUS` for its last 1:39, and Exhilarate opens on `CHORUS` for 36 s. Nobody's checked these by ear.

### The first-time user's three questions
- **Would it find `MIX`?** It read the note at about 3:43 with `?` on, and its first real press was by 11 minutes in: the frame at 12:46:00 has the key reading `MIX 76`. So it found it, through `?`, and not by guessing.
- **Does it read as one more filter?** Its shape and lit state still look like `NEXT`, it says, and it can't honestly say what it thought before reading the note.
- **Moves, thumbs and `MEM`:** "Loop build" read as a technique's name. It read the thumbs as "pick more moves like this", pressed them four times, saw no effect, and they go quickly. It doesn't remember `MEM`, which is behind `MORE` on this phone.
- **What's left in a mix, and that it's ended?** Only briefly, from the first message. It never saw a mix end.

## First impressions
1. **Does it look like $1000 pro software?** On a big screen, close: the jogs, the meters, the waveforms and the density all look the part. On a small phone it's a very good small version, but crowded. Three things break the illusion:
   - Rules that fail silently: the grey play button, a mix that "needs two tracks" with two there, and a new deck that plays without a sound.
   - Messages sitting over the search box, the filters and the waveform labels, which you need at that moment.
   - Text cut short on the phone: "Gepzene - Can't be…", "History 202…", "Tire Dam…".
2. **What felt slow, confusing or surprising?**
   - Waiting for stems before `AUTO` can do anything clever: 2 to 4 minutes a track on this Mac's CPU, which a phone may beat.
   - A key labelled `AUTO` that reads `MIX 53` and whose note is titled `AUTO`.
   - A move that takes a knob, and one that doesn't, with no way to tell which beforehand.
   - The Recordings icon moving under your finger.
3. **Which control was hardest to find or hit?** The `FILTER` key, inside `MIXER` on a phone. Then the tempo fader, behind `JOG` on a phone. And the sampler, four presses into `MORE` the first time.

**Not covered:** how anything sounds, a real finger, haptics, double-tap on a knob, pinch on a waveform, whether the Duo's own slide stalls on a real phone, and the parts of Part 1 and 2 this round didn't ask for (A1, A3, C1 to C3, C5, C6, D2 to D4, D11, G, H, I).

## The first-time user's report

It ran from a session with no CLAUDE.md and no memories, and its brief named no controls. It did see the working folder's name and the two cache folders' names. Its report is below, unedited. It can no longer see its own early screenshots, so I went back to the session's files and saved 20 of them as `fu-*`, and those fill in some of what it marks as "Log":
- `fu-files-folder-is-empty`: the picker at 12:35:31.
- `fu-mix-note`: `MIX`'s note at 12:38:57.
- `fu-crossfader-message`: "Crossfader to the middle, ready for what's next." at 12:46:00, with `MIX 76` on the key.
- `fu-mix-from-all-tracks`: "Mixing through all your tracks, 3 tracks to go…" at 12:51:33.
- `fu-loop-build-with-deck2-at-end`: "Loop build starting" at 13:06:01, with Skylander at -00:00.0.

**Its answers to my questions afterwards,** beyond what's under Timings:
- **After `?`, still a mystery:** `REC 5`, the thumbs, the red flag, the coloured blocks between the waveforms, the green "AI" dot, and how `SLIP` behaves during a Loop build.
- **Notes that didn't help:** "SAMPLE PAD: Plays this sound" doesn't say what `REC 5` is. `AUTO`'s "a % the stems, … it's thinking" is too compressed. The waveform's note mentions stem colours but not when they come on. It can't prove any note wrong, and `BEAT SYNC`'s held up when it tried it.
- **With ears and a finger, it would have tried:** whether the handover stays in time, a long blend by ear with sync off, headphone cueing, how clean the stems are, what the knob effects do, scratching on the jog, pinching the waveform, and moving a crossfader and a knob together.

## Its report, as it wrote it

Started 12:35:14. The 45 minutes were up at 13:20:14. Last touched the app at 13:22:08. One screenshot saved at 13:24:18.

### How to read this report
- Written after the session, not as I went. I held back at first because this session has a read-only rule, then wrote it once the coordinator allowed this one folder.
- Screenshots: only fu-now-end-of-session.png exists. It was taken after the session and I haven't viewed it. The coordinator then withdrew the request for more, so moments below are given by time, not screenshot name.
- "Seen" means I could still see the screenshot when writing. "Log" means I only have the tap time and any short note from then, so the result isn't confirmed. I can no longer see screenshots from before 13:14:47.
- I opened the app by tapping its home screen icon, not with simctl launch. I also ran python3 time.sleep in Bash to wait, which wasn't in the brief.
- Many taps were queued before I'd seen the screen, which a person wouldn't do. Times are not human reaction times.

### 1. Moments I wasn't sure what to do
- 12:35:18, Import (log). Wanted my music in. Import's glow changed but the screen didn't move. I tapped elsewhere (I no longer know what was there) and waited. About 15 s before I could pick files.
- 13:00:14, recording playback (log). Wanted to play my recording with decks running. Play did nothing and a firm press didn't help. I didn't connect it to the decks until 13:11:40, about 11 minutes on and off. Re-check: play was grey with a deck running (13:19:20, seen), white with both stopped (13:21:58, seen), and played from 13:22:02 (seen).
- 13:05:33, AUTO with deck 2 parked at its end (log). "Loop build starting" at 13:06:01, with deck 2 still at its end. I don't know how that run ended.
- 13:15:57, MIX on Warmup (seen). "A mix needs at least two tracks", though the sidebar said 2. Only one row showed because NEXT was on. Turning NEXT off worked 6 s later.

### 2. Stages, from opening the app
These are the times I tapped, not confirmed results. I can't hear anything, and I no longer have the meter images for the early stages.

| Stage | Clock | From open | Evidence |
|---|---|---|---|
| Tapped Import | 12:35:18 | 0:04 | Log |
| Picked five files and confirmed | 12:35:43 | 0:29 | Log |
| Track loaded on each deck | about 12:35:52 | about 0:38 | Log |
| First sound (play on deck 1) | 12:36:00 | 0:46 | Log |
| Two tracks playing together | 12:36:08 | 0:54 | Log |
| First move across (crossfader) | 12:36:15 | 1:01 | Log |
| First used ? | about 12:36:19 | about 1:05 | Log |
| First touched MIX, apparently with ? on | about 12:38:57 | about 3:43 | Log |
| First pressed AUTO | 12:39:26 | 4:12 | Log, result unknown |
| Opened "What everything does" | about 12:39:52 | about 4:38 | Log |
| Warmup playlist made | about 12:41:05 | about 5:50 | Log, playlist seen later |
| Recording started and stopped | 12:55:11 to 12:59:58 | 19:57 to 24:44 | Log, the 4:47 file seen |
| Full MIX handover | 13:16:03 to 13:18:04 | 40:49 to 42:50 | Seen |

### 3. What I still can't explain, and wording
Can't explain:
- What the REC 5 pad does. In ? mode it only says "SAMPLE PAD: Plays this sound".
- What the thumbs on "More like that?" change. I saw no visible effect.
- The red flag on the overview, and the coloured blocks between the two waveforms.
- The green "AI" dot on the stems page.
- With SLIP on, deck 1's time ran backwards during the loop build (3:28.9 to 3:25.7) and never jumped ahead, so I can't square that with SLIP's tip. Deck 1 stopped at the end of the move, which may be why.
- How the search in "What everything does" performed. I tried about eleven searches, but those results are lost.

Wording:
- "A mix needs at least two tracks." is misleading when a filter is hiding the second track.
- AUTO's tip, "A number's bars to go, a % the stems, ... it's thinking", is accurate about the number but too compressed for a newcomer.
- The mixer's AUTO button reads MIX 40 during a browser mix. BEAT SYNC is just SYNC in the pad layout, which looks like the same control.
- "Loop build" and "V I B D" are jargon on first sight, though the V I B D tip explains itself.
- "History 20..." is cut off in the sidebar, so I can't read the date. I didn't make this playlist, and it lists repeats.

### 4. Anything that looked broken
I saw no crash.
- 13:15:57: the MIX refusal above.
- 13:15:57, 13:16:03, 13:18:25: messages cover the search box and filter buttons while they show.
- 13:19:20 and 13:21:58: the grey play button gives no reason. Share and the three-dot button look disabled in both states, while the list icon stays bright.
- 13:17:19: during the mix, deck 1's knob changed from CRUSH to FILTER without telling me. It was back to CRUSH by 13:19:47.
- 13:18:04: deck 1's key shift went from +2 to 0 at the end of the mix, again without a word.
- 13:19:47: deck 2's waveform was in stem colours while Settings said 3-band, and deck 1's wasn't. It stayed that way after all stems were back on (13:20:11). This may be intended.
- History count went from 14 at 13:15 to 16 at 13:18 to 17 at 13:21. I can't say what adds entries.
- 13:15:34: a quarter turn left the app sideways, with no upright layout.

### 5. Best and worst for a newcomer
- Best: ? mode, because it's safe and specific. The tips for Q, SLIP, LIM and BEAT SYNC told me what I needed in one go.
- Worst: the amount on one small screen, combined with rules that fail silently. I had to work out for myself why things refused to act.

### 6. What I can't un-know
- Before opening the app: my session setup listed the working folder /Users/nikhil/Cheeks and caches named cheeks-autodj and cheeks-stems. The brief also gave the simulator name and bundle ID, so I expected auto DJ and stems.
- Knowledge beyond the brief: I know quantize, stems and hot cues, and that key labels like 5A work on a wheel. That's why 5A becoming 7A at +2 made sense to me. I also expect a tempo fader to slow down when pushed up (13:18:40, -6.9 and 117.33), which a newcomer might read as backwards.
- The app's name for itself: none of the screens I can still see shows one, so I only know "Segue DJ" from the brief.

State left behind: app running, both decks stopped, my Warmup playlist and one recording added, deck 1 tempo at +7.2.

## What happened next

The final gate, from clean installs: unit 435 tests (8 skipped), no failures. iPad 28 UI tests (5 skipped), no failures. Small iPhone: phone layouts 3 pass, and the walk 5 pass with no control lacking a note. A short suite on the folded Duo, 4 pass. The long suite on the unfolded Duo wasn't run, as it's folded.

The first full run caught a mistake of mine that the new tests alone hadn't: the check for someone starting the new deck also fired when a move's clock ran out, so every move ended saying "you started deck 2 yourself". That's fixed. Three older tests expected the silent new deck that N10 removes, so they now use a Bass swap, where the new deck's been heard. `testTheFXTabSaysWhenEffectsAreOn` failed once in that first run and passed in the second. Nothing it touches changed, and I didn't find out why, so say if the `FX` tab's blue dot ever misbehaves.

**Fixed, with a test I ran with the fix taken out, to see it fail for the right reason**
- **N10: the new deck left playing in silence.** The score starts a new deck a couple of bars ahead of its moment with every stem down, and handing back only looked at whether it was playing. So `AUTO` in those bars left it running with nothing to hear. A new deck with no stem up is now stopped and goes back as it was: stems up, its tempo and key, and the place it was in. One that's been heard carries on. The old deck stays as it is, as that's what people are listening to.
- **What's still down after a hand-back.** A stem's level only shows on the `STEMS` page, so the message now ends "ALL brings back deck 1's stems." when a playing deck has any down.
- **N9: refusing from any row.** What's been on air is left out on both sides of the playing row. With nothing left it refuses, and says "You've played the rest of Warmup. To go round again, stop the deck and press MIX.", which is the way to replay a list, and that has a test as well.
- **N11, part of it.** The refusal says what's showing: "A mix needs at least two tracks, and only one's showing." A mix now starts on the deck its first track is already on. It would have loaded it on deck 1 as well.
- **`PLAY` on the new deck early in a move.** It ends the move and says so: "Auto DJ stopped: you started deck 2 yourself. Deck 1 carries on." Its stems come up, as someone who presses `PLAY` wants to hear it.
- **A deck at its very end during a move.** A plan now cues the new deck where it'll come in, at once, as a DJ would, and puts it back if it's called off. One moved by hand since stays where it was sent.
- **The message and the key.** They never counted to different points. The message was being read a few seconds after it went up, with the key counting beside it. There's no number in it now: "Loop build next. The key's counting down the bars."
- **A `FILTER` knob at the centre.** A sweep under 0.03 can't be heard, so it counts as no sweep, and the knob goes back to what the key says. A knob still swept stays on `FILTER` until it's back at the centre, by hand or otherwise.
- **The crossfader moving at the press.** It and the new deck's fader now wait for the score's clock, about 2 bars before the move, the same as the `FILTER` knobs. That's said then. In a mix it could have been minutes early.
- **The same music at another BPM: this was worse than it looked.** On the old code, 60 s of music at 170 BPM with 3 minutes of silence after it read 109, and one at 128 read 122.89. Silence brought down the average that an onset's measured against. The first analysis now stops where the music stops. On 40 real tracks, none changed in BPM, key or sections, and one lost one tempo marker of 124.

**Fixed, with a UI test**
- **N12: the grey play button.** A line at the top of the sheet now says why while a deck's playing: "A recording plays out loud, over the mix. To listen to one, stop both decks." A press buzzes and moves its hand. The status capsule's under the sheet, so it couldn't go there. The share and menu icons beside it are the same colour as the list key now, as they looked disabled.
- **N13: renaming on an upright phone.** The playlists menu has a tick on the current list, and Rename and Delete for it. The note says where to look.
- **Which list, and what's left.** While a mix is on, a line along the bottom of the browser's list says so: "Mixing through Warmup, 3 tracks to go." It's over the list and not above it, so nothing moves under a finger. It's there whichever list is showing, which answers changing list with `MIX` lit.

**Changed, with a test of what it does, or none**
- **N11, the rest.** With `NEXT` on, `MIX` puts back the track it's hiding, first. So with Houston on the deck and Gepzene showing, it plays Houston and then Gepzene. No test of this part: it's in the browser's body. It's in the retest.
- **The slide.** Measured in Release on the iPad, the mixer runs about a frame behind the panels, as UIKit moves them on the render server and SwiftUI moves it from the main thread. That's the steady gap: 26 slides had a median widest gap of 47 pt, and a worst of 98. There are two changes. The panels start 8 ms later, which took the median to 33 pt. And a panel-coloured backing now goes with the mixer, under the panels, only while they move, so what opens is the panels' own colour and not black. Over 27 slides the widest black is now 3 pt typically and 24 pt at worst, and none has 40 pt or more. In frames from the middle of a slide I can't see the band. It's still there, up to about 100 pt wide, so it's worth saying if it shows at speed.
- **The first slide after launch.** Sampling it found the 100 to 243 ms freeze isn't in the app's code: the main thread is waiting inside Core Animation's commit, while RenderBox is on the phone to the render server (`RB::SharedSurfaceGroup::prune_removed_locked`, `-[CAContext waitForCommitId:timeout:]`). That's the simulator's render server being busy with a first frame. A phone may well not do it.
- **The holds in your 27 of 49 slides:** in Release there's no main-thread freeze of 50 ms or more in any slide but the first. So the rest is the render server or the recorder, and I can't take it further without a phone. I measured 9 of 26, 10 of 27 and 12 of 27 in three runs, the same before and after the backing.
- **The Recordings icon** is left of `REC` now, as `REC` grows to hold its timer. It can't move.
- **`AUTO` during a mix** has a note of its own, titled `MIX`, and `AUTO`'s note is clearer about what the key shows.
- **`MIX` looks like what it is:** a play or stop mark on it, and a gap from the filters, where there's room. It read as one more filter.
- **On a phone, a message over the browser** hangs below the search and the filters, as those are often what it's sending you to.
- **History** reads "History Nov 4" and fits.
- **Notes:** `REC 5` on a sampler pad, and the flags on the overview, were the first-time user's questions.

**Answers to what you asked or saw**
- **Fast Bird's 140.59 and 139.71:** that's jam1121443, which has a real tempo map with over 120 markers, and the header shows the tempo at the playhead. Nothing's wrong.
- **FC13:** that's two rounds of nothing taking a message away early, and I can't explain the 2.5 s, so I'm closing it.
- **The knob going from `CRUSH` to `FILTER` during a mix, and the key shift going back to 0 at its end,** are as designed. The knob's note says Auto DJ can borrow it, and the old deck's numbers were the move's.
- **`SLIP` during a build:** the time running backwards is the loop wrapping. There's nothing to come back to, as the deck stops at the end of the move.

**Decided against**
- **A track parked by a mix:** the deck shows where it is, and moving it after the fact would be the surprise.
- **Saying beforehand which moves take a knob:** nobody needs that before pressing, and it shows when it happens.
- **Changing Gepzene's and Exhilarate's sections:** the kick and the bass really are in, so the rule's doing what it says. Someone has to listen before that changes.
- **The `AnimationKit` lines:** those are iOS's own, from its long-press menus.

**Not done**
- **Pressing during the slide on the full layout, and FA.** These need the Duo opened in Device Hub, or the iPad's touch access granted. I've asked the owner.
- **Moving the mixer with the panels for real,** which would need it in a host of its own. Nothing in one showed up for VoiceOver last time, and I still don't know why. The backing makes that matter much less.
- **A playlist can't be reordered,** and tracks can only be added one at a time. Features, so they wait behind bugs and speed.
- **The Files folder, the first keyboard's freeze, the import picker's first folder and the slide's stalls** still want the phone.
