# Handoff: read this first

You're picking up **Cheeks**, a standalone iOS DJ app. Until now it was written by Claude in a Linux cloud container with **no Swift compiler and no Xcode**, so it has **never been built or run**. You're on the owner's Mac, so you can finally build, run, test and profile it. Your first job is to get it building and proven. Feature work comes after.

Also read: `CLAUDE.md` (commands and architecture rules), `README.md` (features), `docs/TEST_PLAN.md` (what to do now) and `docs/ROADMAP.md` (what comes after).

---

## 1. The owner and what they want
- **Device:** an "iPhone duo" (their name for it), used **unfolded, in landscape**. The app is designed for a wide landscape screen. Confirm the real screen size: check whether Xcode has a simulator for it. If not, use a large iPad in landscape as the stand-in and ask the owner for the device's resolution.
- **Goal:** a **fully functional, pro-level DJ app in the style of rekordbox**, used **entirely on the phone with no controller**, with pro features like stems. The name "rekordbox" is trademarked, so the app is called Cheeks after the repo.
- **Out of scope by the owner's choice:** hardware (MIDI/controllers, audio interfaces, CDJ link, DVS) and streaming services.
- **Called out as important:** recording a session, including the tracklist.
- **Developer account:** they have a paid Apple Developer account, so device installs last about a year. **The owner picks the signing team in Xcode.** Never invent a `DEVELOPMENT_TEAM`.
- **What they can't do:** they aren't going to debug Swift. They *can* test on the phone by ear and touch. Give them concrete checklists (TEST_PLAN §2) and ask specific questions.

## 2. What exists (about 4,500 lines of Swift)

| Area | Files | Notes |
|---|---|---|
| Realtime playback | `Audio/DeckRenderer.swift` | `AVAudioSourceNode` render callback that owns the playhead. Handles scratch (playhead chases a jog target), loops, slip, brake, reverse, and stem mixing. Lock-free scalars plus `trylock` for swapping sources. |
| Deck control | `Audio/Deck.swift`, `Audio/Deck+Performance.swift` | `@MainActor @Observable`. Load (generation-guarded), CDJ cue, tempo/key lock/key shift, hot cues, loops, rolls, beat jump, sync (half/double, smooth drift correction), stems, beat-grid editing, EQ/filter. |
| Mixer and engine | `Audio/DJEngine.swift` | AVAudioEngine graph. Per deck: renderer → varispeed → timePitch → EQ(3 band + filter band) → delay → reverb, which fans out to the channel fader (→ `program`) and a pre-fader cue send (→ `cueBus`). Split-cue routing via mono mixers panned L/R. Also crossfader curves, Beat FX, a 30 Hz `tick` (sync follow, on-air tracking), and recording. |
| Recording | `Audio/SessionRecording.swift` | Taps `program` into a 24-bit CAF, converts it to AAC/WAV on stop via a temp file, and recovers crash leftovers on launch (with CAF header repair). Writes `.txt` and `.cue` tracklists. |
| Decoding | `Audio/AudioDecoder.swift` | Decodes straight into `PCM16Stereo` (interleaved Int16, growable) at 44.1 kHz. |
| Analysis | `Analysis/*` | A single streaming pass gives the 3-band waveform, onset energies → BPM and grid (autocorrelation plus comb search), and a decimated signal → key (Krumhansl chroma → Camelot). |
| Stems | `Stems/StemSeparator.swift` | `FrequencySplitSeparator` (approximate; the stems sum back to the original) and a `CoreMLStemSeparator` slot for a real model. Stems are stored at ×0.5 headroom. |
| Library | `Model/*` | Tracks and playlists in JSON (debounced saves, backup if unreadable), import from Files and the Documents inbox, duplicate skip, background analysis queue, rekordbox XML import, daily History playlists. |
| UI | `UI/*` | SwiftUI landscape layout: top bar, two waveform strips, deck · mixer · deck, or the browser. Plus the Recordings sheet. |
| Tests | `CheeksTests/*` | Offline tests for analysis, renderer, deck behaviour and the rekordbox parser. Expected values were cross-checked in Python. |
| Python checks | `tools/analysis-check/` | numpy ports of the DSP. Run them after changing analysis or stem code. |

