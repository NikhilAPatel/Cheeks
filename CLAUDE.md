# Cheeks: notes for Claude

**New session? Read `docs/HANDOFF.md` first.** It covers project status, decisions, and what to do next.

Standalone iOS DJ app (SwiftUI, Metal and a C++ audio core hosted in AVAudioEngine). It's designed first for a wide landscape screen, the owner's iPhone Duo unfolded (951×669 pt) or an iPad, and every other screen gets a compact layout (`UI/Shell/CompactScreen.swift`). See README.md for features.

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

# the real stem model, in the simulator on the CPU: separates a clip, and runs a deck through split, cache and reload (opt-in)
TEST_RUNNER_CHEEKS_STEM_MODEL=1 xcodebuild test -project Cheeks.xcodeproj -scheme Cheeks -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -derivedDataPath build -only-testing:CheeksTests/StemModelTests

# the real app driven by real touch events (see CheeksUITests/). Prints UITEST: lines, and screenshots go to $CHEEKS_UI_SHOTS
tools/ui-tests.sh "iPhone Duo"
tools/ui-tests.sh "iPad Air 13-inch (M4)" -only-testing:CheeksUITests/UndoAndRefusalTests

# CPU in each state, on this simulator's own process (it takes a few minutes)
tools/measure-cpu.sh "iPhone Duo"

# where launch time goes: each step, each shader and pre-rendered part, every freeze of 100 ms or more, and CPU and memory
SIMCTL_CHILD_CHEEKS_LAUNCH_LOG=1 xcrun simctl launch --console-pty --terminate-running-process "iPhone 17" com.nikhilpatel.cheeks

# what freezes the app: its own walk round itself, with a big library and nothing touching it (Cheeks/App/SelfTour.swift)
# CHEEKS_PERF_STEMS=1 lets stems split during it. CHEEKS_SELF_TOUR=1 and CHEEKS_LAUNCH_LOG=1 do the same on a phone
CONFIG=Release tools/self-tour.sh "iPhone 17" 2000

# the same driven by a UI test, for the browser's sorting and typing. A UI test freezes the app itself whenever it looks at
# the screen, so believe tools/self-tour.sh over this: pad pages read 130 to 250 ms here and nothing at all there
tools/perf-tour.sh "iPhone 17" 2000

