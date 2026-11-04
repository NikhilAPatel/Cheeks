# Hands-on results, part 10, 2026-11-03 and 04

Commit tested: 53a0201
Device: iPhone Duo simulator, unfolded (951×669 pt; inner screen 2853×2007 px, read before starting), and `iPhone SE Cheeks` (375×667 upright, 667×375 on its side). iOS 27.2. Fresh installs of `com.nikhilpatel.seguedj` on both.
Tooling limits:
- **I broke video on the Duo, at 23:43.** A background job in a non-interactive shell ignores SIGINT, so my first `recordVideo` wouldn't stop, and I sent it SIGTERM. Its render server (pid 81303) carried on recording with nothing attached, and every recording on the Duo since says "A recording is already in progress". On a throwaway simulator, since deleted, the same mistake gave the same error, and sending SIGTERM to that simulator's render server shut the whole simulator down. So on the Duo that would fold it. **It's still running as I hand this over:** about 118 MB/min (112 GB free at 01:11) and about 36% of a core in `SimMetalHost`. A shutdown clears it, and then someone has to press Open in Device Hub. This session has no computer use, so I can't press it.
- **So no video on the Duo.** CB5 is blocked. CA1, CA2 and the big library use the app's freeze log and screenshots on the Duo, and video on `iPhone SE Cheeks`, which records fine. Each says which. The freeze log only sees 100 ms or more.
- **Everything measured or timed on the Duo after 23:43 had that recorder running beside it.** The CPU figures are for the app's own process, so it can only reach them by competing for the Mac.
- **Beside the measuring:** another project's `xcodebuild test` (Slevens) was running on its own simulator, using up to 120% of a core. It couldn't be paused. The other session stopped its gate and shut down its simulators from 00:21 to 00:47. The Mac was 20 to 66% idle by `top` throughout, with load average 120 to 620, and `pmset -g therm` recorded no thermal or performance warning. The CPU table has each row's idle figure.
- **The owner paused me from 00:27 to 00:28.** It stopped CB1 after its fifth row. The last two rows were measured after resuming.
- **Not judged:** how anything sounds, haptics and the headphone output. Levels and gaps come from the recordings.
- **Tool lag:** a tool call takes 1 to 4 s when chained, and more when the Mac's busy. Three times a seek meant for "just after the landing" arrived after the whole move had finished. Four taps sent as one batch at 00:29 lost two pad presses. Spaced out, and in pairs, the same presses worked, so I put that down to the tool. One tap at 01:02 failed with a tool error.
- **The first-time user** was a separate subagent, on `iPhone SE Cheeks`, kept away from the repo's docs and code. It had still seen the project notes, and it says what that changed. I checked its most surprising claims against its screenshots or by doing them myself, and say which under **The first-time user**.
- **The two fingers:** both land together, and neither slides, in CA6.
- **Files:** `On My iPhone` has `My Music`, the only folder here that isn't the app's, plus old backups from earlier rounds on the Duo.

## Summary
40 tests: **26 PASS, 6 FAIL, 1 BLOCKED, 7 just reported** (the first-time user's five and two of the big library's, which ask for what I saw). **No crashes:** no Cheeks or Segue crash reports.

The big changes hold. Idle CPU is back: 3.0% with nothing loaded and 3.2% with two tracks paused, where round 9 had 12.9% and 16.4%. Opening and closing the browser with 2,005 tracks, both decks playing and a recording gave no freeze of 100 ms or more in 10 presses, and nothing can be pressed through it. `AUTO` after a stopped move now gets there at full level, both ways round. Severe Tire Damage reads 148 from the start. In a 15:28 long run nothing was left silent, looping or filtered without the screen showing it.

The problems, most important first:
1. **LR2: a Bass swap goes silent for 0.43 s just before the new track's kick,** 2 of 2 recorded. It's digital silence on the master, in a move that passed its audition. It looks like the 0.42 s round 9 put down to LR1, so that fix wasn't what it needed.
2. **CA4: the browser list doesn't keep its place.** It went back to the top 6 of 6 times, with nothing but scroll, close, wait 3 s, reopen, at 155 tracks and at 2,005. `JOG` does stay. The other session's UI test on the iPad Air doesn't see this.
3. **CB2: the `Segue DJ` folder shows in Files but won't open.** Seven tries in Files and the picker on the Duo, and the first-time user saw the same on the small iPhone, while `My Music` beside it opens first time. This might only be the simulator, so it needs looking at on the phone.
4. **The tempo a move leaves on a deck carries to the next track.** See **Looks wrong**. Exhilarate read 166.02 straight after loading, on a stopped deck, because of a -2.34% nobody had set by hand.
5. **CC13: `SPACE` fully anticlockwise still lights `LIM`:** 3 of 9 and 6 of 8 samples on loud parts. Clockwise, `DUB` and `NOISE` are clean. **CA8:** behind the file picker the deck strip now jumps up onto the waveforms. **CC3:** long titles on a small phone's side break mid-word.

## Failures

### LR2: a Bass swap goes silent for 0.43 s just before the new track's kick
- Steps: `AUTO` from Skylander into Gepzene, with a recording running. A Bass swap, chosen by the planner. Twice: in the 23:58 recording and in the long run.
- Expected: no hole. The audition rejects plans with one.
- Actual, the master in tenths of a second, in dB:

  | Recording | Where | Levels through the hole | Length under -50 dB |
  |---|---|---|---:|
  | Mix 23.58.08 | 8:36 | -22 -28 -42 -127 -inf -145 -22 **-9** -13 | 0.43 s |
  | Mix 00.47.59 | 7:19 | -25 -18 -26 -35 -90 -inf -inf -86 -11 **-10** | 0.44 s |

- By the second it's -12 to -15 dB either side, dipping to -21 or -22 where the hole falls. It then settles at -14. In the long run it ended normally: "Bass swap done. Deck 2 is on." about 14 s later. In the first I'd pressed `AUTO` about 9 s after it, which said "Auto DJ stopped. Deck 2 is on."
- Skylander was at about 2:19 both times, on +0.00%. That's where its own level falls, from about -7 to -20 dB, and its file has no gap at 2:15 to 2:21. Gepzene was at -2.34%, at about 0:47 and about 0:51 by my reckoning, so I can't place it closely. Its whole file has one run of 0.06 s under -50 dB between 0:44 and 0:52. I didn't check its drums on their own.
- A beat at 125 is 0.48 s, so the hole is nearly a beat.
- Round 9's LR1 reported "0.42 s at -58 dB right before the landing". It looks like the same thing, in a move where everything else that fix dealt with is now fine.
- The Loop builds and Echo throw in the same recording have nothing like it, but only these two Bass swaps were recorded, both this pair.
- I can't say how it sounds, or whether a beat's silence before a kick could pass as deliberate. The audition is there to catch holes, and it passed both of these.

