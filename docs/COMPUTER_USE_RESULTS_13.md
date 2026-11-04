# Hands-on results, part 13, 2026-11-04

Commit tested: 95ce321
Device: iPhone Duo simulator, unfolded (951×669 pt), and `iPhone SE Cheeks` on its side (667×375 pt), iOS 27.2, both fresh installs. Also `iPad Air 13-inch (M4)` (1366×1024 pt) for video of the slide.
Tooling limits:
- **The Duo hasn't been restarted, so its stuck recorder is still running** and there's no video on it. FA is blocked. As the task says, what moves a lot ran on the small iPhone, and each result below says where it ran. With the Duo's app closed the recorder wrote only about 9 MB a minute. Its file reached 95.7 GB at 09:00. Free disk was never under 40 GB: lowest 40.9 GiB (41,857 MiB), at 09:45.
- **My tool can't press during the slide by itself.** My next call lands 0.78 s after `BROWSE` (timed on video, 2 of 2), and the slide's over by about 0.2 s on the small iPhone. So for FB1 I paused the app with SIGSTOP, sent `BROWSE`, thawed it after a set time and sent the second press straight after. On the small iPhone, video timed the presses that landed inside the slide at 0.105 to 0.17 s after it began. **The Duo has no video, so there I know each press's result but not its exact moment.** It's still a tool's touch and not a finger.
- **The Duo's slide was judged from stills** at about 12 a second. For frame-by-frame I used video on the iPad, with two tracks playing, driven by `CHEEKS_SELF_TOUR=browser`, so nothing was touching it. That's Debug on a busy Mac. I installed this build over the iPad's copy, and closed it afterwards.
- **Not judged:** how anything sounds, haptics and the headphone output. Levels and gaps come from recordings.
- **Double-tap can't be done here:** two tool calls don't land within 0.3 s. So a double-tap on a knob or fader is untested.
- **CPU ran on the small iPhone,** so it can't be compared directly with last round's Duo numbers.
- **Beside the measuring:** `cheeks-6d` stayed off both simulators and the CPU. `CGPDFService` (45 to 60%), `WindowServer` and a `log stream` from another simulator (about 20%) were running. An `xcodebuild archive` of another project ran at some point. The Mac was 51 to 69% idle by `top` during the CPU readings.

## Summary
53 scripted tests, counting FB3's six cases apart: **48 PASS, 2 FAIL, 3 BLOCKED** (FA1 to FA3, the stuck recorder). The two fails are N4 and N5, with N6, N7 and N8 on top of those. **No crashes:** no Cheeks or Segue crash reports. The first-time user got its full time, 46 minutes on the small iPhone, and found the other three problems below.

**FB1, the one that counted first, passes.** 24 presses with `BROWSE`, none of which set a wrong cue:
- `PLAY` straight after closing, as my next call: started the deck, 6 of 6.
- `PLAY` pushed into the slide: 8 started and 4 did nothing. Three of the 4 arrived together with `BROWSE`, before anything had moved, and the other's on the Duo, untimed.
- A pad pushed into the slide: set the pad I aimed at, 4 of 4.
- A row's `1` pushed into the opening slide: loaded that row, 2 of 2.

**N1 passes:** all four long messages are whole on the Duo. **N3 passes in every case but one:** a track that fades out more than 30 s before its end.

The long run took 15:15 of `MIX` and `AUTO` on the small iPhone, with 15 takeovers, and Loop builds, Echo throws, a Vocal ride and a Brake drop played out, but no Bass swap. Nothing was left silent, looping or filtered that the screen didn't show. Every gap of 0.25 s or more is Gepzene's own, or before I pressed `PLAY`.

The problems, most important first:
1. **N6: `MIX` doesn't go through "the whole list".** It starts after the row that's playing. From row 4 of 5 the first-time user got two tracks, then nothing. The code does this on purpose, but the note says otherwise.
2. **N7: `MIX` and `AUTO` leave the master silent while they wait for stems,** if the crossfader's away from the playing deck: up to about 100 s for me, and about 80 s for the first-time user. I saw it with both keys.
3. **N4: a track that fades long before its end still leaves silence with the next one ready.** 25.1 s under -50 dB, on a track I made for this. Anything within the last 30 s is fine.
4. **N8: after a plan's been made, the `FILTER` knobs and the key disagree.** I set `DUB`, and after a move the knobs read `FILTER` while the key still says `DUB`. The first-time user saw it twice and I saw it once, right through.
5. **N5: a gap opens between the panels during the slide.** Up to 381 pt on the iPad and about 155 pt on the Duo, gone within about 0.25 s. No flash and no jump, but the task asks for no gap, so it's a fail. It may not matter at full speed: I can only see it frame by frame.

## Failures
### N4 (FB3): a track that fades long before its end leaves silence with the next one ready
- Steps: a test track whose music ends at 0:55, followed by 55 s of silence (1:50 in all). Skylander on the other deck with no stems yet. `PLAY`, `AUTO` at 0:42.
- Expected: the next track starts once this one has nothing left to hear.
- Actual: the deck ran on through the silence until 30 s from its end, then stopped, and Skylander started. The recording has **25.1 s under -50 dB**, from 14.9 s to 40.0 s. It says "If this track ends first, deck 2 starts", so nothing's misleading, but it's a long silence.
- The same music with 25 s of silence after it (1:20 in all) is clean: Skylander came in as the music ended, with no silence at the changeover on the recording.
- Why, by the code: `hasNothingLeftToHear` only looks in the last `tailToSearch` = 30 s (`AutoDJ.swift:427`, `:440`).
- I only tried `AUTO`, not `MIX`. I don't know how often a real track has this.
- Screenshot: none that shows it better than the numbers.

### N5 (FB2): a gap opens between the panels during the slide
- Steps: open and close the browser with both decks playing.
- Expected: one thing moving, with no gap opening.
- Actual: the decks' side and the mixer move apart and come back, with black between them. Frame by frame on the iPad (1366 pt wide, 120 frames a second):

  | Slide | Black gap between | Biggest | After 0.1 s | Gone by |
  |---|---|---:|---:|---:|
  | Closing | deck 1 and the mixer | 381 pt | 101 pt | 0.21 s |
  | Opening | the browser and the mixer | 341 pt | about 233 pt | 0.25 s |
  | Opening | the mixer and deck 2 | 60 pt | 8 to 60 pt, changing every frame | about 0.25 s |

- **Mixer and deck 2 go out of step on opening:** the mixer's edge moves on every second video frame and deck 2's on every frame, so the gap between them opens and shuts as they go. That's the UIKit and SwiftUI difference you asked me to watch.
- On the Duo, from stills: up to about 155 pt between the browser and the mixer, and the mixer overlapping deck 2 by about 24 pt in one early frame of opening.
- **No flash and no jump at the end,** either way, on any of the three. Pressing `BROWSE` twice quickly turned round with no flash in Duo stills.
- **A wait on the iPad:** the worst gaps between changed frames were 0.14 to 0.16 s, in 8 of the 16 slides. Three came right after a slide's first changed frame, and the moving frame after that arrives already partway across, which is why the first gap's so wide. The other five came late in a slide. Debug, on a busy Mac, while recording, and the small iPhone's video didn't show that first wait.
- I have no frames of the old slide, so I don't know whether it did the same. All of it's over in about a quarter of a second, and I can't say whether anyone would see it.
- Screenshots: `fb2-ipad-gap` (closing, then opening), `fb2-mid`, `fb2-mid2`, `fb2-p3`, `fb2-se-open`

