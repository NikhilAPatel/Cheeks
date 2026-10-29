# Test plan

The app was written without a compiler. This is the order for bringing it up on a Mac and then proving it on the phone.

## 1. Mac bring-up (Claude can do all of this)

1. **Prerequisites:** Xcode 16+ with an iOS 17+ simulator runtime, with the repo cloned on `master`.
2. **Compile:** `xcodebuild -project Cheeks.xcodeproj -scheme Cheeks -destination 'generic/platform=iOS Simulator' build`. Fix errors minimally; expect a handful.
3. **Unit tests:** `xcodebuild test … -destination 'platform=iOS Simulator,name=<iPad>'`. All of `CheeksTests` should pass. Their expected values were cross-checked against a numpy port of the analysis code.
4. **Simulator UI pass:** launch on a large iPad in landscape, the closest stand-in for an unfolded foldable. Take screenshots of:
   - the decks screen, empty and with two tracks loaded
   - the browser and an empty library
   - each pad mode
   - the stems "separating" state
   - the beat-grid menu

   Check nothing is clipped or overlapping, and that controls are at least ~30 pt.
5. **Smaller widths:** repeat on a smaller iPad and on the largest iPhone in landscape. Note any layout that breaks.
6. **Profile in the simulator** (Instruments → Allocations). Load a 6-minute track on both decks, then separate stems:
   - each loaded deck should add about 65 MB
   - stems should add about 250 MB per 6-minute track
7. **On the phone:** pick a signing team in Xcode once (the owner does this), plug in the phone, and run.

## 2. On-device checklist (owner: ears and fingers)

Tick each item. Anything that fails: note what you did, what you heard or saw, and which track.

### Sound and stability
- [ ] Two tracks play for 30+ minutes with no clicks, dropouts or stutter, with the screen on.
- [ ] The phone stays reasonably cool. Xcode's CPU gauge stays under ~40% with both decks playing.
- [ ] Locking the screen or switching apps: audio keeps playing. Coming back: the UI shows the right state.
- [ ] A phone call or Siri interruption: audio stops, then resumes cleanly afterwards (press play if needed).
- [ ] Unplugging headphones mid-track doesn't crash the app.
- [ ] Load a 60-minute mix, play it and seek around. No crash.

### Decks
- [ ] CUE while playing jumps back to the cue and stops. CUE while paused sets the cue; holding it previews; releasing returns.
- [ ] Holding CUE and then pressing PLAY keeps playing after you release CUE.
- [ ] Tempo fader: at ±8% with KEY on, the pitch stays the same and artifacts are acceptable. With KEY off, the pitch follows the tempo.
- [ ] Key shift ± changes pitch by a semitone per step, and double-tapping resets it.
- [ ] SYNC on two tracks with different BPMs: the beats line up immediately and **stay locked for 5 minutes**, with no flamming kicks.
- [ ] SYNC on a half/double-time pair (e.g. 70 vs 140): it locks at half time rather than jumping ±50%.
- [ ] Platter scratching feels like vinyl: it stops under your finger and follows your hand. The ring nudges a playing track ahead or behind.
- [ ] Dragging the waveform scratches; pinching zooms; tapping the overview jumps.

### Loops, cues, pads
- [ ] Beat loops are seamless with no click at the loop point, and halving/doubling keeps the loop in time.
- [ ] Rolls with SLIP: release a roll and the track is back where it would have been.
- [ ] Hot cues: set A–H, relaunch the app, and they're still there. SHIFT plus a pad deletes a cue.
- [ ] Hot cue jumps with Q on stay on the beat.
- [ ] Beat jump ±1/4/16/32 stays on the grid.

### Stems
- [ ] With all four stems on, the track sounds identical to the original (A/B against another deck).
- [ ] Muting each stem does roughly what its label says. The default mode is approximate.
- [ ] SOLO works, and soloing again restores all stems.
- [ ] Separating while the deck plays doesn't interrupt playback.

### Mixer and FX
- [ ] EQ: each band kills fully at the far left, and boosts are modest.
- [ ] The filter sweeps low-pass to the left and high-pass to the right, silent at centre.
- [ ] Crossfader: SMOOTH has no volume dip at centre; SCRATCH cuts in sharply at the edges.
- [ ] ECHO is in time at 1/2 and 1 beat. REVERB tails. ROLL and BRAKE work on the selected channel.
- [ ] REC for 10+ minutes across 3+ tracks, then stop. "Saving mix…" appears, then the mix, `.txt` and `.cue` show up in Recordings (and in Files → Cheeks → Recordings).
- [ ] The tracklist times match when each track came in (±10 s). A track only previewed in the headphones (fader down) is *not* listed.
- [ ] The recording plays back in the Recordings screen with no gaps or clicks. Share sends the audio and the tracklists.
- [ ] Switch the format to WAV and record again; the file is lossless WAV.
- [ ] Tapping REC while recording asks before stopping.
- [ ] Crash test: start recording, play 2 minutes, force-quit the app, relaunch. The recording is recovered with its tracklist.
- [ ] "History <today>" lists the tracks that were played out.

### Headphones (split cable)
- [ ] With SPLIT on, the left ear has the master in mono and the right ear has the cued channels.
- [ ] CUE·MST blends the master into the cue ear; PHONES sets its level.
- [ ] With SPLIT off, normal stereo returns and the cue buttons have no effect on the main output.

### Library
- [ ] Import 20+ files from Files. They all analyse in the background, and the UI stays responsive.
- [ ] Spot-check BPM and key on 10 tracks you know. Note the misses.
- [ ] Beat-grid menu: ×2 / ÷2, shifting the grid, and "set downbeat here" all behave sensibly.
- [ ] Importing the same file twice doesn't create a duplicate.
- [ ] rekordbox XML import matches tracks by file name and brings over grids, keys, cues and playlists. Re-importing doesn't duplicate playlists.
- [ ] Search, sort, playlists, and deleting a track or playlist all work.
- [ ] The load buttons are disabled for a deck that's playing.

## 3. Known risks to check first

- **Time-stretch quality:** Apple's `AUTimePitch` is not as clean as the engines pro apps license. See ROADMAP → Sound quality.
- **Display latency:** the waveform shows the playhead slightly ahead of what you hear, by the output latency plus the time-stretch latency. Hard to notice at small amounts.
- **Layout:** designed for a wide screen and never seen rendered. Expect spacing fixes.
- **Beat grids:** detection assumes constant tempo and calls the first detected beat a downbeat. Live or tempo-drifting tracks will need manual grid fixes.
