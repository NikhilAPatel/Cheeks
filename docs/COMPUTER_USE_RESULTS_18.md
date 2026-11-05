# Hands-on results, part 18, 2026-11-05

Commit tested: 000cb0b

Device:
- **iPhone SE Cheeks:** 667×375 on its side, for the retest, the long run and CPU.
- **Folded iPhone Duo:** 466×678 pt, upright phone layout, for the first-time user and for `GC1`, `GC3` and `GC5` upright.

Tooling limits:
- **The full layout can't be pressed.** The Duo's still folded: the last `hingeState:` in SpringBoard's log says `Closed`, at 13:01 on 11-04. I didn't reboot it. I asked for the iPad's touch access again at 02:32, with no answer. For `GC5` I rendered the `FX` page at every screen size with the snapshot test, which shows how it looks and not how it presses.
- **Can't be checked here:** how anything sounds, haptics, the headphone output and a real finger. Levels are read from recordings and meter pixels.
- **Double-tap on a knob or fader:** two tool taps are too slow to count.
- **Presses in a slide:** I sent them straight after the key, so by timing they were in or just after the slide. I didn't freeze the app, because the long run was recording.
- **Screen reading:** a logger read the top of the screen by OCR about twice a second. It stalled from 03:22:36 to 03:22:55, and I restarted it. The recording and screenshots cover that gap.
- **Busy Mac:** the first-time user ran beside my retest until 03:19. Mac idle read 0% at 02:36, with both simulators splitting stems. The CPU table came after they'd stopped, with Mac idle at 50 to 73%.
- **A crash report from today,** `Cheeks-2026-11-05-013456.ips`, isn't from this round. It's `CheeksTests` on the iPad at 01:34, an index out of range in `testAMixSaysOnceWhereToWatchItFrom`, before this commit. I didn't copy it in. This round produced none.

## Summary

55 scripted tests including the long run: **50 PASS, 1 FAIL, 4 BLOCKED.** No crash reports. The failure's small: `GB4`, the new tip losing its last words upright. The blocked ones are `GA1` to `GA4`.

**Everything that failed last round is fixed.**
- **`N23`, a track loaded on a mix's last track:** "Up next: Houston. The mix carries on.", and it mixes into it. With nothing loaded, the mix still ends with its green tick.
- **`N24`, `BEAT SYNC` on the only deck playing:** it refuses, with the right words, and nothing moves.
- **`GC4`, the minus:** four tracks out of four end on a plain `00:00.0`, Severe included.
- **`N26` and `N27`:** a recording's delete has a `Cancel`, and a saved cue has a green tick.

**Your three questions:**
- **`GC1`: yes, messages clear the section name,** on the small iPhone and upright, for one line and two. Nothing else is newly covered.
- **`GC6`: no, a press never landed on the wrong key.** All eight presses in gaps landed on one of the two keys beside them, and where I could tell, on the nearer one. `BEAT` and `ALL` at x178 was last round's dead spot, and it's `BEAT` now.
- **The first-time user upright:** they could say what Auto DJ does at **+13:25**, and this time it was your tip that did it. "Loop build starting. Put both decks on STEMS to watch it" came at about +12:37, and they did. That's later than last round's +10:41, but that was by their own account luck. A correction to the brief: round 16's first-time user was upright on the folded Duo too, and took 16:52.

**`GC8` is settled: the Vocal ride's dip is the new track's own.** A ride came up, Gepzene coming in from 0:17 over Houston. The recording dips to -25 dB about 12 s after it started, and to -30 dB as it ended. Gepzene on its own dips to -22 to -27 dB at those very places, every 15 s. See `GC8`.

**The most important problems:**
1. **`N28`: a mix that starts on a track with its saved loop switched on stops at that loop, with no word.** The key reads `MIX…` from the start of the track, with no plan. It held there for about 2:30, until I ended the loop. It's the only silent hold I found.
2. **`N29`: `SYNC` follows what a stopped deck was left at.** Two tracks 2 BPM apart ended up at 85 and 170 for the first-time user, and I reproduced it in a few presses. It says so, and it's what they call the worst thing about the app, as last round's first-time user did about the same leftover speed.
3. **`GB4`: the new tip loses its last words upright.** "The gear's guide h..." at two lines, because a message has a limit of two. The instruction about the `LOW`s survives. It's the only message I saw cut.

**`GC2`, the overview:** a tap or a quick slide only gets the message, up to the 100 pt I tried, and the hold still jumps and follows. It didn't get in my way in about a dozen seeks, and the first-time user wasn't bothered. The catch: twice with the Mac at 0% idle, a slide of 150 ms or less jumped anyway. See `GC2`. It's still one for a real thumb.

## Failures

### GB4: the tip loses its last words upright on the folded Duo
- Steps: clean install, upright on the folded Duo, with both decks playing for the first time.
- Expected: "Two basslines clash. Turn the new track's LOW down, and swap the two LOWs as you crossfade. The gear's guide has the rest."
- Actual: "Two basslines clash. Turn the new track's LOW down, and swap the two LOWs as you crossfade. The gear's guide h..." (`fu-05-two-playing.png`, 02:34:55).
- On the small iPhone on its side it fits on two lines (`gb4-tip.png`). The rest of `GB4` passes: nothing on one deck alone, once only, and with the flag reset by hand, nothing through four moves in a mix, then the tip at 03:14:24 as soon as the mix was off and both decks were playing (`gb4-second.png`).
- Cause: `ContentView.swift:701` has `.lineLimit(2)`. At 123 characters in the 381 pt the app has upright, this needs three lines. `CLAUDE.md` says a long message takes a second line rather than losing its end, and this one's lost its end on the second line. I didn't see another one cut, though a message with `letItBeHeard`'s words in front of it could run as long.

The rest are new, and outside the script.

### N28 (new, reproduced): a mix starting on a track with its saved loop on stops at that loop, with no word
- Steps: on the small iPhone, Severe on deck 2, with its saved loop (5:09, 4 beats) switched on in `LIST`, and reloaded. Nothing playing. `MIX` in the browser (03:32:24).
- Expected: either `MIX` takes the loop off, as pressing `AUTO` or `MIX` does when a track's playing, or the mix says it's waiting, as it does for a loop set by hand: "The mix will carry on when deck 2's loop ends."
- Actual:
  - The key reads `MIX…` from the first second, with no plan. It was still `MIX…` at 0:27.
  - I sought to 5:05. The deck went into the loop at 5:09 and stayed. `MIX…` and no message, with the `MEM` pad lit (`n28-held-no-word.png`). I left it for about 2:30.
  - Ending the loop with its pad gave `MIX 48` within a second, so it recovers at once (03:35:33).
  - **Going into such a track is fine.** A Loop build into Severe (03:42:57) left `MIX 122`, and a seek to 5:05 ran straight past the loop.
- It came up by accident first, at 02:49, with a loop I'd switched off in `LIST` after loading. **So switching it off doesn't disarm it for this load,** and the deck was caught on a loop the list said was off. The note under the list only talks about loading, so that may be fine by itself.
- Where I'd look: `AutoDJ.swift:416`, `if air.renderer.loopActive { return }`, comes before any planning, and `loopActive` is true for a loop that's still up ahead. The words are at `:828`, in the branch where there's already a plan, so here they're never said. A mix with a track playing takes its loop off (`getReadyToLeave`, `:301`). A mix from nothing goes down the other branch, which has no such step.

### N29 (new, from the first-time user, reproduced): `SYNC` follows what a stopped deck was left at
- Steps, on the small iPhone: Exhilarate (170) playing on deck 1. `SYNC` on a stopped Gepzene (128) on deck 2: "Deck 2's 33% faster than its own 128 BPM, to follow." Stop deck 1 and load Houston (126) on it. `SYNC` on deck 1.
- Actual: "Deck 1 follows at half tempo: 85 against 170." Houston's at 85.00, -32.5% (`n29-half-tempo.png`).
- The first-time user's version, as I read their report: they wanted to mix Houston (126) with Gepzene (128). A finished track on deck 2 was still at 170, so `SYNC` took Houston to 85. Gepzene then followed Houston at double: "170 against 85". Both `WIDE`, at -32.5 and +32.8 (`fu-38-final-state.png`). They ran out of time looking for a way back.
- It's what the code means (`DJEngine.swift:472`), and it does say so. But nothing's playing on the deck being followed, and nobody can hear that number. It's the next step on from last round's "a track stays at the other's speed", which you left because real decks do that.
- **It's their worst thing, and the same family was last round's.** Your call.

### N30 (new, from the first-time user, reproduced): upright on the folded Duo, `Done` leaves Settings on scrolling
- Steps: gear, then scroll down by 300 pt.
- Actual: the title and `Done` are gone, with the list running to the top of the sheet (`n30-settings-upright.png`). Swiping down or scrolling back gets out. On the small iPhone on its side they stay, over the list (`n30-settings-on-its-side.png`).

### N31 (new, from the first-time user, confirmed): "Put both decks on STEMS to watch it" on an Echo throw
- Every pad on both decks stays fully lit through an echo throw, so there's nothing there to watch (`n31-echo-throw-stems.png`, with both on `STEMS`). You took the words off a brake drop for this reason. The new tip came up on an Echo throw for me as a mix's first move (`gc7-mix-first.png`), and a mix only says it once, so someone can follow the advice and see nothing. The first-time user did: "This holds for a loop build. During an echo throw the pads stayed fully lit."

## Blocked

- **`GA1` to `GA4`:** the Duo's folded and the iPad's touch access is unanswered. Nobody has yet pressed during the slide on the full layout, or filmed the browser, logo or sweep on the Duo.
- **Two parts of `GC7` weren't seen,** and I've still passed it on the rest. See `GC7`:
  - **A brake drop's words:** no brake drop came up in about 18 moves and plans. The code reads as asked (`AutoDJ.swift:888`).
  - **`SPLIT` saying what it does as it lights on the full layout:** can't be pressed. On a phone the sentence is under the keys, and it's right.

## Looks wrong

- **`-00:00.4` in red, for good.** When `AUTO`'s waiting for stems and the track has nothing left to hear, it stops the deck just short of its end. It then sits at `-00:00.4` (`fu-08-auto-gaveup.png`, stopped at 04:36.8 of 04:37.2). The `GB1` fix is for under 0.1 s. It's small, but a deck that's finished reads as if it hasn't.
- **The thumbs sit over the overview.** With a question up, my hold on deck 1's overview to seek at 03:43:46 landed on the thumb and gave "Got it. Less like that.", a rating I never meant. The first-time user's mirror image: the question had gone, so their tap for a thumb landed on the overview and got the hold message. Both are harmless to the music, which is the point of the hold. A rating nobody meant does reach what Auto DJ chooses.
- **`LIST`'s switch doesn't change this load.** See `N28`.
- **Messages from before a page change stay up.** `SLICE`'s tip stayed over `JUMP`, and "Everything else here has been played" stayed after they'd moved to another playlist, so "here" was wrong. Those are the first-time user's, and I didn't reproduce them. They're only there for the message's lifetime.
- **"Crossfader to the middle, to hear both."** The first-time user read it as an instruction when it had already been done. `AutoDJ.swift:871`.
- **`RELOOP` orange on orange during a held `SLICE` pad,** the first-time user says, at 03:00:50. I didn't look.

## About the first-time user's report

