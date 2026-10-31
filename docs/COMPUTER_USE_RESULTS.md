# Hands-on results, 2026-10-30

Commit tested: e38dcc3

**Device: iPhone Duo simulator, unfolded (951×669 pt), not the 13-inch iPad the script names.** The iPad was built, installed and launched for A1–A3, but the access prompt for driving it timed out, so I couldn't tap it. The Duo already had access, so every test that needs touch ran there. It's the owner's real target and is smaller than the iPad, but nothing past A3 has been checked at iPad size.

Tooling limits:
- **Haptics:** the simulator has none, so nothing about them was tested.
- **Sound:** I couldn't hear anything. Audio checks use the app's own recordings, compared with the source MP3. That covers the master mix only, so the headphone output and split cue routing are unverified.
- **Touch:** synthetic only. The two-finger tool worked for pinch and H5, but a real finger may behave differently, especially at screen edges.
- **Tap length:** default taps last about 10 ms. System switches ignored them (Settings needed a 0.2 s press). Taps sent while a sheet was closing were lost.
- **Coordinates:** the simulator tool reports a 678×466 space, but taps actually land in 951×669.
- **Screenshots:** downscaled to 1600 px wide and reduced to 256 colours to keep the repo small, so any banding comes from that, not the app. Screen video runs at about 30 fps, so anything shorter than a frame or two can be missed.
- **Another process:** a second `Cheeks` appeared on an iPad Air 13-inch (M4) simulator at 16:21:41 and restarted at 16:28:29, using 50–144% CPU at times. I didn't start it and left it alone. `pgrep -x Cheeks` can return it, so I pinned the Duo's PID for all measurements.

## Summary
**PASS 66, FAIL 3, BLOCKED 0** (69 tests). No crashes and no crash reports.

The 3 most important problems:
1. **Hot cue Undo does nothing (D3, FAIL).** The delete works and the capsule offers Undo, but five taps across different press lengths never brought the cue back.
2. **The master meters show levels that aren't there (Looks wrong).** With both decks stopped and no audio, they sweep through the red `LIM` zone every time the browser opens or closes.
3. **The CPU never settles when nothing is happening (N2, FAIL).** With two tracks paused, the screen draws nothing, yet the app stays at 12–15%. That's the same as idle and no lower than playing.

The third failure, C5, is safe but silent: tapping a load key for a playing deck correctly doesn't load, but gives no shake and no message.

## Failures

### C5: A tapped load key gives no feedback when the deck is playing
- Steps: Play deck 1. Open the browser. Tap `1` on a track not loaded on deck 1.
- Expected: the button shakes, and a capsule at the top says deck 1 is playing. The track doesn't change.
- Actual: the track doesn't change, but the `1` key is just dimmed and dead. No shake or capsule appeared in a 3.3 s recording.
- The refusal message does exist: swiping the same row right shows "Deck 1 is playing. Stop it first." That capsule has a green tick, which reads as success.
- Screenshots: docs/test-results/c5-refused.png, docs/test-results/c5-refused-swipe.png
- Pointer: `Cheeks/UI/Browser/BrowserView.swift:361` sets `isEnabled: !deck.isPlaying` on the key, which may be why the tap never reaches any refusal code.
- Crash report: none

### D3: Undo doesn't restore a deleted hot cue
- Steps: Set a hot cue. Tap `DEL`, which lights red. Tap the cue: it's removed, `DEL` turns off, and the capsule says "Deleted hot cue A" with **Undo**. Tap Undo straight away.
- Expected: the cue comes back.
- Actual: it stays deleted. The pad stays unlit, the capsule stays up after the tap, and `library.json` still shows `hotCues: {}`.
- Attempts, all at the centre of the word Undo, which I confirmed by cropping the screenshot:
  - two default taps at y=14, deck playing
  - a 250 ms press at y=13, deck playing
  - a default tap at y=19, deck paused
  - a 120 ms touch at y=14
- Caveat: the same synthetic taps work on other SwiftUI buttons, such as the sort headers and Recordings' Play. But this one sits in a 24 pt capsule at the very top edge of the screen, where a system edge gesture could interfere, so please retest with a real finger on the phone.
- Screenshots: docs/test-results/d3-del-armed.png, docs/test-results/d3-undo.png, docs/test-results/d3-after-undo-tap.png
- Pointer: `Cheeks/UI/Shell/ContentView.swift:335`
- Crash report: none

