# Handoff: read this first

You're picking up **Cheeks**, a standalone iOS DJ app.

Also read: `CLAUDE.md` (commands and architecture rules), `README.md` (features), `docs/TEST_PLAN.md`, `docs/COMPUTER_USE_RESULTS.md` (the first hands-on test, and what was done about it at the end), `docs/COMPUTER_USE_RESULTS_2.md` if it exists, and `docs/ROADMAP.md`. The next hands-on task is `docs/COMPUTER_USE_TASK.md`.

## Status after the rebuild (2026-10-30)

The owner kept rejecting the look ("still looks really bad"), and asked for the whole thing to be redone with real stems, Apple-level polish and haptics. So in one session:

- **Audio engine rewritten in C++** (`DSP/`). It replaces the AVAudioEngine effect chains. See CLAUDE.md for why. Measured on this M1 Pro with both decks on four stems, stretched, with FX on: 2% of realtime on average, worst callback 24%.
- **Interface rebuilt:** Metal for everything that moves, pre-rendered hardware parts, UIKit touch handling and Core Haptics. See CLAUDE.md → UI rules.
- **New:** stem colours on the waveforms, per-stem levels, stem-targeted FX, 12 beat FX, slicer, sampler, beat jump, key sync, loudness matching, artwork, browser preview, sort and filters, drag to load, undo, Lock Screen now playing, settings.

- **Real AI stems:** HT-Demucs on Core ML, with the STFT and overlap-add in Swift. See `tools/stems/README.md` for the full numbers.

**Added afterwards, same day, on the owner's request:** variable-tempo grids, memory cues and saved loops (MEM pads and the cue list), full rekordbox import, library backup and restore with missing-file handling, the sampler's own sounds, FX chains with quantized release and echo out, Color FX, and phrase analysis. See "How far to trust the new features" below.

**Proven:**
- All unit tests pass, including offline click detection, key lock pitch, instant hot cues under key lock, isolator kills, limiter ceiling, a 3-minute sync lock and end-to-end recording.
- `TouchWiringTests` hit-tests the real screen the way UIKit does and presses every control, in every pad mode. So the controls are reachable and wired, but no real touch has gone through them.
- Every screen renders at the Duo and iPad sizes with real music, and the app launches in the simulator with the live Metal path.
- Stems match PyTorch to within 0.005 dB per stem on 34 s clips. A separate scoring script on six MUSDB songs joined into one clip gave drums 8.9 dB, bass 6.6, instruments 5.5, vocals 4.9, against -2 to -7 dB for no separation, and the stems sum back to the mix.
- A 6-minute track takes 15.7 s on this M1 Pro's GPU, using about 575 MB beyond the audio buffers. A cached track comes back in about 0.02 s (12 s clip).

**Not yet proven, because nothing here could touch or hear it:** a real finger, especially near the screen's top and bottom edges, haptic tuning, how it sounds, headphone and split cue routing, and everything on the phone: frame rate, thermals, and above all **how long stems take on the phone's GPU, and whether its Neural Engine behaves as it does on the Mac**. The stems fallback to the CPU when the GPU is unavailable in the background is only tested with a fake loader. The owner covers these with TEST_PLAN §2.

**Auto DJ is in the app, and being tuned by ear (2026-11-01).** `docs/AUTO_DJ.md` has the design, the research and the measurements. `tools/autodj/` is the lab: it drives the real engine from Python, and `app_plan` runs the app's own planner on real tracks. Blind ratings against a crossfade are in the [Listening Room](https://claude.ai/artifact/25J24fKfhoHEMu5QdouQzW), and reading them with `ArtifactData` is how to tune it. No model's been trained: GPUs are on offer from the owner when the ratings show where the rules fall short, and the stem compatibility model is the one to start with. The same work found that the app's first-pass grid was often wrong, so stems now correct it.

**Hands-on testing is a loop now:** the owner told the two Claude sessions to work directly and keep going until told to stop. The computer-use session runs `docs/COMPUTER_USE_TASK.md` and commits its results to local `master`. This side merges, fixes, verifies, pushes, and messages it what to retest. Stay off a simulator while it's testing there.

**First time on a real phone (iPhone 15 Pro Max, 2026-11-02):** it took about 20 s to load things after opening, with "image provider timed out" in the console. Reproduced in the simulator: one time-out per pre-rendered part, on the first launch after an install. `Baked` now draws them into real pixels straight away. In the simulator that's no time-outs, 0.56 to 1.1 s to a free main thread (it was up to 3.85 s), and 30 ms for all 19 parts, with 2,000 tracks adding about 50 ms. It hasn't been tried on the phone yet. "fopen failed for data file" comes from `libCoreFSCache`, a system library, and shows up on a fresh install. It isn't ours.