It's reliable, and it corrects itself in places. I checked these.
- **"Thumbs down gave no reply":** each of my presses got "Got it. Less like that.", within a second. It'll have been the question going as they pressed.
- **"The Recordings icon's first tap showed nothing":** it opened at the first press for me, every time, with the Mac less busy. They suspected a slow sheet, and I think that's right.
- **The black strip at the right of the folded Duo:** it's the cover screen's camera cut-out. Round 16's first-time user mentioned it too, so it isn't new. It does cost them 85 pt on a screen where a message has just run out of room.
- **"`AUTO` undid the `SYNC` I'd pressed on the other deck, with no message":** I think that's the waiting deck being cued for the move. I didn't test it. It's fair to say it doesn't read that way.

## All results

| Test | Result | Notes |
|---|---|---|
| GA1 | BLOCKED | Needs the Duo open. The iPad's touch access is unanswered |
| GA2 | BLOCKED | The same |
| GA3 | BLOCKED | The same |
| GA4 | BLOCKED | The same. Presses in slides on the small iPhone are under the long run |
| GB1 | PASS | Gepzene 03:48.9, Houston 04:50.5, Severe 06:51.8 and Exhilarate 02:25.4 all read `00:00.0` in red, with no minus (`gb1-severe-exhilarate.png`). See Looks wrong for `-00:00.4` |
| GB2 | PASS | See below |
| GB3 | PASS | The refusal's exact words with a hand, and nothing moves (`gb3-refused.png`). `SYNC` on deck 1 brings it to deck 2's tempo. With both playing, `BEAT SYNC` on the master follows the other, 128.00 to 130.04, and `MASTER` moves (`gb3-both.png`) |
| GB4 | FAIL | Right on the small iPhone, once only, and not in a mix. Upright it loses its last words. See Failures |
| GB5 | PASS | "Delete this recording and its tracklist?" with `Cancel` and a red `Delete`. `Cancel` keeps all three files (`gb5-delete.png`) |
| GB6 | PASS | `SAVE CUE`: a green tick, "Memory cue saved. The track loads here now." with `UNDO`. A later one: "Memory cue saved." A deleted one: a bin, "Deleted memory cue" with `UNDO` (`gb6-save.png`, `gb6-del.png`) |
| GC1 | PASS | See below |
| GC2 | PASS | See below |
| GC3 | PASS | See below |
| GC4 | PASS | See below |
| GC5 | PASS | A small orange square under each name, and it fits at the six widths I looked at: two on the simulators, and the full Duo, iPad, iPhone and small upright as renders. It's the one mark on those pads, so it reads as different. Whether it reads as "stops the deck" needs `?` (`gc5-brake-side.png`, `gc5-upright.png`, `gc5-duo-render.png`, `gc5-widths.png`) |
| GC6 | PASS | See below |
| GC7 | PASS | See below. A brake drop didn't come up, and the full layout's `SPLIT` can't be pressed |
| GC8 | PASS | See below |
| GC9 | PASS | Run back to `00:00.0`, `REV` off: stays there, stopped (`gc9-start-stays.png`). Partway and running: `REV` off goes from 11.1 to 16.6, where it would have got to |
| GC10 | PASS | No arrows and no number at 8 cues, and `‹ 1/2 ›` at 9. `SAVE CUE`, `SAVE LOOP` and `LIST` don't move (`gc10-pair.png`) |
| GC11 | PASS | `ROLL` first seen with `?` lit: its note and no tip. `?` off, away and back: "ROLL pads play for as long as you hold them." (`gc11-roll.png`) |
| A2 | PASS | Tap and swipe both: "Deck 2 is playing. Stop it first." with a hand. No load (`a2-refused.png`). Shake not checked on video |
| B2 | PASS | From a recording: the meters run up and back once as the logo lifts (`b2-launch-sweep.png`) |
| B3 | PASS | On a phone it hangs below the top bar, and `MASTER` is always readable |
| B4 | PASS | 11 of 11 centred and green over 2:03 (`b4-marker.png`) |
| B5 | PASS | Load and close at once: the jog reads 128.00 |
| B6 | PASS | Header and jog both 130.59. The menu's title: "Beat grid: 128.00 BPM at normal speed" (`b6-both-match.png`, `b6-bpm.png`) |
| C4 | PASS | Both choices work (`c4-alert.png`, `c4c.png`) |
| C7 | PASS | Whole title in the browser, two lines on a deck where it's needed (`c7-titles.png`) |
| C8 | PASS | At 4 beats, 1/2 and 1 beat, through wraps, the line doesn't cross the text (`c8-counter-loop.png`) |
| D1 | PASS | `SOLO` stays lit and the others dim (`d1-solo.png`) |
| D5 | PASS | New title straight away |
| D6 | PASS | `Stems 8%` and up on the deck's header. A phone has no compact deck in the browser, so it's seen on closing it, or on `MIX 14%` |
| D7 | PASS | Still 32 after a held `ROLL` |
| D8 | PASS | No old loop on Houston after a loop on Gepzene |
| D9 | PASS | "Friday warmup" in the `.cue`, its `FILE` line and the `.txt` |
| D10 | PASS | Shape, not a flat band (`d10-stems.png`) |
| D12 | PASS | Stem colours with the rest as ghosts, and three dim marks over `STEMS`. Normal colours come back (`d12-muted.png`) |
| E | PASS | Hang log empty. Pause while playing, play at the end, and the slider goes (`e-play-pause-end.png`) |
| F1 | PASS | All there, with a page count only at 9 (`f1-mem.png`) |
| F2 | PASS | One pad, then "There's already a memory cue here." with a hand. Red triangles on both waveforms |
| F3 | PASS | "Set a loop first, then save it." Then an orange pad and bar |
| F4 | PASS | Jumps, holds and lights. A second tap ends it (`f4-saved-loop.png`). It starts a stopped deck, as you decided in round 12 |
| F5 | PASS | `DEL`, a pad, `UNDO`. My first `UNDO` came 15 s later, after it had gone |
| F6 | PASS | "Drop", in green, reaches the pad and the flag. The loop's switch: on reload it's armed, `RELOOP` reads `ARMED`, and the deck stays at 0:00 (`f6-list.png`) |
| F7 | PASS | All there after a relaunch |
| J1 | PASS | Skylander 8 sections, Gepzene 6, Exhilarate 5, Houston 9, Severe 13 (`j1-phrases.png`) |
| J2 | PASS | Counts up, and restarts at a boundary: `UP 4.3` to `CHORUS 1.1`, `CHORUS 48.4` to `DOWN 1.3` |
| J3 | PASS | Exhilarate and Severe read one value only, across the whole log |
| K1 | PASS | Saved in Files, "Backup saved." |
| K2 | PASS | "Restored 5 tracks and 1 playlist." and the cue's back, name and colour too (`k2-cue-back.png`) |
| K3 | PASS | Triangle, and "…'s file is missing. Import it again and it'll get its cues back." (`k3-missing.png`) |
| K4 | PASS | Copied back to `Documents/`: moved home, same ID, with its cues and loop, and no second row |
| K5 | PASS | `Segue DJ Library 2026-11-05.json` |
| Long run | PASS | See below |

### GB2: a track loaded on a mix's last track
On the small iPhone, a search for `Kev`, so Severe and then Exhilarate. `MIX` from nothing.
| Time | What happened | What was said |
|---|---|---|
| 02:49:20 | Mix starts | "Mixing through this list, 1 track to go. Up next: Exhilarate." |
| 02:50:07 | I ended the loop `N28` had caught it on | `MIX 49` |
| 02:51:27 | Echo throw | "Echo throw into Exhilarate. Put both decks on STEMS to watch it." (`gc7-mix-first.png`) |
| 02:51:40 | Done. The line says "This is the last track." | "Echo throw done. Deck 1 is on. More echo throws?" |
| 02:52:07 | Houston loaded on the waiting deck | "Up next: Houston. The mix carries on." The line says 1 track to go (`gb2-upnext.png`) |
| 02:52:18 | Planned | `MIX 45` |
| 02:53:21 | Loop build, with no `STEMS` tip | |
| 02:53:50 | Done. The line says "This is the last track." again (`gb2-last-again.png`) | "Loop build done. Deck 2 is on. More loop builds?" |
| 02:54:22 | Nothing loaded, and I sought near the end | "That's the end of this list." with a green tick, the key back on `AUTO`, `00:00.0` (`gb2-mix-ends.png`) |

"That's the last track in this list" wasn't said, as the thumbs question was up (`AutoDJ.swift:375`). The line said it instead. It also worked in the long run, at 03:18:48.

### GC1: messages on a phone
**Yes, it clears, in every case I looked at.** Deck 1's name sits at the bottom of its waveform, with deck 2's just below it across the beat blocks. Two-line messages stop short of it too (`gb4-tip.png`, and `gc1-upright.png` upright).

**How it looks:** better. The two names read as a pair, and you can compare the sections at a glance. It's not my worst thing any more. **Nothing else is newly covered.** A message still covers deck 1's overview and the top half of its waveform for its life, which is as you said.

### GC2: the overview
| Time | Mac idle | Touch on a playing deck | Result |
|---|---|---|---|
| 02:36:04 | about 0% | 10 pt, three samples 40 ms apart | **Jumped** to about 2:15 (`gc2-pegged.png`, top) |
| 02:36:10 | about 0% | 300 pt, 150 ms | **Jumped,** to 3:41 |
| 02:36:14 | about 0% | Held 0.32 s | Jumped, as it should |
| 02:36:19 | about 0% | Held 0.32 s, then 150 pt | Jumped, and followed the finger |
| 02:36:46 | about 0% | Tap | The message, no jump (`gc2-message-only.png`) |
| 02:36:55 | about 0% | 10 pt in 0.08 s | The message, no jump |
| 03:21:31 | 23% | 100 pt in 0.1 s | The message, no jump |
| 03:21:42 | about 23% | The same 10 pt as the first row | The message, no jump |

So it's right with the Mac at 23% idle, and right four times out of six with it at 0%. **My guess at the two jumps:** the Mac was pegged, so the touch reached the app late, or the end of it did, and the 0.25 s timer ran out first. The tool can't tell me how long the touch really lasted, and I only know the time I sent. On a phone, the same could happen in a stall during a split. It's why it wants a real thumb.

**Does it get in the way?** No, in about a dozen seeks. A hold is quick enough, and I was never unsure whether it had taken. The first-time user: "No, it neither got in my way nor read as broken."

### GC3: `JOG` with `TEMPO` under it
**It reads, and isn't clipped,** on the small iPhone and upright, though it's very small (`gc3-jog-side.png`, `gc3-upright-jog.png`). `PADS` when it's lit, with no `TEMPO`, as you intended.

**The waveforms don't move:** with the decks stopped, no row of pixels in the top 118 pt changed on the small iPhone on pressing both decks' keys, or above the decks upright.

**Did it tell the first-time user?** No. "My notes call it JOG / PADS, they never mention TEMPO, and I'm not sure I read that word then." They found the fader by pressing it with `?` on, at +2:38, and moved it at +10:52. That's one person, who wasn't looking for it, as `SYNC` had already matched the tempo.

### GC4: the sampler's sheet on the small iPhone on its side
| Rows | At rest | A flick |
|---|---|---|
| No extras | All on screen, ending about 30 pt above the bottom (`gc4-plain.png`) | Doesn't move at all (`gc4-plain-flick.png`) |
| One extra, a grab | All the rows on screen, with the footer under the bottom | About 38 pt |
| Two extras, a grab and a restore | `Restore the Original Sound` starts under the bottom | About 83 pt, and it stays there (`gc4-extra-pair.png`) |

