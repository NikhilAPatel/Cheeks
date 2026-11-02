# Hands-on results, part 7, 2026-11-02

Commit tested: fdcacdc
Device: iPhone Duo simulator, iOS 27.2, unfolded inner screen (951×669 pt). Layout checks also through `LayoutSnapshots`.
Tooling limits:
- Not testable here: haptics, how anything sounds, headphone output. So whether a transition sounds good isn't judged anywhere below. I checked levels and gaps in recordings, and what's on screen.
- The touch tool can't tap faster than about 0.3 s apart, and its gaps vary from 0.15 to 0.5 s.
- With the Mac busy, a video can start up to about 8 s after it's asked for. I allowed for that when reading them.
- The library had 5 tracks, so nothing here says how `NEXT` feels on a big one.
- Other sessions were running tests on this Mac throughout. CPU figures are for the app's own process in the simulator, not a phone.

## Summary
54 tests: **46 PASS, 6 FAIL, 2 BLOCKED.** No crashes: the only Cheeks crash reports on the Mac are from 10:32, before this round.

Round 6's four findings are fixed: rolls come back (59 of 59, it lost 1 in about 30 last time), meters go dark in the background, `PLAY` during a load waits, and the jog lets go when the app leaves. `MIX`, `NEXT` and the moves themselves did what the task asks. The failures are nearly all in what happens when someone takes over from Auto DJ.

The 3 most important:
1. **AP6: Auto DJ won't mix some pairs when the outgoing track is on deck 2.** Skylander into Houston was refused on all six presses from deck 2, and planned every time from deck 1. From the code, the audition may be playing the wrong decks (see below).
2. **AQ3: after stopping a move, the new deck is stuck almost silent.** Its stems stay down, and neither `ALL` nor tapping a stem pad brings them back. Only sliding each of the four pads up does.
3. **AQ7: `CUE` on the new deck during a move ends in silence with a green tick.** It says "Vocal ride done. Deck 2 is on." with both decks stopped.

## Failures

### AP6: the same pair is refused from deck 2 and mixed from deck 1
- Steps: Skylander and Houston loaded, stems done. Play one from about 1:37 and press `AUTO`. Then swap decks and repeat, relaunching first so nothing's left over.
- Expected: a plan either way round, or the same answer either way round.
- Actual, Skylander on deck 2 into Houston on deck 1: "Auto DJ couldn't find a clean way between these two from here." I pressed six times: from 1:38, 3:06 and 3:26 in one session, 1:37 after a clean launch, and twice more at about 1:10 and 1:32 at 14:07. The message was on screen for five. For the one at about 1:10 I only saw `AUTO` back and unlit 9 s later.
- Actual, Skylander on deck 1 into Houston on deck 2: "Loop build in 8 bars" from 1:37 after a clean launch, left at 1:48.0 and ended right. "Bass swap in 9 bars" from 1:35 later on. A bass swap also ran in AQ6.
- It isn't every pair from deck 2. These planned and finished: Gepzene (deck 2) into Houston (Loop build), Gepzene (deck 2) into Skylander (in `MIX`), and Houston (deck 2) into Skylander (Echo throw).
- A lead, from reading the code and not tested: `TransitionAudition.review` builds its private engine with `[a, b]` as decks 0 and 1, but a score's steps use `side.deck`, the real deck number. With the outgoing track on deck 2, the steps would go to the wrong private deck, so the audition hears something else. If so, a plan that passes from deck 2 hasn't really been auditioned either. Unit tests only go from deck 0 to deck 1.
- Screenshots: ap6-deck1-plan.png, ap6-deck1-done.png, ap6-deck2-refused.png

