# Hands-on results, part 17, 2026-11-05

Commit tested: 9d60f8d

Device:
- **iPhone SE Cheeks:** 667×375 on its side, for the retest, the long run, CPU and the first-time user.
- **Folded iPhone Duo:** 466×678 pt, upright phone layout, for `GC3`, `GC5`, `GC6`, `G`, `H`, `I` and most of `B`, `C` and `D`.

Tooling limits:
- **The full layout can't be pressed.** The Duo's still folded: the last `hingeState:` in SpringBoard's log says `Closed`, at 13:01 on 11-04. I didn't reboot it. I asked for the iPad's touch access at 23:25 and at 01:16, and neither was answered. So `GA1` to `GA4` are blocked.
- **Can't be checked here:** how anything sounds, haptics, the headphone output and a real finger. Levels are read from recordings and meter pixels.
- **Double-tap on a knob:** two tool taps are too slow to count, so it's blocked in `I2`.
- **Presses in a slide:** I sent them straight after the key, so by timing they were in or just after the slide. I didn't freeze the app for these this round, because the long run was recording.
- **Screen reading:** a logger read the top of the screen by OCR about twice a second. It stalled twice, at 23:45:06 and 00:03:05, for up to 40 s, and I restarted it. The recording and the screenshots cover those times.
- **Busy Mac:** another project's archive was running at the start, and XProtect scans and `pairedsyncd` came and went. Mac idle was 46 to 69% during the CPU table. The first-time user was on the small iPhone from 00:18 to 01:05, while I worked on the Duo.

## Summary

48 scripted tests including the long run: **42 PASS, 1 FAIL, 5 BLOCKED.** The failure's small: `GC4`, a minus at the end of one track in four. The blocked ones are `GA1` to `GA4`, and `GC10`, as no Vocal ride came up. `GB3` was skipped, as the task says. No crash reports. Outside the script, the long run and the first-time user found faults, listed under Failures as `N23` to `N27`.

**Everything that failed last round is fixed.**
- **`N21`, the hole in a mix:** a seek past the exit plans again within 8 s and echoes out soon after. Near the end of a track, the next one starts about 0.25 s after the last sound, where it was minutes of nothing and a 4.1 s gap. See `GB1`, which also accounts for your 0.33 s.
- **`N17`, the range key:** it refuses with the right words, and the fader doesn't jump.
- **`N20`, `N18`, `N19` and `C9`:** all fixed as described. A recording made during a preview is digital silence.

**The three most important problems:**
1. **`N23`: while a mix is on its last track, a track loaded on the waiting deck is ignored.** Nothing's said, and the line goes on saying "This is the last track". The mix ends with a green tick and silence, with the loaded track sitting cued. Everywhere else this round, loading on the waiting deck worked well, so this is the one place it doesn't.
2. **`N24`: `BEAT SYNC` on a playing master deck, with the other deck stopped, takes it to the stopped deck's tempo.** One press took a playing 170 to 125, with the range going to `WIDE`, and the key didn't light. The deck still reads `MASTER`, so it's following nothing. The first-time user hit it too.
3. **`N25`: nothing tells a first-time user to swap the `LOW` knobs.** This one's theirs and it's a gap, not a fault. The crossfader appears to do the whole job, at +1:07, and the guide's recipe is what taught them otherwise, at +15:59. See below.

**The first-time user's question.** They could say what Auto DJ does at **+10:41**, against 16:52 last round and 34 minutes before that. They call it mostly luck: `MIX` ran a Loop build while one deck happened to be on `STEMS`. `AUTO`'s new message wasn't what got them there. They followed it twice in eight moves and got nothing they could use from it, partly as they only see a frame every few seconds. **`MIX`'s moves don't carry that message at all,** only `AUTO`'s do, so someone who only ever presses `MIX` never gets the tip. I confirmed that from my own log.

**`GC1`, the overview's hold:** the first-time user called the refusal "one of the best moments", and it didn't read as broken. It never got in my way either, in about 12 seeks. A quick slide of more than 8 pt does still jump a live deck. See below.

## Failures

### GC4: `-00:00.0` at the end of a track
- Steps: let a deck run out.
- Expected: `00:00.0`, with no minus.
- Actual: 3 tracks of 4 read `00:00.0` (Gepzene, Fast Bird, Exhilarate). Severe read `-00:00.0` in red, stopped at `06:51.8` (01:22:14).
- Cause: `DeckPanel.swift:524`. `Format.toGo` adds the minus from 0.05 s, and `tenths` rounds down, so a deck that stops with 0.05 to 0.1 s left reads minus nothing. Any deck passes through that for a moment, and it only stays on one that stops there.
- Screenshot: `gc4-minus-at-the-end-of-severe.png`.

The rest are new, and outside the script.

### N23 (new, from the long run, reproduced): a track loaded during a mix's last track is ignored
- Steps: a mix on its last track, with the line reading "Mixing through all your tracks. This is the last track." Load another track on the waiting deck with the row's key.
- Expected: "Up next: X. The mix carries on." and a move into it, as loading on the waiting deck does at every other point in a mix. Or, failing that, something that says it won't.
- Actual: nothing's said, the line doesn't change and the key reads `MIX` with no count. When the last track ends: "That's the end of this list." with a green tick, and silence, with the track I loaded still cued.
  - **Clean reproduction,** on the small iPhone at 01:21: a search for `Kev`, and `MIX` from nothing, so Exhilarate and then Severe. On the last track at 01:21:36, with 6:27 of it left, I loaded Houston, which hadn't been played, on the waiting deck at 01:21:50. Its row lit, and nothing else happened. I took Severe to 11 s from its end and left it alone. At 01:22:14 the mix ended, with both decks stopped and Houston cued at `00:00.0`.
  - **Long run:** Severe loaded in the same way at 00:07:54, with the same silence from the app. I then started it by hand for `GC9`, so the music went on.
- Where I'd look: `AutoDJ.swift:350` to `371`. With `set.next` nil, `advanceSet` only asks `loadNext` for something from the list and returns, so it never looks at what's on the waiting deck. The changing-what's-next branch at `:379` needs a `next` to compare.
- Screenshots: `n23-line-on-the-last-track.png`, `n23-houston-loaded-nothing-said.png`, `n23-mix-ends-with-a-track-cued.png`, `long-end-of-tracks.png`.

### N24 (new, from the first-time user, reproduced): `BEAT SYNC` on the playing master follows a stopped deck
- Steps: deck 2 playing and `MASTER` at its own 170. Deck 1 stopped, holding a track at 125. Press deck 2's `BEAT SYNC`.
- Expected: it's the only deck playing, so either nothing changes and it says why, or `BEAT SYNC` lights to show it's following.
- Actual: "Deck 2's 26% slower than its own 170 BPM, to follow." It plays at 125.00 at once, the range goes to `WIDE` and the fader reads -26.5. `BEAT SYNC` isn't lit, `MASTER` stays lit, and the top bar says `MASTER 2 125.00`. So what's on air slows by a quarter, and the screen says it's leading and not following anything. A later press did the same again: from 79.13, it went back to 125.00.
- Where I'd look: `DJEngine.swift:447`. It's deliberate that syncing the master means following the other deck. I think what's missing is the case where that other deck isn't playing.
- The first-time user at 00:30:59 had the same result, and "I didn't expect a master to follow anything."
- Screenshots: `n24-beat-sync-on-the-master.png`, `fu-22-jog-page-sync-to-stopped.png`.

### N25 (new, from the first-time user): the crossfader looks like the whole job
- They had two tracks playing and crossfaded in 1:07. Nothing on the deck page suggests more, and the first mention of swapping the `LOW` knobs was in the guide, at +10:59, which they did at +15:59.
- Their one change would be a single tip, the first time both decks are playing: bring down `LOW` on the incoming track, swap the `LOW`s as you crossfade, and a way into `MIX TWO TRACKS`. The app's already got the "New to this?" tip as a pattern.
- It's a suggestion, not a fault, and their knowledge makes it the sharper: they knew to look, and a newcomer wouldn't.

### N26 (new, from the first-time user, reproduced): a recording's delete has no Cancel
- Steps: Recordings, `…`, `Delete`.
- Actual: "Delete this recording and its tracklist?" with a red `Delete` and nothing else. A tap outside does cancel, which you have to guess. A track's delete has a `Cancel`. It's on the small iPhone on its side, and may be how iOS draws that dialog there.
- Screenshot: `n26-recording-delete-no-cancel.png`.

### N27 (new, from the first-time user, confirmed): "Memory cue saved." has a trash icon
- `ContentView.swift:615` gives any message with an `UNDO` the `trash.circle.fill` icon. That was right while `UNDO` only came with a delete. Since this round's `SAVE CUE` offers one, good news arrives with a bin beside it.
- Screenshot: `n27-trash-icon-on-a-saved-cue.png`.

## Blocked
- **`GA1` to `GA4`:** these need the Duo opened in Device Hub or the iPad's touch access. Nobody's pressed during the full layout's slide since it changed, so `GA4` is the one that matters.
- **`GC10`:** no Vocal ride came up.
- **`I2`'s double-tap:** the tool's too slow.

## Looks wrong
- **`REV` with `SLIP`, on a deck that gets back to the start.** Reproduced from the first-time user. It runs back to `00:00.0` and stops. Turning `REV` off then takes the clock to `00:08.9`, still stopped, with no word (`n25-rev-off-with-slip-stopped.png`). It's `SLIP` doing what it says, as the first-time user worked out from `?`, but a stopped deck moving by itself looks like a bug.
- **"No clean way in. Next track starts when this one ends." stays up about 4 s after a seek back,** with `MIX 40` already counting beside it.
- **"Brake drop starting. Put both decks on STEMS to watch it."** A brake drop doesn't do anything you'd see on the `STEMS` page.
- **`Stems 100...`.** While a split's finishing on the small iPhone, the deck's status reads that for a moment, as `100%` doesn't fit: my logger caught it at 23:33:39 and 23:40:37, and the first-time user saw it at 00:22:56.
- **Before restore's name is in UTC.** `Before restore 2026-11-05T083341.json` was made at 00:33 on the Mac's clock. It's correct by the task's wording, and it could read as the wrong time.
- **A row's tap in the browser does nothing,** with no highlight and no word. Reproduced. It's the first thing the first-time user tried on a row.
- **On a `MEM` page with room to spare, the arrows stay, with nothing between them.** Only the number was meant to go, and there's nowhere for them to lead yet.
- **The `SAMPLE` sheet's `Record the Master` fires straight away and replaces the pad.** `Restore the Original Sound` gets it back. On the small iPhone on its side the rows are about 34 pt apart and the sheet's contents are 39 pt taller than it is, so a flick moves them under a finger for about 0.7 s (`sampler-sheet-scrolled.png`). That cost the first-time user two wrong rows, through a slow tool. A real finger might never do it.
- **The first-time user's other small ones,** which I haven't checked: first-time tips sliding under the `?` bubble and getting cut off, the waveforms hopping 3 to 4 pt as `JOG` is pressed, a hand-made loop reading 7.7 on the deck and 7.8 in `LIST`, and "Deck 1 follows at half tempo" staying up after the BPM's been doubled back.

## What the first-time user got wrong, checked against the app
- **"The `MIX` button truncates to `MIX...` for a three-digit count."** No. That's `MIX…`, the no-plan-yet state, which they saw just before a count arrived. Their own `fu-39` shows `MIX 116` fitting, and I saw `MIX 107` fit.
- **"`CHORUS` on a blank stretch of Exhilarate."** Exhilarate has about 0.5 s of silence and then music at -12 dB straight away, so it starts on a loud part. I think the blank was the waveform before the track's start. The other wrong names came before the stems were ready, which you've said not to report.
- **"The tempo fader takes a drag from close by."** Its touch is the cap's width, all the way up its column. On the small iPhone on its side, a 20 pt drag at x 560 and x 568 did nothing, and x 575 moved it, with the platter ending at about x 568. It's relative, at 1.34% a point on `WIDE`. So 7 pt separates a platter from a tempo jump, and a jump is what they got, but it wasn't a reach.
- **"Whether a saved recording keeps playing after you close its sheet."** It stops: `RecordingsView.swift:47`.
- **"Whether History counts loads or plays. It reached 15 entries for 5 tracks."** As I understand `OnAirLog`, it's a line after 10 s audible, and another each time a track comes back after something else has had one. I haven't checked their 15 line by line, and they did swap tracks a lot.