Stopping `Record the Master`: "Pad 3 has your recording. SET and then the pad can restore its original sound." with a green tick (`gc4-record.png`). Restoring worked, and put `RISER` back.

### GC6: gaps between keys, small iPhone on its side
| Gap | Press at | Landed on |
|---|---|---|
| `Q` and `SLIP` | x217.5 | `Q` |
| `Q` and `SLIP` | x219 | `SLIP` |
| `BEAT` and `ALL` | x178 | `BEAT` (dead last round) |
| `BEAT` and `ALL` | x180 | `ALL` |
| `VOX` and `INST` | x99 | `INST` |
| `INST` and `BEAT` | x139, twice | `INST` |
| FX stems `V` and `I` | x171 | `I` |

**No press landed on the wrong one.** The keys are about 2 pt apart, so each of these is near the middle, and there's nothing to choose between the two.

### GC7: words
| Item | Result |
|---|---|
| `MIX`'s first move, not on `STEMS` | "Echo throw into Exhilarate. Put both decks on STEMS to watch it." Its next moves leave it out (`gc7-mix-first.png`). See `N31` |
| With both on `STEMS` | Left out: "Echo throw into Gepzene - Can't be Serious." (03:11:49). It's then said later in that mix, when one's left `STEMS`, as it's once a mix |
| A brake drop | **Not seen** |
| "No clean way in..." after a seek back | Said at 03:29:27 and gone by 03:29:28.6, within my 0.5 s of seeing it, with `MIX…` and then `MIX 40` (`gc7-no-clean-way-in.png`, `gc7-no-clean-way-in-gone.png`) |
| A row's title, tapped | "Press 1 or 2 to load this, or hold the row for more." (`gc7-row-tap.png`) |
| `TRACK ROW` | There, and right (`gc7-track-row.png`) |
| A tap during a scroll, a swipe and a hold | A tap in a flick stops the list, with no message and no load (`gc7-row-tap-in-a-flick.png`, in History). Swipe and hold both still work |
| The guide finds `5A` and `12B` | Both find `KEY` (`gc7-guide-5a.png`, `gc7-guide-12b.png`) |
| `BPM` menu | `Double the Reading` and `Halve the Reading`. "Deck 1's track reads 63 BPM now. Its speed hasn't changed." (`gc7-halve.png`) |
| `CUE/MST` note | Against what it does: right. It says it needs `SPLIT` on (`gc7-cue-mst-split.png`) |
| `SET` note | Says what a gate is, and matches the sheet |
| `TEMPO FADER` note | Down is faster, clicks at the centre, stays at a synced speed until a double-tap (`gc7-tempo-fader-note.png`). I can't test the double-tap |
| `SPLIT` | Under the keys in the phone's sheet: "One output, like AirPods, only plays the mix. SPLIT's for a splitter cable." **Full layout not pressed** |
| `DJ library (XML)…` | "Choose the XML your DJ software exported." (`gc7-xml.png`) |
| `Stems 99%` | At most, over five splits, and no `Stems 100` in the log |
| `Before restore` | `Before restore 2026-11-05 030741.json`, at 03:07:41 here, so the phone's own time |

### GC8: the Vocal ride
It came up by `AUTO` at 03:24:04: Houston on air, Gepzene coming in from 0:17, at 126, with its key up 1.

| Recording | Ride | What's there | Gepzene alone, at that place |
|---|---|---|---|
| 846.5 to 847.5 s, -25 dB | About 12 s in | Gepzene at about 29.1 s | 28.5 to 30 s: -22, -26, -26 dB |
| 861.5 to 863 s, -26 and -30 dB | At its end, "done" at 03:24:39 | Gepzene at about 43.9 s | 43.5 to 45 s: -22, -26, -25 dB |

**So it's the new track's own, as you thought.** Gepzene has that gap every 15 s, and it was there at 13.5 s too, before it was heard. It's the same place as last round's, about 11 s in and at -28 dB. I can't prove last round's was Gepzene, but it looks like the same thing. Nothing went quiet in the ride that wasn't in the track (`gc8-vocal-ride-done.png`).

## Timings and measurements

### CPU, small iPhone, this simulator's process only
| State | This round | Last round |
|---|---|---|
| Idle, nothing loaded | 4.0% | 3.9% |
| Two tracks loaded, paused | 4.5% | 4.1% |
| One deck playing | 9.5% | 9.2% |
| Both playing and synced, with a tempo offset | 15.0% | 14.2% |
| Both, plus stems and an echo | 15.5% | 17.6% |

Mac idle was 73, 73, 57, 50 and 52%. `liveactivitiesd` and `pairedsyncd` came and went. `A3` wasn't asked for this round, and I took it for the comparison.

### The long run
Small iPhone on its side, with `DUB` chosen, from 03:10:18 to 03:25:24. **15:06 of recording, with a mean of -14.8 dB and a peak of -0.1 dB.** No crash, and the decks were usable throughout.

| Time | What I did | What happened |
|---|---|---|
| 03:10:24 | `MIX` from nothing | "Mixing through all your tracks, 4 tracks to go. Up next: Houston." |
| 03:10:37 | **Seek past the exit,** from `MIX 112` | `MIX 38` by 03:10:49 |
| 03:10:55 | `BROWSE`, and **a row's `2` in the slide** | Gepzene on deck 2, as pressed. **A load on the waiting deck:** "Up next: Gepzene - Can't be Serious. The mix carries on." |
| 03:11:03 | `BROWSE`, and **deck 1's `CUE` tab in the slide** | Landed on the tab, and no cue was set |
| 03:11:49 | | Echo throw. Done at 03:12:03, "Deck 2 is on." |
| 03:12:17 | **Seek past the exit,** from `MIX 76` | `MIX 10`, then a Loop build into Houston at 03:12:41 |
| 03:13:03 | **`MIX` key in the build's last bars** | "Mix off. The decks are yours. Deck 2 is still looping. ALL brings back deck 2's stems." Houston back to 0:00 at 126, cued (`lr-handback-mix-key.png`) |
| 03:13:32 | `ALL`, `EXIT`, `LOW` back by hand, `MIX` | "3 tracks to go. Up next: Skylander." That's right |
| 03:14:07 | **`EXIT` in the next build's last bars** | "Mix off: deck 2's loop was changed. The decks are yours. ALL brings back deck 2's stems." Skylander back to 0:00.5 at 125 (`lr-handback-exit.png`) |
| 03:15:20 | `AUTO`, on Skylander | Loop build. I took deck 1's fader at 03:15:41 and it stayed mine. Done at 03:16:14 |
| 03:16:21 | Thumb down | "Got it. Less like that." |
| 03:16:29 | `AUTO` | **Bass swap,** starting at 03:16:37, done at 03:17:23 |
| 03:17:35 | `MIX` | "1 track to go. Up next: Exhilarate." That's right |
| 03:17:54 | **Seek past the exit,** from `MIX 70` | `MIX 10`, then an Echo throw at 03:18:18 |
| 03:18:48 | **A load on the mix's last track** | "Up next: Gepzene - Can't be Serious. The mix carries on." (`lr-load-on-last-track.png`) |
| 03:19:15 | `BROWSE` twice, and deck 2's `FX` tab in the slide | Landed on the tab |
| 03:19:25 | **Seek past the exit,** from `MIX 40` | `MIX 6`, then an Echo throw at 03:19:40 with 3 s of Exhilarate left, done at 03:19:48 with it on `00:00.0` |
| 03:20:05 | `MIX` key | "Mix off. The track playing just carries on." |
| 03:20:26 | `AUTO`, then `AUTO` again | Called off, and Skylander goes back |
| 03:20:35 | `AUTO`, then a loop in the countdown | "Auto DJ stopped: deck 1 is in a loop." (`lr-loop-in-countdown.png`) |
| 03:20:45 | `AUTO` with that loop on | Takes it off, and counts down |
| 03:21:05 | **`PLAY` on the new deck,** before the score started it | "Auto DJ stopped: you started deck 2 yourself. Deck 1 carries on." (`lr-play-new-deck.png`) |
| 03:21:31 | Slides on a playing overview, with `AUTO` counting | The message only |
| 03:22:16 | **Stop the old deck in a Loop build** | "Auto DJ stopped: deck 2 was stopped. Deck 1 is on." (`lr-stop-old-deck.png`) |
| 03:22:31 | `MIX`, with everything played | "Everything else here has been played. To go round again, stop the deck and press MIX." with a hand (`lr-mix-everything-played.png`) |
| 03:23:21 | **`AUTO` in a build's last bars** | "Auto DJ stopped. The decks are yours. Deck 1 is still looping. ALL brings back deck 1's stems." (`lr-handback-auto.png`) |
| 03:23:50 | `BRAKE` on deck 1 | Stops it |
| 03:24:04 | `AUTO` | **Vocal ride.** See `GC8` |

**Everything under -50 dB for 0.15 s or more:**
| Recording | Length | What it is |
|---|---|---|
| 0 to 6.14 s | 6.14 s | Before I'd pressed `MIX` |
| 95.23 to 118.07 s, seven gaps | 0.23 to 0.35 s each | Gepzene's own, 3.6 to 29.9 s |
| 396.14 to 398.27 s, three gaps | 0.2 s each | Houston's own, about 70 to 72 s |
| **409.34 s** | **0.43 s** | **The Bass swap's breath** |
| 564.65 to 579.71 s, five gaps | 0.24 to 0.35 s each | Gepzene's own, 14.9 to 29.9 s |
| 632.26 s | 0.24 s | Gepzene's own, 74.96 s |
| 717.49 to 736.64 s, six gaps | 0.24 to 0.35 s each | Gepzene's own, 11.2 to 29.9 s |
| 893.3 s | 0.24 s | Gepzene's own, 74.96 s |

**No hole.** Each one lines up with the track playing there, looked at on its own.

**Afterwards:** nothing left silent, looping or filtered that the screen didn't show. A hand-back leaves what it says it leaves, and each one was fixed by `ALL`, `EXIT` and `LOW`, as it says (`lr-end-decks.png`).

## First impressions

**1. Does it look like $1000 pro software?** Closer again, on a phone on its side. With both decks running, the screen looks like an instrument, and the section names by the beat blocks are a real help. Three things most break it:
- **The sheets.** Hardware gives way to stock iOS and a lot of black. The Mixer sheet is two rows of controls and a screen of nothing, and that's a sheet you open mid-set.
- **Keys that show a working state with a typographic trick.** `MIX…`, `AUTO 1`, `MIX 14%`, `SMPL ›`. They're honest, and they fit, but they read as a key running out of room.
- **Upright on the folded Duo, the black strip.** 85 pt is gone beside the app, with knobs about 30 pt wide, and a message that can't fit three lines. The first-time user hit the wrong knob there.

**2. What felt slow, confusing or surprising?**
- **Stems.** 2 to 3 minutes a track here, and until then, `AUTO` can't do its real job. It's said well, but the first press of the best feature usually can't work. That's the first-time user's second-worst thing too.
- **`MIX…` with nothing said (`N28`).** I took it for a fault in the middle of testing something else.
- **Two tempos I didn't choose (`N29`).** I'd have stopped and looked hard at 85 BPM on a 126 track, and the message tells me why, but not what to do.
- **Good surprise:** a mix going on past its last track, as of this round, feels right. I loaded something and it just carried on.

