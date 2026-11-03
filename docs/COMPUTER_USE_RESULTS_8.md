# Hands-on results, part 8, 2026-11-02

Commit tested: 970a91f
Device: iPhone Duo simulator, unfolded (951×669 pt), clean install, driven by real touches. iOS 27.2.
Tooling limits:
- **Not judged:** how anything sounds, haptics and the headphone output. I measured levels and gaps from recordings and video, and nothing here says a move sounds good.
- **Small iPhone:** the touch tool asks the owner's permission for each new simulator. I asked twice for the iPhone SE and nobody answered, so AX5 is blocked. I ran the same checks on the Duo rotated upright, which gets the upright layout but is 669 pt wide, not 375.
- **Tool lag:** a tool call takes 1 to 4 s, so I can't hit a chosen beat. Where timing mattered I give the clock it landed on, and I can't choose which of two fingers lands first.
- **`SLIP` with `REV`:** the clock readings come from screenshots, so each has about 0.5 s of error, more when the Mac was busy.

## Summary
30 tests: **25 PASS, 2 FAIL, 1 BLOCKED, 2 just reported** (AY4 and AX4, which ask for what I saw). No crashes: the only Cheeks crash reports are from 10:32, before this round.

Round 7's six failures are fixed. Both decks now give the same plan, stopping a move leaves the decks usable, and `CUE` no longer gives a green tick with both decks stopped. Grabbing `LOW` and a stem while the score was moving them held. The rule table did what it says in every row.

The problems, most important first:
1. **PH: `AUTO` with a loop running counts down forever.** It plans, says "Loop build in 12 bars", and the key's count goes back up each time the loop wraps, so the move never comes. This also happens after stopping a move, since the score's loop stays. New this round.
2. **AQ11: pressing the key during a mix's move says "Auto DJ stopped. The decks are yours."**, not `Mix off:`. The mix does end. Small.
3. **AX5:** blocked on the small iPhone. On the rotated Duo everything worked.

## Failures

### PH: `AUTO` with a loop running never gets there
- Steps, first time: stop a Loop build with `AUTO` 8 s in, which leaves the score's 4-bar loop running. Press `AUTO` again.
- Steps, second time: on a playing deck, press `IN`, then `OUT` a few seconds later, which set a 7-beat loop, then `AUTO`.
- Expected: the move happens, or it says why it can't.
- Actual, first time: "Bass swap in 14 bars." For 1 min 40 s the key's count went round, reading 13 and 16 at different looks, with no further message and no move. `EXIT` freed it, and the swap then started.
- Actual, second time: "Loop build in 12 bars." The key read 12 two seconds after pressing and 11 about 55 s after, with the deck still going round its loop. I pressed `EXIT` then, and it played a Loop build.
- Lead, from reading the code and not tested: `tick()`'s `.armed` case (`AutoDJ.swift:552`) only gives up once the playhead is past `armFrame`, and a deck in a loop never gets there. `updateBarsToGo` counts from the playhead, so it wraps with the loop. I didn't try it during `MIX`, which goes through the same case.
- Screenshots: `ph-auto-stuck-in-loop`, `ph-auto-manual-loop`

### AQ11: `Mix off:` isn't said when the key's pressed mid-move
- Steps: `MIX` through `Order`. Seek Houston close to its exit. Press the key 8 s into the Loop build.
- Expected: `Mix off:`.
- Actual: "Auto DJ stopped. The decks are yours." The mix did end, and the key went back to `AUTO`. `CUE` on either deck said `Mix off:` as it should.
- Lead: `press()` (`AutoDJ.swift:173`) uses `wasSet` for the countdown but not for the `.running` case.
- Screenshot: `aq11-mix-stop-early`

## The rule table
**Does it do what it says?** Yes, in every row:

| What I did | Before the new track took over | After |
|---|---|---|
| Press `AUTO` | AQ5, AQ6 | AQ7 |
| Stop the new deck | AQ8 | AQ10 |
| Stop the old deck | AQ9, both cases | Round 3 of the long run: `CUE` on the old deck just after an Echo throw's handover. The move played out. |