### AQ3: stopping mid-move leaves the new deck stuck quiet
- Steps: Skylander on deck 1 into Houston on deck 2. Press `AUTO` about 10 s into the move. "Auto DJ stopped. The decks are yours." appears. Try to finish the mix by hand: `STEMS` tab on deck 2, `ALL`, stop deck 1, turn `LOW` up.
- Expected: I can carry on and finish it.
- Actual: deck 2 plays with a dim waveform and a tiny meter. `ALL` does nothing audible or visible. Tapping a stem off and on does nothing. The pads look on, with a dark band that's easy to miss. Sliding each of the four stem pads up brought it back. From the code: `setStems` only sets `stemsOn`, and the score has `stemLevels` down.
- The loop and the old deck were fine, and nothing crashed. `MIX` stopped mid-move gives the same message. I didn't try the stems after that one.
- Screenshots: aq3-stopped.png, aq3-all-still-quiet.png, aq3-slid-up.png

### AQ7: `CUE` on the new deck ends in silence with a green tick
- Steps: Houston on deck 1 into Gepzene on deck 2. "Vocal ride in 14 bars". Press deck 2's `CUE` once, about 4 s into the move.
- Expected: it ends with the decks usable. There's no stated rule for this one, so this is my reading of it.
- Actual: deck 2 stops at its cue. The move carries on with deck 1 alone, stops it at 02:05.7, and says "Vocal ride done. Deck 2 is on." with a green tick. Both decks are stopped, and it stays silent until someone presses `PLAY`. The decks do work after that. The same happened in a Loop build in `MIX`, with `CUE` on the new deck and then a hot cue on the old one.
- Screenshots: aq7-cue-new-green-tick.png, ph-cue-new-hotcue-old.png, ph-both-stopped.png

### AQ2: a knob I grabbed doesn't go back to centre at the end
- Steps: during a move, drag the outgoing deck's `HI` down.
- Expected: it stays while everything else carries on, and at the end it goes back to centre.
- Actual: the first part is right: `HI` stays while `MID` and `LOW` move. At the end it's still where I put it, on the deck that's just stopped, until someone turns it back. From the code: `clearAfterMove` only resets EQ index 0.
- Screenshots: aq2-grabbed.png, aq2-end.png

### AQ1: calling it off leaves the waiting deck's tempo moved
- Steps: Skylander playing, Houston waiting at +0.0. Press `AUTO`, then press it again during the countdown.
- Expected: "Auto DJ off.", the track plays on, and nothing has changed.
- Actual: the message and the track are right, but Houston's tempo fader stays at -0.79%, where the plan put it. It was +0.0 before. It happened again each time I called it off, including after I dragged it back to zero.

### AP5: pressing it again picked the same move
- Steps: straight after a Loop build from Houston into Gepzene, reload Houston on the free deck and press `AUTO`.
- Expected: the task asks whether it picks a different move.
- Actual: "Loop build in 6 bars", so the same move, in a different pair. It left Gepzene at 00:47.0 and ended right. This is small: moves did vary across the session (Loop build, Bass swap, Vocal ride, Echo throw), and recent moves only count against a plan.
- Screenshot: ap5-again.png