## All results

| Test | Result | Notes |
|---|---|---|
| GA1 | BLOCKED | The Duo's folded and the iPad's touch access went unanswered |
| GA2 | BLOCKED | Same |
| GA3 | BLOCKED | Same |
| GA4 | BLOCKED | Same. Slide presses on the small iPhone were fine, see the long run |
| GB1 | PASS | `N21` is fixed. See the table below |
| GB2 | PASS | `N17` is fixed. Refuses with "Deck 2's 24.7% from its own speed, so it needs WIDE." A 5 pt touch went from -24.7 to -31.5, in step, with `BEAT SYNC` going off and nothing said. At -12.6 it goes round ±16 and `WIDE` only. A new track's range goes back to ±10, and an 18 pt nudge is +2.43 |
| GB3 | Skipped | As the task says |
| GB4 | PASS | `N20` is fixed. `VOCAL` at 24% and `BEAT` at 29% say so, and `ALL` says nothing. Once it was split, pads said nothing |
| GB5 | PASS | `N18` is fixed. About 1 s after the question left: "Got it. More like that." and deck 1's clock ran straight on |
| GB6 | PASS | `N19` is fixed. A blue ring goes round the stop mark. A recording of 22.8 s during a preview, with both decks stopped, is digital silence, -100 dB throughout. With a deck playing: "This preview's over the mix, as SPLIT's off. It won't be on a recording." |
| GB7 | PASS | `C9` is fixed. All the tabs keep their size and place through `MEM`, `SLICE`, `JUMP` and `SMPL`, and nothing's clipped. `ROLL` and `STEMS` nearly touch |
| GC1 | PASS | A tap and a 0.2 s press only say so. 0.32 s jumps, and so does a slide. A stopped deck goes at once. See below for whether it feels right |
| GC2 | PASS | Five loads mid-mix: while splitting, at `MIX 10`, at `MIX…`, and with tracks already in the queue. "Up next: X. The mix carries on." each time, what it replaced came right after it, and the count stayed true. On the last track there's no plan to change, and it doesn't work: see `N23` |
| GC3 | PASS | On the folded Duo upright, Settings, Recordings, the cue list and a sampler sheet were all the way up in the first frames that showed them. Flicks close them, and I got no parked bar. The mixer sheet's still a half. On the small iPhone on its side, the sampler sheet's at rest within 0.2 s of arriving. See Looks wrong for what a flick does |
| GC4 | FAIL | The real time's right: at 86.9%, over 20.26 s of stopwatch, the countdown lost 20.2 s and the elapsed clock gained 17.6 s. The end isn't always: 3 tracks of 4 read `00:00.0`, and Severe read `-00:00.0`. See Failures |
| GC5 | PASS | Upright on the folded Duo, deck 2's `JOG`: the readout and the bottom pads clear the home indicator |
| GC6 | PASS | The first cue says "Memory cue saved. The track loads here now." and `UNDO` takes it back, by a plain tap and a 0.15 s press. A later one says "Memory cue saved." A full swipe in `LIST` shows a blue `Delete`, and the library still had the cue |
| GC7 | PASS | All the wording's there, listed below. One odd case: see Looks wrong |
| GC8 | PASS | "BEATS" fits under the number on the small iPhone and the folded Duo, and reads as a length, not a page. `MEM` shows arrows with no number up to 8 cues, and `1/2` at 9 |
| GC9 | PASS | They swap in place, with about one frame of blend. A held `SLICE` pad shows `EXIT` while held and `RELOOP` as it lets go, with nothing crossing |
| GC10 | BLOCKED | No Vocal ride came up this round, in about 17 moves of mine and 8 of the first-time user's. See below for last round's timing |
| GC11 | PASS | The marks still look right beside the new names, and sit clear of `ROLL` and `FX` |
| A1 | PASS | Worked all four ways: paused and playing, plain tap and 0.2 s press. The cue came back and the capsule went each time |
| A3 | PASS | 3.9, 4.1, 9.2, 14.2 and 17.6%. See the table |
| B1 | PASS | On the folded Duo: 4 opens and closes, 472 frames, no lit meter pixels at all. The same count with music playing read 3,594 |
| C1 | PASS | Measured on the folded Duo at full resolution: both caps' index lines are centred on their centre ticks to the pixel |
| C2 | PASS | 2 pt stays at the centre and 3 pt leaves. Coming back to within 1.5 pt catches it |
| C3 | PASS | The small iPhone's keyboard leaves the search field in view. The mixer's offstage here, so it can't spill |
| C5 | PASS | Plain taps on the folded Duo: `PLAY`, `CUE`, and the bottom pads down to 22 pt from the screen's edge. All first time, with no system gesture. The small iPhone took the same presses all through the long run |
| C6 | PASS | `BROWSE` at 4 pt, the gear at 5 pt and `REC` at 6 pt from the top, plain taps, first time |
| D2 | PASS | Measured from video: `A`, `B`, `E`, `F` and `H` each flare and settle in about 0.3 s. A held slicer pad is clearly brighter than the rest |
| D3 | PASS | A quick tap stays lit for the sound's 2.5 s |
| D4 | PASS | `IN` lights, with an orange line at the playhead on the waveform and the overview, before `OUT` |
| D11 | PASS | Dragging along `DEPTH` on the small iPhone moves it |
| G1 | PASS | `SET`, `Q`, `VOLUME` and `STOP`, and pads that fire |
| G2 | PASS | The sheet has no grab buttons with no loop set |
| G3 | PASS | Gate is lit only while held. Loop starts on one tap and stops on the next |
| G4 | PASS | `Grab Deck 1's Loop` names the pad `LOOP 1`, and it goes round |
| G5 | PASS | A red timer replaces `SET`. The pad then holds it, and the meters move when it plays |
| G6 | PASS | `Restore the Original Sound` puts the pad's own name and sound back |
| G7 | PASS | `VOLUME` at the bottom leaves the meters empty, and `STOP` stops a looping pad |
| H1 | PASS | `ECHO`, `FLANGER` and `TRANS` stay lit, and `CRUSH` takes `ECHO` out |
| H2 | PASS | `DEPTH` follows the pad being slid: `CRUSH` went to 15% and `TRANS` to 85%, and each kept its own |
| H3 | PASS | "Echo out on deck 1. Press OUT again to bring it back." The meters empty within a few frames, and the track comes back further along |
| H4 | PASS | Stopped: "Echo out needs the deck playing." Pausing during an echo out and playing again comes back with sound |
| I1 | PASS | `DUB`, `SPACE`, `NOISE`, `CRUSH`, `PITCH`, `FILTER`, lit blue, and the label under both bottom knobs follows |
| I2 | PASS | All five turned 100 to 140° each way, playing, on the folded Duo. Nothing went silent, nothing went red and there was no crash. Double-tap is blocked, as two tool taps are too slow |
| I3 | PASS | With `DUB` turned and back at the centre, the meters ran on for about 2 s after the pause |
| Long run | PASS | 15:09, with the takeovers listed below. It found `N23` |

### GB1: a seek past a mix's exit

| | Round 16 | Now |
|---|---|---|
| Seek past the exit, with 2 minutes left | "No clean way in", 0.3 s later | It reads `MIX…` for 7.8 s, then `MIX 9`, then "Echo throw into Fast Bird." about 25 s after the seek. "No clean way in" isn't said |
| How long `MIX…` stayed | 2:13 | 7.8 s |
| Seek to 8.5 s from the end | | "No clean way in. Next track starts when this one ends." 0.6 s later, with the key on `MIX`, not `MIX…` |
| Next track starts | At the file's end | 5 s after the seek: "No clean way in. Deck 2 just started." |
| Seek back from near the end | | `MIX 40` within a second |

**The gap, measured two ways, as you asked about the 0.33 s:**

| | Round 16 | Now |
|---|---|---|
| Stretches of 10 ms under -50 dB by RMS, which is what I gave you last time | 4.13 s and 4.10 s | **1.61 s** (282.08 to 283.69 in `Mix 23.30.28`) |
| From the last sample over -50 dB to the next track | Not measured | **About 0.2 s** (283.4 to 283.6) |

**I think that accounts for your 0.33 s, and it's my measuring.** RMS goes under -50 dB before the peaks do: Skylander's file falls under by RMS at 355.15, and its last sample over the same level is at 356.51, 1.36 s later. So last round's "the file's last 3.77 s" went by peaks and "4.13 s" by RMS, and the two were never comparable. By RMS on both, last round's next track came about 1 s before the file's end, so it wasn't waiting for the very end either. Now 1.61 = 1.36 + 0.25, so it starts about 0.25 s after the last sound, inside your 0.5 s. What's left in that 1.61 s is the track's own fade, from -18 dB down, with no stop in it.

### GC1: does it feel right, or is it just slow?

I can't judge it with a finger, so this is from a tool's presses and the code:
- **The wait never got in my way.** I made about 12 seeks on playing decks in the long run, each a 0.32 s press. The jump comes as the 0.25 s runs out, under the finger. The message says exactly what to do.
- **A stray touch that slides still jumps.** Quick slides of 0.08 s on a playing deck: 3 pt and 6 pt only gave the message, and 10 pt went from 1:15 to 4:33. That's `slideToJump`, at 8 pt. So a touch that lands and drags a little, such as a finger heading for the top bar, can still move a live track. It wants a real finger on the phone, as a thumb brushing past is the case that hurt.

### GC7: the words, as they appeared

| Where | What it said |
|---|---|
| `AUTO`, not on `STEMS` | "Brake drop starting. Put both decks on STEMS to watch it. A control you touch is yours." Also on a Bass swap |
| `AUTO`, both on `STEMS` | "Bass swap starting. A control you touch is yours." Also on a Loop build |
| Thumbs | "More loop builds?", "More echo throws?", "More bass swaps?", "More brake drops?" |
| `MIX` with `IN KEY` or a search on | "Mixing through this list, 1 track to go. Up next: Exhilarate." |
| A sync of more than 12% | "Deck 2's 25% slower than its own 170 BPM, to follow." and "Deck 1's 33% faster than its own 128 BPM, to follow." Nothing at 1.6% |
| First load | "New to this? Press ? and tap anything to see what it does. The gear has the whole guide." |
| `IMPORT`, `Music files…` | "Opening Files…" until the picker came, about 1.5 s |
| History | "Remove from History" on a row, and "Delete History" on the list |
| Upright list menu | "All Tracks" |
| Backups | `Before restore 2026-11-05T083341.json` |
| Stopping a recording | "Stop and save" is white, not red |

### GC10: last round's Vocal ride, looked at again

No Vocal ride came up, so I can't say which track it was this time, but last round's log disagrees with "17 s after the landing":
- "Vocal ride starting" was on screen from 21:27:17. The dip is 766 s into a recording started at 21:14:42, so about 21:27:28. "Vocal ride done" came at 21:27:43.
- So the dip's about 11 s after the start message and 15 s before the end, and it isn't at the ride's end.
- The level's about -28 dB for the 1.5 s before it and -11 dB right after. A jump of 17 dB straight after a dip does look like something landing, and it's not a steady stretch of one track's instruments.

That recording's still in my scratchpad if you want it, and it isn't conclusive. Neither Houston nor Gepzene has that same shape where I looked.

## The long run

Small iPhone on its side, `DUB` chosen on both, recording from 23:56:17 to 00:11:26: **15:09**. Mean -14.3 dB, peak 0.0 dB. No crash report.