### N6: `MIX` starts after the playing row and not at the top of the list
Found by the first-time user. It isn't one of the scripted tests.
- Steps: All Tracks with five tracks, row 4 playing, press `MIX`.
- Expected: the note says "Auto DJ through the whole list on screen, in the order it's showing".
- Actual: it played row 5 and stopped, with rows 1 to 3 never played. Run once to the end.
- By the code it's on purpose: `queue.removeFirst(here + 1)` drops everything up to the playing track (`AutoDJ.swift:236`).
- So either the note or the behaviour should change. The first-time user's suggestion is to say at the start how many tracks that leaves.
- The first-time user couldn't say whether a message ended it, as "Added to Friday night" may have covered it.
- With both decks stopped, `MIX` started from row 1 and played a 4-track playlist through to "That's the end of Friday night." So this is about a mix started mid-list.
- Screenshots: `fu-mix-pressed`, `fu-mix-ended`, `fu-h-mix`

### N7: `MIX` and `AUTO` leave the master silent while they wait for stems
Found by the first-time user, and I repeated it.
- Steps: crossfader all the way to deck 2. Deck 1 playing and deck 2 stopped with stems still to come. Press `AUTO`, or `MIX` in the browser.
- Expected: the rule is that `AUTO` never leaves silence with the next track ready. `AUTO` with stems ready opens the crossfader at once: "Loop build in 16 bars. Crossfader to the middle, to hear both."
- Actual: the crossfader stays put and the master meters stay dark until the stems finish.

  | Who | Key | How long silent |
  |---|---|---|
  | First-time user | `MIX` | About 80 s, and the start of the recording was silent |
  | Me, 10:53 | `AUTO` | Dark for the 10 s I held it, at 5 to 17%, and I called it off |
  | Me, 10:53:47 | `MIX` | Up to about 100 s: dark at 10:54:38, at 68%, and centred with the meters up by 10:55:28 |

- A person put the crossfader there, but deck 1's own meter is full, the key's lit and nothing says the master's silent. The simulator's slow split makes it longer than it may be on a phone.
- **`MIX` also made the split start again:** it loaded the same track back onto deck 2, and `Stems 22%` became `Stems 2%`.
- Screenshot: `n7-silent-while-waiting`, `fu-mix-crossfader`

### N8: the `FILTER` knobs and the key disagree after a plan's been made
Found by the first-time user, and I repeated it on the small iPhone.
- Steps: `MIXER`, press the key to `DUB`. The knobs read `DUB`. Press `AUTO`.
- Actual:

  | Step | Knobs read | Key reads |
  |---|---|---|
  | `AUTO` pressed, plan made | `FILTER`, at once | Not checked |
  | `AUTO` off | `DUB` | Not checked |
  | Move finished | `FILTER`, and stays | `DUB` |

- The next press of the key then goes on from `DUB` and skips it, as the first-time user found.
- Why, by the code: `prepare` sets `colorFX = .filter` on both decks (`AutoDJ.swift:595`, `:606`). The key shows `dj.colorFX`, which isn't touched (`DJEngine.swift:33`). So the knobs' label looks true of what they do, and the key's the one that's wrong. I can't hear it.
- Screenshot: `filter-label-after-move`, `fu-filter-mode-check`, `fu-filter-label-check`

## Blocked
**FA1 to FA3** need video on the Duo, and it hasn't been restarted. For FA1's question I do have the iPad, with two tracks and both decks playing, over 16 slides: the worst gap between changed frames was 0.16 s. That isn't FA1, which asks for 2,000 tracks on the Duo.

## Looks wrong
**Mine:**
- **A message and the key give different counts.** Since the key now counts to the move's real start, the capsule's count is 1 or 2 bars higher, in all 12 shots where I had both: "Loop build in 6 bars" with `AUTO 4`, "Brake drop in 7 bars" with `AUTO 5`, "Echo throw in 40 bars" with `AUTO 39`. Some of that's the moment between the press and my shot. (`fc4-a`)
- **"The stems are ready. Auto DJ is choosing a move." is up for about 0.6 s,** and the key's already showing a number by then. `AUTO…` lasted 0.45 s. Too short to read. On a slower phone it might be longer. (`fc5-stems-ready`)
- **A list with the same track twice logs faults.** Opening History with a track in it twice gave 4 SwiftUI lines ("the ID … occurs multiple times"), at 10:41:18, and the first-time user's log has 3 at 10:16:08. The rows look right. SwiftUI's lists can misbehave with repeated IDs, and I didn't see that happen.
- **With `NEXT` on, a load re-sorts the list straight away,** so a second quick press lands on a different row. It caught me at 09:04, where the `2` I aimed at Houston's row landed on another. Anyone loading two tracks in a row could meet it.
- **`RELOOP` after handing back from a Loop build.** At 09:43 I pressed `AUTO` during a build: "Auto DJ stopped. The decks are yours. Deck 1 is still looping.", with a 4-beat loop. `EXIT` then `RELOOP` came back as a 16-beat loop, the deck at 1:34.8 from 1:37.1. So the loop it hands back isn't the one you left. (`reloop-after-build`)
- **"Brake drop starting" comes after the brake.** At frames 1.5 s apart: old deck's clock slows from about REC 13:08, the new track's level arrives on the recording about REC 13:10, and the message and `AUTO` come at REC 13:11, with the old deck stopped. One Brake drop, from frames I didn't keep. Loop builds were right (FC4).
- **"FX pads slide…" is up for about 2.5 s,** two lines and 14 words, and it only shows once. (`n1-fx`)
- **Which move you get changes from one press to the next.** Six `AUTO` presses in a row gave three Bass swaps and three Echo throws, from different places in the track. It's fine by itself, but it made a Loop build hard to get for FC3.
- **A press with the slide's first frame does nothing,** 4 of 12 pushed `PLAY`s. That's what you said it'd do in the first 40 ms, and it's better than a wrong cue.
- **A press 1 pt from a pad's bottom edge did nothing:** on the Duo at y 658, with the pad drawn to about y 658.5, and y 652 landed. One press, and no system gesture came of it. (`c5-bottom`)

**From the first-time user** (section numbers are in the report at the end):
- `MIX` undoes a tempo set on a stopped deck, without saying: 155.34 went back to 170.00.
- `MIX` replaces what's on the decks without asking, and "Up next" only says so afterwards.
- A held slice during a mix says "The mix will carry on when deck 2's loop ends." and nobody set a loop. I held one while a mix waited for stems and that message didn't show, so it may need a plan to have been made.
- "Touch a control to take it back" gives no sign it has: the crossfader stayed left of centre after the move, with nothing to say so.
- The lit `MIX` key's note is `AUTO`'s, and it says "press AUTO to call it off".
- `NEXT`'s note doesn't say that what's been on air goes last, so 170 BPM can come above 126.
- A sort chosen on All Tracks carries into a playlist, so its built order's gone from view without saying why.
- The Recordings sheet says "Tap REC" while `REC` is running. A recording's playback has no time and no way to move through it.
- The import picker opens on an empty folder, which you'd listed as still wanting a look.
- `MASTER` means three things on the small iPhone: the top bar's readout, the jog page's key and a knob in `MIXER`.
- Section names look coarse on Houston: see FC9.

**Fault lines (FC11):** opening and closing the browser logs none now, on the Duo over 90 minutes with about 40 slides, or on the small iPhone. The first-time user's run has 118 lines from `AnimationKit`, about 'bounds' and 'position'. They come from a list row's long-press menu: I got 6 lines from one menu at 10:56:12, and none from the mixer sheet or the browser. It's the system's menu, so it may not be yours to fix.