# run in the simulator and screenshot
xcrun simctl boot "iPad Pro 13-inch (M5)" 2>/dev/null
xcodebuild -project Cheeks.xcodeproj -scheme Cheeks -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -derivedDataPath build build
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/Cheeks.app
xcrun simctl launch booted com.nikhilpatel.cheeks
xcrun simctl io booted screenshot screenshot.png
```

- **Simulator names:** list the installed ones with `xcrun simctl list devices available`. Xcode 27 here has no standalone Simulator.app; use `simctl` or the Claude simulator panel.
- **iPhone Duo simulator:** it boots folded, so the app shows on the 466-pt-tall cover screen and the inner screen stays black. `simctl` can't unfold it (toggling screen power crashes SpringBoard), but it's currently unfolded on this Mac, and UI tests reach it at 951×669. If a UI test prints a different window size, use the layout snapshots for the unfolded size. Its screenshots need `--display=primary` (cover) or `--display=primary-1` (inner).
- **Measuring the app:** other simulators can be running their own `Cheeks`, so never use `pgrep -x Cheeks`. Get the PID from that simulator's `launchctl list`, matching `UIKitApplication:com\.nikhilpatel\.cheeks\[`, since the UI test runner's name starts the same way.
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
- **Beats go through `BeatGrid`** (`Model/BeatGrid.swift`), never `bpm` and `firstBeat` sums, because a track can change tempo. `Deck.bpm`, `beatFrames` and `firstBeatFrame` describe the section at the playhead, and `Deck.tick` tells the core when that changes. Use `beatPosition(frame)` and `frame(atBeat:)` for anything spanning more than a beat.
- **Edit a loaded track through `Deck.updateTrack`:** its closure runs once, so anything it creates has one ID in both the deck and the library. A deck holding the same track picks the change up.
- **A held roll or slice borrows the loop** (`BorrowedLoop`) and gives back what was set, running or not, so nothing else finds its tiny loop afterwards. A loop that was running comes back where it would have got to. Going somewhere else during one (a seek, a cue, a recalled loop) ends it through `endMomentaryPads`, and letting go of the pad afterwards does nothing.
- **A held control whose view goes away has been let go:** `Key`, `Pad` and `TransportButton` release from `onDisappear`, since a touch never ends once its view has gone. They keep that in a `Hold` object and not in `@State`, which can't be read back until the next update. Anything that holds a touch itself also lets go on `willResignActive`, as `TouchSurfaceView` and `JogLiveView` do, or the system takes about 5 s to cancel it.
- **`SLIP` pressed during a reverse starts from then,** the same as during a running loop. Two touches in one event come in no fixed order.
- **The render thread reads slip once per chunk** (`slipHolding`, in `applyCommands`), never per sample, and `cheeks_deck_slip_release` writes the release before it turns slip off. A release can land partway through a block, and read per sample the return point followed the deck for the rest of it, so the jump back went nowhere. Commands that come in pairs need this care: think about the render thread seeing one and not the other.
- **PLAY pressed during a load waits for the track** (`Deck.startsWhenLoaded`). It lights at once, a second press or `CUE` takes it back, and another load forgets it.
- **A frame sent as the app goes away never reaches the screen,** though the view thinks it drew it. `LiveRenderer` makes everything draw afresh on `didBecomeActive`, and when `nextDrawable` gives nothing. A view that skips unchanged frames has to allow for this.
- **A running loop holds in reverse too,** wrapping from its start back to its end. Only a deck that was in the loop gets caught, so a loop waiting further on doesn't, and a jog goes where the hand takes it.
- **A deck going backwards stops at the start of the track,** and `PLAY` says why it can't start from there.
- **A deck that's run out starts again from its cue, on `PLAY` or `CUE`,** and `CUE` doesn't move the cue while it's at the end. A roll held past the end of the track does stop the deck on release, because that's where the track would have got to.
- **The same track on both decks shares one split** (`StemJob.shared`), with the same buffers. It stops only when every deck waiting for it has gone.
- **A loop can be waiting up ahead** (`Deck.isLoopAhead`): on, but the deck hasn't reached it. Anything that moves the deck or the loop has to allow for that. Go through `leaveLoop(ifGoingTo:)` when moving the deck, or a loop behind it pulls it straight back.
- **Once a track's stems are ready, its drums correct its grid** (`Analysis/TrackMap.swift`, `Deck.applyTrackMap`), once. The first analysis of a mix had the wrong 1 on 8 of 16 club tracks and sat about 100 ms late on 4, so even `SYNC` could flam. A grid set by hand or brought from rekordbox (`Track.gridSource == .person`) is never replaced, and any grid edit has to set that. Try changes to the map in `tools/autodj/analyze.py` first, and check a port with `tools/autodj/compare_map.py`.
- **Auto DJ performs a score in the audio core** (`AutoDJ/`, `CheeksAutoStep`), which runs at the top of every block, so a move lands within one block. Don't time moves from the main thread. The rules in `TransitionMove` hold for every move: one bassline, handed over on a downbeat; one kick; two vocals never overlap; harmony overlaps only when it agrees. See `docs/AUTO_DJ.md`.
- **Ratings lean on what Auto DJ chooses and never rule a move out** (`TransitionRatings`, kept on the device). The question sits in the status capsule for 8 s, and any new message takes it away, so `AutoDJ.advanceSet` holds back its `Up next` while it's asking.
- **`NEXT` orders a list by tempo first, then key, from what's on the deck** (`SetOrder`). It runs in the browser's body, so `keyTable` keeps it off the strings: 2,000 tracks have to sort without a hitch.
- **The browser keeps how its list is showing** (`@AppStorage`: the playlist, the sort, `NEXT` and the filters), because it closes every time someone goes back to the decks. **A playlist stays in the order it was built** unless a column's been chosen, and that's the order `MIX` plays. A column's third tap goes back to that.
- **`MIX` is Auto DJ through the list on screen** (`AutoDJ.mixSet`, `advanceSet`). It only ever plans between moves, gives each track its time (`TransitionPlanner.setExit`), and leaves out the brake drop. Anyone loading the waiting deck, starting it or stopping the playing deck ends it. If nothing passes from as far back as it'll look, it echoes out from where it would have left, into where the next track's beat comes in, at that track's own tempo (`TransitionChoice.echoOut`). Pressing `AUTO` goes straight to that. Without stems or a map there's no move at all, and the next track starts when the last one has nothing left to hear (`PCM16Stereo.lastSound`, -50 dB), so the music never just stops. `tools/autodj/app_set/` runs a whole set through the real planner without playing it.
- **On a stretched deck, stems and beat FX are heard `cheeks_deck_stem_lag` late,** about 125 ms, because they go in ahead of the stretcher. A score sends them that much early, plus a moment for the gain to open. Without it a drop's first kick is gone, 60 dB down.
- **Every plan gets auditioned before it's played** (`TransitionAudition`): rendered offline faster than real time, and rejected if the drop lands low, there's a hole or a bump, or the limiter's pushed. It catches let-downs. It isn't taste. A score's steps name real decks, so its private engine has each track on that deck. Anything else that replays a score has to do the same, and `app_set` goes back and forth between the decks as a real mix does.
- **A control the score's moving belongs to whoever touched it last.** Setting one from the screen releases it from the score through `Deck.onManualControl`. Showing what the score did goes through `Deck.followAuto`, which doesn't, and `followControls` skips a control that's been released, because the core stops reporting it. At the end of a move the old deck goes back to neutral, and on the new deck what someone took stays as they set it.
- **A move that's cut short ends on the next tick** (`AutoDJ.endEarly`), once the core can't be writing to the controls. Up to `TransitionScore.handover` the old track is what people hear. `AUTO` before that leaves the decks to you, and after it ends the move with the new deck on. Stopping the new deck before it leaves the old one playing clean, and after it stops both. Stopping the old deck brings the new one in at once. What the screen can't show (the score's effects, its noise) never stays behind, and a new deck nobody's heard goes back as it was (`Prepared`), the same as calling it off before the clock starts.
- **A stem that's all the way down counts as off** (`Deck.stemIsHeard`), on the pad and in what a tap does: a tap brings it back, and any combination brings its stems up to full. `stemsOn` alone doesn't mean it can be heard, as Auto DJ can leave levels at 0.
- **Track is Codable by hand:** a new field needs a line in `init(from:)` using `decodeIfPresent`, or every existing library stops loading.
- **Beat FX are a chain of `CHEEKS_FX_LINKS` `BeatFX` units**, ahead of the stretcher. Color FX (`DSP/ColorFX.hpp`) sit after the EQ, in real time, so their beat length allows for the tempo.
- **Beat FX are level-compensated:** at their default depth they stay out of the red on the test tracks, and within about 1.5 dB of dry. The flanger mostly leaves out the lows. `LevelTests.testBeatFXLevels` measures it with real music, as the screen shows it: one peak over 0 dB holds a red LED up for 1.1 s, so what counts is the meter's top, not how often it's over. An echo out's tail goes back to full level, because there's nothing left to leave room for.
- **The isolator is out of the path with every band at 1.** Its bands add back flat but with the phase turned, which raised a loud master's peaks by 5 dB. It crossfades in as the first knob leaves centre.
- **A deck's meter is `Deck.level`:** after TRIM and loudness matching, ahead of the fader, and read 3 dB down. The master meters read ahead of the limiter. Red on either means it's really too hot.
- **Sampler voices each have a `Declicker`**, including loop wraps. Press and stop are last-one-wins in the C API, so a stale stop can't eat a new press.
- **Two decks' positions come from `DJEngine.positions`,** not one `playhead` each: those can be read between two decks being published, a whole block apart. The engine publishes them together under a sequence lock, and the render thread never waits.
- **Audio session calls stay off the main thread,** including `AVAudioPlayer.play()`, which activates the session. `RecordingPlayer` has its own queue for that.
- **Sample rate and memory:** internal audio is 44.1 kHz (`AudioConfig.sampleRate`).
  - Files decode straight into interleaved Int16 (`PCM16Stereo`). Analysis and stem separation stream over that buffer, so never materialise full-length Float copies.
  - Stems are stored at `stemHeadroom` (×0.5).
- **Stems:** `Cheeks/Stems.mlpackage` (100 MB, git-ignored) is HT-Demucs, built by `tools/stems/convert.py`. Without it, the app builds and falls back to a frequency split.
  - **Never run it with `.all` or `.cpuAndNeuralEngine`.** The Neural Engine returns audio 3 to 9 dB worse with no error. Use `.cpuAndGPU`, falling back to `.cpuOnly`.
  - Stems sum back to the mix exactly (melody takes the residual), so swapping them in is inaudible and needs no restart of the stretcher.
- **Swift language mode is 5:** keep it that way unless asked.
- **Vendored code:** `DSP/vendor/` is Signalsmith Stretch and Linear (MIT), unmodified. `Bridging.h` is the Swift bridging header, and it includes `UI/Live/ShaderTypes.h`, which Metal also includes.

## UI rules

The look is **black display screens set into a club controller's matte control surface**. The owner rejected flat grey versions as "unpolished" and cheap skeuomorphism as "really bad". What works is density, thin lines, small precise type, and real materials on the hero parts.

- **Anything that moves is drawn in Metal** (`UI/Live/`), by a shared display link that skips any view whose uniforms didn't change. An idle screen costs nothing. Don't put per-frame work in SwiftUI: no `TimelineView(.animation)`, no observed playhead.
- **No `TimelineView` shorter than about 0.25 s, even when it's only updating a label.** It keeps SwiftUI's display link running, which re-renders the whole view graph every frame: this was most of the app's idle CPU. Use `DeckClock`, or an observed value set from `DJEngine.tick` that only changes when the number on screen would.
- **Hardware parts are pre-rendered once** (`Baked` in `UI/Design/Theme.swift`) and composited as bitmaps. Shadows, blurs and gradients are fine inside a bake, and should be avoided outside one, because they cost GPU time on every frame.
- **A bake draws into real pixels straight away, through `ImageRenderer.render`. Never use `.uiImage` or `.cgImage` for this.** Those hand back an image still to be drawn on the GPU, and until its shaders are built, each one waits for a time-out ("image provider timed out" in the log). That cost about 20 s the first time the app opened on a real phone. Going this way, a `Canvas`'s conic gradient comes out mirrored top to bottom, so `KnobArt.cap` flips it back.
- **Performance controls take touches from UIKit** through `TouchSurface`, not SwiftUI gestures: true multitouch, and they act on first contact. Browser and settings screens are ordinary SwiftUI, and should look and feel native.
- **Anything along the screen's top edge is a `TouchSurface` key,** not a SwiftUI `Button`. A button there failed every tap in the hands-on test.
- **Don't fade between pages of pads:** they change instantly. While they faded, a tap within about 0.15 s of changing tab fired the old page's pad in the hands-on test.
- **Don't set a state and animate it back in one step:** SwiftUI only sees the end, so nothing's drawn. Use a keyframe track with a trigger. Pad flares were invisible for this reason.
- **A control's touch can't be in anything that animates:** a press lands where the view is at that moment. The Undo key's touch is in a still copy of the capsule's layout, under which the drawn capsule arrives.
- **Say things through `dj.say(message, kind)`:** `.refused` shows a hand and buzzes, `.done` a green tick. Held upright, the capsule hangs below the top bar, as there's no room for a message in it. It lets touches through, apart from its keys.
- **Everything you touch has a feel:** add a `Haptics.shared` call when you add a control. Use the existing vocabulary instead of raw generators.
- **One blue (`Theme.accent`) for every "on" state.** Hot cues, stems and FX families have their own colours, and they match across pads, waveforms and flags.
- **Knob arcs:** white on level knobs (`TRIM`, `MASTER`, `CUE/MST`, `LEVEL`), blue on tone knobs (EQ, filter).
- **A deck's BPM is always the tempo it's playing at,** in the header and on the jog. The track's own speed is in the BPM menu and the browser.
- **Stem colours show on the `STEMS` tab, and anywhere while `Deck.stemsAltered`,** because the 3-band waveform can't show that part of the track is missing.
- **The `FX` tab shows a blue dot while effects are on,** because they stay on when you leave the page.
- **`AUTO` is lit from pressing it until the move is over.** While it waits for its bar it counts down in bars, and pressing it again calls it off or hands the decks back.
- **Respect the system:** `UIAccessibility.isReduceMotionEnabled` for decorative motion, accessibility labels and adjustable actions on controls, continuous corners everywhere.
- **Deck 2 is mirrored** so each deck's tempo fader and CUE/PLAY sit at the screen edge.
- **The screen has three layouts** (`ScreenLayout`): full at 900×600 or more, and compact on its side or upright below that. Compact keeps both decks' pads and the mixer on screen, and a deck's `JOG` key swaps its pads for the jog. Anything that changes a control's size has to fit the smallest, 667×375. Decks have fixed widths there, so a page that's too wide gets clipped and can't push the screen sideways. Check with the `small`, `small-up`, `iphone` and `iphone-up` snapshots, and `PhoneLayoutTests` on an iPhone simulator.
- **Don't name other DJ brands in the app.** The library import says "DJ library", and the code does too.
- **The Duo has a centre crease when unfolded**, so the mixer sits across it and the waveform playhead sits off-centre.
- **Check visual changes with the snapshot test at the Duo size** before calling them done, using real music (below). Synthetic fixtures make waveforms look much worse than they are.
- **Run one `xcodebuild test` per simulator at a time.** A second run on the same simulator installs over the first and kills it with `signal kill`, which looks like a crash.

A blank snapshot fails its test: on a busy Mac the image provider can time out and write an all-white picture. Snapshot options, on top of `TEST_RUNNER_CHEEKS_SNAPSHOT_DIR`:

```sh
tools/test-music/fetch.sh /tmp/cheeks-music   # two CC tracks, not kept in the repo
TEST_RUNNER_CHEEKS_FIXTURE_A="/tmp/cheeks-music/Exhilarate.mp3"          # real music on deck 1
TEST_RUNNER_CHEEKS_FIXTURE_B="/tmp/cheeks-music/Severe Tire Damage.mp3"  # and deck 2
TEST_RUNNER_CHEEKS_SNAPSHOT_SCREEN=duo                                   # one screen size only
TEST_RUNNER_CHEEKS_SNAPSHOT_ONLY=decks-cue,browser                       # only these views
TEST_RUNNER_CHEEKS_REAL_STEMS=1                                          # decks-stems uses the real model
TEST_RUNNER_CHEEKS_WRITE_ICON=1                                          # also writes AppIcon.png
```

## Testing on the device

Hands-on testing with computer use is scripted in `docs/COMPUTER_USE_TASK.md`, and its next results come back in `docs/COMPUTER_USE_RESULTS_8.md`. Read those if they exist. Earlier runs are in `docs/COMPUTER_USE_RESULTS.md`, `_2`, `_3`, `_4`, `_5`, `_6` and `_7`, each ending with what was done about them. Things only the owner can judge (a real finger, haptics, sound, heat) are in `docs/TEST_PLAN.md` §2.
