# Cheeks: notes for Claude

**New session? Read `docs/HANDOFF.md` first.** It covers project status, decisions, and what to do next.

Standalone iOS DJ app (SwiftUI + AVAudioEngine). It's designed for a wide landscape screen: the owner's iPhone Duo unfolded (951×669 pt in landscape), with iPads as a bigger fallback. See README.md for features.

## Build, test, run (macOS with Xcode 16+)

On this Mac `xcode-select` may still point at the Command Line Tools. If `xcodebuild` says it "requires Xcode", prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (no sudo needed), or ask the owner to run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

```sh
# compile
xcodebuild -project Cheeks.xcodeproj -scheme Cheeks -destination 'generic/platform=iOS Simulator' build

# unit tests (offline audio engine and analysis tests)
xcodebuild test -project Cheeks.xcodeproj -scheme Cheeks -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'

# layout snapshots: renders every screen at the Duo, Duo-folded and 13" iPad sizes into a folder (opt-in test)
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
- **iPhone Duo simulator:** it boots folded, so the app shows on the 466-pt-tall cover screen and the inner screen stays black. `simctl` can't unfold it (toggling screen power crashes SpringBoard). Use the layout snapshots for the unfolded size. Its screenshots need `--display=primary` (cover) or `--display=primary-1` (inner).
- **Installing on the phone:** this needs a signing team (`DEVELOPMENT_TEAM`). The owner sets it once in Xcode; don't invent one.

## History

The project was written without a compiler, in a Linux container, so the first build may surface errors. Fix them minimally, in the style of the surrounding code.

## Architecture rules

- **Realtime thread:** `Audio/DeckRenderer.swift` runs on the audio render thread.
  - No allocation, locks (other than the existing `trylock`), Swift arrays growing, or main-actor calls in `render`.
  - Scalars are shared with the main thread without locks on purpose.
- **Main-actor control:** `Deck` and `DJEngine` are `@MainActor @Observable` and hold all control state.
  - The playhead is *not* observed. Views poll `deck.position` from a `TimelineView`.
- **Sample rate and memory:** internal audio is 44.1 kHz (`AudioConfig.sampleRate`).
  - Files decode straight into interleaved Int16 (`PCM16Stereo`). Analysis and stem separation stream over that buffer, so never materialise full-length Float copies.
  - Stems are stored at `stemHeadroom` (×0.5).
- **Signal chain:** renderer → varispeed → timePitch → EQ/filter → delay → reverb → (channel fader → program bus) + (pre-fader cue send → cue bus).
  - varispeed and timePitch are never bypassed, so every deck has the same latency and sync stays phase-accurate.
- **Swift language mode is 5:** keep it that way unless asked.
- **UI style is rekordbox's** (the owner asked for it explicitly): flat black and dark-grey panels, grey legends, one blue (`Theme.accent`) for every "on" state, no gradients or glows. The one deliberate difference is the jog: a big rekordbox-style jog display that's the centre of each deck, because the owner wants large, prominent spinners.
  - Deck 2 is mirrored so each deck's tempo fader and CUE/PLAY sit at the screen edge.
  - Check layout changes with the snapshot test at the Duo size before calling them done.