### N2: Two loaded, paused decks don't use "very low" CPU
- Steps: Load both tracks, stay paused, wait 10 s, then sample for 30 s.
- Expected: very low, because nothing is being drawn.
- Actual: 14.7% by `top` (14.2% by `ps`), and 12.5% on a repeat. That matches idle with nothing loaded (12.1%) and one deck playing without contention (12.2%).
- The drawing claim itself holds: a 6 s screen recording while paused captured a single frame. So the cost is something other than drawing. I didn't try to find out what.
- Caveat: simulator numbers are relative, and GPU work on the Mac isn't counted in the app's CPU. Check this on the phone.
- Crash report: none

## Looks wrong
Most important first. Sizes and positions are on the Duo.

**Meters and readouts**
- **Fake meter movement:** with both decks stopped, opening or closing the browser runs all four master meter columns through red and back down, in about 1.5 s. It looks like the launch animation replaying. Screenshot: b1-meter-flourish-no-audio.png
- **Top bar capsules cover the `MASTER` readout:** the end of the number pokes out beside the capsule, for example ".59". This happens with Undo, the refusal message, and "Saving your mix…". Screenshots: d3-undo.png, c5-refused-swipe.png
- **The header BPM doesn't follow the tempo:** at +8.5% the header says 170.59 while the jog says 185.16. After sync, deck 2's header says 178.00 while the jog says 170.59. Screenshots: f1-tempo-down.png, f2-synced.png
- **`LIM` is on at default levels:** with both decks playing and an echo on, at default faders, the `LIM` light is lit and the meters touch red. One deck also touches red at the top. Screenshots: n5-stems-echo.png, l1-recording.png. A single-deck recording came out 5.2 dB below the source and no window went quiet or distorted in the comparison, so this may be only the meter's scale.
- **The sync marker flips to amber:** it stayed centred, but 3 of 11 samples were amber rather than green, about 5 px (at 3×) left of centre. Screenshot: f3-marker-2min.png

**Layout**
- **Fader caps are off centre:** at exactly zero, the crossfader's index line sits about 6 pt left of the centre tick, and the tempo cap sits about 6 pt above the green centre LED. Double-tap reset lands in the same place. Screenshots: h3-crossfader-centre-offset.png, a-relaunch-empty.png
- **The mixer overflows when the keyboard is up:** its top row (`TRIM`, `MASTER`) spills out of the panel onto the waveform area. Screenshot: b4-search.png
- **Stop-recording popover:** its arrow points at the middle of the screen, not `REC`, and "Keep recording" isn't visible, so you cancel by tapping outside. Screenshot: l2-confirm.png
- **Tab row:** `SAMPLER` is set smaller than the other tabs and almost touches `DEL`. Screenshot: c1-loaded.png
- **Truncated titles:** "Severe Tire Damage…" is cut off in the list with room left in the column beside it, and shortens to "Severe Tir…" on the compact deck. Screenshot: b1-browser.png
- **Unused strip:** a band of empty chassis, about 35 pt tall, runs along the bottom of every screen. Screenshot: c1-loaded.png
- **Loop line over the label:** the loop start line cuts through the `BARS` label. Screenshot: e1-autoloop.png

**Feedback**
- **`SOLO` pads don't light up** while soloing, so the pad doesn't show which stem is soloed. Screenshot: i5-macros-solos.png
- **Quick taps show nothing on sampler pads:** across all recorded frames, pad 1 stayed the same brightness when tapped, though synthetic taps are very short. A held slicer pad is also only slightly brighter than the others. Screenshot: e6-slicer-tab.png
- **`IN` shows no marker** until you press `OUT`. Screenshot: e3-manual-loop.png
- **Stale header on load:** for about 0.6 s, the header shows the previous track's details with a dash for the time.
- **Knob arcs:** `TRIM`, `MASTER`, `CUE/MST` and `LEVEL` have white arcs, where the script expects blue. This may be deliberate. Screenshot: h1-knobs-moved.png
- **Stem waveform detail:** `INST` draws as a flat mint band with little internal detail, unlike the 3-band view. Screenshot: i2-stems.png

