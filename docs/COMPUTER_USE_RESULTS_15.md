# Hands-on results, part 15, 2026-11-04

Commit tested: b70f85f

Device:
- **Folded iPhone Duo:** 466×678 pt, upright phone layout, most of the retest and Part 2.
- **iPhone SE Cheeks:** 667×375 on its side for CPU, `B1`, `C3`, `C5`, `C6`, `GC10` to `GC13`, and the long run. Upright for the first-time user.
- **iPad Air 13-inch (M4):** video only, for the slide.

Tooling limits:
- **The full layout can't be pressed.** The Duo is still folded: its inner screen is black and SpringBoard logged no `hingeState:` line I could read. I didn't reboot it. I asked for the iPad's touch access again at 18:39 and it wasn't answered. So all of GA is blocked, and `C5` and `C6` ran on the small iPhone and the folded Duo instead.
- **Can't be checked here:** how anything sounds, haptics, the headphone output, and a real finger. The one buzz in `GB3` is unchecked for that reason.
- **Double-tap on a knob or fader:** two tool calls are too slow to count, for me and the first-time user.
- **Screen reading:** a logger read the top of the screen by OCR about twice a second, sometimes slower, so its times are good to about a second. It stalled once for 8 minutes (17:49:42 to 17:58) and I restarted it. Nothing timed depended on that stretch.
- **Freezing the app:** I pressed inside short moments by stopping the app with SIGSTOP. My first try sent the wrong signal number, so it didn't freeze. That press landed about 2 s after the new deck lit, and I count it as "past the drop". A freeze also runs a recording's timer on, so `gb.m4a` is 20:40 long with its timer at 22:18. That's my doing.
- **Busy Mac:** the first-time user was on the small iPhone during the slide video and most of the retest, and `photolibraryd`, `backboardd`, `pairedsyncd` and `softwareupdated` were using up to about 60% of a core each at times. Mac idle was 50 to 75% during the CPU table.

## Summary

54 scripted tests including the long run: **48 PASS, 2 FAIL, 4 BLOCKED.** No crash reports. The first-time user also found a failure that I confirmed, and it's listed as `N14`.

**Everything that failed last round is fixed.** The new deck's no longer left playing in silence, in 4 presses inside that window while frozen and 3 more in a build's last bars during the long run. `MIX` with `NEXT` on works from either deck. A recording says why it won't play. `MIX` refuses from every row. An upright phone can rename a playlist.

**The three most important problems:**
1. **`N14`: the mixer sheet's knobs hardly move on a phone.** `TRIM 1`, `TRIM 2`, `MASTER`, `CUE/MST` and `LEVEL` are only in that sheet there. A 120 pt drag over 2 s did nothing. On the main screen, 85 pt is the whole travel. The first-time user lost about a minute to it and saw the sheet ride up instead. My tool isn't a finger, so this wants checking by hand, but both of us saw the same thing on three setups.
2. **`N15`: `PLAYLISTS` has no note on its side.** With `?` lit, pressing a sidebar row chooses it, `New Playlist` opens its name prompt and the heading does nothing. The note is only on the upright menu's key, so the sidebar can't be asked.
3. **`N16`: a new deck's fader comes up without a word when the crossfader's already centred.** The message only speaks for the crossfader.

**The slide is much better.** Nothing flickered when the backing went, and the stand-stills are mostly gone. Panel-coloured band is wider than the black it replaced: up to 102 pt for a frame. It's in `GC9`.

**The long run was clean:** 15:13.7, about 35 presses and takeovers, two hand-backs in a build's last bars with `EXIT`, one with `AUTO`, a finished Bass swap, and every gap on the recording explained.

## Failures

### N14 (new, from the first-time user): the mixer sheet's knobs hardly move on a phone
- Steps: open `MIXER`, drag a knob up or down.
- Expected: the same travel as the main screen's knobs, where 85 pt takes `FILTER` from the centre to the end.
- Actual:

| Where | Drag | Result |
|---|---|---|
| Folded Duo, `TRIM 1` | 40 pt in 0.5 s | No movement |
| Folded Duo, `TRIM 1` | 60 pt in 0.5 s | No movement |
| Folded Duo, `TRIM 2` | 37 pt in 130 ms, finger-speed points | About 15° |
| Folded Duo, `TRIM 1` | Hold 300 ms, then 47 pt in 360 ms | About 15° |
| Small iPhone on its side, `TRIM 2` | 40 pt in 0.5 s | No movement |
| Small iPhone on its side, `MASTER` | 120 pt in 2 s | No movement |
| Small iPhone on its side, `MASTER` | Hold 500 ms, then 60 pt in 450 ms | About 12° |

  The first-time user, upright on the small iPhone at 17:35 and 17:48, says ordinary drags moved the sheet, and three tries each on `TRIM 1`, `TRIM 2` and `MASTER` did nothing. The sheet also covers the meters you'd watch while setting `TRIM`. `CompactScreen.swift:357` makes it a `.medium` detent sheet, and `Knob` takes its touches through `TouchSurface`, so a sheet's own drag may be winning, though I haven't proved that.
- Screenshots: `n14-trim-after-drags.png`, `n14-master-after-two-drags.png`, `fu-mixer-sheet-knob-fight.png`, `fu-mixer-sheet-trim-barely-moved.png`.
- Not known: whether a real finger does better. Please try it on the phone.

### GC12 / N15: `PLAYLISTS` can't be asked on its side
- Steps: small iPhone on its side, browser open, `?` on. Press the `PLAYLISTS` heading, a playlist row and `New Playlist`.
- Expected: a note, true to what it does. `GC12` asks for it both ways up.
- Actual: the general `?` note stays up throughout. The heading does nothing. A row chooses that list, which is fair as it only moves between pages. `New Playlist` opens its name prompt, though the note on screen says controls only explain themselves. `.whatsThis("Playlists")` is on the upright menu's key only (`BrowserView.swift:537`).
- Screenshots: `gc12-sidebar-no-note.png`, `gc12-sidebar-no-note-2.png`.
- Upright, the note's there and it's true.

### GC7 / N16: the new deck's fader moves without a word
- Steps: small iPhone. Crossfader at the centre, the new deck's fader all the way down, `AUTO`.
- Expected: at about 2 bars before "starting" the fader comes up, and it says so.
- Actual: it came up, and nothing was said between 18:38:37 and "starting" at 18:38:40. With the crossfader away as well, the message is "Crossfader to the middle, to hear both.", which doesn't mention the fader either. `openTheChannel` only speaks when the crossfader moves (`AutoDJ.swift:799`).
- Screenshot: `gc7-fader-only.png`.
- The rest of `GC7` passed. See the table.

## Blocked

| Test | Why |
|---|---|
| GA1 | The Duo's folded. Last round's iPad stand-in was 0.155 s, not rerun |
| GA2 | The Duo's folded |
| GA3 | The Duo's folded |
| GA4 | Nobody's pressed during the slide on a full layout yet, as the iPad's touch access isn't granted and the Duo's folded. This is the biggest thing still unchecked |

## Looks wrong

- **The mix line on an upright phone:** the home indicator runs through its text, on the folded Duo. `gc2-line-home-bar.png`.
- **"5 tracks" and "4 tracks to go" on screen together,** in the message and the mix line. The first-time user tripped on it as well, then worked out that one's already on a deck. `gc10-11-side.png`.
- **A chosen History row loses its end:** "History No…" in the sidebar when chosen, as the bold doesn't fit. Unchosen it reads "History Nov 4". `gc2-bottom-of-list.png`.
- **"While this is lit, the music won't change":** a running mix goes on changing tracks with `?` lit. What it means is that your touches won't change it. Seen by the first-time user at 17:07.
- **"The key's counting down the bars":** see `GC5`. "Key" also means the `KEY` filter, the `KEY` column, key lock and `KEY SYNC`.
- **A `MIX` refusal for a list nobody's played as a list:** one-track Friday, whose track had been on air earlier: "You've played the rest of Friday. To go round again, stop the deck and press MIX." It's true by the rule, and it does say what to do, but the first-time user just wanted to play a playlist, and nothing shows which tracks count as played. `fu19-friday.png`. With that same track on the stopped deck, it says "There's nothing left in Friday to mix into." instead.
- **The first-time user's first `MIX` was barely a blend:** about 5 s of overlap, as the next track's stems weren't ready. It's the designed fallback, and it's what a newcomer sees first.
- **A new deck reads a tempo nobody chose** from the moment a plan cues it: Skylander (125) read 126.00 with `SYNC` unlit, from the press. It's put back if called off.
- **From the first-time user, not checked by me:**
  - `SYNC` took Houston (126) to 85.00, half of 170, and when the other deck ended it stayed there as master with only -32.54% to show for it. `fu-stuck-at-85.png`.
  - `ROLL` and `SLICER` pads look dead on a tap, as they need holding and look like `CUE` and `LOOP` pads. `fu-recheck-roll-held.png`.
  - A sampler pad's Name field was blank though the pad said AIR HORN.
  - "Nothing here is in key or close in tempo" was untrue on a screen where something was in key and something else close in tempo. `fu-nothing-fits.png`.
  - `LIM` lit red for a moment with both tracks at default levels, at 17:35:53.
  - A recording's tracklist gives tempo as played and key as tagged. Houston at 10A was listed as 5A. `fu-recording-tracklist.png`.
- **Seen by both of us:** thumbs up and down vanish with no acknowledgement. Mine were at 18:24 and 18:34.
- **"That's yours now" and then the knob goes back:** the first-time user reproduced this twice, both on the old deck. That's as designed in `CLAUDE.md`, but they read it as a broken promise. `fu-recheck-thats-yours-toast.png`, `fu-recheck-knob-reset-after-yours.png`. In my run, with the move stopped by hand, the knob stayed where I'd put it.

The first-time user's "History is every load" isn't what I found: History went up by 10 in the long run, the same as the recording's 10 tracklist lines, and loading Exhilarate on a stopped deck added nothing. It logs tracks that were audible for 10 s, as `OnAirLog` says. Their list had many repeats because mixes come back to tracks.

## All results