## Looks wrong
- **In `MIX` the move's name never shows.** "`<move>` in N bars" is left out for a mix, and "`<move>` done. Deck N is on." is replaced by "Up next" straight away: no frame showed it in video read at 8 frames a second. I named the moves below from what the decks did. Screenshot: ar3-handover.png
- **The one message explaining a missing transition can't be read.** "`<track>` is on, without a transition: there wasn't a clean way in." is covered by "Up next" at the same moment. In frames it's a ghost behind the new message. It's also long enough to be cut off with dots. Screenshot: ar9-message-overwritten.png
- **"Auto DJ lost its moment when the deck moved. Press AUTO to plan…"** is cut off with dots on the Duo. Screenshot: aq4-lost-moment.png
- **`NEXT` and the column sort are forgotten when the browser closes.** Press `NEXT`, close the browser to work the deck, open it again, and it's off with the list back in date order. Screenshot: as2-next-goes-off.png
- **A playlist doesn't show the order you built it in.** I added Skylander, Houston, Gepzene, and `library.json` has them that way. On screen, and so in `MIX`, it's Houston, Gepzene, Skylander, by date added. Screenshot: ar1-start.png
- **A long fade plays out in full before the next track.** With no clean way in, the next track waits for the old one's real end. Exhilarate's last 3.5 s are below -50 dB, so there's 3.5 s of near silence between tracks. It's the file, not a dropout, and the task only asks me to describe it (AR9).
- **`SLIP` missed its return once.** On deck 2, `SLIP` and `REV` landed together and both lit, and the deck ran back. `REV` off, then `SLIP` off: it carried on from where it had run back to, about 31 s behind where it should have been. The Mac was busy with a build. I couldn't repeat it: three more tries in the same order came back +11.9, +13.9 and +11.3, and `SLIP` first came back +6.6. A guess: two touches in one event aren't in a fixed order, and `REV` going first wouldn't engage slip.
- **Severe Tire Damage goes from 178.00 to 148.00 BPM when stems finish.** I can't call that wrong. A plain check over the whole file fits 148 better than 178 (score 1.22 against 1.08, control Skylander at 125 scores 2.05), with its sharpest beats at 0.017 s, right where the new first beat is. But 160, 200 and 150 score about the same, so this track has no clear steady beat for anything to find.
- **"Stems 8%" under the next track.** As `MIX` loaded Gepzene onto the deck that had just had Exhilarate, unsplit, the header read `Gepzene` and `Stems 8%` with no BPM. It may be Exhilarate's progress left over. It had gone 25 s later. Gepzene's stems were already done.
- **"Auto DJ stopped:" and "Mix off:" for the same kind of thing.** In a mix, loading or starting the waiting deck says "Auto DJ stopped: …", while pausing the playing deck says "Mix off: deck 2 was stopped."
- **A mistimed tap of mine set a hot cue** (slot G on Exhilarate), landing on a pad while the browser was closing.