**Logs** (no engine assertions, see A3)
- 67 faults of `UIKit.AnimationKit:DebugAssertion`: "Decomposition of 'position'/'bounds' was requested… while a composite animation is already running". The first was at 15:47:15, during the browser tests.
- 30 or so `renderbox` errors at launch: "image provider timed out while waiting for phase 2".
- `AVAudioSession` "Hang Risk" fault at 16:34:56, around Recordings playback (L3).
- At launch: "`UIRequiresFullScreen` will soon be ignored" and "Support for all orientations will soon be required". This matters for a landscape-only app.

**Problems with the test script**
- The setup's `| tail -1` prints a blank line, because xcodebuild's output ends with one, so "BUILD SUCCEEDED" never shows. The build did succeed, with 0 warnings.
- A3's `grep -iE 'error|fault|assert'` also matches "Default" and "assertion", so its 30 lines are almost all harmless. Filtering on `messageType == error OR messageType == fault` is more useful.
- `open -a Simulator` fails here, as the script warned.

## All results
| Test | Result | Notes |
|---|---|---|
| A1 | PASS | No crash on iPad or Duo. First launch about 3 s of black, later launches about 1.6 s. Blue ring sweep seen on video on a later launch, but missed on the first (dropped frames). Meters still falling at launch + 4 s. a1-launch is the iPad, a-relaunch-empty the Duo |
| A2 | PASS | Both analysed in ≤4 s (iPad), ≤5 s (Duo). Exhilarate 170.59, 12B. Severe Tire Damage 178.00, 5A. "Analysing…" seen in the top bar. BPM and key accuracy not verified |
| A3 | PASS | No engine assertions, crashes or app-specific errors. Not spotless: 42 Error/Fault lines in the launch window, see below |
| B1 | PASS | Slides in, mixer moves right, compact decks above the list. Meter sweep replays |
| B2 | PASS | Coloured letter tiles and tiny waveforms drawn (no artwork in these files) |
| B3 | PASS | `TITLE`, `BPM`, `KEY` and `TIME` all sort, and a second tap flips the order and arrow. Rows slide with 33 in-between frames over about 0.35 s, no jump |
| B4 | PASS | Filters as you type, ✕ clears, "No Results" appears |
| B5 | PASS | Dims, stop icon, line moves. Tapping another row switches to it. Tapping again stops. Sound not heard |
| B6 | PASS | All four items present, plus Add to Playlist |
| B7 | PASS | Right loads deck 1, left loads deck 2 |
| B8 | PASS | Blue outline on hover, loads on drop. The context menu flashes up before the drag starts |
| B9 | PASS | Created Warmup, added a track through the submenu, count 1, selecting it filters the list |
| C1 | PASS | Titles, BPM, coloured waveforms and time all shown |
| C2 | PASS | Opens from the centre line in about 0.1 s, after about 0.6 s blank |
| C3 | PASS | Everything moves, icon becomes pause. Steady 32 fps on video (a capture limit), no gap over 50 ms, with stems separating in the background |
| C4 | PASS | `PLAY` pauses. `CUE` jumps to 00:00.4 and stops |
| C5 | FAIL | No shake or capsule on tap. Track unchanged. See Failures |
| C6 | PASS | Tapping 75% along jumped to 01:50 of 2:25 |
| D1 | PASS | Pad lights with letter and 0:24, flag on both waveforms. Stored time lands exactly on a beat |
| D2 | PASS | Jumped from bar 33.2 back to the cue, landing just past the flag as a beat-locked jump should. "In time" judged visually only |
| D3 | FAIL | Delete works, Undo doesn't. See Failures |
| E1 | PASS | Region, orange ring arc and lit `EXIT`. Playhead wraps 99.4 back to 99.1 cleanly |
| E2 | PASS | Went 2 to 8 with the region resizing. `EXIT` leaves, `RELOOP` jumps back in |
| E3 | PASS | `IN` then `OUT` makes a loop |
| E4 | PASS | All 8 lengths work. Tapping the lit pad exits |
| E5 | PASS | Held 1/8 roll about 2.4 s, went from bar 50.3 to 52.2 (7 beats, 2.46 s) |
| E6 | PASS | Held pad 3 about 2.4 s, went from bar 67.2 to 69.3 (7 beats) |
| E7 | PASS | All 8 pads and the ±4 keys jump correctly. The number cycles 4, 8, 16, 32, 1, 2, 4 |
| F1 | PASS | +8.54% updates the label and jog (185.16), and the waveform compresses. Stops at exactly +0.00 (+0.25 doesn't catch). Double-tap resets. Range cycles ±10, ±16, WIDE, ±6, ±10 |
| F2 | PASS | Deck 2 to 170.59 (−4.16%), blue cap, beat lines within 2–3 px at 3×, marker centred |
| F3 | PASS | Marker centred in all 11 samples over the last 1:47 of about 2:20 synced, until deck 1 ran out. 3 samples amber |
| F4 | PASS | Amber light moves, deck 2 sync off, top bar `MASTER 2` |
| F5 | PASS | 12B to 7B at +1 and 9B at +3. `KEY SYNC` set −1, giving 5B, compatible with deck 2's 5A |
| G1 | PASS | One clockwise turn moved 01:01.8 to 01:03.6 (1.8 s per turn), then back. Platter lights |
| G2 | PASS | Follows in both directions. Back at normal speed on the first frames after release |
| G3 | PASS | A 270° ring drag added about 0.75 s (expected 0.81) without stopping |
| G4 | PASS | Scrubs both ways. Pinch zooms both decks together. Double-tap resets |
| H1 | PASS | All 8 on deck 1 and the centre section turn. `HI` sticks at centre. Double-tap resets. Deck 2's knobs not tried |
| H2 | PASS | Channel meter keeps moving, master meters drop to nothing |
| H3 | PASS | Master meters drop at the far side and stay high at the near side. Sticks at centre, though the catch is under 1 pt each way. Double-tap centres |
| H4 | PASS | `CUE` keys and `SPLIT` light and unlight. Audio routing not checked |
| H5 | PASS | Two-finger tool: held a roll pad while moving a fader, both tracked |
| I1 | PASS | Model present. Starts on load, percentage counts up to 96%, then green dot and `AI`. 50 s for 2:25, 128 s for 6:52. i1-progress-row.png |
| I2 | PASS | Stem colours appear, almost no pink as expected. They only show while the `STEMS` tab is open |
| I3 | PASS | Pad dims at once, layer drops to a ghost, restores. `NO VOCAL` lights by itself |
| I4 | PASS | Dark band shows the level, layer dims and brightens, stem stays on |
| I5 | PASS | `ACAPELLA`, `NO VOCAL`, `BEAT`, `ALL` and all 4 `SOLO` work. Soloing again restored the earlier state, including vocals off. `ALL` leaves a slid level where it was |
| I6 | PASS | Reload opens in stem colours in about 0.5 s. After relaunch: no percentage, CPU 9–12% 10 s after loading, no new cache file. Time to `AI` after relaunch not measured exactly |
| I7 | PASS | No gap or jump in the waveform, bars continuous, change takes about a frame. Audio gap not measured |
| I8 | PASS | 532.5 MB straight after separating, 656 MB after relaunch and loading from cache |
| J1 | PASS | No crashes. All 12 light while held. The 10 non-stopping effects each changed the recorded audio, then returned to dry. `BRAKE` and `BACKSPIN` lights go out early, as the deck stops |
| J2 | PASS | `ECHO` stays lit after a quick tap, second tap turns it off |
| J3 | PASS | Up and down moves `DEPTH` from about 95% to about 5%. Sideways changes the beat value. Both stay after release |
| J4 | PASS | `V`, `I`, `B` turn off. `D`, the last one, refuses |
| J5 | PASS | `BRAKE` slows to a stop over about 1.5 s. `BACKSPIN` rewinds about 0.7 s and stops. Play button returns to stopped |
| K1 | PASS | Meter at rest with no deck playing, then jumped for all 8 pads |
| L1 | PASS | Widens, turns red, running timer. Later shows track count |
| L2 | PASS | Asks first. "Saving your mix…" for under 0.5 s, then "Saved Mix…" for about 4.5 s |
| L3 | PASS | Listed 1:06, 2.2 MB, M4A. Play toggles, audio matches the source with no gaps. Tracklist shown. Rename changes all 3 files, but the `.cue` title and `.txt` heading keep the old name, and renaming stops playback |
| L4 | PASS | `.m4a`, `.txt` and `.cue` present |
| M1 | PASS | Standard iOS grouped form. RGB and back works, all 3 toggles work and persist. Curve and Format pickers seen but not changed |
| M2 | PASS | 11 s away: time went −02:08.5 to −01:55.6, so playback continued. Visuals running on return |
| M3 | PASS | Pad B at 1:44 and its flag survive terminate, relaunch and reload |
| M4 | PASS | Killed 21 s in. "Recovered Mix…" about 3 s after launch. Listed at 0:21, tracklist kept, audio matches. The decks come back empty |
| N1 | PASS | Measured, see table |
| N2 | FAIL | Not "very low", see Failures |
| N3 | PASS | Measured |
| N4 | PASS | Measured |
| N5 | PASS | Measured |

**A3 output** as requested, cut to 170 characters per line with non-printing characters removed:

```
2026-10-30 15:38:30.923 Df Cheeks[43845:1030d1] [com.apple.xpc:connection] [0x104680500] failed to do a bootstrap look-up: xpc_error=[3: No such process]
2026-10-30 15:38:30.949 Df Cheeks[43845:10304d] [com.apple.avfaudio:avae]      AVAudioIONodeImpl.mm:235   Engine@0x1044fc180: associating with audio session (0x0), error
2026-10-30 15:38:31.006 Df Cheeks[43845:1030d5] [com.apple.coreaudio:ddagg]        AggregateDevice.mm:887   Creating DefaultDeviceAggregate
2026-10-30 15:38:31.029 Df Cheeks[43845:1030d5] [com.apple.coreaudio:aqme]           AQMixEngine.cpp:741   AQMEDevice (0x1046e0268) has neither a defaultOutStreamClient n
2026-10-30 15:38:31.044 Df Cheeks[43845:1030d4] [com.apple.coreaudio:aqme]  MEDeviceStreamClient.cpp:248   AQME Default-InputOutput: client starting: <CA_UISoundClientBas
2026-10-30 15:38:31.099 Df Cheeks[43845:10304d] [com.apple.amp.mediaplayer:RemoteControl] [RCC:0x103a3eb10:MediaRemote-DefaultPlayer] initWithPlayerPath:  LOCL   com.nikh
2026-10-30 15:38:31.099 Df Cheeks[43845:10304d] [com.apple.amp.mediaplayer:RemoteControl] [RCC:0x103a3eb10:MediaRemote-DefaultPlayer] _startMediaRemoteSync | MRMediaRemot
2026-10-30 15:38:31.103 Df Cheeks[43845:1030d2] [com.apple.coreaudio:aqme]  MEDeviceStreamClient.cpp:248   AQME Default-InputOutput: client starting: <RemoteIOClient@0x10
2026-10-30 15:38:31.103 Df Cheeks[43845:10304d] [com.apple.amp.mediaremote:MediaRemote] Set:   LOCL   com.nikhilpatel.cheeks (43845)   default  setting ActivePlayerPa
2026-10-30 15:38:31.104 Df Cheeks[43845:10304d] [com.apple.amp.mediaremote:rr] Request: setNowPlayingPlayer<3BE29B0F-9540-44DD-8132-AD60E2E33483> for   LOCL   com.nikhilp
2026-10-30 15:38:31.104 Df Cheeks[43845:10304d] [com.apple.amp.mediaplayer:RemoteControl_Oversize] [RCC] reevaluateCanBeNowPlayingApplication: canBeNowPlayingApplication=
2026-10-30 15:38:31.113 Df Cheeks[43845:10312a] [com.apple.amp.mediaremote:rr] Response: setNowPlayingPlayer<3BE29B0F-9540-44DD-8132-AD60E2E33483> returned for   LOCL (iP
2026-10-30 15:38:31.144 Df Cheeks[43845:103100] [com.apple.UIKit:BackgroundTask] Creating new assertion because there is no existing background assertion.
2026-10-30 15:38:31.144 Df Cheeks[43845:103100] [com.apple.UIKit:BackgroundTask] Creating new background assertion
2026-10-30 15:38:31.145 Df Cheeks[43845:103100] [com.apple.UIKit:BackgroundTask] Created new background assertion <BKSProcessAssertion: 0x1046b9900>
2026-10-30 15:38:31.145 Df Cheeks[43845:103100] [com.apple.UIKit:BackgroundTask] Incrementing reference count for background assertion <BKSProcessAssertion: 0x1046b9900>
2026-10-30 15:38:31.149 Df Cheeks[43845:10304d] [com.apple.runningboard:general] Added observer for process assertions expiration warning: <_RBSExpirationWarningClient: 0
2026-10-30 15:38:31.158 Df Cheeks[43845:10304d] [com.apple.dt.xctest:Default] Registering for test daemon availability notify post.
2026-10-30 15:38:31.158 Df Cheeks[43845:10304d] [com.apple.dt.xctest:Default] notify_get_state check indicated test daemon not ready.
2026-10-30 15:38:31.158 Df Cheeks[43845:10304d] [com.apple.dt.xctest:Default] notify_get_state check indicated test daemon not ready.
2026-10-30 15:38:31.159 Df Cheeks[43845:10304d] [com.apple.dt.xctest:Default] notify_get_state check indicated test daemon not ready.
2026-10-30 15:38:31.173 Df Cheeks[43845:10304d] [com.apple.app_launch_measurement:ApplicationLaunch] alm_acquire_pageins_recording_assertion: acquired pageins recording a
2026-10-30 15:38:31.176 Df Cheeks[43845:10304d] [com.apple.UIKit:BackgroundTask] Reusing background assertion <BKSProcessAssertion: 0x1046b9900>
2026-10-30 15:38:31.176 Df Cheeks[43845:10304d] [com.apple.UIKit:BackgroundTask] Incrementing reference count for background assertion <BKSProcessAssertion: 0x1046b9900>
2026-10-30 15:38:31.180 Df Cheeks[43845:10304d] [com.apple.BacklightServices:scenes] 0x10b4b7210 setDelegate:<0x10b4b6cd0 _UIBacklightEnvironment> hasDelegate:YES for env
2026-10-30 15:38:31.182 Df Cheeks[43845:10304d] [com.apple.GenerativeModels:availability] UserDefaults(com.apple.gms.availability, 501
2026-10-30 15:38:31.193 Df Cheeks[43845:10304d] [com.apple.BackBoard:EventDelivery] [BKSHIDEventObserver] 0x10b494fc0 _UIKeyWindowSceneObserver-0x10b4b6d00 setToken:com.a
2026-10-30 15:38:31.193 Df Cheeks[43845:10304d] [com.apple.UIKit:KeyWindow] Setting default evaluation strategy for UIUserInterfaceIdiomPad to LastOneWins
2026-10-30 15:38:31.193 Df Cheeks[43845:10304d] [com.apple.UIKit:KeyWindow] Scene target of keyboard event deferring environment did change: target=1; ancestor=0; scene:
2026-10-30 15:38:31.193 Df Cheeks[43845:10304d] [com.apple.UIKit:KeyWindow] Scene became target of keyboard event deferring environment: UIWindowScene: 0x10b444780; scene
```

These are all Default-level lines, including the `-10879` engine line. The real Error and Fault lines in the same window (42 on the iPad) were mostly simulator audio-device messages (`EnhanceDialogueProcessor`, `MEMixerChannel`, `audioanalytics`), plus the `renderbox` and `UIRequiresFullScreen` lines listed under Looks wrong.

## Timings and measurements

**Launch and import**
| What | Result |
|---|---|
| First launch after install, to UI | about 3 s |
| Later launch, to UI | about 1.6 s |
| Import and analyse both tracks | ≤4 s (iPad), ≤5 s (Duo) |

**Stems** (simulator, CPU only)
| What | Result |
|---|---|
| 2:25 track | 50 s, 2.9× realtime, deck playing |
| 6:52 track | 128 s, 3.2× realtime, deck paused |
| 2:25 track on the very first run, other loads overlapping | 106 s |
| CPU while separating | 130–300% |
| Reload from cache in the same session | about 0.5 s |
| Cache on disk | 103 MB and 291 MB, about 42 MB per minute of audio |

**Memory**
| What | Result |
|---|---|
| Both decks on stems (I8), straight after separating | 532.5 MB |
| Both decks on stems (I8), after relaunch, from cache | 656 MB |
| Peak while separating one track | about 1.0 GB |
| Peak with loads overlapping | about 1.32 GB |

**CPU** (N1–N5): 10 s settle, then `ps` every 5 s for 30 s (7 samples), with `top` alongside (6 samples).
| State | `ps` %CPU | `top` %CPU | RSS | Notes |
|---|---|---|---|---|
| N1 Idle, nothing loaded | 14.1 | 12.1 | 296 MB | |
| N2 Two loaded, paused | 14.2 | 14.7 | 685 MB | Repeat: 12.3 / 12.5, 414 MB |
| N3 One deck playing | 9.6 | 9.5 | 572 MB | Other `Cheeks` using about 50%. Clean repeat: 12.0 / 12.2, 456 MB, tempo −4.16% |
| N4 Both playing, synced, tempo offset | 13.8 | 13.8 | 318 MB | Other `Cheeks` using about 144%. Clean repeat: 15.1 / 15.4, 497 MB |
| N5 N4 plus stems and echo | 13.0 | 13.5 | 382 MB | |

**How the states compare:** they barely differ. Using the clean runs, everything falls between 12% and 15%, so playing, stretching, stems and an echo together add about 3 points. Nearly all the cost is a baseline that doesn't drop at idle. RSS isn't comparable between states, because it fell over time at the same load.

**Audio checks from the app's recordings** (against the source MP3, per 0.5 s window; the difference is how far the spectrum's shape moved from the source)
| Recording | Result |
|---|---|
| Dry take (L3), 66 s | Lines up throughout, mean difference 0.10 dB, max 0.5 dB |
| Recovered take (M4), 21 s | Mean 0.08 dB, max 0.2 dB, no quiet windows |
| Dry level | 5.2 dB below the source at default fader and crossfader |