**One line that doesn't match:** "None of these ask for a rating." That last case, the old deck stopped after the handover, ended with "Echo throw done. Deck 2 is on.", a green tick and the two thumbs. A move that plays out probably should ask, so I'd change the sentence, not the app.

**Where I think the rule could be better:**
- **Loading the waiting deck mid-move isn't in the table, and it's inconsistent.** It says "Auto DJ stopped: the track changed." and treats it like pressing `AUTO`: the old deck stays in its loop with its `LOW` and filter as the score left them. `CUE` on that same deck leaves the old deck clean ("carries on"). Both take the new deck away, so I'd expect the same result, clean. Screenshot `ph-load-mid-move`.
- **Stopping late in a Loop build leaves the least usable state.** The old deck can be left in a very short loop with its filter and `LOW` moved. All of that shows on screen, so the rule holds, but it takes `EXIT` and two knobs to recover, and pressing `AUTO` first hits the problem above. I don't think the rule's wrong. This is just the case I'd look at again.

## Looks wrong
- **`REV` on a move's new deck:** the move still ends with a green "Loop build done. Deck 2 is on." while the deck runs backwards towards 0:00, where it stops. It's what I asked for, but "is on" is generous.
- **`REV` on a move's old deck** stays lit after the deck has stopped and reset.
- **"Auto DJ lost its moment when the deck moved."** is also what it says if you pause the deck during the countdown, when nothing moved.
- **"No Results. Check the spelling or try a new search."** shows when only the filters have emptied the list, with nothing typed. Seen with `IN KEY`, `±6% BPM` and `NEXT` on in `Order`.
- **A recording's tracklist skips a track that comes back on the same deck.** My 14-minute run lists 4 entries, and Gepzene's return from about 2:50 to 12:00 is missing, so Skylander appears to run for 11 minutes. It only showed because I kept replaying the same tracks.
- **UIKit debug faults:** "Decomposition of 'bounds' was requested on layer", and the same for 'position', in bursts around 16:00 to 16:01 and at 17:20. I was using the New Playlist alert and the context menus at those times, though I can't tie each burst to one. Nothing visibly went wrong.