## All results
| Test | Result | Notes |
|---|---|---|
| Setup | PASS | Fresh build at fdcacdc succeeded, clean install. |
| AT1 | PASS | 59 rolls of `1/4` held 1 s (I sent 59, not 60), about 1.1 s apart, while stems were splitting. 59 forward jumps of 0.9 to 1.2 s, none missing. Clock moved 73.20 s in 73.20 s. at1-rolls.png |
| AT2 | PASS | 20 presses of a `SLICER` pad, 20 forward jumps. 25.1 s in 25.20 s. |
| AT3 | PASS | 10 pairs, `1/4` then `1/8`, each held 0.6 s. 20 jumps of about 0.7 s. 25.1 s in 25.20 s. About 0.36 s between one lifting and the next landing, the closest the tool allows. |
| AT4 | PASS | `SLIP` on, `4` pad then `EXIT`, 10 times. 10 jumps of +1.3 to +1.5. 38.2 s in 38.20 s. |
| AU1 | PASS | `SPIRAL`, stop, away 20 s. All four columns dark at 1, 3 and 8 s. au1-meter.png |
| AU2 | PASS | No effect, 2 minutes away. Dark at 1, 3 and 8 s, and the clock unchanged at 04:16.5. |
| AU3 | PASS | Deck 1 playing, deck 2 stopped, away about 11 s. Clock, overview, jog, waveforms and strip live and right, even during the switch animation. 04:22.9 to 04:41.1 in about 18 s. |
| AV1 | PASS | `PLAY` lit at the press, load done about 0.7 s later, clock started by itself from the cue. av1-play.png |
| AV2 | PASS | A second `PLAY` before it loaded: stayed at 00:00.0, `CUE` lit. |
| AV3 | PASS | Compact `CUE`. Third try landed inside the load window: `PLAY` went out and the deck stayed at its cue. My first two arrived after the load. |
| AV4 | PASS | Load, `PLAY`, another load key. First load superseded, by its play count. Nothing started. |
| AV5 | BLOCKED | Loads take 0.2 to 0.6 s and the browser takes about 0.5 s to close, so I can't press under the cover on purpose. One run: load key landed as the browser closed, round `PLAY` pressed, the deck ran from its cue. I can't say it landed under the cover. Two others hit the old layout. |
| AW | PASS | Clock held 2.40 s at -05:26.8, app left at about 3.9 s, 2.22 s lost overall, so it carried on from the moment it left. Last time about 5 s more. Runs normally on return. |
| AM | PASS | Three club tracks copied in. `jam1197771` is Skylander (125), `jam1072904` is Gepzene (128), `jam1280420` is Houston (126). |
| AN1 | PASS | Skylander 125.00 throughout. First beat 1.8347 to 0.5118 when stems finished, lines on the kicks. an1-grid.png |
| AN2 | PASS | Houston on the other deck, `BEAT SYNC`: lines on the kicks on both, kicks line up, phase marker green and centred. an2-sync.png |
| AN3 | PASS | Gepzene, `Grid 10 ms later` before stems: 0.1974 to 0.2074, and still 0.2074 after. |
| AN4 | PASS | Nothing odd. Skylander INTRO, CHORUS, DOWN, UP, CHORUS, OUTRO. Houston CHORUS, VERSE, CHORUS, VERSE, CHORUS, OUTRO. Gepzene CHORUS, UP, CHORUS, OUTRO. |
| AO1 | PASS | Hand and "Play a track first, then Auto DJ can mix out of it." |
| AO2 | PASS | Hand and "Auto DJ brings in a stopped deck. Stop the one you want next." |
| AO3 | PASS | "Load the next track on the other deck first." |
| AO4 | PASS | `AUTO…` lit, "Auto DJ is waiting for the stems to finish." About 3 minutes later by itself: "Loop build in 18 bars." Ended right. I missed the move itself. |
| AP1 | PASS | Under 1 s from the press to "Loop build in 12 bars" on video. `AUTO…`, then `AUTO 12`. |
| AP2 | PASS | Count falls in step. `MIX 106` at 00:04.7 and `MIX 4` at 03:18.9 both point at 03:26.5. ap2-armed.png |
| AP3 | PASS | Houston from 1:30 into Gepzene: Loop build, leaving at 01:54.2. Loop halves, stem colours on, EQ moves by itself. CPU in the table below. ap3-move.png |
| AP4 | PASS | "Loop build done. Deck 2 is on." Old deck stopped, `AUTO` unlit, knobs centred, stems up, no loop or FX dot. New deck at -1.56%, playing 126. ap4-done.png |
| AP5 | FAIL | Same move again. See above. |
| AP6 | FAIL | Depends on the deck. See above. |
| AQ1 | FAIL | Waiting deck's tempo stays moved. See above. |
| AQ2 | FAIL | Stays while moving, but doesn't go back at the end. See above. |
| AQ3 | FAIL | New deck stuck quiet. See above. |
| AQ4 | PASS | Seek well past the start: "Auto DJ lost its moment when the deck moved." Track plays on. aq4-lost-moment.png |
| AQ5 | PASS | `PLAY` on the waiting deck: "Auto DJ stopped: you started deck 2 yourself." Load: "Auto DJ stopped: the track changed." |
| AQ6 | PASS | Bass swap. `BROWSE` open and back, then Calendar for 3 s and back. Carried on: deck 2 00:10.5 to 00:16.9 in about 6 s. "Bass swap done. Deck 2 is on." aq6-background-back.png |
| AQ7 | FAIL | `CUE` on the new deck: see above. The rest: `CUE` on the old deck stops it, the score carries on with about 20 s of near silence until the new stems rise, and it ends right (aq7-cue-on-old.png). `REV` and a tempo change on the old deck carry on and stay as I set them, and a hot cue on the new deck jumps it, ending right (aq7-rev-tempo-hotcue.png, aq7-end.png). A hot cue on the old deck jumps it and the move still finishes. No eject control exists, and load keys say "Deck 1 is playing. Stop it first." during a move, and that move then finished right (aq7-load-refused.png). No crash in any of these. |
| AR1 | PASS | Deck 1 starts the first track, deck 2 loads the next, "Up next", key reads `MIX` and stays lit. `MIX` fits the toolbar. ar1-start.png |
| AR2 | PASS | `MIX 106` at 00:04.7. Left Houston at 03:26 of 04:50, 71% through. |
| AR3 | PASS | Skylander loaded on the freed deck, "Up next: Skylander." Moves by what the decks did: Loop build out of Houston, Loop build out of Gepzene at about 02:47 of 03:48, 73% through. Messages: see Looks wrong. ar3-move.png, ar3-handover.png, ar3-done.png |
| AR4 | PASS | "That's the end of Club." with a green tick, `AUTO` back and unlit. ar4-end.png |
| AR5 | PASS | Playing a list track: carries on, "Up next: Skylander" from Gepzene in Club. Not on the list: "Up next: Houston", the top. Last track: hand and "There's nothing after this track in Club." ar5-where-it-starts.png |
| AR6 | PASS | Waiting or counting down, by the mixer's key and by `MIX`: "Mix off. The track playing just carries on." During a move, by `MIX`: "Auto DJ stopped. The decks are yours." ar6-stopping.png |
| AR7 | PASS | Load the waiting deck: "Auto DJ stopped: the track changed." Start it: "Auto DJ stopped: you started deck 1 yourself." Pause the playing deck: "Mix off: deck 2 was stopped." ar7-reasons.png |
| AR8 | PASS | `All Tracks` by `BPM`: Exhilarate, Severe, then "Up next: Gepzene", the order on screen. Exhilarate into Severe overlapped with no gap of 30 ms or more. Search `so`: Houston, then "Up next: Skylander", only what's showing. Clearing the search afterwards doesn't change the mix. ar8-sorted.png, ar8-search.png |
| AR9 | PASS | Exhilarate's cached stems deleted first, so it was unsplit. Seek near its end: Severe starts when it runs out. Severe into Gepzene the same, "No clean way into the next track, so it'll start when this one ends." The gaps are 3.54 s and 3.16 s below -50 dB, and the level stays at the file's own tail right up to the new track, so the app adds nothing I can measure. ar9-run-out.png |
| AR10 | PASS | Seen in `AUTO`, as the mixes I watched chose Loop builds. Skylander into Houston, "Bass swap in 9 bars": 0.435 s below -50 dB, a beat is 0.48 s at 125, then the new track lands at -8.4 dB. Both waveforms dark and meters down during it. ar10-air.png |
| AS1 | PASS | Houston leading at 125, 5A: Gepzene 128, Skylander 125, Severe 148, Exhilarate 170.6. Houston leaves the list. Closest tempos first. Neither close track has a compatible key here, so tempo wins over Severe's 5A, as it should. as1-next.png |
| AS2 | PASS | Starting Severe and stopping Houston: Houston first, Severe off the list. Exhilarate at 144.08: Severe first. Exhilarate at 169.24: nothing's close, so date order. The browser has no tempo fader, so I changed tempo between looks. |
| AS3 | PASS | `BPM` header takes over and `NEXT` goes out. `NEXT` again brings it back. |
| AS4 | PASS | Nothing loaded: Houston stays first, the rest follow on from it. |
| AS5 | PASS | `MIX` with `NEXT` on: "Up next: Houston", the top of the list showing. |
| AS6 | PASS | From Houston: `IN KEY` leaves Severe. `±6% BPM` leaves Gepzene and Skylander. Search `e` orders what's left. as6-filters.png |
| AS7 | BLOCKED | Only 5 tracks. No hitch seen scrolling or typing, which says nothing about a big library. |
| AS8 | PASS | Duo live. Others in `LayoutSnapshots`, not live: iPad 13, small iPhone (667×375) and iPhone (874×402), each both ways. All readable. Upright it shortens to `KEY`, `±6%`, `NEXT`, `MIX` and two icons. as8-*.png |
| Pressing harder | PASS | 14 minutes of recording, with `MIX` then `AUTO` running and everything below. No crash, and no gap or stop I can't explain. |

