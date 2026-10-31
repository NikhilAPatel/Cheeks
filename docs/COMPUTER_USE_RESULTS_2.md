# Hands-on results, part 2, 2026-10-30

Commit tested: 97e6a30
Device: iPhone Duo simulator, iOS 27.2, unfolded inner screen (951×669 pt)
Tooling limits:
- **Not testable here:** haptics, how anything sounds, and the headphone output. Where a test needed audio, I used the master meters and saved files instead.
- **Touch:** synthetic only, so nothing here confirms how a real finger behaves. That matters most for `UNDO` and the screen edges. The simulator tool turns any touch within 4 pt of an edge into a system gesture, so I stayed at least 6 pt away.
- **Timing:** each tool call takes seconds, so I can't hit exact times. The "5 second" master recording came out at 18.3 s.
- **Video:** the recorder only writes a frame when the screen changes, so tail lengths are approximate.
- **Ignored presses:** a 0.2 s press did nothing twice, on `Save a Backup…` and on the colour well, and a plain tap then worked. I can't tell whether that's the tool or the app.
- **Not checked:** anything at iPad size.
- **Interruption:** another session's `tools/ui-tests.sh` reinstalled the app on this simulator at 19:51 and wiped its data, partway through A2. I waited for that run to finish, reinstalled this commit's build clean, and carried on. A1 and A2's tap test ran on my first install of the same build, and everything else ran on the second. The home screen that appeared wasn't an app failure.
- **My own slip:** during I2 one swipe turned deck 1's `LOW` knob by mistake. I reset it, and it isn't an app problem.

## Summary
58 tests: **53 PASS, 5 FAIL (C9, F3, F5, F6, G2), 0 BLOCKED.** No crashes and no crash reports.

All three failures from last time are fixed here: Undo worked every time, the refused load now shakes and explains, and CPU drops when idle. Undo still needs checking with a real finger.

The 3 most important problems:
1. **Deleting a newly saved memory cue or loop doesn't stick (F5, F6).** The pad disappears, but the library keeps the item. `UNDO` then adds a second copy, and the deleted item comes back on the next load. A saved loop's on-load switch is lost the same way.
2. **`ROLL` and `SLICER` leave a hidden loop behind (F3, G2).** With no loop showing, `SAVE LOOP` saved a 1/16-beat loop, and the sampler offered to grab a loop that isn't there.
3. **A pad tapped straight after a tab fires the old page's pad (Looks wrong).** It happened on all 3 tab-then-pad taps sent with no pause. Two jumped a deck to a hot cue and the third set a hot cue. It's right after a 0.15 s wait, so it needs quick hands, but a jump in the middle of a mix is costly.

## Failures
The causes below are leads from reading the code, not confirmed diagnoses.

### F5: Deleting a newly saved memory cue doesn't stick, and Undo duplicates it
- Steps: with Severe Tire Damage on deck 1 only and nothing saved, open `MEM` and tap `SAVE CUE`. Tap `DEL`, then the pad. Tap `UNDO`. Reload the track.
- Expected: the delete removes the cue from the library, and `UNDO` brings back one cue.
- Actual, from `library.json` at each step:

  | After | On screen | `memoryCues` in the file |
  |---|---|---|
  | `SAVE CUE` | One pad | `63611872` |
  | `DEL`, then the pad | Pad gone, capsule offers `UNDO` | `63611872`, still there |
  | `UNDO` | One pad | `63611872`, `BF304B90`, both at 1.29 s |
  | Reload | Two identical 0:01 pads | Same two |

  It also happens with no Undo: a saved loop I deleted came back on the next load. Once a track has been reloaded, delete works: a cue deleted after a relaunch did leave the file.
- Lead: `Deck.updateTrack` (`Cheeks/Audio/Deck.swift:395`) runs its closure twice, once on the deck's copy and once on the library's. `saveMemoryCue(at:)` and `saveCurrentLoop` (`Cheeks/Audio/Deck+Performance.swift:61`, `:101`) create the item inside that closure, and its `id` defaults to `UUID()`, so the two copies get different IDs. `delete` (`:141`) then matches by ID and misses the library's copy. The reload fix fits this.
- Screenshot: docs/test-results-2/f5-delete-undo.png, f5-duplicate-after-undo.png, f6-after-reload.png