## Stale sentences
- **Task, Setup:** "writing about 118 MB a minute". Line 91 has the right figure, up to about 650 MB, and it's about 9 MB with the Duo's app closed.

## All results
| Test | Result | Notes |
|---|---|---|
| FA1 | BLOCKED | Duo not restarted. iPad, 2 tracks: worst gap 0.16 s |
| FA2 | BLOCKED | Duo not restarted |
| FA3 | BLOCKED | Duo not restarted. Small iPhone's sweep is under B2 |
| FB1 | PASS | No wrong cue in 24 presses, on both simulators. Detail under Timings. `AUTO` in the slide does nothing, 2 of 2, and works at 0.78 s |
| FB2 | **FAIL** | N5: a gap opens. No flash and no jump. Two quick `BROWSE` presses turn round cleanly |
| FB3 running out | PASS | Small iPhone, 40 s left, fader down, crossfader away: "Auto DJ is waiting for the stems. If this track ends first, deck 2 starts." At -04.4, where Exhilarate's sound ends, deck 2 starts with fader up and crossfader centred. On the recording Exhilarate falls to -51 dB at 38.0 s and Gepzene's first hit is at 38.15 s. `fb3-auto-first-message`, `fb3a` |
| FB3 stems finishing late | PASS | 99% with 8.3 s left: "No clean way in from here. Deck 2 starts when this one ends.", `AUTO…`, then "No clean way in. Deck 2 just started." `fb3b2-s`. With 91% at the end: "The stems didn't get there in time. Deck 2 just started." |
| FB3 no clean way in | PASS | Stems ready, about 10 s left: the message, `AUTO…`, starts at -04.4. `fb3c` |
| FB3 `AUTO` again | PASS | Both waits: "Auto DJ off.", and deck 2 stays stopped through the end in the one I ran out. `fb3d-s`, `fb3e` |
| FB3 starting the waiting deck | PASS | Both waits: "Auto DJ stopped: you started deck 2 yourself." Both play. `fb3f` |
| FB3 fades long before its end | **FAIL** | N4: 25.1 s of silence with 55 s of tail. Clean with 25 s of tail |
| FB4 | PASS | Duo: "Exhilarate's file is missing…", "FX pads slide…", `RELOOP` with no loop and "Auto DJ stopped: deck 1's loop was changed. The decks are yours." all whole on two lines. Short ones look as they did. `UNDO` 4 of 4. Thumb pressed about 2 s after it showed, on the small iPhone: "Got it. More like that.", and saved to `auto-dj-ratings.json`. `UNDO` within about a second of the delete. My tool can't press on the first frame. No message with keys ran to two lines, so I couldn't check their line-up. `n1-*`, `thumb-pressed` |
| FC1 | PASS | Small iPhone, 11 starts at different moments with `CUE` between. 9 on the same beat of the bar: 10.1/27.1, 2.3/33.3, 1.2/45.2, 10.4/2.4, 10.2/39.2, 9.4/`DOWN` 1.4, 2.3/43.3, 2.4/45.4 and 2.2/48.2. 2 read one beat apart in the one shot I took: 2.1/43.2 and 10.4/47.3. I read those as the labels changing at slightly different moments, as locked decks read a beat apart in 2 of 20 samples. From a cue by a downbeat (`CHORUS` 8.4 to 9.1), it fitted the other deck rather than starting on the cue, 3 of 3. From the very start of a track it went on, 3 of 3, as it can't go back. `SYNC` with both playing: 25.1/6.2 amber became 26.3/7.4 green, the nearest beat. `fc1-started-in-bar`, `fc1-sync-playing` |
| FC2 | PASS | `NEXT` puts the deck's track and what's been on air last. `MIX` said "Up next: Houston", not the Gepzene just played. A track that was only loaded and never heard stays in with the rest. `fc2-mix-next` |
| FC3 | PASS | Stopped by `EXIT` (Duo) and after one that finished (small iPhone): "There's no loop to go back to yet. Press a loop size, or IN and OUT.", and the deck stays. Pressing a size key during the build (small iPhone): "Auto DJ stopped: deck 1's loop was changed. The decks are yours.", 8-beat loop, new deck stopped, and still in the loop 20 s later. `fc3-size-key-stays` |
| FC4 | PASS | Key counts to 1, reads `AUTO`, and "Loop build starting" comes 0.7 s later with `EXIT` lit and the new deck running. `fc4-a` |
| FC5 | PASS | Seen with fast frames, for about 0.6 s. See Looks wrong. `fc5-stems-ready` |
| FC6 | PASS | Slides of 6, 7 and 8 pt keep it lit. A tap, a 0.2 s press and a 3 pt wobble turn it off. It needs a real finger, as you said. `fc6-lit-pad` |
| FC7 | PASS | Houston's jog: tempo, time and key all readable. `fc7-jog-houston` |
| FC8 | PASS | Each true as far as I can try. `AUTO`: bars, %, and `…` all seen. `BEAT BLOCKS`: mirrored, red first. `BEAT SYNC`: bars, and the tempo fader takes it off (`fc8-sync`). `BEAT JUMP`: the `JUMP` pads have 1 beat either way (`fc8-jump`). `CUE`: says what it does. `WAVEFORM`: `UP` and `DOWN` seen. Can't check `CUE`'s output line here |
| FC9 | PASS | Names change on screen when stems finish: `CHORUS 1.1` to `INTRO 1.1`, with the strip's colours, about 3:20 after loading. Every `UP` is 4 bars before a `CHORUS`. List under Timings. `fc9-names-change` |
| FC10 | PASS | 22 presses seen on video with stems splitting, 0.3 to 1.1 s apart and back to back: all changed the page. Not repeated |
| FC11 | PASS | 0 fault lines from opening and closing. See Looks wrong for where the others come from |
| A1 | PASS | Duo, 4 of 4: default and 0.2 s, paused and playing. Cue comes back and the capsule goes. A press after the capsule's gone is too late, which caught me once. `a1-undo` |
| A2 | PASS | Duo: "Deck 1 is playing. Stop it first.", hand, no load. The row's `Deck 1` action says the same. Small iPhone on video: the row's key moves about 0.5 pt either way by my measure, for 0.25 s. Last round's measure was about 3.5 pt, on the key's own edge, so these aren't comparable. `a2-refused` |
| A3 | PASS | Small iPhone: table under Timings |
| B1 | PASS | Small iPhone on video: 4 opens and closes, no lit LED in 398 frames. Control: 265 frames lit in the launch video. Duo not on video |
| B3 | PASS | Duo: right of `MASTER 1 125.00`, whole. `a2-refused` |
| B4 | PASS | Small iPhone: 11 of 11 green and centred, over 2:14. `b4-marker` |
| C1 | PASS | Duo: index lines on the tick and the LED. `c1-caps` |
| C2 | PASS | Duo, on the right side only: 2 pt stays, 4 pt leaves, back to 1 pt catches |
| C3 | PASS | Duo: mixer stays, field visible. `c3-keyboard` |
| C5 | PASS | Duo: `PLAY` at y 645 on both decks and a pad at y 652, first time. A press at y 658, on the pad's very edge, did nothing: see Looks wrong. No system gesture, and no empty strip. `c5-bottom` |
| C6 | PASS | Duo: `BROWSE`, `REC` and the gear at y 3, first time |
| D2 | PASS | Small iPhone on video: each pad flashes near white and settles in 0.2 to 0.5 s. Held slicer pad clearly brighter. `d2-slicer-held` |
| D3 | PASS | Small iPhone, fast frames: `SIREN` flashes, then stays lit about 2.3 s after a quick tap. One shot of mine at about 0.3 s and one of the first-time user's caught it unlit, which I can't explain. `d3` |
| D4 | PASS | Small iPhone: `IN` lit, marker on the overview. `d4` |
| D11 | PASS | Small iPhone: the bar follows a drag along it. `d11` |
| G1 | PASS | Small iPhone: `SET`, `Q`, `VOLUME`, `STOP`, and pads fire |
| G2 | PASS | Only `Grab Deck 1's Loop`, with a loop on deck 1 only |
| G3 | PASS | Gate stops on release, Loop starts and stops. `g3a`, `g37` |
| G4 | PASS | `LOOP 1`, goes round. `g4a` |
| G5 | PASS | Red timer, `REC 3`, plays with the deck stopped. `g5-record-master` |
| G6 | PASS | `RISER` back |
| G7 | PASS | Meters fall at `VOLUME` bottom, `STOP` stops. `g37` |
| H1 | PASS | Small iPhone. `h1-chain-se` |
| H2 | PASS | Each keeps its own depth. `h2` |
| H3 | PASS | Lit red, meters fall, comes back further along. `h34` |
| H4 | PASS | "Echo out needs the deck playing." Not silent after a pause. `h34` |
| I1 | PASS | Small iPhone: key's in the `MIXER` sheet, and the label under both knobs follows it. `i1`, `i2-space-noise`, `i2-crush-pitch`, `i2-filter` |
| I2 | PASS | All six, both ways: nothing silent, red or crashed. Double-tap not tried (tool) |
| I3 | PASS | `DUB`, right of centre and back, pause: meters fall over about 2 s. `i3` |
| `?` over the mixer | PASS | Duo, 16 controls, and small iPhone including its `MIXER` sheet: all have a note, none acted. `notes-mixer-duo`, `notes1`, `notes2`, `notes3` |