### CA4: the browser list goes back to the top
- Steps, the barest version: launch, `BROWSE`, one 0.5 s swipe, wait 4 s, `BROWSE` with a 0.2 s press, wait 3 s, `BROWSE`.
- Expected: where you left it.
- Actual: at the top, 6 of 6.

  | Device | Tracks | Decks | Sort | Scrolled to | Closed for | After |
  |---|---:|---|---|---|---|---|
  | Duo | 2,005 | Both playing, recording | Default | Track 1828 | About 2 s | Top |
  | Duo | 2,005 | Both playing, recording | Default | Track 1942 | About 2 s | Top |
  | Duo | 2,005 | Loaded, stopped | `KEY` | About Track 925 | About 2 s | Top |
  | SE upright | 2,005 | Playing, one on `JOG` | Default | Track 1924 | About 2 s | Top |
  | Duo, fresh launch | 2,005 | Empty | `KEY` | Track 1659 | 3 s | Top |
  | Duo, fresh launch | 155 | Empty | `KEY` | Track 113 | 3 s | Top |

- Nothing was pressed between scrolling and closing, and `NEXT`, the filters and any playlist were off. So it isn't the 200-row limit, the sort, or anything on the decks.
- The other session says its UI test on the iPad Air keeps its place. I haven't tried an iPad.
- The other half passes: a phone deck on `JOG` stayed on `JOG`.
- Screenshots: `ca4-scrolled`, `ca4-reopened-at-top`, and before over after in `ca4-bare-2005` and `ca4-bare-155`.

### CB2: the `Segue DJ` folder shows, and won't open
- Steps: fresh install, open Files, `On My iPhone`, tap `Segue DJ`.
- Expected: `Music`, `Recordings` and `Backups` inside.
- Actual: it's there with the app's icon: "2 items" on a fresh install, "4 items" after an import, so the count's live. If Files was already running, the folder wasn't listed until I relaunched Files. **Tapping it does nothing:** 7 tries with default, 0.15 s and 0.2 s presses, in Files and in the app's picker. `My Music` next to it opens first time, in both, with the same taps. The first-time user's taps on the small iPhone didn't open it either.
- Files logs, at each tap: "An node, 'Segue DJ', was selected. Attempting to open it? false", then "Cannot find source for location… title="Segue DJ" DOCNode=FILocalAppContainerNode<Segue DJ>".
- `LSSupportsOpeningDocumentsInPlace` and `UIFileSharingEnabled` are both true in the built app. The disk has `Documents/Music`, `Recordings`, `Samples` and `Backups`.
- **Copying a track in works:** into `Documents/` with the app in the background, it was imported when I came back and moved to `Documents/Music/<id>.mp3`. I couldn't try `Browse`, as I couldn't get inside.
- This might be only the simulator's Files. It's worth one look on the phone.
- Screenshot: `cb2-files-folder`

### CA8: behind the file picker, the deck strip jumps onto the waveforms
- Steps: browser open, `IMPORT`, `Music files`.
- Expected: nothing changes behind it.
- Actual: the mixer now stays put, which is the part round 9 reported. But the compact decks jump up about 160 pt, onto the waveforms, and the browser's sidebar and list go, until the picker closes. It comes back correctly.
- It opened in about 2 s on the Duo, in `On My iPhone`. On a fresh install on the small iPhone it opens in `Segue DJ` reading "Folder is Empty" (see FU1).
- Screenshots: `ca8-picker`, `ca8-picker-behind`

### CC13: `SPACE` fully anticlockwise still lights `LIM`
- Steps: Skylander's loud part, the knob at each end, screenshots of the meters every 1 to 2 s. So these are spot samples, not how long it was lit.

  | State | Where | `LIM` lit | Top LED red |
  |---|---|---:|---:|
  | Knob just off centre, looped | 4:02 | 0 of 11 | 1 of 11 |
  | Centred | 4:20 | 1 of 8 | 3 of 8 |
  | **`SPACE` anticlockwise, looped** | 4:02 | **3 of 9** | 5 of 9 |
  | **`SPACE` anticlockwise** | 3:55 to 4:05 | **6 of 8** | |
  | `SPACE` clockwise, looped | 4:02 | 0 of 9 | |
  | `SPACE` clockwise | 2:03 | 0 of 11 | |
  | `NOISE` clockwise, looped | 4:02 | 0 of 14 | 3 of 14 |
  | `NOISE` anticlockwise, looped | 4:02 | 0 of 21 | 2 of 21 |
  | `DUB` anticlockwise, looped | 4:02 | 0 of 17 | 2 of 17 |
  | `DUB` clockwise, looped | 4:02 | 0 of 13 | |

- Better than "the whole time", but not "rarely". Bringing `SPACE` back from clockwise to centre over 6 s showed no jump in 7 samples, which can't rule out a short one.

### CC3: long titles on a small phone's side break mid-word
- Steps: `iPhone SE Cheeks` on its side, with two tracks loaded.
- Expected: a readable header.
- Actual: "Skyl / an…", "Seve / re…", "Gepz / en…", "Exhil / arate", and "Hous / ton" even when it would nearly fit. The behaviour's right: `SYNC` took Severe Tire Damage from 148 to 126, lit, the same as `BEAT SYNC`, and goes away on `JOG`, upright and on its side.
- Screenshots: `ca-se-sync`, `fu-side-titles-and-stems-truncated`

## Blocked

### CB5: the logo on the Duo, frame by frame
No video on the Duo, as above. **On the small iPhone:** across launches 2, 3 and 5, measured frame by frame, the logo's bright rows settle and then stay within 1 px until the decks show. No doubling in the frames I looked at. That doesn't settle it, as round 9's failure was only ever on the Duo, and the small iPhone didn't show it then either. `cb6-se-launch`.

## Looks wrong

**Auto DJ and `MIX`**
- **The tempo a move leaves carries to the next track.** Gepzene came in at -2.34% to match Skylander. When it stopped as the old deck, its fader stayed at -2.3, which isn't what "back to neutral" led me to expect. `MIX` then loaded Exhilarate there, which read **166.02** and not 170 on a stopped deck, -2.34%, with nobody having touched the fader. While the mix had a plan it read 170.00 +0.00%. After `Mix off` it went back to 166.02, and it played at that. The first-time user hit the same thing by hand: 129.02 and 151.55 on tracks the list calls 128 and 148. `lw-tempo-carried-to-next-track`.
- **A mix's plan was lost by a loop, with stems ready.** `MIX 55` was counting down. `OUT` then `EXIT` on the playing deck: "The mix will carry on when deck 1's loop ends", then `MIX…`, then, with Skylander at 2:30 and over 3 minutes left, "No clean way in. Next track starts when this one ends." Once, and I then turned the mix off. The first-time user's first `MIX` also ended that way, though there the stems had only just finished.
- **`MIX` takes the stopped deck's track away.** `AUTO` tells you to stop the one you want next, and `MIX` replaces it with the next on the list. I saw Gepzene go for Exhilarate on the Duo. The first-time user lost a split at 33% to it, and calls it the contradiction it is, since it had just been told to stop the one it wanted.
- **After stopping a move and then the old deck, there's silence with `PLAY` lit.** Bass swap or Loop build, `AUTO` before the handover: the new deck runs with every stem off, as "the decks are yours" says. Stop the old deck, and there's nothing at all: 7.96 s in my recording, until I pressed `AUTO`. The dim waveform and pads do show it. Nothing says so, and the meters are simply dark.