### F6: The on-load switch isn't saved for a loop saved since the track loaded
- Steps: save a 4-beat loop, open `LIST`, switch the loop on, then reload the track.
- Expected: the loop is active after the reload, and the deck doesn't jump to it.
- Actual: the switch showed on, but `library.json` kept `activeOnLoad: false`, and after the reload the loop wasn't active. After a relaunch I switched it on again: this time the file said `true`, and a reload worked as designed, with the pad lit, an orange ring on the jog and the time still at 00:00.4. Naming a hot cue and changing its colour in the same list both worked. This looks like the same ID mismatch as F5.
- Screenshot: docs/test-results-2/f6-list.png, f6-after-reload.png, f6-active-on-load.png

### F3: `SAVE LOOP` saves a loop nobody set, after a roll
- Steps: on deck 2, hold the 1/16 `ROLL` pad for 2 s and let go. No loop is showing. Open `MEM` and tap `SAVE LOOP`.
- Expected: a capsule says to set a loop first.
- Actual: it saved one, 42.584 to 42.606 s, listed as "0:42, 1/16 beats". Deck 1, which hadn't rolled, refused correctly. The rest of F3 passed: a real 4-beat loop saved as 0:22, with an orange pad and an orange bar on the waveform.
- Lead: `saveCurrentLoop` (`Deck+Performance.swift:92`) only checks `renderer.loopEnd > renderer.loopStart`, and the roll seems to leave those values set.
- Screenshot: docs/test-results-2/f3-phantom-loop.png, f3-save-loop-refused.png, f3-saved-loop.png, f3-loop-bar-waveform.png

### G2: The sampler offers to grab a loop that isn't there, after a slicer hold
- Steps: load a track on deck 1, tap `SET`, then a pad. Close the sheet. Play, hold a `SLICER` pad for 1.2 s, let go and pause. Tap `SET`, then a pad again.
- Expected: no grab button for deck 1, because it has no loop set.
- Actual: the button wasn't there before the slicer hold, and `Grab Deck 1's Loop` was there after it. Grabbing in that state gave a 0.1685 s sample, which is half a beat at 178 BPM. The sheet itself is otherwise correct: only `Grab Deck 2's Loop` showed while only deck 2 had a loop. Probably the same cause as F3.
- Screenshot: docs/test-results-2/g2-no-loop-on-deck-1.png, g2-phantom-grab-after-slicer.png, g2-sheet.png

### C9: `SAMPLE` is smaller than the other tabs and crowds `DEL`
- Steps: measure the labels and the gap in a full-resolution screenshot of a page that shows `DEL`.
- Expected: nine labels the same size, and `SAMPLE` clear of `DEL`.
- Actual: capital letters are 19 px tall on the other labels (`CUE` 20 px) and 16 px on `SAMPLE`, so it's about 84% of the size. Its last letter ends at x = 1045 px, `DEL`'s outline starts at about 1047 px and its face at 1050 px. That's about 0.5 pt to the outline and 1.7 pt to the face. It stays small on pages without `DEL` too.
- Lead: the label scales to fit, with `minimumScaleFactor(0.75)` (`Cheeks/UI/Deck/PadSection.swift:84`).
- Screenshot: docs/test-results-2/c9-tabs.png