## Timings and measurements
**CPU, small iPhone** (6 readings each, 5 s apart, on its own process, stems finished):

| State | Avg | Peak | Round 12, on the Duo |
|---|---:|---:|---:|
| Idle, nothing loaded | 4.1% | 4.5% | 4.5% |
| Two loaded, paused | 4.3% | 4.9% | 5.4% |
| One deck playing | 9.4% | 9.9% | 10.6% |
| Both, synced, with an offset | 14.6% | 16.0% | 20.2% |
| Both, plus stems and an echo | 14.9% | 15.9% | 20.4% |

**FB1, every press:**

| How | Press | Result |
|---|---|---|
| Next call (0.78 s, after the slide) | `PLAY` deck 1, Duo ×2, small iPhone ×2 | Started, 4 of 4 |
| Next call | `PLAY` deck 2, Duo ×2 | Started, 2 of 2 |
| Pushed into the slide | `PLAY` deck 1, small iPhone | Nothing ×2 (sent as it began). Started ×2: lit at +0.17 s, and +0.45 s (just after) |
| Pushed into the slide | `PLAY` deck 2, small iPhone | Nothing ×1. Started ×2: lit at +0.125 s and +0.105 s |
| Pushed into the slide | `PLAY` deck 1, Duo | Nothing ×1. Started ×2 |
| Pushed into the slide | `PLAY` deck 2, Duo | Started ×2 |
| Pushed into the slide | Pad `H` deck 1 and `E` deck 2, small iPhone. `H` deck 2 and `E` deck 1, Duo | Each set that pad only, 4 of 4. `E` lit at +0.21 s, about as the slide ends. The others aren't timed |
| Pushed into the opening slide | Houston's `1`, both | Loaded, 2 of 2. Not timed |
| Pushed into the slide | `AUTO`, Duo. Also `AUTO` during a move on the small iPhone | Nothing, 2 of 2 |
| Next call | `AUTO`, Duo | Worked |
| Pushed into the slide | Crossfader drag, Duo ×2 | Moved. I can't tell if either began inside the 0.45 s |
| Long run, pushed into the slide | `JUMP +32`, `RELOOP`/`EXIT` | `JUMP` landed, `EXIT` found nothing |

**Is the mixer's 0.45 s a nuisance?** Not that I can measure. A closing slide takes 0.35 to 0.42 s on the iPad by changed frames, so the mixer's dead time is about what you'd see it moving for. It needs a real finger to say. Nothing tells you a press was lost.

**Long run, small iPhone:** 09:30:41 to 09:45:57, 15:15, with music on throughout and a frame every 1.5 s.
- **Tracklist:** Houston 00:00, Exhilarate 01:22, Gepzene 02:39, Skylander 05:38, Severe Tire Damage 06:39, Houston 10:14, Gepzene 11:00, Exhilarate 13:05, Gepzene 13:51.
- **Levels:** peak -0.2 dB, mean -14.7 dB. No crash reports.
- **Gaps of 0.25 s or more under -50 dB:** six.
  - 0:00 to 0:00.76, before I pressed `PLAY`.
  - Ending 2:47.8, 3:02.8, 14:43.6 and 14:58.6, each 0.27 to 0.33 s: Gepzene's own. The file itself dips like that every 3.75 s, up to 0.31 s.
  - Ending 13:06.7, 0.30 s: also Gepzene's own. The file has the same pattern of dips at 1:45, going into its `DOWN`. The new track's level arrives 0.9 s later, with no hole.
- **Moves that played out:** Loop build ×3, Echo throw ×2, Vocal ride and Brake drop, plus two starts with no move as a track ran out. No Bass swap, so that beat of silence wasn't on this recording.
- **Takeovers:**

  | What I did | What it said or did |
  |---|---|
  | `JUMP +32`, many times, during `MIX`'s count | Count follows |
  | `EXIT` in a move's closing slide | Nothing: the press found nothing, and the move ran on |
  | A 4-beat loop on the playing deck | Waits, `MIX…`. `EXIT` and it carried on |
  | `MIX` key | "Mix off. The track playing just carries on." |
  | `AUTO` with both playing | Refused: "Auto DJ brings in a stopped deck. Stop the one you want next." |
  | `AUTO` late in a track | "No clean way in", and the next one started |
  | Flanger on and filter moved while waiting | Flanger ended with its track. My filter on the new deck stayed, as the rules say |
  | `PLAY` on the waiting deck in the count | "Mix off: you started deck 1 yourself." |
  | 3 × `JUMP` past the plan's moment | "Auto DJ lost its moment when the deck moved." Off, music on |
  | Browser open during a move, `AUTO` in its closing slide | Nothing. Move finished |
  | Key `2` on the playing new deck | "Deck 2 is playing. Stop it first." |
  | Stop the old deck, after the handover | "Vocal ride done. Deck 1 is on." Mix carries on |
  | Load on the waiting deck | "Mix off: the track changed." |
  | `AUTO` in a Loop build | "Auto DJ stopped. The decks are yours. Deck 1 is still looping." |
  | `AUTO` with my loop on | Took the loop off, then a Brake drop. Old deck back at its own speed |

- **I meant one more:** stopping the new deck during a build. My wait was refused, so the press landed in the count and started that deck: "Auto DJ stopped: you started deck 1 yourself."

**Section names (FC9),** read from `library.json` after stems:

| Track | Sections |
|---|---|
| Skylander (6:00) | `INTRO` 0:00, `UP` 0:24, `CHORUS` 0:31, `DOWN` 2:19, `VERSE` 3:13, `UP` 3:28, `CHORUS` 3:36, `OUTRO` 5:23 |
| Gepzene (3:49) | `INTRO` 0:00, `UP` 0:10, `CHORUS` 0:17, `DOWN` 1:47, `UP` 2:02, `CHORUS` 2:10 |
| Exhilarate (2:25) | `CHORUS` 0:00, `VERSE` 0:37, `UP` 0:54, `CHORUS` 0:59, `OUTRO` 2:18 |
| Houston (4:51) | `CHORUS` 0:00, `OUTRO` 4:27 |
| Severe Tire Damage (6:52) | `INTRO` 0:00, `UP` 0:07, `CHORUS` 0:13, `VERSE` 1:57, `CHORUS` 2:49, `VERSE` 3:41, `CHORUS` 4:07, `VERSE` 4:32, `CHORUS` 5:11, `VERSE` 5:24, `UP` 5:44, `CHORUS` 5:50, `OUTRO` 6:42 |

What looks unlikely:
- **Houston is one `CHORUS` of 4:27.** The counter reads `CHORUS 131.4`. Its level's flat, -15 to -16 dB for most of it, so the rule may be doing what it says. The mix alone had six sections.
- **Exhilarate starts on a `CHORUS`,** at the first beat. Its `gridSource` still says `analysis`, where the other four say `drums`.
- **Gepzene has no `OUTRO`,** though it goes silent from about 3:45 and the mix alone said `OUTRO` at 3:41.
- **Severe's `CHORUS` at 5:11 lasts 13 s.** It's the one short section among the rest.

Gepzene's `DOWN` fits its level: -24 dB at 1:45 to 2:00, against -11 dB around it.

**Stems, small iPhone, by the first-time user:** 2 tracks together about 4 minutes. One at a time, about 1.5 min for 3:48 and about 2:10 for 6:51.

## First impressions
**Does it look like $1000 pro software?** On the Duo and the iPad, yes, mostly: the wide layout's dense and precise, and the waveforms and jogs are the best part. What most breaks the illusion:
1. **The words Auto DJ leaves you with.** A capsule that says "Echo throw" and a pair of thumbs, with nothing to say what either means unless you search Settings. A key that says `MIX 63`. Pro software would show you what's coming.
2. **Section names you can't trust yet:** one 4:27 `CHORUS` on a real track, on the screen all the time.
3. **On the small iPhone, what's hidden:** the sampler is four presses of `MORE` away, the knobs' effect key's in a sheet, and the second row of FX names is very small.

**What felt slow, confusing or surprising?**
- Stems, on this simulator: a move can't start for a minute or two, and that's when N7's silence happens.
- `MIX` from mid-list ending after two tracks, and replacing what's on the decks.
- With `NEXT` on, the list moving under your finger.
- Which move you get changing from press to press.

**Which control was hardest to find or hit?** `FILTER`'s effect key on the small iPhone, in the `MIXER` sheet. On the Duo nothing was hard to hit. After twelve rounds I'm not a fair judge of finding things, so the first-time user's report below is the better answer.

## The first-time user's report
Written by a separate session, from what it could see and with no access to the code or docs, apart from what it says it was shown. Its screenshots are `fu-*`.

Clock: launch 09:48:51, stopped 10:35:07, so 46 min 16 s. It came up sideways, with no rotate needed.

Limits on everything below:
- I can't hear, and I can't feel haptics. "Worked" means the keys, numbers, waveforms and meters behaved. I can't say whether any mix or effect sounded good.
- Each tap plus screenshot cost me 3 to 8 s, and I lost longer stretches re-reading screenshots (roughly 10:06 to 10:11 and 10:17:47 to 10:20:26). So durations are upper bounds on the tool's side, and a real person reading the screen would be slower in other ways.
- Screenshots are in `docs/test-results-13/`, named `fu-*.png`.

### 1. What I can't un-know

I was shown these before starting, so I'm not a true newcomer:

- **The git status line** `?? docs/test-results-13/` **and these git log lines:**
  - `95ce321 Slide panels so a press lands where it's aimed, name sections from stems, and fix what round 12 found`
  - `60e1edf Add hands-on test results, part 12`
  - `6fc9a2c Hand the decks back when a Loop build's loop is touched, and fix what round 11 found`
  - `d20bb16 Add hands-on test results, part 11`
  - `f264c0a Add ? to explain any control, and fix what hands-on round 10 found`
- **The whole of the project's CLAUDE.md and the memory index.** What that spoiled for this test:
  - `?` exists, what it does, and that Settings has the same notes as a list. So I can't say whether I'd have found help unaided, though the app did tell me about it unprompted.
  - `MIX` is in the browser and is the whole-list mode, and `AUTO` does one move. I went straight to `MIX`, so **how findable it is went untested**.
  - The compact layout hides the tempo fader behind `JOG`.
  - `NEXT` puts what's been on air last, a playlist keeps its built order unless a column's chosen, and a held roll or slice borrows the loop. These explain things below that the app itself didn't explain, and I say where.
  - That `SPACE` is a knob effect, what `MIX…` and the number on `AUTO` mean, that stems run on the CPU here, and the deliberate beat of silence in a bass swap.
- **Your brief** told me the app can mix a list by itself, and which areas to look at.

I didn't read any docs, source or git history beyond that.

### 2. From nothing to a mix by hand

| Stage | Time | Took | Screenshot |
|---|---|---|---|
| Launch to first screen | 09:48:51 to 09:48:53 | 2 s | `fu-first-screen.png` |
| Import key, then the file picker appearing | to 09:49:14 | 21 s, including the picker loading: still loading in a shot at 09:49:07, up by 09:49:14 | `fu-files-picker.png` |
| Finding My Music, choosing, Open | to 09:49:36 | 22 s | |
| Import and analysis of 5 tracks | to 09:49:45 | 9 s | `fu-import-progress.png` |
| Loading two tracks | to 09:49:53 | 8 s | `fu-help-hint.png` |
| To the decks, and reading help | to 09:50:54 | 61 s | `fu-decks-first.png`, `fu-help-on.png`, `fu-h-jog.png` |
| Deck 1 playing, deck 2 synced and playing | to 09:51:08 | 14 s | `fu-sync2-play2.png` |
| Crossfader and low EQ across to deck 2 | to 09:51:41 | 33 s | `fu-hand-mix-done.png` |
| **Total** | | **2 min 50 s** | |

I matched tempo with `SYNC`, not by hand. I tried the tempo fader later.

Moments I wasn't sure:

- **The first screen is the browser, not the decks.** It worked well: "No music yet. Tap Import to add music from Files, or drop audio into the Segue DJ folder in the Files app or Finder." I knew what to do. `IN KEY` and `±6%` were dim on the empty library, while `NEXT` and `MIX` weren't. I didn't try pressing them there.
- **The picker opened in an empty folder.** It showed the Segue DJ folder and "Folder is Empty". I expected recent files or a place to browse. I pressed back at the top left and found My Music. This is the one real stumble in the import, and a newcomer may well think their music has gone.
- **Picking files.** A tap ticks a file instead of opening it, with Select All at the bottom and Open at the top. That's fine once seen. The `jam…` filenames meant nothing, and the real titles appeared after import, which was a pleasant surprise.
- **After loading, I stayed in the browser.** To reach the decks I guessed that the lit `BROWSE` key would close it, and it did. Nothing says "decks", so that's a guess a newcomer has to make.
- **Looking for the tempo fader.** It isn't on the decks page at this size. `?` on `JOG` says it's on the jog page, and my notes had already told me. The fader itself has no label.
- **Starting deck 2 went straight out.** The channel faders were up and the crossfader was central, so pressing `PLAY` on deck 2 put it on air with deck 1 (both on the meters) for about 7 s before I reached the crossfader. To preview it you need `SPLIT` and a splitter cable. The note says so, and says AirPods can only play the mix. On a phone, a first mix has no private stage.
- **`MASTER 1` stayed on the top bar** after I'd crossfaded all the way to deck 2 (`fu-hand-mix-done.png`). I expected it to follow what's being heard. The note explains that it means the leading deck, and only stopping that deck moves it.