| Time | On the recording | What | What it said |
|---|---|---|---|
| 23:56:20 | 0:03 | `MIX` with Severe playing | "Mixing through all your tracks, 5 tracks to go. Up next: Houston." |
| 23:56:50 | 0:33 | Seek toward the exit | `MIX 79` to `MIX 8` |
| 23:57:05 | 0:48 | Loop build into Houston | "Loop build into Houston." |
| 23:57:29 | 1:12 | **`MIX` pressed in the build's last bars** | "Mix off. The decks are yours. Deck 1 is still looping. ALL brings back deck 1's stems." (`long-auto-in-last-bars.png`) Houston went back to 0:00, cued |
| 23:57:35 | 1:18 | `EXIT` and `ALL` by me | Severe back at full |
| 23:57:53 | 1:36 | `MIX` again | Same, 5 to go |
| 23:58:10 | 1:53 | Seek | `MIX 107` to `MIX 9` |
| 23:58:24 to 23:58:44 | 2:07 | Echo throw into Houston | "More echo throws?" |
| 23:58:53 | 2:36 | **Gepzene loaded on the waiting deck,** over Exhilarate | "Up next: Gepzene - Can't be Serious. The mix carries on." It went on to `MIX 90` |
| 23:59:06 | 2:49 | Seek | `MIX 90` to `MIX 11` |
| 23:59:27 | 3:10 | Loop build into Gepzene | |
| 23:59:50 | 3:33 | **`EXIT` in the build's last bars** | "Mix off: deck 2's loop was changed. The decks are yours. ALL brings back deck 2's stems." (`long-exit-in-last-bars.png`) Gepzene went back to 0:00, at its own 128 |
| 00:00:22 to 00:01:10 | 4:05 | `AUTO`, with both decks on `STEMS` | "Loop build next, with deck 1 cued at 126 BPM…", then "Loop build starting. A control you touch is yours." |
| 00:01:20 | 5:03 | **Press sent during `BROWSE`'s slide:** row 6's `2` | Skylander loaded on deck 2, the right row |
| 00:01:32 | 5:15 | `MIX`, then `BROWSE` and the `CUE` tab during the slide | "3 tracks to go." The tab changed |
| 00:01:53 | 5:36 | **Seek past the exit** | `MIX 62` to `MIX 9`, then an Echo throw into Skylander at 00:02:09 |
| 00:02:14 | 5:57 | The new deck's `DUB` turned up and back during the move | It stayed mine, and went back to the centre |
| 00:02:39 | 6:22 | **Houston loaded on the waiting deck,** over Fast Bird | "Up next: Houston. The mix carries on." with "3 tracks to go", which was true |
| 00:03:01 | 6:44 | Seek | `MIX 82` to `MIX 8`, then a Loop build, done at 00:04:01 |
| 00:04:10 | 7:53 | `MIX` off | "Mix off. The track playing just carries on." |
| 00:04:22 | 8:05 | `AUTO`, then `PLAY` on the new deck at `AUTO 4` | "Auto DJ stopped: you started deck 2 yourself. Deck 1 carries on." Skylander played at its own 125 (`long-play-on-new-deck.png`) |
| 00:05:03 to 00:05:46 | 8:46 | **`AUTO`: a Bass swap** | "Bass swap starting. Put both decks on STEMS to watch it…", then "More bass swaps?" and a thumb down: "Got it. Less like that." (`long-bass-swap-done.png`) |
| 00:06:00 | 9:43 | `MIX` | "2 tracks to go. Up next: Exhilarate." |
| 00:06:18 | 10:01 | **Seek past the exit** | `MIX 75` to `MIX 4`, then an Echo throw into Exhilarate at 00:06:27 |
| 00:06:31 | 10:14 | The old deck stopped during the move | The new one came straight in, with `MIX` still lit (`long-old-deck-stopped.png`) |
| 00:07:07 to 00:07:35 | 10:50 | Loop build into Fast Bird, with the old deck's fader taken | It stayed where I put it |
| 00:07:54 | 11:37 | Severe loaded on the waiting deck, on the last track | **Nothing said.** See `N23` |
| 00:08:44 | 12:27 | `RELOOP` on that deck, for `GC9` | It started playing, with `MIX` still lit and nothing said |
| 00:11:00 | 14:43 | The last track ended | "That's the end of all your tracks." at `00:00.0` (`long-end-of-tracks.png`) |

After each hand-back, both decks worked again at once, with nothing left silent, looping or filtered that the screen didn't show.

**Every stretch under -50 dB on the recording, 0.15 s or longer:**

| On the recording | How long | What it is |
|---|---|---|
| 167 to 179 | Seven of 0.17 to 0.23 s | Houston's own, at 3:02 to 3:14, where I'd seeked it |
| 287 to 306 | Six of 0.24 to 0.35 s, 3.8 s apart | Gepzene's own, at 0:15 to 0:30 |
| 552.64 to 553.07 | 0.43 s | The Bass swap's breath |
| 607.11 to 607.34 | 0.23 s | Houston's own, at 4:22 |
| 826.42 to 827.33 | 0.91 s | Fast Bird's own, at 2:35 |

No holes, and none of my seeks past an exit left one.

## Timings and measurements

CPU on the small iPhone, each 30 s after 10 s of settling, on the pinned process, with my logger off:

| State | This round | Last round |
|---|---|---|
| Idle, nothing loaded | 3.9% | 3.7% |
| Two tracks loaded, paused | 4.1% | 4.2% |
| One deck playing | 9.2% | 9.4% |
| Both playing and synced, with a tempo offset | 14.2% with one stretched, 16.9% with both | 16.1% |
| Both of those, plus a stem off and an echo | 17.6% | 16.6% |

Beside it: another project's archive, the first-time user hadn't started, and Mac idle was 46 to 69%, with XProtect scans and `pairedsyncd` taking a core between them.

Memory with two tracks loaded: about 430 MB.

## First impressions

**1. Does it look like $1000 pro software?** On the small iPhone on its side, with both decks running, it comes close. The waveforms, the meters and the pads look like a real instrument. Three things break it most:
- **Messages over the waveform.** Every capsule sits on deck 1's section label for its whole life. It's the one thing I'd see in any screenshot of a good moment.
- **The sheets.** Hardware gives way to stock iOS and a lot of black. The Mixer sheet on the folded Duo is two rows of controls and a screen of nothing, and on its side the sampler's has to scroll for the sake of 39 pt.
- **The tab row's last word.** `SMPL ›`, `SLICE ›` and `MORE ›` stop the row changing size, which is right, but the tab that takes turns reads as an abbreviation of something you haven't been told about.

**2. What felt slow, confusing or surprising?**
- **Nothing felt slow in the app itself.** The 0.25 s on the overview comes under the finger.
- **One button with two kinds of number.** `MIX 14` is bars, `MIX 14%` is stems. It took the first-time user 14 minutes, and I'd have to have read it to know.
- **`AUTO` picks the move, and you find out as it counts down.** There's no way to ask for a different one, short of calling it off and trying again. The thumbs teach it for later, and nothing shows what they've taught it.
- **A stray track on the waiting deck at the end of a mix (`N23`).** I expected it to play, and I think anyone would.

**3. Which control was hardest to find or hit?** On the small iPhone on its side, the row of keys above the pads. `BEAT` and `ALL` have gaps wide enough that two of my presses landed between them, with no response and no word, and I took it for a fault until I looked. Hardest to find is still the tempo fader, behind `JOG`, which is the first-time user's point as well.

## The first-time user

On the small iPhone on its side, from 00:18:41 to 01:04:40, 45:59 from opening. Clean install, with no `Cheeks` backups in its Files. No crash, and the process ran throughout.

**What I asked them about afterwards, in their words as near as I can:**

1. **What Auto DJ does.** "At 00:29:22, at the end of the first Loop build: it picks a named move, holds the outgoing track in a short loop, runs the new track with all its stems shut off, turns the outgoing deck's low and filter knobs itself, then leaves the new deck on." That's **+10:41**. "Mostly luck": `MIX` ran that move while deck 1 happened to be on `STEMS`. They hadn't yet seen the stems come back in. A newcomer would be later: their guide search for echo throw came at +11:24, and they already had a rough idea of the term.
2. **"Put both decks on STEMS to watch it."** They did it for two of eight moves, and saw nothing useful at the rate they get frames, and "`A control you touch is yours`" was the part that stuck. Some of the moves never asked, being `MIX`'s. **The marks above `STEMS` told them nothing on another page.** They noted them once after muting a stem by hand, and never worked out what lit or dim means.
3. **The overview.** "The message covered it. It didn't read as broken at all, and it was one of the best moments: it refused the jump and taught me the gesture in the same breath." The hold seemed right, as a stray tap mid-mix would be nasty. They can't feel the wait.
4. **Nothing, with no word.** A track row in the browser, a track row in `?`, empty `MEM` pads, a deck's name or time, dragging a row to a playlist, and the green `AI` marker, which may not be a button.
5. **The one thing they'd change.** The tip in `N25`.

**How they use `?`:** "The best thing in the app". It told them what each thing does, not what order to use them in. Their bubble covered what it described more than once. Wording they found wrong or no help:
- `CUE` says "with the cue in your right ear" and `CUE/MST` says "left for the decks you've cued, right for the mix": I think one's your ear and the other's the knob's direction, and side by side they read as a contradiction.
- "Gate" is mentioned and not explained.
- The key codes are explained nowhere you can search: "5A" gets No Results (`fu-37`), and they're in bright colour on every row.
- `Halve BPM` and `Double BPM` sound like speed controls.
- `BACKSPIN` and `BRAKE` look like the other effect pads, and only they end a mix.

**Best thing:** `?`, and the app's habit of speaking in plain sentences. The line they'd show someone: "Loop build done. Deck 2 is on. The crossfader's still turned away from it. More loop builds?"

**Worst thing:** the crossfader "works", so nothing tells you there's more. Tempo's behind `JOG`. And after a sync, the track that's left quietly stays at the other's speed: Houston at 148 (its own 126), Exhilarate at 125 (its own 170).

**Their brief was not kept in full, and they said so:** they ran one read-only `launchctl list` on that simulator three times, to check for a restart. They also pressed Home once. Neither affects anything here.

**Their report follows unchanged,** with its corrections to itself, and mine are above.

---

# Segue DJ - first-time user report (fu17)

Opened 00:18:41. Stopped 01:04:40 (the 45 minutes ran out at 01:03:41, and I finished the guide search I was in). At 01:05:10 I turned MIX off and stopped the deck so it wasn't left playing. The app never crashed: same process, 63677, at launch, 00:42:08, 00:46:15 and 01:01:52.

"Worked" below only means what I saw. I can't hear or feel anything, so where I say "fade", "cut" or "echo" I mean the app's own word or what the meters and knobs did.

How to read the times: the first-minute numbers flatter the app, because I know DJ software far better than "roughly" (section 6). Sliding the crossfader at 1:07 was not a mix. A real newcomer would be slower.

## 1. Every moment I wasn't sure