| Effect, 1.5 s hold, beat 1/2 | Largest difference | Other change |
|---|---|---|
| `ECHO` | 3.5 dB | Level up about 5 dB |
| `PING PONG` | 5.8 dB | |
| `SPIRAL` | 5.1 dB | Tail lasts about 3.5 s |
| `REVERB` | 4.2 dB | |
| `FLANGER` | 2.9 dB | |
| `PHASER` | 4.6 dB | |
| `FILTER` | | Highs down about 7 dB |
| `TRANS` | | Level ducks about 13 dB |
| `CRUSH` | 6.5 dB | |
| `ROLL` | 10.4 dB | |

## First impressions

**1. Does it look like $1000 pro software?**
On the decks screen, at first glance, yes. The platters, dense layout and meters look like a high-end controller, and that's further than I expected. The illusion breaks when you look longer or leave that screen. The three biggest breaks:
1. **The meters move with nothing playing.** They run through red when you open the browser. On pro gear a meter is something you trust, and this is the thing most likely to make a DJ distrust the app.
2. **Stock iOS pieces on top of a custom hardware look.** There's the floating glass "Stop recording?" popover with its misplaced arrow, a capsule sitting on the `MASTER` readout with ".59" poking out, and a full phone keyboard. The Settings and Recordings sheets are tidy, but they feel like a different app.
3. **The stems styling.** The bright pink, mint, blue and yellow pads and the flat mint waveform band look like a toy next to the restrained controls around them. Smaller, but in the same spot: the crossfader cap sits visibly off its centre mark, right in the middle of the mixer.