## Looks wrong
- **A pad tapped right after a tab uses the old page.** All 3 tab-then-pad taps sent with no pause hit the old `CUE` page: hot cue E and hot cue F jumped the deck (2:38 remaining to 3:31 in the frames), and an empty pad B set a new cue. With a 0.15 s wait the same tap landed correctly. Screenshot: d-tab-race-frames.png
- **The same track on both decks doesn't stay in step.** With Exhilarate on both, a hot cue and memory cue made on deck 2 didn't appear on deck 1's pads or waveform until deck 1 reloaded. Screenshot: f6-cue-pad-flag.png
- **Sliding on a lit FX pad turns it off when you let go.** `DEPTH` follows the slide, then the effect ends, so you can't fine-tune an effect that's latched on. Screenshot: h2-depth-slide.png
- **`OUT` on a stopped deck says nothing.** It stays dark with no capsule, and the code only buzzes. It's the same kind of silent refusal that C5 was last time. Screenshot: h4-refused.png
- **Section names look wrong.** Exhilarate is `CHORUS` from 0:00 to 2:17, then `OUTRO`. Severe Tire Damage is `CHORUS` from 0:16 to 5:24, giving counters like `CHORUS 190.4`. The colour strip is one colour for most of each track, so it says little. Screenshot: j1-phrases.png
- **The header's picture is stale during a load.** The new title appears at once, but the old track's letter and colour stay for about 0.2 s. Screenshot: d5-load-frames.png
- **The jog says `NO TRACK` during a load,** with a spinner, while the header already shows the title. Screenshot: b5-jog.png
- **The loop key reads 5 after a manual `IN`/`OUT` loop,** and keeps that after the loop ends. Screenshot: d4-in.png
- **A held slicer pad is clearly brighter than its neighbours but much duller than other lit pads,** so "on" looks different on this page. Screenshot: d2-slicer-hold.png
- **The loop line is still faintly visible behind the bar counter.** It's dimmed and behind the text, and the text stays readable. Screenshot: c8-counter.png
- **The keyboard is very tall.** The mixer doesn't move, but its lower half is covered and only about two rows of the list show. Screenshot: c3-keyboard.png
- **The home indicator sits over the bottom of the pads and mixer.** It doesn't block anything I pressed. Screenshot: c5-bottom.png
- **One deck at default levels reaches the lowest red segment of the meter.** `LIM` didn't light. Screenshot: h3-echo-out-meters.png
- **Backups:**
  - The restore summary says "1 playlists". Screenshot: k2-restore-summary.png
  - The browser's row order flipped after a restore, with Severe Tire Damage first before it and Exhilarate first after. Screenshot: k3-missing-file.png
  - `Save a Backup…` shows no confirmation. The sheet just closes.
  - The daily copy is written once, on the first save of the day. Today's stayed at 19:56 with no cues in it, so it doesn't protect anything made later that day.
- **Logs over the last hour, none of them from an engine:**
  - 12 `UIKit.AnimationKit` DebugAssertion faults, 6 each for `position` and `bounds`. Last run reported 67, but I can't say over how long, so the two aren't comparable.
  - 32 `renderbox` "image provider timed out" errors.
  - 81 pairs of haptics errors, which is probably just the simulator having no haptics.
  - 4 `NSPredicate` faults.
  - 260 "Automation type mismatch" lines, which come from the other session's UI tests.

