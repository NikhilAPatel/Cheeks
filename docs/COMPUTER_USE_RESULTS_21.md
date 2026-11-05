# Hands-on results, part 21, 2026-11-05

Commit tested: aed9d58

Device:
- **iPhone SE Cheeks:** 667×375 on its side, for most of this, the long run and CPU. Upright (375×667) for `GO NOW`'s fit and the playlist's search field.
- **Folded iPhone Duo:** 466×678 pt, upright phone layout, for `HB1`, `HB2` and `HC2`, with a 400-row playlist.
- **iPad Air 13-inch (M4):** 1366×1024, the full layout. **Touch access works now,** so `HA` could run here, along with `C3`.
- **iPhone 17:** 402×874 upright, for the first-time user.

Tooling limits:
- **The Duo's still folded:** the last `hingeState:` says `Closed`, at 13:01 on 11-04, and I didn't reboot it. So `HA1` to `HA3` ran on the iPad instead, and say nothing about the Duo's own screen.
- **Can't be checked here:** how anything sounds, haptics, the headphone output and a real finger. Levels are read from recordings and meter pixels.
- **Double-tap on a knob:** two tool taps in a row did re-centre the knob this time, so that's as far as I can vouch for it. The first-time user's taps were too slow to count.
- **Screen reading:** a logger read the top of the screen by OCR about twice a second. It was off for the CPU table. It also died from 13:21:42 to 13:22:25 in the long run, which was my tool, and the screen and the recording cover that stretch.
- **Presses in a slide:** I froze the app with SIGSTOP so presses landed together. On the iPad I also let it run for 150 ms, then froze it, to land in the middle of a slide.
- **Busy Mac:** the first-time user ran beside my tests from 12:08 to 12:53. Another `Cheeks` process, not on my simulators, was at about 100% during the CPU table. I think that's `cheeks-6d`'s tests. Load average read 577 at 12:14.
- **Crash reports:** none from aed9d58. The newest are still the four from 09:08 and 09:10, which `cheeks-6d` says were from work that isn't in this round.
- **Logged faults:** only UIKit's "Decomposition of 'position'/'bounds' was requested" assertions, as last round: about 65 each on the small iPhone, 52 on the Duo, 127 on `iPhone 17` and 4 on the iPad. There's also an error-level "cannot add handler to 0 from 0 - dropping" from Core Animation on `BROWSE`. Nothing I could see came of any of these.
- **Slips of mine, not the app's:**
  - In the long run I pressed `CUE` on the deck on air at 13:22:42, which rightly stopped it.
  - I pressed too soon after one relaunch, so `PLAY`'s position hit `New Playlist` in the browser.
  - One `GO NOW` in the browser missed the key.
  - Two knob drags started off the knob, and one moved fader 2. I put it back.

## Summary

43 scripted tests including the long run: **41 PASS, 2 FAIL.** No crash reports from this commit. `HA1` to `HA3` pass on the iPad, and the Duo itself is still blocked.

**Five of last round's six problems are fixed, and the sixth, `N39`, is fixed except in a move's last bars.**
- **`N37`, a row out of a playlist:** it says so, and `UNDO` puts the row back in the same place, in a list of about 400 too.
- **`GC4`:** no phone lifted a row.
- **`N38`:** the fader sentence, the crossfader sentence, and silence with the fader up in time or `CUE` lit.
- **`N40`:** with the question up, `EXIT` says nothing and the question stays.
- **`N41`:** no grey on orange on video. A key goes dark in one frame, with its word.
- **`N39`:** this is the first failure below. Holding `CUE` works from well off, but not always in a move's last bars.

**The two failures, worst first:**
1. **`N42` (`HB4`): holding `CUE` on the waiting deck in the last few bars before an Echo throw can end the move, and a mix with it.** 3 of the 5 holds I started within 4 bars of an Echo throw did. Once it left both decks stopped, with 17.6 s of silence on the recording until I pressed `PLAY`. It reads "Mix off: deck 1 was stopped", though nobody stopped it. Holds from further off were all fine, and so was one at 2 bars on a Loop build.
2. **`N43` (`HC2`): in `Choose Several`, a row's load key also ticks the row.** 4 of 4 on the Duo, and one of those didn't load the track either.

**New this round that works:**
- **`GO NOW`:** in a mix it brought the move forward 13 times out of 13, on the decks and in the browser, on its side and upright. With `AUTO`, 25 bars became 17.
- **Speed:** with 2,005 tracks and both decks playing on the small iPhone, the worst gap in ten opens and closes was 0.108 s. On the iPad it was 0.155 s. In 14 fast flicks it was 0.067 s.
- **Saving:** killed straight after adding 2,003 rows to a playlist, the file's whole.
- **The stems warning:** it comes as `AUTO` is pressed, says what's coming, and music never stopped.
- **`MIX` going round again:** it says so, and carries on.

**The first-time user** could say what Auto DJ does at +9:52, and neither their first `AUTO` nor their first `MIX` ended in a plain cut. Last round's worst thing has gone. Their worst now is "MIX and AUTO change my decks without asking": `MIX` replaced a track they'd just loaded on the waiting deck. It's the rule as written, so that's your call. I saw the same at 13:47:35.

## Failures

### N42 (`HB4`): holding `CUE` on the waiting deck just before an Echo throw ends the move
- **Steps:** a mix or `AUTO`, an Echo throw counting down, then hold the waiting deck's `CUE` with the key reading about 3 bars or fewer.
- **Expected:** the preview ends by itself, or goes back when you let go, and the move runs.
- **Actual:**