**How it runs, by `tools/self-tour.sh` in a simulator, on a Mac (nothing's been measured on a phone):** with no stems splitting, pad pages, loading tracks and moving knobs freeze nothing for 50 ms or more. Playing two decks takes about 15% of a core and about 190 MB, and a library of 2,000 tracks adds about 50 ms to launch. Opening the browser was the slowest thing left, and rebuilding the screen was what it cost. The browser and decks now stay built (`Offstage` in CLAUDE.md), so 24 opens on the old and new code, one after the other on the same Mac, went from about 4 freezes and 380 ms frozen in all to usually none at 50 ms or more, with the worst at 52 ms, and closing went from about 230 ms to usually none, worst 96 ms. That costs about 16 to 20 MB. With both decks' stems splitting on the CPU, it's about 190% of a core and about 800 MB, and the screen stays responsive. SwiftUI builds a shader of its own on a fresh install, which took from under a second to 3.7 s here depending on what the Mac was doing, and 0.66 s for one on the phone. That isn't ours to avoid.

**After the fifteenth hands-on test:** 48 of 54 passed on b70f85f, with 2 failures, 4 blocked, no crashes, and three new problems, all fixed: the mixer sheet's knobs hardly moved on a phone, as the sheet's own drag took the touch, `PLAYLISTS` couldn't be asked about on its side, and a new deck's fader came up without a word. A first-time user took 34 minutes to see what Auto DJ does, so the `STEMS` tab now shows which parts are in from any page, and the message points there. `BROWSE` reads `DECKS` while the browser's open, `MIX` on a list without what's playing plays the whole list, played tracks have a tick, and a phone can preview. Still unchecked: pressing during the slide on a full layout, as the Duo's folded and the iPad's touch access hasn't been granted. See the end of `docs/COMPUTER_USE_RESULTS_15.md`. **Next after the bugs:** a "go now" in a mix, and changing what's next without ending it.

**After the fourteenth hands-on test:** 62 of 68 passed on f20dbe9, with 2 failures, 4 blocked, no crashes, and five new problems, all fixed: `AUTO` late in a Loop build left the new deck playing in silence, `MIX` refused with "needs two tracks" when `NEXT` was hiding one, a recording's play button went grey with no reason, `MIX` only refused from the bottom row with everything played, and a playlist couldn't be renamed upright. A mix now keeps saying which list it's on. A new test also showed the first analysis misreading music with long silence after it, by up to 36%. See the end of `docs/COMPUTER_USE_RESULTS_14.md`. The slide's steady gap was the mixer running a frame behind, even in Release, and a panel-coloured backing now covers it. The first slide's freeze is the render server, not the app's code. **The Duo is folded until the owner presses Open in Device Hub,** and pressing during the full layout's slide still wants that, or the iPad's touch access. The next retest is at the top of `docs/COMPUTER_USE_TASK.md`.

**After the thirteenth hands-on test:** 48 of 53 passed on 95ce321, with 2 failures, 3 blocked by the Duo's stuck recorder, no crashes, and three new failures from a first-time user who had its full 46 minutes. All five are fixed: `MIX` from part-way down a list stopped after two tracks, the master was silent while waiting for stems with the crossfader away, a track going quiet long before its end left silence, the `FILTER` knobs and key disagreed after a plan, and black opened between the panels as the browser slid. See the end of `docs/COMPUTER_USE_RESULTS_13.md`. The mixer can still fall behind the panels on the first slide after launch, and the next retest is at the top of `docs/COMPUTER_USE_TASK.md`.

**After the twelfth hands-on test:** 74 of 77 passed on 6fc9a2c, with 3 blocked by the Duo's stuck recorder, no crashes, and three new failures nobody had asked about, all fixed: `AUTO` running out into silence while waiting for stems, `PLAY` setting a hot cue when pressed just after closing the browser, and long messages cut on the Duo. Sections are named from the stems now. See the end of `docs/COMPUTER_USE_RESULTS_12.md`. The next retest is at the top of `docs/COMPUTER_USE_TASK.md`.

**After the eleventh hands-on test:** 23 of 33 passed on f264c0a, with 4 failures, 3 blocked, 3 only reported and no crashes. The list's place and the file picker are confirmed by real touches through the tester's tool. A first-time user went from nothing to a mix in 1:33 on the smallest screen, and found `?` from its hint, though it knew general DJ words and had seen a line in the git log. See the end of `docs/COMPUTER_USE_RESULTS_11.md`. Next round runs Parts 1 and 2 again, for the first time since the screen was rebuilt.

**After the tenth hands-on test:** 26 of 40 passed on 53a0201, with 6 failures, 1 blocked, 7 only reported and no crashes. Idle CPU is back to 3%, and the browser opens and closes with no freeze of 100 ms or more with 2,005 tracks, both decks playing and a recording. See the end of `docs/COMPUTER_USE_RESULTS_10.md`, including what's still open: the Files folder won't open in the simulator, and a list's place can only be shown by touches through the tester's tool, as a UI test's press doesn't set off the gesture behind it. `?` on the top bar is new since then, and nobody who doesn't know DJ gear has read its notes. The next retest is at the top of `docs/COMPUTER_USE_TASK.md`.

**After the ninth hands-on test:** 75 of 90 passed on a9d454b, with 6 failures, 9 only reported and no crashes, and a 16-minute long run with no dropout. See the end of `docs/COMPUTER_USE_RESULTS_9.md`. The next retest is at the top of `docs/COMPUTER_USE_TASK.md`.

**After the eighth hands-on test:** 25 of 30 passed, on 970a91f, with 2 failures and no crashes. All of round 7's failures held. See the end of `docs/COMPUTER_USE_RESULTS_8.md`. The next round is bigger: the retest, a first-time user, a big library, and Parts 1 to 3, which hadn't been run since round 2.

**After the seventh hands-on test:** 46 of 54 passed, on fdcacdc, with no crashes. The worst was Auto DJ auditioning the wrong decks from deck 2, and the rest was what happens when someone takes over mid-move. See the end of `docs/COMPUTER_USE_RESULTS_7.md`. The next retest is at the top of `docs/COMPUTER_USE_TASK.md`.

**After the fifth hands-on test:** 23 of 24 passed, on c5eeab6, with no crashes. See the end of `docs/COMPUTER_USE_RESULTS_5.md`. The next retest is at the top of `docs/COMPUTER_USE_TASK.md`.

**After the fourth hands-on test:** 23 of 24 passed, on edd906b, with no crashes. See the end of `docs/COMPUTER_USE_RESULTS_4.md`.

**After the third hands-on test:** 21 of 22 passed, on 05feeed, and the tab race held on 29 of 29 synthetic tries. See the end of `docs/COMPUTER_USE_RESULTS_3.md`, which also has a bug nobody had reported: with every knob centred, the channel's EQ was raising loud masters' peaks by up to 5 dB. The next retest, including a harder round, is at the top of `docs/COMPUTER_USE_TASK.md`. Section names have only been judged from the numbers, with nobody listening.

**After the second hands-on test:** 53 of 58 passed, on 97e6a30. See the end of `docs/COMPUTER_USE_RESULTS_2.md`.

**After the first hands-on test:** 66 passed and 3 failed. Those, and the "Looks wrong" list, have been worked through: see the end of `docs/COMPUTER_USE_RESULTS.md`. Three things to know:
- **The Undo failure was never reproduced.** The control's been rebuilt on the evidence available, so it needs the task doc's retest and the owner's finger.
- **There's now a UI test target** (`tools/ui-tests.sh`), so a Claude without computer use can drive the real app with real touch events and take screenshots. Use it. It found bugs reading the code didn't.
- **Product calls are yours to make.** The owner has said they don't know what DJ software usually does and wants Claude to decide things like these three, so decide and report it instead of asking:
  - The header BPM now follows the tempo, matching the jog. The track's own speed is in the BPM menu and the browser.
  - Level knobs keep their white arcs, and tone knobs their blue ones.
  - Stem colours show on the `STEMS` tab, and also anywhere else while a stem is muted or turned down, because the normal waveform can't show that.

**How far to trust the new features:**
- **Section names** come from the stems once they're ready (`TrackMapSections.swift`, `TrackMapSectionsTests`), and they read like real arrangements on 49 real tracks: 38 club tracks and 11 of rock, pop and the test tracks. Nobody's checked them by ear yet. Rock is the weak spot, as a loud master hardly moves in level: a long run gets split where nobody's singing or it's clearly quieter, which is a guess. The mix-only `PhraseAnalyzer` only shows until the stems arrive, or with stems turned off, and it's been left as it was (`PhraseTests`). Build-ups fade in, so where an UP starts is approximate.
- **Tempo maps:** a band-style speed-up lands within 8 ms of the kicks, and a step change is followed. The guard against false maps (`fitThreshold` in `TempoMapDetector`) rests on one real steady track that came out at a ratio of 1.17. No real live-played track has been tried. If a map's wrong, the BPM menu's "Use one steady tempo" undoes it, per track.
- **Color FX, FX chains and sampler** are tested for being bounded, doing something, and timing (a quantized pad lands within 2 frames of the grid), but nobody has heard them. The pitch Color FX is a simple delay-line shifter and may sound watery.
- **Library catch-up:** tracks analysed before phrases existed get re-analysed in the background, but only while no deck's playing and the phone isn't hot.
- **Memory:** the three FX links and Color FX add about 16 MB in total. Worst case with everything on measures 2.4% of realtime on average and 25% in the worst callback on this M1 Pro.

**Before distributing the app:** see `docs/RELEASE.md`. The Demucs maintainer has said the weights are for research and that a real app is out of scope, so this blocks a public release. Personal use is fine. The options, with Spleeter measured on the owner's tracks, are in there.

**Still open:**
- **Install on the phone** once the owner picks a signing team.
- **Releasing it publicly:** the owner wants it on all iPhones. The layouts are started, and the app now rotates and resizes (`UIRequiresFullScreen` is gone). Before release: the stem model's licence (below), a lawyer's look at how closely the design follows one maker's gear, and real-device testing. The privacy manifest is in.

**Surprises worth knowing:**
- The iPhone Duo is a real simulator here (iOS 27.2).
  - Inner screen: 2007×2853 px @3x, which is **669×951 pt (951×669 landscape)**.
  - Cover screen: 466×678 pt.
  - The owner named the app Segue DJ on 2 Nov 2026. The name still has to be reserved in App Store Connect and checked by a trademark lawyer; MegaSeg DJ, a Mac DJ app, is the closest name found so far.
  - It boots folded, and a reboot folds it again. Nothing on the command line can unfold it. Apple's docs put the control in Device Hub, Xcode 27's device window: select the Duo, then the Open pose button under the bezel. It's unfolded on this Mac now, and if a UI test prints a window that isn't 951×669, it's folded again.
  - `XCUIScreen.main` is the cover screen, which is black. UI tests screenshot the app's window instead, and those can come out rotated.
- Xcode 27 ships no standalone Simulator.app.
- Metal layers don't appear in `drawHierarchy`, so the snapshot test sets `LiveRenderer.captureMode` and each live view paints itself into an image overlay. Animations that start from zero (waveform reveal, ring sweep) skip to the end in that mode.
- `origin` is an HTTPS remote and this shell has no credentials for it, but the owner's SSH key works: `git push git@github.com:NikhilAPatel/Cheeks.git master:master`.

---

## 1. The owner and what they want
- **Device:** an iPhone Duo, used **unfolded, in landscape, never folded**: 951×669 pt (see Status above). Design for that size first; the 13-inch iPad is a larger check.
- **Goal:** a **fully functional, pro-level DJ app in the style of rekordbox**, used **entirely on the phone with no controller**, with pro features like stems. The name "rekordbox" is trademarked, so the app is called Cheeks after the repo.
- **Out of scope by the owner's choice:** hardware (MIDI/controllers, audio interfaces, CDJ link, DVS) and streaming services.
- **Called out as important:** recording a session, including the tracklist.
- **Developer account:** they have a paid Apple Developer account, so device installs last about a year. **The owner picks the signing team in Xcode.** Never invent a `DEVELOPMENT_TEAM`.
- **What they can't do:** they aren't going to debug Swift. They *can* test on the phone by ear and touch. Give them concrete checklists (TEST_PLAN §2) and ask specific questions.

## 2. What exists

| Area | Files | Notes |
|---|---|---|
| UI tests | `CheeksUITests/`, `tools/ui-tests.sh`, `tools/measure-cpu.sh` | The real app, real touch events, either screen size. `measure-cpu.sh` measures each state on a pinned process. |
| Realtime core | `DSP/Engine.cpp`, `Primitives.hpp`, `BeatFX.hpp`, `ColorFX.hpp`, `CheeksDSP.h` | Decks, stretcher, isolator EQ, filter, FX chain, Color FX, mixer, limiter, recording ring, sampler with capture, preview. One callback, one clock. |
| Deck control | `Audio/DeckRenderer.swift`, `Deck.swift`, `Deck+Performance.swift` | `DeckRenderer` is a facade over the core. `Deck` is `@MainActor @Observable`: load (generation-guarded), CDJ cue, tempo, hot cues, loops, rolls, slicer, jump, sync, stems, FX, grid editing. |
| Mixer and engine | `Audio/DJEngine.swift` | Hosts the core in one `AVAudioSourceNode`. Mix controls, crossfader, master tracking, sync follower, on-air tracking, recording, preview. |
| Recording | `Audio/SessionRecording.swift` | The render thread writes a lock-free ring; `RecordingDrain` moves it to a 24-bit CAF, converted to AAC or WAV on stop through a temp file. Crash leftovers are recovered on launch (with CAF header repair). Writes `.txt` and `.cue` tracklists. |
| Decoding | `Audio/AudioDecoder.swift` | Decodes straight into `PCM16Stereo` (interleaved Int16, growable) at 44.1 kHz. |
| Analysis | `Analysis/*` | One streaming pass: 3-band waveform at 300 bins/s, onset energies → BPM and grid, decimated signal → key, BS.1770 loudness. |
| Stems | `Stems/*` | See README → Stems. |
| Library | `Model/*` | Tracks and playlists in JSON (debounced saves, backup if unreadable), import from Files and the Documents inbox, duplicate skip, background analysis queue, rekordbox XML import, History playlists, artwork and waveform thumbnails. |
| Live visuals | `UI/Live/*` | `LiveRenderer` (display link, skip-unchanged), `Shaders.metal`, waveform, overview, jog, meter and phase views. |
| Design system | `UI/Design/*`, `UI/Controls/*` | Theme, `Baked`, `TouchSurface`, `Haptics`, keys, pads, knobs, faders. |
| Screens | `UI/Deck/*`, `UI/Mixer/*`, `UI/Browser/*`, `UI/Shell/*` | The deck panel, pad modes, mixer, browser, recordings, top bar, status capsule, settings. |
| Tests | `CheeksTests/*` | Offline engine, analysis, deck and rekordbox tests. Opt-in `LayoutSnapshots` and `MemoryFootprint`. |
| Python checks | `tools/analysis-check/`, `tools/stems/` | numpy ports of the DSP; the stem model conversion. |

## 3. Decisions and why (don't undo these without a reason)
- **C++ core instead of AVAudioEngine effects:** AUTimePitch's latency made hot cues and scratching lag, its chains couldn't be sample-locked or sent single stems, and its shelf EQ couldn't truly kill a band. All of this is now testable offline.
- **Signalsmith Stretch:** MIT-licensed, good quality at DJ tempo ranges. Avoid Rubber Band unless a commercial licence is bought (it's GPL).
- **Int16 storage, decode-to-Int16, streaming analysis:** memory. Four stems of a 6-minute track are about 250 MB even at 16-bit. Full-length Float copies were removed on purpose.
- **Stem headroom ×0.5:** separated stems can peak above the source. The renderer scales them back up.
- **44.1 kHz internally:** matches typical tracks. AVAudioEngine converts to the hardware rate at the output.
- **Swift language mode 5, iOS 17:** avoids strict-concurrency churn.
- **Debug builds use `-O` (Swift) and `-O3` (C++):** the realtime path and analysis are too slow otherwise.
- **Project file:** written by hand (objectVersion 77, file-system-synchronized groups). New files in `Cheeks/` or `CheeksTests/` are picked up automatically, and that includes anything that isn't code, which gets copied into the app.
- **Recording safety:** capture to CAF, convert to a temp file, rename, and only then delete the capture. On any failure, keep `"<name> (raw).caf"`.
- **Waveforms are scaled by tempo** so that matched beats line up between decks on screen.

## 8. Working agreements
- **Git:** commit in small, validated steps with clear messages. The owner said (2026-10-30) to commit straight to `master` and gave full push access. Never force-push.
- **Realtime rules** (CLAUDE.md): nothing on the render path in `DSP/` may allocate, lock (except the existing `TryLock`), or call Swift.
- **DSP changes:** update `tools/analysis-check/` and the tests together.
- **Testing:** for anything needing hands on the UI, use the UI tests (`tools/ui-tests.sh`) first, and extend `docs/COMPUTER_USE_TASK.md` for what they can't judge. For ears and fingers on the phone, ask the owner, and be specific about what to listen or feel for.
- **Keep the docs current:** `README.md`, `docs/TEST_PLAN.md`, `docs/ROADMAP.md`, and this file.

## 9. Open questions for the owner
- How they'll import music (Files, iCloud Drive, a rekordbox XML export), so that path gets tested first.