| Test | Result | Notes |
|---|---|---|
| GA1 to GA4 | BLOCKED | See Blocked |
| GB1a | PASS | **`AUTO` in the silent window.** Loop build Houston into Skylander, frozen the moment the new deck's `PLAY` lit (0:27.7, every stem down), `AUTO` in the freeze: "Auto DJ stopped. The decks are yours. Deck 1 is still looping. ALL brings back deck 1's stems." New deck: `PLAY` unlit, every stem up, 125.00, and back at 1:32.8, where it was before the first press. Old deck: still playing with its loop, `BASS` half down, `LOW` and `FILTER` as they'd got to. `EXIT` and `ALL` bring it back whole. `gb1-before-press.png`, `gb1-auto-in-silent-window.png` |
| GB1b | PASS | **The same with `EXIT`:** "Auto DJ stopped: deck 1's loop was changed. The decks are yours. ALL brings back deck 1's stems." New deck back the same way. `gb1-exit-in-silent-window.png` |
| GB1c | PASS | **Bass swap:** `AUTO` 5 s after "starting", with the new deck's drums in: "Auto DJ stopped. The decks are yours. ALL brings back deck 2's stems." Both play, and `ALL` brings them back. `gb1-bass-swap-auto.png` |
| GB1d | PASS | **Other moments.** Before the new deck starts (4 s into a build, and just as `FILTER` appears): new deck back, no `ALL` as nothing's down. Echo throw in the new deck's first second: back at 0:00.5, `PLAY` unlit. Just past the drop: both keep playing, as people can hear the new one. Bass swap 11 s in, past its handover: "Auto DJ stopped. Deck 1 is on." and the old deck stopped. Nothing left silent in any of these |
| GB2 | PASS | **Houston on deck 1, stopped, `NEXT` on, one row:** "Mixing through Warmup, 2 tracks. Up next: Gepzene - Can't be Serious." Houston plays, then an Echo throw into Gepzene. Houston on deck 2: the same. Search leaving one row: "A mix needs at least two tracks, and only one's showing." None: "...and none are showing." `NEXT` hides the deck that leads, so Skylander on the other deck as master showed both rows until Houston had played |
| GB3 | PASS | Line at the top: "A recording plays out loud, over the mix. To listen to one, stop both decks." A press moved the hand for 0.48 s on video and didn't play. Both stopped: the line goes and it plays. The buzz can't be checked. `gb3-line.png` |
| GB4 | PASS | All 5 on air. `MIX` from rows 1, 3 and 5: all "You've played the rest of all your tracks. To go round again, stop the deck and press MIX." Stopped, `MIX`: "Mixing through all your tracks, 5 tracks. Up next: Houston.", from the top. Relaunched, only rows 2 and 4 on air, `MIX` from row 3: "2 tracks to go. Up next: Skylander", row 5. Then Severe loaded, row 1 |
| GB5 | PASS | Upright menu ticks the list. Warmup: Rename Playlist and Delete Playlist, and renaming worked, read back from `library.json`. History: only Delete. All Tracks: neither. `gb5-playlist-menu.png`, `gb5-history-menu.png` |
| GC1 | PASS | Recordings icon, `?` and gear stay put. `REC` grows to the right. The `MASTER` readout moves about 44 pt, but nobody presses that |
| GC2 | PASS | "Mixing through Warmup, 1 track to go.", counted down, "Mixing through Warmup. This is the last track.", gone with the mix. Still named Warmup on All Tracks. Rows stayed put as it came and went. Last row of a long list above it. `gc2-other-list.png`, `gc2-last.png`, `gc2-bottom-of-list.png` |
| GC3 | PASS | `PLAY` on the new deck before the score starts it: "Auto DJ stopped: you started deck 2 yourself. Deck 1 carries on." Heard, from its cue, stems up. In a mix: "Mix off: you started deck 2 yourself...". After the score's started it: "Auto DJ stopped: deck 2 was stopped. Deck 1 carries on." `gc3-play.png`, `gc3-stop-new-deck.png` |
| GC4 | PASS | At the very end in red (-00:01.9). At the press, once planned: 0:31.2. Called off: back at -00:01.9, 125.00. Scrubbed to 2:59.1 while counting and called off: stayed at 2:59.1. Nothing surprised me apart from the tempo noted above. `gc4-cue-at-press.png` |
| GC5 | PASS | "Loop build next. The key's counting down the bars." It reads right and I do look at the key, and it counts in step. But the first-time user read "key" as a musical key, and said so |
| GC6 | PASS | `DUB` chosen. Hand-back just as `FILTER` appeared: `DUB` at once. 17 s into the sweep: stays `FILTER`, then `DUB` straight after I turned it to the centre. `gc6-filter-stays.png` |
| GC7 | FAIL | See N16. **Passed:** crossfader left and fader down, `AUTO`: neither moved at the press, both moved at key 2 with a message. `MIX` a plan ahead: the same, "Crossfader to the middle, ready for what's next." Called off before: where I left them. During, new deck unheard: back where I left them. Landing heard: first kick -8 dB on the recording, from -30 just before. `gc7-mixer.png`, `gc7-mix-at-the-clock.png`, `gc7-called-off-during.png` |
| GC8 | PASS | Fade Test and Fade Long both 170 BPM, 12B |
| GC9 | PASS | See the table below |
| GC10 | PASS | A play mark, a stop mark while on, and a gap, on its side. Upright has no mark, and the first-time user took it for a filter. `gc10-11-side.png` |
| GC11 | PASS | Below the search and filters, both ways up, readable. Two lines where needed |
| GC12 | FAIL | See N15. **True as far as I could try:** `AUTO`, the mixer's key during a mix (titled `MIX`), the mix line, `PLAYLISTS` upright, a sampler pad, the overview. `gc12-mix-note.png`, `gc12-overview-note.png`, `gc12-sample-note.png` |
| GC13 | PASS | "History Nov 4" and its count fit on the small iPhone, and in the upright menu. Chosen, it's cut: see Looks wrong |
| GC14 | PASS | Share and menu icons the same white as the list key |
| GC15 | PASS | I couldn't make it stay. After moves with stems down and `ALL`, off the `STEMS` page: normal colours, on 3-band on the Duo and on RGB on the small iPhone. `gc15-normal-colours.png` |
| A1 | PASS | 4 of 4: plain tap and 0.2 s, playing and paused. Cue back, capsule gone. `a1-undo.png`. My first tries read the screen between presses, and the 8 s had gone by then, so the tap fell through. That's me, not the key |
| A3 | PASS | See the table below |
| B1 | PASS | 8 `BROWSE` presses with both decks stopped, 197 frames: the meters never lit. Only panels passing through the crop, at most 73 of 3188 samples |
| C1 | PASS | On the folded Duo, a tempo cap's and the crossfader's line are midway between their ticks. `c1-caps.png` |
| C2 | PASS | 2 pt stays at the centre, 3 pt leaves it. Dragged from +11 towards the centre and stopped at +2: it caught |
| C3 | PASS | Small iPhone on its side, keyboard up: search field visible, mixer not involved. `c3-keyboard.png` |
| C5 | PASS | Not on the full layout. Small iPhone and folded Duo: bottom pads, crossfader, `PLAY` and `CUE`, all first press, no system gesture |
| C6 | PASS | Not on the full layout. `BROWSE`, `REC`, the Recordings icon and the gear, all first press across hundreds of presses this round |
| D2 | PASS | Video: pads go to a brightness of 104 to 106, then settle at 69 to 82. A slicer pad held 1.5 s: 88 to 109 against 44 to 46 for the others |
| D3 | PASS | Video with the deck stopped: lit for 1.31, 2.42, 3.99, 2.21, 0.50, 0.48, 0.29 and 1.03 s, with the meters on throughout |
| D4 | PASS | `IN` lights, and a thin orange line appears at the playhead before `OUT`. Clear on a stopped deck, faint while it's playing |
| D11 | PASS | Drag from 180 to 210: the blue ends at 209.3. From 230 to 150: 149.3. It follows the finger |
| G1 | PASS | `SET`, `Q`, `VOLUME` and `STOP`. All eight fired |
| G2 | PASS | Sheet opens. No grab buttons with no loop, and they're there with one |
| G3 | PASS | Gate: a 0.6 s press lit for 0.65 s, with the meters off by 0.8 s of a 1.3 s sound. Loop: one tap ran it 4.79 s, the next stopped it |
| G4 | PASS | `LOOP 1`, with a loop mark, goes round |
| G5 | PASS | A red timer in place of `SET`. `REC 3` after about 5 s. Meters move playing it with the deck stopped. `g5-recorded-pad.png` |
| G6 | PASS | `RISER` back. "Restore the Original Sound" is in red, which the first-time user found odd for a safe undo |
| G7 | PASS | `VOLUME` at the bottom: pad lit, meters dark. `STOP` stops a looping pad |
| H1 | PASS | `ECHO`, `FLANGER`, `TRANS`, then `CRUSH`: `ECHO` out, three lit. `h1-chain.png` |
| H2 | PASS | Slide on lit `FLANGER`: `DEPTH` follows it. I didn't read the others' depths separately |
| H3 | PASS | `OUT` lit, "Echo out on deck 1. Press OUT again to bring it back.", meters fall. Again: back from 2:14 to 2:28. `h3-out.png` |
| H4 | PASS | Stopped: "Echo out needs the deck playing." with a hand. Paused during one and played: meters on. `h4-out-pause.png` |
| I1 | PASS | `DUB`, `SPACE`, `NOISE`, `CRUSH`, `PITCH`, `FILTER`, under both knobs |
| I2 | PASS | With a track playing, each way, top of the meter: `DUB` 25-28, `SPACE` 26-29, `NOISE` 28-30, `CRUSH` 25-29, `PITCH` 22-28, `FILTER` 16-30 % lit, against 23-27 dry. Nothing silent, no jump, no red, no crash. Double-tap couldn't be tried |
| I3 | PASS | `DUB` well round, back to the centre, paused at once: the meter fell over 2.33 s. With 9 s at the centre first, 0.65 s, as the echoes had gone by then |
| Long run | PASS | See below |

### The first-time user's three questions
- **Would it find `MIX`, and does it still read as a filter?** Upright, yes, it read as a filter. They pressed it at 1:31 thinking it was one, and it started a mix. On its side, "▶ MIX" would have told them, they said.
- **Does it know which list a mix is on, what's left, and that a mix has ended?** They noticed the line and read it right, apart from "5 tracks" against "4 tracks to go". They never saw a mix reach its end, as they stopped each one or loaded over it.
- **Does anything still refuse without saying why?** Nothing refused silently. The silent failures are now things that do nothing rather than refuse: a tap on a `ROLL` or `SLICER` pad, and the mixer sheet's knobs.

## Timings and measurements

### CPU (`A3`, small iPhone on its side, Debug, RGB waveforms left by the first-time user)
| State | This round | Peak | Last round |
|---|---|---|---|
| Idle, nothing loaded | 3.7% | 3.9% | 4.1% |
| Two tracks loaded, paused | 3.9% | 4.1% | 4.3% |
| One deck playing | 9.1% | 9.7% | 9.4% |
| Both playing, synced, +2.4% | 16.3% | 17.0% | 14.6% |
| Both, plus stems and an echo | 17.0% | 18.0% | 14.9% |

Both-playing is up about 2 points. That may be RGB waveforms, as I didn't change them back, or the rest of the Mac.

### `GC9`: the slide
iPad Air, Debug, `CHEEKS_SELF_TOUR=browser`, on video, with the first-time user on another simulator. 21 slides from 19 to 50 s, and one of them had nothing over the threshold. Black is under about 15.5 of 255 and the band is the panels' colour, about 16 to 21. "Frames" counts frames of 20 pt or more. Left and right are either side of the mixer, black and band together.

| Time | Way | Widest black, pt | Frames | Widest band, pt | Frames | Left / right |
|---|---|---|---|---|---|---|
| 19.12 | Open, first | 40 | 1 | 46 | 2 | 0 / 46 |
| 20.69 | Close | 40 | 1 | 24 | 2 | 24 / 40 |
| 22.18 | Open | 30 | 2 | 42 | 1 | 42 / 0 |
| 23.79 | Close | 26 | 1 | 28 | 1 | 28 / 26 |
| 25.30 | Open | 26 | 1 | 46 | 1 | 46 / 0 |
| 26.96 | Close | 0 | 0 | 26 | 2 | 26 / 0 |
| 30.15 | Close | **58** | 2 | **102** | 1 | 102 / 22 |
| 31.64 | Open | 24 | 1 | 66 | 2 | 66 / 0 |
| 33.21 | Close | 0 | 0 | 72 | 2 | 0 / 72 |
| 34.70 | Open | 22 | 1 | 68 | 1 | 22 / 68 |
| 36.30 | Close | 26 | 2 | 24 | 2 | 24 / 26 |
| 37.88 | Open | 24 | 1 | 48 | 1 | 48 / 0 |
| 39.39 | Close | 26 | 2 | 30 | 2 | 8 / 30 |
| 40.97 | Open | 20 | 1 | 30 | 1 | 30 / 18 |
| 42.50 | Close | 42 | 1 | 42 | 1 | 10 / 42 |
| 44.07 | Open | 24 | 2 | 68 | 3 | 68 / 0 |
| 45.66 | Close | 26 | 1 | 30 | 1 | 30 / 26 |
| 47.24 | Open | 0 | 0 | 34 | 1 | 34 / 0 |
| 48.76 | Close | 18 | 0 | 32 | 2 | 8 / 32 |
| 50.29 | Open | 48 | 2 | 12 | 0 | 48 / 12 |