## All results
| Test | Result | Notes |
|---|---|---|
| A1 | PASS | All four combinations worked: default tap and 0.2 s press, deck paused and playing, 6 tries in all. The cue came back and the capsule went each time. Synthetic touch, so still confirm with a real finger |
| A2 | PASS | Didn't load. Key `1` shakes in the video while `2` stays still. Capsule has a hand: "Deck 1 is playing. Stop it first." A swipe says the same |
| A3 | PASS | Idle 3.6%, paused 4.5%, and it rises with the work. See the table |
| B1 | PASS | With nothing played since launch, no meter LED lit in any frame across 8 toggles. My first recording began too soon after stopping a deck, so I re-ran it |
| B2 | PASS | The sweep runs once, in the first second or so |
| B3 | PASS | The capsule sits right of `MASTER`, with the whole number readable, including with the longest message I saw |
| B4 | PASS | Centred and green in 11 of 11 samples over 2:00. An earlier run didn't count, because deck 2 had reached the end of its track |
| B5 | PASS | The jog shows the tempo once loaded, after closing the browser straight away. `NO TRACK` shows during the load |
| C1 | PASS | Crossfader line within 0.2 pt of its tick, tempo line within 0.2 pt of its LED. Was about 6 pt |
| C2 | PASS | Catches from about 3 pt right of centre to about 3 pt left of it. Was under 1 pt |
| C3 | PASS | The mixer doesn't move and the search field stays visible |
| C4 | PASS | An alert offers both. `Keep recording` carried on, with the key showing 0:23. `Stop and save` wrote the `.m4a`, `.cue` and `.txt` |
| C5 | PASS | Strip gone. `PLAY`, the bottom pads and the crossfader all registered first time, 14 to 24 pt from the edge, with no system gesture. `CUE` sits above `PLAY` in this layout, about 125 pt up, and worked |
| C6 | PASS | `BROWSE`, `REC` and the gear all registered first time at y = 6 pt. `BROWSE` and `REC` also took a 0.2 s press |
| C7 | PASS | List shows "Severe Tire Damage - Hi…", and compact decks show "Severe Tire / Damage - H…". One line while `Stems` shows a percentage |
| C8 | PASS | The line runs behind the counter, dimmed. See Looks wrong |
| C9 | FAIL | See Failures |
| D1 | PASS | `SOLO`, its stem pad and `ACAPELLA` stay lit, and the next tap restores. The first try hit the tab race in Looks wrong |
| D2 | PASS | Each pad flashes pale and settles. A held slicer pad is clearly brighter than the others |
| D3 | PASS | Pads stay lit for their sound, and long ones overlap correctly. `RIM`, a short sound, was lit for 0.25 s |
| D4 | PASS | `IN` lights and a marker shows before `OUT` |
| D5 | PASS | The new title shows at once, with no old title. The picture lags. See Looks wrong |
| D6 | PASS | Compact decks showed `Stems 14%` and `Stems 0%` |
| D7 | PASS | The key stays at 32 after a `ROLL` hold |
| D8 | PASS | No old loop on the new track |
| D9 | PASS | Both files use the new name inside. See d9-recording-rename.txt |
| D10 | PASS | The mint layer has a clear shape at three places in the track, in d10-stems.png. It's thin in places, where bass and drums dominate, in d10-all-stems.png |
| D11 | PASS | The bar does drag here: 60% to about 20%, then to 100%. See d11-depth-drag.png |
| E | PASS | The log lists nothing (below). The button shows pause while playing and goes back to play when the mix ends |
| F1 | PASS | Everything's there, with `DEL` on the tab row |
| F2 | PASS | One red pad. The second tap is refused: "There's already a memory cue here." Red triangles on the waveform and overview |
| F3 | FAIL | See Failures |
| F4 | PASS | Jumps to the loop and holds there with the pad lit, then the next tap ends the loop |
| F5 | FAIL | See Failures. On screen it looks right, so the problem only shows in the file or on the next load |
| F6 | FAIL | See Failures. The hot cue's name and colour reach the pad and flag |
| F7 | PASS | Everything saved was there after a relaunch, including the hot cue's name and colour and the sampler's pads. Items "deleted" under F5 were there too, and the F6 switch was off. The decks come back empty |
| G1 | PASS | The row is correct and all eight pads fire |
| G2 | FAIL | See Failures |
| G3 | PASS | Gate: a 0.4 s hold lit the pad for 0.45 s and the meters fell on release. Loop: one tap starts it and the next stops it |
| G4 | PASS | Named `LOOP 1`, set to Loop mode, and goes round. A real 4-beat loop grabbed at 1.348 s, exactly 4 beats at 178 BPM |
| G5 | PASS | A red timer replaces `SET`. The pad holds real audio (mean -13.5 dB, peak 0 dB) and the meters move with the deck stopped. Named `REC 3` |
| G6 | PASS | The pad is `RISER` again and the recording's file is gone |
| G7 | PASS | At the bottom of `VOLUME` the saved level is 0 and the meters nearly empty. `STOP` stops a looping pad |
| H1 | PASS | Three stay lit, and `CRUSH` takes `ECHO`'s place |
| H2 | PASS | `DEPTH` went to 100% during the slide and read 60% after, with the others still lit. Letting go ends the pad I slid on. See Looks wrong |
| H3 | PASS | `OUT` lights and the capsule explains. The meters fell to nothing within about 4 s. The next tap brought the track back further along |
| H4 | PASS | Refuses, but silently. See Looks wrong. Pausing during an echo out and playing again didn't come back silent |
| I1 | PASS | Cycles through all six, and both labels change |
| I2 | PASS | All six, both ways. Nothing went silent, jumped to the top of the meter or crashed. Double-tap brings the knob back. Sound not judged |
| I3 | PASS | Borderline. The meters kept moving for 2.3 to 2.6 s after pausing, against 1.5 s with `DUB` off. That's only about 1 s longer, so please check by ear |
| J1 | PASS | Strips are there. Exhilarate has 2 sections: `CHORUS`, `OUTRO`. Severe Tire Damage has 5: `INTRO`, `CHORUS`, `VERSE`, `CHORUS`, `OUTRO`. The names look wrong |
| J2 | PASS | Counts up and restarts at the boundary: `INTRO 12.3`, then `CHORUS 1.2` |
| J3 | PASS | 178.00 and 170.59 held steady in all 11 samples over 2:00 |
| K1 | PASS | The picker worked and the file saved to Files |
| K2 | PASS | The cue returned, with "Restored 2 tracks and 1 playlists." It also keeps a `Before restore` copy |
| K3 | PASS | Warning triangle, dimmed row. Loading is refused: "Exhilarate's file is missing. Import it again and it'll get its cues back." |
| K4 | PASS | The warning went and all its cues and loops were still there |
| K5 | PASS | `Documents/Backups/Cheeks Library 2026-10-30.json` |