**Decks**
- **`OUT` with no `IN` sets a loop at once.** Its length depends on where the deck is. Once it read `1.3e…` in the loop key, with `EXIT` lit (`fu-out-without-in-1.3e`, which I've looked at; I didn't reproduce it).
- **A capsule's 5 s doesn't restart for the same words** (`.task(id: dj.statusMessage)`, `ContentView.swift:525`). Pressing dim controls about 5 s apart, one message showed for only every other press, so half of them looked ignored. On their own, spaced out, each said it.
- **`Q` and `KEY` stay full blue on an empty deck,** where everything else is dim, and so do the `STEMS` page's pads.
- **A press during the logo is lost.** `BROWSE` about 1 s after launching did nothing, and at 2.2 s it worked.

**Browser and Files**
- **The first keyboard after a launch freezes the app:** 1,663 ms and then 810 ms, with both decks and a recording, and with no dropout. Every later search had none. It may be the system's keyboard, which I can't separate from here.
- **"Delete from Library" removes a playing track** with no confirmation and no undo, and the deck plays on. A deleted hot cue gets `UNDO`. `fu-deleted-playing-track-no-confirm`, which I've looked at.
- **On a small phone's side:** the sidebar reads "All Tr…" and "History…", and capsules lose their second half, usually the part you act on. `fu-side-refusal-truncated`, which I've looked at.

## All results
| Test | Result | Notes |
|---|---|---|
| CA1 | PASS | Duo, 2,005 tracks, both playing, recording, 10 presses, all landed: **no freeze of 100 ms or more**, on the freeze log. No video there. On video on the SE: worst 130 ms upright, with a split running, and 162 ms on its side. First open: at 2.2 s and at 7 s after launching, no freeze. *Last time: 620 to 800 ms and 340 to 470 ms, on the Duo by video, so not the same measure.* |
| CA2 | PASS | SE, both ways up, contact sheets of both directions: clean, nothing doubled or left behind, and the meters carry on throughout. Duo by screenshots only. Jogs and meters are drawing as soon as the decks are back, stopped and playing. |
| CA3 | PASS | Duo. Browser open, 9 presses under and round it, including both edges and the bottom: nothing moved. Closed, 6 presses where its load keys and filters were: nothing loaded or changed. |
| CA4 | FAIL | The list goes to the top, 6 of 6. `JOG` stays. |
| CA5 | PASS | "sky" typed, closed with the keyboard up: the keyboard's gone and the search is empty on reopening. Audition on: the meters are dark at once on closing, 3 of 3. `ca5-audition`. |
| CA6 | PASS | 3 of 3. `ROLL` pad: let go, ran on, no pad lit, no loop. `CUE`: stopped on its cue. Hand on the platter: it ran on, -3:42.7 then -3:40.0 2.7 s apart. Each fine on coming back. |
| CA7 | PASS | No dim row in my screenshot 1 s after typing, though nothing on video. Filters on and off: no freeze. The first keyboard froze the app: see **Looks wrong**. A 5-track list fades its rows out and in on each filter change. |
| CA8 | FAIL | The mixer stays. The deck strip jumps up about 160 pt. |
| CB1 | PASS | 3.0 and 3.2% at rest. See **Timings and measurements**. |
| CB2 | FAIL | It shows and won't open. Copying in works. |
| CB3 | PASS | Both ways. See below. `cb3d`, `cb3e`, `cb3g`, `cb3i`. |
| CB4 | PASS | First analysis: Severe Tire Damage 148, Exhilarate 170, Skylander 125, Gepzene 128, Houston 126, the club tracks as in round 9. After stems, the same, and `gridSource` `drums` on all but Exhilarate. Nothing jumped, so no message was due. |
| CB5 | BLOCKED | No video on the Duo. No jump on the SE. |
| CB6 | PASS | SE only, Duo blocked. 5 of 5: the meters run up and back once as the logo lifts, peaking about 1.9 to 2.3 s into the video. `cb6-se-launch`. |
| CC1 | PASS | No `DSP` in any screenshot, with load average up to about 620 and two stems splitting. |
| CC2 | PASS | All dim. `PLAY`, `CUE`, `IN`, a hot cue pad, `BEAT SYNC`, `MASTER`, `BEAT JUMP`, `KEY SYNC`, the jog and the tempo fader each say "There's no track on deck 1 yet. Load one from the browser." with a hand. Tabs change page, `SAMPLE`'s pads play and the meter moves, and the header opens the browser. It looks right, like hardware that's off. `ca-empty-deck`, `cc2-sample`. |
| CC3 | FAIL | The key's right, upright and on its side. Long titles aren't readable on its side. |
| CC4 | PASS | `MORE` is readable and opens the panel. Though it's the same word as the tab's `MORE >`, which does something else. |
| CC5 | PASS | "Auto DJ stopped: deck 2 stopped before the stems were ready." |
| CC6 | PASS | `MIX…`, with "The mix will carry on when deck 2's loop ends." `cc6-mix-waiting`. |
| CC7 | PASS | Parked at 1:53: pad at 1:53, 113.19 s in the library. On its cue: 0.197 s, with the deck there. |
| CC8 | PASS | `DEPTH` and `VOLUME`: a tap sets it, and a drag past either end reaches that end. |
| CC9 | PASS | With only History there's no `Add to Playlist`. With `Set One` it offers only that. `cc9-add`. |
| CC10 | PASS | Duo: Skylander 8% 3 min, 30% 3 min, 48% 2 min, 66% 1 min, 82% 40 s, 99% 5 s, with Gepzene alongside, about 3.5 min in all. SE upright: see FU3. It never went up. Right to within about a minute. On a phone's side there's no room and no estimate. |
| CC11 | PASS | Upright: the first-time user reports a small spinner at top right. |
| CC12 | PASS | Overview, about 6 s in, and hot cue, about 10 s in, both before the landing: "Auto DJ stopped: deck 1 was moved. The decks are yours." It stayed where I sent it, and the new deck stopped with its tempo back. After landing, in an Echo throw 7 s after the new deck started: it stayed and the move played out, "Echo throw done. Deck 2 is on." `cc12a`, `cc12b`, `cc12-seek-after-landing`, `cc12-echo-plays-out`. |
| CC13 | FAIL | `SPACE` anticlockwise lights `LIM`. The rest are clean. |
| CC14 | PASS | Smaller type on dark in both. Eight colours in a small popover that closes on a pick. Green reached the list, pad, waveform flag and overview flag at once. A footnote in the pad's sheet mentions grabbing a loop when no grab is offered. `ca-cue-list`, `ca-colours`, `cc14-sampler-sheet`. |
| CC15 | PASS | "FX pads slide: up and down for depth, left and right for the beat." the first time, and not after a relaunch. `cc15-fx-first`. |
| FU1 to FU5 | Reported | See below. |
| BIG1 | PASS | With 2,005 tracks, main thread free at 0.73, 1.52 and 1.84 s. `BROWSE` works from about 2.2 s. |
| BIG2 | Reported | See below. |
| BIG3 | PASS | The recording, 190 s with both decks playing: no run of 30 ms or more under -50 dB. |
| BIG4 | Reported | See **Timings and measurements**. |
| Pressing harder | PASS | 15:28, no crash, no dropout that isn't LR2, and the decks stayed usable. See below. |
| LR2 | FAIL | Found in the long run: the Bass swap's hole. |