## 3. Decisions and why (don't undo these without a reason)
- **Own render callback instead of AVAudioPlayerNode:** needed for vinyl scratching, sample-accurate loops, slip, and sample-locked stems.
- **Int16 storage, decode-to-Int16, streaming analysis:** memory. Four stems of a 6-minute track are about 250 MB even at 16-bit. Full-length Float copies were removed on purpose.
- **Stem headroom ×0.5:** filtered stems can peak above the source (measured 1.31×). The renderer scales them back up.
- **timePitch and varispeed are never bypassed:** equal latency on every deck. Bypassing at 0% made a synced deck flam.
- **44.1 kHz internally:** matches typical tracks. AVAudioEngine converts to the hardware rate at the output.
- **Swift language mode 5, iOS 17:** avoids strict-concurrency churn. `@Observable` and iOS 17 SwiftUI APIs are used throughout.
- **Debug builds use `-O`:** the realtime callback and analysis are too slow at `-Onone`.
- **Project file:** written by hand (objectVersion 77, file-system-synchronized groups). New `.swift` files in `Cheeks/` or `CheeksTests/` are picked up automatically. If Xcode refuses to open it, recreate a minimal project with the same target names and point it at the folders.
- **Recording safety:** capture to CAF, convert to a temp file, rename, and only then delete the capture. On any failure, keep `"<name> (raw).caf"`.

## 4. How it was checked so far
- **Three independent read-through reviews** looked for compile errors and bugs. Every finding was fixed.
- **Python ports** confirmed the analysis on synthetic tracks:
  - exact BPM at 92 to 174 BPM
  - grid phase within 5 ms
  - correct keys (8A, 10B, 4A)
  - stems summing back to the original
- **The CAF repair walk** was simulated and checked.
- **Never done:** compiling, running, hearing it, seeing the UI, or measuring performance.

## 5. Where the first build is most likely to complain
Reviewers judged these fine but flagged them as worth a look:
- **CGFloat/Double mixing** in `UI/WaveformViews.swift` (e.g. `geo.size.width / secondsVisible`, `zoomBase! / g.magnification`). Wrap operands in `Double(...)` or `CGFloat(...)` if Xcode calls them ambiguous.
- **`PadButton` trailing-closure matching** (`UI/Theme.swift` memberwise init vs the `Label == Text` extension init).
- **Sendable warnings:** `MainActor.run` / `Task.detached` closures capturing non-Sendable `PCM16Stereo`. These should only be warnings in Swift 5 mode.
- **`.task(id:)` in `TopBar`** capturing `dj`.
- **`String(format:)` with `Int` arguments** using `%d`.
- **Runtime, not compile-time:**
  - the AVAudioEngine fan-out graph (`AVAudioConnectionPoint`s, mono mixers into the main mixer). Watch the console for engine assertions at launch.
  - recording format settings when REC is pressed.

**Fix minimally, in the style of the surrounding code.** Note anything surprising in this file for the next person.

## 6. Your first session (definition of done)
Follow `docs/TEST_PLAN.md` §1:
1. **Clean build** for the simulator.
2. **All `CheeksTests` pass.** If an expected value is wrong, check it against the Python ports before changing it.
3. **The app launches** in the simulator with no engine assertions.
4. **Screenshots look right** on a large iPad in landscape for: empty decks, two decks loaded (drag a couple of audio files into the simulator's Files app), the browser, each pad mode, and the Recordings sheet.
5. **Layout fixes** for anything clipped or overlapping.
6. **Allocations profile** with two tracks loaded plus stems; the expected numbers are in TEST_PLAN.
7. **On the phone, once the owner has set the team:** install, then hand them TEST_PLAN §2.

Update `docs/TEST_PLAN.md` and this file with what you learn.

## 7. After bring-up
Work through `docs/ROADMAP.md` Phase 1 in order. The biggest gap is **real AI stems** (HT-Demucs → Core ML with STFT in Swift; the plan is in the roadmap). The Mac can download the model weights; the cloud container couldn't.

## 8. Working agreements
- **Git:** commit in small, validated steps with clear messages. Up to now the owner has had work merged to `master`; confirm before pushing to `master` yourself, and never force-push.
- **Realtime rules** (CLAUDE.md): nothing in `DeckRenderer.render` may allocate, lock (except the existing `trylock`), or touch the main actor.
- **DSP changes:** update `tools/analysis-check/` and the tests together.
- **Testing on the device:** ask the owner to test on the phone for anything you can't verify by ear. Be specific about what to listen or feel for.
- **Keep the docs current:** `README.md`, `docs/TEST_PLAN.md`, `docs/ROADMAP.md`, and this file.

## 9. Open questions for the owner
- The exact device ("iPhone duo") and its unfolded resolution. Does it also need to work folded?
- Which roadmap items they want first after bring-up. AI stems is the recommendation.
- How they'll import music (Files, iCloud Drive, a rekordbox XML export), so you can test that path first.
