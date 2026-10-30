# Cheeks: notes for Claude

**New session? Read `docs/HANDOFF.md` first.** It covers project status, decisions, and what to do next.

Standalone iOS DJ app (SwiftUI, Metal and a C++ audio core hosted in AVAudioEngine). It's designed for a wide landscape screen: the owner's iPhone Duo unfolded (951×669 pt in landscape), with iPads as a bigger fallback. The owner only uses it unfolded, so the folded cover screen (678×466 pt) is deliberately unsupported. See README.md for features.

## Build, test, run (macOS with Xcode 16+)

Shaders need Xcode's Metal toolchain. If a build says it's missing: `xcodebuild -downloadComponent MetalToolchain` (once per Mac).

On this Mac `xcode-select` may still point at the Command Line Tools. If `xcodebuild` says it "requires Xcode", prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (no sudo needed), or ask the owner to run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

```sh
# compile
xcodebuild -project Cheeks.xcodeproj -scheme Cheeks -destination 'generic/platform=iOS Simulator' build

# unit tests (the audio engine rendered offline, analysis, deck behaviour). EngineTests.testRealtimeHeadroom prints a DSP: line
xcodebuild test -project Cheeks.xcodeproj -scheme Cheeks -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'

# layout snapshots: renders every screen at the Duo (unfolded) and 13" iPad sizes into a folder (opt-in test)
TEST_RUNNER_CHEEKS_SNAPSHOT_DIR=/tmp/cheeks-snaps xcodebuild test -project Cheeks.xcodeproj -scheme Cheeks -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -derivedDataPath build -only-testing:CheeksTests/LayoutSnapshots

# memory for a 6-minute track and its stems (opt-in test; prints MEMORY: lines)
TEST_RUNNER_CHEEKS_MEMORY=1 xcodebuild test -project Cheeks.xcodeproj -scheme Cheeks -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -derivedDataPath build -only-testing:CheeksTests/MemoryFootprint

# run in the simulator and screenshot
xcrun simctl boot "iPad Pro 13-inch (M5)" 2>/dev/null
xcodebuild -project Cheeks.xcodeproj -scheme Cheeks -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -derivedDataPath build build
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/Cheeks.app
xcrun simctl launch booted com.nikhilpatel.cheeks
xcrun simctl io booted screenshot screenshot.png
```

- **Simulator names:** list the installed ones with `xcrun simctl list devices available`. Xcode 27 here has no standalone Simulator.app; use `simctl` or the Claude simulator panel.
- **iPhone Duo simulator:** it boots folded, so the app shows on the 466-pt-tall cover screen and the inner screen stays black. Neither `simctl` nor the Claude simulator panel can unfold it (toggling screen power crashes SpringBoard), and the cramped cover-screen layout there is expected. Use the layout snapshots for the unfolded size, and the 13-inch iPad simulator for live tapping. Its screenshots need `--display=primary` (cover) or `--display=primary-1` (inner).
- **Installing on the phone:** this needs a signing team (`DEVELOPMENT_TEAM`). The owner sets it once in Xcode; don't invent one.

## Architecture rules

- **Realtime thread:** `DSP/Engine.cpp` (C++, called through the C API in `DSP/CheeksDSP.h`) runs on the audio render thread.
  - No allocation, locks (other than the existing `TryLock`), or Swift or Objective-C calls anywhere on the render path.
  - Controls reach it through relaxed atomics, and it publishes state back the same way. Swift's `DeckRenderer` is a thin facade over this.