### CB3: after a stopped move
Timed from the recording, where its clock is the wall clock less 00:48:00.

**As asked, on a Loop build.** The planner chose that and not a Bass swap, and I can't choose for it. The new deck had just started when I pressed `AUTO`, so something was left to clear: "Auto DJ stopped. The decks are yours." left deck 1 in a loop with `MID` and `LOW` down, and deck 2 running with every stem off. `EXIT`, stop deck 1, `AUTO`: "Loop build in 17 bars". All four stems came back, and the knobs centred.

| From | To | Level | |
|---|---|---:|---|
| 4:20 | 4:28 | Silence | Between stopping deck 1 and pressing `AUTO`. See **Looks wrong** |
| 4:28 | 5:21 | -14 dB | Full level. Round 9 was -25 to -28 dB here for 47 s |
| 5:21 | 5:32 | -17 to -22 dB | The build itself. Two other Loop builds in this recording, with no stopped move before them, dip the same |
| 5:32 | | -13 dB | Landed. "Loop build done. Deck 1 is on." at 5:38 |

**The other way round.** A Bass swap, `AUTO` just as the new deck started, both left playing. Stop the new deck, `AUTO`: "Bass swap in 10 bars", with its stems and `MID` back. -12 to -13 dB up to the swap, -14 after, and "Bass swap done. Deck 2 is on." That's where LR2's second hole is.

### The first-time user, as a summary
The full report is at the end. I checked these myself: the picker's "Folder is Empty", `1.3e…`, the cut-off capsules and deleting a playing track, from its screenshots. `MIX` replacing a stopped deck's track and the tempo carrying over, by seeing them on the Duo. The rest I didn't repeat. Its three worst:
1. **Import starts on "Folder is Empty", every time,** in the app's own folder, on a fresh small iPhone. Importing while on an empty playlist then still says the playlist's empty, so it looks as if it failed.
2. **Auto DJ and `MIX` don't say what they're doing.** `AUTO…` looks like a clipped label for nearly 4 minutes. When the move starts, the crossfader moves and a loop appears, with nothing said.
3. **On its side, the words that matter get cut off.**

Import to mixed by hand took it 1:25 upright, and `AUTO` from first press to done took 4:51, of which 3:50 was stems.

### A big library
The real 5 tracks plus 2,000 from `big_library.py`, on the Duo, with the recorder beside it. Freezes of 100 ms or more, by the freeze log. There's no video, so nothing under that shows.

| | Where | Freezes |
|---|---|---|
| Nothing playing | Launch | 718 and 257 ms in the best run, 1,816 and 541 in the worst |
| | The 15 s after launch, tied to nothing I pressed | 134, 182, 132, 253 ms |
| Both playing, recording | 10 opens and closes | None |
| | 6 hard flicks to Track 1828 | None |
| | First search after launch | 1,663 and 810 ms |
| | Second search | None |
| | `IN KEY` and `±6% BPM` on and off | None |
| | Tapping columns and `NEXT` | 103 and 101 ms |
| | Stopping the recording | 204 ms |
| | Two-finger `BROWSE` tests | 120, 103, 115, 164 ms |

- **Columns, `NEXT` and the filters** all gave the right lists.
- **On the SE, on video,** see CA1.

### Pressing harder
00:47:59 to 01:03:27, so 15:28, with a recording throughout, on the Duo. Load average up to about 470, with the other session's gate back on at low priority.

| Time | What I did | What it did |
|---|---|---|
| 00:48:05 | `AUTO`, then pressed again after the handover | "Loop build in 5 bars", then "Auto DJ stopped. Deck 2 is on." Old deck stopped, clean |
| 00:49:12 | The same, the other way | "Auto DJ stopped. Deck 1 is on." |
| 00:51:10 | `AUTO`, pressed again as the new deck started | "Auto DJ stopped. The decks are yours." Everything stayed, shown |
| 00:52:14 | `EXIT`, stop the old deck, `AUTO` | CB3. Done 00:53:38, thumbs up and down offered |
| 00:53:43 | Seek on the deck that had just stopped | It moved and stayed stopped |
| 00:54:13 | `AUTO`, pressed again as the new deck started, stop the new deck, `AUTO` | "Bass swap in 4 bars", "The decks are yours", "Bass swap in 10 bars", done 00:55:33 |
| 00:56:27 | `AUTO`, seek on the old deck | "Loop build in 30 bars". Done before my seek arrived. The seek stuck |
| 00:58:32 | `AUTO`, seek on the old deck 7 s after the new one started | "Echo throw in 5 bars". The move played out, CC12 |
| 00:59:18 | `AUTO`, stop the old deck after the handover | "Loop build in 18 bars". The move played out, done 01:00:25 |
| 01:00:59 | `MIX` | "Up next: Exhilarate", which took Gepzene off deck 2 |
| 01:01:29 | Home for 12 s in its countdown | Carried on, `MIX 55`, still recording |
| 01:02:03 | `OUT` with no `IN`, then `EXIT` | `MIX…`, then "No clean way in". See **Looks wrong** |
| 01:03:22 | Turned the mix off | "Mix off. The track playing just carries on." |

- **Gaps:** 95 runs of 30 ms or more under -50 dB in 928 s.

  | Where | Runs | Longest |
  |---|---:|---|
  | Between the two stops above, my doing, and shown | 1 | 7.96 s |
  | LR2 | 1 | 0.44 s |
  | Gepzene, on its own or nearly | The rest | 0.32 s |

  Gepzene's runs fall at the same spacing each time it plays, and the same sections match across both recordings, so they look like its own, as round 9 found. I didn't check them against its file this time, so on a track this sparse a very short dropout could hide. Skylander has none, apart from 0.28 s before its first `PLAY`. Exhilarate never played during it.
- **The tracklist:** 9 lines, each matching a change of track. History rose with them.
- **Afterwards:** deck 2's `PLAY` and clock work, with no loop, the knobs centred and every stem on, at the -2.34% under **Looks wrong**. Skylander played out to its end and stopped there, as it should, and I didn't press it again. Nothing's silent, looping or filtered that the screen doesn't show, and the closest is the silent deck under **Looks wrong**.
- **The app's log** over the last 20 minutes: 4 `CVPixelBufferCreate` errors and some Core Audio noise. No crash report.

## Timings and measurements
CPU by `top` on this simulator's own process, 30 s after 10 s of settling, stems finished, the Duo, 5 tracks unless it says. The orphan recorder was beside all of them. Other work: the Slevens test on its own simulator, in % of a core at the end of the row. "Idle" is the whole Mac's idle in `top`.