- **Against last round:** widest 124 pt then, 102 now, and that's the band and for one frame. Black's widest is 58 and its median 26. You measured 3 typically and 24 at worst in Release, so Debug with a busy Mac is well over that. 5 of 20 have 40 pt or more of black, and 12 of 20 have 40 pt or more of black and band together, where it was 32 of 50.
- **The first slide no longer stands out:** 46 pt and 3 frames, where it was 124 and 24.
- **Can the band be seen at full speed?** I can't watch it at speed. Going by the numbers, it's up to 102 pt for 1 to 3 frames, at about 18 of 255 against the panels' 26 and the screen's 13. It's easy to see in a still (`gc9-frames-at-widest.png`), and in a slide that takes 0.3 to 0.55 s I'd expect a moving dark edge at most. Please look on the phone.
- **Does anything flicker as the backing goes?** Not in the numbers. Beside the mixer, on 4 closing slides, the level steps down 26, 24, 21 or 24, 21, 19 around frames 40 to 47, about 0.45 s in, then stays. There's no rise or flash. `gc9-backing-goes.png`.
- **Stand-stills:** on the 18 slides I could separate, the longest stand-still was 27 to 95 ms, and only one was 90 ms or more. Last round 27 of 49 slides held 90 to 180 ms. The biggest steps are still large: 264 pt on the slide at 47.24 and 195 pt on the one at 30.15, which is where the 102 pt band was.

### Long run (small iPhone on its side, `DUB` chosen throughout)
18:22:02 to 18:37:15, 15:13.7, peak 0.0 dB, mean -15.0 dB. Music on throughout. No crash, dropout or unexplained stop. Afterwards nothing was left silent, looping or filtered that the screen didn't show. After each hand-back, `LOW` and `FILTER` showed on their knobs and the message pointed to `ALL`.

| Time | What I did | What happened |
|---|---|---|
| 18:22:10 | `AUTO` | Loop build next, Skylander into Houston |
| 18:23:05 | **`AUTO` in the build's last bars,** new deck just lit | "...Deck 1 is still looping. ALL brings back deck 1's stems." Houston back as it was. `long-auto-in-last-bars.png` |
| 18:23:20 | `ALL`, `LOOP` page, size key, `EXIT` | Whole again. Key back to 4 |
| 18:23:45 | Deck 2 on, `BROWSE`, row's `1`, `BROWSE`, `ECHO`, one after another across the slide | "Deck 1 is playing. Stop it first." `ECHO` landed on deck 2 |
| 18:24:00 | Stop deck 2, `AUTO` | **Bass swap,** Skylander into Houston, finished 18:24:38. 0.41 s under -50 dB at 2:20.8 |
| 18:24:45 | Thumbs up, `MIX` | "3 tracks to go. Up next: Gepzene" |
| 18:25:05 | Seek on the overview during the mix | The key follows: `MIX 15` |
| 18:26:00 | **`EXIT` in the last bars** of the mix's Loop build | "Mix off: deck 2's loop was changed. The decks are yours. ALL brings back deck 2's stems." Gepzene stopped, as it was. `long-exit-in-last-bars.png` |
| 18:26:44 | `ALL`, `AUTO` at -00:07 | "No clean way in from here. Deck 1 starts when this one ends." It did. The old deck's knobs had cleared |
| 18:27:15 | `BROWSE`, row's `2`, `BROWSE`, `AUTO` | Severe loaded, Loop build |
| 18:27:44 | `FILTER` on the old deck during the move | "That's yours now. Auto DJ carries on with the rest." |
| 18:28:08 | Stop the new deck in the last bars | "Auto DJ stopped: deck 2 was stopped. Deck 1 carries on." My knob stayed |
| 18:28:25 | `MIX`, then a 4-beat loop straight after the slide | "The mix will carry on when deck 1's loop ends." Key `MIX…` |
| 18:28:40 | `EXIT`, seek | `MIX 52`, then `MIX 6` |
| 18:29:10 | `PLAY` on the new deck early in the mix's move | "Mix off: you started deck 2 yourself. Deck 1 carries on." Both heard. `long-play-new-deck-in-mix.png` |
| 18:29:25 | Stop deck 1, load Exhilarate, `AUTO` | Echo throw, finished 18:29:56 |
| 18:30:12 | `AUTO` | Loop build next |
| 18:30:28 | 4-beat loop in the countdown | "Auto DJ stopped: deck 1 is in a loop." |
| 18:30:36 | `AUTO` | Loop off, Loop build again |
| 18:31:13 | **`EXIT` in the last bars** | "...deck 1's loop was changed... ALL brings back deck 1's stems." Severe back at 1:17.8. `long-exit-in-last-bars-2.png` |
| 18:31:40 | Friday, one track on deck: `MIX`. All Tracks, `NEXT` on: `MIX` | Both refused, with a reason |
| 18:32:10 | `AUTO` | Brake drop, 18:32:20.8 to 18:32:23.7. No knob changed label. That answers last round's open question on Brake drop's knobs |
| 18:32:35 | `BROWSE`, row's `1`, `BROWSE`, `AUTO` | Loop build |
| 18:32:52 | **Stop the old deck** 3 s in | "Auto DJ stopped: deck 2 was stopped. Deck 1 is on." Clean. `long-stop-old-deck.png` |
| 18:33:10 | Load Houston, `AUTO` | Loop build, finished 18:34:18 |
| 18:34:30 | Thumbs down, 4-beat loop, `AUTO` | Loop off, Echo throw, finished 18:34:59 |
| 18:35:20 | Load Gepzene, `AUTO` | Loop build, finished 18:36:08 |
| 18:36:20 | `MIX` on Friday, load Exhilarate on the stopped deck | Refused, then loaded. Stops at REC 15:13 |

**Gaps of 0.25 s or more under -50 dB:**
| At | Length | What it is |
|---|---|---|
| 2:21 | 0.41 s | The Bass swap's beat |
| 4:34, 4:41 | 0.38, 0.39 s | Houston's outro with its stems down, before my `ALL` |
| 4:49, 4:50, 4:51 | 0.25, 0.29, 0.31 s | Houston's own: the same three gaps are in the mp3 at 4:46 to 4:48 |
| 4:55, 5:06, 5:21 | 0.32, 0.33, 0.27 s | Gepzene's intro. The 5:06 one is in the mp3 at 0:15. The other two are the same 8-beat pattern, just under the threshold in the mp3 |
| 14:04 | 0.32 s | Gepzene's own gap at 0:15 again, falling in the Loop build's beat of breath just before the landing (`TransitionScore.swift:175`) |
| 14:19 | 0.25 s | Gepzene's 8-beat pattern again |

**The task only mentions a Bass swap's beat of silence, and a Loop build has one too, per that comment.** On Gepzene it went under -50 dB, so you may want to add that to the task. It's only worth a listen by someone who can hear it.

**Moves in the run:** Loop build 8 (2 finished, 3 handed back in the last bars, 3 taken over earlier), Bass swap 1, Echo throw 2, Brake drop 1, No clean way in 1.

### The earlier recording (`gb.m4a`, folded Duo)
20:40. Under -50 dB: only the first 0.86 s and 0.42 s at 11:56, the Bass swap's beat. So that's 0.41 and 0.42 s this round. Last round's were 0.42.

### Your other questions
- **`NEXT` on, the part with no automated test:** works on both decks. `GB2`.
- **The `FX` tab's dot:** lit with an effect on and gone with it off, on the Duo and the small iPhone, every time I looked. It never misbehaved.
- **The order on the top bar:** nothing's moved under a press since the change.
- **State left behind:** apps closed on all three. The Duo's library has Fade Test, Fade Long and a Warmup playlist. The small iPhone's has the first-time user's Friday and two recordings, plus mine. Free disk 125 GB. No recorder running.

## First impressions

**Does it look like $1000 pro software?** Yes, in the decks and mixer on its side, and even on a small phone it holds together better than it should. What breaks the illusion most:
1. **The mixer sheet's knobs,** if they do this under a finger too. They look like the hardware everywhere else, and there they won't turn.
2. **What Auto DJ does can't be seen unless you're on the right page.** On `CUE` or `LOOP`, a deck's sound goes away with its fader up. The first-time user took 34 minutes to see how it works, and only by having both decks on `STEMS` by luck. That's their worst thing, and I agree. A `?` note can't help, as nobody knows to ask.
3. **Words.** "Key" means six things by the first-time user's count, and "the rest of all your tracks" and "5 tracks" with "4 tracks to go" read like a machine, in an app whose messages are otherwise very human.

**What felt slow, confusing or surprising?** Waiting for stems the first time, on this simulator's CPU. A new deck showing a number nobody set. Stopping `AUTO` going two different ways depending on a moment you can't see, though the message is always clear about which it was.

**Which control was hardest to find or hit?** The sheet's knobs. Then `RELOOP` and `EXIT` on the small iPhone, which are small and close to the size key, and the `MORE` tab's hidden pages, which take four presses to learn.

## The first-time user

They ran for 56:20, with 45 minutes up at 17:49:26 and the rest spent checking their own notes, from 17:04:26 to 18:00:46, on the small iPhone upright, with no notes and from outside the repo. It's their report below, unchanged. I kept the 26 `fu-*` screenshots that matter most in `docs/test-results-15/`. The other 30 it names aren't in the repo, as they'd add 19 MB and nothing to what it says. My own checks of what it found are under Looks wrong.

---

### Segue DJ: first-time user report

**Started:** 17:04:26, when I opened the app.
**Stopped:** 18:00:46, my last touch, pausing the last deck.

The 45 minutes were up at 17:49:26. From about 17:47:40 to 17:53:50 I was mostly reading my own screenshots back, then I went back into the app until 17:57:30 to re-check notes that looked wrong. That comes to about 48 minutes of actual use.

**The app never crashed or froze, and I never had to restart it.**

**How far to trust this**
- "Worked" only means what I saw: keys, numbers, waveforms and meters. I never heard anything.
- I saw the app as still frames, one every few seconds, so brief things may have passed unseen.
- Each tool call takes a second or more, so durations include a slow finger. Quick double-taps aren't a fair test.
- Times come from the screenshot clock and are good to within a few seconds.
- "Live" means I read something on screen but no saved screenshot shows it.
- My running notes had mistakes. Sections 1 to 6 are checked against the screenshots. Section 7 lists what I got wrong. The raw notes are at the end, uncorrected.

---

#### 1. Every moment I wasn't sure what to do

**1. Adding music (17:04:30, about 5 s).** I wanted to add my music. The empty screen says "Tap the blue button above", but two things up there are blue: BROWSE and a tray icon. I guessed the tray and was right. The Files picker was easy from there. `fu-empty-library.png`

**2. Finding the decks (17:05:04, about 15 s).** I'd pressed "1" on a track and wanted to see the deck, but the list stayed put. I tried the waveform icon, which looked like "deck view", and got Recordings. Then I tried BROWSE, which turns out to be a switch hiding the list. Pressing a button called BROWSE to reach the decks felt backwards. `fu-waveicon-is-recordings.png`, `fu-decks-first-look.png`

**3. Choosing a second track (17:05:52, a few seconds).** I wanted something to go with the first track and tried KEY. The list shrank to the track already on the deck, because nothing else matched. Live.

**4. MIX started something big (17:05:57).** I took MIX for another filter like its neighbours, KEY, ±6% and NEXT. It started an automatic mix through the whole library, with no confirmation. It was harmless and clearly announced, but I hadn't meant to start it. On its side the same button reads "▶ MIX", which I'd have understood. `fu-mix-on.png`, `fu-landscape-browse.png`

**5. "MIX 47%" (17:06:10 to 17:06:42, about 30 s).** I read this as "the blend is 47% done". It's actually how far the track's split into stems has got. Pressing ? told me. `fu-help-mix.png`

**6. Was that the mix? (17:07:25 to 17:08:33, about a minute of watching).** I waited to see my first automatic blend, but the first track simply ran out as the second started. Going by the counters they overlapped for about 5 seconds. No fader moved. The reason, which I only worked out later, is that the next track's stems weren't ready, and a move seems to wait for them. So a newcomer's first MIX can be little more than a hard change. `fu-help-mix.png`, `fu-automix-first-change.png`

**7. Understanding section labels (17:05:20 to 17:37:30).** "CHORUS 28.4" sat on screen for half an hour before I asked help. It means bars and beats into that section. `fu-decks-first-look.png`

**8. MORE (17:11:45, about 15 s).** I wanted to see what was under MORE. Each press swaps to one hidden page: MEM, SLICER, JUMP, SAMPLE. It took four presses to learn the list, and the tab's name changes as you go. MEM's blank pads gave no hint of their use until help. `fu-mem-page.png`