1. 00:19:15. Which track was which. Files called three of them jam1072904 and so on. About 10 seconds later the app had renamed them (Houston, Skylander), so I couldn't match file to title. I just read the new names. A few seconds. fu-02 (before the names changed).
2. 00:19:20. Getting a track on a deck. I guessed the "1" on the row. For about a second nothing looked different, then it went blue and MASTER 1 148.00 appeared. About 2 seconds. Tapping a row itself does nothing, no highlight or message (found at 00:46:45). No screenshot of the moment.
3. 00:19:22. Why the 5A pill on Houston turned solid pink. I guessed "same key as the deck", and deck 1 did hold a 5A track. Never saw it said outright, so still a guess. No screenshot.
4. 00:19:26. The Decks page as a whole. I wanted sound and went for the big Play. 5 seconds. The rest meant little until ? at 00:20:02. fu-03.
5. 00:19:42. SYNC's toast, "Deck 2's 17% faster than its own 126 BPM, to follow." I had to read it twice. No screenshot.
6. 00:19:48. Whether the crossfade had done anything. The handle moved, all the meter columns stayed lit, and nothing on deck 1 showed it was out of the mix. I took it on trust and never got a visual answer. fu-05.
7. 00:20:02 to 00:21:20. What everything is. I pressed ? and tapped about 22 controls. 80 seconds, and it worked well. It told me what each one does, not what order to use them in. fu-06.
8. 00:21:50. AUTO with both decks playing. I wanted a mix. It said "Auto DJ brings in a stopped deck. Stop the one you want next." I stopped deck 1 and pressed again. 7 seconds. No screenshot.
9. 00:21:57 to 00:23:41. What AUTO 55% was. The toast said it was waiting for the stems. I waited 1 minute 44 seconds, the stems reached 99%, and I got "The stems didn't get there in time. Deck 1 just started." So my first AUTO wasn't a transition: no knob moved, the crossfader just jumped to the middle. fu-07, fu-09, fu-11.
10. 00:22:37. History Nov 5 said 2 but showed 1 row. NEXT was still lit from the other list and was hiding a track. For a moment I thought it had lost one. About 15 seconds. No screenshot.
11. 00:22:50. Stopping a preview. I guessed the square on the tile. It worked, then "This preview's over the mix, as SPLIT's off. It won't be on a recording." arrived after I'd stopped, and rode over to the Decks page. fu-08 is just before this.
12. 00:23:15. Waveforms changing colour. I thought it meant stems had finished. It really means that deck is on the STEMS tab. I believed the wrong thing for about 4 minutes. fu-09 (orange), fu-10 (stem colours).
13. 00:26:05. "Echo throw starting." I wrote that I didn't know what that was, and the guide search answered it at 00:30:05. That's what I'd expect of a newcomer, but I do have a general idea of the term myself (section 6). fu-13, fu-14.
14. 00:26:10. The "· 1" on the REC pill. I wanted to know what it counted, and guessed tracks. The guide confirmed it at 00:52:12, 26 minutes later. fu-13 (no dot yet), fu-15 (· 2).
15. 00:26:36. Thumbs-up did nothing. The toast had already left when my tap arrived: seen at 00:26:23, gone by 00:26:36. So it lasts under 13 seconds, and I'd taken for a dead button a thing that had simply timed out. Settled at 00:44:00 and 00:59:20 when the thumbs answered. fu-15.
16. 00:26:50 to 00:40:49. The number on the MIX button. It says "MIX 8%" and also "MIX 14". The first is stems, the second is bars left, and only a % sign tells them apart. I worked it out from the clock 14 minutes later (94 to 87 in 13.4 seconds at 125 BPM). fu-16, fu-17.
17. 00:27:15. MORE. I tapped it to see more, it became MEM, and only further taps showed it cycles MEM, SLICE, JUMP, SMPL. About 20 seconds. Nothing says how many there are. No screenshot.
18. 00:27:45 to 00:28:10. Putting my own sound on a pad. SET then a pad opened "Pad 1". I scrolled, it bounced, and my tap hit Choose a File instead of Record the Master. I cancelled and tried again. Record the Master replaced AIR HORN at once and SET became a red stop timer. About 25 seconds. fu-17.
19. 00:28:37 to 00:35:05. Getting AIR HORN back. I tapped Restore the Original Sound, the sheet moved under my finger, and I think I hit Record the Master again. Pad stayed REC 1. I gave up for 6 and a half minutes. Waiting for the sheet to settle worked first time. fu-18 and fu-19 show REC 1 still there.
20. 00:30:45. Where tempo lives. It's behind JOG. Correction: I'd already seen that page at about 00:20:45 in ? mode, so this was my first use of it, not my first sight. I wouldn't have looked under a word meaning the platter. fu-22.
21. 00:30:50. Moving the fader down made the tempo go up, 170 to 175.27. The help had warned me. A surprise otherwise.
22. 00:30:58. What dragging the platter does on a playing deck. I went round it. The clock kept counting and nothing visibly changed. On a stopped deck it does move (01:12.4 to 01:13.0 at 00:50:38). Still unanswered for a playing deck.
23. 00:30:59. BEAT SYNC on the deck that was master, with the other deck stopped. It dropped to 125 to follow the stopped deck, stayed labelled master, and BEAT SYNC didn't light. ±10 went to WIDE by itself. 26% slower with one tap. I didn't expect a master to follow anything. fu-22.
24. 00:31:30. "No clean way in. Next track starts when this one ends." Plain, and I understood it. I don't know whether my tempo change at 00:30:59 caused it. fu-23 (toast already fading).
25. 00:32:05. SPLIT. I wanted to know what it would do to my one output. I pressed it, it lit, and nothing was said. The guide answered at 00:52:15. fu-24 is just before.
26. 00:32:50. Finding recordings. The bars icon says nothing, but ? had named it earlier. A few seconds. fu-25.
27. 00:29:40 to 00:34:40. Whether the crossfader alone was "mixing". The guide's MIX TWO TRACKS was the first thing to mention swapping the LOW knobs. Doing its recipe took 28 seconds. Nothing on the deck page suggests it. fu-20, fu-26, fu-27.
28. 00:35:40. Empty MEM pads. Completely blank, and a tap does nothing. SAVE CUE above them is the clue. Under 10 seconds. No screenshot.
29. 00:36:20. Adding to a playlist. I tried to drag a row to it. No drag, only the press-and-hold menu, as the empty playlist had in fact told me. About 20 seconds. No screenshot.
30. 00:36:40 to 00:55:05. Setting the order for MIX. I looked for a way to reorder a playlist and found none. MIX turned out to follow the sort: sorted by BPM it went 148, 128, 126, 125. Nothing tells you that. 18 minutes. No screenshot.
31. 00:37:20. KEY SYNC. It showed -1 and a tiny 10A on a track the list calls 5A, with no message. It's correct if you know the system, but the app doesn't explain the system, and that label is about 4 points high. fu-28.
32. 00:38:57. A stopped deck jumped 7 seconds. REV ran back to 00:00.0 and stopped, and when I turned REV off the clock leapt to 00:07.2, still stopped. I'd left SLIP on. ? on SLIP explained it 30 seconds later. fu-30.
33. 00:40:20. MIX with both decks playing. "A mix carries on from one playing deck. Stop the other." Clear, but it means a trip to Decks and back, as Browse has no stop. About 20 seconds. No screenshot.
34. 00:41:40. One tap on BACKSPIN during a MIX. Within about 4 seconds deck 1 had stopped, MIX was gone, deck 2 had snapped back to its saved cue at its own tempo, and the meters were dead. I missed the toast and thought something had gone wrong. I repeated it at 00:42:45 and read "Mix off: deck 1 was stopped." About 1 minute. fu-32.
35. 00:44:00. "Got it. Less like that." Less of what: loop builds, this pair, for ever? Nothing shows what I've taught it. Unanswered. fu-34 (toast already gone).
36. 00:45:10. Whether Halve BPM changes the speed. The readout said 63 and the clock kept its pace, so it corrects the reading. 10 seconds, by watching the clock. No screenshot.
37. 00:48:36. Play on a deck that had run out. It jumped to my saved cue at 1:03 instead of the start. I'd forgotten saving it. No screenshot.
38. 00:49:00 to 00:49:35. Lining up beats by hand. I got the tempo to 125.00 and then couldn't read the beat blocks, even after one go at their help. A second read, with the deck running, got it, though the bubble covers half of what it describes. fu-36.
39. 00:49:47. Nudging a playing deck. I tried the platter's edge and took the tempo fader instead: 125 to 141.77 in one drag. BEAT SYNC fixed it in one tap. I never found a nudge I could confirm. No screenshot.
40. 00:51:40. The grey ticks by the titles. They'd been there half an hour before I asked. "Everything else here has been played" gave it away. ? on a tick gives only the general bubble. No ticks in fu-02.
41. 00:54:03. Delete on a recording. "Delete this recording and its tracklist?" with a red Delete and no Cancel. Tapping outside cancels, which I had to guess. The track delete does have a Cancel. No screenshot.

### What the help did and didn't do

- ? mode (first used 1:21 in): the best thing in the app. The music keeps running and you tap anything. It didn't give me order or priorities, its bubble often covers what it describes, and first-time tips slide underneath it.
- The guide, gear then What everything does (first used 11 minutes in): clear, and its search answered echo throw, SPLIT, headphones, the · number and the borrowed filter. It didn't explain gates or the key codes, and "key" as a search leads with the ? entry.
- The toasts: they say what just happened and what to do next. Their weakness is timing. They last under 13 seconds, you can miss them while looking elsewhere, and they cover deck 1's section label.

## 2. How long each stage took

| Stage | Clock | From opening |
|---|---|---|
| Files picker on screen | 00:19:00 | 0:19 |
| Getting music in: five tracks in the list | 00:19:08 | 0:27 |
| Analysis done: BPM, key, real names | about 00:19:20 | 0:39 |
| First track on a deck | about 00:19:22 | 0:41 |
| First sound (clock counting, meters moving) | 00:19:31 | 0:50 |
| Two tracks playing together | 00:19:38 | 0:57 |
| Tempos matched with SYNC | 00:19:42 | 1:01 |
| First move from one to the other (crossfader only) | 00:19:48 | 1:07 |
| First press of ? | about 00:20:02 | 1:21 |
| First press of AUTO | about 00:21:50 | 3:09 |
| First stem muted | about 00:23:20 | 4:39 |
| First AUTO finished: no move, stems were late | 00:23:41 | 5:00 |
| First recording started | 00:25:56 | 7:15 |
| First full automatic move ("Echo throw done") | 00:26:23 | 7:42 |
| First MIX through a list | about 00:26:50 | 8:09 |
| First opened the full guide | about 00:29:40 | 10:59 |
| First used the tempo fader | about 00:30:50 | 12:09 |
| First recording saved, tracklist read | 00:32:56 | 14:15 |
| First mix by hand with the LOW swap, following the guide | about 00:34:40 | 15:59 |
| Own playlist with tracks in it | about 00:36:29 | 17:48 |
| Tempo matched by hand to 125.00 | about 00:49:00 | 30:19 |
| Understood that MIX follows the sort | 00:55:05 | 36:24 |

Each tool call is slow, so these include waiting on the test rig.

## 3. What I still can't explain, and wording

Still can't explain:

- What the platter does on a playing deck, and how to nudge one.
- What the thumbs change.
- Whether a deck should stay at the other's tempo. Houston stayed at 148 (its own is 126), Exhilarate at 125 (own 170), Gepzene at 125 (own 128). It's said only at the moment of sync, not afterwards. The number on the deck is the only clue.
- Whether a saved recording keeps playing after you close its sheet (00:45:56). Nothing outside the sheet shows it.
- Whether History counts loads or plays. It reached 15 entries for 5 tracks.
- Whether IN KEY uses a track's own key or its shifted one.
- Whether the tracklist's heading follows a rename. I meant to check at 00:33:10 and didn't get a clean look.
- Whether an automatic move from 128 to 170 BPM (00:28:41 to 00:29:22) came off. The readouts just stayed at 128 and 170.

Wrong, misleading or no help:

- CHORUS. The section name is wrong before the stems are ready. See section 4.
- JOG. Most of what a DJ reaches for by hand (tempo, sync, master, key, reverse) is behind a word meaning a wheel.
- MIX 8% and MIX 14: two meanings in one place.
- REC 0:39 · 2: the number has no label.
- CUE is two different controls, the big orange button and the unlabelled headphone key.
- The CUE help says "with the cue in your right ear". The CUE/MST help says "left for the decks you've cued, right for the mix". I think one means your ear and the other means which way you turn the knob, but side by side they read as a contradiction.
- Gate. "A pad becomes a one shot, a gate or a loop" is the only mention I could find. It doesn't say what a gate is.
- Key codes. "5A" gets No Results in the guide (fu-37), and nothing I searched explains them, though they're in bright colour on every row.
- Halve BPM and Double BPM sound like speed controls. They correct the reading. The menu heading, "Beat grid: 126.00 BPM at normal speed", doesn't help a newcomer.
- The preview warning about SPLIT is a good fact at the wrong moment, after you've stopped.
- BACKSPIN and BRAKE look like the other effect pads. Only they stop the deck, and only ? says so.
- A saved-cue toast reading "Memory cue saved" has a trash icon on it, beside UNDO. It looks wrong for good news.