### 3. Everything else

### Mixing a whole list

Key: `MIX` in the browser. I ran it three times.

**Run 1, All Tracks, 09:57:50 to about 10:03:50. It played 2 of 5 tracks, then stopped.**
- The state: deck 1 Skylander playing (row 4 of the list), deck 2 Houston run out, crossfader all the way to deck 2 from my hand mix.
- The capsule said "Up next: Gepzene - Can't be Serious." and replaced Houston on deck 2 without asking (`fu-mix-pressed.png`). That's row 5, the last row.
- It moved to Gepzene (`fu-mix-move-1.png`) and played it out, then both decks stopped and the music ended (`fu-mix-ended.png`), with Severe, Exhilarate and Houston never played.
- I'd expected all five, because the note says "Auto DJ through the whole list on screen".
- If it said anything at the end, I missed it: "Added to Friday night" from my own playlist work was fading in that spot (`fu-playlist-4.png`). So I can't say.

**Run 1's first 80 s had nothing on the master meters.** Deck 1 was playing with the crossfader shut on it, and `MIX` waited for stems (15% to 97%) before saying "Crossfader to the middle, ready for what's next." (`fu-mix-crossfader.png` at REC 0:22, master columns empty.) My recording's tracklist puts Skylander at 00:29.
- It got into that state through my own slip: I'd restarted deck 1 without moving the crossfader. But a newcomer will do the same.
- Pressing `AUTO` with stems ready moved the crossfader at once ("Loop build in 16 bars. Crossfader to the middle, to hear both.", `fu-auto2-press.png`). Calling it off put it back (`fu-auto2-off.png`). So only the wait for stems holds it up.

**Run 1 also kept what I'd left on.** My vocal mute, half-level drums and cut LOW stayed on Skylander going into the move, with no comment. That's fair, but a newcomer won't connect it.

**Run 2, playlist Friday night, about 10:07:50 to 10:24:25, 4 tracks. This is the good one.**
- Pressing `MIX` with both decks stopped replaced both decks' tracks with rows 1 and 2 and started at once (`fu-mix2-pressed.png`, `fu-mix2-decks.png`).
- It went through every track, 16.5 minutes, and ended with "That's the end of Friday night." (`fu-end-of-list.png`).
- The meters never fell silent in anything I sampled, but I sampled every few seconds at best.
- The key counted down: `MIX 101`, `MIX 74`, `MIX 3` (`fu-mix-count.png`), then a move.
- The moves I saw were "Echo throw done. Deck 2 is on." (`fu-mix2-rate.png`) and "Loop build into Gepzene - Can't be Serious." (`fu-mix-move-2.png`, 48 s from capsule to done).
- **I missed the third move** (Gepzene at 126 into Severe at 148, between 10:17:47 and 10:20:26) while I was reading old screenshots.

**Run 3, All Tracks sorted by BPM, 10:26:12.** With Exhilarate on deck 1 and my tempo fader at -8.6 (155.34 BPM), pressing `MIX` started it at 170.00, undoing my tempo without comment. "Up next" was Severe, which had just finished two minutes earlier. Pressing `MIX` again: "Mix off. The track playing just carries on." (`fu-mix-stop.png`). That's a clear, good message.

Things I tried during a mix:
- A loop on the playing deck: "The mix will carry on when deck 2's loop ends." (`fu-loop-during-mix.png`). Exactly what I'd want to be told.
- A jump forward 16 beats: `MIX 28` became `MIX 20`, so it took account of it.
- Pressing a deck key for a playing deck in the browser: "Deck 2 is playing. Stop it first." (`fu-load-playing.png`). Good.
- Looking at another list while mixing: the mix carries on with the original list, but nothing shows which list that is, except the message at the end.
- Sorting the list mid-mix: I sorted by BPM at 10:16:21, when the mix was already on its last track, so this shows little. It ended after Severe although the sorted view had rows below it, which only weakly suggests it keeps the order it started with. The note says "in the order it's showing".

Not tried: loading a track during a mix, pressing the `MIX` key on the decks page (as opposed to the browser), stopping a deck mid-move.

Would I have found `MIX` unaided? I can't say (section 1). It sits with `IN KEY`, `±6%` and `NEXT`, which all filter or sort the list, so it reads as one more filter. `MIX`'s note mentions `AUTO`, but `AUTO`'s note doesn't mention `MIX`, so someone starting from the mixer wouldn't be led there.

### AUTO, one move

10:26:47 "Loop build in 28 bars.", counting `AUTO 24`, `16`, `10` (`fu-auto-press.png`). 10:27:27 "Loop build starting. Touch a control to take it back." (`fu-auto-starting.png`). 10:27:49 "Loop build done. Deck 2 is on." with the thumbs. It handled 170 into 148, and `AUTO` again gives "Auto DJ off." See section 5 for what touching a control does.

### Pad pages

- **`CUE` (`fu-d2-cue.png`):** tap sets, tap again jumps (A at 1:12, B at 1:17, jump back seen on the timer). `DEL` then a pad: "Deleted hot cue B" with `UNDO`, and undo works (`fu-del-undo.png`). Easy.
- **`LOOP` (`fu-pads-loop.png`):** pads 1/4 to 32, pad lights, the key above becomes `EXIT`. `IN` then `OUT` about 2 s apart gave a 6-beat loop, and `<` halved it to 3 (`fu-loop-inout.png`). Easy.
- **`ROLL` (`fu-pads-roll.png`):** hold it and the timer carries on underneath. True to the note.
- **`MORE >` steps one page at a time:** `MEM`, `SLICER`, `JUMP`, `SAMPLE` (`fu-pads-more.png` to `fu-pads-more4.png`). Nothing lists them, so a newcomer only finds the sampler by pressing it four times, and it went back to `MEM` the next time I came from another tab (seen once). That's the screen size, but it hides a lot.
- **`SLICER`:** held slice 02:36.6 during, 02:41.2 after, so it keeps time as the note says (`fu-slice-held.png`). See section 5 for what it said during a mix.
- **`JUMP`:** eight clearly drawn pads, and it worked. I read no note specific to these pads, only the page's.
- **`MEM`:** the name isn't explained on the tab. `SAVE CUE` added a red bookmark pad silently (`fu-mem-save.png`). `LIST` opens "Memory cues" with a name field (`fu-mem-list.png`). I couldn't tell why I'd use this rather than `CUE`, and the notes say what it does, not why. `SAVE LOOP` not tried.
- **`SAMPLE` (`fu-pads-more4.png`):** `SET` then a pad opens a sheet (`fu-sampler-set-pad.png`) that needs scrolling at this height. Grab Deck 2's Loop worked: the pad became `LOOP 2`, a press lit it and raised the meters, `STOP` stopped it (`fu-grab-done.png`). A pad lights while it plays (`fu-sampler-riser.png`), though one tap caught at 0.3 s showed nothing lit, and I can't tell why without sound. Not tried: `Q`, `VOLUME`, Gate and Loop modes, Choose a File, Record the Master. I couldn't tell whether the sampler belongs to a deck or is shared.
- **A loop running under the sampler or FX page has no key on that page:** only the waveform shows it, and the way out is on `LOOP`.