**3. Which control was hardest to find or hit?** Hardest to find is still the tempo fader. `JOG` with `TEMPO` under it is the right idea, in very small type. Hardest to hit on the small iPhone is that same fader, 7 pt from the platter. The gaps between keys, my answer last time, are gone.

## The first-time user

Upright on the folded Duo, from 02:32:58 to 03:19:18, 46:20 from opening. Clean install, with no backups in its Files, and seven tracks in `My Music`. No crash, and the process ran throughout.

**What I asked them about afterwards, in their words as near as I can:**

1. **What Auto DJ does.** "At about 13:25 from opening, when my first loop build finished: it loops the end of the playing track, takes that track's bass and lows out while a filter rises, starts the other track at a spot it picks, then stops the old one." **"The STEMS tip got me there."** It came at about +12:37, they put both decks on `STEMS`, and they watched `BASS`, `LOW` and `FILTER` move by themselves. The guide then named the move. It's only true of loop builds, and they say so: they didn't see an echo throw until about +32:00. Their first `AUTO` was at +4:56, and it couldn't do anything without stems. The first finished move came from their second press, at +9:54, and took 3:31, of which 2:16 was waiting.
2. **The tempo fader.** First seen at about +2:38, by pressing `JOG` with `?` on, and first moved at about +10:52. They weren't looking for it, as `SYNC` had done the job. They recognised it on sight, from what they already know about DJing. "I'm not sure I read" `TEMPO`.
3. **Swapping the `LOW`s.** At about +19:45, one knob after the other, after hitting the wrong knob. **The tip didn't lead them there:** it came at +1:57, they ignored it and crossfaded at +2:19. What did it was `?` on `LOW` at +16:47 and the guide's MIX TWO TRACKS at +19:22. They already knew about the bass swap, so they can't say how much the tip added for someone who doesn't. It's one person, and the tip came before they had any reason to care.
4. **Nothing, with no word.**
   - An EQ knob dragged sideways, though `?` says "left".
   - A playing deck's waveform, dragged, though a stopped one's scrubs.
   - A long press on a new empty playlist, as the list had jumped under them.
   - The Segue DJ folder in the Files picker, with three kinds of tap. It's the same as round 16's `N22`, and I skipped that this round as asked.
   - They also list a thumb, the Recordings icon and a memory cue's name field, and doubt each one themselves.
5. **The overview.** "It neither got in my way nor read as broken." They got the message once, by accident, and their one deliberate hold jumped first time because the message had told them how.

**How they use `?`:** "Press ?, tap anything, and you get a sentence or two that usually fits your exact situation." Which note didn't help:
- `LOW`'s "All the way left removes them" describes where the knob ends, and they tried it as a gesture.
- `AUTO`'s note doesn't name its moves. The guide does, and it took them 3 minutes to look.
- The guide's "Only keys that move between pages still work": column sorting works too, with the old note still up.
- Asking `?` about the key cell itself explained the bright key block. Asking about `KEY` didn't, and it took them 22 minutes, on and off, to try the cell.

**Best thing:** `?` and the messages. The one they'd show someone: "Auto DJ stopped. The decks are yours. Deck 1 is still looping. ALL brings back deck 1's stems."

**Worst thing:** "Things stay changed and the main screen doesn't show it." `N29`, a synced deck staying bent after the other's gone, `SPLIT` on for 22 minutes with no sign on the deck screen, the crossfader left on a deck that had run out for 2 minutes, and EQ knobs carrying over to the next track.

**Their brief was kept.** They read their own screenshots with a file tool, inside their folder, and say so. They say they know more about DJing than the brief, so a real newcomer would be slower.

**Their report follows unchanged,** with its corrections to itself, and mine are above.

---

# Segue DJ: a newcomer's 45 minutes (fu18)

iPhone Duo simulator, folded, upright. Opened at 02:32:58. Last touched the app at about 03:17:31 and last looked at it at 03:19:18, 46 minutes 20 seconds in all. No crash, freeze or restart.

I can't hear anything. "Sound" below means meters moving. I can't say whether anything sounded good.

**Reading this report**

- Times were checked afterwards against the clock and the timestamps on the test tool's screenshots. "About" means worked out from those rather than read off the clock. The raw notes at the end are rougher, up to 90 seconds out in places, and contain mistakes that I list there. Where they disagree with the sections below, trust the sections.
- Short messages had usually gone by the time I saved a screenshot, a few seconds after the tool's own. So many quotes come from what I read at the time, and the saved file only shows the state around them. Messages that are in the saved files: fu-05 (basslines), fu-12 (loop build starting) and fu-30 (echo throw done, with thumbs).
- The long presses at the far right of the screen (x 440, y 400) at about 02:50:34, 02:50:54, 03:06:45 and 03:10:19 were me waiting, as I had no other way to pause. They landed on empty screen, so ignore them in any touch log.
- From about 03:14:44 to 03:16:08 and from 03:17:33 to 03:19:18 I was re-reading my own screenshots, not using the app.

## 1. Every moment I wasn't sure what to do

**Where did my track go? About 02:33:50, 8 seconds, fu-03.** I pressed 1 on a track and expected to see a deck. The list stayed put, and the only signs were a blue 1 and the MASTER figure. I looked around and found DECKS at top left.

**What the bright key block means. About 02:33:50 to 02:55:55, on and off for 22 minutes, fu-03, fu-09.** One key in the list (1B) had a bright block and I didn't know why. Asking ? about the KEY filter at about 02:39 didn't settle it. Asking ? about the key cell itself did: it lights when it goes with the leading deck. It took me that long to try the cell.

**What the browser's KEY and ±6% compare against. About 02:34:26 to 02:34:36, 10 seconds, no screenshot.** I pressed them to find out. The list shrank but nothing said what it was being matched to. I turned them off and loaded a track anyway.

**Vocals wouldn't go. 02:36:28, a short wait, fu-06.** I pressed VOCAL to mute it. A message said "That happens when the split's done. It's at 82%." NO VOCAL lit up at once, as if it had already happened. The words were clear but the lit button said otherwise.

**The wave-shaped icon next to BROWSE. About 02:36:54, 7 seconds, visible in fu-01.** I took it for an audio setting. The first tap seemed to do nothing and the second opened Recordings. Nothing about the icon says recordings.

**My first AUTO. 02:37:54 to about 02:38:27, 33 seconds, fu-07, fu-08.** I wanted a transition and pressed AUTO with about 30 seconds left on the playing track. It showed a percentage and said "Auto DJ is waiting for the stems. If this track finishes first, deck 1 starts." The track ran out, deck 1 just started, the crossfader moved itself to the middle and AUTO went off: "The stems didn't get there in time. Deck 1 just started." It was honest, but I had no real transition until 02:46:23, over 8 minutes after that first press.

**"As SPLIT's off". About 02:39:45, 18 seconds.** Previewing a track gave "This preview's over the mix, as SPLIT's off. It won't be on a recording." I didn't know what SPLIT was. I found it in the MIXER sheet, where a sentence explains it. Then I left it on for 22 minutes (see section 5).

**LIM. About 02:42 to about 02:48:30.** I noted LIM lit red with both decks at full and didn't know whether to act. No saved screenshot shows it lit, so treat that as my note only. The guide's LIM entry answered it.

**Getting out of ?. About 02:40:30, about 6 seconds.** With the MIXER sheet up I pressed ? to turn it off. That closed the sheet and left ? on, so my next tap explained pad D instead of pressing anything.

**The fourth knob reading DUB. About 02:40:11 to 02:48:30, 8 minutes, fu-04 shows FILTER, fu-10 shows DUB.** I pressed the FILTER button in the MIXER sheet to see what it did, and only its own label changed. Later I noticed the deck knobs said DUB, and at first thought the app had changed them. Nothing in the sheet says that button changes a knob on the main screen. It also changes under you: during a build the outgoing deck's knob reads FILTER again (fu-12, fu-17).

**Effect pads, tap or hold. About 02:41:55 to 03:09:05, on and off for 27 minutes.** I couldn't tell whether a pad stayed on. By experiment, a tap stays on until tapped again and a hold lasts while held. The pad looks the same either way. Part of this was my tool's half-second lag, so a finger may settle it faster.

**How many pages MORE has. About 02:42:57 to 03:12:50, on and off for 30 minutes, fu-11, fu-22, fu-24.** I thought it simply cycled. In fact it goes back to the last page you used, and a second tap moves on. Its label changes to MEM, SLICE, JUMP or SMPL, and nothing lists the choices.

**What a "loop build" is. About 02:45:09 to 02:48:00, 3 minutes, fu-16.** "Loop build next, with deck 1 cued at 115 BPM." ? on AUTO doesn't name its moves. Searching the guide found "Auto DJ's moves", with one clear sentence for each.

**The thumbs. About 02:46:23 to 02:46:35, fu-14, fu-30.** I wanted to answer "More loop builds?" The message had gone before my tap, which landed on the overview and gave "Hold the overview for a moment to jump while the deck's playing". That was a good save, but I never answered. The message lasted under 14 seconds when I measured it later (present 03:05:35, gone 03:05:49).

**"2 tracks to go" out of 7. About 02:46:59 to 02:47:50, about 50 seconds, fu-15.** MIX said "Mixing through all your tracks, 2 tracks to go." I had seven tracks. I hadn't realised the ticks on the rows meant played. Searching the guide for "played" explained it.

**How to turn a knob. About 02:49:45 to 02:50:05, 20 seconds.** ? on LOW says "All the way left removes them". Dragging left did nothing. Dragging up and down turns it.

**Should a 115 BPM track go into a 148 BPM one? About 02:50:20 to 02:51:04, never settled, fu-17.** MIX did a loop build between them with neither tempo moving and no comment. I can't tell whether that's a good idea.

**The share button. About 03:01:47 to 03:01:55, about 8 seconds, fu-25.** The icon dimmed and nothing else happened, with no spinner, so I nearly tapped again. Then the sheet said "Plain Text and 2 Documents, 14.8 MB". It doesn't say what the three things are.

**Nothing coming out. About 02:55:44 to 02:58:00, about 2 minutes, fu-19, fu-22.** My crossfader was still hard over to deck 1 when that track ran out while I was in the browser. Deck 2 kept playing with its own meter up, but both mix meters sat at zero. MASTER said 2, and nothing said the output was empty. I saw it when I came back to the decks at 02:57:48 and moved the fader. The 02:55:44 start is worked out from the time left in fu-19.

**A folder I couldn't open. About 02:57:05 to 02:57:25, fu-21 shows the import result.** The Files picker showed a Segue DJ folder with 4 items. It wouldn't open with a plain tap, a firmer tap or a tap on its label, though My Music opened first time. That picker is Apple's, so this may not be the app. At about 03:03:05 the end of Settings explained that daily backups are kept in the Files app, so that is probably what the 4 items are. I never saw inside.

**Why did AUTO move my crossfader? About 03:04:58 to 03:05:22, fu-28 before, fu-29 after.** I had it at 2. AUTO moved it to the middle, reset deck 1's LOW (which I'd left fully down) and said "Crossfader to the middle, to hear both." That reads as an instruction, but it was already done. I expected "A control you touch is yours" to protect it. At about 03:10:15 AUTO likewise undid the SYNC I'd pressed on the other deck, with no message.

**A deck "playing" with an empty meter. About 03:05:22 to 03:05:29, fu-29, fu-30.** During an echo throw deck 2 still showed pause, all stems lit and its fader up, but its own meter was at zero, for about 7 seconds. I'd followed the advice to watch on STEMS and the pads showed nothing. It's what the guide describes ("it cuts"), but nothing on the deck showed it had happened.