**2. What felt slow, confusing or surprising?**
- **Slow:** stems took 50 s and 128 s here, and loading a track starts that work by itself at 130–300% CPU and about 1 GB. Nothing on the compact decks shows it's happening, because the percentage is only in the `STEMS` tab.
- **Confusing:**
  - Two BPM numbers disagree once the tempo moves, and the larger jog one is the real one.
  - `DEPTH` looks like a slider, but dragging it does nothing. You can only change it by sliding on a held pad.
  - Stem colours disappear when you leave the `STEMS` tab, and the loop keys are gone on the `STEMS` and `FX` tabs.
  - `ROLL` and `SLICER` pads silently change the loop-size key (32 became 1/8).
- **Surprising:**
  - When a track ends, the master moves and the other deck's sync turns off with no message.
  - After a crash, the recording comes back but both decks are empty, which would hurt mid-set.
  - Renaming a recording stops its playback and closes its tracklist.
  - The long-press menu flashes up just before a row starts dragging.

**3. Which control was hardest to find or hit?**
`Undo`: small, at the very top edge, gone after 5 s, and it never worked for me. After that, judging by size on screen rather than with a real finger:
- the crossfader's centre, whose catch is under 1 pt each way, so double-tap is the only practical way to centre it
- the key shift `−` and `+` buttons and the beat jump arrows, at about 20 pt
- `DEL`, squeezed in at the end of the tab row
- the small `CUE/MST` and `LEVEL` knobs