**9. SLICER and ROLL looked dead (17:11:15 and 17:27:00, about a minute in all).** I tapped the pads and nothing happened, so I thought they were broken. Help says to hold them. They look just like CUE and LOOP pads, where a tap works, and FX pads, where a tap stays on. `fu-recheck-roll-held.png`

**10. What was AUTO doing? (17:13:02, not settled until 17:39:00).** I watched the faders to learn how it mixes. Deck 1's meter fell while its fader stayed up and the crossfader stayed in the middle, so I couldn't see why. It only made sense 26 minutes later, when I happened to have both decks on the STEMS page and could see pads dim and sweep. `fu-auto-echo-silent.png`, `fu-loopbuild-stems-dim-filter-label.png`, `fu-autodj-seen-through-stems.png`

**11. Did my thumbs-up count? (17:13:35, about 20 s).** The message simply vanishes with no acknowledgement. I only found out from the help list that ratings count. `fu-auto-echo-silent.png` shows the buttons.

**12. Where is the tempo fader? (17:15:05, about 10 s).** It isn't on the pads view. You press JOG. Help had told me, or I'd have taken longer. `fu-manual-mix-done.png`

**13. Finding cue names (17:17:05, by accident).** I wouldn't have looked under the BPM reading for "Cues and loops". Renaming and recolouring a cue worked first go once I was there. `fu-cue-renamed-recoloured.png`

**14. Reverse appeared stuck (17:22:21, about 15 s).** With REV on, the deck ran back to 00:00.0 and sat there with REV still lit. I thought it was stuck. On my re-check at 17:54, pressing Play gave a clear message: "Deck 2 is at the start. Turn REV off to play it forward." I just hadn't pressed Play the first time. `fu-rev-parked.png`, `fu-recheck-rev-at-start.png`

**15. Asking help how to do something (17:23:40, about 15 s).** I searched "how do I" and "transition" and got No Results both times. Searching the word on a control does work. `fu-help-search-bass.png`

**16. "Touch a control to take it back" (17:25:40 to 17:26:18, about 40 s).** I read this as "touch anything to cancel". Dragging the crossfader gave no message and the move carried on. Dragging a knob gave "That's yours now. Auto DJ carries on with the rest." So it works one control at a time. When the move ended, the knob I'd been told was mine went back to centre. I reproduced this at 17:56:31 to 17:57:17, and both times it was the outgoing deck's knob. `fu-takeback.png`, `fu-recheck-thats-yours-toast.png`, `fu-recheck-knob-reset-after-yours.png`

**17. Getting back from 85 BPM (17:30:58 to 17:31:30, about 35 s).** SYNC had pulled a 126 BPM track down to 85, half of 170. When the other deck ended, this one stayed at 85 as the new master. Help says to double-tap the fader, and my two taps didn't count, which may be my tool. Dragging near the middle snapped it to +0.0. `fu-sync-halftime.png`, `fu-stuck-at-85.png`

**18. Mixer sheet knobs (17:35:00 to 17:35:40, again 17:48:56 to 17:49:07, about a minute in all).** I wanted to adjust TRIM. Ordinary drags moved the sheet instead of the knob. Three tries on each of TRIM 1, TRIM 2 and MASTER did nothing. Pressing, waiting half a second, then dragging slowly moved TRIM 1 by only a tick. The same drag worked first time on the main screen's knobs, but my tool's timing may play a part. The sheet also covers the meter I'd want to watch. `fu-mixer-sheet-knob-fight.png`, `fu-mixer-sheet-trim-barely-moved.png`

**19. Playing a playlist (17:40:40, not solved).** I wanted MIX to play my one-track playlist. It said "You've played the rest of Friday. To go round again, stop the deck and press MIX." (live). Earlier plays of that track seem to count as used up, and nothing in the list shows which tracks are. `fu-played-the-rest-of-friday.png` shows the playlist but not the message.

**20. Did the wheel do anything? (17:41:00 to 17:42:00, about a minute).** Nothing on screen changes when your finger is on the record. I had to test it with numbers. With SLIP off, about 6 s that included a hold moved the time only 1.8 s. With SLIP on, about 10 s with a hold moved it 9.9 s. So it works, and SLIP does what help says, but you can't see it. No screenshot.

**21. Stopping AUTO part-way (17:43:30).** I wanted to go back to how things were. Pressing AUTO during a move gave "Auto DJ stopped. Deck 1 is on." (live). It jumped to the end, with the track that had been playing now stopped. Pressing it before the move starts just says "Auto DJ off." and leaves everything alone. `fu-auto-stopped-midmove.png`

**22. Previewing a track (17:45:15, not solved).** I tapped a row hoping to hear it and nothing happened. I never found a way to hear a track without putting it on a deck, though one may exist. No screenshot.

**23. "Next track now" (17:46:15, not solved).** Mix showed about 98 bars to wait, roughly two to three minutes. I couldn't find a "go now". Loading a different track ended the whole mix: "Mix off: the track changed." (live). `fu-mix-off-track-changed.png`

**24. Finding out what I'd played (17:46:30).** History is every time a track went on a deck, including ones Mix loaded and ones I loaded and never played, with no times. `fu-history-is-every-load.png`

### What the help did and didn't do

- **What it did:** pressing ? then touching any control answered nearly everything about what a control does. I didn't catch it being wrong about a control. It's the best thing here (see section 5).
- **Also useful:** the "What everything does" list in Settings searches by word and explains the Auto DJ's moves.
- **What it didn't do:**
  - It never says when you'd want a control, or how to mix two tracks. There is no "start here".
  - Searching only works if you already know the app's word. It calls a transition a "move".
  - Its SYNC text, as I noted it, doesn't warn about half-speed.
  - It didn't warn me that BRAKE and BACKSPIN stop the deck.

---

#### 2. How long each stage took

| Stage | Clock | From opening |
|---|---|---|
| Opened | 17:04:26 | 0:00 |
| Music in: 5 tracks listed | 17:04:52 | 0:26 |
| Titles, BPM and key shown for all 5 | by 17:04:58 | 0:32 |
| First track on a deck | 17:04:59 | 0:33 |
| Found the decks | 17:05:19 | 0:53 |
| First sound: Play pressed, time running | 17:05:28 | 1:02 |
| Meters moving (I checked at this time, they may have moved sooner) | by 17:05:35 | 1:09 |
| First automatic mix started (by accident) | 17:05:57 | 1:31 |
| First two tracks playing together, automatic, for about 5 s (worked out from counters) | about 17:07:46 | about 3:20 |
| First move from one to the other, automatic, not much of a blend | about 17:07:52 | about 3:26 |
| First two tracks together by my own hand, tempos synced | 17:09:41 | 5:15 |
| First move by hand: crossfader all the way across | 17:10:11 | 5:45 |
| First full AUTO move I asked for, started | 17:12:46 | 8:20 |
| First AUTO move finished | about 17:13:30 | about 9:05 |
| First proper hand blend: synced, bass taken out, crossfader across | 17:15:39 | 11:13 |
| Recording started | 17:15:56 | 11:30 |
| Recording saved and in the list | 17:18:21 | 13:55 |
| Finally saw how AUTO works | 17:39:00 | about 34:30 |
| Repeat hand blend with no help, about 25 s from load to finish | 17:45:13 to 17:45:38 | about 41:00 |

Splitting stems took roughly 2.5 to 4 minutes a track on this simulator, judging by the on-screen percentages. An automatic move waits for that, so it matters early on.

---

#### 3. What I still can't explain, and wording that was wrong or no help

### Still can't explain
- Why AUTO picks one move over another. I saw Brake drop between tracks far apart in tempo, and Loop build and Echo throw between closer ones, but also Loop build from 170 to 148. The app never says why.
- How long AUTO will wait. I saw counts from 4 to 33 bars.
- What counts as "played" for NEXT and MIX. Nothing in the list shows it.
- What NEXT's order is based on. Its top pick on one occasion was 5A against a 11A deck, and no reason is given.
- How much to trust section labels. A track can read CHORUS 1.1 at its very start, and sections run past 50 bars. At 17:11:10 a label went from CHORUS 34.2 to CHORUS 28.1 just as the stems finished.
- What the deck meters measure. A deck's meter stays high with the crossfader hard over the other way, yet falls during an AUTO move with its fader up. I don't know why. `fu-crossfaded-to-1.png`, `fu-hand-mix-eq-swap.png`
- Why AUTO moved the crossfader to centre before a move, but left it where I put it during one.
- What the 1/1 beside LIST on the MEM page counts. `fu-mem-page.png`
- What Smooth and Scratch crossfader curves, or Match Track Loudness, actually do. Settings doesn't say.
- A dim pause icon on Play for a moment just after letting go of a held CUE. It looks like a passing state.
- FILTER, DUB, SPACE, NOISE, CRUSH and PITCH: I can see the knob's label change but can't tell what they sound like.

### Not tried
Finding recordings in the Files app, Save or Restore a Backup, a real XML library import, real headphones or SPLIT with a real splitter, haptics, and sharing a recording.

### Wrong, misleading or no help
- **"While this is lit, the music won't change"** (help mode). A running Mix went on and changed tracks while I was in help at 17:07 to 17:08. It only means your touches won't change it.
- **"MIX 47%"** reads as blend progress, but it's stem progress. The same button also shows bars left, "..." and nothing, so it has four states and a tiny label.
- **"The key's counting down the bars"** and help's "The key shows bars to the next move". Here "key" means a button, in an app where KEY also means musical key, the KEY filter, the KEY lock button and KEY SYNC.
- **"Touch a control to take it back"** reads as cancel. It means that one control only, and only until the move ends.
- **"That's yours now"**, then the knob returns to centre by itself.
- **"Nothing here is in key or close in tempo"** was untrue on the screen I got it on. Severe Tire Damage was in key and Skylander and Gepzene were close in tempo. Nothing was both. It also says "IN KEY" and "±6% BPM" where the upright buttons say "KEY" and "±6%". `fu-nothing-fits.png`
- **"You've played the rest of all your tracks"** reads oddly. "The rest of Friday" is worse when I'd never played Friday as a list.
- **"5 tracks" and "4 tracks to go"** appear around the same moment. One is already on a deck, I think.
- **Jargon in the messages:** Echo throw, Loop build, Brake drop. Help explains them, but only if you search that exact word.
- **"BROWSE"** is also how you get back to the decks.
- **"Restore the Original Sound"** is in warning red, though it's a safe undo.
- **The word "CUE"** covers the big button, a pad page and the headphone send, which only has a headphone icon.
- **BRAKE and BACKSPIN** sit in the FX grid among effects that stay on, but they stop the deck.

---

#### 4. Anything that looked broken, however small

