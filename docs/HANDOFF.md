# Handoff: read this first

You're picking up **Cheeks**, a standalone iOS DJ app.

Also read: `CLAUDE.md` (commands and architecture rules), `README.md` (features), `docs/TEST_PLAN.md`, `docs/COMPUTER_USE_TEST.md`, `docs/COMPUTER_USE_RESULTS.md` if it exists, and `docs/ROADMAP.md`.

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

**Not yet proven, because nothing here could touch or hear it:** real touch delivery, haptic tuning, how it sounds, and everything on the phone: frame rate, thermals, and above all **how long stems take on the phone's GPU, and whether its Neural Engine behaves as it does on the Mac**. The stems fallback to the CPU when the GPU is unavailable in the background is only tested with a fake loader. `docs/COMPUTER_USE_TEST.md` covers touch. The owner covers the rest with TEST_PLAN §2.

**How far to trust the new features:**
- **Phrase analysis** gets the kinds and hard edges right on synthetic arrangements (`PhraseTests`). On real music it's only been run on two tracks, neither club music, with no ground truth to compare to: it came out coarse, with long CHORUS sections. Expect to tune `minimumSectionDifference` and the labelling once it's run on the owner's music. Build-ups fade in, so where an UP starts is approximate.
- **Tempo maps:** a band-style speed-up lands within 8 ms of the kicks, and a step change is followed. The guard against false maps (`fitThreshold` in `TempoMapDetector`) rests on one real steady track that came out at a ratio of 1.17. No real live-played track has been tried. If a map's wrong, the BPM menu's "Use one steady tempo" undoes it, per track.
- **Color FX, FX chains and sampler** are tested for being bounded, doing something, and timing (a quantized pad lands within 2 frames of the grid), but nobody has heard them. The pitch Color FX is a simple delay-line shifter and may sound watery.
- **Library catch-up:** tracks analysed before phrases existed get re-analysed in the background, but only while no deck's playing and the phone isn't hot.
- **Memory:** the three FX links and Color FX add about 16 MB in total. Worst case with everything on measures 2.4% of realtime on average and 25% in the worst callback on this M1 Pro.

**Before distributing the app:** the Demucs code is MIT, and states no separate terms for its weights, but they were trained partly on MUSDB18, which is non-commercial. Personal use is fine. Get a real answer before anything commercial.

**Still open:**
- **Install on the phone** once the owner picks a signing team.
- **The folded cover screen** (678×466 pt) is deliberately unsupported: the owner only uses it unfolded.
- iOS 27 warns that `UIRequiresFullScreen` "will soon be ignored" and that all orientations will soon be required. A landscape-only app may be forced to handle portrait or resizing in a later iOS.

**Surprises worth knowing:**
- The iPhone Duo is a real simulator here (iOS 27.2).
  - Inner screen: 2007×2853 px @3x, which is **669×951 pt (951×669 landscape)**.
  - Cover screen: 466×678 pt.
  - It boots folded and `simctl` can't unfold it, so the layout snapshot test is the way to see the unfolded size.
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
- **Testing:** for anything needing hands on the UI, extend `docs/COMPUTER_USE_TEST.md`. For ears and fingers on the phone, ask the owner, and be specific about what to listen or feel for.
- **Keep the docs current:** `README.md`, `docs/TEST_PLAN.md`, `docs/ROADMAP.md`, and this file.

## 9. Open questions for the owner
- How they'll import music (Files, iCloud Drive, a rekordbox XML export), so that path gets tested first.