- **`position` means what is being heard.** Audio lives in memory, so the stretcher's input simply reads ahead of `position` by exactly its latency. That's why hot cues are instant with key lock on, why scratching has no time-stretch lag, and why decks stay sample-locked whether or not they're stretched. Keep this invariant.
- **The stretcher is only in the path when needed:** tempo differs with key lock on, or key shift is set. Otherwise audio is read directly, which is bit-exact at normal speed.
- **Any jump in the audio goes through `Declicker`:** seeks, loop wraps, mode changes, play and pause.
- **Signal chain:** stems → FX bus (ahead of the stretcher, so effects can target single stems and stay on the track's beat) → stretcher or direct read → isolator EQ → filter → trim → cue send and fader → program bus → limiter → recording ring → master. Everything renders in one callback on one sample clock.
- **Main-actor control:** `Deck` and `DJEngine` are `@MainActor @Observable` and hold all control state.
  - The playhead and the meters are *not* observed. The live views read them directly from the audio core.
- **Sample rate and memory:** internal audio is 44.1 kHz (`AudioConfig.sampleRate`).
  - Files decode straight into interleaved Int16 (`PCM16Stereo`). Analysis and stem separation stream over that buffer, so never materialise full-length Float copies.
  - Stems are stored at `stemHeadroom` (×0.5).
- **Swift language mode is 5:** keep it that way unless asked.
- **Vendored code:** `DSP/vendor/` is Signalsmith Stretch and Linear (MIT), unmodified. `Bridging.h` is the Swift bridging header, and it includes `UI/Live/ShaderTypes.h`, which Metal also includes.

## UI rules

The look is **rekordbox's screens set into a Pioneer DDJ-style control surface**. The owner rejected flat grey versions as "unpolished" and cheap skeuomorphism as "really bad". What works is density, thin lines, small precise type, and real materials on the hero parts.

- **Anything that moves is drawn in Metal** (`UI/Live/`), by a shared display link that skips any view whose uniforms didn't change. An idle screen costs nothing. Don't put per-frame work in SwiftUI: no `TimelineView(.animation)`, no observed playhead.
- **Hardware parts are pre-rendered once** (`Baked` in `UI/Design/Theme.swift`) and composited as bitmaps. Shadows, blurs and gradients are fine inside a bake, and should be avoided outside one, because they cost GPU time on every frame.
- **Performance controls take touches from UIKit** through `TouchSurface`, not SwiftUI gestures: true multitouch, and they act on first contact. Browser and settings screens are ordinary SwiftUI, and should look and feel native.
- **Everything you touch has a feel:** add a `Haptics.shared` call when you add a control. Use the existing vocabulary instead of raw generators.
- **One blue (`Theme.accent`) for every "on" state.** Hot cues, stems and FX families have their own colours, and they match across pads, waveforms and flags.
- **Respect the system:** `UIAccessibility.isReduceMotionEnabled` for decorative motion, accessibility labels and adjustable actions on controls, continuous corners everywhere.
- **Deck 2 is mirrored** so each deck's tempo fader and CUE/PLAY sit at the screen edge.
- **The Duo has a centre crease when unfolded**, so the mixer sits across it and the waveform playhead sits off-centre.
- **Check visual changes with the snapshot test at the Duo size** before calling them done, using real music (below). Synthetic fixtures make waveforms look much worse than they are.

Snapshot options, on top of `TEST_RUNNER_CHEEKS_SNAPSHOT_DIR`:

```sh
tools/test-music/fetch.sh /tmp/cheeks-music   # two CC tracks, not kept in the repo
TEST_RUNNER_CHEEKS_FIXTURE_A="/tmp/cheeks-music/Exhilarate.mp3"          # real music on deck 1
TEST_RUNNER_CHEEKS_FIXTURE_B="/tmp/cheeks-music/Severe Tire Damage.mp3"  # and deck 2
TEST_RUNNER_CHEEKS_SNAPSHOT_SCREEN=duo                                   # one screen size only
TEST_RUNNER_CHEEKS_SNAPSHOT_ONLY=decks-cue,browser                       # only these views
TEST_RUNNER_CHEEKS_WRITE_ICON=1                                          # also writes AppIcon.png
```

## Testing on the device

Hands-on testing with computer use is scripted in `docs/COMPUTER_USE_TEST.md`, and its results come back in `docs/COMPUTER_USE_RESULTS.md`. Read those results if they exist. Things only the owner can judge (haptics, sound, heat) are in `docs/TEST_PLAN.md` §2.