| State | Average | Peak | Round 9 | Memory | Mac idle | Beside it |
|---|---:|---:|---:|---:|---:|---|
| Idle, nothing loaded | **3.0%** | 3.6% | 12.9% | 95 MB | 56% | |
| Idle, browser open | 2.8% | 3.1% | 2.8% | 99 MB | 56% | Slevens 120 |
| Two loaded, paused | **3.2%** | 3.5% | 16.4% | 500 MB | 48% | Slevens 31 |
| Two loaded, stopped, browser open | 3.4% | 4.1% | | 498 MB | 50% | Slevens 97 |
| One deck playing | 10.7% | 11.4% | 17.0% | 500 MB | 20% | |
| Both playing and synced, tempo offset | 18.6% | 19.3% | 23.4% | 501 MB | 36% | Slevens 42 |
| Both, plus a muted stem and an echo | 18.6% | 19.2% | 28.5% | 507 MB | 44% | Slevens 98 |
| 2,005 tracks, two loaded, stopped, browser, at rest | 4.8% | 5.3% | 3.7% | 531 MB | 66% | Slevens 42 |
| 2,005 tracks, the same, a flick every 1.7 s | 17.1% | 21.9% | 26.2% | 531 MB | 61% | |
| Just after the long run, one deck playing, stretched | 13.3% | 13.9% | 17.0% | 447 MB | 27% | The other session's gate, at low priority |

- **Memory:** I can't see it running away: 447 MB after the long run, where round 9 had 509 MB.
- **Launch to a free main thread, 2,005 tracks:** 0.73, 1.52 and 1.84 s.
- **Press to plan:** about 2 to 6 s.

## First impressions
**1. Does it look like $1000 pro software?** On the wide layout, yes. It's faster to the eye than last time as well: the browser now feels like part of the screen and not something being fetched. What most breaks the illusion:
- **Words broken in half on a small phone.** "Skyl / an…" in the one place you need to read which track's on the deck.
- **The first step ends in "Folder is Empty".** It's the system's picker, but it's the first thing a new person meets, and it reads as a failure.
- **Numbers nobody chose.** 166.02 on a 170 track that nobody's touched, and once `1.3e…` in the loop key. Pro gear doesn't show you a number you can't account for.

**2. What felt slow, confusing or surprising?**
- **Slow:** only the stems, now. About 3 to 4 minutes a track here on the CPU, and that's what holds `AUTO` up.
- **Confusing:** `MIX` taking the track I'd stopped. A list that forgets where it was, after being told it wouldn't. A deck that's playing and silent.
- **Surprising, in a good way:** how quiet the app is at rest, and how it behaves under every way of cutting a move short. Every one of them ended somewhere sensible, and said so.

**3. Which control was hardest to find or hit?** `AUTO`, to find, as nothing on it says "Auto DJ" until you press it, and upright the wait reads like a clipped label. To hit: `DEL`, still at the end of a tab row. On the small iPhone, the `MORE` beside the tabs and the `MORE` on the mixer are one word for two different things.

## The first-time user: the subagent's full report
Written by the subagent on `iPhone SE Cheeks`, from 23:28 to 00:12, with its own caveats first. "FU" numbering is the task's. Its screenshots are the `fu-*` files.

**Time:** 23:28 to about 00:12, roughly 44 minutes. No crashes: the crash-report check came back empty at 23:44, 23:52, 00:03 and 00:11.


### How far to trust this

- **Project notes did affect me.** They were loaded before I started, and I can't un-know them.
  - I knew `AUTO` and `MIX` meant Auto DJ before I saw them. My 6 seconds to find `AUTO` is not evidence that it's easy to find. Nothing on screen says `AUTO` is "Auto DJ" until you press it.
  - I knew stems and Auto DJ were linked. The brief told me that too.
  - Some of my tests came from what the notes describe: starting or stopping a deck during a move, and stopping the deck `MIX` wants.
- **General DJ knowledge did too.** I read `SYNC`, `CUE`, hot cues, loop, roll and key codes like `5A` from what I already know, not from the app. A real novice gets less from them than I did.
- **"No message" means none in the frames I caught.** Frames were 1 to 20 s apart, and one gap was 52 s. A background log took a frame every 20 s or so, and that's the only reason I saw the two rating prompts. Anything that came and went between frames is invisible to me.
- **Timings include tool delay.** They show the order and rough size of things, not how fast a person would be.
- **Reasons are marked "My guess".** Everything else is what the screen showed.
- **I didn't discover things in a natural order.** I checked the empty screens first, as asked. So I was already on an empty playlist when I imported, which a first-timer wouldn't be. FU1 item 2 only happens from there.

### Stage timings

#### Upright

| Stage | From | To | Took | What got in the way |
|---|---|---|---|---|
| Icon tap to usable screen | 23:28:16 | 23:28:20 | 4 s | Opened sideways (see FU5, "Looked wrong") |
| Empty-screen checks, on purpose | 23:28:34 | 23:30:53 | 2:19 | Not counted below |
| Import: find it, leave the empty folder, select, Open | 23:30:53 | 23:31:24 | 31 s | Picker opened on an empty folder |
| Work out the import had worked | 23:31:24 | 23:31:36 | 12 s | Screen still said the playlist was empty |
| Track on deck 1 | 23:31:36 | 23:31:43 | 7 s | None |
| Track on deck 2, back to the decks | 23:31:43 | 23:31:49 | 6 s | None |
| Deck 1 playing | 23:31:49 | 23:31:56 | 7 s | None |
| `SYNC` on deck 2 | 23:31:56 | 23:32:06 | 10 s | None |
| Deck 2 playing | 23:32:06 | 23:32:12 | 6 s | None |
| Crossfade across | 23:32:12 | 23:32:18 | 6 s | None |
| **Import to mixed, by hand** | 23:30:53 | 23:32:18 | **1:25** | |
| Press `AUTO`, refused, stop a deck, press again | 23:32:18 | 23:32:30 | 12 s | Both decks were playing |
| Waiting for stems | 23:32:30 | 23:36:20 | **3:50** | Includes my cancel at 23:32:55 and re-press by 23:33:02 |
| The Auto DJ move | 23:36:20 | about 23:37:09 | 49 s | None |
| **Auto DJ, first press to done** | 23:32:18 | 23:37:09 | **4:51** | |

#### On its side (already knowing the app)

| Stage | From | To | Took | Note |
|---|---|---|---|---|
| Rotate during a running `MIX` | 23:38:42 | same | Instant | Nothing was disturbed |
| Import one file again | 23:43:53 | 23:44:17 | 24 s | Empty folder again, then no feedback |
| Three quick loads on one deck | 23:42:57 | 23:43:11 | 14 s | Last press won |
| Mix by hand: `SYNC`, `PLAY`, crossfader | 23:42:18 | 23:42:27 | 9 s | |
| `AUTO` with stems ready | 23:47:12 | 23:47:45 | 33 s | Echo throw |
| `MIX`, next track not yet split | 23:38:31 | 23:41:28 | 2:57 | Ended in "No clean way in" |

### FU1. From nothing to a mix

#### Where I wasn't sure

1. **The file picker opens on the wrong folder.** Every time: 23:31:07, 23:44:02 and 23:45:40.
   - Import opened on the "Segue DJ" folder, reading "Folder is Empty". The music was one level up and across, in My Music. It never remembered where I'd been.
   - I used the system back arrow straight away, because the brief had told me the music was in My Music. Someone without that has only "Folder is Empty" to go on. This is the app's first real step, and it starts with the word "Empty".
   - The Files app lists the same folder as "Segue DJ, 4 items", so the picker's "Empty" also looks untrue.
   - My guess: the picker shows only audio files, and those 4 items aren't.
   - `fu-import-opens-on-empty-folder.png`, `fu-files-app-on-my-iphone.png`