**"Deck 1 is still looping". About 03:07:06 to 03:07:32, 26 seconds, fu-32.** I stopped AUTO mid-build. The message was the best in the app (quoted in section 5). But on the STEMS tab there's nothing that stops a loop, so I had to think to go to the LOOP tab for EXIT. The FILTER knob and BASS pad stayed where AUTO left them, and the message doesn't mention those.

**Why +1 turned 1B into 8B. About 03:09:38 to 03:10:47, about a minute, fu-34.** I expected 2B. ? on the + button explains: "A semitone is 7 places round the key numbers, so +1 takes 1B to 8B." It was exactly my case, once I thought to ask.

**Beats out with SYNC lit. First at about 03:04:34, retested at 03:17:31, fu-37, fu-38.** I scratched a synced deck and the beat blocks went orange and off-centre while BEAT SYNC stayed lit. At 03:19:18 they were green and centred again, without my doing anything. I don't know when or how that happened, or whether it's meant to.

**Half tempo. About 03:17:06 onward, unresolved, fu-36, fu-38.** I wanted to mix Houston (126) with Gepzene (128), two tracks 2 BPM apart. SYNC on Houston said "Deck 1 follows at half tempo: 85 against 170", because the finished track on deck 2 was still sitting at 170. Houston dropped 32.5% and its range changed to WIDE. Gepzene then followed at "double tempo: 170 against 85", up 32.8%. I ran out of time before finding a quick way to put them back.

## 2. How long each stage took

Measured from opening the app at 02:32:58. Tool calls are slow, so a finger would be quicker. My DJ knowledge also makes these faster than a real newcomer's (section 6).

| Stage | Clock | From opening |
|---|---|---|
| Library screen with instructions | about 02:33:05 | 0:07 |
| Getting music in ("Added 7 tracks") | about 02:33:41 | 0:43 |
| First track on a deck | about 02:33:50 | 0:52 |
| Found the deck screen | about 02:33:58 | 1:00 |
| First sound (meters up) | 02:34:06 | 1:08 |
| First time two tracks played together, not synced | 02:34:55 | 1:57 |
| Two tracks at matched tempo (SYNC) | about 02:35:05 | 2:07 |
| First move from one to the other (crossfader by hand) | 02:35:17 | 2:19 |
| First use of ? | about 02:35:30 | 2:32 |
| First read of the guide | about 02:37:14 | 4:16 |
| First AUTO press (no transition: stems not ready) | 02:37:54 | 4:56 |
| Second AUTO press | 02:42:52 | 9:54 |
| First recording started | 02:43:36 | 10:38 |
| First finished Auto DJ transition | about 02:46:23 | 13:25 |
| MIX pressed for a whole list | about 02:46:59 | 14:01 |
| First MIX transition finished | about 02:51:04 | 18:06 |
| First recording saved | about 02:51:24 | 18:26 |
| First hand mix from the guide's steps, clumsy | 02:53:13 | 20:15 |
| Second hand mix, fader starting on the playing deck | about 03:04:24 | 31:26 |
| Stopped | 03:19:18 | 46:20 |

Other timings:

- The first finished Auto DJ transition took 3 minutes 31 seconds from pressing AUTO: about 2:16 waiting for stems, 26 seconds counting bars and 48 seconds for the move.
- Stems took about 2 to 3 minutes a track on this simulator, which may not match a phone. Once a track is done, it stays done.
- The estimate sat at "5 s" at 99% for several seconds at about 02:45:00.

## 3. What I still can't explain, and wording that was wrong or no help

**Still can't explain**

- Why the list starts in the order it does (fu-03: 148, 125, 126, 128, 129.5, 139.7, 170).
- How AUTO picks a move, and whether the thumbs change anything. Over six moves it did loop build, loop build, echo throw, loop build, echo throw, loop build. A thumbs up at about 02:51:09 and a thumbs down at about 03:14:14 made no difference I could see.
- What counts as "a control you touch". My VOCAL mute during a countdown was respected. SYNC, crossfader and LOW set before pressing AUTO were not. My guess is that only touches after AUTO starts count, but I didn't test the fader during a move.
- How to put a deck back to its own tempo quickly. I only know dragging the fader.
- How far to trust section names. I saw CHORUS 73.4 (fu-35) and CHORUS 40.4 (fu-30), and Gepzene's opening changed from CHORUS (fu-07) to INTRO (fu-24) after its stems finished. The guide tells you to swap on a new section, and I can't judge the names without hearing.
- Why Fast Bird read 139.7 in the list (fu-15), 140.59 on the deck at about 02:51:04 and 140.06 later (fu-34). Nothing said it had changed.
- What the three shared items are, and whether SPLIT being on throughout my first recording affected it.
- "DJ library (XML)": what kind and from where. I had nothing to test it with. I also never saw the "=EQ" state.

**Wrong, misleading or no help**

- "A control you touch is yours." See above. It was true during a run, but it's not what I took it to mean.
- "Crossfader to the middle, to hear both." It reads as an instruction after the app has already done it.
- "Put both decks on STEMS to watch it", and the guide's "To see how it's done, put both decks on STEMS". This holds for a loop build. During an echo throw the pads stayed fully lit.
- "Mixing through all your tracks, 2 tracks to go." It skips played tracks, and the ticks aren't explained on screen.
- "Two basslines clash. ... The gear's guide h..." The message is cut off mid-word (fu-05).
- The guide's MIX TWO TRACKS says press PLAY, then turn LOW down, then bring the crossfader across. It doesn't say where the crossfader should start. It rests in the middle, so the new track is heard from its first beat with its bass in.
- "All the way left removes them" (? on LOW). It describes the knob's position, not the gesture, and a sideways drag does nothing.
- "Only keys that move between pages still work" (guide, on ?). Column sorting also works in ? mode, with the old help box left showing (about 02:39).
- "More loop builds?" reads like a question about what to do next, when it's a rating. "Got it. More like that." makes this clear only afterwards.
- One word for several things:
  - CUE is the big button and also the ? title for the headphone button.
  - KEY is a deck button, a browser filter and a list column.
  - ROLL and FILTER are each both an effect pad and something else.
  - SYNC and BEAT SYNC appear on the two views of a deck. I assume they're the same control.
- The Recordings icon looks like audio, and the playlist icon looks like a sidebar toggle but opens a menu.
- REC's "2:04 · 1" means nothing until ? says the number is tracks so far.

## 4. Anything that looked broken, however small

Nothing crashed. Some of these may be deliberate or down to my tool, and I say so where I suspect it.

- **All session:** the app stops about a fifth of the way short of the right edge, leaving a black strip with the camera cut-out in it (every screenshot). It may be deliberate, but knobs are about 30 points wide and I hit the wrong one at about 02:52:40. In guide search the back chevron sits alone in that strip (fu-16).
- **02:34:55:** message cut off mid-word (fu-05).
- **About 02:36:54:** Recordings icon, first tap showed nothing and the second opened it at about 02:37:01. May be a slow sheet.
- **About 02:37:25 to 02:37:43:** Done disappears from Settings once you scroll. Scrolling back or swiping down gets out.
- **About 02:38:42:** a track that had run out 17 seconds earlier sat at -00:00.4, not 00:00.0 (fu-08; compare fu-06 and fu-34).
- **About 02:39:29 to 02:39:33:** after creating a playlist the list stayed on All Tracks for a couple of seconds, then jumped, and my long press landed on the empty playlist.
- **About 02:39:** column sort worked in ? mode, with the old help box still up.
- **About 02:40:30:** ? with a sheet up closed the sheet and left ? on.
- **About 02:43:10:** a SLICE message stayed up over the JUMP page.
- **About 02:45:00:** stems estimate stuck at "5 s" at 99%.
- **About 02:52:05:** the tracklist collapsed itself when I renamed a recording.
- **About 02:56:46 to 02:56:51:** "Everything else here has been played" stayed up after I moved to another playlist, so "here" was wrong.
- **About 03:00:50:** during a held SLICE pad, RELOOP is orange on orange and hard to read.
- **Around 03:03:50:** when the fourth knob changes type it keeps its position, so a DUB I'd nudged became an off-centre FILTER.
- **About 03:11:34 to 03:11:39:** the memory cue sheet slid up as my tap landed and the name field didn't take my typing. A person would see it move, so this may be my tool.
- **About 03:14:14:** thumbs down gave no reply, where thumbs up said "Got it. More like that." Could be timing.
- **Also noted, not faults as such:**
  - Two hot cues a beat or two apart both read 2:33, as pads show whole seconds only (fu-24).
  - The Segue DJ folder wouldn't open in Apple's picker at about 02:57:05.

## 5. Best and worst for a newcomer

**Best: ? and the messages.** Press ?, tap anything, and you get a sentence or two that usually fits your exact situation, and the page-moving keys still work. The messages say what happened and what to do next. The best one was at 03:07:06: "Auto DJ stopped. The decks are yours. Deck 1 is still looping. ALL brings back deck 1's stems." That help, plus a clear empty library, took me from nothing to two tracks crossfaded in 2:19. Refusals are just as good ("Auto DJ brings in a stopped deck. Stop the one you want next.").

**Worst: things stay changed and the main screen doesn't show it.**

- Two tracks 2 BPM apart ended up at 85 and 170, a third slower and a third faster (fu-38), after SYNC followed a deck that had already finished.
- When the deck you followed ends, the SYNC light just goes off and your track stays bent: 170 against its own 129.53 (fu-06). The pads view shows no percentage at all.
- SPLIT sat on for 22 minutes with no sign on the deck screen (fu-26). The sheet says it puts the mix in one ear and the cue in the other.
- The crossfader sat on a dead deck for two minutes with nothing saying so.
- EQ knobs carry over to the next track you load.

Second worst: the first AUTO press usually can't work yet, because stems take minutes, so the most impressive feature is unavailable when a newcomer first reaches for it.

## 6. What I can't un-know

- **From how I was started, before I opened the app:** the working folder was /Users/nikhil/Cheeks, with cache folders named cheeks-autodj and cheeks-stems. So I knew the project has another name, an auto DJ and stems. I didn't open any of them. I also saw other agents named main and fu16, so I knew this was one of a series.
- **DJ knowledge beyond "roughly what a DJ does":** I know hot cues, memory cues, quantise, slip, key lock, beat grids, that tempo faders go up for slower, and key numbering like 5A, including that a semitone moves 7 places. So my "I don't know what 10A means" and my surprise at 8B were partly me playing the part. I also went straight for SYNC and the crossfader, and I guessed "DJ library (XML)" means another DJ program's export. A real newcomer would be slower and more lost on the deck screen than I was.
- **The app's name for itself:** Segue DJ, in the empty library text and Settings, with "Auto DJ" for the feature. I saw no other name. The name was also in my brief.
- **What my tool couldn't test:**
  - Double-tap to reset a knob, because two separate taps are too far apart.
  - Turning two knobs at once.
  - Holding a real phone.
- **Outside the brief's list of commands:** I re-read my own screenshots and this report with a file-reading tool, inside the fu18 folder only. I used no source code, docs, git or other simulators.

## What I left behind

Both decks still playing (Houston and Gepzene at those odd tempos), SLIP on, deck 1 on jog view, waveform colours on RGB, SPLIT off, the fourth knob back on FILTER. The library has seven tracks, a Warm up playlist, a recording called First go, and a few cues.

