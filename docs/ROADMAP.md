# Roadmap

The goal is to match top-end DJ software for **phone-only** use. Hardware controllers, club-gear linking and streaming services are out of scope by choice.

**Effort:** S = one sitting, M = a few sessions, L = multi-session project.

**Order of work:**
- **Phase 0** comes first.
- **Phase 1** follows in the order listed.
- **Phases 2–5** can be interleaved.

---

## Phase 0: Bring-up (blocks everything)
Follow `docs/TEST_PLAN.md`: compile, fix errors, get the unit tests green, run a simulator layout pass, then go through the on-device checklist. Don't add features until the device checklist mostly passes. Each new feature written without a compiler makes debugging harder.

---

## Phase 1: Close the pro gaps

### 1. Real AI stems (L), the biggest gap
**Today:** a frequency split (`FrequencySplitSeparator`). All four stems on sound identical to the track, but isolation is rough.

**Target:** HT-Demucs (Meta, MIT-licensed code; confirm the weight licence). It gives 4 stems (drums, bass, other, vocals) at 44.1 kHz, the same set rekordbox and Serato expose.

**Conversion (on the Mac):**
- Core ML can't convert Demucs's STFT/iSTFT cleanly. So export only the network:
  - wrap a module taking `(mix waveform segment, |STFT| magnitude)` and returning `(spectral branch output, time branch output)`
  - convert it with `coremltools` at fp16
- Do the STFT, masking and iSTFT in Swift with vDSP. Match Demucs exactly: `n_fft 4096`, `hop 1024`, its padding and normalisation.
- Validate against PyTorch on a few clips: SDR within ~0.1 dB of the reference.
- **Fallback if HT-Demucs won't convert:** Open-Unmix (MIT). It uses spectrogram masking only, is easy to convert, and has lower but still usable quality.

**Runtime:**
- Run the segment model (~7.8 s windows, 25% overlap, triangular cross-fade) on the Neural Engine in the background, starting **when a track loads**.
- The deck plays the full mix until the stems are ready, then swaps them in seamlessly. `prepareStems` already does the swap.
- Measure speed on the device; the target is a 6-minute track ready within ~1 minute.

**Caching:** 4 stems ≈ 250 MB per 6-minute track as Int16. Cache recent tracks in Caches with an LRU cap (e.g. 2 GB) so reloading is instant. Optionally re-encode the cache to AAC to cut it ~10×.

**Code:** `CoreMLStemSeparator` already has a slot for this. Change its interface to the network-only model above and add the STFT stage.

**Also add:** stem FX sends (echo on vocals only) and per-stem level knobs instead of only on/off.

### 2. Key sync and smarter key controls (S)
- **KEY SYNC button:** shift this deck by the smallest number of semitones (±6) to the master's key, or to a compatible Camelot key. `keyShift` already exists.
- **Display:** show the current key after shift and tempo, i.e. the effective key when key lock is off.

### 3. Saved loops and memory cues (M)
- **`Track` additions:**
  - `memoryCues: [Cue]` (time, name, colour)
  - `savedLoops: [Loop]` (start, length in beats, name, active-on-load flag)
- **UI:** a cue/loop list per deck, reachable from the deck header, and "save current loop".
- **rekordbox XML:** import `POSITION_MARK Type="4"` (loops) and every memory cue, not only the first.
- Hot cues gain names and colours (also in the XML).

### 4. FX expansion (M–L)
- **Custom DSP plumbing:** register in-process `AUAudioUnit` subclasses (`AUAudioUnit.registerSubclass`) and attach them like the built-in units. The DSP lives in a C/C++ render block, which also covers the flanger, phaser and gate below.
- **Beat FX:**
  - delay types: echo, ping-pong, spiral, slip echo, delay
  - reverb
  - modulation: flanger, phaser, filter LFO
  - trans/gate
  - pitch
  - roll, slip roll, brake, backspin
  - noise, bit crush
- **Settings:** beat-synced timing everywhere, with a quantized on/off.
- **Color FX (per channel, on the filter knob):** filter, dub echo, space, noise, crush, pitch.
- **FX chain:** 3 slots per FX unit; two FX units assignable to channel 1/2/master.
- **Pad FX / Release FX** mode on the performance pads (momentary FX with a release tail).

