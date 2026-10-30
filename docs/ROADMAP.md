# Roadmap

The goal is to match top-end DJ software for **phone-only** use. Hardware controllers, club-gear linking and streaming services are out of scope by choice.

**Effort:** S = one sitting, M = a few sessions, L = multi-session project.

## Done
Real AI stems with cache, per-stem levels, stem-targeted FX, 12 Beat FX in chains of three, quantized FX release, echo out, Color FX, key sync and effective key display, slicer, sampler with its own sounds, loop grabbing, master recording, gate and loop modes and quantized triggers, beat jump, memory cues, saved loops, hot loops, cue names and colours, full rekordbox import, variable-tempo grids, phrase analysis, library backup and restore, missing-file handling, loudness matching, a better time-stretcher (Signalsmith), a master limiter, latency-compensated display, thermal-aware frame rate, browser preview, sort by column, drag to load, Lock Screen integration, settings, VoiceOver labels and haptics.

---

## Phase 1: Close the remaining pro gaps

### 1. Four decks (L), deliberately not done
The owner was advised against it: the screen's already dense and four sets of stems is a lot of memory on a phone. If it's wanted later:
- **Engine:** the core already takes up to 4 decks. Each channel needs a crossfader assign of A, B or THRU.
- **UI on the unfolded screen:** decks 1/2 left and 3/4 right with a layer toggle per side, as on 4-channel controllers.
- **Memory:** budget for 4 loaded tracks plus stems.

### 2. Smaller performance features (S each)
- Loop roll with a triplet option, and loop move.
- Censor (momentary reverse with slip) and spin-back on release.
- Vinyl / CDJ jog mode setting, and vinyl-style start and stop times.
- Instant doubles (load the same track onto the other deck at the same position).
- Auto-cue to the first sound instead of the first beat.
- Jump to the next or previous phrase.

---

## Phase 2: Analysis quality
- **Tune phrases and tempo maps on real music (M):** both have only seen two real tracks, neither club music. See "How far to trust the new features" in the handoff.
- **Downbeat detection (M):** the grid picks its "1" from where the biggest changes land. Chord-change likelihood at bar boundaries would make it surer.
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

## Phase 4: Sound quality and performance
- **Stretcher tuning (S):** block size against latency against quality, once it's been heard on real tracks at real tempo changes.
- **Stem latency with key lock (M):** stem mutes and FX go in ahead of the stretcher, so they're heard about 125 ms late when it's in the path. Shortening its block helps, at some cost in bass quality. Worth doing if the owner notices.
- **Stem speed on the phone (?):** nothing's been measured there. If it's too slow, a smaller model such as `htdemucs` with fewer transformer layers, or streaming only the part around the playhead, are the options to look at.

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
