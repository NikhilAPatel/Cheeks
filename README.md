# Cheeks

A standalone DJ app for iPhone, designed for a large landscape screen (an unfolded foldable, or an iPad). You perform entirely on the phone, with no controller needed. The layout follows rekordbox / CDJ conventions: two decks, a two-channel mixer, waveforms on top and a browser.

> Built without a Mac, so it has **never been compiled**. Expect to fix a handful of compile errors on the first Xcode build.

## Features

**Decks (×2)**
- Touch jog wheel. Touch the platter to scratch (vinyl feel); use the outer ring to bend pitch. When paused, any touch scrubs.
- CDJ-style CUE button: pressing while playing returns to the cue; pressing while paused sets the cue, and holding previews from it. PLAY/PAUSE.
- Tempo fader with ±6 / ±10 / ±16 / WIDE ranges, key lock (master tempo), and key shift of ±12 semitones.
- SYNC matches BPM (including half or double time) and snaps beat phase, then keeps following the master and corrects drift.
- Quantize (Q) and slip mode (SLIP).
- 8 performance pads with five modes:
  - **HOT CUE** A–H, saved with each track. Turn on SHIFT and tap a pad to delete its cue.
  - **BEAT LOOP**: 1/4 to 32 beats.
  - **ROLL**: momentary loop rolls from 1/16 to 8 beats. Playback resumes in time when you release.
  - **BEAT JUMP**: ±1 / 4 / 16 / 32 beats. An active loop moves with the jump.
  - **STEMS**: mute or solo VOCAL / INST / BASS / DRUMS.
- Loop controls: IN / OUT / RELOOP-EXIT / ½ / ×2. Loops are sample-accurate.

**Mixer**
- Trim, 3-band EQ (turning a band fully left kills it), and a one-knob LPF/HPF filter per channel.
- Channel faders, level meters, master volume, and a crossfader with smooth or scratch curves.
- Beat FX: ECHO and REVERB (beat-synced), ROLL and BRAKE, applied to channel 1, 2 or both.
- Headphone cue with SPLIT mode: master in the left ear, cued channels in the right, for use with a cheap headphone splitter cable. Each channel has a pre-fader 🎧 cue button. There are also CUE·MST blend and PHONES level knobs.
- **Session recording.** REC records the master mix.
  - **Crash-safe:** it captures to a 24-bit file that can be recovered if the app is killed mid-set, then converts to AAC or WAV (your choice, in settings) when you stop. Interrupted recordings are recovered on the next launch.
  - **Tracklist:** every track audible for 10+ seconds is logged with its timestamp and BPM/key. It's saved next to the mix as a `.txt` and a `.cue` sheet (chapter markers).
  - **Recordings screen:** play, view the tracklist, share, rename and delete.
  - **Safety:** stopping asks for confirmation, recording warns when storage is low and stops cleanly if storage fills.
- **History:** a "History <date>" playlist logs what you played each day, recording or not.

**Waveforms and library**
- rekordbox-style 3-band colour waveform (low blue, mid amber, high white) with beat grid, bar markers, cues and loop region. Drag it to scratch; pinch to zoom.
- Overview waveform per deck. Tap or drag it to needle-search.
- Automatic analysis of BPM, beat grid, key (Camelot) and waveform on import.
- Tap a deck's BPM to fix the grid: ×2 / ÷2, ±0.1 BPM, shift the grid by 10 ms, or set the downbeat at the playhead. You can also save the cue point as the track's memory cue.
- Library with playlists, search, and sorting by date / title / artist / BPM / key.
- Keys that mix harmonically with the playing track are shown in green.
- Load buttons are disabled for a deck that is playing, so you can't replace a track mid-set by mistake.
- Import from the Files app, or drop files into the app's folder through Files / Finder (Documents is shared).
- rekordbox library import, in two steps:
  1. Import your audio files first.
  2. In rekordbox, choose File → Export Collection in xml format, then pick that file under Import → rekordbox library.

  Tracks are matched by file name. For each match, Cheeks brings over:
  - beat grid and BPM
  - key
  - hot cues A–H
  - memory cue
  - playlists

## Getting it onto your phone

1. On a Mac with **Xcode 16+**, open `Cheeks.xcodeproj`.
2. Select the **Cheeks** target. Under **Signing & Capabilities**, pick your team (your Apple Developer account). Change the bundle ID if Xcode asks.
3. Plug in the phone (or pair it over Wi‑Fi). On the phone, turn on **Developer Mode** under Settings → Privacy & Security.
4. Press Run. With a paid developer account, the install lasts about a year.

## Stems: how they work

Real stem separation needs a machine-learning model. Apple doesn't provide one.

- **Without a model** (the default), Cheeks uses a frequency-based split:
  - bass = the lows
  - drums = cymbals and hats
  - vocals = the centre of the vocal band
  - inst = everything else

  With all four stems on, the track sounds exactly like the original. Muting a stem is a rough approximation, good for "drop the bass" or "thin out the vocals", but not a clean acapella. The pads show **≈EQ** in this mode.
- **With a model**, you get real separation. Convert a source-separation model such as [HT-Demucs](https://github.com/facebookresearch/demucs) (MIT licence) to Core ML with `coremltools`, name it `Stems.mlpackage`, and drop it into the `Cheeks/` folder. The app detects it automatically and the pads show **AI**. Expected interface:
  - input `audio`: Float32 `[1, 2, N]` (stereo, 44.1 kHz)
  - output `stems`: Float32 `[1, 4, 2, N]` in Demucs order: drums, bass, other, vocals

Separation runs in the background when you first touch a stem pad, then swaps in without interrupting playback.

## Tests

`CheeksTests/` checks the engine offline using synthetic tracks:
- BPM, beat-grid and key detection
- loop wrap, slip return and scratch tracking in the realtime renderer
- stem muting
- sync (including half time)
- quantized loops and hot cues, beat jump and grid editing
- stems summing back to the original

Run them with ⌘U in Xcode, or:

```sh
xcodebuild test -project Cheeks.xcodeproj -scheme Cheeks -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'
```

## Code map

| Folder | What's there |
| --- | --- |
| `Audio/DeckRenderer.swift` | Realtime render callback: playhead, scratch, loops, slip, brake, stem mixing |
| `Audio/Deck*.swift` | Deck control: load, cue, hot cues, loops, rolls, sync, stems, EQ/filter |
| `Audio/DJEngine.swift` | AVAudioEngine graph, crossfader, Beat FX, sync follower, recorder |
| `Analysis/` | Decoding, BPM/beat grid, key detection, 3-band waveform |
| `Stems/` | Stem separators (frequency split + Core ML) |
| `Model/` | Tracks, playlists, library storage |
| `UI/` | SwiftUI views |

Signal chain per deck: `source → varispeed → time-pitch → EQ/filter → echo → reverb → channel fader → master`. Internal audio runs at 44.1 kHz.

## What's next

See [docs/ROADMAP.md](docs/ROADMAP.md) for the plan:
- real AI stems
- more FX, saved loops, a sampler and 4 decks
- better analysis

[docs/TEST_PLAN.md](docs/TEST_PLAN.md) covers first build and on-device testing. Hardware controllers and streaming are out of scope.