### 5. Sampler (M)
- **Pads:** 8–16 sample pads in a pad mode or a sampler panel.
- **Modes:** one-shot, loop, or gate; the volume knob routes to the program bus.
- **Timing:** trigger quantized to the master beat; loops tempo-synced to master BPM.
- **Sources:**
  - a few bundled royalty-free samples
  - record the master or a deck into a pad
  - import from Files
- **Engine:** a third `AVAudioSourceNode` like `DeckRenderer` (simpler: no scratch), mixed into `program`.

### 6. Four decks (L)
- **Engine:** generalise `decks` to 4 and the mixer to 4 channels. Each channel gets a crossfader assign of A, B or THRU.
- **UI on the unfolded screen:** decks 1/2 left and 3/4 right with a layer toggle per side, as on 4-channel controllers. Or a compact 4-deck view with mini waveforms and pads.
- **Memory:** budget for 4 loaded tracks plus stems; the stem LRU cache helps.

### 7. Smaller performance features (S each)
- **Pads and loops:**
  - a slicer pad mode (8 slices of a bar, quantized)
  - beat-jump size selector and loop move
  - loop roll with a triplet option
- **Transport and jog:**
  - censor (momentary reverse with slip)
  - spin-back on release
  - vinyl / CDJ jog mode setting
- **Load behaviour:**
  - instant doubles (load the same track onto the other deck at the same position)
  - auto-cue to the first sound instead of the first beat

---

## Phase 2: Analysis quality
- **Downbeat detection (M):** find the bar phase, not just beats. Use low-band energy and chord-change likelihood at bar boundaries, so grids start on "1".
- **Variable tempo grids (L):** piecewise beat grids for live and older recordings. Analysis needs local tempo tracking, and sync/quantize must use the local BPM.
- **Phrase analysis (L):** label intro, up, chorus, down and outro with a self-similarity matrix over chroma/MFCC. Show colour bands on the overview, like rekordbox phrase analysis.
- **Key detection (M):**
  - EDM-tuned profiles
  - tuning offset estimation
  - a confidence score
- **Loudness (S):** measure integrated LUFS per track and auto-set TRIM so tracks play at matched loudness. This is a real pro feature.
- **Re-analysis UI (S):** a progress list, cancel, and "analyse all".

## Phase 3: Library
- **Smart playlists (M):** rules on BPM range, key, rating, tags, date added and play count.
- **Track metadata (S):**
  - tags ("My Tag" style) and colour labels
  - comments and a ratings UI
- **History and suggestions (S):**
  - play history per session, exportable as a setlist
  - "related tracks": compatible key, ±6% BPM, same tags
- **Browser (S):**
  - track preview in the browser (a third mini player into the cue bus)
  - multi-select, drag to playlists, sort by any column
- **Housekeeping (S):**
  - missing-file detection
  - library backup/export (JSON plus cues) through Files

## Phase 4: Sound quality and performance
- **Better time-stretch (M):** replace `AUTimePitch` with **Signalsmith Stretch** (MIT, header-only C++). Run it inside the renderer via Swift–C++ interop or a small ObjC++ wrapper. This gives cleaner key lock at large tempo changes and lets the latency be compensated in-house. *Avoid Rubber Band unless a commercial licence is bought (it's GPL).*
- **Latency compensation (S):** show the waveform/jog at the *heard* position (playhead minus output latency). Use the measured latency of each deck's chain in sync phase alignment.
- **Master limiter (S):** Apple's `AUPeakLimiter` on the program bus, so the master can't clip.
- **Thermal and battery (S):**
  - lower the UI frame rate when idle or in Low Power Mode
  - watch `ProcessInfo.thermalState` and drop to the frequency splitter for new stem jobs when hot

## Phase 5: UX polish
- **Settings screen (S):**
  - tempo range default and quantize default
  - jog mode and cue behaviour
  - crossfader curve
  - load lock on a playing deck
  - waveform colour style (3-band / RGB / blue)
- **Layouts (M):**
  - folded or compact single-deck view
  - mixer-only view
  - large pads view for finger drumming
- **Onboarding (S):** a first-run import walkthrough and splitter-cable guidance.
- **Accessibility (S):** VoiceOver labels on all controls, Dynamic Type in the browser, and haptics on beat-jump and loop set.
- **Recording (S):** embed chapter markers in the m4a itself (CUE sheets already exist), and add a 'publish' preset with normalisation.

---

## Explicitly out of scope
- MIDI or HID controllers
- DVS
- Pro DJ Link
- Multichannel audio interfaces
- Streaming services (Apple Music, Beatport, SoundCloud, TIDAL)
- Lighting and video