| Time | What I saw | Screenshot |
|---|---|---|
| 17:11:10 | Section label jumped from CHORUS 34.2 to 28.1 as stems finished, with no explanation | none saved |
| 17:13:35, 17:24:45 | Thumbs up and down give no acknowledgement | none of the tap |
| 17:14:40, 17:46:30 | History lists tracks once per load, Skylander many times, with no times | `fu-history-is-every-load.png` |
| 17:18:21 | Tracklist says Houston is 5A, though it played at 10A with KEY SYNC. BPM is as played, key isn't | `fu-recording-tracklist.png`, `fu-manual-mix-done.png` |
| 17:19:00, 17:50:41 | "MASTER" names a deck with both decks stopped | none saved |
| 17:24:10 | AUTO silently dropped SYNC and the tempo I'd set on the incoming deck | `fu-brake-drop-done.png` |
| 17:26:18, 17:57:17 | Knob I was told was "yours" returned to centre at the end of the move | `fu-recheck-knob-reset-after-yours.png` |
| 17:28:00 | Sampler pad sheet's Name was blank though the pad said AIR HORN | none saved |
| 17:29:55 | BPM on the platter is hard to read over cover art | `fu-sync-halftime.png`, `fu-manual-mix-done.png` |
| 17:30:58 | Synced deck stayed at 85 BPM (-32.54%) as the new master once the other deck ended. Possibly by design, but nothing flags it | `fu-stuck-at-85.png` |
| 17:32:22, 17:46:00 | "5 tracks" against "4 tracks to go" | `fu-mix-follows-sort.png` shows the second only |
| 17:32:50 | With RGB waveforms chosen, a deck on the STEMS page keeps its four colours until you leave the page | `fu-hand-mix-eq-swap.png` (deck 2 on STEMS, deck 1 not) |
| 17:33:02 onward | Messages cover the top waveform's section label | `fu-del-undo.png`, `fu-auto-echo-silent.png` |
| 17:33:54 | Next Mix track parked at 128 when its own speed is 126, with SYNC unlit | `fu-mix-next-track-at-128.png` |
| 17:35:00, 17:48:56 | Mixer sheet knobs: drags move the sheet instead (may be partly my tool) | `fu-mixer-sheet-knob-fight.png`, `fu-mixer-sheet-trim-barely-moved.png` |
| 17:35:53 | LIM lit red with both tracks at default levels. Worrying for a newcomer, gone in seconds | none saved |
| 17:39:00, 17:56:25 | During a move, one deck's knob reads FILTER while the other reads PITCH, which looks like a mistake | `fu-loopbuild-stems-dim-filter-label.png` |
| 17:43:50 | Tracklist reads "Gepzene — Gepzene - Can't be Serious" | `fu-tracklist-title-doubled.png` |
| 17:48:26 | For one frame after letting go of a ROLL pad, RELOOP and EXIT overlap and the size number blurs. It's a passing fade. Mid-hold is clean, and so is the frame after | not saved in the folder. See `fu-recheck-roll-held.png`, `fu-roll-after-release.png` for the clean states |

---

#### 5. The best and worst thing for a newcomer

**Best: the ? button.** You press it, then touch anything, and it tells you what that does in a sentence or two, in plain words and honest about limits. The other messages share that voice: "Mix off: you started deck 1 yourself." and "Deleted hot cue A", with an UNDO button. I never felt unsafe trying things.

**Worst: the Auto DJ changes things without leaving a trail you can follow.** Faders and the crossfader mostly stay still while the sound changes. Tempos, start points and knobs change without a word. One small button shows four different things. Stopping it can jump to the end. It took me 34 minutes, and a lucky choice of page, to see what it was actually doing. The controls you'd watch to learn from it tell you almost nothing.

---

#### 6. What I can't un-know

- **The name "Cheeks".** My setup showed a working folder `/Users/nikhil/Cheeks`, cache folders `cheeks-autodj` and `cheeks-stems`, and the simulator is called "iPhone SE Cheeks". The home screen also showed a "CheeksUITes..." icon. So before opening anything I had a project name, plus hints of an auto DJ and stems. I didn't open any of those folders. Inside the app I only ever saw "Segue DJ", on the splash, the empty library, Recordings and Settings.
- **I know far more about DJing than the brief says.** I read 5A and 12B as key codes straight away, and I already knew stems, hot cues, sync and master, quantise, slip, key lock, EQ bass swaps, and terms like echo out and brake. So where my notes say "I'd never guess" or "words I don't know", that's my estimate of a newcomer, not something I went through. A real beginner would struggle more with Q, SLIP, KEY, TRIM and "Echo throw". My 11-minute hand blend is faster than theirs would be.
- **What I left out.** I read no source code, docs, git history or project folders. Besides this report and my screenshots I read nothing else on the Mac. I also made one rename inside this folder (see section 7).

---

#### 7. Corrections to my running notes

These are the raw notes below. Where they disagree with the sections above, the sections above are right.

- **17:04:51 and 17:05:00:** I said the BPMs and proper titles filled in when I pressed "1". Wrong: `fu-library-loaded.png`, saved before that press, already shows them. Analysis finished by itself within about 6 s.
- **17:05:20:** I wrote "Stems 32%". The saved frame says 44%, a moment later.
- **17:17:12:** I noted "Stems 100% · 5 s" as a mismatch. No frame backs it up, and the closest saved one reads "Stems 97% · 5 s" (`fu-two-playing.png`). Please ignore it.
- **17:22:21:** I wrote that the REV deck showed a dim pause icon. Wrong: `fu-rev-parked.png` shows a Play triangle. The theories I built on that at 17:37 and 17:38 ("moving, but not really playing") are withdrawn, including my claim that BACKSPIN shows the same icon, which I can't back up.
- **17:27:25:** I said RELOOP was ghosted under EXIT "during the hold" and cited `fu-slicer-after-hold.png`. Wrong on both: it's one frame just after release, and that file doesn't show it. I renamed one screenshot to `fu-roll-after-release.png`, because it was clean and its first name said otherwise.
- **17:13:10:** `fu-auto-echo-silent.png` shows the end of the move, not the middle I described. The middle was live only.
- **17:26:10:** `fu-thats-yours-now.png` actually shows "Loop build done". The "That's yours now" message is in `fu-recheck-thats-yours-toast.png`.
- **17:31:30:** "four presses to get back to ±6" was never tested, and help suggests one press may do it. Withdrawn.
- **17:42:30:** I said the filled key pill hadn't been visible in the first half hour. Wrong: it's in `fu-landscape-browse.png` at 17:22.
- **17:44:40:** I quoted "No clean way in from here. Deck 2 starts when this one ends." and said deck 2 started about 4 s later. The saved frame reads "No clean way in. Deck 2 just started." and the counters suggest deck 2 started right when I pressed AUTO, with deck 1 running on about 4 s before stopping at -00:04.0. `fu-no-clean-way-in.png`
- **Other times in the raw notes** are up to about 10 s out. Use the table in section 2.
- **Screenshots that don't show the message my note gives:** `fu-recording-tracklist.png` ("Saving your mix"), `fu-brake-drop-done.png` (the "done" message), `fu-mix-follows-sort.png` ("Up next"), `fu-mix-on.png` ("Up next"), `fu-mix-off-track-changed.png`, `fu-played-the-rest-of-friday.png`. All of those were live.
- **Other speculation, please ignore:** "Exhilarate dropped with about 15 s to go" (17:33:40) and "anything loaded counts as played" (17:20:00).

---

#### Raw running notes (uncorrected)