## All results
| Test | Result | Notes |
|---|---|---|
| AY1 | PASS | Skylander from about 1:37 into Houston. Deck 1: "Loop build in 5 bars", old deck stopped at 1:48.0, bar 56. Deck 2: "Loop build in 6 bars", stopped at 1:48.0. Both ended right. |
| AY2 | PASS | Three more pairs, each way round, after a relaunch. All the same both ways. See below. |
| AY3 | PASS | `MIX` through `Order`. Loop build from deck 1, then Echo throw from deck 2, leaving Skylander at 4:06 of 6:00, with Gepzene at 0:25.8 when it finished. It ended right and looked as sensible as the first. |
| AY4 | Reported | Loop build, then Echo throw straight after, then Loop build. Varied. Later runs on one pair: Echo throw, Bass swap, Loop build, Bass swap. |
| AQ1 | PASS | Tempo -4.8, a mixer `HI`, filter, fader low, crossfader off-centre and `DUB` all back as I set them. During the countdown the tempo read -0.8. "Auto DJ off." and the track played on. |
| AQ2 | PASS | Tempo moved to +3.3 and `MID` moved during the countdown: both stayed. The rest went back. |
| AQ3 | PASS | Old deck. See "Grabbing" below. |
| AQ4 | PASS | New deck. See "Grabbing" below. |
| AQ5 | PASS | Pressed about 3 s in. Message right, loop stays. Old deck's stems all muted: meter went dark. New deck's stems up, tempo back to +0.0, its `PLAY` on the meters within a second. Couldn't judge by ear that the noise and reverb stopped, but the dark meter says nothing was left. |
| AQ6 | PASS | Pressed at the new deck's 0:21. Its pads looked off. `ALL` brought all four up. Separately, a tap on `VOCAL` came back at full and lit `ACAPELLA`, and sliding `BASS` up from nothing turned it on. |
| AQ7 | PASS | Pressed after the drop: "Auto DJ stopped. Deck 2 is on." Old deck stopped, no tick, no rating. |
| AQ8 | PASS | "Auto DJ stopped: deck 2 was stopped. Deck 1 carries on." Old deck: loop gone, knobs centred, stems up. New deck stopped at its start, tempo +0.0. No tick or rating. |
| AQ9 | PASS | See below: 0.15 s below -50 dB when the new deck hadn't started, none when it had. |
| AQ10 | PASS | "Auto DJ stopped: deck 2 was stopped." Both stopped, no tick. |
| AQ11 | FAIL | `CUE` on either deck says `Mix off:` and ends the mix. Pressing the key doesn't say it. See above. |
| AQ12 | PASS | See below. No message cut off with dots on this screen. |
| AX1 | PASS | Both messages right, and each press saved a line with the move, both titles and the answer. Reach below. The keys never took each other's press. |
| AX2 | PASS | Went by itself after about 8.8 s of deck clock. Nothing saved: the file stayed at 9 lines. |
| AX3 | PASS | Stayed up about 8.2 s with Gepzene loading underneath, and no `Up next` over it. The move's name now shows in a mix. |
| AX4 | Reported | It leans, and one press can change a plan. See below. |
| AX5 | BLOCKED | Small iPhone: no permission for the simulator. On the Duo upright: text readable, `UNDO` and thumbs up worked (I didn't press thumbs down there). A tap on the overview under the capsule went through (deck 1 went to 3:00). `KEY` just beside it in the browser worked, though the capsule covers part of the search field. |
| AZ1 | PASS | `Order`, `BPM` sort, `NEXT`, `IN KEY` and `±6% BPM` all kept across closing and a relaunch. `IN KEY` and `±6%` are dimmed with no deck loaded, and light again once one is. Deleting the playlist I was viewing went to `All Tracks`. |
| AZ2 | PASS | Added Houston, Skylander, Gepzene, which isn't date order. It showed that way, it's stored that way, and `MIX` played it that way. |
| AZ3 | PASS | Three taps go one way, the other way, then back, in `Order` and in `All Tracks`. A column takes over from `NEXT`. The same column with `NEXT` on gave the same order as before. |
| AZ4 | PASS | Exhilarate with no stems, into Gepzene. 0.51 s below -50 dB, against 3.54 s last time. "No clean way in. Deck 2 just started." stayed about 5 s with no `Up next`. |
| AZ5 | PASS | 10 of 10 came back. See below. |
| AZ6 | PASS | Loaded split Skylander while Gepzene split, browser open. No `Stems n%` under Skylander at any of three looks, and Gepzene's own 20, 22, 28% stayed under Gepzene. |
| AZ7 | PASS | Slid `VOCAL` down: it looked off and `NO VOCAL` lit. A tap brought it back at full. `ACAPELLA`, `NO VOCAL` and `BEAT` each lit, and `BEAT` brought a half-slid `BASS` up to full. `ALL` brought all four up. |
| AZ8 | PASS | `LayoutSnapshots` passed with 8 browser pictures, none blank. I didn't see a blank, so the new failure wasn't exercised. The toolbar fits on `small`, `iphone`, `small-up` and `iphone-up`. Those are snapshots, not the live app. |
| Pressing harder | FAIL | 14 min 30 s, 15 rounds. One failure, the `AUTO` loop above. No crashes or dropouts, and nothing left silent, looping or filtered that the screen didn't show. |

### AY2: the same plan from either deck
| Pair | From deck 1 | From deck 2 |
|---|---|---|
| Skylander into Houston | Loop build, leaves at 1:48.0, bar 56 | The same |
| Houston into Gepzene | Loop build, leaves at 1:23.8, bar 44 | The same |
| Gepzene into Skylander | Loop build, leaves at 0:47.0, bar 25 | The same |
| Houston into Skylander | Loop build, leaves at 1:23.8, bar 44 | The same |

Each started from the same point on the overview, after a relaunch. The clock is where the old deck stopped, and bars count from the track's first beat.

### AQ3 and AQ4: grabbing while the score's moving it
My first runs didn't really test this, as I got there before the score reached those controls, or after the landing. So I repeated it on a Bass swap, with the touches landing just after it started. Screenshot `aq3-aq4-score-moving`, three moments top to bottom.

| Control | Grabbed | What the score does to it | What happened |
|---|---|---|---|
| Old `BASS` | Slid down part way | Cuts it to 0 at the air | Stayed at my level past the landing, while `VOCAL` and `INST` were cut. It lit `BEAT`, as bass and drums were what was heard. |
| Old `LOW` | Turned up | Cuts it to 0 | Stayed turned up |
| New `DRUMS` | Slid to the bottom | Ramps it up, then sets it to full at the landing | Stayed down through the landing and after the end, with no jump in the clock. The other three came up to full. |
| Old deck, at the end | | | Everything back to centre, all four stems up, deck stopped |

The earlier Loop build run also held on old `HI`, `LOW` and `INST`, and all went back at the end (`aq3-grabbed`, `aq3-end`). On the new deck, `HI` and `INST` held past the end.

### AQ9: the silence after `CUE` on the old deck
Measured from a recording, in the same session:
- **New deck hadn't started:** "Auto DJ stopped: deck 1 was stopped. Deck 2 is on." One run of 0.15 s below -50 dB, then the new deck at full from 0:23.
- **New deck had started:** "Auto DJ stopped: deck 2 was stopped. Deck 1 is on." No run below -50 dB. The level sits at about -25 dB for 2 s, because Skylander is quiet there: its source file reads about -20 dB at that point.

Last time: about 20 s of near silence.

### AQ12: everything else
| What I did | How it ended |
|---|---|
| Moved the deck in the countdown | "Auto DJ lost its moment when the deck moved." Waiting deck back at +0.0. |
| Loaded the waiting deck in the countdown | "Auto DJ stopped: the track changed." |
| Pressed the waiting deck's `PLAY` in the countdown | "Auto DJ stopped: you started deck 2 yourself." Both playing. |
| `BROWSE` open and closed during a move | No effect. It ended right. |
| Background during a move, about 10 s | It carried on: the new deck had started when I came back, and it ended right. |
| `REV` on the old deck | It rode through. Stopped and reset at the end, with `REV` still lit. |
| `REV` on the new deck | "Loop build done." while running backwards. It stops at 0:00. |
| Tempo on both decks during a move | Both taken: +4.3 and -5.3. It ended right, and the tempo stayed as I set it. |
| Hot cue set and fired on both decks | Taken each time. It ended right, with the cues kept. |

### AX1: how far the keys reach
Thumbs up is drawn at x 766 to 795, and thumbs down at 802 to 832.

| Press | Result |
|---|---|
| x 797 (2 pt past thumbs up) | Thumbs up |
| x 799 (3 pt before thumbs down) | Thumbs down |
| x 834 and 836 (past thumbs down) | Nothing |
| Under thumbs down, y 27, about 5 pt below the key | Thumbs down |
| Under thumbs down, y 30 | Nothing |

The two meet at about x 798. I didn't try past the left edge of thumbs up.

### AX4: does it lean?
The same pair from about the same place: Skylander into Houston, from a relaunch.

| Ratings so far, by move | What it chose |
|---|---|
| None | Loop build, every time from here |
| Loop -1, Bass +1, Echo +1 -1 | **Bass swap** |
| Bass +1 -1 | Bass swap |
| Bass +1 -2 | Bass swap |
| Bass +1 -3 | **Loop build** |
| Loop -2 | Bass swap |

So it leans, and one press can change a plan. It went between these two and didn't pick a third. I didn't press six on one move: it was 3 on Bass swap and 2 on Loop build, as the choice kept moving, and I stopped there.

### AZ5: `SLIP` with `REV`
Both landing together, 2 s or more of reverse, then `REV` off, then `SLIP` off. Drift is how far the clock ended up from real time.

| Cycle | Fingers | Drift after `REV` off |
|---|---|---|
| 1 | `SLIP` first | +1.6 s, with the Mac busy starting the SE, so screenshots were slow |
| 2 | `REV` first | +0.1 s |
| 3 | `SLIP` first | 0.0 s |
| 4 | `REV` first | 0.0 s |
| 5 | `SLIP` first | -0.1 s. Read mid-cycle: the clock had gone back 4 s, so reverse really was on. |
| 6 | `REV` first | -0.6 s |
| 7 | `SLIP` first | 0.0 s |
| 8 | `REV` first | -0.6 s |
| 9 | `SLIP` first | -0.2 s |
| 10 | `REV` first | -0.1 s |

`SLIP` pressed with `REV` already held: -1.2 s from the clock I read about a second before pressing, so that's about the lag. Last time one in four went about 31 s astray.

### Pressing harder
Mixing both ways round across Gepzene, Skylander and Houston, with a recording running throughout.

| Round | What I did | How it ended |
|---|---|---|
| 1 | Loop build. Grabbed old `LOW` and `BASS`, new `HI` and `VOCAL`. | Done, with old back to centre |
| 2 | `AUTO` straight after. Bass swap. `CUE` new. | "Deck 1 carries on." |
| 3 | `AUTO`. `CUE` old just after an Echo throw's handover. | The move played out |
| 4 | `AUTO`. Pressed it 8 s into a Loop build. | "The decks are yours." |
| 5 | `AUTO` with that loop still running | **Stuck counting.** `EXIT` freed it. |
| 6 | Pressed `AUTO` during that Bass swap | "Deck 1 is on." |
| 7 | `MIX`, seek, grabbed old `INST` and `MID` | Done, then "That's the end of Order." |
| 8, 9 | `AUTO` with both stopped, then paused the old deck in a countdown | "Play a track first…" with a hand, then lost its moment |
| 10 | Pressed `AUTO` close to a drop's air | "Deck 2 is on." with all stems up. It landed just after the drop. |
| 11 | Browser in a move. Load onto the old deck, then the waiting deck. | Refused with a hand, then "the track changed" |
| 12 | `EXIT`, left its filter on, `AUTO`. A Vocal tease, the first I'd seen, with a -1 key shift. | Done, with filter back to neutral |
| 13 | `MIX`, then `PLAY` on the waiting deck | "Mix off: you started deck 2 yourself." |
| 14 | `AUTO` with both playing ("Auto DJ brings in a stopped deck…" with a hand), then pause one, `AUTO`, background during the move | Done |
| 15 | `AUTO`, called off | "Auto DJ off." |

**The recording:** 14 min 32 s. Every run of 0.25 s or more below -50 dB has a cause:

| Where | Length | Cause |
|---|---|---|
| 2:43, 2:58, 10:16, 10:31 | 0.28 to 0.36 s | Gepzene's own opening bars: its source file has the same pair of gaps, 0.34 and 0.28 s long and 15.1 s apart |
| 6:23 | 0.42 s | A Bass swap's beat of air |
| 8:33 | 40.8 s | Both decks stopped, by me (the end of `Order`, then round 8) |
| 9:21 | 11.5 s | The old deck paused, by me (round 9) |
| 12:05 | 0.26 s | Gepzene's own gap at about 1:15, which shows in its source file |

So nothing looks like a dropout. Shorter runs of 30 ms and up, 185 in all, I didn't check one by one, and many are Gepzene's short notes.

## Timings and measurements
Not CPU-table conditions: other simulators were running. Figures for this simulator's own process.

| State | CPU | Memory |
|---|---|---|
| Splitting stems, browser open | 79% | 891 MB |
| A deck playing, browser open | 6.5% | 493 MB |
| After the long run, one deck playing | 12.6% | 546 MB |

- **Press to plan:** "`<move>` in N bars" on screen within 1 to 2 s.
- **Stems:** the first two tracks took 206 s, on the CPU.

## State left on the simulator
- Playlist `Order`, and today's History.
- 10 ratings in `auto-dj-ratings.json`, mixed on purpose, so they lean the choice from here. A clean install resets them.
- Hot cues: Skylander A at 1:46, Houston A at 0:22, Gepzene A at 1:57.
- Three recordings, kept in the app.
- The Duo is back on its side at 951×669.
- The iPhone SE has the app with copied music and stems, and I shut it down.

**`Cheeks.xcodeproj/project.pbxproj` has an uncommitted change, not mine:** `DEVELOPMENT_TEAM` set, at 16:19 during this round. I left it alone and out of this commit.

## First impressions
Not run. This round was the retest only.
