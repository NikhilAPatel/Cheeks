# Cheeks

A professional DJ app for iPhone, designed for a large landscape screen: the iPhone Duo unfolded, or an iPad. You perform entirely on the screen, with no controller. It looks and works like rekordbox's screens set into a Pioneer control surface, and it feels like an Apple app.

## Features

**Decks (×2)**
- **Jog wheel:** touch the record to scratch, the metal ring to bend pitch. When paused, any touch scrubs. Touches go straight to the audio core with every sample the screen reports, and scratching bypasses the time-stretcher, so the record follows your hand. You can feel beats and bars go past under your finger.
- **CDJ-style CUE:** pressing while playing returns to the cue. Pressing while paused sets the cue, and holding previews from it.
- **Tempo fader** with ±6 / ±10 / ±16 / WIDE ranges, a centre click, and finer control if you slide sideways off it.
- **Key lock**, key shift of ±12 semitones, and **KEY SYNC**, which moves a deck to the nearest compatible key.
- **BEAT SYNC** matches BPM (including half or double time) and snaps phase. MASTER chooses which deck leads. Both decks render on one sample clock, so a synced pair can't drift.
- **Waveforms are drawn in real time scale**, so beats line up on screen when decks are matched.
- Quantize, slip mode, reverse, beat jump, and manual and automatic loops.

**Performance pads**
- **CUE:** hot cues A–H, saved with each track. DEL then a pad removes one, with Undo.
- **LOOP:** 1/4 to 32 beats.
- **ROLL:** momentary loops from 1/16 to 8 beats. Playback resumes in time on release.
- **SLICER:** play any of eight slices of the current bar, back in time on release.
- **JUMP:** ±1 / 4 / 16 / 32 beats. A loop moves with the jump.
- **STEMS:** see below.
- **FX:** 12 Beat FX: echo, ping pong, spiral, reverb, flanger, phaser, filter, trans, crush, roll, brake, backspin. Hold for as long as you want, or tap to latch. While holding, slide up and down for depth and left and right for beat length. Effects stay on the beat at any tempo.
- **SAMPLER:** eight one-shots, including an air horn.