### FX

- **Per-deck pad page (`fu-pads-fx.png`):** on the first visit a capsule explains: "FX pads slide: up and down for depth, left and right for the beat." Good, but it's the only place this is said on the page itself.
- Holding `ECHO` and sliding lit it and moved the beat from 1/2 to 3/4, and let go it's off, with 3/4 kept (`fu-fx-held.png`). I didn't see depth move on its bar in the one shot I took, so I can't confirm that half.
- A tap latches, and the `FX` tab gets a blue dot (`fu-fx1-echo.png`). `D` off works as a target.
- `OUT`: "Echo out on deck 2. Press OUT again to bring it back." with the meters dropping almost to nothing (`fu-fx-out.png`). Exactly what the note says.
- The second row of names (`REVERB`, `FLANGER`, `PHASER`, `BACKSPIN`) is very small type at this size.
- **The knob effects are a separate system, and easy to miss.** The key that turns `FILTER` into `DUB`, `SPACE` and so on is inside the `MIXER` sheet, not with the knobs (`fu-mixer-sheet.png`). See section 5 for the bug.
- I saw an `ECHO` I'd left on deck 1 go off when `AUTO`'s move ended, with no message. Reasonable, as the deck had stopped.

### Stems

Simulator on the CPU: a phone may be quite different.