2. **After an import from a playlist, it looks as if nothing happened.** After Open (23:31:24) the screen still said "Nothing in this playlist yet", with only a tiny spinner at top right. Nothing said tracks had arrived. They were in All Tracks, with BPM and key already filled in, by 23:31:36. I found out by opening the list menu. `fu-import-into-playlist-looks-failed.png`
3. **Upright, nothing says which list you're looking at.** The list has no heading. All Tracks and the playlists sit behind an unlabelled icon.
4. **Upright, there's no button called Import.** The empty screen says "Tap Import", but upright it's an unlabelled blue icon. I guessed right because it was the only blue icon in that row. On its side it says `IMPORT`. `fu-empty-browser-upright.png`
5. **Getting back to the decks.** The only way is `BROWSE`, which is already lit. It worked first time, but nothing says it's the way back.
6. **`SYNC`:** I pressed it from general knowledge. 125.00 became 126.00, which looked right. I couldn't tell whether the beats lined up. There's a row of small lit segments between the waveforms that may show this, but I couldn't read it.
7. **Which deck to stop for Auto DJ.** "Auto DJ brings in a stopped deck. Stop the one you want next." is clear and I followed it. `fu-auto-both-playing-refusal.png`
8. **While it waits (23:32:30 to 23:36:20).** The message goes, and only a lit key reading `AUTO…` is left. It looked like a clipped label, not a state. I pressed it to check, which turned it off ("Auto DJ off."), so I had to press it again. See FU3. `fu-auto-waiting-no-message.png`
9. **When the move began, nothing said so.** None of the frames at 23:36:20, :25 or :32 had a message.
   - The crossfader had moved by itself from far right to centre: compare the 23:36:09 frame with `fu-auto-started-crossfader-moved.png`.
   - A loop appeared on deck 2, with `EXIT` and `4` lit as if I'd set them: `fu-auto-set-loop-on-deck-2.png`.
   - Deck 1's waveform went black, and I wondered whether it had unloaded: `fu-auto-loop-and-empty-waveform.png`.
   - By 23:37:05 deck 1 was playing at 00:29.1, earlier than the 00:34.9 where I'd left it. Nothing said it had moved back.
10. **The rating prompt.** "Loop build done. Deck 1 is on." came with a thumbs up and down. I only saw it in the background log, so it's easy to miss, and nothing said what the thumbs were for. I never pressed them. `fu-loop-build-done-thumbs.png`, `fu-echo-done-thumbs.png`

#### The contradiction in `MIX`

- At 23:38:15 `MIX` refused with "Stop the one you want next." So I stopped deck 2, which held Gepzene.
- At 23:38:24 `MIX` said "Up next: Severe Tire Damage - High Quality."
- By 23:38:31 Gepzene had been taken off and replaced, and its split at about 33% was gone. It started again at 0% when I reloaded it at 23:43:11.
- The instruction said the stopped deck's track would be next, and it wasn't. `fu-mix-up-next-replaced-my-track.png`, `fu-mix-dots-waiting.png`

#### `AUTO` and `MIX` are two doors

One is on the decks and one is in the browser. Nothing says how they differ. I knew only from the notes.

#### First `MIX` result

- The key read `MIX…` for nearly 3 minutes.
- At 23:41:23, with 2.9 s left of Houston, a message began "No clean way in. Next track starts when this…" and was cut off.
- By 23:41:28: "No clean way in. Deck 2 just started."
- So the first transition I got from `MIX` was no transition.
- My guess: the next track's split finished only about 3 s before the end, so there was no time to plan. A library that's already split may behave quite differently. Stems run on the CPU here.
- `fu-side-no-clean-way-in-truncated.png`, `fu-side-mix-count-no-clean-way-in.png`

#### On its side: what changes

**Easier:**
- Browser: the sidebar shows All Tracks and the playlists all the time, and `IMPORT`, `IN KEY` and `±6% BPM` have full labels.
- Both decks' pads and the mixer are on one screen, with bigger pads.

**Harder:**
- **Cut-off messages.** Every long one lost its second half, which is usually the instruction (FU3, FU5).
- **Titles break mid-word.** "Hous / ton", "Seve / re…", "Skyl / an…", and at worst "Se…" with "Ste…" under it. `fu-side-titles-and-stems-truncated.png`
- **Stem time left is gone** (FU3).
- **The crossfader is much shorter.** About 117 pt against about 325 pt upright. I measured these from screenshots.
- **The jog is smaller.** About 80 pt against about 130 pt upright, and its page gets narrow. `fu-side-jog-page.png`
- **The same keys change name.** See FU4.

### FU2. What it says when it's empty

| Screen | What it says | Clear what to do next? |
|---|---|---|
| Browser, no music | "No music yet. Tap Import to add music from Files, or drop audio into the Segue DJ folder in the Files app or Finder." | Yes, apart from Import being an icon upright. Opening here is a good choice. `fu-empty-browser-upright.png` |
| Playlist, after music exists | "Nothing in this playlist yet. Go to All Tracks, press and hold a track, and add it from there." | Yes. It's the only place press-and-hold is mentioned. `fu-empty-playlist-upright.png` |
| Playlist, library empty | "No music yet" | Fine, but after creating one nothing changed on screen, and I couldn't tell whether I was now in it. `fu-playlist-created-nothing-shows.png` |
| Recordings | "No recordings yet. Tap REC at the top of the screen to record your mix…", plus where they're kept | Yes. The best one. `fu-empty-recordings.png` |
| Decks | "No track loaded", all dim | Half. Dim says "not yet", but nothing points to `BROWSE` until you press something. `fu-empty-decks-upright.png` |
| Empty deck, pad or `PLAY` pressed | "There's no track on deck 1 yet. Load one from the browser." | Yes. `fu-empty-deck-refusal.png` |
| `AUTO`, nothing loaded | "Play a track first, then Auto DJ can mix out of it." | Yes. `fu-auto-empty-refusal.png` |
| `MIX`, nothing imported | "A mix needs at least two tracks." | Yes. `fu-mix-empty-refusal.png` |
| `FX` tab, empty deck | "FX pads slide: up and down for depth, left and right for the beat." | Useful, though it isn't about being empty. `fu-fx-empty-message.png` |
| `CUE`, `SLICER`, `JUMP` and `MEM` pads, empty | Dim labels; `MEM` pads are blank | Fine. A press on `MEM` gave the same refusal; I didn't press the others. |
| `STEMS` tab, empty deck | Full bright pad colours | Looked wrong: everything else is dim, and these look ready. I didn't press one while the deck was empty. |
| `SAMPLE` tab, empty deck | Bright | Right, and it's the one page that seems usable without a track. I didn't press a sound without a track loaded. |
| Jog page, empty | Dim platter, "NO TRACK" | Fine. `fu-empty-jog-page-upright.png` |
| Search, nothing found | "No Results for "zzz". Check the spelling or try a new search." | Yes. `fu-search-no-results.png` |
| Filters, nothing fits | "Nothing fits right now. Nothing here is in key or close in tempo with what's on the deck. Turn off IN KEY or ±6% BPM to see the rest." | Yes, and it also explains the two filters. `fu-filter-nothing-fits.png` |
| Cue list, nothing saved | "Nothing saved yet. Set hot cues on the CUE pads, and save cues and loops on the MEM pads." | Yes |