## 4. Anything that looked broken

I saw no crash and no hang.

- 00:21:10. First-time tips appear under the ? bubble and are cut off ("SLICER pads play for as lo...", "FX pads slide: up and down for de..."). Seen live. fu-06 was saved later and doesn't show it.
- All session. Toasts cover deck 1's section label for their whole life. fu-13, fu-38.
- 00:20:30. Pressing JOG makes the waveforms hop up about 3 or 4 points. Compare fu-22 with fu-27.
- 00:22:56. Deck 2's status line truncated to "Stems 100...". Seen live. fu-09 was saved 16 seconds later and doesn't show it. While a track's stems are preparing its name also shrinks, to "Severe T..." (fu-07).
- 00:23:41. The stems were at 99% when AUTO gave up. Unlucky timing rather than a fault, but it was my first AUTO. fu-11.
- 00:24:51 and 00:26:00. The same spot on the same track changed name. Gepzene at 00:00.1 read CHORUS 1.1 with stems at 51% (fu-12), and at 00:00.2 read INTRO 1.1 with stems ready (fu-13). Houston near the start read CHORUS 8.2 at 00:14 (fu-05) and INTRO 4.4 at 00:07 later on (fu-30). So until stems finish, CHORUS seems to be a default. Exhilarate opens with a blank stretch of no waveform (fu-16) and still reads CHORUS with stems ready (fu-18).
- 00:27:55 and 00:28:37. The pad sheet moves about 40 points as it settles, so a quick tap lands on the wrong row. Twice in 3 minutes, once starting a recording I didn't want.
- 00:29:05. A small glass blob flashes as you press a menu, like a smudge. Seen live.
- 00:23:41 and 00:31:39. Probably fine, but a track stopped with time still on its clock (-00:02.3, fu-11, and -00:05.9, fu-23). The waveform has run out by then.
- 00:36:30. "Analysing Skylander again." outlives the job by a few seconds.
- 00:43:15. Deck 1's knob label went from DUB to FILTER by itself during a move while deck 2 stayed DUB. It looks like a bug, but the guide says "Auto DJ can borrow it for a filter". It happened again at 01:01:52. fu-33, fu-41.
- 00:44:20. A hand-made loop reads 7.7 on the deck and 7.8 beats in LIST.
- 00:44:50. The tab row shifts a few points when DEL appears, and MORE and DEL crowd each other (fu-12).
- 00:45:15. "Deck 1 follows at half tempo: 62 against 125." stayed up after I'd doubled the BPM back.
- 00:45:56. No sign anywhere outside the sheet that a recording is playing.
- 00:49:47. The tempo fader takes a drag from close by, wherever its knob is. A 13% jump in the middle of a mix, by accident.
- 00:55:47. The MIX button truncated to "MIX..." for a three-digit count (fu-39). MIX 115 fitted moments later, so it depends on the digits.

Things that look broken but I now think are correct: the stopped deck jumping with SLIP on (00:38:57, fu-30), and BACKSPIN ending a mix (00:41:40, fu-32). The partly filled DEPTH bars aren't a bug either: partly filled is how they start (fu-07), and my best guess is that a slide on an FX pad at 00:41:30 filled deck 1's.

## 5. Best and worst for a newcomer

Best: ? mode, with the app's habit of speaking in plain sentences when it stops you. The moment I'd show someone is "Loop build done. Deck 2 is on. The crossfader's still turned away from it. More loop builds?" (00:43:55). It noticed what I'd done and told me, without blocking me. Pressing AUTO again also put everything back as it was (00:47:15), which made me trust it.

Worst: the crossfader "works", so nothing tells you there's more to it. I had two tracks playing and crossfaded in 1:07 and could have thought that was it. The way to do it properly is behind gear, What everything does, MIX TWO TRACKS. Tempo is behind JOG. And after a sync the surviving track quietly stays at the wrong speed. Runners-up: BACKSPIN ending the whole mix with one tap, and the key codes being explained nowhere.

## 6. What I can't un-know

- Before opening the app, my session setup listed folders called cheeks-autodj and cheeks-stems, a project folder called Cheeks, and other agents called main and fu16, so I also knew I wasn't the first tester. I read none of those folders, but I knew to expect an auto DJ and stems. That may be why I pressed AUTO at 3:09.
- I know far more than "roughly what a DJ does". I know stems, hot cues, beat grids, quantise, slip, key lock and the numbered key wheel. So some confusion I noted is what I'd expect of a newcomer, not what I felt. That's true of echo throw (item 13), the key codes and -1 to 10A (item 31), and gate. The app does leave those unexplained, but I wasn't lost on them. I also went straight for CUE, the fader and SYNC.
- Words I've picked up from the app and now use as if they were natural: leading deck, echo throw, loop build, brake drop, memory cue, beat blocks, stem, AUTO, MIX. The app calls itself Segue DJ in its delete dialog, and I used that name only because the brief gave it to me.
- Outside the brief: I ran `simctl spawn "iPhone SE Cheeks" launchctl list` filtered for the app three times, to check for a restart. Read-only, that simulator only, and not one of the two things you said I'd need. I also pressed Home once at 00:46:03. The Home screen came up in portrait, which wasn't a rotation by me, and showed two "CheeksUITes..." icons, which I didn't touch. The app came back on its side.
- The test rig can't tap twice fast enough, so I couldn't test any double-tap reset, on a knob or on a waveform. I tried on a knob at 00:25:30 and 00:34:45, and it didn't reset, but that says nothing about the app.

Screenshots saved a little after the moment they're named for: fu-06 (no cut-off tip), fu-09 (no "Stems 100..."), fu-15, fu-16 and fu-34 (toast gone), fu-23 (toast fading), fu-40 (after OUT came back). The running notes below quote those moments from what I saw live.

What I changed and left behind: waveform colours on RGB, SPLIT on, filter key on DUB, SIREN pad on Loop, D off on deck 2's FX, hot cue A on Severe Tire at 3:11, hot cue B on Houston at 2:36, memory cue "Drop" on Gepzene at 1:03, two recordings ("First go" and "Mix 2026-11-05 00.53.09"), playlist "Friday warmup" with two tracks, All Tracks sorted by BPM, one thumbs-up for echo throws and one thumbs-down for loop builds. The app is still running with Skylander and Houston loaded, both stopped, MIX off, not recording. fu-42.

## Corrections to the running notes below

The notes are kept as written, mistakes included, so you can see what I believed at the time. These are wrong:

- 00:22:56: fu-09 doesn't show "Stems 100...".
- 00:23:41 "this was a cut": I can't hear. I only saw that no knob moved.
- 00:26:36: the thumbs-up tap came after the toast had gone. Not a fault.
- 00:28:55: the BPM menu opens with a plain tap, not a long press.
- 00:30:45 "12 minutes before opening this": I'd seen the JOG page at about 00:20:45 in ? mode.
- 00:37:20 "looks like nonsense": correct behaviour, and I could do the sum myself. See section 6.
- 00:41:40 "there may have been a toast": there was.
- 00:56:30 and 00:57:15 on DEPTH: see the end of section 4.
- 00:31:45: Skylander started at about 00:31:39, going by fu-23.