- The header counted down "Stems 30% · 2 min" (09:50:46), "82% · 40 s", "92% · 15 s" (09:53:21). The first two tracks, 6:00 and 4:50, split together and were done by 09:53:57, about 4 minutes after loading. The ETA ran a little short early on.
- Later, one at a time: Gepzene (3:48) about 1.5 min, Severe (6:51) about 2 min 10 s, Exhilarate (2:25) about a minute (8% at 10:25:13, 32% at 10:25:24; I didn't catch the end). Tracks already split came back at once (Skylander in run 2).
- Nothing else I tried had to wait for a split. Only `MIX` and `AUTO`'s moves did.
- Stems page: muting `VOCAL` lights `INST` above it by itself (`fu-stem-vocal-off.png`). `SOLO D` works, and a second press goes back to what I had (`fu-solo-drums.png`). Sliding a pad sets a level you can see (`fu-stem-slide.png`). The waveform takes the stem colours at once, which is a nice touch. All true to the notes.
- I muted `VOCAL` at 8% split with no comment (`fu-stems-splitting.png`). I can't tell what you'd hear before it's ready. The note on the status says "≈EQ is a rougher split by frequency, used when the full one isn't available", but the screen showed a bar and a percentage, not `≈EQ`.

### Recording

- `REC` went red with a running time, then a track count: `0:22`, `1:19 · 1`, `5:20 · 2` (`fu-rec-on.png`). Clear.
- Pressing it again asks "Stop recording?" (`fu-rec-stop.png`), then "Saved Mix 2026-11-04 09.58.36" (`fu-rec-saved.png`).
- Finding it: the waveform icon on the top bar, with no text on it. I learned what it was from `?`. Without help I'd have opened it by chance.
- The list shows 5:49, 9.8 MB, M4A (`fu-recordings-list.png`). The tracklist has two lines, with BPM as played: Gepzene reads 125.0 though its own is 128 (`fu-recording-tracklist.png`).
- Play turns its icon to pause, with **no time, no progress and no way to move through it** (`fu-recording-play.png`). I can't tell whether it sounded.
- Rename works (`fu-recording-renamed.png`). Share offered "Plain Text and 2 Documents 9.8 MB", which took several seconds to appear: not there at 10:05:30, there at 10:05:37 (may be the simulator). Nothing says what the extra files are. Delete not tried.
- My recording has about 37 s of silence at the end, because the mix stopped and I didn't notice, and about 25 to 35 s at the start, from the crossfader. Both are mine in a sense, but see run 1.

### Settings

Looked through, one setting changed. (`fu-settings-1.png`, `fu-settings-2.png`)

- Help comes first, which is right. Crossfader curve, Match track loudness, Waveform colours, Haptics, Prepare stems on load, Recording format, Backups. The explanations under Haptics, Prepare stems and Backups are plain and useful.
- I set Waveform colours to RGB. I couldn't really tell what it changed (`fu-rgb-waves.png`), as the colours already change between pages. Nothing else changed or tested, so curve, loudness, haptics and backup are unverified.

### Playlists

- `+ New Playlist`, a name, Create: quick (`fu-new-playlist.png`).
- The empty list says exactly what to do: "Nothing in this playlist yet. Go to All Tracks, press and hold a track, and add it from there." (`fu-playlist-made.png`). Very good.
- Adding is one track at a time: hold, Add to Playlist, the playlist name (`fu-track-longpress.png`). Four tracks took me about 1 minute. I found no multi-select.
- I tried dragging a held row onto the playlist in the sidebar, and it only opened the menu. That may be the touch tool.
- Inside a playlist the row menu adds Remove from Playlist (`fu-pl-row-menu.png`). Holding the playlist itself offers only Delete Playlist (`fu-pl-side-menu.png`), so no rename. I found no way to reorder, but I only tried the menus, not dragging within the list.
- `MIX` on it was the best part of the app (`fu-playlist-4.png`).
- **A sort chosen on All Tracks carries into the playlist.** My built order was gone from view at 10:23 (shown by BPM) with nothing saying why. My notes say a third tap on the column gets it back. I didn't try it, and a newcomer wouldn't know.
- History builds itself (`fu-history.png`), with a line per time on air. Search worked (`fu-search.png`). `±6%` worked.
- `IN KEY` left only the leading deck's own track (`fu-in-key.png`), which correctly had no neighbours in my five, but looks odd.

### 4. Using the help

**How I found it.** At 09:49:45, as I loaded the first track, the capsule said "New to this? Press ? and tap anything to see what it does." (`fu-help-hint.png`). I already knew about it (section 1), but that's a well-placed message at the right moment. `?` lights (`fu-help-on.png`), and notes appear at the side away from what you touched.

**It's the best thing in the app for a newcomer.** I used it constantly and the music kept playing. Pages still change while it's lit, and each arrival explains itself ("SLICER PADS: The bar you're in, cut into eight...", `fu-h-slice.png`). The searchable list in Settings is a good second route (`fu-settings-help.png`, `fu-settings-help-search.png`), though on this screen the keyboard covers most of the results.

**Checked against what really happens, and true:** `BEAT SYNC` ("Moving the tempo fader takes it off"), tempo fader ("Down is faster"), `OUT`, `SLICE`, `DEL`, `SOLO`, loop size, `SLIP` (with `REV`: 00:46.9 during, 00:56.8 after, `fu-rev-on.png`), jog ("On a stopped deck, any touch moves through the track"), "the music won't change" while `?` is lit.

**Wrong, or didn't help:**

1. **`MIX`:** "Auto DJ through the whole list on screen, in the order it's showing, loading each track as it goes." From row 4 of 5 it played rows 4 and 5 and stopped. (`fu-h-mix.png`)
2. **`NEXT`:** "Puts the list in a good order to play from the leading deck, by how close the tempo is and how well the key goes." From Gepzene at 126 it put **Exhilarate at 170 first**, above Houston at 126 and Skylander at 125 (`fu-next-order.png`). My notes say tracks already on air go last, which would explain it, as those two had just played. The note doesn't say so, and the result looks wrong.
3. **The lit `MIX` key on the decks page:** the note's title is `AUTO`, and it says "press AUTO to call it off" while the key reads `MIX 35%` (`fu-h-mix-lit.png`). Nothing tells me whether that ends the move or the whole mix. I didn't press it.
4. **`AUTO`:** "Touch a control to take it back." True in that the crossfader stayed where I put it, but nothing confirmed it (section 5).
5. **`FILTER` knob:** "The key with the arrows gives this knob other effects, which is why its name changes." That key isn't on this screen, it's inside `MIXER`, and the name doesn't always change (section 5).
6. **Waveform:** "The track going past, and the line is what you're hearing... UP is a build-up and DOWN a breakdown." It says nothing about **colour**, which is the first thing you notice, and which changes between pages. Good that it mentions UP and DOWN.
7. **Searching the list for "playlist":** gives `BROWSE` and `PLAYLISTS` ("Chooses which list you're looking at, and makes new ones."), and not how to put a track in one. Only the empty playlist says that.
8. **`REC`:** "Press it again to stop and save." It asks first. Harmless, and the asking is good.
9. **Recordings, while recording (not a `?` note):** "No recordings yet. Tap REC at the top of the screen to record your mix." I had, and it was lit (`fu-recordings-empty.png`).

**Still a mystery after using it:**

- What the thumbs do. They show for about 8 s after a move, with no words about what they change. I didn't press them.
- What "Echo throw" and "Loop build" are. They appear in capsules with no explanation. I didn't search the list for them.
- Which list a running mix is working through.
- Why `MEM` exists alongside `CUE`.
- What stems do before they're ready.
- Whether the sampler is per deck.
- `MASTER` means three things here: the top bar's readout, the jog page's key, and the knob in the `MIXER` sheet. Each note is right on its own, but together they're confusing.

**Not read or not checked:** `CUE` hold on a stopped deck, `KEY SYNC`, key shift, the `TRIM` and headphone knobs, `SPLIT`, pinch zoom, and double-tap to centre (tried once on a knob, but the tool's 2 s between taps makes that an unfair test).

### 5. What surprised me, or felt slow or broken

1. **`MIX` played 2 of 5 and left silence.** Steps: on All Tracks in its import order, have row 4 playing, press `MIX`, wait. It plays row 5 and stops, with rows 1 to 3 never played. I ran this to the end only once. It looks like the app, not the tool. Run 3's start fits: from row 1 of a sorted list, "Up next" was row 2, so it seems to go down from wherever the loaded track is, though I called run 3 off early. One thing I can't rule out: during run 1 I made a playlist and switched the view to it and back (10:02:49 to 10:02:54), and to it again at 10:03:53, about when the mix ended. I also switched lists during run 2 and that carried on, so I doubt it's the cause. Screenshots: `fu-mix-pressed.png`, `fu-mix-ended.png`.

2. **`MIX` left the master silent for about 80 s while waiting for stems.** Steps: crossfader all the way to deck 2, deck 2's track finished, deck 1 playing, and the next track in the list not yet split. Press `MIX`. The crossfader only moved at about 09:59:05, as the split finished. `AUTO` with stems ready moved it at once. Simulator speed makes this longer than it may be on a phone, but the order of events is the point. Screenshot: `fu-mix-crossfader.png`.

3. **The `FILTER` knob's label doesn't match the mode. Repeatable.** Steps: `MIXER`, press the key with arrows until it isn't `FILTER`, and close it. The knobs now read that name too (`fu-filter-dub.png`). Then let a plan get made, by pressing `MIX` or `AUTO`, or a mix reaching its next plan.
   - The knobs went back to `FILTER` twice: at 10:17:44 to 10:17:47, as `MIX 99%` became `MIX 7`, with `DUB` chosen, and between 10:26:03 and 10:26:47, with `SPACE` chosen and `MIX` then `AUTO` pressed.
   - The key didn't follow. After the first time, one press from knobs reading `FILTER` went to `SPACE`, skipping `DUB`, so the mode hadn't been `FILTER` at all. After the second, the key read `SPACE` while the knobs read `FILTER` (`fu-filter-mode-check.png` at 10:30:49, `fu-filter-label-check.png` at 10:30:57).
   - I can't hear which one the knob actually does.

4. **A slice during a mix says something untrue.** Steps: during a `MIX`, on the playing deck, `SLICER`, hold a pad. "The mix will carry on when deck 2's loop ends." with `EXIT` and `4` lit orange, and I'd set no loop (`fu-slice-held.png`). It stayed for at least a second after I let go, with the key on `MIX…`. My notes say a held slice borrows the loop, which explains it, but the message reads wrongly. Not tried for `ROLL` during a mix.

5. **"Touch a control to take it back" gave no sign it had.** Steps: `AUTO`, wait for "starting", drag the crossfader. Nothing said anything, `AUTO` stayed lit, the move ran to "Loop build done. Deck 2 is on." and the crossfader stayed where I'd left it, left of centre, which may leave deck 2 turned down with nothing to say so (`fu-auto-touch.png`). I can't tell whether it was any quieter.

6. **`MIX` undoes a tempo I set, silently.** Steps: move a stopped deck's tempo fader, press `MIX`. It starts at the track's own speed (155.34 to 170.00). A new track starting at its own speed makes sense, but this was a track already loaded with my setting on it.

7. **Pressing `MIX` replaces what's on the decks without asking.** Run 1 replaced Houston, run 2 replaced both decks. If I'd cued something up, it's gone. "Up next" tells me afterwards.

8. **Section names looked coarse.** Houston (4:50) read `CHORUS 85.4` and `CHORUS 106.4` (`fu-mix-count.png`), so a "chorus" over 100 bars long, out of about 150. I can't hear whether that's fair. The note says the number counts within the section.

9. **`SYNC` to a far tempo gives no warning.** 170 to 148 took the deck to -12.9% and changed the range from ±10 to ±16 by itself (`fu-sync-far.png`). It did what I asked, but a newcomer doesn't know that's a lot.

10. **Capsules cover useful things briefly.** On the decks they sit over deck 1's section name, and in the browser over the search field and filter keys (`fu-mix-stop.png`). Small-screen problem, and they're short-lived. A capsule can also displace another: I may have lost run 1's ending to "Added to Friday night".

11. **The grid menu opens from the BPM number, even mid-mix** (`fu-bpm-menu.png`): Double BPM, Halve, nudge, Set downbeat here. It's easy to reach by accident and nothing warns. Set downbeat was cut off at the bottom, and I didn't try scrolling. Small-screen issue in part.

Tool or simulator rather than the app, as far as I can tell:
- Dragging a held row to the sidebar (may be the tool).
- The several seconds the file picker and the share sheet took to appear (may be the simulator).
- No taps were lost once I used `duration: 0.2` on sheets. Default taps on the performance keys all landed.

### 6. The three things I'd fix first

1. **Make `MIX` do what it says, or say what it'll do.** Starting mid-list and stopping after one more track is the biggest let-down in the app, as the same key on a playlist was the best part. Either go on through the rest of the list, or tell me at the start: "Mixing the 1 track left in this list." Show something like tracks left on the key, and make sure the end message can't be lost to another capsule.
2. **Open the crossfader as soon as `MIX` is pressed, not when stems finish.** A first-timer who's left the crossfader at the far side gets silence for as long as the split takes, and the first thing their recording holds is nothing. `AUTO` already moves it at once when it can.
3. **Fix the `FILTER` knob's label.** It's small, but it's the one place a control plainly says the wrong thing, and it's a control you touch while the music's playing.

Close behind:
- Say what the thumbs do, and what "Echo throw" and "Loop build" mean.
- Make `NEXT`'s note match its result.
- Fix the slice message during a mix.
- Give a recording's playback a time and a way to move through it.