| Time | Running | Move | Held from | For | What happened |
|---|---|---|---|---:|---|
| 12:23:05 | Mix | Loop build | 32 bars | 3 s | Fine: 00:09.6 to 00:12.2, kept counting, back to 00:09.5 |
| 12:23:43 | Mix | Loop build | 13 bars | 28 s | Fine: the preview ended between 3 and 2 bars, and the move ran |
| 13:20:11 | Mix | Echo throw | about 3 bars | 10 s | **"Mix off: deck 1 was stopped. Deck 2 carries on."** at 1 bar, finger still down. Deck 1 went back to 00:00.0 |
| 13:21:37 | Mix | Echo throw | 13 bars | 28 s | Fine: mix on and the move done afterwards (the logger was down, so that's from the screen) |
| 13:23:16 | Mix | Echo throw | 4 bars | 7 s | Fine: back at its cue by 3 bars, and the move ran |
| 13:23:53 | Mix | Echo throw | 3 bars | 3 s | Fine |
| 13:30:24 | Mix | Loop build | 2 bars | 3 s | Fine: 00:31.2 to 00:34.2, back to 00:31.2 when I let go |
| 13:32:49 | Mix | Echo throw | 1 bar | 3 s | **"Echo throw into Exhilarate." came up, then on letting go: "Mix off: deck 1 was stopped. Deck 2 has stopped too."** Both stopped. 17.6 s of silence on the recording until my `PLAY` |
| 13:43:30 | `AUTO` | Echo throw | about 3 bars | 2.5 s | **"Auto DJ stopped: deck 2 was stopped. Deck 1 carries on."** at 1 bar, finger still down |
| 13:44:05 | `AUTO` | Vocal ride | 13 bars | 3 s | Fine: 00:17.0 to 00:20.0, `AUTO` kept counting, back to 00:17.0 |
| 13:44:13 | `AUTO` | Vocal ride | about 8 bars | 21 s | Fine: the preview ended between 3 and 2 bars, the score started the deck, and letting go at 13:44:34 did nothing |

- **What I think is happening, from reading the code and not from testing it:** `AutoDJ.swift:1005` only ends a preview while the phase is `.armed`. An Echo throw's new deck starts early, so a preview can still be on when the clock starts. Then `Deck.cueUp` (`Deck.swift:632`) pauses a deck the score has started, and `noticeStoppedDeck` (`AutoDJ.swift:1138`) reads that as someone stopping it. The two Echo throw holds that passed may just have fallen the other side of that moment.
- **Why it matters:** the message blames a stop nobody made, and nothing on the waiting deck looks wrong beforehand. `HB4`'s other parts all pass: the mix and `AUTO` keep counting, and `PLAY` during the hold says "Mix off: you started deck 2 yourself."
- **Screenshots:** `docs/test-results-21/n42-a.png`, `n42-b.png`, `n42-c-auto.png`, `hb4-b.png`, `hb4-s.png`

### N43 (`HC2`): in `Choose Several`, a row's load key also ticks the row
- **Steps:** on the folded Duo, in `Choose Several`, press a row's `1` or `2`.
- **Expected:** "Tap rows anywhere but their load keys": the key loads, and the tick stays as it was.
- **Actual:**

| Press | Row | Loaded? | Ticked? |
|---|---|---|---|
| Plain tap on `1` | Severe Tire Damage | Yes | Yes |
| Plain tap on `2` | Skylander | **No** | Yes |
| 0.2 s press on `1` | Exhilarate | Yes | Yes |
| 0.15 s press on `2` | Gepzene | Yes | Yes |

- So a track you meant to load is now on its way into a playlist, and the only sign is a tick and a count going up.
- **Screenshots:** `docs/test-results-21/hc2-loadkey-ticks.png`, `hc2-2.png`

## Looks wrong
- **`EXIT` more than 3 s after a move:** "There's no loop to go back to yet. Press a loop size, or IN and OUT." still takes the question away, seen at +7 s and +8 s. The question's up for longer than the 3 s `isJustAfterAMove` covers. Within 3 s it's right (`hb5-d.png`).
- **The key pressed just as a move ends in a mix:** at 13:25:19, 0.6 s after "Bass swap done…", it read "Mix off. The track playing just carries on." and the question went. `wasMeantForTheLastMove` only guards the case with no mix, where the same press does nothing (13:37:58). A press meant to hand a move back, just too late, ends the mix.
- **"That's yours for this move" after a seek:** at 13:24:37 I held the overview to go past a mix's exit, touched nothing else, and that's what it said (`lr18.png`). The second time, at 13:33:30, it didn't. The replan itself was right both times: `CHOOSING`, then 6 bars.
- **Loading on the waiting deck just as a move's clock starts:** at 13:47:41, with about 15 s left on the track, "Mix off: the track changed. Deck 1 carries on." It ran out 12 s later, with the track I'd loaded sitting ready. A load any earlier says "Up next", and 4 of 4 of those held.
- **"The stems need 3 min, and this track has 3 min left. Deck 2 will just start at the end, with no move."** A tie reads as a contradiction, and it isn't certain: the first-time user got the same words and then did get a move, as their loop bought time.
- **Two numbers for one wait:** "Echo throw in 7 bars" with the key on 5 BARS half a second later, and "in 21 bars" with 19. I think one counts to the score's clock and the other to the move's start. Side by side, it looks like a mistake.
- **`GO NOW` isn't now.** The first-time user expected now and got 10 to 17 bars. It's a mild surprise, and the note explains it, but the name promises more than it does.
- **Number format:** "2005 tracks chosen." and "Added 2003 tracks" beside the sidebar's "2,005".
- **`?` on the fourth knob with `DUB` chosen:** it's headed "FILTER KNOB" and doesn't say what `DUB` does. The `FILTER ↻` key's note does ("DUB (echo)"), but you have to think to ask that key. The first-time user took 8 minutes to find out, through the guide's search.
- **`GO NOW`'s press has no reply until it's found something.** I never caught `CHOOSING` on the key after it. The old count stayed until the new one came, about 5 s once (13:32:33 to 13:32:38), and nothing on screen said it had been pressed.
- **The sheet on its side:** a sampler pad's `Restore the Original Sound` is off the bottom until you scroll.

## All results

| Test | Result | Notes |
|---|---|---|
| HA1 | PASS, iPad only | 2,005 tracks, both decks playing, 20 presses on video at 80 fps. Worst 0.155 s, 3 at 0.15 s or more, none at 0.2 s. The same as last time's stand-in. Not on the Duo |
| HA2 | PASS, iPad only | 4 launches frame by frame: the logo's unchanged until a one-frame cut to the decks. No double, no jump (`ha2-logo.png`). Not on the Duo |
| HA3 | PASS, iPad only | 5 launches on video: up once in about 0.15 s, at the top for about 1 s, back over about 2 s, starting as the logo goes. Not on the Duo |
| HA4 | PASS | **First time on the full layout since the slide changed.** Details below |
| HB1 | PASS | "Took Track 3 out of Friday." with `UNDO`. Back in the same place, checked in `library.json`, including Track 39 of 398, between 38 and 40 |
| HB2 | PASS | No lift for a 0.5 s hold and slide, or a 1 s hold and slide. Small iPhone in All Tracks and History, Duo in a playlist. No drag lines in UIKit's log on either. A hold opens the menu. No other way of lifting found. `Change the Order` and `Choose Several` are there |
| HB3 | PASS | "Deck 1 is playing with its fader down. Nothing's coming out." Once. None with the fader up in time, none with `CUE` lit. "Deck 1 is playing with the crossfader away from it. Nothing's coming out." On my first try the logger was stalled, so that one's unknown |
| HB4 | **FAIL** | `N42`. Everything else in it passes |
| HB5 | PASS | Pressed 0.4 s into the question: nothing said, and it stays (`hb5-d.png`). Later than 3 s, see Looks wrong |
| HB6 | PASS | 4 let-goes at 188 fps, 2 `ROLL` and 2 `SLICE`: lit `EXIT` up to the last frame, dark `RELOOP` on the next (`hb6-a.png`, `hb6-b.png`) |
| HC1 | PASS | Details below. Taking a loop off a mix that's given up wasn't reached |
| HC2 | **FAIL** | `N43`. Everything else in it passes |
| HC3 | PASS | Details below. I didn't reach the bottom of 2,005 rows |
| HC4 | PASS | Details below |
| HC5 | PASS | Details below |
| HC6 | PASS | "You've played all of Club, so this goes round again, 1 track to go. Up next: Houston." and "…4 tracks to go." The music didn't stop, and it played them |
| HC7 | PASS | Details below. `KEY SYNC` with no key known wasn't reached |
| A1 | PASS | Plain tap paused, and a 0.2 s press playing. The cue comes back and the capsule goes (`a1-stack.png`) |
| B1 | PASS | 445 frames, 8 presses: no lit meter samples at all. The same measure on music reads 1,715 |
| C1 | PASS | Index lines on the centre on both faders (`c1-caps.png`) |
| C2 | PASS | 2 pt stays either way, 3 pt leaves, and it catches coming back |
| C3 | PASS | iPad: the mixer stays where it was and the search field shows (`c3-keyboard.png`) |
| C5 | PASS | `PLAY`, the bottom pads and the crossfader, all first time, no system gesture (`c5.png`) |
| C6 | PASS | `BROWSE`, `REC`, the gear, all first time. Both choices in the alert |
| D2 | PASS | 4 flashes on video, back to where they were in 0.27 to 0.29 s. A held slicer pad's clearly brighter (`d2-slice.png`) |
| D3 | PASS | Lit as long as the sound: 0.24 s for `RIM` up to 4.03 s for `RISER` |
| D4 | PASS | `IN` lights and marks the waveform before `OUT` (`d4-c8.png`) |
| D11 | PASS | The bar follows the finger, right and left (`row.png`) |
| G1, G2 | PASS | All 8 fire. Only deck 2's grab, as only deck 2 had a loop (`g2.png`) |
| G3 | PASS | Gate: lit 0.54 s on a 0.5 s hold, 1.0 s on a 0.9 s hold. Loop: on and off |
| G4 | PASS | With deck 2's loop: `LOOP 2`, goes round. "Pad 8 plays deck 2's loop now. This sheet can bring back the original sound." |
| G5 | PASS | A red timer, then the pad holds it. The meters move with both decks stopped, once the music in it comes round (`g5m.png`) |
| G6 | PASS | `REWIND`'s back |
| G7 | PASS | `STOP` stops a looping pad. `VOLUME` down: no meters. Up: meters |
| H1, H2 | PASS | (`h1.png`, `row.png`) |
| H3, H4 | PASS | "Echo out on deck 1. Press OUT again to bring it back." "Echo out needs the deck playing." It comes back with sound after a pause (`h3.png`, `h4.png`) |
| I1 | PASS | `DUB`, `SPACE`, `NOISE`, `CRUSH`, `PITCH`, `FILTER`, under both knobs |
| I2 | PASS | Each way on a playing deck: no silence, no red. Two taps re-centre (`i-dub.png`, `i-e23.png`, `i-e45.png`, `i-e56.png`) |
| I3 | PASS | After the pause the meters fall over 6 s and more |
| Long run | PASS, apart from `N42` | 15:15, no crash, every gap accounted for. See below |

### HA4: pressing during the slide on the full layout
All on the iPad, with both decks loaded.

| Press | Landed on | Wrong cue? |
|---|---|---|
| `PLAY`'s place, in the slide's first frame, 2 times | Nothing | No |
| `PLAY`'s place, opening the browser | Nothing | No |
| `PLAY`, 150 ms into closing | The deck that was arriving: it started (`ha4-e.png`) | No |
| Pad A, 150 ms into closing | Hot cue A on deck 1, the pad arriving (`ha4-f.png`) | No, that's the pad I pressed |
| A row's `2`, 150 ms into opening | Loaded on deck 2 (`ha4-g.png`) | No |

Frozen frames show black beside the mixer. I think that's from my freezing the app, as the panels move in the render server and the mixer can't.

### HC1: `GO NOW`
- **In a mix on the decks:** 39 bars to "Echo throw in 7 bars, into Houston.", and the same in the long run: down to 6, 17, 7, 8, 5, 6, 13, 16 and 8 bars. The longest were 19 and 21 bars, which is your "about 20". The next track's cued, and the mix carries on after the move.
- **In the browser:** "Loop build in 12 bars, into Gepzene - Can't be Serious." (`hc1-browser.png`). "Mixing through Club, 4 tracks to go." with `GO NOW` along the bottom.
- **`AUTO`:** 25 bars became 17 at the press, the key went, and "Loop build next, with deck 1 cued at 128 BPM. AUTO's counting down the bars." came up again (`hc1-auto.png`). My two earlier presses, at 13:37 and 13:40, came after the key had gone at 24 bars, so they don't count.
- **Stopping the mix as it's pressed:** frozen so they landed together: "Mix off. The track playing just carries on." Deck 2 went back as it was, and nothing arrived afterwards.
- **Loading on the waiting deck as it's pressed:** "Up next: Skylander. The mix carries on."
- **A mix that's given up:** key reads `MIX`, "No clean way in. Next track starts when this one ends.", and `GO NOW`'s there (`hc1-given-up.png`). The track ran out before my press landed, and the next one started, with "No clean way in. Deck 2 just started." So taking a loop off wasn't reached, in three tries.
- **Upright:** it fits. `MIX`, `MIXER` and `GO NOW` stack, and the meters shrink to about 40 pt tall (`hc1-upright.png`).
- **Would a first-time user find it?** Yes: theirs found it at 14:52 by itself, read its note and used it four times.

### HC2: `Choose Several`
All pass apart from `N43`:
- A hold, then `Choose Several`: that row's ticked, with ticks for pictures, and "1 track chosen." along the bottom.
- Search for something else and tick more: the count keeps them.
- `ALL` chose all 5, and `NONE` went to "Tap the tracks you want." with `ADD TO` dim.
- "Added 3 tracks to Friday." with `UNDO`, in the order they were showing: I ticked Severe, Skylander, Houston, and got Severe, Houston, Skylander in the file.
- "Added 1 track to Friday. 1 already there." `UNDO` took it back out.
- `New Playlist…`: "Added 2 tracks to Saturday.", and it opens with them in it.
- `DONE` adds nothing. Deleting a ticked track asks first, and the count went from 5 to 4 (`hc2-del.png`).
- Leaving the browser ends it (`hc2-left.png`). A swipe still shows `Deck 2`.
- History's row menu offers it (`hist.png`). I didn't add from there.

### HC3: speed
- **Ten opens and closes, small iPhone, 2,005 tracks, both decks playing, the first-time user running beside it:** worst moving gap 0.108 s, at the end of a slide. There are 9 longer gaps of 0.4 to 1.09 s, and those are the browser fully open with nothing on it moving (`hc3-gaps.png`). No freeze.
- **14 fast flicks:** worst gap 0.067 s, with rows filled in. I didn't reach the bottom of 2,005 rows: my flicks covered about 37 rows each, and the scroll indicator didn't take my drag.
- **Its place:** it kept the same top row going to the decks and back.
- **On a row deep in the list:** the swipe and the hold both work (`hc3-ps.png`). The picture's preview works, and says "This preview's over the mix, as SPLIT's off. It won't be on a recording." (`hc3-prev.png`).
- **Memory:** see Timings.

### HC4: saving
| Did | Then | In the file |
|---|---|---|
| `SAVE CUE`, 1 s | `simctl terminate` | There at 1:54.3, and on its pad after relaunch |
| `SAVE CUE`, `HOME` at once | `simctl terminate` at once | There at 1:04.8, with the first |
| 2,005 tracks: added 2,003 to a playlist, `UNDO` | `simctl terminate` at once | 1.47 MB, whole, playlist back to 2 |
| 2,005 tracks: added 2,003 again | `simctl terminate` at once | 1.55 MB, whole, playlist at 2,005 |

### HC5: the stems not making it
| Case | At the press, or soon after | At the end |
|---|---|---|
| `AUTO`, 35 s left, new track at 8% | "The stems need 1 min, and this track has 35 s left. Deck 1 will just start at the end, with no move." Once | "The stems weren't ready in time, so there's no move. Deck 1 just started." (`hc5-a0.png`, `hc5-a2.png`) |
| `AUTO`, 28 s left, crossfader shut on the new deck | "Auto DJ is waiting for the stems. If this track finishes first, deck 2 starts.", then 8 s later "The stems need 3 min, and this track has 20 s left…" | "…Deck 2 just started, with the crossfader moved to the middle." (`hc5-c2.png`) |
| `AUTO`, 6:51 left | "Auto DJ is waiting for the stems…" only, for the 14 s I watched | Not run out (`hc5-d.png`) |
| `MIX`, 10 s left, stems at 84% | `MIX` / `STEMS 84%` | "The stems weren't ready in time, so there's no move. Deck 2 just started." (`hc5-g.png`) |
| Loading on the waiting deck in a mix, 3 min left | "The stems need 3 min, and this track has 3 min left…", 12 s after the load | "No clean way in. Next track starts when this one ends." It did |

No silence in any of them. Stems took about 70 to 95 s a track with nothing else running, and about 3 min beside the first-time user.

### HC7: words
- **"It takes over deck 2's SYNC, EQ and stems, and deck 1's effects."** It reads right with `FLANGER` and a muted vocal still showing (`hc7-a.png`).
- **"That's yours for this move. Auto DJ carries on with the rest."** On a knob touched at 3 bars, ahead of the clock (`hc7-b.png`). The mix's version says "The mix carries on".
- **`KEY SYNC`:** "Deck 2's down 1 to 6A, to go with deck 1's 5A." and "Deck 2's own key, 5A, goes with deck 1's 5A, so it needs no shift." (`ks1.png`, `ks2.png`). With no key known wasn't reached, as every track had one.
- **`Grab Deck 2's Loop`:** it says so, and the sheet's way back works.
- **Upright in a playlist:** "Search Club" (`u1.png`).
- **`MASTER`'s note:** "A paused deck goes on leading until the other one starts playing." That's what I saw: `MASTER 1` with deck 1 paused until deck 2 started.
- **`NEXT`'s note against its order:** with 148 on the master, nothing's within reach, so key decides: Houston 5A, Gepzene 1A, Skylander 11A, and what's on a deck last. That matches (`hc7-next-note.png`, `hc7-next-order.png`).
- **The words under `AUTO`:** `AT THE END` fits (`hc7-at-the-end.png`), and so do `STEMS 8%`, `98 BARS`, `CHOOSING` and `WAITING`.
- **Two messages, one after the other:** on video the old one's gone and the new one can be read within about 0.06 s (`hc7-two-messages.png`).

## Timings and measurements

### CPU, small iPhone, this simulator's process only

| State | Now | Last round |
|---|---:|---:|
| Idle, nothing loaded | 2.6% | 2.9% |
| Two tracks loaded, paused | 3.0% | 3.7% |
| One deck playing | 9.7% | 10.1% |
| Both playing and synced, tempo offset | 14.4% | 16.2% |
| Both of those, plus stems and an echo | 14.8% | 15.8% |

My first go at the last row didn't take, as the presses went in too quickly and the screen showed the vocal on and no echo. I checked the screen and measured again. Mac 15% to 53% idle throughout.

### Memory, from `footprint`

| State | Small iPhone |
|---|---:|
| 2,005 tracks, nothing loaded, at rest | 78 MB |
| 2,005 tracks, both playing, stems ready | 432 MB |
| The same, scrolling the browser | 442 MB |
| 5 tracks, two loaded and paused, stems ready (from `top`) | 426 MB |

Your 164 MB playing is well under mine, and I think that's stems: mine are two real tracks with their stems in memory. On the iPad, 499 MB playing with 2,005 tracks.

### The long run

Small iPhone on its side, `DUB` chosen, recording 13:19:09 to 13:34:28, **15:15**, mean -15 dB, peak 0.0 dB.

| Time | What I did | What happened |
|---|---|---|
| 13:19:40 | `EXIT` on the old deck, in a build's last 9 s | No word, and the build finished: "Loop build done. Deck 2 is on." Past the handover, so as it should be |
| 13:20:06 | `GO NOW` from about 70 bars | "Echo throw in 6 bars, into Severe Tire Damage" |
| 13:20:11 | Held `CUE` on the waiting deck | **`N42`:** "Mix off: deck 1 was stopped. Deck 2 carries on." |
| 13:21:24 | `MIX` again | "Mixing through Club, 3 not played yet." |
| 13:21:30 | `GO NOW`, held `CUE` for 28 s | Mix on and the move done |
| 13:22:42 | Pressed `CUE` on the deck on air, my slip | "Mix off: deck 1 was stopped." 14.1 s of silence until my `PLAY` |
| 13:23:10 | `GO NOW`, held `CUE` from 4 bars | Fine. "Echo throw into Exhilarate." |
| 13:23:48 | `GO NOW`, held `CUE` from 3 bars | Fine. "Echo throw into Skylander." |
| 13:24:16 | Loaded Houston on a mix's last track | "Up next: Houston. The mix carries on." |
| 13:24:27 | Froze, then `DECKS` and a tab | The tab on what was arriving took it |
| 13:24:37 | Seek past the exit | Replanned to 6 bars, and said "That's yours for this move" |
| 13:24:53 | Bass swap | 0.43 s breath at the handover |
| 13:25:19 | The key, 0.6 s after the move | "Mix off. The track playing just carries on." |
| 13:26:16 | Switched a saved loop on, on Houston | |
| 13:27:01 | **`AUTO`** 20 s into a Loop build | "Auto DJ stopped. The decks are yours. Deck 2 is still looping. ALL brings back deck 2's stems." (`lr-handback-auto.png`) |
| 13:28:17 | **`EXIT`** 20 s into a Loop build | "Auto DJ stopped: deck 2's loop was changed. The decks are yours. ALL brings back deck 2's stems." (`lr-handback-exit.png`) |
| 13:28:43 | Mix started on Houston, its saved loop on | Seeked back past the loop: not held |
| 13:29:19 | Froze, then `GO NOW` and the key | "Mix off." Nothing left behind |
| 13:29:44 | Froze, then `GO NOW` and a load | "Up next: Skylander. The mix carries on." |
| 13:30:03 | `GO NOW`, `CUE` at 2 bars | Fine. Went back when I let go |
| 13:31:13 | Thumb up, `GO NOW`, then a load | "Up next: Exhilarate. The mix carries on." |
| 13:32:49 | Held `CUE` at 1 bar | **`N42`:** "Mix off: deck 1 was stopped. Deck 2 has stopped too." |
| 13:33:30 | Seek past the exit | Replanned, no odd word |
| 13:33:47 | The key, in a move | "Mix off. The decks are yours. ALL brings back deck 1's stems." |

**10 `GO NOW`s, 6 holds of `CUE` on the waiting deck,** one right through a move, 2 seeks past an exit, 3 loads on the waiting deck, including one on the last track.

Every gap under -50 dB for 0.2 s or more:

| In the recording | How long | What it is |
|---|---:|---|
| 0:30 to 0:49, 6 gaps | 0.24 to 0.35 s | Gepzene's own, at 0:11 to 0:30 |
| 1:35, 2:05 | 0.23 s | Gepzene's own, at 1:15 and 1:45 |
| 2:08 | 0.2 s | Gepzene's own: it dips under -50 dB at 1:47.6 |
| 3:33 to 3:47 | 14.08 s | My slip at 13:22:42 |
| 5:52 | 0.43 s | The Bass swap's breath |
| 7:30 to 8:06, 40 gaps | 0.21 to 0.28 s | Houston's own at 1:10 to 1:16, going round in a build's loop and my hand-backs |
| 9:16 to 9:33 | 16.72 s | I stopped the only deck playing, to reload |
| 9:38 to 9:42, 9:59 to 10:05 | 0.21 to 0.23 s | Houston's own, played twice as I went back |
| 13:41 to 13:58 | 17.61 s | **`N42`.** The sound falls away in about 2 s and then there's nothing, until my `PLAY` |
| 14:40 to 14:48 | 0.21 to 0.31 s | Skylander's own, at 5:44 to 5:49 |
| 14:51 to 14:56 | 0.33 to 0.45 s | After I stopped a move: Houston with only its drums in, until I pressed `ALL` |

Afterwards the decks were usable, and what was left down or looping was said each time.

## First impressions

**1. Does it look like $1000 pro software?** On the iPad and a phone on its side, yes. The platters and the meters look expensive, the density reads as serious, and an empty deck's dim keys look like hardware that's waiting. The three things that break it:
1. **iOS's own menus.** The `BPM` menu has "Back to Its Own Speed" and "Grid 10 ms earlier" in one system list over the mixer, and a row's menu looks like Files. Everything else looks made, and those look borrowed.
2. **Messages over the waveforms.** They're good sentences, and they sit on what you're watching, for up to 10 s. The first-time user says the same.
3. **Upright on a small phone.** The meters shrink to a stub beside `GO NOW`, and it's tight. It works, but it's the one layout that looks squeezed.

**2. What felt slow, confusing or surprising?**
- **Slow:** stems. Everything good waits for them, and they take a minute or three here. `CHOOSING` took 14 s once.
- **Confusing:** two counts for one wait, and `GO NOW` not being now.
- **Surprising:** `MIX` replacing what's on the waiting deck, and `N42`'s "was stopped".

**3. Which control was hardest to find or hit?** `UNDO`. It's in a capsule that moves with the length of its message, and I missed it at least three times on the Duo. For a thumb it's a small target near the top, and it goes away by itself. After that, the overview's hold, as nothing shows you where you'll land until it's happened.

## The first-time user

`iPhone 17` upright, 12:08:53 to 12:53:56, 45:03, no backups in its Files, through the `Explore` subagent. Their report's at the end, unchanged, and their screenshots are `fu-*`.

| Stage | This time | Last time |
|---|---:|---:|
| Music in | 0:37 | 0:44 |
| First sound | 1:05 | 1:11 |
| Two tracks together | 3:19 | 1:49 |
| First move by hand | 3:57 | 2:29 |
| First press of `AUTO` | 5:57 | 6:29 |
| First automatic move finished | 9:52 | 10:09 |
| Could say what Auto DJ does | +9:52 | +10:09 |

**Your questions:**
- **How long until they could say what Auto DJ does?** +9:52. By the end it was right on splitting, on coming in past the start, on stopping the old track early and on a touched control staying yours. It was wrong on tempo, as it only matched close ones, and "a part at a time" only described a Bass swap.
- **Is the first `AUTO` and first `MIX` still a let-down?** Neither ended in a plain cut.
  - **`AUTO`:** the warning came straight away and was enough about the wait. Then after 2:50 of waiting: "Auto DJ stopped: deck 2 is in a loop." They'd set that loop during the wait, and nothing said it mattered until then. Pressed again, it did a Bass swap within a few bars.
  - **`MIX`:** it replaced Houston, which they'd just loaded on deck 2, with Gepzene. It said what was next, but not that their choice had gone.
- **Do they find `GO NOW` or `Choose Several`?** Both, by themselves. `GO NOW` at 14:52, from the middle column. `Choose Several` in a row's menu at 20:17, used at 30:22, because an empty playlist's words sent them to hold a track. It did what they expected.
- **What's still doing nothing with no word?** Almost nothing, and most of it they doubt themselves:
  - Thumbs up looked like no reply, twice. I saw "Got it. More like that." at 13:38:08, so that's their snapshots.
  - Grey `Play` on a recording with decks running: it has a note, which reads like advice and not a block.
  - Taps missing the mixer sheet while it's still rising, twice.
  - Dragging the platter shows nothing on screen.

**Best, in their words:** "watching an automatic move on both STEMS pages… It teaches mixing without a lesson."

**Worst, in their words:** "the app acts on my decks without asking." `MIX` replaced a track, cues and tempos move, and "the reasons are in short-lived toasts that cover what they describe."

**What I checked of theirs:**
| They reported | What I found |
|---|---|
| "Up next: Houston" going back to another track within 8 s, once, after two taps | Not reproduced: 4 of 4 held for me, with one tap each |
| "No recordings yet" just after saving a recording of about 9 min | Not reproduced: 14 s long and about 3 s later on the iPad, the list had it (`rc.png`) |
| The `BPM` arrow resetting the tempo with no word | My one tap opened the menu. `Back to Its Own Speed` is first, under the finger, and says nothing at 2.3%, as the rule has it |
| `MIX` replacing a loaded track | Yes. At 13:47:35 Houston on deck 2 made way for Exhilarate |
| The `DUB` note | Yes, `Explanations.swift`:170 |
| "The sidebar" on `PLAYLISTS` | The note goes on "or choose it and open this menu on an upright phone" (`Explanations.swift`:205), so it covers it |

**Their own reports I haven't checked:** pinch-zoom staying on with nothing to show it, `TRIM` not coming back to centre after dragging the same distance down and up, and `SYNC` going dark with no word on deck 2 after stopping both decks.

### Not tested
- **On the Duo unfolded:** everything. It's still folded.
- **`GO NOW` taking a loop off a mix that's given up,** `KEY SYNC` with no key known, adding to a playlist from History, and the bottom of a 2,005-row list.
- **A real thumb,** especially on `CUE` in `N42`, and on the slide from a hold to `Remove from Playlist`.
- **How anything sounds,** haptics and the headphone output.

## Running notes

Opened the app at 12:08:53 (simctl launch).

- 12:08:53 opened. Splash, then Browse screen with "No music yet" and an import button already glowing blue. Clear.
- 12:09:04 import button gives Music files / DJ library (XML). About 6-7s of "Opening Files..." before the picker. Files opened on On My iPhone with My Music and Segue DJ folders.
- 12:09:30 "Added 7 tracks." Hint on the empty screen was accurate. Selecting all 7 was easy. fu-first-screen.png, fu-tracks-added.png
- 12:09:40 tapped 1 on Fast Bird. Toast covers the top row for 10s+. Library said 139.7 BPM; MASTER and deck show 140.59. fu-loaded-toast.png
- 12:09:50 DECKS. Very dense screen, two decks plus mixer all at once. Toast still there and still saying "DECKS takes you there" though I am already there; it hides the waveform. fu-decks-first-look.png
- 12:09:58 Play: meters moved, clock moved. fu-first-play.png
- 12:10:36 Deck 2 loaded (Skylander). Used ? mode from 12:10:40 to 12:11:50: AUTO, SYNC, JOG, Q, SLIP, KEY, BEAT BLOCKS, RECORDINGS, MIXER all explained well. BPM on deck 1 wandered 139.6-141.6 with +0.00% pitch. Library says 139.7. fu-both-playing.png
- 12:12:05 SYNC on deck 2: toast "Deck 2 is now 12% faster than its own 125 BPM, to follow." with UNDO. Good.
- 12:12:12 Play deck 2: both meters moving. Tip "Two basslines clash..." appeared. Useful.
- 12:12:25 LOW knob turned with a vertical drag, worked first time. Swapped LOWs and moved the crossfader to 2 at about 12:12:45. fu-crossfaded.png
- 12:13:35 Fast Bird ran out (I hadn't stopped it). Toast "Deck 2 has nothing to follow now, and stays at 140 BPM, 12% faster than its own." Clock red 00:00.0, CUE glows. fu-track-end.png
- 12:14:00-12:14:30 ? in Browse: KEY filter, +-6%, NEXT, MIX, PLAYLISTS, 1/2, KEY column. All clear. PLAYLISTS mentions "the sidebar" on a phone that has no sidebar I can see.
- 12:14:35 NEXT: top pick Severe Tire Damage 148 BPM 5A while master is Skylander 11A at 140. App's own "best" is in a key it doesn't light. Skylander vanishes from the list. fu-next-sorted.png
- 12:14:50 Pressed AUTO with Severe Tire Damage on deck 1 (0% stems) and Skylander playing on deck 2 with 3 min left. Button became AUTO / STEMS 7%. Toast: "The stems need 3 min, and this track has 3 min left. Deck 1 will just start at the end, with no move." First time I saw "move" used for a transition. I had expected AUTO to mix. fu-auto-pressed.png
- 12:15:10 Settings > What everything does: good Start here section (load and play, mix two tracks, let it mix). fu-guide-start-here.png. Would never have looked in Settings for that without the toast.
- 12:15:45 Loop pads on deck 2: pressed 4, orange shaded region on waveform, RELOOP becomes EXIT, beat counter 4 lights. Clear. While looping the elapsed clock sits around 04:19-04:20.
- 12:15:55 FX tab on deck 2. Toast "FX pads slide: up and down for depth, left and right for the beat." Pressed ECHO and slid: DEPTH bar went full and stayed full after release. LIM lit red. ? on V I B D, OUT, LIM, headphone CUE: all good. LIM says TRIM is under MIXER on a phone.
- 12:16:30 MORE > opened MEM page. Toast explains SAVE CUE / SAVE LOOP.
- 12:16:47 SAVE LOOP filled the pad with "4:18" and a loop icon, orange. LIST shows the loop with an unlabelled name field and an unlabelled switch; its footnote explains. fu-save-loop.png
- 12:17:20 Mixer sheet. FILTER tapped once with no effect because the sheet was still sliding up under my finger (the sheet jumps ~20pt after opening). 2nd press went to DUB. Fourth knob on each channel now says DUB. Nothing tells me what DUB is until ?.
- 12:17:30 ? on the DUB-labelled knob: heading is "FILTER KNOB" and it never says what DUB does. No explanation of DUB. MIXER page says only "the key with the arrows chooses what each deck's fourth knob does."
- 12:17:40 AUTO waited 2m50s for stems then "The stems are ready. Auto DJ is choosing a move." AUTO / CHOOSING. fu-auto-choosing.png
- 12:17:47 "Auto DJ stopped: deck 2 is in a loop." My fault but after almost 3 minutes of waiting nothing warned me while it was still waiting. Honest message though.
- 12:17:55 Exited loop, pressed AUTO again. fu-auto-move.png
- 12:18:00 AUTO: "Bass swap next, with deck 1 cued at 140 BPM. It takes over deck 1's EQ, and deck 2's EQ. AUTO's counting down the bars." Button AUTO / 3 BARS. My LOW knob on deck 1 snapped back to centre by itself and the deck 1 cue moved to Chorus (00:12.9). Crossfader jumped to centre a few seconds later. fu-auto-bass-swap-next.png
- 12:18:10 "Bass swap starting. Put both decks on STEMS to watch it. From here, a control you touch is yours." Deck 1 playing, DRUMS pad fading up from the bottom. Deck 2 knob label went back to FILTER, deck 1 still says DUB. fu-auto-bass-swap-running.png
- 12:18:20-12:18:55 Watched the move on both STEMS pages: pads fill from the bottom, small 4-colour dots above the STEMS tab show what's up. Deck 1 stacks DRUMS, then INST, then a short moment where both decks' pads looked dark (12:18:38 fu shot), then deck 1 all on and deck 2 drums only. LOW knobs swap. It's very readable and is the best thing I've seen so far. ? mode during the move let me read STEM STATUS, ACAPELLA / VOX ("Just the vocal."), SOLO without disturbing anything. fu-auto-swapped.png
- 12:18:45 "Bass swap done. Deck 1 is on. More bass swaps?" with thumbs up/down. Move took ~45s from bars countdown. Deck 2 stopped itself and reset: BPM back to 125.00, LOW and fourth knob back to centre, fourth knob back to DUB (what I'd chosen). Crossfader left at centre. Deck 1 stays -5.4% (140.06), SYNC MASTER now shown on deck 1. fu-auto-done-rating.png
- 12:19:10 Rated the move thumbs up: toast just vanished, no acknowledgement. AUTO went back to plain, deck 2 stopped and cued itself. Note deck 2's clock says -00:37.2 / 05:23.0 with BPM back to 125.
- 12:19:20 Tried deck 2 ACAPELLA while stopped: pad states change immediately. Pressing ACAPELLA again to clear it didn't look obvious, ALL did it.
- 12:19:25 JOG on deck 1: PADS page swaps for a platter, pitch fader, BEAT JUMP, Q, SLIP, KEY, REV, KEY SYNC. The JOG button becomes PADS, same spot but in the title strip. fu-jog-page.png. Dragging round the platter while playing: clock kept going, no visible jump.
- 12:19:35 BEAT JUMP: right arrow moved forward 1 bar; middle 4 -> 8 by tapping.
- 12:19:45 ? on JOG WHEEL, ±10, REV, KEY SYNC good. My earlier drag was on the record's middle while playing; ? says the record scratches and the ring nudges. REV works: clock counts down, REV goes red, BEAT positions go backwards.
- 12:20:05 SLIP + REV: while reversed clock ran back 01:52 to 01:44, on REV off it jumped forward to 02:05 which is where it would have been. Worked as ? promised. 
- 12:20:40 Wanted the dropdown under the BPM number. Tap on the readout (a chevron next to "-5.4%") silently reset deck 1 from 140.06 to 148.00, also moving MASTER. No toast, no undo (SYNC gets a toast + UNDO; this doesn't). Tap again on the same chevron, now next to "BPM": opens the menu. So the same chevron does two different things depending on whether the tempo's been moved. I'd read a chevron as "menu". fu-bpm-menu.png
- 12:21:20 CUE pads A-H: empty pad sets a hot cue (coloured flag on the waveform and overview, time on pad), lit pad jumps. Empty pads have no hint. DEL lights red, next pad deletes, toast with UNDO, DEL un-lights itself. Very clear. fu-hot-cues.png. "Cues and loops..." empty state OK.
- 12:21:40 REC: starts immediately, button grows to red 0:02. Pushes MASTER readout right. No toast saying where it goes (? told me earlier: Settings > Recordings). Later shows "0:12 · 1", I don't know what "· 1" means; maybe tracks.
- 12:21:50 NEXT list: Skylander just finished, shows a tick, shows it's on deck 2. Now list includes it again. Tick = played. ±6% filter: "1 of 7 showing, with ±6% on." Clear, and a yellow dot. Fast Bird 140.1 is in range of 148 (5.3%). Good.
- 12:22:00 Loaded Houston on deck 2 from the list. The list re-sorts under me: Houston moved from row 1 to the bottom within 5 seconds of the tap. A bit disorienting. Then MIX: toast "Mixing through all your tracks, 4 not played yet. Up next: Gepzene - Can't be Serious." It REPLACED the Houston I just loaded on deck 2 with Gepzene, without asking. Houston not ticked, so still to come. Status bar at bottom "Mixing through all your tracks, 4 tracks to go." fu-mix-started.png
- 12:22:25 Waveform icon next to BROWSE is Recordings, not a waveform view. I keep having to remember this. Nice empty state "You're recording now, and it'll be here once you stop."
- 12:22:40 ROLL: 1/16...8. Toast "ROLL pads play for as long as you hold them." Pad lit while held, clock stays honest after release. MORE cycles MEM > SLICE > ... each press replaces the tab name. Hard to know how many pages there are.
- 12:22:55 MORE cycles MEM > SLICE > JUMP > SMPL >... SMPL has AIR HORN etc. Pad lights while held. Sampler isn't on the meters as far as I can tell (can't hear).
- 12:23:15 ? on SET says pads can hold "a file, a deck's loop, or a recording of the mix". The Pad 8 sheet only offers Choose a File and Record the Master. No deck-loop option on that sheet (though nothing was looping then, maybe it appears when something is). 
- 12:23:30 SET then REWIND > Record the Master: sheet closes, pad goes red with a record dot, SET turns into stop with timer. Clear. Pressed stop.
- 12:23:40 REC 8 worked; green toast "Pad 8 has your recording. SET and then the pad can restore its original sound." Pad renamed REC 8. Toast covers deck 1's waveform for ~10s. fu-sampler-recorded.png
- 12:23:45 After stems reach 100% MIX shows "MIX / 37 BARS" and a new GO NOW button appears in the middle column, squeezing the meters. ? on GO NOW good. fu-mix-go-now.png. Deck 2 waveform re-coloured and section label changed from CHORUS to INTRO when stems landed (the first label was wrong/provisional and nobody says so).
- 12:24:00 GO NOW: "Echo throw in 10 bars, into Gepzene - Can't be Serious." fu-echo-throw-next.png. Section label "UP" on the waveform, unexplained; I guess build-up.
- 12:24:30 Echo throw ran: deck 2 STEMS pads dimmed for one bar then all lit as it started, deck 2 at 128.00 with MASTER 148.00 and no matching. Deck 1 meter went dark, deck 2 meter up; deck 1's clock and waveform still moving but nothing on deck 1's controls says it's been silenced: pads all lit, fader up, crossfader centre, HI/MID/LOW/DUB centred. So the meter is the only sign. Button is plain MIX now. fu-echo-throw-running.png
- 12:24:40 Mix moved on: master now deck 2 Gepzene, deck 1 auto-loaded DJ Karda - Alone with stems 6%. REC shows "2:55 · 2" so the dot number is tracks. Severe Tire Damage was dropped with about 40s left, no rating this time, no message. If I'd looked away I'd have missed it. Rating only came for AUTO, not for MIX so far.
- 12:25:00 Settings: "Every control, explained." Help search works: "dub" -> FILTER: DUB (echo), SPACE (reverb), NOISE, CRUSH, PITCH. Good answer, buried. Search for "grid" gives No Results, though the Library note says backups hold "beat grids". 
- CORRECTION to my earlier note: Settings says "A deck on STEMS shows its stems' colours". So the waveform going blue/yellow wasn't stems arriving, it was the deck being on the STEMS tab. I'd misread that, nothing on the deck says it.
- 12:25:05 Accidentally dismissed the Settings sheet by swiping down in it to scroll back to top (the sheet closes), my fault but note the mis-swipe lands on the deck below.
- 12:26:00 BPM menu: "Beat grid: 128.00 BPM at normal speed", Double/Halve the Reading, BPM +/- 0.1, Grid 10 ms earlier/later, Set downbeat here, Save cue as memory cue, Cues and loops... Sounds pro. Help says "fix the beats if they're off" but I can't hear so no way for me to judge.
- 12:26:20 ? on waveform: "UP's a build-up, DOWN a breakdown." Number counts bars. Answers what I'd guessed. Help for it is on the waveform itself; I'd not have guessed I could ? a waveform. Drag on stopped deck 1 waveform moved it (00:01.6 -> 00:05.0). Pinch zooms both waveforms together.
- 12:26:45 Mixer sheet: TRIM 1/2, MASTER, CUE/MST, LEVEL, SPLIT, DUB key. Sheet rises in two steps; my tap on Done at its first position missed because it had moved 20pt up by the time it landed. Second time this happened (also FILTER key at 12:17).
- 12:27:00 During MIX, deck 1's tempo was set to 128 (-1.2%) and its cue moved to 00:23.1, by itself, while I'd dragged it to 00:05. Countdown on the MIX key only says "n BARS" - not which move. Toast naming the move only came at the moment it started ("Loop build into DJ Karda - Alone."). Earlier GO NOW told me 10 bars ahead (Echo throw). Inconsistent.
- 12:27:20 Touched deck 2's FILTER knob during the loop build: "That's yours for this move. The mix carries on with the rest." Lovely clear message. fu-control-yours.png. Deck 2's 4th knob had changed itself from DUB to FILTER 5 seconds earlier without saying anything.
- 12:27:40 Loop build watching: deck 2 goes into a loop that gets shorter (shaded area on the waveform; clock hops back and forth around 02:47) with bass fading out, deck 2's LOW going down on its own. Deck 1 starts itself after the loop's been building for ~20s; its cue had moved so deck 1 started at 00:20.8 and clock ran. Deck 2's meter is the right bar pair, then the meters swap. fu-loop-build.png
- 12:28:15 Mix moved to DJ Karda with no message when deck 2 finished the loop build; Exhilarate (170 BPM) was auto-loaded next, though Houston 126 is 2 BPM from master and I had loaded it first. "2 tracks to go." I tried to overrule it from the list. First tap on Houston's 2 looked like nothing for 5s. Second tap: "Up next: Houston. The mix carries on." and the list re-sorted so the row I'd just tapped jumped to row 3. Can't tell which tap took.
- 12:28:50 Playlist menu: All Tracks / History Nov 5 (auto-made, nice) / New playlist. New playlist alert fine. Empty state tells me: "Go to All Tracks, press and hold a track, and add it from there." Clear.
- 12:29:00 BROKEN? 8s after the toast "Up next: Houston. The mix carries on." the list had Exhilarate back on deck 2 with Houston unlit in row 1. fu-up-next-reverted.png is what deck 2 said after. So the app told me Houston and then, apparently, took it back with no message.
- 12:29:10 Press and hold on a track gives Load 1/2, Preview, Add to Playlist, Choose Several, Re-analyse, Delete from Library. The menu's discoverable only from the playlist empty state. Preview: artwork gets a stop square. Nothing tells me where it's playing (headphones? main?). Tapping the artwork again stopped it. So artwork is a preview button? Didn't try it from cold. "Added to Warmup." good. GO NOW also appears in browser status bar. 
- 12:29:40 Pressed MIX to stop: "Mix off. The track playing just carries on." Button back to AUTO. Clear.
- 12:29:50 SYNC deck 2 (170) to deck 1 (128): "Deck 2 is now 25% slower than its own 170 BPM, to follow." -24.7% and clock jumps to 03:13 total. Honest and readable. App lets me do it. 
- 12:30:00-12:30:30 Followed the app's "Mix two tracks" recipe by hand: crossfader to 1, LOW down on 2, PLAY, crossfader to centre, swap LOWs, crossfader to 2. Worked first go: bar numbers on both waveforms hit .1 together, meter on deck 2 rises. Done in about 30s. REC count went 3 to 4 as I crossfaded. fu-manual-mix-done.png
- Crossfader full on 2 and deck 1 still shows up in the 1st meter column and MASTER 1 stays 128 until I stop deck 1. So the meter column 1 is before the crossfader. The word MASTER means "tempo boss", not what's on air. Took me a while.
- 12:30:30 ? on BEAT BLOCKS, METERS ("deck 1, the mix left and right, and deck 2" - answers my meter question), MASTER TEMPO, REC. Good.
- 12:30:45 REC: "Stop recording?" Stop and save / Keep recording. Good guard.
- 12:30:50 Opened Recordings about 6s after Stop and save: "No recordings yet. Tap REC..." - while I had just saved one. Wrong for a moment. fu-no-recordings-after-save.png
- 12:30:55 A few seconds later it appeared by itself: Mix 2026-11-05 12.21.41, 9:03, 17.3 MB, M4A. Warning with a hand: "A recording plays out loud, over the mix. To listen to one, stop both decks." fu-recording-listed.png. No "saving..." status during the gap.
- 12:31:10 Tracklist: 4 tracks with times, BPM, key. 05:45 Alone, 08:18 Exhilarate. Lists Exhilarate as 128.0 BPM (the speed I played it). Skylander & Fast Bird correctly left out (played before REC). Severe Tire Damage is listed at 00:00, correct. Key says 12B even though I'd slowed it 25% - I can't say whether key's held; KEY never lit up.
- 12:31:30 While decks are playing the recording's Play button is grey and does nothing, no feedback when pressed (tapped it twice). Hand note wording: "A recording plays out loud, over the mix. To listen to one, stop both decks." It reads like advice, so I expected it would play. It's a block. After stopping decks note disappears and Play goes white and works; scrub bar appears. Scrub handle is fat and its 0:00 end is odd but works.
- 12:32:00 Share sheet: "Plain Text and 2 Documents", i.e. audio + tracklist + something I can't name. Didn't send. Dismissed.
- 12:32:20 CUE on a stopped deck moved the cue to the next bar line (04:17.1 -> 04:17.3). Holding CUE for 2s: meters blip, clock returns to same place. As expected. But MASTER flips to whichever deck last moved even if only held: "MASTER 2" -> "MASTER 1" just from holding CUE on the other deck.
- 12:32:50 MORE cycles SMPL > MEM > SLICE > JUMP. Fine but I'd have liked to see them all at once. ? on a slice pad: "Plays this eighth of the bar for as long as you hold it. The track keeps time underneath and comes back in time when you let go."
- 12:33:05 JUMP back 32 pad with stopped deck: 04:17 -> 04:02. No extra confirmation needed; numbers correct.
- 12:33:15 Crossfader on 2 with only deck 1 playing: deck 1 meter moves, both mix meters dark. So the meter tells the truth about what's on air, and that's the way to tell. No words or lit crossfader to warn "you're playing a deck the crossfader has shut". Could easily catch a newcomer.
- CORRECTION: I said KEY never lit. It is lit by default, on the JOG page only, which I hadn't noticed. So key lock is on and 12B in the tracklist is right.
- 12:33:30 On JOG page key + changes 12B to 7B. For a newcomer one step up jumping from 12 to 7 looks like a bug. It's the app's key numbering and I'd have to look it up: it isn't explained in the ? for key, as far as I saw.
- 12:33:35 KEY SYNC: "Deck 2's own key, 12B, goes with deck 1's 1B, so it needs no shift." Clear.
- 12:33:50 Pressed WIDE on deck 2 (at -24.7%). Toast: "Deck 2's 24.7% from its own speed, so it needs WIDE." I had just pressed WIDE and it isn't lit, so the message read as "press WIDE" while it was refusing to let WIDE go off. Confusing. 
- 12:34:00 Pulled the tempo fader DOWN 35pt: from -24.7% to +34.5% (228.70 BPM). Down = faster, the opposite of what I expected though I've heard DJ gear does this. Nothing on the fader says + or -. Only 35pt of drag = 60 BPM swing: hopeless for fine control in WIDE mode. Deck was stopped; imagine it playing. fu-wide-tempo.png
- 12:34:00 Also: after I pressed SYNC on deck 2 (lit blue at 12:30) it became unlit SYNC by itself after I stopped decks & played deck 1. Sync on deck 2 silently off. No message.
- 12:34:20 BPM menu "Back to Its Own Speed": deck 2 back to 170.00, +0.00%, tempo range label changes WIDE -> ±10 on its own, fader recentres, clock total changes 00:52 -> 01:10. So I now see WIDE came on automatically when SYNC needed more than ±10, and that's why pressing it got "so it needs WIDE". Understood only now. Deck 1's menu: "Beat grid: 129.53 BPM at normal speed", which is 128 / 0.988, consistent.
- Deck 1 clock ran to 00:00.0 in red at 04:37.3 and just sat there, waveform black to the right. Nothing else happens: no prompt, no "track ended". Fine when I'm not in MIX.
- 12:34:45 Browse with NEXT off: BPM and KEY headers sort, tap again to flip (arrow shows). Row with the track on a deck lights blue + deck button lit. Search title or artist works, "kevin" finds both; "kevinzz" shows the standard No Results. KEY filter: "3 of 7 showing, with KEY on." The import button stays glowing blue for ever, even with 7 tracks in, so it always looks like the thing I'm meant to press next.
- 12:35:05 ▶ MIX with both decks stopped. It took a track I hadn't loaded (Gepzene) to deck 1 and started playing it straight away, moved Alone from deck 1 to deck 2 and cued it, crossfader to centre. "Mixing through all your tracks, 6 tracks to go. Up next: DJ Karda - Alone." So "6 to go" counts played ones; nothing says it starts over. It does give me a nice 84 BARS countdown. But no warning it would start sound or replace what I'd got on my decks. Houston, the only track never played, is not next again. My LOW on deck 1 (left turned down from the hand mix) stayed down on Gepzene while deck 2's was reset. Not sure if it's a bug.
- CORRECTION 12:35:45: searching the help for "key" answers my 12B -> 7B puzzle: "A semitone is 7 places round the key numbers, so +1 takes 1B to 8B." and NEXT: "Tempos within reach come first... Past that, key decides. What's on a deck and what's ticked go last." So both explained, but only in the long help, and my earlier note on NEXT ordering was me not knowing the rule. The help calls the filter "IN KEY", the button says "KEY".
- 12:36:10 Dim 1s in Browse during MIX: tapped one: "Deck 1 is playing. Stop it first." Clear. 
- 12:36:20 Second try at overruling MIX, Houston on 2: "Up next: Houston. The mix carries on." Houston row blue, 2 lit. GO NOW gone from the status bar for now; no reason given.
- 12:36:50 Deck 1 STEMS: tap VOCAL. Pad dims, NO VOCAL lights by itself, four coloured dots over the STEMS tab show which are up, waveform colours change at once so the vocal disappears from the picture. Very readable. fu-no-vocal.png. Houston stems 20%, MIX/STEMS 20% on the key; 2:15 left on Gepzene.
- 12:37:00 SOLO V on deck 1: ACAPELLA lights, other pads dim, waveform blank because this section has no vocal. Meters drop nearly to nothing. ALL brings everything back.
- 12:37:25 Pressed VOCAL on deck 2 whose stems are 52%: "That happens when the split's done. It's at 58%." Pad dims and NO VOCAL lights at once, so the state looks done but isn't. Message is clear. Good, but MIX isn't mentioned: will the mix keep my muted vocal? Watching. 
- ? on AI lamp: "How the split's going. AI with a green dot means it's ready. ≈EQ is a rougher split by frequency, used when the full one isn't available. START splits this track now, if Prepare stems is off in Settings." OK. Decks show a % progress bar in that same spot while splitting.
- 12:37:50 Tap on overview while playing: "Hold the overview for a moment to jump while the deck's playing." Hold it: jumped from about 02:31 to 03:11. Works and explained at the moment of need. Deliberately left deck 1 with 37s to run while stems for the next track are only at 86%, to see what the mix does.
- 12:38:25 Stems for Houston reach 100% (about 2 min for a 4:50 track) with 18s left on the outgoing track; a few seconds later MIX shows "3 BARS", Houston's tempo goes +1.6% and its cue moves to 00:22.8 without a message. 12:38:32 toast "Echo throw into Houston." My NO VOCAL on Houston was wiped when the move began: the "That happens when the split's done" promise was only kept for about 8 seconds and then the move took the pads. Nothing told me the two conflict.
- CORRECTION 12:39: the mix DOES ask for a rating: "Echo throw done. Deck 2 is on. More echo throws?" with thumbs. It was hiding behind the playlist menu when it arrived and it vanishes by itself after ~15s, so I'd missed it before (and my attempt to press thumbs down missed the screen; I can't say what thumbs down does). I still don't know what the rating does: nothing says it changes what's chosen next, though "More echo throws?" hints it.
- 12:39:15 Choose Several from the hold menu: circles down the left where the artwork was; "1 track chosen", ALL / ADD TO / DONE. Clean.
- 12:39:40 "Added 3 tracks to Warmup." + UNDO. ADD TO's popup is small and sits right over the bar. Fine. Playlist picked in the menu: search hint changes to "Search Warmup", playlist button goes blue so I know I'm in one. Nice detail. While a mix was running from All Tracks and I went to Warmup, status still said "all your tracks", which was at least honest. Stopped and restarted MIX in Warmup: see fu-mix-playlist.png.
- 12:39:46 fu-mix-playlist.png "You've played all of Warmup, so this goes round again, 3 tracks to go. Up next: Gepzene" Really clear. This time Gepzene went on deck 1 and my LOW on deck 1 finally reset. (So LOW resets when the deck gets a new track from the mix, not when it's a track you had on already?) Can't tell.
- 12:40:05 GO NOW, Loop build in 17 bars, into Gepzene - Can't be Serious. Toast faded over the overview.
- 12:40:25 ? on BRAKE: "Slows the track to a stop... The square on the pad says so: the deck stays stopped until you press PLAY, and a mix ends with it." Clear warning. 12:40:30 Pressed BRAKE on deck 2 to find out. fu-brake.png
- 12:40:35 BRAKE: pad lit, took about a second. No toast at all. Mix key dropped back to plain AUTO, deck 1 sent back to 00:00.2, its waveform showing an INTRO 1.1 at the start. So the app did what ? said, but if I hadn't read ? I wouldn't know MIX had ended, and that a cued deck got moved. Only clue the MIX key changing name. fu-brake.png is just before.
- 12:40:50 Settings: Waveform colours RGB, Prepare stems on load off. Note says a deck on STEMS shows stems' colours either way, and it does: deck 2 on FX went RGB, deck 1 on STEMS unchanged. Good, and finally that explains why the deck waveforms kept changing colour on me earlier.
- 12:41:25 Playlist hold menu adds Remove from Playlist and Change the Order. Handles appear; "Drag the handles to change the order." Dragged Skylander to top with one go. Very clear. Started MIX from that order to see whether it's obeyed.
- 12:41:30 MIX from a stopped state in my reordered Warmup: Skylander (now top) went to deck 1 and started; "Mixing through Warmup, 3 tracks to go. Up next: Houston." So it obeys my order. Good. 
- 12:42:00 Re-imported Exhilarate while in Warmup: "Added 1 track you already had to this playlist." Clever and honest: no duplicate. fu-reimport-playlist.png. But I hadn't realised importing goes into the open playlist. Status still says "3 tracks to go" though Warmup's 1 longer. Files picker opens with circles already on, with the app's own Segue DJ folder (4 items) that bounced me straight back when I tapped it, twice (Files app behaviour? can't tell).
- Files have names like "jam1051513" in Files but real titles in the app. Good that it read tags.
- 12:42:50 FX page: tap latches an effect, it stays lit; a blue dot appears over the FX tab. Effects stack: ECHO and PING PONG lit together, no limit message. V I B D chips light on and off by stem but they don't say what they do until ? (they pick which stems the effect hits). Page has ROLL, a pad, and a separate ROLL tab. FILTER is a pad and a knob. Could not separate those without help.
- 12:43:10 Stopped the master deck during MIX: "Mix off: deck 1 was stopped." Plain and true. But Houston on deck 2, which the mix had set to 125 BPM at 00:07.6, jumped back to 128 BPM at 02:13.6, i.e. where I braked it two tracks ago. Unexplained. The I chip I'd turned off stays off.
- 12:43:30 Settings bottom half: backup note is very clear: says what's held, what isn't, and warns that deleting the app deletes the auto backups. That also explains the Segue DJ folder in Files. Format AAC/WAV.
- 12:43:50 Hold menu > Re-analyse on Exhilarate: "Analysing Exhilarate again." dots in BPM and KEY, ~10s later green "Analysed Exhilarate again: 170.0 BPM, 12B." Nice. Side effect: stems for that track are forgotten, so a 2-3 minute split has to be redone. Nothing warned me. I'd have assumed Re-analyse means only beats. With Prepare stems off the deck shows START where the % bar was. I did NOT try Delete from Library or Delete Playlist.
- CORRECTION 12:44:00: my note above that Re-analyse loses the stems is WRONG. START took effect in a second, green AI: the split had been kept, as Settings says. So START just means "fetch them". fu-start-stems.png is from after the press. Waveform changes to stem colours at once.
- 12:44:35 Manual loop: IN lights orange, OUT makes a loop, RELOOP turns to EXIT, and the beat counter says 6 (what I got by tapping by hand), so it measured my loop. The arrows halve/double it. Clean and it behaved exactly as I'd expect from a real deck. fu-manual-loop.png
- 12:45:00 (fu-manual-loop.png was taken just after I pressed EXIT, so it shows the deck after the loop, not during.) Loop pads remember where I am in MORE: SMPL then MEM. The 4:18 loop I saved on Skylander on deck 2 half an hour ago is there on deck 1: saved with the track. Pressed it while playing: jumped to 04:19 and is looping a long way (about 21 bars to the right on the waveform). Whole loop shaded orange. Clean.
- 12:45:10 Pressing a saved-loop pad a second time leaves the loop and the deck carries on. As I'd want.
- 12:45:15 Headphone key: "You'll hear the cue with SPLIT on and a splitter cable." Right when I needed it. Mixer sheet text changes when SPLIT goes on: "SPLIT's on: the mix in the left ear and your cue in the right, for a splitter cable." and the MIXER key on the main screen grows a SPLIT tag so I can see it after the sheet closes. Excellent. Can't test it without a cable.
- 12:45:40 TRIM 1 down: knob drawn with a white arc, meters visibly drop. Tried a double tap to reset (a habit from other audio apps): nothing, but my two taps are slow through this tool, so that's not a fair test. Dragging it back the same distance: see below.
- 12:46:00 Trim knob: dragged down 98pt then up 98pt from the knob: did not return to centre, ended about 2 o'clock. Another 20pt down got it near but not on 12 o'clock. No visible snap. On a real phone the haptic detent might help (Settings mentions them), I can't feel it. No obvious way to reset. Touching the knob with ? may say.
- 12:46:20 AUTO with stems ready, 45s left on Skylander: "Echo throw next, with deck 2 cued at 170 BPM. AUTO's counting down the bars." Waited just 5 bars this time. "Echo throw starting. From here, a control you touch is yours." Deck 1 fades on the meters though its pads, faders and knobs all look untouched. 125 BPM and 170 BPM running together, no sync, which fits an echo. Clock on deck 1 turned red with 25s left: a nice end-of-track warning, nobody explains it but it needs no explaining. Exhilarate's first section is drawn nearly silent but labelled CHORUS 1.1 (intro, surely). No idea what that label's based on.
- CORRECTION 12:47:00: the saved loop's LIST row says "4:18, 4 beats", so my "21 bars" was wrong, the waveforms were still zoomed in from my pinch. Nothing on screen says it's zoomed. The zoom stays after you pinch.
- 12:46:55 Thumbs down on the echo throw: "Got it. Less like that." Clear. (So my earlier note that the thumbs up "vanished" may just be that I missed the toast between screenshots. No fair complaint there.)
- 12:47:00 ? on HI: "The highs: hi-hats and sparkle. Drag down, and all the way removes them. Double-tap for the centre." So there is a reset, in the ? text only. BEAT "Just the drums and bass."
- 12:47:05 MEM > SAVE CUE on a stopped deck at 5:46: "Memory cue saved. The track loads here now." with UNDO. So one idle press 14 seconds from the end means this track will now always load nearly at its end! Honest and undoable for ~10 seconds. I'm going to check that next.
- 12:47:40 Reloaded Skylander: confirmed, it loaded at 05:46, 14 seconds from the end, red clock. fu-loads-at-memory-cue.png. Exactly what the toast said. Nothing warns me it's unusual. Worth noting an accidental SAVE CUE is sticky and only visible on the MEM page. Severe Tire Damage had a hot cue A at 3:15 that I set hours ago in tool time, kept. Good. 12:47:55 removed the memory cue with DEL.
- Time-of-day aside: Skylander's overview has a small orange tick where the loop is, a nice touch.
- 12:48:40 Exhilarate ran out with MIX and AUTO off: red 00:00.0, CUE glows, nothing else. Master stays "2 170.00". Fine.
- 12:48:50 Import > DJ library (XML): "Choose the XML your DJ software exported." Told at the right moment, doesn't name which software, and I have no such file so can't go further. fu-xml-picker.png. The picker's top-left button is a blank grey circle in that screenshot.
- CORRECTION: the blank circle in the XML picker was the sheet part-way through opening; it finished as a normal Files picker with an X. Not a bug.
- 12:49:20 History Nov 5 lists every load in order, repeats included (Gepzene, Skylander, Exhilarate twice each), with no times on it. MIX from it: "Mixing through History Nov 5, 9 tracks to go. Up next: Skylander." Stopped decks replaced with Fast Bird (row 1, started at once) and Skylander. Nice way to replay a set, if it's meant for that. Nothing warned me it would replace both decks.
- 12:49:50 GO NOW on the History mix: "Loop build in 12 bars, into Skylander." Deck 1's 4th knob switched itself DUB -> FILTER a bar before the move again. Moved the crossfader part way to 1 as the move began, to see whether I could overrule it. It stayed where I put it. I saw no "yours" message this time, though I may have missed it between screenshots.
- 12:50:30 Loop build finished: "Loop build done. Deck 2 is on. More loop builds?" Thumbs up: toast went away, no reply I caught. The crossfader stayed part way towards 1 where I'd dragged it, after the move and into the next countdown. So on screen "Deck 2 is on", but the mix meters sat lower than deck 2's own meter, because my crossfader is turned against it. fu-crossfader-left-mine.png
- 12:51:35 GO NOW again: "Echo throw in 11 bars, into Severe Tire Damage - High Quality." Crossfader still where I left it. Watching whether the next move takes it back. fu-crossfader-before-next-move.png
- 12:51:55 ? on the crossfader: "Slides the mix between deck 1 and deck 2. In the middle, you hear both. Double-tap for the centre." 
- 12:52:00 One bar before the echo throw: "Moved the crossfader to the middle, ready for what's next." So the app does take it back and says so. fu-crossfader-moved-back.png. That also probably answers the crossfader "jump" I noted at 12:18:00: there was very likely a toast I missed between screenshots.
- 12:52:20 Echo throw done: "Echo throw done. Deck 1 is on. More echo throws?" Gepzene, next in the History order, loaded itself on deck 2. MASTER had stayed on deck 2 through the move even after deck 2's meter went dark, and changed to 1 only at the end.
- 12:53:55 Stopped. "Mix off. The track playing just carries on." I paused deck 1. Gepzene on deck 2 went back from 00:09.5 to 00:00.2 with no message.

## Their report

Started 12:08:53, stopped 12:53:56 (45 minutes). The notes above were written as I went and include wrong guesses, which I left in and corrected further down. Where they disagree with what follows, trust what follows.

How far to trust this report:
- I can't hear. "Worked" below means keys, numbers, waveforms and meters behaved. I can't say whether any mix sounded good.
- I saw the app as snapshots, a few seconds apart. Toasts vanish, so when I say "no message" or "silently", I mean I didn't see one. I got this wrong at least twice: the thumbs-up reply, and probably the crossfader moving at 12:18. Please check those claims against the code or logs.
- Times in the notes are my own labels, and they can be up to about 30 seconds out either way. One (the BRAKE note) is ahead of the clock reading I logged it with. Search the logs with some margin.
- The app never crashed, and I never had to restart it.

## 1. Moments I wasn't sure what to do

Durations are from first doubt to answer. "Not found" means I never got an answer. Each tool call is slow, so short durations are mostly the tool.

1. Decks screen, first look (12:09:50). Wanted: to play the track I'd loaded. The screen shows two decks and a mixer at once, and a toast covers the waveform. Tried the green play button, and the meters moved. About 8s. fu-decks-first-look.png, fu-first-play.png.
2. What AUTO does (12:14:50). Wanted: the app to mix for me. Pressed AUTO and got "The stems need 3 min, and this track has 3 min left. Deck 1 will just start at the end, with no move." I didn't know what "stems" were doing here or what a "move" was, so I went to Settings and found the guide. The wait was 2m50s, and then it stopped because I'd left deck 2 in a loop in the meantime. Understood after about 3 minutes. fu-auto-pressed.png, fu-auto-choosing.png.
3. What DUB is (12:17:20). Picked it on the mixer's key, and the fourth knob on each channel changed name. ? on that knob is headed "FILTER KNOB" and doesn't explain DUB. Help search found it at 12:25:00. About 8 minutes. No screenshot.
4. Why waveforms change colour (from 12:10). I thought the colours meant stems had arrived. They actually follow whether the deck is on the STEMS tab. A Settings line told me at 12:25, and I only really got it at 12:40:50. About 15 minutes or more. fu-mix-go-now.png.
5. The arrow next to the BPM (12:20:40). Wanted a menu. Tapping it reset deck 1 from 140.06 to 148.00, which also moved MASTER, and I saw no message and no undo. A second tap on the same arrow opened the menu. About 20s. fu-bpm-menu.png.
6. What MIX would do to my decks (12:22:00). I had loaded Houston, then pressed MIX, and it replaced Houston with Gepzene. Tried to put Houston back at 12:28 (see section 4). A second try worked at 12:36:20. About 14 minutes to get the track I wanted. fu-mix-started.png, fu-up-next-reverted.png.
7. What the ·1 on the REC button means (12:21:40). Worked out at 12:24:40 that it counts tracks, when it went to 2. fu-mix-started.png.
8. The waveform icon next to BROWSE (12:22:25). It looks like a waveform view but opens Recordings. I kept having to remember that. No screenshot.
9. How many pages MORE has (12:22:40). It cycles MEM, SLICE, JUMP, SMPL one at a time, replacing its own label, so you can't see the list. About a minute of pressing. fu-save-loop.png, fu-sampler-recorded.png.
10. SET on a sampler pad (12:23:15). ? says a pad can hold "a file, a deck's loop, or a recording of the mix". The sheet offered only a file or recording. Nothing was looping at the time, so that may be why. Not found.
11. Who is on air during an echo throw (12:24:30). Deck 1's clock and waveform kept moving, and its pads, fader, knobs and crossfader all looked normal, but its meter was dark. The meter was the only clue. fu-echo-throw-running.png.
12. Which meter is which, and what MASTER means (12:12:45). Crossfader fully on 2, yet MASTER still said 1 and deck 1's meter was still up. I took MASTER to mean "on air". ? on the meters explained it at 12:30:30, and I worked out MASTER means tempo boss. About 18 minutes, partly because I didn't ask sooner. fu-manual-mix-done.png.
13. Why the waiting deck changes by itself (12:18:00, 12:27:00, 12:38:25). Its cue point and tempo move before a move starts, and the fourth knob flips between DUB and FILTER. I worked out the pattern but never saw it explained. fu-auto-bass-swap-next.png.
14. Grey Play on a recording (12:31:30). Tapped twice with nothing happening. The note reads like advice, not a block. Worked once both decks were stopped. About 20s. fu-recording-listed.png.
15. A key jumping from 12B to 7B (12:33:30). One press of + looked like a bug. Help search explained it at 12:35:45. About 2 minutes. No screenshot.
16. WIDE (12:33:50). Pressed it, it stayed unlit, and I got "Deck 2's 24.7% from its own speed, so it needs WIDE." I read that as "press WIDE". It was actually refusing to turn WIDE off. Worked out at 12:34:20. About 30s. fu-wide-tempo.png.
17. Tempo fader direction (12:34:00). Pulling down made it faster, and 35pt of drag moved it from -24.7% to +34.5%. Nothing on the fader marks plus or minus. fu-wide-tempo.png.
18. Resetting a knob (12:45:40). Dragged TRIM down 98pt and back up 98pt, and it didn't return to centre. Double-tap is the answer, which I read in ? at 12:47:00, but I never got it to work on TRIM because my taps through this tool are too slow to be a fair test. About 80s. No screenshot.
19. A deck the crossfader has shut (12:33:15). Deck 1 playing with the crossfader on 2: its own meter moves and the mix meters are dark. Only the meters show it. No screenshot.
20. What the thumbs do (12:19:10, 12:39:00, 12:46:55). Thumbs down says "Got it. Less like that." Whether it changes anything, I couldn't tell in the time. Not found. fu-auto-done-rating.png, fu-thumbs-down.png.
21. Where Preview plays (12:29:10). Headphones or main? Nothing says, and I can't hear. Not found. No screenshot.
22. Importing while in a playlist (12:42:00). I didn't realise the import would go into the open playlist. The message was clear once it did. fu-reimport-playlist.png.
23. Why deck 1 sat ready at 00:00.2 after BRAKE (12:40:35), and why Houston jumped when the mix stopped (12:43:10). See section 3. fu-brake.png.
24. Tapping on the mixer sheet while it rises (12:17:20, 12:26:45). See section 4.

The help, and what it did and didn't do:
- ? mode was the best of it. It covers nearly everything, including the waveform, meters and stem lamp, and it's safe to use while music plays. It's only useful if you know what to ask about, and it failed on the DUB knob.
- "Start here" under Settings > What everything does gave me the steps for a hand mix, and they worked first go at 12:30. The app never offered it. I went looking only because AUTO confused me.
- Help search answered "dub", "key" and "bpm". "grid" returned No Results, even though the BPM menu says "Beat grid".
- Tips at the moment of need were very good: "Two basslines clash...", "Hold the overview for a moment to jump...", "You'll hear the cue with SPLIT on and a splitter cable." Their weakness is that they sit on top of the waveform.
- Nothing in the help told me what to do next after a first mix, or that a track needs 2 to 3 minutes before AUTO can do a proper move, until I'd pressed AUTO.

## 2. How long each stage took

Measured from opening at 12:08:53. The tool is slower than a finger, so a person would be quicker on the early stages.

| Stage | Clock | From opening |
|---|---|---|
| Browse screen showing, import button obvious | 12:08:58 or earlier | under 0:05 |
| Getting music in ("Added 7 tracks.") | about 12:09:30 | 0:37 |
| First track on a deck | about 12:09:40 | 0:47 |
| First sound (meters moving, I can't hear) | about 12:09:58 | 1:05 |
| Second track on a deck | about 12:10:36 | 1:43 |
| First time two tracks playing together | about 12:12:12 | 3:19 (about 70s of it reading ?) |
| First move from one to the other, by hand with crossfader and LOW knobs | about 12:12:50 | about 3:57 |
| First press of AUTO | about 12:14:50 | 5:57 |
| Found the "Start here" guide | about 12:15:10 | 6:17 |
| First automatic transition finished (bass swap) | about 12:18:45 | 9:52 (about 3 min waiting for stems) |
| Started recording | 12:21:41 | 12:48 |
| Started MIX | about 12:22:05 | 13:12 |
| First playlist made | about 12:28:50 | 19:57 |
| First full hand mix following the guide's steps | about 12:30:25 | 21:32 |
| Recording listed, then played back | about 12:30:55, 12:31:40 | 22:02, 22:47 |

Stems took about 2 to 3 minutes per track here. That may differ on a real phone.

## 3. What I still can't explain, and wording

Still can't explain:
- Whether the thumbs change what gets chosen.
- How a move gets chosen. I saw bass swap, echo throw and loop build, with no list of them in front of me and no reason given for any choice.
- Whether section labels can be trusted. Exhilarate's nearly silent start is labelled CHORUS 1.1, a label changed from CHORUS to INTRO on one deck at 12:23:45, and most of what I saw was labelled CHORUS.
- The rule for LOW after a mix: my turned-down LOW stayed down on Gepzene at 12:35:05, and reset at 12:39:46.
- What the waiting deck does when a mix ends. It moved back with no message at 12:40:35, 12:43:10 and 12:53:55. My guess is it returns to where it was before the mix prepared it. If so, that's a rule, not a bug, but nothing says so.
- What the third item is in the recording's share sheet ("Plain Text and 2 Documents").
- Why the first BPM reading wandered. See section 4.
- Whether the sampler or Preview reach the mix or the headphones.
- ROLL as a tab and as an FX pad, and FILTER as a pad and as a knob: I can't say how they differ in use without hearing them.

Wording that was wrong, misleading or no help:
- "DECKS takes you there": still showing after I'd gone there, and hiding the waveform.
- "move": used from the first AUTO message with no explanation.
- "FILTER KNOB": the heading of the ? for a knob labelled DUB, which doesn't explain DUB.
- "the sidebar": in the ? for PLAYLISTS, on a phone where I found no sidebar.
- "IN KEY" in the help, "KEY" on the button.
- "so it needs WIDE": reads as an instruction, when it means WIDE can't be turned off.
- "A recording plays out loud, over the mix. To listen to one, stop both decks.": reads as advice, but Play is blocked.
- "No recordings yet": shown just after Stop and save.
- "Mixing through all your tracks, 6 tracks to go": the count includes tracks already played and doesn't say it's going round again. Warmup's version does ("You've played all of Warmup, so this goes round again"), which is much better.
- MASTER: reads as "on air", but it's the tempo reference. It stays on the outgoing deck through an echo throw, after that deck's meter has gone dark.
- "That happens when the split's done": my NO VOCAL on Houston did take effect once the split finished, and then the move replaced it within seconds. Nothing warned me the two would conflict.

Wording that was very good: "That's yours for this move. The mix carries on with the rest." / "Mix off: deck 1 was stopped." / "Moved the crossfader to the middle, ready for what's next." / "Added 1 track you already had to this playlist." / "Deck 2 is now 12% faster than its own 125 BPM, to follow."

## 4. Anything that looked broken

Search the logs with some margin on these times.

- About 12:28:45. Toast said "Up next: Houston. The mix carries on." Within about 8s the list showed Exhilarate on deck 2 and Houston unlit, with no message. I'd tapped twice, so my taps may have played a part. The same thing held fine at 12:36:20, so I saw this once only. fu-up-next-reverted.png.
- About 12:30:47. Recordings said "No recordings yet" just after Stop and save, then filled in within seconds, with no "saving" status. The screenshot fu-no-recordings-after-save.png is misnamed: I took it too late and it shows the list already filled in, so I have no picture of the empty state.
- 12:17:20 and 12:26:45. The mixer sheet rises in two steps, about 20pt apart. Tapping FILTER and Done while it was still moving missed.
- 12:09:40 to about 12:11:50. Fast Bird read 139.7 in the library, and 140.59 on the deck, wandering 139.6 to 141.6 at +0.00%, then settled at 140.06 (140.1 in the list). Possibly analysis still running, but nothing says so.
- 12:12:05 to 12:34:00. SYNC on deck 2 went from lit to unlit by itself after I stopped the decks and restarted deck 1. I saw no message. I don't know exactly when.
- 12:18:10, 12:27:15, 12:49:50. The fourth knob changes DUB to FILTER before a move, with no message, and goes back after it.
- 12:20:40. The BPM arrow resets tempo with no message or undo, though SYNC gets both. This may be intended.
- 12:25:05. Swiping down to scroll in Settings closed the sheet. My mistake, but easy to make.
- 12:26:20 onward. Pinching zooms both waveforms and stays zoomed, with nothing showing it. It made me misread a 4-beat loop as about 21 bars.
- 12:35:05. See LOW in section 3.
- 12:41:50. Tapping the app's own Segue DJ folder in the picker bounced me straight back, twice. May be the Files picker's own behaviour.
- 12:42:00. "3 tracks to go" didn't change when the import made Warmup one track longer.
- 12:46:00. TRIM dragged down and back the same distance doesn't return to centre.
- Throughout. The import button stays glowing blue with 7 tracks in, so it always looks like the next thing to press.
- 12:39:00. The rating toast appeared behind a menu I had open, and went away by itself in about 15s, so I missed it.
- Throughout. Toasts cover the waveform, or whatever they're describing, for up to 10s or more.
- 12:47:05. Not broken, but a trap: SAVE CUE near the end of Skylander made it load 14 seconds from the end, every time. The toast was honest and has UNDO. After that the only sign is on the MEM page. fu-loads-at-memory-cue.png. I deleted it at 12:47:55.

## 5. Best and worst for a newcomer

Best: watching an automatic move on both STEMS pages at 12:18. The pads fill and empty, the knobs turn by themselves and the meters swap, so you can see what a transition is made of while it happens, and read ? on anything without disturbing it. Touching a control during a move just makes that control yours. It teaches mixing without a lesson. (fu-auto-swapped.png, fu-control-yours.png)

Worst: the app acts on my decks without asking. MIX replaced a track I'd just loaded and started sound from stopped decks. Cues, tempos and knob jobs all change on their own, and the reasons are in short-lived toasts that cover what they describe. Together with a very dense first screen and a guide that's only in Settings, a newcomer can get sound in a minute but can't easily tell why things are happening or how to get their own choice to stick.

## 6. What I can't un-know

- My session listed the working folder /Users/nikhil/Cheeks and two cache folders, cheeks-autodj and cheeks-stems. So before opening the app I knew it had an auto-DJ and stems, and probably an older name. I didn't open any of them.
- From the launch command I knew the identifier com.nikhilpatel.seguedj. From the folder name fu21 and another agent listed as fu16, I knew this was one of a series of tests.
- I know more about DJing than "roughly what a DJ does": sync, hot cues, quantise, slip, swapping bass on EQs, faders where down is faster, and key numbers like 8A. I was surprised by the fader but had heard of it. Terms like "bass swap" and "echo throw" meant something to me right away. A real newcomer will find much of this harder than I did, and my stage times flatter the app.
- The app's names for things, which I learned only from using it: Segue DJ (the Files folder), Auto DJ, stems, split, moves (bass swap, echo throw, loop build), MIX, AUTO, GO NOW, beat blocks, memory cue, saved loop.
- The tool gives me exact coordinates, so I tapped small targets more accurately than a thumb would. It also can't double-tap quickly, and it taps slowly enough that the two mixer-sheet misses might be rarer for a finger.
- Besides the tools you listed, I read only this report and a few of my own screenshots in this folder, to check them. Nothing else on the Mac.

What I left behind in the app: Waveform colours set to RGB, Prepare stems on load off, playlist Warmup, recording Mix 2026-11-05 12.21.41, sampler pad 8 replaced with REC 8, a saved loop on Skylander at 4:18, hot cue A on Severe Tire Damage at 3:15, TRIM 1 not quite centred, ratings given (thumbs up on bass swap and loop build, down on echo throw), and the I stem chip on the FX page of deck 1 left off, as last seen. Both decks stopped, MIX off. I didn't delete any track or playlist.

Corrections to the notes above: "hours ago in tool time" (12:47:40) should read 26 minutes ago. The AUTO warning at 12:14:50 wasn't wrong: my loop on deck 2 bought the extra time, which is why a move happened after all.

## 7. Afterwards

Answered from my notes and memory, without touching the app again. Times are approximate, so allow up to 30 seconds either way.

### 1. When could I first have told a friend what Auto DJ does?

About 12:18:45, when the first bass swap finished. Before that I could only have repeated the help: I read `?` on AUTO at about 12:11, and still pressed it at 12:14:50 expecting it simply to mix.

What I'd have said then: "Load the next track and press AUTO. It splits that track into vocals, instruments, bass and drums, which takes a few minutes. Then it picks where to come in, matches the tempo, brings the new track in a part at a time while swapping the bass over, and stops the old track before it ends. If you touch a knob, it leaves that knob to you."

By the end, that was only partly right.
- Still right: it splits first, and it usually comes in past the start of the track (00:12.9, 00:22.8 and 00:31.2, for example). It stops the old track early (37s left the first time, about 40s on Severe Tire Damage), and a control you touch stays yours.
- Wrong: "matches the tempo" only held when the tracks were close. It matched gaps of 1.2%, 1.6% and 5.4%. It left 140 into 125 (12%) unmatched, and bigger gaps too. The rule is my inference from those seven moves.
- Wrong: "a part at a time" described only the bass swap. In an echo throw the old deck's meter drops quickly. In a loop build the old deck loops shorter and shorter while the next one comes in. I saw only those three kinds.
- Missing: AUTO does one transition and then goes back to plain AUTO. MIX keeps going through a list, choosing and loading tracks itself.
- I can't say how any of it sounded.

### 2. Were the first AUTO and first MIX a let-down? Was the warning enough? Did either end in a plain cut?

First AUTO, pressed about 12:14:50: a let-down, partly my doing.
- I expected a mix right away. The warning came straight away and was clear: "The stems need 3 min, and this track has 3 min left. Deck 1 will just start at the end, with no move." The key also showed STEMS %. That was enough about the wait, though it only appears after you press.
- It wasn't enough about what could stop it. I put deck 2 in a loop at 12:15:45 and saw nothing to say that mattered. After about 2m50s I got "Auto DJ stopped: deck 2 is in a loop."
- That press ended in no transition at all, not a cut. Pressing again at about 12:17:55 gave the bass swap within a few bars, which was the opposite of a let-down.

First MIX, pressed about 12:22:05: a smaller let-down at the start.
- It replaced Houston, which I had just loaded on deck 2, with Gepzene. The toast named Gepzene as up next but gave no warning that my choice would go.
- Then it waited about 1m40s for stems, showing a percentage. It ran an echo throw at about 12:24:30, after I pressed GO NOW.
- The app called it an echo throw, not a cut. On screen, the old deck's meter went dark quickly with its controls untouched, at tempos of 148 and 128, with about 40s of the old track left. I can't hear whether there was an echo, so from the meters alone I can't tell it from a fast cut.

I never saw the "no move" ending. The nearest I came was at 12:37:50, when I jumped the playing track to 37s from its end with stems at 86%. The stems finished with 18s left, and it still did an echo throw.

### 3. Did I find GO NOW and Choose Several?

GO NOW: yes, without looking for it.
- It appeared in the middle column at about 12:23:45 once the stems were ready during MIX, squeezing the meters down. I read `?` on it and pressed it at about 12:24:00. It also appears in the Browse status bar, seen at 12:29:10.
- I expected "now" to mean now. It actually brought the transition forward to the next suitable point: 10 bars at 12:24:00 (the countdown had been in the 30s), 17 at 12:40:05, 12 at 12:49:50 and 11 at 12:51:35.
- That was a mild surprise rather than a problem. Its toast is also the only place I got advance notice of which move was coming, for example "Echo throw in 10 bars, into Gepzene". I used it four times, and it always brought the move forward.
- It wasn't always there, and at 12:36:20 I saw no reason given for it being gone.

Choose Several: yes, but only indirectly.
- I saw it in the press-and-hold menu at 12:29:10. I only tried holding a track because the empty playlist said "Go to All Tracks, press and hold a track, and add it from there." Nothing else pointed me to holding.
- I used it at 12:39:15. Circles replaced the artwork, the track I'd held was already chosen ("1 track chosen"), and I picked two more. ADD TO then gave "Added 3 tracks to Warmup." with UNDO, at about 12:39:40. It did exactly what I expected.

### 4. Things I pressed that did nothing and said nothing

As far as I could see:
- About 12:18:55 and about 12:50:35: thumbs up on a rating. The toast went away, and there was no reply in the screenshot taken right after. Thumbs down at about 12:46:35 showed "Got it. Less like that." in the screenshot right after it. My notes label the first of these 12:19:10, which is too late.
- About 12:31:15 and 12:31:20: the grey Play on a recording, with decks running. Nothing responded to the press. The hand note was already on screen, so it isn't wholly unexplained.
- About 12:19:15: dragging round the platter on deck 1 while playing. The clock carried on, with no visible jump. It may have been audible, since `?` says the record scratches. At about 12:20:25 I did a second, back-and-forth drag, and noted no visible result.
- About 12:45:30: two taps on TRIM as a double-tap. Nothing happened, but my taps through this tool are too slow for that to be a fair test.

Missed because the control was still moving:
- About 12:17:20: FILTER key on the mixer sheet, while the sheet was rising.
- About 12:26:45: Done on the mixer sheet, while the sheet was rising.

Unclear:
- About 12:28:05: first tap on Houston's 2 during MIX. Nothing visible for about 5s. A second tap at about 12:28:10 got the "Up next: Houston" toast, and I can't tell which tap took. Houston was gone somewhere between about 12:28:15 and 12:28:55, so my "about 12:28:45" in section 4 was too exact.
- About 12:27:25: two taps on deck 2's fourth knob, during the loop build. I made no note of the result, so I can't say.
- About 12:33:50: a tap on deck 2's BPM area. I have no note of it doing anything, and I retried lower down, which opened the menu. Low confidence.

The closest near-miss:
- About 12:22:55: sampler pads lit while held, but I saw no movement on the meters.

Not counted:
- About 12:38:55: my tap for thumbs down landed off the screen, which was my error.
- About 12:41:50: the Segue DJ folder in the file picker bounced me back twice with no message. That's probably the picker, not the app.
- The 12:19:20 note about ACAPELLA: going by my memory of the taps, I never pressed it a second time. I pressed ALL.