E's log output:
```
getpwuid_r did not find a match for uid 501
Timestamp               Ty Process[PID:TID]
```
The same query over the last hour also listed nothing.

## Timings and measurements
CPU, 30 s after 10 s of settling (30 s after launch for idle), on the pinned process, with stems finished:

| State | This run, average | This run, peak | Last run |
|---|---|---:|---:|
| Idle, nothing loaded | 3.6% | 4.2% | 12.1% |
| Two tracks loaded, paused | 4.5% | 4.9% | 14.7%, then 12.5% |
| One deck playing | 9.1% | 9.3% | 12.2% |
| Both playing and synced, with a tempo offset | 17.8% | 18.1% | 15.4% |
| Both of those, plus a muted stem and an echo | 20.6% | 21.0% | 13.5% |

- These are simulator numbers, so they're only relative.
- The two busiest states are higher than last time. Last run's numbers may not be comparable, because the task now warns that `pgrep -x Cheeks` can find another simulator's copy of the app.
- For the last state, deck 1's vocal was muted and deck 2 had `ECHO` on.

| Measure | Result |
|---|---|
| Crossfader line against its tick | Line centre x = 1426.5 px, tick at about 1426 px, so under 0.2 pt |
| Tempo line against its LED | Line centre y = 1154.5 px, LED centre 1155 px, so about 0.2 pt |
| Crossfader catch | Holds at centre from a finger at about 478.5 pt to about 472.5 pt, with centre at 475.5 pt |
| `DUB` tail after pausing | Meters still moving for 2.3 s and 2.6 s on two runs, 1.5 s with `DUB` off |
| Gate | A 0.4 s press lit the pad for 0.45 s |
| Grabbed 4-beat loop | 1.348 s, with 4 beats at 178 BPM being 1.348 s |
| Stale picture during a load | About 0.2 s |

## First impressions
**1. Does it look like $1000 pro software?**
The main deck screen nearly does. It's dense and consistent, and the jogs and meters look like hardware. Three things break the illusion:
1. **System sheets.** Settings, `LIST`, the sampler sheet, the Files picker and the keyboard use large iOS type and big rounded rows, and they cover the decks. The change of scale feels like leaving the app.
2. **The tab row.** It's tiny, low-contrast text with no visible button shapes, and one shrunken label pressed against `DEL`. Everything else on the surface is more careful than this.
3. **Results that are visibly wrong.** A five-minute `CHORUS`, a counter reading `CHORUS 190.4`, two identical 0:01 pads and a "1/16 beats" loop nobody made all undo the impression of precision.