### Pressing harder
Both fingers landed together each time, first finger listed first. Second finger slides where it says.
- **Two pads held, landing and lifting together:** `ROLL` 110,582 and 187,582 for 1 s, clock back by +1.2. `ROLL` 265,582 and 343,634 for 1.5 s, +1.1 and +0.8. `SLICER` for 1.2 s, +1.0. Across that video the clock moved 23.40 s in 23.28 s.
- **Also together, nothing stuck:** `ECHO` and `ROLL` FX. Two stem pads, sliding opposite ways and back. Both `BEAT JUMP` keys. `CUE` and `PLAY` on one deck. Both jogs, during a move. Both `HI` knobs. Both tempo faders. `SLIP` and `REV`. The crossfader with a second finger that missed the channel fader it was meant for.
- **Gaps:** 121 runs of 30 ms or more below -50 dB in 846.6 s.
  - 1.29 s at the very start, before `MIX` started.
  - 66.8 s and 63.3 s from AQ7: `CUE` on the new deck, both stopped until I carried on.
  - 47.0 s at the end, with both tracks run out while I was reading results.
  - 0.655 s and 0.45 s inside moves.
  - Everything else is 0.355 s or less, between beats and in moves. The largest group is Houston's own: the same pattern at the same place each time it played, 3.81 s apart at 126 and 3.79 s at 127.

