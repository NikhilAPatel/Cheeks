# Cheeks: notes for Claude

Standalone iOS DJ app (SwiftUI + AVAudioEngine). It's designed for a wide landscape screen: an unfolded foldable iPhone, or an iPad as a stand-in. See README.md for features.

## Build, test, run (macOS with Xcode 16+)

```sh
# compile
xcodebuild -project Cheeks.xcodeproj -scheme Cheeks -destination 'generic/platform=iOS Simulator' build

# unit tests (offline audio engine and analysis tests)
xcodebuild test -project Cheeks.xcodeproj -scheme Cheeks -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)'

# run in the simulator and screenshot
xcrun simctl boot "iPad Pro 13-inch (M4)" 2>/dev/null; open -a Simulator
xcodebuild -project Cheeks.xcodeproj -scheme Cheeks -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' -derivedDataPath build build
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/Cheeks.app
xcrun simctl launch booted com.nikhilpatel.cheeks
xcrun simctl io booted screenshot screenshot.png
```

- **Simulator names:** list the installed ones with `xcrun simctl list devices available`.
- **Installing on the phone:** this needs a signing team (`DEVELOPMENT_TEAM`). The owner sets it once in Xcode; don't invent one.

## History

The project was written without a compiler, in a Linux container, so the first build may surface errors. Fix them minimally, in the style of the surrounding code.

## Architecture rules

- **Realtime thread:** `Audio/DeckRenderer.swift` runs on the audio render thread.
  - No allocation, locks (other than the existing `trylock`), Swift arrays growing, or main-actor calls in `render`.
  - Scalars are shared with the main thread without locks on purpose.
- **Main-actor control:** `Deck` and `DJEngine` are `@MainActor @Observable` and hold all control state.
  - The playhead is *not* observed. Views poll `deck.position` from a `TimelineView`.
- **Sample rate:** internal audio is 44.1 kHz (`AudioConfig.sampleRate`). Audio is held as interleaved Int16 (`PCM16Stereo`) to keep memory down with 4 stems.
- **Signal chain:** renderer → varispeed → timePitch → EQ/filter → delay → reverb → (channel fader → program bus) + (pre-fader cue send → cue bus).
- **Swift language mode is 5:** keep it that way unless asked.