**2. What felt slow, confusing or surprising?**
- The biggest surprise is that deleted cues come back.
- Tapping a pad just after a tab can fire a pad you can no longer see, which is alarming when it moves the track.
- Sliding on a lit FX pad to adjust it turns it off when you let go.
- `OUT` on a stopped deck appears to do nothing.
- Load a track and there's a wait for stems, shown only as a percentage under the title.
- The Color FX selector isn't obviously a key you cycle by tapping. It just reads `FILTER`.

**3. Which control was hardest to find or hit?**
- **To hit:** `UNDO`. It's 46×18 pt at the very top edge and only there for 8 seconds, when you've just made a mistake. The tab labels come next, since a tap on the right of `SAMPLE` is a tiny distance from `DEL`.
- **To find:** `Record the Master`, which is behind `SET`, then a pad, then a sheet. `LIST` is also easy to miss, as it only appears on the `MEM` page.

---

## What happened next
Everything here was checked against the code first, and each fix below has a test unless it says otherwise.

**Failures, all fixed**
- **F5, F6:** confirmed as reported. `Deck.updateTrack` ran its closure twice, so a new item got two IDs. It runs once now.
- **F3, G2:** confirmed. A held roll or slice left its loop set. It also broke two things nobody had reported: `RELOOP` jumped into the leftover loop, and a roll threw away any loop or waiting `IN` you'd set. Now it gives back what was there.
- **C9:** tabs keep one size, and a long label gets more room instead of shrinking. Not re-measured: see "Still to check".

**Looks wrong, fixed**
- **Tab race:** probably fixed, not proven. Pages faded over 0.12 s, which fits the 0.15 s wait that made it go away, and they now change instantly. A test that hit-tests the screen 40 ms after a tab fails with the fade and passes without it, but with the fade it found the new pad not responding yet, not the old one firing. `S1` in the retest settles this.
- **Same track on both decks:** edits reach the other deck, including grid changes.
- **Sliding on a lit FX pad:** it stays on. A plain tap still lets it go.
- **`OUT` on a stopped deck:** says why.
- **Section names:** a fade-out set the bottom of the scale, so the rest all looked big. Exhilarate is now `CHORUS VERSE CHORUS OUTRO` and Severe Tire Damage has eleven sections. This is better but not proven: nobody has compared them with the music, and the longest section is still about 2 minutes.
- **Stale header picture, `NO TRACK` during a load, loop key stuck at 5:** fixed. The key shows a manual loop's length only while that loop's on.
- **Held pads:** look like any other lit pad.
- **Meter red:** it read after the limiter, with red starting at -1.5 dB. It now reads before the limiter and red starts at 0 dB, so it means the mix is really over.
- **`DUB` (I3):** a real bug. The tail flipped to the bright side when the knob came back, which cut most of it. It now takes about 5 s to fall 40 dB on a test tone. Not yet heard.
- **Backups:** "1 playlist", a confirmation, row order kept on restore, and today's copy now keeps up with the library, at most every 5 minutes and always on going to the background.
- **`UNDO`:** takes touches 6 pt past its edges. It's still only 46×18 pt to look at.
- **Color FX key:** has an arrows icon, to show that it steps.
- **Tab labels:** brighter.

**Left alone, on purpose**
- **System sheets:** the project's rule is that browser and settings screens stay native.
- **The keyboard's height:** it's the system's. The mixer stays put, and the list still scrolls.
- **The loop line behind the bar counter:** dimmed, and the text stays readable.
- **The home indicator:** the app already asks for it to be hidden, and it didn't block any press here.
- **`Record the Master` behind `SET`, and `LIST` only on `MEM`:** the BPM menu also opens the list.

**Not looked into**
- The `UIKit.AnimationKit` faults, the `renderbox` errors and the 4 `NSPredicate` faults: none of them comes from the audio or a crash.
- The two ignored 0.2 s presses, on `Save a Backup…` and the colour well. The report can't say if it's the tool or the app.
- CPU with both decks playing, at 17.8%, up on the last run. The earlier number may have come from the wrong process, so there's no sign it's a regression.

**Still to check:** the retest at the top of `docs/COMPUTER_USE_TASK.md`.