## Timings and measurements
| State | CPU, one core = 100% | Memory |
|---|---|---|
| `AUTO` counting down, Houston and Gepzene | 15% | 684 MB |
| During a move, same tracks | 19% | 685 MB |
| Planning, Skylander and Houston | about 75% for 8 s | 762 to 782 MB |
| A plan that gets refused | about 70% for 5 s | see below |
| `MIX` waiting, in the browser | 10% | see below |

Memory's only comparable within a row: as read by `ps` it ranged from 130 to 782 MB across the session, with the same tracks loaded at times. Planning added about 20 MB.

- **Press to plan:** under 1 s on video, though the CPU keeps working for a few more seconds. A refusal shows about 5 to 6 s after the press, with `AUTO…` until then.
- **Stems:** Houston went from under 20% to done in about 3 minutes, on the CPU, with a deck playing.
- **Loads:** 0.2 to 0.6 s. Two taps sent during one (AV3) took effect 14 ms apart on video, so a load seems to hold touches up until it's done.
- **`LayoutSnapshots`:** the first run wrote all-white pictures with `** TEST SUCCEEDED **` and "image provider timed out" in the log, on a busy Mac. The second was fine. A blank snapshot doesn't fail the test.

## State left on the simulator
Club playlist added. Gepzene's grid is 10 ms later than it was. Exhilarate's stems cache deleted, and it has a stray hot cue G. Houston has hot cue A at 0:21, Gepzene hot cue A at 2:47. Recordings kept in the app.

## First impressions
Not run. This round was the retest only.

## What happened next