**Not clear:**
- `NEXT` on an empty library lights up and does nothing, with no message. `fu-next-empty-no-effect.png`
- `REC` with nothing loaded just starts, and saves a silent mix: "Mix 2026-11-03 23.30.33, 0:13, 61 KB". `fu-rec-on-empty.png`, `fu-saved-silent-mix.png`

### FU3. Stems

**Do you notice?** Upright, yes: the deck's header reads "Stems 2%" as soon as a track loads. On its side, barely: on any tab but `STEMS` that line becomes "Ste…". `fu-stems-waiting-and-percent.png`, `fu-side-titles-and-stems-truncated.png`

Upright, you see that something is happening but not what stems are. The only explanation is in Settings ("Splits each track in the background…"). I saw no stem status in the browser, so you can't tell which tracks are ready.

**Would you know why Auto DJ won't start?**
- For a moment, yes: "Auto DJ is waiting for the stems to finish." is plain. `fu-auto-waiting-stems-message.png`
- It had gone by my next look 18 s later. For the remaining minutes (nearly 4 in all) the only trace is `AUTO…`. Nothing ties that key to the percentage on the deck.
- Someone who looks away during those seconds has a lit key and no reason. `fu-auto-waiting-no-message.png`

**Is it clear how long it'll take?**
- Upright, roughly. Each deck gives its own figure, with no overall one. At 23:33:20 it read "2 min" and "4 min", and the real wait was 3:00. You have to work out that the longer one is the one that counts.
- On its side, no. There's only a percentage, and only on the `STEMS` tab. `fu-stems-tab-side.png`
- Upright on the `STEMS` tab, the same: a small bar with a percentage. `fu-stems-tab-upright.png`
- When a split finishes the line simply disappears. I saw no "ready" message.

**Was the estimate right?** About right, and calm. It never went up.

| Time | Houston (4:50) | Skylander (6:00) |
|---|---|---|
| 23:31:49 | 2% | "Stems waiting" |
| 23:32:02 | 10%, 3 min | "Stems waiting" |
| 23:32:07 | 12%, 3 min | 4% |
| 23:32:11 | 14%, 3 min | 6%, 5 min |
| 23:32:30 | 22%, 3 min | 12%, 4 min |
| 23:32:55 | 32%, 3 min | 21%, 4 min |
| 23:33:20 | 42%, 2 min | 29%, 4 min |
| 23:33:47 | 52%, 2 min | 38%, 3 min |
| 23:34:24 | 68%, 1 min | 50%, 3 min |
| 23:34:53 | 80%, 1 min | 60%, 2 min |
| 23:35:00 | 82%, 40 s | 63%, 2 min |
| 23:35:21 | 92%, 15 s | 69%, 2 min |
| 23:35:46 | done | 82%, 1 min |
| 23:36:09 | | 99%, 5 s |
| 23:36:20 | | done |

- **Houston:** said 3 min at 23:32:02 and took about 3:30.
- **Skylander:** said 5 min at 23:32:11 and took about 4:05. It sped up once Houston finished: "2 min" at 69% turned out to be under a minute. That's the only real miss, and it errs the good way.
- **Gepzene alone (3:48):** said 2 min at 5%, and was going at about 1% a second, so roughly right. Then `MIX` threw it out.
- **Severe alone (6:51):** about 2:50, with no time-left reading on its side.

**Stem pads work before the split is done.** `NO VOCAL` at 43% and `DRUMS` at 12% both responded. I can't judge what they do at that point, because I can't hear.

**With "Prepare stems on load" off:**
- The slot on the deck reads a grey `STEMS`, which doesn't look like a button.
- `AUTO` says "Auto DJ needs stems, and this track doesn't have them." It doesn't say how to get them. `fu-auto-needs-stems-upright.png`
- I got a split going after tapping the grey `STEMS` and then a stem pad. I can't say which of the two started it. `fu-stems-off-pad-tap.png`
- Houston, which had already been split at 23:35, got the same refusal when reloaded with the setting off. Settings says "Split tracks are kept, so they load instantly next time." With the setting back on and a reload, its stems were there at once. So the refusal "doesn't have them" reads as untrue. `fu-auto-refuses-already-split-track.png`

### FU4. What needs explaining

Controls I couldn't work out from looking at them:

**Browser**
- **`NEXT`:** lights up and reorders the list by a rule it never states. It also removes the track playing on the other deck: with `NEXT` on there were 4 rows, not 5. `fu-next-hides-playing-track.png`
- **`KEY` and `±6%` (upright):** key of what, 6% of what? The empty-filter message is the only explanation, and you only see it if nothing matches.
- **Pink highlight on one row's key (`5A`):** no explanation. My guess: it matches the deck's key.
- **Key codes and their colours:** nothing explains them.
- **`MIX`:** see FU1. What list does it mix, in what order?
- **Sidebar icon (upright):** no label.

**Decks and waveforms**
- **`AI` with a green dot:** nothing links it to stems. It appears where the percentage was.
- **`CHORUS 26.1`, `DOWN 13.3`, `UP 1.4` on the waveform:** I guessed section and bar.beat. `DOWN` and `UP` aren't obvious.
- **The row of small lit segments between the waveforms:** no idea.
- **`4` between `<` and `>`:** 4 what? Then it reads `1/2`, `25`, `21` or `2.7`.
- **`IN`, `OUT`, `RELOOP`:** fine if you know DJing. `OUT` on its own does different things (FU5).
- **`LOOP` pads and `ROLL` pads:** both are sets of beat fractions, with nothing to tell them apart.
- **`DEL`:** small, on `CUE` and `MEM`. It lights red and the next pad deletes. Good once you know, and "Deleted hot cue A" with `UNDO` is reassuring.
- **`MORE >` on the tabs:** I expected a menu. It swaps that one tab through `MEM`, `SLICER`, `JUMP` and `SAMPLE`, and the word `MORE` goes away. You can't see what's there or how many there are.
- **`MORE` on the mixer:** the same word, but a different thing (a panel).
- **`SOLO` V, I, B, D:** readable once you've seen the row above.
- **`SAVE CUE`, `SAVE LOOP`, `1/1`, `LIST` on `MEM`:** `1/1` is a page number, I think.
- **`FX` page:** `1/2`, `DEPTH`, V, I, B, D, `OUT`. No idea what `OUT` does here. Pad names like `SPIRAL`, `TRANS`, `BRAKE` and `BACKSPIN` aren't explained.
- **`SET`, `Q` and `VOLUME` on `SAMPLE`:** `SET` opens a clear "Pad 2" sheet with "Grab Deck 1's Loop", once you press it.
- **Jog page:** `Q`, `SLIP`, `KEY`, `REV`, `KEY SYNC`, the `±0` with `–` and `+`, `MASTER`, `BEAT JUMP`, and the tempo-range key, which I saw read `±10`, `WIDE` and `±6`. `KEY` lit and `KEY SYNC` beside it is especially unclear.
- **`MASTER`:** lit orange by itself, and it moves between decks.
- **`LIM`:** a small light that went red in normal play (for example 23:33:47, 23:38:09, 23:43:45). Is that bad? Should I act? It says nothing.
- **The `AUTO 5`, `AUTO 10`, `MIX 134` numbers:** only the "Loop build in 12 bars." message hints at the unit. 134 going to 110 in 38 s fits bars at 148 BPM, but I had to work that out. `fu-side-mix-110.png`
- **"Loop build" and "Echo throw":** jargon, shown with no explanation.