---

## What happened next (added by the engineer, not the tester)

Fixed on the `features` branch. "UI test" means the real app driven by real touch events through `tools/ui-tests.sh`, which now runs at both the Duo and 13-inch iPad sizes. None of this has had a real finger on it yet, and nothing has been heard or felt.

**The failures**
| Item | What was actually wrong | What changed | Checked by |
|---|---|---|---|
| D3 Undo | **Not confirmed.** Seven combinations of deck state and press length all worked under XCUITest, so it doesn't reproduce with that tool. But it was the only SwiftUI `Button` on that bar, and every `TouchSurface` key at that height worked under both tools | Rebuilt as a `TouchSurface` key acting on first contact. Stays up 8 s instead of 5 | UI test, paused and playing. **Needs the task doc's retest and a real finger** |
| C5 refused load | The tap did reach the key, which only buzzed. Nothing said why | Key shakes and says why. Refusals show a hand, not a green tick | UI test (message), screenshot. The shake itself wasn't filmed |
| N2 idle CPU | Six 0.1 s `TimelineView`s kept SwiftUI's display link running, re-rendering its whole view graph every frame: about 11% of the main thread | The clocks read an observed clock that only changes when a number would | Duo simulator, pinned process: idle about 4.4%, paused about 4.1%, playing 13 to 15%. The drawing the report called out was never the cost |