**Fixed**
- **AP6: the same pair refused from one deck and mixed from the other.** The tester's lead was right, and it was worse than it looked. A score's steps name real decks, but the audition always had the outgoing track on its private deck 0. From deck 2, the old track got the new track's moves and the new track the old one's, so what was judged wasn't the move. That refused good plans, and it passed ones nobody had heard: in a `MIX`, every second transition went out unchecked. Now each track's on the deck the score names. `testAnAuditionHearsTheSameFromEitherDeck` fails on the old code by up to 0.69 on the output's peaks, for all three moves it tries. On the real tracks, Skylander into Houston now gives the same plan from either deck, and a set of 22 of the owner's tracks comes out line for line the same started from either.
- **AQ3: stuck quiet after stopping a move.** `ALL` and the combinations now bring their stems up to full, a tap on a stem that's all the way down brings it back, and sliding one up from nothing turns it on. A stem that's all the way down now looks off, since it sounds off. `testStoppingPartWayLeavesTheStemsWithinReach`, `testStemsThatAreAllTheWayDownComeBackWhenAskedFor`.
- **AQ7: `CUE` on the new deck ending in silence with a green tick.** A move now notices a deck someone's stopped, and ends. The table's in `docs/AUTO_DJ.md`: before the new track has taken over, stopping it leaves the old one playing clean, and stopping the old one brings the new one in at once. This also fixes this round's 20 s of near silence after `CUE` on the old deck. No green tick and no rating for a move that didn't finish.
- **AQ2: a grabbed knob not going back.** The old deck now goes back to neutral on all three bands. On the new deck, what you took stays as you set it, because that's what people are hearing, and the score's loop and FX clean-up no longer touches anything you started there.
- **AQ1: calling it off leaving the waiting deck moved.** Everything getting ready changes now goes back: tempo and its range, key lock, key shift, sync, EQ, filter, the Color FX, the fader and the crossfader. Anything changed during the countdown stays as it was changed.
- **AP5: pressing again picks the same move.** A repeat now costs 0.5 against the last move, where it was 0.3, which is more than the Loop build's head start over an Echo throw at the same spot. On the 22 tracks that's 3 moves the same twice running where it was 4, the same 19 joins, and key shifts down from 3 to 2. Ratings are the real answer to which move you want.
- **`SLIP` missing its return.** The tester's guess was right. `SLIP` after `REV` never engaged, and in one event the order isn't fixed. It now starts from then, as it does during a loop. `testSlipPressedAfterReverseStillComesBack`.
- **`NEXT` and the sort forgotten, and a playlist's order.** The browser now keeps the playlist, the sort, `NEXT` and the filters, across launches too. A playlist stays in the order it was built, which is what `MIX` plays, until a column's chosen, and a column's third tap goes back. Before this there was no way back to date order either.
- **A long fade before the next track.** With no move coming, the next track starts as soon as the old one has nothing left to hear, at -50 dB. `testAMixDoesntSitThroughAFadeIntoSilence`.
- **Messages.** "Up next" no longer covers the message about a missing transition, and that's now "No clean way in. Deck 2 just started." The ratings commit already keeps it off "`<move>` done." The two cut off with dots are shorter. Everything stopped from outside now starts "Mix off:" in a mix and "Auto DJ stopped:" otherwise.
- **"Stems 8%" under the next track.** It was the last track's progress, shown until the new one finished loading. It's left out during a load.
- **A blank snapshot** now fails `LayoutSnapshots`.

**Found on the way, that nobody had reported**
- **A knob the score was moving snapped back when you let go.** Once someone's taken a control the core stops reporting it, and `followControls` kept showing that last report, which put the control back every 33 ms. It only looked right on `HI` because the score doesn't move that one. It's in the task to try on `LOW` and a stem. `testAControlTakenFromTheScoreStaysWhereItsPut`.
- **Stopping a move left its effects and noise on the old deck,** with nothing on screen showing them and no way to turn them off. They now go. `testStoppingLeavesNothingYouCantSee`.
- **Stopping once the new track had landed brought the old one back** as a tiny loop over the top of it. It now just ends the move. `testPressingOnceTheNewTrackIsOnJustEndsIt`.
- **A new deck nobody had heard yet was left silent** after stopping a move, so `PLAY` on it later would have made no sound. `testStoppingBeforeTheNewDeckStartsLeavesItReady`.
- **Three tests were seeking in the wrong units,** frames where seconds were wanted, which sent the deck to the very end. It happened to work. They now seek to where they meant, which is also why some now get a Bass swap where they'd got a Loop build.

**Decided against changing**
- **Severe Tire Damage's 148 BPM:** the tester's own check agrees it's no worse than anything else, and that track has no clear steady beat to find.
- **A hot cue set by a tap landing as the browser closed:** the pad really was there by then, and pads have to act on first contact.
- **Loads holding touches up until they're done:** nothing's lost, by this round's own timing.

**Not run**
- **AV5 and AS7** were blocked. They're covered by `LoadingTests` and `testAHugeListKeepsEverythingAndDoesntHang`, and they're off the task, as they can't be driven from here.