**The same control under different names**
- `ACAPELLA` and `NO VOCAL` upright are `VOX` and `INST` on its side. `INST` is also the name of a stem pad, and it means something different there.
- `SYNC` on the pads page is `BEAT SYNC` on the jog page.
- `KEY` upright in the browser is `IN KEY` on its side. `±6%` is `±6% BPM`. These two are harmless.

**Plain and good**
- The row `1` and `2` load keys: dim means no.
- The `BPM ▾` menu, once you open it.
- `PLAY` and `CUE`.
- The crossfader labelled 1 and 2.
- Stem pads with their icons.

### FU5. What happens when you do it wrong

#### Clear refusals (all good)

| What I did | What it said |
|---|---|
| `PLAY` or a pad on an empty deck | "There's no track on deck 1 yet. Load one from the browser." |
| `AUTO` with nothing playing | "Play a track first, then Auto DJ can mix out of it." |
| `AUTO` with both playing | "Auto DJ brings in a stopped deck. Stop the one you want next." |
| `AUTO` again while waiting | "Auto DJ off." |
| Load onto a playing deck | "Deck 2 is playing. Stop it first." Also "Deck 1 is playing. Stop it first." |
| Start a deck during the countdown | "Auto DJ stopped: you started deck 1 yourself." `fu-auto-stopped-you-started-deck.png` |
| Stop a deck during the move | "Auto DJ stopped: deck 2 was stopped. Deck 1 is on." `fu-auto-stopped-deck-jumped.png` |
| Turn `MIX` off | "Mix off. The track playing just carries on." |
| Delete a hot cue | "Deleted hot cue A", with `UNDO` |

These are the strongest part of the app.

#### Clear on the upright screen, cut off on its side

The capsule fits the first half of the sentence, and the second half is the part you act on.

- "Auto DJ brings in a stopped deck. Stop the o…" `fu-side-refusal-truncated.png`
- "Play a track first, then Auto DJ can mix out of…"
- "Auto DJ needs stems, and this track doesn't…" `fu-side-auto-needs-stems-truncated.png`
- "No clean way in. Next track starts when this…" `fu-side-no-clean-way-in-truncated.png`

#### Silently ignored, or no feedback

- **Import a track already in the library** (23:44:17, 23:45:52): nothing happens and nothing is said. Four duplicates were correctly skipped, but I couldn't tell. `fu-reimport-no-feedback.png`
- **Create a playlist:** nothing changes on screen.
- **Add to Playlist:** the menu closes and only the small count changes.
- **Re-analyse:** no sign of anything, 52 s later. A message may have come and gone.
- **`NEXT` on an empty library:** lights up, nothing else.
- **`IN` on a stopped deck, then `OUT`:** nothing happens, `IN` stays lit. `RELOOP` did nothing either. `fu-in-then-out-stopped-nothing.png`
- **Turn all four stem pads off:** the waveform goes black and the meter falls, with no message. It's logical, but looks like a failure. `fu-all-stems-off-black-waveform.png`

#### Allowed, and arguably shouldn't be

- **Delete a playing track.** "Delete from Library" removed Gepzene while it played on deck 2, with no confirmation and no undo that I saw. The deck carried on playing a track that was no longer listed. Importing it again brought it back. Compare deleting a hot cue, which offers `UNDO`. I didn't test whether a deleted track's cues and grid edits survive. `fu-deleted-playing-track-no-confirm.png`, `fu-deleted-track-while-playing.png`
- **`RELOOP` on a stopped deck that had a loop starts it playing,** with no warning. `fu-reloop-starts-stopped-deck.png`
- **`OUT` with no `IN` sets a loop at once,** and what you get depends on where the deck is. On a stopped deck at the start: a `1/2` loop. Near the start while playing: `25`, then `21`. Elsewhere while stopped, see the next point. `fu-out-without-in-half-beat.png`
- **`OUT` on a stopped deck once showed `1.3e…`** in the loop-size slot, with `EXIT` lit: a clipped number in scientific notation. I saw it once and didn't reproduce it. `fu-out-without-in-1.3e.png`
- **`SYNC` from 125 to 148, up 18.4%,** with no warning. It stays that way: the deck kept +18.4. `fu-sync-jump-18-percent.png`
- **`REC` with nothing loaded** saves a silent mix.

#### Handled well

- **`PLAY` straight after a load:** the deck was playing by 23:46:09. Tool delay means I can't be sure the load hadn't already finished when the press landed, so this is weak evidence.
- **Three quick loads on one deck:** the last press won.
- **`PLAY` on a track that has run out:** starts from the top.
- **Home during play, back a minute later:** still playing, and back at once. `fu-back-from-background.png`
- **Rotate during `MIX`:** no effect.

#### Looked wrong, though it may be working

- **A deck's BPM doesn't match the list.** Gepzene is 128.0 in the browser and read 129.02 on the deck. Severe is 148.0 and read 145.69, then 151.55. Nothing says why. My guess: the deck keeps the previous track's fader offset, as +2.4 stayed on the fader. A new track playing at a speed you didn't choose, with no sign of it, is confusing. `fu-bpm-differs-from-list-129.png`, `fu-bpm-differs-from-list-151.png`
- **After Auto DJ was stopped by my starting deck 1,** that deck read 128.00 against the other's 126.00. `fu-auto-stopped-you-started-deck.png`
- **Stopping deck 2 mid-move:** deck 1's position jumped from 00:07.3 to 00:31.3 between two frames. The message explains the end state, not the jump. `fu-auto-stopped-deck-jumped.png`
- **The loop-size digit showed `42`** with the two numbers overlapping, during a change (23:38:02).
- **A brief letter tile instead of cover art** for Gepzene after it came back (23:45:52), right by 23:46:03.
- **The app opened sideways** on an upright Home Screen, with the logo drawn sideways, and stayed so until I rotated both ways. My guess: the simulator's stored orientation, not the app. `fu-launch-logo-sideways.png`, `fu-first-screen-sideways.png`
- **The red top LED and `LIM`** with both decks up and the crossfader in the middle (23:43:45). I don't know whether that's a problem.
- **A few blank seconds** while the import picker opened (23:31:03). `fu-import-blank-sheet.png`

### What I didn't get to

- A full `MIX` set. I stopped it after about 3.5 minutes and one fallback, so I never saw a real planned move under `MIX`.
- Pressing a rating thumb, `UNDO`, or anything in a recording's tracklist, share or `…` menu. I didn't play a recording back.
- DJ library (XML) import, dropping files in the folder, backup and restore.
- Pressing `FX` or `SLICER` pads with a track loaded, and hot cues beyond setting and deleting one.
- Whether a jog drag does the right thing: I tried one, and the frames don't settle it.
- Inside the Segue DJ folder in the Files app. My taps on it didn't open it, and I can't say whether that was the tool. `fu-files-app-on-my-iphone.png`
- Whether deleted tracks keep their cues.
- Anything about sound or haptics, as agreed.
