# Roadmap

The goal is to match top-end DJ software for **phone-only** use. Hardware controllers, club-gear linking and streaming services are out of scope by choice.

**Effort:** S = one sitting, M = a few sessions, L = multi-session project.

## Done
Real AI stems with cache, per-stem levels, stem-targeted FX, 12 Beat FX, key sync and effective key display, slicer, sampler, beat jump, loudness matching, a better time-stretcher (Signalsmith), a master limiter, latency-compensated display, thermal-aware frame rate, browser preview, sort by column, drag to load, Lock Screen integration, settings, VoiceOver labels and haptics.

---

## Phase 1: Close the remaining pro gaps

### 1. Saved loops and memory cues (M)
- **`Track` additions:**
  - `memoryCues: [Cue]` (time, name, colour)
  - `savedLoops: [Loop]` (start, length in beats, name, active-on-load flag)
- **UI:** a cue/loop list per deck, reachable from the deck header, and "save current loop".
- **rekordbox XML:** import `POSITION_MARK Type="4"` (loops) and every memory cue, not only the first.
- Hot cues gain names and custom colours (also in the XML).

### 2. FX expansion (M)
- **Color FX (per channel, on the filter knob):** dub echo, space, noise, crush, pitch.
- **FX chain:** more than one effect at a time per deck.
- **Pad FX:** release FX with quantized tails.

### 3. Sampler (S)
- Import your own samples from Files, record the master or a deck into a pad, quantize triggers to the master beat, and loop or gate modes.

### 4. Four decks (L)
- **Engine:** the core already takes up to 4 decks. Each channel needs a crossfader assign of A, B or THRU.
- **UI on the unfolded screen:** decks 1/2 left and 3/4 right with a layer toggle per side, as on 4-channel controllers.
- **Memory:** budget for 4 loaded tracks plus stems.

### 5. Smaller performance features (S each)
- Loop roll with a triplet option, and loop move.
- Censor (momentary reverse with slip) and spin-back on release.
- Vinyl / CDJ jog mode setting, and vinyl-style start and stop times.
- Instant doubles (load the same track onto the other deck at the same position).
- Auto-cue to the first sound instead of the first beat.

---

## Phase 2: Analysis quality
- **Downbeat detection (M):** find the bar phase, not just beats. Use low-band energy and chord-change likelihood at bar boundaries, so grids start on "1".
- **Variable tempo grids (L):** piecewise beat grids for live and older recordings. Analysis needs local tempo tracking, and sync/quantize must use the local BPM.
- **Phrase analysis (L):** label intro, up, chorus, down and outro with a self-similarity matrix over chroma/MFCC. Show colour bands on the overview, like rekordbox phrase analysis.
- **Key detection (M):**
  - EDM-tuned profiles
  - tuning offset estimation
  - a confidence score
- **Re-analysis UI (S):** a progress list, cancel, and "analyse all".

## Phase 3: Library
- **Smart playlists (M):** rules on BPM range, key, rating, tags, date added and play count.
- **Track metadata (S):**
  - tags ("My Tag" style) and colour labels
  - comments and a ratings UI
- **History and suggestions (S):**
  - play history per session, exportable as a setlist
  - "related tracks": compatible key, ±6% BPM, same tags
- **Browser (S):** multi-select, and drag to playlists.
- **Housekeeping (S):**
  - missing-file detection
  - library backup/export (JSON plus cues) through Files

## Phase 4: Sound quality and performance
- **Stretcher tuning (S):** block size against latency against quality, once it's been heard on real tracks at real tempo changes.
- **Stem latency with key lock (M):** stem mutes and FX go in ahead of the stretcher, so they're heard about 125 ms late when it's in the path. Shortening its block helps, at some cost in bass quality. Worth doing if the owner notices.
- **Thermal and battery (S):** drop to the frequency splitter for new stem jobs when `ProcessInfo.thermalState` is serious.

## Phase 5: UX polish
- **Settings (S):** tempo range and quantize defaults, load lock override.
- **Layouts (M):** mixer-only view, large pads view for finger drumming.
- **Live Activity (M):** a recording timer in the Dynamic Island. Needs a widget extension target in the hand-written project.
- **Recording (S):** embed chapter markers in the m4a itself (CUE sheets already exist), and add a 'publish' preset with normalisation.

---

## Explicitly out of scope
- MIDI or HID controllers
- DVS
- Pro DJ Link
- Multichannel audio interfaces
- Streaming services (Apple Music, Beatport, SoundCloud, TIDAL)
- Lighting and video