**Looks wrong**
| Item | Cause | Result | Checked by |
|---|---|---|---|
| Fake meter movement | The launch sweep was timed from each meter being built, and the mixer was rebuilt when the browser opened or closed | Timed from launch, and the mixer stays one view. The jog's ring had the same problem | Unit test, UI test screenshots |
| Capsule covering `MASTER` | It floated over the bar | Laid out in the bar, so it can't overlap | UI test |
| Fader caps 6 pt off | Their 6 pt shadow margin was taken out of the space they used, but not added to what was drawn, so they were also too small | Index line on the tick and LED | Full-resolution crops |
| Mixer overflow with keyboard | The whole layout shrank | Only the list makes way | UI test, at both sizes |
| Stop-recording popover | On this screen a confirmation dialog becomes a popover, which drops its cancel button | An alert with both answers | UI test |
| `SOLO` not lighting | Never told to | Lights while soloed | UI test |
| Sampler taps showing nothing | **Real bug:** the flare was set and animated away in one step, so it was never drawn on any pad | A keyframe track, and sampler pads stay lit while sounding | Screenshot |
| Sync marker amber | **Real bug, and more than cosmetic:** a read could land between the two decks being published, showing 256 frames of drift that wasn't there. The sync follower could act on it too | Positions published together under a sequence lock. The render thread never waits | Test rendering on another thread: 256 frames apart before, 0 after. The marker itself still needs watching |
| `LIM` on at default levels | Measured with real tracks: one deck reaches 0.4 dB at worst. Both at full go over 0.5 dB for 11% of the time, 3.2 dB at worst | **Not changed:** that's the limiter doing its job | `LevelTests` |
| Unused strip | The home indicator's safe area, about 38 pt | Used. Needs a real finger near that edge | Screenshot |
| Others | | `IN` marker, stale header, truncated titles, loop line through the label, `SAMPLER` label, roll changing the loop key, flat `INST` band, recording rename, stems progress on compact decks | Unit tests and screenshots |
| `AVAudioSession` warning | `AVAudioPlayer.play()` on the main thread in Recordings. Reproduced within a second of pressing play. The engine's own session calls were already off the main thread: 20 launches, no warning | Playback has its own queue | UI test plus the log: none with playback running |

**Found while checking, not in the report**
- **The jog said `NO TRACK` with a track playing** if it was built while the deck was loading, because `isLoaded` didn't read `isLoading` when the deck was empty.
- **The previous track's loop was drawn on a newly loaded track**, because a load only cleared the loop's switch.

**Doesn't reproduce**
- **`DEPTH` not dragging:** a UI test drags it from 60% to 100% at both sizes. It's in the task doc to settle.

**Not changed**
- **Waiting on the owner:** white knob arcs, stem colours only on the `STEMS` tab, and the header's BPM.
- **By design, left alone:** the loop keys aren't on the `STEMS` and `FX` pages, and when a track ends the other deck becomes master and its sync turns off.
- **Not looked into:**
  - the `UIKit.AnimationKit:DebugAssertion` faults: none in about an hour of UI tests, but those don't drag rows or open context menus, so they may still be there
  - the launch `renderbox` errors: still there
  - decks coming back empty after a crash, and renaming a recording stopping its playback