## Appendix: raw running notes

Written as I went. Mistakes in them, corrected above:

- Many times are up to 90 seconds out. For example, the preview at "02:41:20" was really about 02:39:45.
- The "77 s" loop build was 48 seconds.
- The deck with an empty meter "for at least 15 s" was about 7 seconds. fu-30 shows the finished echo throw and fu-29 shows the empty meter.
- "Echo latches on" is not shown in fu-10. The pad is unlit there, and it was probably tool lag.
- The scratch note cites fu-28, but by then Houston had ended and SYNC was off. Use fu-37 and fu-38.
- I said I changed the fourth knob "by accident". I pressed it on purpose and missed what it changed.
- The headphone complaint at 02:53:45 is withdrawn, as SPLIT was on then.
- The complaint that Settings says "Backups" while Files says "Segue DJ" is withdrawn. I never opened the folder, and the first screen names the Segue DJ folder.
- The thumbs message is not in fu-14 or fu-31, and the crossfader message is not in fu-29.

# Segue DJ newcomer test (fu18)

Running notes, tidied at the end.

- 02:32:58 launched. Splash for a few secs, then library with "No music yet" and very clear instructions.
- 02:33:06 tapped the import icon. Menu: Music files / DJ library (XML). Picked Music files. "Opening Files..." toast, 8 secs or so before picker shows.
- 02:33:41 "Added 7 tracks" (fu-02-added7.png).
- 02:33:50 tapped 1 on Exhilarate. Stays on library, no sign of deck except MASTER 1 170.00 and blue 1. Tip: "New to this? Press ? and tap anything... The gear has the whole guide." Tip overlaps first row.
- 02:34:00 DECKS. Screen packed but everything in view (fu-04-decks-first.png). Tip covers waveform on deck 1.
- 02:34:05 Play deck 1: meters up (first sound).
- 02:34:53 Deck 2 play (DJ Karda) unsynced. Toast "Two basslines clash... The gear's guide h..." truncated (fu-05-two-playing.png).
- 02:35:02 SYNC on deck 2. "Deck 2's 31% faster than its own 130 BPM, to follow."
- 02:35:15 crossfader to 2 by hand. First transition (crude).
- 02:35:30 ? mode: help box. Tapped JOG (flips deck to jog view, "JOG / PADS"), Q, AUTO, beat blocks, STEMS tab. Help box moves out of the way of what you tapped. Good. Tab keys work in ? mode.
- 02:36:30 turned off. Tried VOCAL mute on deck 2: "That happens when the split's done. It's at 82%." NO VOCAL lights up even though it isn't real yet.
- 02:36:45 deck 1 ended. Time 00:00.0 in red. Master went to 2, SYNC on deck 2 went off silently. DJ Karda stays at 170 (its own 129.5).
- 02:36:55 waveform-looking icon next to BROWSE = Recordings (first tap seemed to do nothing, second opened sheet). Icon reads as waveform or audio settings, not recordings.
- 02:37:00 Gear > Settings > What everything does. Very good guide with "Start here". Done button vanishes when Settings scrolled.
- 02:37:54 AUTO with crossfader on 2, deck 1 Gepzene not played. AUTO 5%. Toast "Auto DJ is waiting for the stems. If this track finishes first, deck 1 starts."
- 02:38:27 Deck 2 ended. Toast "The stems didn't get there in time. Deck 1 just started." Crossfader moved back to centre by itself, AUTO off, MASTER 1 128.
- 02:39:30 browser: ? works on KEY, 6%, NEXT, MIX, sidebar icon. Column headers sort. "1B" highlighted chip unexplained: seems to be the one best-matching key, but not said. Also ? help says only page-moving keys work, but the column sort does work in ? mode, with the old help box still showing.
- 02:40:20 New playlist "Warm up". Stayed on All Tracks for a couple of secs, then jumped to empty playlist, which swallowed my long-press. "Nothing in this playlist yet. Go to All Tracks, press and hold a track..." clear.
- 02:41:10 Long press menu: Load on Deck 1/2, Preview, Add to Playlist, Re-analyse, Delete from Library.
- 02:41:20 Preview: toast "This preview's over the mix, as SPLIT's off. It won't be on a recording." What is SPLIT? Toast runs over BPM/KEY headers, small and grey (fu-09-preview-split-toast.png).
- 02:40:00 MIXER sheet: Trim, Master, Cue/Mst, Level, SPLIT, FILTER cycle. SPLIT explained in place, nice. Tapping ? off with sheet open dismissed the sheet instead and left ? on, so my next tap (Done position) hit Pad D in help mode.
- 02:41 Hot cues A, B set by tapping empty pads. Both read 2:33 on the pad, though flags on the wave are a beat or two apart: the pad only shows whole seconds.
- 02:42 Waveform of Houston changed from orange to yellow/blue and section label from CHORUS to INTRO when stems hit 100%. No note about it, "AI" dot appears.
- 02:42:30 LOOP tab, pad 4: clear feedback, shaded region, EXIT. SOLO D, BEAT, works with obvious waveform change. FX tab: 12 effects + V/I/B/D target + OUT. Echo latches on after sliding: pad stays lit after lifting finger. (fu-10-echo-stems.png)
- LIM lights red on its own with both decks at full. Nothing tells a newcomer what to do.
- 02:42:10 AUTO with both decks playing: refused, "Auto DJ brings in a stopped deck. Stop the one you want next." Clear, and tells me how.
- 02:42:25 Tried to load Skylander on deck 1 while deck 1 playing: "Deck 1 is playing. Stop it first." Clear. Deck 2's load buttons not greyed though and could tap 1 while playing? They dim. OK.
- 02:42:30 Browser NEXT and KEY filters: NEXT re-sorts, "1B" chip moves. With NEXT on and KEY on, only DJ Karda. Then 5A chip when deck 2's master. Chip = best match for what's playing; nothing says so except ?.
- 02:42:50 While I fiddled in browser, Gepzene ran out to 00:00.0 and deck 1 sat at the end. Fine, but no warning from the browser page.
- 02:42:52 Loaded Skylander on 1, AUTO: "Auto DJ is waiting for the stems. If this track finishes first, deck 1 starts." AUTO 0% climbs in step with the "Stems 4%" under the deck 1 title.
- MORE > cycles MEM, SLICE, JUMP on each tap; label changes to current. SLICE toast stays up over JUMP page (stale).
- 02:43:40 SMPL page (MORE>'s last). Air horn lights while it plays. SET then pad: "Pad 1" sheet with One shot/Gate/Loop, Choose a File, Record the Master. Q on SMPL page lit; unclear whether it's the same Q as jog's Q (it's lit on deck 1 and I pressed it once).
- 02:44 REC: 0:00, then "0:13 · 1" with no meaning until ? says "how many tracks so far". Started recording while AUTO waiting.
- 02:44:10 JOG page: tempo fader up = slower, like real gear (-8.6%). Tested and BPM follows. Key stays 5A.
- ? answers on jog page: BEAT SYNC, MASTER, Q, SLIP, KEY, KEY SYNC, REC, BPM. All good and short. The waveforms get covered when ? is at the top but that's fair.
- 02:44:30 BPM down-arrow opens menu: Cues and loops, Save cue as memory cue, Beat grid reading, Set downbeat here, Grid 10ms later/earlier, BPM -/+0.1, Halve/Double the Reading. No way to know a newcomer should touch this. "the Reading" is a clear-enough phrase.
- 02:45:08 Stems hit 100 at about 2m15 after pressing AUTO. Stems estimate "5 s" at 99% for several seconds; then toast: "Loop build next, with deck 1 cued at 115 BPM. AUTO's counting down the bars." AUTO button now "AUTO 13", counting. fu-11. Skylander moved itself to 00:31.2 CHORUS at 115.21. "Loop build" unexplained; never mentioned by ? AUTO text that I read? (to check).
- 02:45:35 "Loop build starting. Put both decks on STEMS to watch it. A control you touch is yours." (fu-12). Deck 2's fourth knob turned DUB into FILTER on its own when AUTO got close. Deck 1 stems all dim, not lit; deck 1 waveform almost invisible.
- 02:45:55 During build the BASS pad on deck 2 fills from the top with a darker band (level going down), FILTER knob turns by itself with blue arc. A shaded loop region on deck 2's wave. Good thing to watch: this is the moment I understood what the pads' brightness means.
- 02:46:05 AUTO started Skylander (deck 1) itself; deck 2 kept looping with low + bass out, filter arc rising. REC count went 1 -> 2 about 02:46:15.
- 02:46:22 "Loop build done. Deck 1 is on. More loop builds?" thumbs up/down (fu-14). Deck 2 stopped, returned to CUE, its BPM snapped back to 126.00. Knobs all back to centre. AUTO off, MASTER 1. That's a full automatic transition. Took 77 s from "Loop build starting" (02:45:35ish) to done. AUTO stays off, so it only does one. Nothing tells me it will not continue.
- 02:46:35 Tapped where thumbs-up had been, toast had gone within ~10 s, so my tap landed on deck 1's overview: "Hold the overview for a moment to jump while the deck's playing." Nice guard. Never got to answer the thumbs.
- 02:46:45 ? AUTO: "Mixes the playing deck into the other, bringing parts in and out, which STEMS shows. Shows bars to go, % while the stems split, or ... as it chooses. A control you touch is yours. Press to stop. MIX in the browser does a whole list." Clear, though it doesn't say it needs the other deck loaded and stopped.
- 02:47:00 MIX in browser pressed while Skylander's on deck 1: "Mixing through all your tracks, 2 tracks to go. Up next: Severe Tire Damage." Status line at bottom too, and MIX button becomes stop square (fu-15). "2 tracks to go" out of 7: it's skipping the ones with check marks (played). The tick wasn't explained anywhere I've seen so I hadn't realised ticks mean played. Toast overlaps first row's top.
- 02:47:15 MIX replaced Houston on deck 2 with Severe Tire Damage without asking (Houston hadn't been stopped by me; it had finished its job). AUTO button now reads "MIX 5%" and counts the split. Quite fair, the toast did say.
- 02:47:30 Settings read again top to bottom: every option has a sentence under it. Good. "What everything does" has Search; "played" finds the tick under NEXT; "Loop build" found "Auto DJ's moves".
- Guide search: when searching, the back chevron drops into the row below the search bar and sits to the right of content (fu-16). Sheet looks a bit unfinished there but works.
- 02:48:30 Guide: "LIM" and "Dub" both find good entries. LIM entry answers my earlier worry exactly. The knob reading DUB was my own doing: first screen shows FILTER (fu-04); I must have tapped the FILTER cycle in the MIXER sheet at 02:40 without noticing what it changed. There's no sign in the MIXER sheet that it changed the deck knobs outside the sheet, at least none I noticed. Guide's "Auto DJ's moves": Loop build, Echo throw, Brake drop, Vocal tease, one sentence each. (fu-16)
- 02:49:10 MIX 65%: split is the wait. While MIX waits for stems, deck 2 shows a blue progress bar where AI dot normally is. Deck 1's waveform turns stem colours only when deck is on STEMS and back to orange when I move to ROLL: exactly as Settings says.
- 02:49:30 ROLL tab: tapped a pad? Toast "ROLL pads play for as long as you hold them." I hadn't tapped a pad, I tapped the tab. Tab-entry hint then. Fine.
- 02:49:20 ROLL pad 1/4 held 3 s: pad lit, RELOOP goes orange, loop length shows "1/4", overlaid on the 4. Lifting: track picks up further on, as if it had kept moving. Lag of perhaps a second before pad dims (might be the tool).
- 02:49:45 LOW knob: dragged down, blue arc, waveform lost its orange bass peaks. Works. ? LOW: "All the way left removes them, and that's how you stop two basslines fighting. Double-tap for the centre." Says left; knob responded to a downward drag. Sideways drag test next.
- 02:50:05 Sideways drag on knob does nothing. Up/down turns it (? says "left"). Drag back up snaps to centre, nice.
- 02:50:12 MIX 99 -> "MIX..." -> "MIX 9" (9 bars to go). Deck 2 moved itself to 00:25.9 CHORUS 8.4 before I saw anything. BPM still 148 on deck 2, no warning about 148 vs 115.
- 02:50:20 "Loop build into Severe Tire Damage - High Quality." with deck 1 at 115 and deck 2 parked at 148 BPM, 00:25.9, and its stems all dim. I'm a newcomer and don't know if a 115-to-148 mix is sensible; the app doesn't warn or mention the gap. "MIX" label has no countdown during the build itself (fu-17).
- 02:51:05 Loop build ended: MASTER 2 148.00. Deck 1 unloaded Skylander (still 4:25 of 6:05 played... it just got replaced) and loaded Fast Bird, 140.59 BPM (browser said 139.7). Stems 2%. MIX 2%. REC count now 3. Toast "Loop build done. Deck 2 is on. More loop builds?" Second time. It's the move I watched at 115->148 with both decks kept at own speed; tempo never bent to meet.
- 02:51:20 Thumbs up: "Got it. More like that." Clear. Tapped it in about 8 s of it appearing.
- 02:51:25 REC again: "Stop recording? Stop and save / Keep recording". Good guard.
- 02:51:30 Saved, toast "Saved Mix 2026-11-05 02.43.36" (start time, so a slightly odd name when stopping at 02:51). Saving didn't touch the music; MIX kept going.
- 02:51:40 Recordings sheet: tracklist with times, BPM, key. Lovely. Warning "A recording plays out loud, over the mix. To listen to one, stop both decks." Play button greyed while decks going. Tracklist shows Houston at 00:00, Skylander at 02:27, Severe Tire Damage 07:10 (fu-18). Shows artist names the library rows truncated.
- 02:52:05 Rename worked. Tracklist collapsed itself on rename, trivial.
- 02:52:10 MIX pressed: "Mix off. The track playing just carries on." Good and calm.
- 02:52:20 Followed "MIX TWO TRACKS" by hand. SYNC deck 1 -> 148.00 (Fast Bird from 140.59); the whole track shifted and the time jumped to -03:21.7. Waveforms have beat blocks with a green tick in the middle when they line up, which ? BEAT BLOCKS explained. Crossfader to 2, LOW down on 1, PLAY, bring fader back. Guide doesn't say "start with the crossfader on the deck that's playing" and the fader rests in the middle: a newcomer following its words just hears both from the first beat at centre.
- Slipped on knob: aimed for deck 2's LOW and hit DUB (knobs ~30 pts). Dragged too far up on deck 1's LOW: it goes past centre to a boost with no snap when moving fast. Double-tap reset not testable here: separate taps from this tool are too far apart.
- 02:53:00 First proper hand transition completed: crossfader full to 1, low back in (fu-19).
- 02:53:30 Pressed the deck 2 pause: master stayed 148 and moved to 1, deck 1's own SYNC went off silently (the blue light just goes). Deck 1 was playing at 148 still (its own 140.59). Nothing said deck 1 had stopped following, or that it was still sped up.
- 02:53:45 Headphone button lit blue with no effect I can see on this set-up; ? explains: "Sends this deck to your headphones... It takes SPLIT and a splitter cable... One output, like AirPods, can only play the mix." Ok, but pressing the button itself gave no warning that nothing's going to happen until SPLIT's on. Help title for the headphone button is "CUE", same as the big orange CUE button, whose help has title "CUE" too (fu-20). Two different things named CUE.
- 02:54:10 ? on Q, REV, range, KEY SYNC, all short and direct. Range title reads "+-6 +-10 +-16 WIDE" so I know the choices without pressing.
- 02:54:30 KEY SYNC on stopped deck 2: 5A to 10A, "-1" in blue, button doesn't stay lit. I'd guess that's right but no message says which key and why, and I don't know what 10A means; colour coding on key label changes too (pink to green). Deck 1 keys now 10A/10A.
- 02:55 REV turned red, jog needle ran backward, time went down. Works. Section number ("CHORUS 80.3") explained by ? WAVEFORM: "The number counts bars in the section." Doesn't say total. That section label "CHORUS" for 80 bars feels wrong (track 2's CHORUS at 62 too): the sections it finds look long. Can't judge musically.
- 02:55:30 BEAT SYNC on deck 2 with play: blue number, 148. Beat jump size is 4 -> 8 per tap, nice.
- 02:56 MEM page: SAVE CUE, SAVE LOOP, LIST, DEL. Pressed SAVE CUE: "Memory cue saved. The track loads here now." with UNDO. Toast clears after about 8 s. Good wording; first I didn't know what memory cue vs hot cue meant, and this tells me.
- 02:56:30 Browser ? on key cell: "A is minor and B is major. The same number, or numbers next to each other, with 12 next to 1, go together. It lights up when it goes with the deck that's leading." Finally explains the 11A chip I'd wondered about since 02:39. Useful, but only one chip lights (11A) when 10A itself should go too, and 9A/10B/11B aren't in my library so I can't tell. Fast Bird's own row (10A) doesn't light.
- Number oddity: Fast Bird read 139.7 in the library at first, 140.59 on the deck when it loaded, 140.1 in the browser now. Nothing told me it changed. (Deck reads +5.67% at 148, which matches 140.06.)
- 02:56:20 Correction to my key note: after Fast Bird ended, deck 2 leads at 10A (from its -1 key shift) and 10A + 11A both lit. So chips do follow the leading deck's shifted key, not the listed key. Sensible. Fast Bird ended while I was in the browser with no warning. Nothing playing on deck 1 but mix went on.
- 02:56:30 Playlist menu (the "sidebar" icon) shows History Nov 5, automatically made, in play order. Very nice to find. Icon looks like a sidebar-toggle though and does not open a sidebar: a little wrong to me. Button stays lit while on a playlist, good.
- 02:56:45 Long-press in History: Load 1/2, Preview, Add to Playlist, Remove from History, Re-analyse, Delete from Library. "Add to Playlist" lists Warm up.
- 02:57 In the import picker: there's now a "Segue DJ" folder with 4 items next to My Music. Wanted to see what they were. Picker slow to respond to a tap on it.
- 02:57:10 MIX with everything played: "Everything else here has been played. To go round again, stop the deck and press MIX." Good: refuses and tells me what to do. But the toast stays over the header after I changed playlist, so "here" no longer means where I am.
- 02:57:30 Re-imported Exhilarate while on Warm up: "Added 1 track you already had to this playlist." fu-21. No duplicate. Excellent. And it answers "where do imports go if I'm on a playlist?".
- Couldn't open "Segue DJ" folder in the Files picker with three tries (plain, firmer, on label), though My Music opened first time. It's the system's picker but it's odd. Never saw what the 4 items were.
- 02:58 Trap I set for myself: crossfader was still fully on 1 when Fast Bird ran out, so deck 2 was the only thing moving and its meter was up, but both middle (mix) meters sat at zero for over a minute. MASTER said 2. Nothing on screen says "you're playing to nobody". On a phone with no headphones I'd have just heard silence and hunted for why. A person hearing it would look at the fader soon enough, but the screen doesn't help. Crossfader moved: mix meters came up.
- 02:58:40 Loaded Houston on 1. Pads all empty for this track though I'd set A and B on it earlier in the session: pads are blank A-H (wait, I set them on Gepzene or Exhilarate? I set them on Skylander/Houston? need to check). Memory pads don't show a cue from earlier. One tap on pad A at start, pad reads 0:00. Red flag on wave.
- 02:58:50 IN then OUT by hand, while playing: orange shaded loop, loop number jumped to "3" in orange and RELOOP became EXIT. Very clear (fu-23). Time readout stuck at -04:44.0 for that loop? (time and remaining held during looping, while track stayed at 00:06.4.) Sensible but it looks frozen if you don't know.
- 02:59:05 EXIT: loop gone, RELOOP back. Deck 2 reached the end: its Master light moved to deck 1 and BPM jumped to 126 with no prompt. Fine. Deck 2's wave is blank with a thin line, ended time in red.
- 02:59:40 Corrected: pads A and B from 02:41 were on Gepzene, not Houston. Loading Gepzene back shows both, still 2:33, and flags on the overview. Cues stay with the track. Good.
- Deck 2 EQ knobs stayed where I'd left them when I loaded a new track (LOW slightly up, MID slightly off). Nothing draws attention. A newcomer's next track starts with a colour they forgot about. Double-tap to reset says ? help; can't do from this tool reliably.
- Deck 2 "AI" dot and stems all ready instantly, since Gepzene's been split. Stems remembered. Good.
- SYNC on pads view, BEAT SYNC on jog view: same thing under two names (assume).
- 03:00:00 DEL: red, then tap pad. Toast "Deleted hot cue B" UNDO. UNDO puts it back. DEL turns itself off after one, which I like. In ? mode the FX explanations are excellent: BRAKE's little square is explained ("the deck stays stopped"), OUT, VIBD.
- 03:00:30 OUT: "Echo out on deck 1. Press OUT again to bring it back." OUT turns red; blue dot appears on the FX tab so I'd find it from another tab. Meters drop though the waveform keeps moving. Nice.
- 03:01 Overview: hold jumps (as the app told me at 02:46), to 03:12 on Houston. Drag on stopped deck 2's wave scrubs it and its meter comes up, so you can find a spot. Pinch on the wave zooms both decks together. None of those are offered unless you try or read the guide, but all three felt right when I tried them. Drag across deck 1's wave while playing did nothing I can see.
- 03:01:20 SLICE: 8 purple pads. Held pad 3: lights up, the loop button above goes orange with RELOOP in a barely readable orange-on-orange, off-centre, and the loop length goes orange. Lift: back to normal. Don't know what SLICE plays other than the slice number; the ? answer I got at 02:43 helped. Tab label reads "SLICE >" and next tap moves to "JUMP >"; to get back to CUE you tap CUE. To find SMPL I had to press MORE four times and it isn't listed anywhere as a set of options: no way to know how many there are.
- JUMP page: back 1,4,16,32, forward 1,4,16,32. Instantly clear.
- 03:01:15 Stopped deck 1, as the Recordings warning told me to. Recording's play button then worked: slider moves, drag to 3:09 worked. Closed the sheet with Done while it was playing: the meters went quiet and on reopening it had reset to the start, no slider. So Done stops playback with no word about it. Acceptable, since it said it plays out loud over the mix.
- 03:01:50 Share a recording: icon dims, nothing else for ~9 s, then sheet: "Plain Text and 2 Documents, 14.8 MB" (fu-25). Nothing says what the three things are. I'd guess audio plus a tracklist. The wait had no spinner; I nearly tapped again.
- 03:02:20 Found I've left SPLIT on since 02:40, for 22 minutes (fu-26). Correction to my 02:53:45 note: when I pressed the headphone button SPLIT was on, so that complaint doesn't stand. The real point: nothing on the main deck screen shows SPLIT's on. MIXER is a plain grey button. On SPLIT, "the mix in the left ear and your cue in the right", which would matter a lot through a phone speaker or AirPods, and I forgot about it completely.
- 03:02:30 MIXER cycle button goes FILTER, DUB, SPACE, NOISE, CRUSH, PITCH, back to FILTER. Lit blue on everything but FILTER, so "lit" means "not the default". The sentence underneath only ever talks about SPLIT; nothing in the sheet says this button changes the fourth knob on each deck on the main screen, so a change here lands somewhere you can't see while the sheet's up. I'd changed mine by accident at 02:40.
- 03:03:05 Settings bottom answers the "Segue DJ" folder I couldn't open: "Segue DJ keeps a copy each day in its Backups folder in the Files app", and warns that deleting the app deletes those. Honest and useful, but only found by scrolling to the end of Settings.
- 03:03:50 Waveform colours to RGB: both big waves change instantly, the thin overview strips stay orange. Fourth knob label back to FILTER on both decks and its position carried over from when it was DUB, so it's now a filter sitting off-centre. Double-tap on knob to centre: my two separate tap calls were too far apart to count as a double-tap, so that isn't a finding about the app; I had to drag.
- 03:04:10 Followed the guide's MIX TWO TRACKS step by step, Houston into Gepzene, this time starting with the crossfader on deck 1. SYNC 128 -> 126; PLAY; LOW down; fader across; beat block bar stays green and centred, meaning (per ?) the beats line up. "Swap the two LOW knobs as a new section starts": section names on the waves do tell me when. Hard part: I can't do two knobs at once with one finger, so the swap isn't simultaneous; with a real hand you could.
- Deck 1 time turned red at -00:26.6 and jog ring went red: an end warning. Nothing explains it until ? on the time.
- 03:04:50 Scratched on the platter (jog ring) with BEAT SYNC lit. Time moved back, beat block in the strip between the waves went from green-and-centre to orange-off-centre (fu-28). SYNC stayed lit though beats are now out. Is this meant to be? SYNC's lit means tempo only, then? ? said earlier "SYNC so the beats match".
- 03:05:20 Loaded DJ Karda on 1 as its stems are done: AUTO reads "AUTO..." at once, no waiting, chose a move in seconds. "..." is explained by ? AUTO earlier ("... as it chooses"). LOW on deck 1 stayed fully down from Houston, so the next track starts with no bass, and I can't see whether AUTO will take that as "mine". Fader's on 2.
- 03:05:25 AUTO moved my crossfader from 2 to the middle by itself, reset deck 1's LOW, moved deck 1 to UP 3.4 and started it, BPM 126, and showed: "Crossfader to the middle, to hear both." (fu-29). This wording reads as an instruction to me, yet the app had already done it. Either it's AUTO's explanation or a hint from elsewhere, not clear. I thought "A control you touch is yours" meant it wouldn't move my fader. But I'd moved it earlier, before pressing AUTO; maybe only touches during AUTO count.
- 03:05:40 During AUTO, around 02:21 left on Gepzene: deck 2 is playing, all its stems lit, fader up, crossfader centre, HI/MID/LOW near centre, but its meter (the far right one) sits at zero, for at least 15 s (fu-30). Every visible control says deck 2 is on and it isn't reaching the meter. MASTER still says 2. AUTO shows no number now. I don't know what's holding it down. If you can't see it, you can't take it over.
- 03:05:45 "Echo throw done. Deck 1 is on. More echo throws?" (fu-31). So that silent spell on deck 2 was Auto's echo throw. It didn't show on the STEMS pads the guide told me to watch: the pads stayed lit and said nothing, unlike the loop build. That's the difference: "To see how it's done, put both decks on STEMS" holds for the loop build, not the echo throw.
- 03:06:10 Loaded Fast Bird, AUTO. Chose "Loop build" again (deck 2 at 140 BPM), AUTO counted 25, 20. Muting VOCAL by hand on deck 1 mid-countdown, to test "A control you touch is yours".
- 03:06:40 Browser KEY filter: only matching keys. KEY + "+-6%": narrower. Both clear and the row just shrinks; Skylander at 125 sits right by the BPM but has 11A, so it goes. Good little tool, once ? told me what the chip meant.
- 03:07:05 Pressed AUTO mid loop build. "Auto DJ stopped. The decks are yours. Deck 1 is still looping. ALL brings back deck 1's stems." (fu-32). Superb message: says what's still going on and what to do about it. My muted VOCAL stayed muted all through the countdown and build, so "A control you touch is yours" holds. Deck 2 went back to the start, stems lit. FILTER knob and BASS pad stayed where AUTO left them.
- 03:07:30 ALL brought back all stems as promised (also undid my own VOCAL mute, reasonable). "Deck 1 is still looping": on the STEMS tab there's no sign of a way to stop it, because the loop row's replaced by ACAPELLA/NO VOCAL. I had to think to go to LOOP for EXIT. FILTER knob on deck 1 stayed tilted where AUTO left it; message doesn't mention it.
- 03:08:05 BPM menu, Fast Bird: "Beat grid: 140.06 BPM at normal speed" and Halve the Reading: "Deck 2's track reads 70 BPM now. Its speed hasn't changed." Very clear. Double puts it back. Cues and loops sheet for this track: "Nothing saved yet. Set hot cues on the CUE pads, and save cues and loops on the MEM pads." Good empty state.
- 03:08:10 BRAKE held: deck stops and stays stopped, as the little square on the pad and the ? text said. CUE lights, play goes dim, meters fall (fu-33). If I hadn't read ? I'd have thought it had crashed the deck. Press play to restart.
- 03:09:15 FX pads: tap = stays on until tapped again; hold = on while held. Settled by experiment; both work and it's good, but the pad doesn't look different in either case. With my tool the display catches up half a second after lifting, which I read as stuck at first. Blue dot on FX tab when an effect's on. Swipe-down on Settings closes it, which I'd found by accident while trying to scroll back up to Done.
- Settings text calls it "its Backups folder in the Files app" but in the Files picker the folder's named "Segue DJ". Would have helped me know what I was looking at.
- 03:09:50 Jog view on deck 1 is a mirror of deck 2's. SLIP lit, scratched: elapsed time carried on as though playing, so SLIP does what ? says. KEY + : +1, key label went 1B -> 8B. I expected 2B. ? on the browser key says "numbers next to each other go together", so a one-step key change jumping seven numbers makes me think I've misread what the numbers are. Nothing explains it. Range +-10 -> +-16 moves the fader cap, keeps -2.7, keeps 126. Good.
- 03:10:15 BEAT SYNC on stopped Fast Bird (140 -> 126, -10.04%): the deck's range changed itself from +-10 to +-16 to fit, without a word. Reasonable, but I'd set nothing and it's now not what the button said. AUTO pressed with 20 s left on DJ Karda, to see what it does with so little time.
- 03:10:15 AUTO undid my SYNC on deck 2: sync off, Fast Bird back to 140.06, 0.00%, and no word about it ("A control you touch is yours" made me expect the opposite). Toast: "Echo throw next, with deck 2 cued at 140 BPM", AUTO 9. It's the same wording every time; I do get it now.
- 03:10:33 Exactly as deck 1 hit 00:00.0 and started to tail off, deck 2 played, "Echo throw starting" (fu-34). It fitted the last 18 s, which is neat. MASTER 2 140.06 at once.
- 03:10:45 ? on the key + - answers my 03:09:50 question word for word: "A semitone is 7 places round the key numbers, so +1 takes 1B to 8B." And it uses the example that happened to me. Withdrawn as a complaint. Only snag: you have to think to ask it.
- "Echo throw done. Deck 2 is on." came 20 s after starting. Deck 1 is then reset: tempo fader to +0.0, key shift to 0, BPM back to its own 129.53, my +-16 range left. Everything I'd done on that deck tidied without comment, though it's a finished deck, so fine.
- 03:11:30 MEM: SAVE CUE: bookmark on the first pad with 0:54, red triangle on wave and overview. "Memory cue saved. The track loads here now." SAVE LOOP with no loop: "Set a loop first, then save it." LIST: the cue under "Memory cues", with Name field and the time in blue. First go at naming: typed, return, and "Name" stayed empty: the sheet had slid up 30 pts under my tap so the field hadn't got focus. Tool timing may matter, a person would see the jump.
- 03:12:20 Named the memory cue "Good bit": the pad now shows the name instead of the time. Nice. Re-analyse on a playing mix: "Analysing Exhilarate again.", "..." in BPM and KEY for a few secs, back to same values. Exhilarate on deck 1: first section labelled CHORUS 1.1 while the wave's blank for many beats; Fast Bird's label reads "CHORUS 61, 68" and only then changes. Reads like a machine guess. I can't judge it by ear. It's the only name those sections have and they are what the guide tells you to mix on.
- 03:12:30 ACAPELLA while playing: lights pink, SOLO V lit, other stems dim, wave pink only, meter drop, tiny four-stem bar over the STEMS tab that I'd never noticed until now (fu-35). Instantly understood.
- 03:12:50 Loop pad 1/4 then MORE: it takes me straight back to MEM, because MORE remembers the page I last used. So tapping MORE when not on it = go back to last; tapping it when on it = next page. Correction to my earlier "it cycles". Took me a while, the tab label changes from "MORE >" to "MEM >". SAVE LOOP while looping: orange loop-icon pad, 2:07. No toast on this one that I caught.
- 03:13:05 Tap the lit saved-loop pad: leaves the loop, pad drops to dim. ? on the AI dot: "How the split's going. AI with a green dot means it's ready. =EQ is a rougher split by frequency, used when the full one isn't available." All clear. Never saw the =EQ state myself.
- AUTO this time cued deck 1 from 00:00.0 to 00:02.8: the first bit of Exhilarate that isn't silent. So "cued" means moved to a good spot. Sensible; the first waveform showed 00:00.0 was blank before.
- 03:13:40 SMPL: Q help: "With it on, a pad starts on the leading deck's beat rather than straight away." SET, tap pad 7 (RIM): "Pad 7" sheet: name, One shot/Gate/Loop, Choose a File / Grab Deck 2's Loop / Record the Master, with a clear note. "Grab Deck 2's Loop" while AUTO's loop build had a loop going: sheet closes, pad's now "LOOP 2" with a loop icon. RIM is gone with no message and no undo that I could see.
- 03:14:00 Correction: reopening Pad 7 shows a new "Restore the Original Sound" row, and it worked, RIM's back. So the replacement isn't lost; my "no undo" note stands only in that there's no message when it happens. "One shot" had changed to "Loop" on its own after the grab, sensibly.
- AUTO's second deck comes in with its stems off at first, and at 03:14 deck 1 is playing with all four pads dim, LOW and FILTER on deck 2 moving by themselves. Reads clearly as the same loop build as before.
- 03:14:30 Thumbs-down: toast just went, no reply seen (thumbs-up said "Got it. More like that."). Could be timing. ? BEAT BLOCKS: "Four blocks for each deck, one lit for each beat of the bar, mirrored about the middle... Red is the first beat. The scale in the middle shows how far apart they are." OVERVIEW: "The flags are your cues, and the colours its sections." Both good. So the coloured band under the overview = sections, not explained until you ask.
- 03:14:45 Import menu has "DJ library (XML)...". Doesn't say what kind of XML or from where. I have nothing to test it with, so I didn't try.