**Stems**
- Real AI source separation into **vocals, instruments, bass and drums** with HT-Demucs running on the device. See [Stems](#stems).
- Tap a pad to mute a stem, instantly. Slide on it to set its level. SOLO, and one-touch ACAPELLA, NO VOCAL and BEAT.
- The waveform splits into matching colours, and muted stems drop to a ghost, so you can see what you've taken out.
- **Effects can target single stems.** Echo the vocal, then mute it, and the tail rings out over the instrumental.
- Split tracks are cached, so they load instantly next time.

**Mixer**
- Trim, 3-band **isolator EQ** where fully left removes the band, and a one-knob resonant LPF/HPF filter per channel.
- Channel faders, LED meters with peak hold, master volume, and a crossfader with smooth or scratch curves. Knobs and faders have detents you can feel.
- **Look-ahead limiter** on the master, so two hot decks can't clip the output or a recording.
- **Loudness matching:** tracks are measured to BS.1770 and brought to a matched level.
- **Headphone cue with SPLIT mode:** master in the left ear, cued channels in the right, for a cheap splitter cable. Each channel has a pre-fader cue button, plus CUE/MST blend and level.

**Recording**
- REC records the master mix. **Crash-safe:** it captures to a 24-bit file that can be recovered if the app is killed mid-set, then converts to AAC or WAV when you stop.
- **Tracklist:** every track audible for 10+ seconds is logged with its timestamp, BPM and key, and saved next to the mix as a `.txt` and a `.cue` sheet.
- **Recordings screen:** play, view the tracklist, share, rename and delete.
- **History:** a "History <date>" playlist logs what you played each day, recording or not.

**Library**
- Automatic analysis of BPM, beat grid, key (Camelot), loudness and waveform on import.
- Fix the grid from a deck's BPM: ×2 / ÷2, ±0.1 BPM, shift by 10 ms, or set the downbeat at the playhead.
- Browser with playlists, search, tap-to-sort columns, artwork, tiny waveforms, and **IN KEY** and **±6% BPM** filters. Compatible keys are highlighted.
- Load with the deck buttons, by swiping a row, or by dragging it onto a deck. A playing deck refuses a new track.
- Tap a row's waveform to **preview** it: in the cue ear with a split cable, or quietly on the main output without one.
- Import from the Files app, or drop files into the app's folder through Files or Finder.
- **rekordbox library import:** in rekordbox, File → Export Collection in xml format, then Import → rekordbox library. Import your audio first; tracks are matched by file name, and bring over their beat grid, BPM, key, hot cues, memory cue and playlists.

**The small things**
- Haptics designed per control. Keys that move like keys, pads that flare when struck.
- Now Playing on the Lock Screen and in Control Center, with the track's artwork.
- Status messages in a capsule at the top of the screen, with Undo where it matters.
- A refused action shakes its head. Knobs and faders spring home on a double-tap.
- The hardware wakes up: rings sweep on and meters run up and back at launch.
- VoiceOver labels and adjustable actions on every control, and Reduce Motion is respected.

## Getting it onto your phone

1. On a Mac with **Xcode 16+**, open `Cheeks.xcodeproj`. If it asks for the Metal toolchain, let it download (or run `xcodebuild -downloadComponent MetalToolchain`).
2. Select the **Cheeks** target. Under **Signing & Capabilities**, pick your team (your Apple Developer account). Change the bundle ID if Xcode asks.
3. Plug in the phone (or pair it over Wi‑Fi). On the phone, turn on **Developer Mode** under Settings → Privacy & Security.
4. Press Run. With a paid developer account, the install lasts about a year.

## Stems

Separation needs a machine-learning model. Cheeks uses [HT-Demucs](https://github.com/facebookresearch/demucs) converted to Core ML. `tools/stems/` has the conversion script and instructions, and the result goes at `Cheeks/Stems.mlpackage`. It's large, so it isn't kept in git. **Personal use is fine; check the weights' licence before distributing the app**, since they were trained on a research dataset.

Without the model, the app falls back to a frequency-based split, and the status shows **≈EQ**. That's only good for rough "drop the bass" moves.

Separation runs in the background, and swaps in without interrupting playback. With "Prepare stems on load" on (Settings), it starts as soon as a track is loaded.

## Tests

`CheeksTests/` renders the engine offline using synthetic tracks:
- BPM, beat-grid and key detection
- loop wrap, slip return, scratch tracking, stem muting
- no clicks at jumps, loops, play or pause
- key lock and key shift pitch, and instant hot cues under key lock
- isolator flatness and kills, filter sweeps, limiter ceiling
- stem-targeted FX and tails, and every effect staying bounded
- a 3-minute sync lock, and recording end to end
- real-time CPU headroom

Run them with ⌘U in Xcode, or:

```sh
xcodebuild test -project Cheeks.xcodeproj -scheme Cheeks -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'
```

Hands-on testing is scripted in [docs/COMPUTER_USE_TEST.md](docs/COMPUTER_USE_TEST.md), and on-device checks in [docs/TEST_PLAN.md](docs/TEST_PLAN.md).

## Code map

| Folder | What's there |
| --- | --- |
| `DSP/` | The realtime engine in C++: decks, time-stretcher, isolator EQ, filter, FX, mixer, limiter |
| `Audio/` | Deck control, the mixer, recording, decoding, the sampler |
| `Analysis/` | BPM and beat grid, key, loudness, 3-band waveform |
| `Stems/` | Stem separators and their cache |
| `Model/` | Tracks, playlists, library storage, artwork |
| `UI/Live/` | Metal renderer and shaders for everything that moves |
| `UI/Design/`, `UI/Controls/` | Theme, pre-rendered parts, touch, haptics, keys, pads, knobs, faders |
| `UI/Deck/`, `UI/Mixer/`, `UI/Browser/`, `UI/Shell/` | The screens |

Credits: time-stretching by [Signalsmith Stretch](https://github.com/Signalsmith-Audio/signalsmith-stretch) (MIT). Stem separation by [Demucs](https://github.com/facebookresearch/demucs) (MIT).

## What's next

See [docs/ROADMAP.md](docs/ROADMAP.md). Hardware controllers and streaming are out of scope.