## Running notes (written as I go)
- 00:18:49 First screen is a library with "No music yet" and a blue IMPORT. Clear. The text is long for one screen but tells me where to go. (fu-01-first-open.png)
- 00:18:55 IMPORT -> tiny menu Music files / DJ library (XML). I took Music files. "Opening Files..." toast, then a black screen for about 2 seconds, then the Files picker.
- 00:19:08 Picker opened straight on "My Music" with my 5 files. Multi-select was on by default. Tracks in the list at 00:19:08 = 27s. Files shows album art for three files; the app shows coloured letters and "Unknown artist" for all five. (fu-02-imported-analysing.png)
- 00:19:15-20 Analysis finished in about 10 seconds. Titles changed from file names to real names ("jam1280420" became "Houston"). Good surprise, but the list order stayed by import order, and I couldn't tell which file was which any more.
- 00:19:20 Tapped "1" on the first row - nothing looked different for a second, then button went blue and MASTER 1 148.00 appeared. A toast: "New to this? Press ? and tap anything to see what it does. The gear has the whole guide." Good hint, right moment. It covers COLLECTION and the header row.
- 00:19:20 The "5A" pill on Houston lit up solid pink when deck 1 had the other 5A loaded. Nothing says why. I guessed "same key". Also the filter buttons IN KEY / +-6% BPM woke up.
- 00:19:26 DECKS: dense screen. Two waveforms, two 8-pad grids, mixer. I've got no idea yet what a lot of this is, but Play is obvious and big. (fu-03-decks-first-look.png)
- 00:19:31 First sound (play deck 1, meters moved, time counted) = 50s from opening.
- 00:19:38 Both playing = 57s. (fu-04-both-playing.png)
- 00:19:42 SYNC on deck 2: BPM 126 -> 148. Toast: "Deck 2's 17% faster than its own 126 BPM, to follow." Odd sentence, I understood it on second read. Toast covers the top waveform's section label.
- 00:19:48 Crossfader to 2 = 67s. Meters stayed all lit. Nothing on the waveform changed to show that deck 1 is now out. (fu-05-crossfaded-to-2.png)
- 00:20-00:21 Help ("?") mode: very good. Tap a control and a bubble names it and tells me what it does. Music keeps running. Taps on tabs and JOG still change page while help is on, as promised. Learned: AUTO, MIXER, METERS, BEAT BLOCKS, JOG/PADS, BEAT SYNC, MASTER, Q, KEY, KEY SYNC, JOG WHEEL, CUE, HOT CUE, DEL, STEMS, ACAPELLA/VOX, STEM STATUS, MEM, SLICER, JUMP, SMPL, FX.
- 00:21:10 In help mode the first-time tips ("SLICER pads play for as lo...", "FX pads slide: up and down for de...") appear UNDER the help bubble and are cut off. Then one covers the deck 1 section label. (fu-06-toast-under-help.png is a little later, but see the screens at that time.)
- 00:20:30 Pressing JOG makes the waveforms jump up about 3-4 points. Tiny layout hop.
- 00:21:50 Pressed AUTO with both decks playing: "Auto DJ brings in a stopped deck. Stop the one you want next." Clear; it told me exactly what to do. Stopped deck 1.
- 00:21:57 AUTO again: button shows "AUTO 55%", toast "Auto DJ is waiting for the stems. If this track finishes first, deck 1 starts." Clear. (fu-07-auto-pressed.png). Deck 2's SYNC turned itself off and it stayed at 148 (its own tempo is 126), so Houston keeps running 17% fast, now as the master. Nothing said so.
- 00:22:20 In Browse, IN KEY/NEXT worked. A greyed "2" while deck 2 plays: tapped anyway, told "Deck 2 is playing. Stop it first." Good. "?" works in Browse too; KEY and NEXT and MIX explanations are clear. A plain track row gives no help in ? mode (tapped row, bubble stayed on MIX).
- 00:22:37 A playlist "History Nov 5" appeared by itself. Sidebar says 2 but with NEXT lit it showed only 1 row (NEXT hides the leading deck's track). NEXT stays on when you change list. Count and rows didn't match, and for a second I thought the history had lost a track.
- 00:22:45 Long press row: Load on Deck 1/2, Preview, Remove from History, Re-analyse, Delete from Library (fu-08-history-long-press.png). No "add to playlist" because I have none; nothing tells me it would appear.
- 00:22:50 Preview: tile shows a stop square. Tapping the tile stops it - I guessed right. Toast "This preview's over the mix, as SPLIT's off. It won't be on a recording." came up after I had already stopped it, and rode along onto the Decks page. A bit alarming: I don't want a preview over the mix, and the warning arrived too late to help.
- 00:22:56 Deck 2's stems label truncated: "Stems 100..." (what's the rest?). (see fu-09)
- 00:23:15 Deck 2's stems finished: waveform turned from orange to pink/blue/yellow without a word, and a green "AI" dot appeared on the stems page. Pretty. Took me a moment to realise it had happened because of stems.
- 00:23:20 Muted VOCAL: pad dimmed, pink gone from waveform, mix meters dropped, little coloured dots above the STEMS tab. SOLO D: only yellow left, INST/BASS dim. Press SOLO again: back to the previous mutes. Best feedback in the app, can see what I can't hear. (fu-10-stems-solo-drums.png)
- 00:23:41 AUTO path "stems late": toast "The stems didn't get there in time. Deck 1 just started." Stems had been at 99%. Deck 2 stopped with -00:02.3 left, AUTO button went off, crossfader jumped by itself from far right to the centre. No fade happened, this was a cut. Nothing bad, but the first time I used AUTO, it wasn't a mix. (fu-11-auto-stems-late.png)
- 00:24:20 ? on waveform, overview, BPM: the most useful single bubbles. Waveform bubble told me I can pinch, drag, double-tap and that the number counts bars. Without it I'd have read "CHORUS 32.4" as a time.
- 00:24:40 Hot cue A: pad went red with "3:11", flag on the waveform and overview. Tap again: jumped back. (Time said so, can't hear.)
- 00:24:45 Tapped the loop size number "4": it became orange, RELOOP became EXIT, shaded region on waveform, clock sat still around 3:13-3:14. Left arrow halved to 2 and loop shrank live. I didn't need help for this. (fu-12-loop-on.png)
- 00:25:10 ECHO: pad turned blue, blue dot over FX tab. Tap again off. The ? bubble for OUT is a bit of a riddle until you've pressed it.
- 00:25:30 Knobs: dragged LOW down and FILTER up: blue arcs show how far. They respond to a vertical drag - guessed right first time. Nothing on screen says whether LOW is cutting or by how much (no number). Meter dropped.
- 00:25:55 Also started REC at the same moment, tapped by me. It's a big red pill with a running time.
- 00:26:00 AUTO with deck 2 stopped and stems ready: "Echo throw next, with deck 2 cued at 128 BPM. AUTO's counting down the bars." Button counted "AUTO 4". (fu-13-auto-started.png). It tells me what it's doing, in words I half understood. I don't know what an echo throw is.
- 00:26:05 "Echo throw starting. Put both decks on STEMS to watch it. A control you touch is yours." Great line - told me where to look and that I can take over. I moved deck 1 to STEMS. The toast covers deck 1's section name for its entire life.
- 00:26:10 Deck 2 started itself. REC pill grew a "· 1": no idea what that is (a count of tracks in the recording?). It went to "· 2" when the move finished.
- 00:26:23 "Echo throw done. Deck 2 is on. More echo throws?" with thumbs up/down. (fu-15-echo-throw-done-thumbs.png). Whole move took about 25 seconds from pressing AUTO. Deck 1 stopped. Crossfader did not move, stayed in the centre. Deck 2 kept 128.
- Auto-DJ first mix: 00:26:23 (7m42 after open).
- 00:26:36 Pressed the thumbs-up: nothing visible (no tick, no change, toast just went). Don't know if it registered or whether the toast had already timed out.
- 00:26:50 MIX in Browse: "Mixing through all your tracks, 2 tracks to go. Up next: Exhilarate." Severe Tire vanished from stopped deck 1 without asking, replaced by Exhilarate, MIX button -> square/stop, status bar at bottom of Browse. (fu-16-mix-started.png). AUTO button on Decks renamed "MIX 12%". Clear enough. The next track is 170 BPM/12B against 128/1A - I'd never have picked this. It's going in list order, as the help said.
- CORRECTION to my earlier note: stem colours appear when a deck is on the STEMS tab, not when stems finish. I read that wrong for several minutes. Leaving STEMS tab turns the waveform orange/blue again. Help on WAVEFORM does say "lows, mids and highs, or stems" but not when each one shows.
- 00:27:15 MORE > is a tab which also cycles: MEM -> SLICE -> JUMP -> SMPL (and back?). Took me a few taps to see tapping again moved on. The label changes in place (MORE -> MEM >), with a little ">" telling you there's more. Clever, but nothing to say how many there are.
- 00:27:15 SAVE CUE: toast "Memory cue saved. The track loads here now." with UNDO. Trash icon on a toast that says "saved" looks wrong. Red flag above waveform and overview. Saved at 1:03. LIST lets me name it; autocapitalised "Drop". Fine.
- 00:27:17 SAVE LOOP with no loop: "Set a loop first, then save it." Good.
- 00:27:40 JUMP: 8 pads with arrows, 32 fwd jumped time as expected.
- 00:27:45 SMPL: tapped AIR HORN, pad lights. SET lit blue, then a tap on a pad opens "Pad 1" editing: One shot / Gate / Loop, Choose a File, Record the Master. Gate is unexplained in the sheet.
- 00:27:55 In "Pad 1" sheet, I scrolled, it bounced back and my next tap landed on Choose a File instead of Record the Master. A spinner, then a Files sheet (fully white tiles, no multi-select, no name of what it's for). Cancelled ok.
- 00:28:10 Record the Master: sheet closes, pad shows a recording dot, SET button becomes red "stop 0:00" counting up. Stopped after ~8 s. Pad renamed "REC 1" and my AIR HORN was gone. No warning, no undo. (fu-17-pad-record-master.png)
- 00:28:10 AUTO button "MIX 16" then 12, counting bars. At 100% stems, MIX moved Exhilarate's head to bar 2.4 of a CHORUS. I'd have thought intro but there it's labelled CHORUS 1.1 at the start of a track. Odd.
- 00:28:37 Good: "Restore the Original Sound" appears in the pad sheet once the pad has been replaced. I take back "no undo". You have to go looking for it. Tapped it... and my scroll bounced, so I actually tapped "Record the Master" again by accident? Pad now REC 1, red, with a record dot. Stopped; still REC 1. Sheet content jumps after any scroll/tap: the layout moves about 40 points when the sheet comes up and after scrolling, so a quick tap lands on the wrong row. Happened twice in 3 minutes.
- 00:28:41 "Loop build into Exhilarate." MIX: deck 2 sits in a 4-beat loop, shaded orange, overview shaded too. Deck 1 fades in? No: Deck 1 is at 2.4, ALL its stem pads dim (muted), green AI dot. Deck 1 waveform darkened. (fu-18-loop-build-into-exhilarate.png)
- 00:28:55 Long-press BPM (deck 1) during the MIX: beat-grid menu with Double/Halve, +/-0.1, Grid 10 ms earlier/later, Set downbeat here, Save cue as memory cue, Cues and loops. It's deep stuff. A small "lens" glass blob flashes as you press, looks like a smudge on the screen for a second. Menu needs scrolling on this phone: "Set downbeat here" cut off at bottom.
- 00:29:05 Closing that menu by tapping elsewhere: my tap also hit nothing else - good. But the mix's filter knobs (Deck 2's LOW/FILTER) are visibly turning by themselves. "A control you touch is yours" stuck in my head and I kept my hands off them.
- 00:29:40 Settings "What everything does": a searchable, well-written guide. Start here: LOAD AND PLAY, MIX TWO TRACKS, LET IT MIX. MIX TWO TRACKS is the first thing that told me about LOW knobs and swapping. (fu-20-guide-start.png) I had used the crossfader alone until this.
- 00:30:05 Searched "echo throw" (Auto DJ's moves section) and it answered perfectly. Searched "gate": only got "That's also where a pad becomes a one shot, a gate or a loop" - no explanation of what a gate is. 
- 00:30:20 In the guide, Done/back and the glass search bar float over the text, a third of a phone screen on its side; text scrolls under them blurred (fu-21-guide-search-bar-covers-text.png). Guide mentions things I can't find yet: TEMPO FADER, SLIP, BEAT JUMP, TEMPO %.
- 00:29:25 Swiped down on Settings sheet too many times and dismissed it by accident. Normal iOS, my fault. App was fine. Settings opened from the middle of a MIX didn't interrupt the mix.
- 00:29:22 "Loop build done. Deck 1 is on. More loop builds?" Skylander is loaded on deck 2 and stems started at 3%.
- 00:30:45 JOG (right of SYNC): this is the whole missing half of the deck: tempo fader, platter, BEAT SYNC, MASTER, BEAT JUMP, Q, SLIP, KEY, REV, key +/- and KEY SYNC. I'd had the app 12 minutes before opening this. "JOG" doesn't suggest tempo fader. I'd have looked for a tempo control. (fu-22-jog-page-sync-to-stopped.png)
- 00:30:50 Dragged tempo down: 170 -> 175.27 (+3.1). Faster when down as help said. Would've surprised me otherwise.
- 00:30:58 Dragged around the platter while playing: the time just kept counting, no visible jump. Don't know if it did anything.
- 00:30:59 BEAT SYNC on deck 1 while deck 1 is playing and MASTER and deck 2 is stopped: tempo dropped to 125, toast "Deck 1's 26% slower than its own 170 BPM, to follow." Master display said MASTER 1 125.00 i.e. it followed a stopped deck, but stays labelled master. BEAT SYNC button did not light. ±10 became WIDE by itself. Bit of a jolt. Time remaining jumped from -0:35 to -0:48, which is right for slower but surprised me.
- 00:31:30 "No clean way in. Next track starts when this one ends." (fu-23-no-clean-way-in.png) Straight talking: I understand and am grateful. At 00:31:45 Skylander started and Exhilarate was stopped with -00:05.9 left: its waveform had gone flat by then. MIX is still lit; Skylander's the last in the list. Deck 1's tempo stays at 125 / -26.5% from my sync.
- 00:32:00 MIXER key opens a full-screen "Mixer" sheet: TRIM 1, TRIM 2, MASTER, CUE/MST, LEVEL, SPLIT, FILTER (with a little circular arrow). Half the screen empty. ? works inside it, bubble at the bottom. Help text is good. (fu-24-mixer-sheet.png)
- 00:32:05 FILTER key: tap -> DUB, turns blue, the deck knobs' label changes from FILTER to DUB on both decks. I worked this out from the guide's "key with the arrows, under MIXER on a phone": that's the first time a help line had told me where something lives, thank you.
- 00:32:06 SPLIT turned on with no warning or message that I've got only one output. Meters kept going. I can't hear so can't say what it does. No indicator on the main deck screen that SPLIT is on.
- 00:32:40 Stopping REC: "Stop recording? Stop and save / Keep recording". Tapped through (the first tap hit help-off, then REC). Toast "Saved Mix 2026-11-05 00.25.56". I noticed the REC pill had to go through a 1-second stage before becoming "REC" again.
- 00:32:50 Recording pill is the second-from-left button (the waveform-bars icon) -> "Recordings" list. Icon says nothing about "recordings". Found by ? earlier ("RECORDINGS"). Yellow hand warning: "A recording plays out loud, over the mix. To listen to one, stop both decks." Clear and honest. Play is grey while a deck plays.
- 00:32:56 Tracklist icon: very nice. Shows times, artist, title, BPM and key for four tracks, even track names I'd never seen in the Browse list ("Gepzene - Can't be Serious", "Kevin MacLeod - Severe Tire Damage - High Quality"). (fu-25-recording-tracklist.png) BPMs there are the tracks' own, though I played Houston at 148 etc.
- HOLD ON: tracklist does not include Houston, even though Houston was on deck 2 at the time I started recording? No: Recording began after Houston was replaced by Gepzene, OK. It starts with Severe Tire Damage at 00:00 and Gepzene at 00:09. Consistent with what I did.
- 00:33:10 Rename: normal. Tracklist collapsed after rename, and the tracklist has the old name in it? Will check.
- 00:33:55 Browse: "Mixing through all your tracks. This is the last track." while MIX on. Stop MIX: "Mix off. The track playing just carries on." Reassuring. History Nov 5 count now 6, and it counts a track again if loaded twice?
- 00:34:00 IN KEY with Skylander leading: list shows only Skylander itself. No "nothing in your library's in key" message. ±6% BPM showed three. Good filter, but a tiny library makes IN KEY look broken.
- 00:34:12 Loaded Houston on deck 1 and did the guide's recipe: SYNC on deck 1, crossfader right, LOW 1 down, PLAY 1, crossfader to middle, swap LOWs, crossfader to the left. Finished 00:34:40. (fu-26-manual-mix-halfway.png, fu-27-manual-mix-done.png) All steps did what they said by the numbers: SYNC -> 125.00 on both, red bars/green mark on the beat blocks. Beat-block scale in middle sat at centre (green). I couldn't have done this from the screen without the guide. Mid-transition: the deck 1 LOW arc only came back to "a bit past centre" - no way to read the value. Knob-return is by eye. Couldn't try double-tap: this test tool can't tap twice quick enough.
- 00:34:55 Stopped deck 2: MASTER moved to deck 1 by itself, deck 1 SYNC went off, Houston stayed at 125 (its own tempo is 126). So after every sync the leftover track stays at the other's tempo. Nothing tells you; I only see it because the BPM number's not what the library says. That's three times now (Houston 148, Exhilarate 125, Houston 125).
- 00:35:05 Restore the Original Sound: this time I waited for the sheet to stop moving and it restored AIR HORN straight away. So my 00:28:37 press was the sheet bouncing under my finger: it started recording instead of restoring. The app had taken over the deck's SET key as a stop button with a timer, so I could see that.
- 00:35:15 ROLL: hold a pad: pad lights, RELOOP goes orange, loop size jumps to pad's value (4). On release clock is where it would have been (00:57.8 -> 00:58.1 moments later). "Worked" by numbers.
- 00:35:30 SLICE: hold 3: pad lights, RELOOP orange, loop size 2. Release: back to normal. Clock kept counting. Both fine.
- 00:35:40 MEM empty pads: completely blank, tapped one, nothing at all. No label like "empty" or "save a cue first".
- 00:35:55 Pinch on deck 2's waveform zoomed BOTH waveforms together. Good: keeps beats comparable. Nothing to say so but it makes sense. Drag on stopped deck waveform moved 0.8 s. Drag on the playing deck 1 waveform: no change I could read, clock carried on.
- 00:36:05 Tap overview while playing: "Hold the overview for a moment to jump while the deck's playing." One of the best bits: it stopped a jump, then taught me the gesture. Hold jumped to 3:39. Toast sits right on deck 1's section label (again).
- 00:36:00 New Playlist: name dialog, then empty-state: "Nothing in this playlist yet. Go to All Tracks, press and hold a track, and add it from there." Exactly what I needed. Tried dragging a row onto the playlist first (00:36:20): no drag, press-and-hold opens the menu and that's that. Add to Playlist is a sub-menu; "Added to Friday warmup."
- 00:36:30 Re-analyse with track loaded: "Analysing Skylander again."; BPM and KEY become "..." for ~3 secs, back with same numbers. Toast outlived the job.
- 00:36:40 Column headers sort (BPM down, then KEY up). Sort stayed separate from the playlist's order. No reordering in a playlist: I couldn't find a way, and MIX "goes through the list in order" so that matters. (Unknown whether a sorted list is the order it uses.)
- 00:36:50 Menu in a playlist needs scrolling: "Delete from Library" is half hidden at the bottom edge right under "Remove from Playlist". Close together, one's a much bigger thing. I did NOT press Delete; so I can't say whether it asks first.
- 00:37:05 Deck 1 ran off the end while I was in Browse and stopped by itself at 00:00.0 in red, CUE glowing. REC-less so nothing lost. Fine, but no warning on the Browse page that a deck's about to end.
- 00:37:10 Press play: the head starts BEFORE the first beat? The time reads -04:52.5 (longer than the 4:50 in the list, because of my 125 sync). OK.
- 00:37:15 Tap CUE while playing: back to 00:00.0, stopped. Hold CUE 2 s: plays while held, and returned to play button pale green ("pause" look) with -04:50.6 for a moment. Standard.
- 00:37:20 KEY SYNC on stopped deck 1: KEY lit, number shows -1, platter centre shows "10A" against Skylander's 11A. (fu-28-key-sync-minus1-10A.png) Nothing told me what happened or why -1. I guess it moved Houston to sit next to Skylander. The list says Houston is 5A, so to a non-musician the jump from 5A to 10A with "-1" looks like nonsense.
- 00:37:55-00:38:40 Settings read end to end (long, one-per-screen on its side): crossfader curve, Match track loudness, Prepare stems on load, Waveform colours, Haptics, Recording format, Save/Restore backup with clear warnings. All with one clear sentence. Save a Backup goes to a Files save panel, cancelled OK. No "how do I get sound to my headphones / which output" and no version number. Nothing about what stems cost in battery or storage, though the note says "Split tracks are kept".
- 00:38:40 Waveform colours -> RGB took effect at once, loud rainbow. Readable? It looks more like a thermal camera, but changes back easily.
- 00:38:50 Platter: dragged a half turn while playing with SLIP on. Numbers kept moving forward, I can't tell what the turn did.
- 00:38:55 REV on (red) with SLIP on: clock ran backwards to 00:00.0 and the deck stopped there by itself. Pressed REV off a second later: clock jumped forward to 00:07.2 and stayed STOPPED, overview marker too. (fu-30-rev-off-slip-jump-while-stopped.png) So a stopped deck moved 7 seconds on its own. I think this is SLIP bringing me back to where I'd have been, and the help did say something like that, but with the deck stopped it looks like a bug. Would have been lost if I'd not known I left SLIP on from earlier.
- 00:39:15 Tempo range key: ±10 -> ±16 -> WIDE, fader knob moves down a little each time (same speed, bigger range). Help "±6 ±10 ±16 WIDE" clears it. Didn't need to know it, though it's a sign of how far "SYNC" had taken this deck: -0.8%.
- 00:39:30 ? on BEAT JUMP, JUMP SIZE, KEY ("Key lock"), KEY SYNC ("fewest semitones to a key that goes with the leading deck"), SLIP: each good, and SLIP explains my 00:38:57 jump. KEY doesn't say what the blue -1 is; and KEY SYNC's "goes with" doesn't explain why 5A at -1 reads 10A. So I can use it but not check it.
- 00:39:50 Stem shortcuts: VOX: only VOCAL + SOLO V lit, deck waveform goes almost black in the intro and deck meter empties. If I hadn't known it's an intro I'd have thought it was broken. BEAT lights BASS and DRUMS. ALL puts everything back. Easy and clear after one go. INST: not tried on its own, assume the same.
- 00:40:00 With RGB chosen in Settings, a deck on STEMS tab draws stem colours anyway and the other deck stays rainbow, so the two waveforms look like different apps. (fu-31-one-rainbow-one-stems.png) The Settings note doesn't mention this.
- 00:40:05 Headphone key lit blue for deck 2 with SPLIT on. Can't test what it does.
- 00:40:10 AIR HORN while both decks play: pad lit bright, LIM dot red. Meters top out. LIM's own help says that's normal. OK.
- 00:40:20 Both decks playing and pressed MIX from my playlist: "A mix carries on from one playing deck. Stop the other." Told me what to do. I went back, stopped deck 2. Note it costs a trip to DECKS and back: no stop button in Browse.
- 00:40:45 MIX: "Mixing through Friday warmup, 2 tracks to go. Up next: Gepzene - Can't be Serious." The MIX button shows "94" (stems percent, it must be; earlier it was with a %). Crossfader is hard left by me. Curious to see if it moves it for me.
- 00:40:49 CORRECTION: "MIX 94" is not a percent. It went 94 -> 87 while the clock moved 13.4 s, which is 7 bars at 125 BPM. So MIX n is bars left until the move, and AUTO 55% (with the % sign) is stem progress. Two different numbers in the same button, told apart only by a %.
- 00:41:30 FX tab has 12 pads: ECHO, PING PONG, SPIRAL, REVERB, FLANGER, PHASER, FILTER, TRANS, CRUSH, ROLL, BRAKE, BACKSPIN. Hold ECHO and slide: lit while held. FILTER held. Fine.
- 00:41:40 *** Tapped BACKSPIN on deck 1 in the middle of a MIX (MIX 64 counting). Within about 4 seconds: deck 1 stopped at 01:55.3, MIX gone (button back to AUTO), deck 2 Gepzene jumped from 00:02.0 at 125 to my saved cue at 01:03.9 at 128, meters dead. So silence, both decks stopped. I only saw it because I'd pressed ? a moment later: there may have been a toast I missed, there was none on screen by then. App process number was the same as when I launched it (63677), so NOT a crash. (fu-32-both-decks-stopped-mix-gone.png). Going to reproduce it.
- 00:42:45 REPRODUCED, and a correction: there IS a toast, "Mix off: deck 1 was stopped." I'd missed it at 00:41:40 because I was looking at something else. ? on BACKSPIN and BRAKE both say the deck stays stopped until PLAY. So it does what it says. Still a trap: those two sit among the other effect pads, the rest of which don't stop anything. One tap on a pad that sounds like a flourish ended the mix and both decks. The label doesn't warn you; only ? does. Deck 2 snaps back to its saved cue and its own tempo (128), undoing what MIX had set up.
- 00:42:56 AUTO on Houston with Gepzene waiting: "Loop build next, with deck 2 cued at 125 BPM. AUTO's counting down the bars." It ignored the saved cue at 1:03 and put deck 2 at 00:09.5 (the track's "UP" section, whatever that is). Said "AUTO 10" and counted down to 0 in about 20 seconds. No choice of how many bars. Fine.
- 00:43:15 "Loop build starting. Put both decks on STEMS to watch it. A control you touch is yours." Crossfader slid itself from hard left to the middle. Deck 1's knob label went from DUB back to FILTER on its own while deck 2's still said DUB. That label mismatch looks odd: I'd set DUB on the Mixer sheet for both.
- 00:43:20 Tested "A control you touch is yours": dragged crossfader nearly all the way left. It stayed where I put it and AUTO kept going (fu-33-loop-build-after-touching-crossfader.png). Worry: I've got deck 2 faded out now; will it warn? Watching.
- 00:43:55 "Loop build done. Deck 2 is on. The crossfader's still turned away from it. More loop builds?" It noticed what I did and told me. That's the best bit of writing in the app. Deck 1 back at its own 126; deck 2 stays at 125 (own 128) and is now MASTER 2. Second time the track carries on at the previous deck's tempo.
- 00:44:00 Thumbs down: "Got it. Less like that." So thumbs do answer. My thumbs-up at 00:26:36 must have missed the button or come after the toast left; that's a me or a timing thing, not a broken button. What it's "less" of (loop builds, for this pairing, forever?) isn't said and nothing shows what I've taught it. (fu-34-after-thumbs-down.png)
- 00:44:20 IN and OUT by hand: IN lit orange, OUT made a loop and the size number turned into "7.7". EXIT on the key. MEM > SAVE LOOP gave a loop pad labelled 2:25. Good. LIST for that loop says "2:25, 7.8 beats": 7.7 on the deck, 7.8 in the list. Tiny, but they should agree.
- 00:44:33 LIST wording: "A loop switched on here is waiting when the track loads, and holds the deck once it gets there." Clear, but the switch itself has no label, so the sentence below is the only clue.
- 00:44:50 MEM's DEL: tap DEL, it goes red, tap loop pad, gone. "Deleted saved loop" + UNDO: brings it back. Same on CUE tab. DEL went off by itself after one delete, safe. Good. The word MORE and DEL crowd each other at the end of the tab row and the row's letter spacing shifts by a few points when DEL is there.
- 00:45:10 BPM menu heading: "Beat grid: 126.00 BPM at normal speed". Halve BPM on deck 1: readout 63.00, and the clock did not slow down (kept running at normal rate). So it's correcting the app's reading of the track, not changing speed. That's fine for a DJ, but the button says "BPM" not "this reading". I only know because I watched the clock.
- 00:45:15 SYNC then: "Deck 1 follows at half tempo: 62 against 125." Screen says 62.50. Sensible. Doubling back to 126 at once: toast above is now stale and stayed up. Deck 1 reads 125 from then. Toast covers the section label again.
- 00:45:46 Recording: "First go, 6:46, 12.9 MB, M4A". Play: scrubber appears with 0:02 / 6:46, dragging the scrubber went to 5:05. Plain and it works. Closed the sheet while playing it: the mix meters stayed flat, so I can't tell from the deck screen whether it's still playing. There's no indicator outside the sheet.
- 00:46:03 Home button with deck 2 playing, Home screen for 6 secs, back by the icon: same process, same screen, deck 2 had carried on (2:05 -> 2:16). Nice. Portrait home screen, and it came back on its side straight away. There are two "CheeksUITes..." icons on the Home screen next to it; not the app's fault but see section 6.
- 00:46:45 Re-imported Exhilarate: "That track's already in your library." Good. No duplicates. Search for nonsense: "No Results for zzz". Normal. Tapping a track row does nothing at all (no highlight, no preview, no load, no message), though tapping is what I'd try first. ? IMPORT: good, includes "If Files opens on an empty folder, go back from there", which I never needed but a real person might.
- 00:47:05 AUTO with nothing playing: "Play a track first, then Auto DJ can mix out of it." Good.
- 00:47:15 AUTO while counting down, pressed again: "Auto DJ off." and it PUT BACK what it had changed: deck 1 returned from 00:22.8 to my 03:20.3, SYNC came back on. Excellent, I trust the button more now.
- 00:47:42 Stopped the outgoing deck by hand in the middle of an echo throw: AUTO stayed on for a while, then went off at some point in the next 15 secs with deck 1 on and deck 2 stopped, back at 128. Meter went straight to deck 1 only. Nothing bad happened: no toast I caught said what had been done. It handled it. Time-remaining goes red for the last 30 seconds: nice, I noticed that without being told.
- 00:48:36 Pressing PLAY on a deck that has run out: it jumped to my saved cue at 1:03 and played. Sensible once you know, a surprise the first time: it's the track's "memory cue", which I'd forgotten about.
- 00:48:45 Both decks playing: every load button in Browse greys out and tapping says "Deck 2 is playing. Stop it first." No way to replace a track while it's playing, which is safe, and I never wanted to, except when it stops me getting a new track ready while both play.
- 00:49:00 Beat-matched by hand: JOG page, ±10 to ±16, tempo fader up to -15.5% takes 148 to 125.00, same as deck 1. Fader is quick: 2 points of finger moved it 124.36 -> 125.00. No way that I found to nudge by a small amount from the screen (no +/- buttons on tempo). Phase I couldn't work out by myself: the beat-block strip (between the waveforms) has dashes and colours but I can't read which is which, even after its help. (fu-36-manual-tempo-hunting.png)
- 00:49:35 ? on beat blocks: now I can read them: "Four blocks for each deck ... mirrored about the middle ... Red is the first beat. The scale in the middle shows how far apart." Clear words, but the bubble covers half of what it's describing while you read it.
- 00:49:47 Tried to nudge deck 2 with the platter's right edge and grabbed the tempo fader instead: tempo -15.5 -> -4.2 (125 -> 141.77) in one drag with both decks playing. The platter's edge and the fader sit side by side and the fader will take a drag from anywhere near it, wherever the knob is. Wrong gesture on my part, but that's a nasty, instant 13% jump in a mix. BEAT SYNC put it right in one tap ("Deck 2's 16% slower than its own 148 BPM, to follow.").
- 00:50:00 With a sync running the waveforms visibly line up: red bar markers at the same place on both. So that's how you can tell. Good to see.
- 00:50:05 SMPL: SET + tap SIREN opens "Pad 2": One shot / Gate / Loop. New row "Grab Deck 1's Loop" (only there when deck 1 has one?). Set to Loop: pad gets a loop icon, SET turned itself off. Tap SIREN: pad lit. STOP: pad off. VOLUME slider is a blue bar you drag: dragged to near zero, it stays. Nothing warned me, and it isn't a usual look for a slider, but it works. Restored it.
- 00:50:10 Meter shows a red block now and again at top of a meter while LIM stays dark. Red usually means too loud. I don't know which matters.
- 00:50:38 Platter on a stopped deck: 01:12.4 -> 01:13.0, waveform moved with it. So here it's fine for finding a spot. While a deck plays I still can't see that it does anything.
- 00:50:50 Tapping or holding the track name or the time on a deck does nothing. There's no eject, no way to see the artist on a deck, no way to swap elapsed/remaining (they're both shown, so fine).
- 00:51:05 Key + twice on deck 2: "+2" in blue, the tiny platter label goes 5A -> 7A. KEY off: goes 10A. Correction to my 00:37:20 note: the -1 -> 10A looks to be right if you know how these labels work (a step up is not a step in the number). I didn't get that from the app. The label's tiny (about 4 pts on this screen) and it's the only place you see it. With KEY off, the app shows 10A with no warning at all. The Browse IN KEY filter: don't know if it uses 5A or 10A.
- 00:51:29 Delete from Library asks first: "Delete Exhilarate? This removes its file from Segue DJ, along with its cues, loops and stems." Clear, with Cancel. So my 00:36:50 worry about the menu's close neighbours is smaller than I thought. It doesn't say the original in Files is safe; "from Segue DJ" hints at it. I cancelled. History count has reached 11 for 5 tracks over 33 minutes.
- 00:51:40 History list shows repeats, newest first, and every row of a loaded track lights its deck button. MIX in History: "Everything else here has been played. To go round again, stop the deck and press MIX." Which told me what the little grey ticks by the track names are! I'd been seeing them for half an hour without asking. ? on a tick gives only the general ? bubble. (No ticks at first import, see fu-02-imported-analysing.png.)
- 00:52:10-35 Guide search: "played" finds REC ("how many tracks so far": so that's what the "· 2" on REC is) and TIME. "headphone" finds CUE, CUE/MST, LEVEL, SPLIT, which answers everything I had about phones and a splitter cable: "One output, like AirPods, can only play the mix." I wish I'd seen that at 00:32:06 when I lit SPLIT; the toggle says nothing. "5A": No Results (fu-37-guide-search-5A.png). "key": first hit is the "?" entry, because the word "keys" is in it. In the whole guide, as far as I can search it, nothing explains the number-letter codes, though they are in big colour in every row. CUE/MST says "left for the decks you've cued, right for the mix" while CUE says "with the cue in your right ear". Knob left, ear right: reads like a contradiction. And two different things are called CUE: the big orange button and the headphone key, which has no word on it.
- 00:52:56 Houston ran out while I read the guide. Loaded Exhilarate on BOTH decks: allowed, no fuss. Sections say "CHORUS 1.1" on what's a blank stretch before any waveform, on a track whose first 5 secs look silent. So "CHORUS" isn't always right, or I don't know what it means.
- 00:53:05 AUTO with both decks on the same track: "Brake drop next, with deck 2 cued at 170 BPM. AUTO's counting down the bars." A third kind of move. REC on: pill reads "0:11 · 1", and it stayed "· 1" after a transition to the same track.
- 00:53:30 "Brake drop done. Deck 2 is on. More brake drops?" (fu-38-brake-drop.png). Deck 1 stopped at 00:24.7, showed nothing like a slow-down I could catch in screenshots.
- 00:53:50 The Stop recording? dialog lets the music run on behind it. Saved mix: "Mix 2026-11-05 00.53.09, 0:41, 1.4 MB, M4A". The name is the START time, so the toast (at 00:53:52) and my clock differ by 41 secs. No problem.
- 00:54:03 Delete on a recording: "Delete this recording and its tracklist?" with a red Delete and NO visible Cancel. Tap outside does cancel (I checked, it stayed). On this one, the track-delete dialog had a Cancel; here you have to guess.
- 00:54:17 With a deck playing, Play on a recording is greyed and does nothing, the hand note explains it. Fine.
- 00:54:23 Settings' sticky header goes dark and blurred over text as you scroll. No trouble with reading the "Prepare stems on load" note: "Split tracks are kept, so they load instantly next time." It doesn't say how much room that takes, or how to clear it.
- 00:54:45 Playlist long-press: Rename Playlist, Delete Playlist. No reorder. History Nov 5 has now got to 12 entries.
- 00:55:05 Followed the toast's advice (stop the deck, press MIX) with All Tracks sorted by BPM, highest first: "Mixing through all your tracks, 4 tracks to go. Up next: Severe Tire Damage." So MIX follows whatever SORT I've chosen. That answers my 00:36:40 question, and is the only way to choose an order; nothing tells you so.
- 00:55:21 While MIX was counting (MIX 58), I held the overview near the end of deck 1's track. It jumped to 02:03.6 and the count went straight to MIX 11. Nice, the countdown follows you. MIX also pressed PLAY for me on deck 1, carrying on from where it had stopped (00:24.7) not from the start.
- 00:55:47 With a long track on, the MIX button truncates to "MIX..." : the count (three digits) doesn't fit. (fu-39-mix-button-truncated.png). Up to then: Echo throw into Severe Tire ran from deck 1 at 170 to deck 2 at 148 and left deck 2 playing 148, deck 1 with next track Gepzene at its saved cue 1:03.
- 00:56:30 FX tab: the top row of the pad area becomes a mini control strip: beat length arrows, DEPTH bar, V/I/B/D, OUT. ? on V I B D has the second clever idea in the app: "Echo just the vocal and then mute it, and the echo rings out over the rest." Took D off, tapped ECHO: lit. Pressed OUT: red, meters dropped, the ECHO pad stopped being lit, toast "Echo out on deck 2. Press OUT again to bring it back." (fu-40-fx-on-parts-out-back.png). Without that toast I'd have thought the deck had broken.
- Noticed DEPTH on deck 2 isn't full, deck 1's looks full. I never touched either. Deck 1's slider is a solid blue pill, deck 2's is about 60%. Same word, same control, different starting values on the two decks?
- 00:57:15 Went back to the waveform bubble: it does say "UP's a build-up, DOWN a breakdown." I'd read that at 00:24 and forgotten it by the time I saw UP at 00:43. Fair enough. VOLUME on SMPL is back at full, so my 00:50 drag put it back. DEPTH on deck 2 still partly filled; I can't remember touching it. It may have been me or one of the auto moves, which would explain why I can't say.
- 00:57:31 DJ library (XML) opens the same Files picker with my music greyed out and no word about what kind of file it wants or from which program. Help on IMPORT covers it if you look. I closed it. Nothing lost.
- CORRECTION: the BPM menu opens with a plain tap on "BPM v", not a long press as I wrote at 00:28:55.
- 00:57:46 BPM + 0.1: 128.00 -> 128.10, menu closes, so a real fix of, say, 0.5 BPM is five visits. Put it back with - 0.1. "Cues and loops..." at the bottom shows the track's saved points by name and time: my "Drop" at 1:03. Calm, simple page.
- 00:58:19 Preview with SPLIT on: no toast, so the 00:22:50 warning is about SPLIT being off (which is the default). The toast is a good fact at a bad moment: the first time I ever tried preview it told me I'd been playing it over the mix, and only after I'd stopped. It's also the only place in the app that nudges you to look at SPLIT. Preview has a blue ring progress and a white stop on the tile. Nice. History Nov 5 is 13 now.
- 00:59:20 Second-from-last MIX move: Severe Tire left with 3:05 still to run. So MIX doesn't play tracks to the end; nothing says it won't, and I'd assumed it would. Toast "Echo throw done. Deck 1 is on. More echo throws?" Thumbs up: "Got it. More like that." So the thumbs work; my 00:26:36 tap was probably too late or off target.
- 01:01:52 Last move watched: FILTER/LOW on deck 1 turn by themselves, and deck 1's label goes from DUB to FILTER while deck 2's stays DUB (fu-41-move-running-filter-borrowed.png). The guide line "Auto DJ can borrow it for a filter" explains that. Before reading it I took it for a label bug (my 00:43:15 note).
- CORRECTION, DEPTH: deck 1's DEPTH was partly filled at 00:21:57 too (fu-07), the same as deck 2's. So partly filled is the starting value, and deck 1 only went full because I slid up on the ECHO pad at 00:41:30. A slide on the pad changes DEPTH and it stays changed. Not a bug. My 00:56:30 and 00:57:15 notes are wrong about that.