- 17:04:26 Splash: a platter with SEGUE DJ. About a second or two.
- 17:04:30 Landed on an empty library (fu-empty-library.png). "No music yet. Tap the blue button above..." There are TWO blue things at the top: BROWSE (top left) and a download-tray icon (right). I guess the tray, because BROWSE looks like the tab I am already on.
- 17:04:34 Tapped the tray icon: a menu, "Music files..." and "DJ library (XML)...". Took "Music files". Files picker opened straight on a folder called My Music, with my 5 tracks. Select All, Open. Easy.
- 17:04:51 5 tracks in the list (fu-library-loaded.png). 25 s from opening. BPM and KEY show "..."; I assume it is working them out. Each row has buttons 1 and 2. I read them as "load to deck 1 / deck 2". Artist says "Unknown artist" on all 5, and three are titled jam1280420 etc. (that is the file name).
- 17:05:00 Tapped "1" on Exhilarate. The list then turned real: titles and artists filled in, BPMs and keys appeared, row went blue, "MASTER 1 170.00" appeared top. Tip appeared: "New to this? Press ? and tap anything to see what it does." It sits on top of the TITLE/BPM/KEY headings.
- 17:05:05 MISREAD: I wanted the decks. The waveform-looking icon next to BROWSE looked like "the deck view" (BROWSE = list, waveform = decks). It opened "Recordings" sheet instead (fu-waveicon-is-recordings.png). Now I do not know where the decks are.
- 17:05:20 Closed Recordings. Tried tapping BROWSE (the only other thing up there that looked like a mode switch). It is a toggle: blue = library covering the decks. Tapping it off reveals the full deck/mixer/deck layout (fu-decks-first-look.png). Lost about 20 s. Nothing said the decks were behind the list. The word BROWSE being the way to get to the DECKS is backwards in my head.
- First look: everything is on one screen, very dense but recognisable: deck 1 on top, mixer, deck 2 upside-down-ish mirror below. CUE and Play big and familiar. "Stems 32% · 40 s" is ticking on deck 1. "CHORUS 1.1" on the waveform. It already knows the song sections?
- 17:05:29 Pressed Play on deck 1 (first sound by the evidence on screen: time counting, playhead moving, meters green by 17:05:33 once the track's opening silence passed).
- 17:05:40 Back to list to find a second track. The "1" buttons are now grey while deck 1 plays. Good, no accident possible (though nothing explains why).
- 17:05:45 Tapped KEY: list drops to just Exhilarate itself (12B). I get it: "keys that go with what's playing". With only 5 tracks it hid everything including the sensible choice. Turned off.
- 17:05:50 Tapped MIX (fu-mix-on.png): "Mixing through all your tracks, 4 tracks to go. Up next: Skylander." And a line at the bottom stays. So MIX = automatic mix? I did not expect that from a word like MIX next to filter buttons (KEY, ±6%, NEXT look like filters; MIX is not). It started something big from a small button with no confirmation, though harmless and clearly announced.
- 17:06:10 Closed browser with MIX running. Skylander has loaded on deck 2 by itself but is parked at 00:01.8, CUE lit. Centre button AUTO became "MIX 1%", then 4%, 12%... I read "MIX 4%" as "the crossfade is 4% done", i.e. it's mixing. It isn't. It is the stem split for deck 2 (same number as "Stems 4%" on deck 2). That only became clear from help.
- 17:06:30 Pressed ? (fu-help-mix.png). Help mode is the thing I'd want. "While this is lit, the music won't change". Tapped MIX 12%: it says the % is stems splitting. Wording "The key shows bars to the next move" - "key" is confusing in an app that also has musical KEY.
- 17:07:40 Help: SYNC ("BEAT SYNC ... Started from stopped, its bars line up too. Moving the tempo fader takes it off.") Useful. Help popup moves to the opposite end of the screen from what you touched, which is clever.
- 17:07:50 Help: JOG. "Swaps this deck between its pads and its jog wheel". It really did swap the deck to the platter view, though I'm in "controls only explain themselves" mode (allowed: "keys that move between pages").
- 17:07:55 While in help, the automatic mix moved on by itself: Exhilarate ran down to its end (-00:05.8 and then the track gone), Skylander started on deck 2, and Gepzene loaded onto deck 1 (fu-automix-first-change.png). MASTER changed to 2 / 125.00. "MIX 0%", Stems 0% for Gepzene. So the help promise "the music won't change" is only about my own touches. A newcomer might be startled.
- OBSERVED: MIX started at 17:05:50 with Exhilarate about 20 s in, track had 2:25 total. The automatic "mix" happened only as Exhilarate ended. Skylander's stems were at about 64%: the two overlapped for a few seconds at most from what I could see. Fader and crossfader did not visibly move while I watched (centre, both up). I did not see a blend. I only sampled every ~10 s though.
- 17:08:35-17:09:00 Help on MIXER opens a sheet of extra controls (TRIM 1/2, MASTER, CUE/MST, LEVEL, SPLIT, FILTER with a cycle arrow). Help explained each. The sheet stays usable in help mode. "It needs SPLIT on" is honest. I would not have found what "FILTER ↻" does without help.
- 17:09:10 Wanted BEAT SYNC on the deck showing the wheel; hit MASTER by mistake (they are stacked). Nothing visible happened on a stopped deck, no feedback.
- 17:09:30 BEAT SYNC on deck 1 (Gepzene): BPM went 128 → 125.00 in blue, tempo fader jumped to -2.3. Clear.
- 17:09:35 Played deck 1. Toast: "Mix off: you started deck 1 yourself." Very clear and it reassured me that the automation had let go. AUTO button back. First time two tracks played together by my own doing (fu-two-playing.png). All 4 meters lit. Now I understand the meter: deck 1 / master L+R / deck 2 (a guess from which columns light up).
- 17:10:05 Dragged crossfader full left to deck 1. It moved fine (fu-crossfaded-to-1.png). There's nothing else on screen that says deck 2 is now silent: deck 2's meter is still high, waveform still bright, MASTER still "2 125.00". First manual move from one to the other: 5:40 after opening (a lot of that was reading help).
- 17:10:35 Pressed Pause on deck 2. "MASTER" moved to 1 by itself. Deck 1 stayed at 125.00 (it's really a 128 track, -2.3%), and the BEAT SYNC light went off once deck 2 stopped. No word that the tempo stayed changed.
- 17:10:45 CUE pads: tapped empty A: turned red with "0:57", red flag on waveform. Tapped again: jumped back. Exactly what I'd expect. 
- 17:11:00 LOOP pads: 1/4 to 32. Tapped 4: orange region on waveform, RELOOP turned to EXIT, "4" lit up. Time sat between two values. Unambiguous. EXIT released it cleanly.
- 17:11:10 Section label changed under me: at 00:52.5 it said CHORUS 28.4, at 01:02.8 CHORUS 34.2, and at 01:07.8 CHORUS 28.1, exactly when "Stems" hit 100% and the overview strip changed its colours. So the song map is revised after the stems finish. No word about it. I can't tell what the number after the section name means (bar.beat since the section began?).
- 17:11:15 ROLL pads: quick tap on 1/4 did nothing I could see. Presumably it's a hold-down control.
- 17:11:20 STEMS page: lovely. Vocal/Inst/Bass/Drums, Solo row, ACAPELLA / NO VOCAL / BEAT / ALL, "AI" with a green dot. Waveform repaints to show what's left. DRUMS off: gold part vanished from the waveform. ACAPELLA: waveform nearly flat and meter almost empty (this track seems to have nearly no vocal). Pressing ALL restored. Best "wow" so far.
- 17:11:30 FX page: 12 effects on 2 rows. Toast "FX pads slide: up and down for depth, left and right for the beat." appears once, I think, over the waveform. Tap latches on (blue, little dot on FX tab). Slide changed 1/2 to 1 and DEPTH grew. V/I/B/D buttons on FX row: no idea until help. OUT: no idea.
- 17:12:00 MORE > cycles through four hidden pages one press at a time: MEM (SAVE CUE, SAVE LOOP, blank pads, LIST), SLICER, JUMP, SAMPLE (AIR HORN, SIREN...). No way of seeing the list first; the tab label just changes. I had to press 4 times to learn what's there. MEM (fu-mem-page.png) has blank pads, nothing tells me what it's for: is it "memory"? "MEM >" isn't a word. AIR HORN lit red when tapped.
- 17:12:30-17:13:30 Another help pass. Beat blocks (the small coloured bars between the waveforms), LIM, meters, waveform, overview, BPM, CUE-to-headphones, SAVE CUE/LOOP, LIST, DEL, AUTO. All clear, short, and honest about limits ("One output, like AirPods, can only play the mix"). Help answered every question I had. "AUTO: mixes the playing deck into the other... MIX in the browser does a list." So AUTO = one transition; MIX = a playlist.
- Word "CUE" means at least 3 things: the big orange CUE button, the CUE pad page, and the headphone send (which has only a headphone icon on screen and is called CUE only in help).
- 17:12:52 Pressed AUTO. It's counting: AUTO 11, 3, 1 (bars). Toasts narrate it step by step (fu-auto-pressed.png): "Echo throw next. The key's counting down the bars." then "Crossfader to the middle, to hear both." and the crossfader actually jumped from my far-left to the middle, then "Echo throw starting. Touch a control to take it back." I love being told what it's doing, and this is how I'd learn. Problem: "echo throw" and "the key" aren't words I know (I'd say "button"; KEY is a music thing here).
- 17:13:02 Deck 2 picked a start ("CHORUS 1.1", jumped to 00:31.2) and started right on "AUTO 1". Waveform dark for ~4 s, then bright. Nothing explains the dark: I think it's being silenced / ducked for the first bars.
- 17:13:10 Deck 1's meter has gone dark, deck 2's is high. But deck 1's waveform is still bright, its fader is still at the top, its time still counts red, MASTER still says 1 (fu-auto-echo-silent.png). AUTO is lit with no number now. Help said "with the controls you can see", but I can't see which control silenced deck 1.
- 17:13:30 AUTO finished: toast "Echo throw done. Deck 2 is on. More like that?" with thumbs up/down. Deck 1 stopped itself at -00:16.8, BPM back to 128, CUE lit. Crossfader stays middle. I tapped thumbs up; toast vanished with no acknowledgement. I wondered if it took. I found out from Help that it does ("Auto DJ leans towards what you like... Ratings stay on your device").
- 17:13:50 Settings (gear). Plain, short, well explained. "What everything does": a searchable list of every control and of the Auto DJ's moves (BASS SWAP, LOOP BUILD, ECHO THROW, VOCAL TEASE, VOCAL RIDE) (fu-help-search.png). Searching "throw" gave me what I needed. Search for "next" gives me everything with the word "next" in it, the NEXT button isn't first.
- Dismissed Settings by dragging the title by accident; no harm.
- 17:14:40 Library: small sidebar-looking icon next to the tray opens a list menu (All tracks / History Nov 4 / New playlist). "History Nov 4" appeared by itself: Exhilarate, Skylander, Gepzene, Skylander. It logged Skylander twice (once for load by Mix, again for mine?). Once you're in History there is no title saying where you are; the icon just goes blue. Delete Playlist in red right there on history.
- 17:14:50 NEXT: reorders the list, puts Houston first, hides what's playing. It's a suggestion list. No reason given for the order, and the top track's key doesn't match what I was taught by the KEY filter (5A against 11A). I'd assumed compatible. I took its word.
- 17:15:05 JOG view holds a lot that PADS view doesn't: tempo fader, range, platter, BEAT SYNC, MASTER, BEAT JUMP, Q, SLIP, KEY, REV, key shift, KEY SYNC. The button to come back reads PADS. So tempo fader isn't visible until you press JOG. I went looking for it.
- 17:15:15 Tempo fader down = faster (133.07). Fine for DJs, my first drag went the way I'd guessed. Double-tap (two separate taps, slow in this tool, so maybe not a fair test) didn't reset to 0.
- 17:15:25 BEAT SYNC to 125. KEY SYNC: Houston goes from 5A to 10A, "-1" shows. Understood from the label.
- 17:15:35 Play on deck 1, Q on. Beat blocks both red together, centre tick goes green: visual proof they're aligned. Really satisfying (only as far as my eyes can tell).
- 17:15:45 Dragged Skylander's LOW knob down (vertical drag), then crossfader to deck 1. Blue ring on knob shows it's off centre. Moved LOW back up by dragging. First hand-made blend (fu-manual-mix-done.png) at 11:20 from opening.
- 17:15:55 Pressed REC: top bar goes red with a running time. No confirmation. Immediately records. After a bit it reads "0:10 · 1", I don't know what the ·1 is (tracks so far?). Nothing in help says.
- 17:16:00 AUTO with both decks playing: refuses, helpfully: "Auto DJ brings in a stopped deck. Stop the one you want next." I stopped deck 2, pressed AUTO. "Auto DJ is waiting for the stems. If this track ends first, deck 2 starts." AUTO shows 66%. Wait is about a minute. I now know why Auto wants stems, but I'd have preferred "start now without them" as a choice.
- Side effect: stopping deck 2 quietly made deck 1 MASTER and took it off BEAT SYNC. Only the two button colours changed. Tempo stayed.
- 17:17:05 Tapped BPM on a deck: a menu with Cues and loops / Save cue as memory cue / Beat grid (Set downbeat here, Grid 10 ms later/earlier, BPM ±0.1, Halve/Double). I wouldn't have looked under "BPM" for "Cues and loops", though the little arrow suggests a menu.
- 17:17:12 "Stems 100% · 5 s" displayed at the same moment (fu-time ~17:17:10). 100% with 5 s to go. Tiny, but a mismatch. Houston's stems took about 2:15 from the moment of loading, a 4:50 track.
- 17:17:14 Stems done: "Loop build next. The key's counting down the bars." AUTO 14. Deck 2's position snapped from where I'd left it (03:30) to 00:31.2 by itself; the row turned to CHORUS 1.1. So the Auto DJ chose to start Skylander's chorus. Nice. Pity it isn't announced. It also overrode where I'd stopped it.
- 17:17:11-17:18:00 Watched a whole "Loop build", with the LOOP page open. Honest: pad 4 lights by itself, RELOOP becomes EXIT, filter knob turns, LOW knob turns down, waveform flips to stem colours (fu-loopbuild-stems-knobs.png), the loop gets too short to see but the lit pad still says 4 (so "smaller and smaller loops" isn't shown on the pads). Then deck 2 runs dark (silent?) from 00:30.6, bright at bar start, deck 1 stops, knobs snap to centre. Toast: "Loop build done. Deck 2 is on. More like that?" I learned more from watching this than from reading. REC's "· 1" became "· 2": it's the count of tracks.
- Note: my earlier-noted clock times around 17:17 were a few seconds out. Use 17:16:56 for the "Loop build next" note.
- 17:18:10 Stop REC: "Stop recording? Stop and save / Keep recording". Good. "Saving your mix..." brief (fu-recording-tracklist.png). Recordings now shows it with a tracklist: Houston 00:00, Skylander 01:46, BPMs and keys. But Houston listed at 5A when it was played at 10A (I had key-shifted it -1 with KEY SYNC). Skylander was also playing at the start of the recording but faded out by my crossfader; that's handled sensibly. Also, the track that really finished the mix was clearly right.
- "A recording plays out loud, over the mix. To listen to one, stop both decks." Honest, and the play button is greyed out. Good message.
- 17:18:40 MY SLIP: wanted to close the ... menu by tapping away, tapped where Delete sat. It asked "Delete this recording and its tracklist?" with a single red Delete button and no Cancel; I tapped outside and it went away. The recording was safe. (No Cancel button is standard on iOS for a popover, though a newcomer might hunt for one.)
- 17:18:50 Rename worked. List row updates at once. The tracklist panel collapsed on rename.
- 17:19:02 Stopped both decks: the "plays over the mix" warning disappears and the play button turns white. Tapped: 0:04 counting, slider appears. Dragged to 1:01. Worked. Closing Recordings stops it and resets to the start with no word, fine.
- Label "MASTER 2 125.00" still sits at the top with both decks stopped. Nobody is leading anything. Tiny.
- 17:19:40 Long-press a track row: Load on Deck 1 / 2, Re-analyse, Delete from Library. Nothing tells you that exists but it's where you'd look. Loading on deck 2: the list instantly reordered itself under my finger because the leading deck changed (now Skylander on top). In a busy moment that would make me hit the wrong row.
- 17:20:00 Help in the browser: NEXT, KEY column, ±6%, KEY filter, MIX. All excellent. KEY column: "lights up when it goes with the deck that's leading" answers my question about the pink pill. So 5A next to a 5A goes solid. Help says MIX "goes on from there, then back for what's above it" so order on screen matters.
- Help says NEXT puts "what's been played" last. Severe Tire Damage has never played but sorts below played tracks: seems anything loaded counts as played. Small.
- 17:20:30 KEY + ±6% together: "Nothing fits right now. Nothing here is in key or close in tempo with what's on the deck. Turn off IN KEY or ±6% BPM to see the rest." (fu-nothing-fits.png). Great empty state. Tiny nit: "or" isn't quite right since it's "and"; there ARE tracks close in tempo. And the button says KEY but the message says IN KEY.
- 17:20:40 Playlist: New playlist > name > empty state tells me exactly what to do ("Go to All Tracks, press and hold a track, and add it from there."). Note Add to Playlist only exists in the long-press menu once a playlist exists. "Added to Friday." toast. Good.
- 17:21:10 Column headers sort (arrow appears). Key sort is 1A, 5A, 11A, 12B in proper number order. Search matches artist. All fine.
- 17:21:20 Waveforms: drag doesn't scrub a stopped deck that I can see (it nudged 0.8 s and resumed?), and tapping the overview strip jumps (Houston went to 03:53). Pinch zoomed in. Both undiscovered until I tried; help mentions them.
- 17:21:40 Headphone button on deck 2: lit it. Toast tells me honestly: "You'll hear the cue with SPLIT on and a splitter cable." Good. SPLIT toggles. FILTER button in the Mixer sheet cycles through DUB / SPACE / NOISE / CRUSH: the label itself is the choice. Nothing tells me what the FILTER knobs on the mixer are set to while the sheet is closed.
- 17:22:10 CORRECTION to my last note: closing the Mixer sheet, the FILTER knobs on BOTH decks are now labelled PITCH (fu-knob-renamed-pitch.png). So the knob does tell you. Nice. Cycle was FILTER > DUB > SPACE > NOISE > CRUSH > PITCH. It's a single choice for both decks. I don't know what "SPACE" or "DUB" sound like; the buttons don't say.
- 17:22:20 REV on a deck that had only played 2.4 s: it ran backward to 00:00.0 and sat there. CUE lit, dim green pause icon (not a play triangle), meter empty, MASTER still orange (fu-rev-parked.png). Is it playing? The button says it can be paused, the counter says it's not moving. Odd in-between state. Time 17:22:21.
- 17:22:40 Tried it on its side (fu-landscape.png): side-by-side decks, mixer in the middle, looks like a real controller. No wheel/tempo fader visible there either until JOG. Browser on its side (fu-landscape-browse.png) is much clearer than upright: a real sidebar (COLLECTION / PLAYLISTS), words instead of icons: IMPORT instead of tray icon, "▶ MIX" with a play triangle (so it's an action!), "IN KEY", "±6% BPM", a TIME column. Upright I never saw TIME at all. If upright had said IMPORT and ▶ MIX I'd have guessed both right first time. "History Nov 4: 6": six entries, and I played four tracks' worth. Unsure how it counts.
- 17:23:10 Settings again, slowly: Crossfader curve, Match track loudness (on, no explanation), Prepare stems on load (explained), Waveform colours, Haptics, Recording format, Library backups (fu-settings-backup.png). The backup paragraph is really good. It's the only place where the app says what happens if you delete it. Nothing here is required reading.
- 17:23:40 Help page is organised by control and it searches words on the screen, not tasks. "How do I" → No Results. "transition" → No Results (the app calls it a "move"). A newcomer doesn't know the word "move" means that. "crossfader" finds it. There's no "start here" or a "how to mix two tracks" section. Once you know a word it's great; you must already know the word.
- 17:24:10 AUTO with tracks 22 BPM apart (Houston 126, Severe Tire Damage 148): this time it picked "Brake drop" (a different move, with a short 4-bar wait), no tempo match. Deck 2's BEAT SYNC and -14.86% tempo that I had set were silently thrown away and the deck went back to 148 (I'd pressed nothing). So the app decides. I'd never guess "Brake drop" = "stop the track". It took ~14 s. Done: "Brake drop done. Deck 2 is on. More like that?" (fu-brake-drop-done.png).
- 17:24:45 Thumbs-down: toast vanishes silently, same as thumbs-up. Tapping a dim deck button on the list while that deck plays: "Deck 2 is playing. Stop it first." with a hand icon. Clear.
- 17:24:50 AUTO with Exhilarate loaded: "Loop build next... AUTO 33". Press AUTO again: "Auto DJ off." Clear. Deck 1 quietly moved its start point to 00:02.8 then back to 00:00.0. Press again: AUTO 26 and the same toast. It seems to count to a fixed place, so waiting is not always the same length. 33 bars is ~50 s of nothing on screen that says when. 
- Moving the crossfader during the countdown does NOT cancel, nor is it mentioned. I expected "Touch a control to take it back" to hold from the start. That toast only appears when the move starts. The "next" toast sits for the whole countdown, hiding deck 1's top label.
- 17:25:10 Help FX: "Twelve effects..." "TRANS: Chops the sound on and off, in time." "OUT: Ends the track on its own echo..." All clear; TRANS, ROLL, SPIRAL are unexplained by name but one tap in help fixes it.
- 17:25:40 "Loop build starting. Touch a control to take it back." Waveforms of deck 1 fade right down to nothing (it's parked, stopped) and deck 2 loops. Deck 1 hasn't started yet: I'm unsure what "take it back" covers.
- 17:25:45 I dragged the crossfader: it stayed where I put it (fu-takeback.png) but no toast at all this time.
- 17:26:10 I dragged deck 2's LOW knob. Toast: "That's yours now. Auto DJ carries on with the rest." (fu-thats-yours-now.png). Oh, that's it: one control at a time. I'd have read "take it back" as "cancels the whole thing". That's a really good line; it should be the one that appears first. And the crossfader drag got no such line.
- 17:26:18 Move ended: "Loop build done. Deck 1 is on." (fu-yours-then-reset.png). Deck 2's LOW knob, which the app had just told me was "yours now", is back at centre by itself. Crossfader did stay off-centre where I left it, so deck 1 isn't in the full mix and nothing says so. Also deck 1 went straight to its own 170 BPM from 148: no tempo blending. And deck 2 parked at 01:56.7. So what "yours" means isn't consistent: fader stays, knob doesn't.
- 17:26:40 MEM page: SAVE CUE: pad 1 fills, "0:37", red bookmark. SAVE LOOP with no loop: "Set a loop first, then save it." Tap a saved pad: jumps. LIST: sheet with the cue, tap to name it. "1/1" with ‹ › next to LIST: no idea what it's counting at first (it says 1/1 with one or zero memories?).
- 17:27:00 SLICER: tapped pads 1, 3: nothing visible at all; time carried on. Thought it was broken. Help: "Plays this eighth of the bar for as long as you hold it." So it needs a hold. ROLL the same. Both pages look identical to the CUE/LOOP pages where a tap IS the action, and nothing on the pad says hold. FX pages, by contrast, tap latches. Three different meanings of a tap on pads that look the same.
- 17:27:25 ROLL 4 held: lit, EXIT comes up and "4" orange in the loop bar. Time keeps counting through it, as promised ("the track keeps time underneath"). The word RELOOP stays ghosted underneath EXIT when you look closely (fu-slicer-after-hold.png): overlapping text during the hold. Happens with both ROLL and SLICER.
- 17:28:00 SAMPLE > SET > tap pad: sheet "Pad 1" with Name, One shot/Gate/Loop, Choose a File, Record the Master. Tapped Record the Master: it starts right away, sheet closes, the red SET button shows a count (0:00, then more). Tapped it to stop. AIR HORN is gone and pad reads "REC 1" (fu-sampler-rec.png): overwritten with no warning and no visible way to get AIR HORN back. Would a Reset be in that sheet?
- 17:28:30 Correction: after recording, the same "Pad 1" sheet gains "Restore the Original Sound" (in red). Press: AIR HORN is back straight away. So nothing is lost. A red label for a helpful undo is odd. The very first time I opened the sheet, Name was blank though the pad says AIR HORN.
- 17:28:40 The track I'd left playing ran to its very end while I was in the sheet: -00:00.0, big CUE lit, Play back to green triangle, meters dark, deck 2 waiting (fu-track-ended.png). Silence. The only warning was the time turning red around -00:27. It's what I'd expect, but nothing draws my eye if I'm looking at the pads. The waveform stays stuck at the end point rather than reset.
- 17:28:55 Pressing Play on the ended deck: it started from 00:37, not 00:00: the memory cue I'd tapped earlier has become its cue point. Fine, but if I'd wanted the start I'd have been surprised. Press CUE to stop: goes back there.
- 17:29:05 IN then OUT: IN goes orange, a marker appears; OUT and it's looping: EXIT lit, "11" on the size chip (beats, I work out). The ‹ › halves and doubles: 5.5, 11. Waveform shows the loop as an orange slab. Clear.
- 17:29:30 BPM menu: "Beat grid: 170.00 BPM at normal speed", Double/Halve/BPM ±0.1/Grid 10 ms earlier/later/Set downbeat here, Save cue as memory cue, Cues and loops... Halve changed it to 85.00 instantly and MASTER too. Double put it back. Plain and undoable. Nothing confirms it was saved. I have no way of telling if a grid is good or bad other than by eye.
- 17:30:00 Load Houston (126) on deck 2 with Exhilarate (170) playing. No stems wait this time: "Split tracks are kept". Pressed SYNC. It went to 85.00 BPM, -32.54%, tempo range label flipped itself from ±16 to WIDE and the fader moved (fu-sync-halftime.png). So it matches at half-speed: 85 is half of 170. Clever and I worked it out after a moment, but a third slower is a big change and nothing warns me. Help never said it might do this: its "BEAT SYNC" note says "Matches this deck's tempo to the master".
- The BPM number on the platter sits over the cover art here and is hard to read.
- 17:31:00 STEMS page again, tapped things in help: "AI" with green dot isn't a button. Solo D works: three others dim. ALL resets. Help for the JOG page: KEY = "Key lock". So the word KEY is now: the KEY column (musical key), the KEY filter in the browser, the KEY lock button on the deck, KEY SYNC, "KEY - +", and in toasts "the key's counting down the bars" (meaning the button). Six things.
- MASTER help: "A stopped deck can't lead, so the first one to start playing takes over." Answers my earlier question about why it moved. Very clear. SLIP, Q, the range all clear. Help has never been wrong or unhelpful about what a control does. What it doesn't do is tell me when I'd want it.
- 17:30:58 Deck 1 ended while Houston was synced to it at half-speed. Deck 2 became MASTER automatically and BEAT SYNC turned off, and it just carries on at 85.00 with the fader at -32.5 (fu-stuck-at-85.png). A 126 BPM track now plays at 85, and it's the master. Nothing says "this isn't its natural speed" except the small -32.54%. Now how do I get it back? No reset is labelled.
- 17:31:30 Help says double-tap the fader for the centre. Two taps through this tool didn't count (probably too slow, not the app's fault). A drag near the centre snapped to +0.0 and 126.00 with the fader dropped lower. So the snap works. Range stays on WIDE and I'd need four presses to get back to ±6.
- SLIP on + drag on platter: can't see much happen while my finger is off; time was still running on after. Unverified beyond that.
- 17:31:45 DJ library (XML): picker opens, all my music greyed out (right; I have no XML). The menu doesn't say whose library or from what app. Backed out with no harm.
- 17:32:08 Re-imported Exhilarate: "That track's already in your library." Clean. System picker: second time the select circles needed a firmer tap. That's iOS, not this app.
- 17:32:15 MIX with Houston playing: "You've played the rest of all your tracks. To go round again, stop the deck and press MIX." Told me exactly what to do, though "the rest of all your tracks" reads oddly. It covers the top of the list while it's up.
- 17:32:22 Did it. "Mixing through all your tracks, 5 tracks. Up next: Gepzene" while the strip at the bottom says "4 tracks to go". It restarted deck 1 by itself from the 0:37 memory cue, not from the top of the track, and replaced Houston on deck 2 with Gepzene parked at 00:09.5 with the label UP 1.1. Good if I'd wanted it; I didn't choose either. SLIP stayed on through the load (deck settings stick across tracks). AUTO button reads MIX 53.
- 17:32:50 Settings Waveform colours: 3-band / RGB, no explanation. Switched to RGB: deck 2 went yellow/green at once. Deck 1 stayed in the four-colour look because its STEMS page was open, until I left that page. So the page tab you're on changes what a waveform means. Nothing says so.
- 17:33:02 Hot cues while the mix counted down: A, B set. DEL lights red, tap A: "Deleted hot cue A", UNDO button in the toast, DEL un-lights itself (fu-del-undo.png). Lovely, exactly right. One thing: the toast covers the top waveform's section label each time.
- 17:33:40-17:33:54 Unattended Mix move, watched: "Echo throw into Gepzene". Deck 2's waveform runs almost black for ~4 s, then bright; deck 1's meter drops to almost nothing within ~4 s, deck 2's rises. Exhilarate was dropped with about 15 s to go. "Echo throw done. Deck 2 is on. More like that?" appeared. The very next track, Houston, had already been put on deck 1, parked at 00:22.8, reading 128.00 BPM (its own number is 126), with SYNC not lit (fu-mix-next-track-at-128.png). So a tempo was changed for me with nothing to show why. The button now reads MIX 77. Crossfader and channel faders never moved in any of this. I keep looking at them to understand the mix and they tell me nothing.
- 17:34:10 Pressed the blue MIX-number button: "Mix off. The track playing just carries on." Clear. (So the same button that says AUTO starts it and when it says MIX stops it.) Deck 1 Houston snapped from 128 back to its own 126 once it stopped, and to 00:00.0, so the tempo I'd noticed was the Mix's own, undone. Good clean-up.
- 17:34:20 NEXT with Gepzene playing: Houston then Skylander on top. Loaded Skylander on deck 1, SYNC: 128.00, Play. Green tick in the middle of the beat bar; red blocks line up (fu-beat-aligned-synced.png). It feels like a real thing I'm doing. This is the moment the app clicked for me as a DJ tool, rather than a robot.
- 17:34:50 Knob on the main mixer: drag up = PITCH knob sweeps, blue arc from the centre. Waveform shape doesn't change, so nothing else shows it's on. Reliable and clear. BUT...
- 17:35:00-17:35:40 Knobs inside the Mixer sheet (TRIM 1, TRIM 2, MASTER, CUE/MST, LEVEL): my ordinary quick drags moved the SHEET, not the knob (sheet jumps up then back). Three attempts each on TRIM 1, TRIM 2, MASTER: no change. A press, a hold of a third of a second, and a longer slow drag moved TRIM 1 only a little, with the sheet still riding up under my finger (fu-mixer-sheet-knob-fight.png). I can't be sure this is purely the app rather than my tool's timing, but main-screen knobs took the same quick drag first time. The sheet also covers both decks and the crossfader, so to raise TRIM while I watch the meter... the meter is hidden behind the sheet too. A sheet called Mixer hides the mixer. I also tapped Done where it had been before the sheet settled, missed, tried again.
- 17:35:53 LIM lit red for a moment with both tracks up and everything left at default (I'd only touched a filter). Help told me earlier it's a safety limiter. It's the app's own default mix hitting it, so it might worry a newcomer. It went out again within a couple of seconds.
- 17:36:05 BEAT JUMP on the wheel page: tap 4 and it becomes 8 (only goes up? I got 8 from one tap). I also missed the skip buttons once (they sit below their label). Back/forward both worked by the exact 3.75 s of 8 beats at 128. Precise. Nothing tells me whether Q matters here.
- 17:36:18-17:36:32 Pressed Home for 8 s and came back from the icon. Both decks had carried on playing (time moved by the right amount), same screen, no splash. Good. (Home screen also showed two icons, "CheeksUITes...". Not this app.)
- 17:36:50 Library while both decks play: long-press menu still offers "Load on Deck 1/2", tapping says "Deck 1 is playing. Stop it first." Re-analyse: BPM/key go to "..." with a shimmering title, toast "Analysing... again". While NEXT is on, the leading track isn't in the list at all, so I can't see what's on that deck from there.
- 17:37:10 Tap CUE on paused deck: sets the mark at 02:41.7 (the old cue is silently replaced). Hold CUE: meter lit while held and Play ring goes dim with a pause icon, back on release. Help's CUE text is the clearest description of this I've ever read: "On a stopped deck, marks this spot, and holding it plays from here until you let go. On a playing deck, goes back to the mark and stops." The dim pause icon also explains what I saw at 17:22:21 on REV? No: that REV deck was at 00:00.0 with nothing held. Still unexplained.
- 17:37:30 Help on waveform says the number counts bars in the section and UP is a build-up, DOWN a breakdown. So that's what CHORUS 28.4 means, finally. "CHORUS 53.4" on a track that has now ended; a 53-bar chorus sounds like a guess by the app. Overview help doesn't give a key for which colour means which section.
- 17:38:10 FX BRAKE and BACKSPIN: both lit for a moment then stopped the deck dead (BACKSPIN rewinds about a second first), so these are "end the track" effects, not latching ones like ECHO; they sit in the same grid. Help hadn't warned me; I got a stopped deck. At least obvious and recoverable. While BACKSPIN runs the Play button shows the same dim-green pause icon I saw at 17:22:21 with REV stuck at 00:00.0 and when holding CUE. So it seems to mean "moving, but not really playing". No word on it anywhere.
- 17:38:40 Discovery: the deck 2 screen with JOG off (PADS view) moves JOG and SYNC to the left of the title. Both decks then look the same and, for the first time, I can see the mix properly. I set both to the STEMS page and pressed AUTO. AUTO counted down, then:
- 17:39:00-17:39:28 Watched Loop build with stems showing (fu-loopbuild-stems-dim-filter-label.png, fu-autodj-seen-through-stems.png). Deck 1's four pads go dim. Deck 2 grows an orange loop. Deck 2's BASS pad sweeps out top to bottom (a coloured bar empties), LOW knob turns down with a blue ring, FILTER knob rises. Then deck 1 starts and its pads light up all at once. Deck 2's meter drops to almost nothing, though its waveform still looks bright. For the first time I can see what Auto does; before this I'd only seen numbers change. A beginner on the CUE page doesn't see any of this.
- Odd: during the move the deck 2 knob label is FILTER, while deck 1's stays PITCH. I'd set PITCH for both (17:22). Auto used a different effect on one side and the label says so, but it reads as a mistake if you don't know.
- 17:39:50 Stem pads are also faders! Tried it only because I'd seen Auto do it. Slide on BASS leaves a dim band from the top (fu-stem-pad-is-a-fader.png). Help confirms: "Tap to mute it or bring it back, and slide up and down to set its level." Nice. Nobody would guess from looking at a pad. And the level isn't a number. The band doesn't reach far visibly when set.
- 17:40:15 JUMP page: arrows and 1 / 4 / 16 / 32. Skipped forward by 32 and the count moved by what looks like 32 beats (no "bars or beats" label, I worked it out from the time). The MORE tab remembers where I last was and shows its name, and that's why I never saw "MORE" as a list. Also the waveform went back to RGB once I left STEMS. OK.
- 17:40:40 Playlist Friday, one track, Exhilarate. Skylander (not in the playlist) is playing. MIX: "You've played the rest of Friday. To go round again, stop the deck and press MIX." (fu-played-the-rest-of-friday.png). I've never "played Friday". It remembers I played Exhilarate earlier in the session. If I build a playlist for a set from songs I've auditioned, MIX is going to treat them as used up. Can't see which tracks count as played (no marks in the list). I wanted a simple "play this list" and got a hand icon.
- 17:41:00 Dragging round the platter on a playing deck, slow half-turns, SLIP off and SLIP on: the time and waveform carried on at about the normal rate. I can't say from what I can see whether it bent the speed or scratched; nothing on screen shows it took my finger (no "nudge" read-out, nothing lights). With no sound I have no way of checking. Marked as NOT verified. The wheel's own edge moves very gently, so I can't tell if my drag did anything at all.
- 17:41:30 JOG WHEEL help: "Touch the record to scratch. Turn the metal ring to push a playing track ahead or hold it back for a moment". There are two zones. Not visible as such.
- 17:42:00 Tested by numbers, since I can't hear it. SLIP off, finger held on the record 4 s: time moved 1.8 s over 6.2 s of real time, so holding really does hold it. SLIP on, same hold: time carried on at full rate (9.9 s over 9.65 s of real time). So SLIP does what help says as far as the numbers go. Nothing else on screen shows I'm holding: no change in the wheel, Play stays bright. So correcting my 17:41:00 note: the wheel works, I just couldn't see it.
- 17:42:30 Hand-made stem mix: both decks at 126, tapped BASS and DRUMS off on deck 1. The waveform thinned, the meter fell, nothing else moved. ACAPELLA: others off, V and SOLO V light pink. Stopping deck 1 straight after a stem mix: master moved to 2 at once. Browser: KEY column shows a big pink 5A pill on Severe Tire Damage because deck 2's Houston is 5A. So THAT'S what the pill looks like. Clear once seen, though I'd only seen it by chance: a filled pill was never visible with the track in the first half hour.
- 17:42:50 New track on deck 1: stems reset to all on (fu-new-track-stems-reset.png). The stem page stayed open. Long title wraps to two lines and still fits. Good.
- 17:42:40 Settings again. Crossfader curve: Smooth / Scratch, with no words on what either does. Recording Format: AAC (small). Haptics note is lovely: "you can feel beats and bars pass under your finger on the platter". The note says deleting the app deletes the backups too.
- 17:42:50 Pressed REC again; loaded Gepzene (128) with Houston (126) playing, near the same tempo, to see which move Auto picks. Hit AUTO: button read "AUTO..." for a second or two, no toast.
- 17:43:30 Pressing AUTO mid-move (while the echo was going): "Auto DJ stopped. Deck 1 is on." Houston (the one that had been playing until a moment before) is stopped dead, CUE lit, and Gepzene plays (fu-auto-stopped-midmove.png). So stopping doesn't mean "go back to how it was", it means "jump to the end". I wanted the opposite for the moment. Before the move it had said "Auto DJ off" and everything stayed put. Two behaviours from one button, depending on a moment you can't see. No undo.
- 17:43:50 Second recording, tracklist (fu-tracklist-title-doubled.png): Gepzene is listed "Gepzene — Gepzene - Can't be Serious" (the artist is in the title tag as well). "126.0 BPM" is the speed it played, not its native 128, but on the first recording Houston was shown as 5A when it played at 10A (key shifted). So tempo is as-played, key as-tagged. Time 00:38 matches REC's own "· 1 → · 2" moving, near as I could see. Recording's name "Mix 2026-11-04 17.42.39" is the time pressed. Nice to have.
- 17:44:20 BPM menu > Cues and loops: my hot cue A from half an hour ago (0:57) is still there on Gepzene. So cues stick to the track. Named it Drop, picked green from a colour popover: pad A is green and says Drop, flag on the overview strip is green (fu-cue-renamed-recoloured.png). Neat and it worked first go.
- Gepzene is still at 126 on an unlit SYNC after the move: on the PADS view nothing says that's not its own speed (no % shown here). You have to open JOG or look at the menu: "Beat grid: 128.00 BPM at normal speed". The tiny grey menu header is the only place that tells you.
- 17:44:40 Jumped to the last few seconds of Gepzene and pressed AUTO: "No clean way in from here. Deck 2 starts when this one ends." (fu-no-clean-way-in.png). Honest and exactly what I'd want. About 4 s later deck 2 started, while deck 1 stopped at -00:04.0 with its waveform flat from there: it hadn't reached its end, it cut at the last sound. No thumbs toast that time.
- 17:45:15 Tapping a row body in the browser does nothing, and nothing in the list previews a track. (I never found a way of hearing a track before it's on a deck. I may have missed one.) I saw "Delete from Library" in the long-press menu and chose not to press it.
- 17:45:40-17:45:55 A proper hand mix, by myself, no help: load Skylander to 1, SYNC (126), Play at the intro, LOW down on 1, LOW down on 2, LOW up on 1, crossfader across to 1 (fu-hand-mix-eq-swap.png). It took me under a minute this time. Honest moment: it now feels like a DJ app, not a puzzle. The two blocks and the green tick show they're aligned, the two waveforms' tall peaks stack.
- With the crossfader hard over to deck 1, deck 2's meter is as high as ever and nothing shows it's cut. I've learnt the meter shows the deck before the crossfader, but that's a guess.
- 17:46:00 Sorted the list by BPM, stopped everything, MIX: "Mixing through all your tracks, 5 tracks. Up next: Houston." Yes: it plays the list in the order on screen (fu-mix-follows-sort.png). That's a clever idea, and I'd never have guessed the sort was also the set order until I read MIX's help. "5 tracks" vs the strip's "4 tracks to go" within the same screenshot reads like a mismatch; I get it after a beat (one's already on).
- 17:46:15 Mix running, crossfader had jumped back to centre by itself, button says MIX 98: 98 bars, about three minutes before anything happens. I got impatient and wanted "go to the next track now"; nothing offers that. The only choices I found are the MIX button (stops it) or to load something else: "Mix off: the track changed." (fu-mix-off-track-changed.png), which threw away the plan when all I'd wanted was to change what plays next.
- 17:46:30 History (fu-history-is-every-load.png): newest first, and it's every time a track went on a deck, not what I played. Exhilarate is top having just been loaded and never played. Tracks Mix loaded and threw away are in there too. No times on any of it, and every row looks like a normal track list. A "history" I'd want for working out what I played at a gig isn't this. Every copy of a loaded track is highlighted.
