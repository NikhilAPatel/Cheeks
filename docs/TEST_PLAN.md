# Test plan

**Automated (run by Claude):** `CheeksTests` renders the engine offline. See CLAUDE.md for the commands.

**Hands-on in the simulator (run by a Claude with computer use):** `docs/COMPUTER_USE_TASK.md`.

**On the phone (the owner):** below. Picking a signing team in Xcode once is all the setup it needs.

## 2. On-device checklist (owner: ears and fingers)

Tick each item. Anything that fails: note what you did, what you heard or saw, and which track.

### First: things that need your finger
- [ ] **Undo on a deleted hot cue:** set a cue on the `CUE` tab, tap `DEL`, tap the cue, then tap `UNDO` in the top bar. Does it come back every time? It failed every synthetic tap in the first hands-on test, couldn't be reproduced another way, and has been rebuilt, so your finger is the real test.
- [ ] **The top edge:** do `BROWSE`, `REC`, the gear and `UNDO` all respond first time, or does a swipe from the top ever pull something down instead?
- [ ] **The bottom edge:** the app now uses the space by the home indicator. Do `PLAY`, `CUE`, the bottom pads and the crossfader all respond first time? Does sliding the crossfader ever switch apps or bring up the home indicator? If it's a problem, tell me and I'll give that space back.

- [ ] **A tab, then a pad, quickly:** on any tab, tap another tab and hit a pad straight after. The pad must belong to the new page. A synthetic touch fired the old page's pad until this was fixed.

### Feel: the things only you can judge
Say which of these feel wrong, and how (too strong, too weak, too buzzy, late).
- [ ] Keys click on the first touch and there's no perceptible delay before anything happens.
- [ ] Pads feel firmer and duller than keys.
- [ ] The platter has fine ridges as it turns, and you can **feel each beat go past, with a stronger tap on each bar**.
- [ ] Knobs and the tempo fader have a centre click you can find without looking. Fader ends have a soft stop.
- [ ] Loading a track, locking sync and a refused load each feel distinct.
- [ ] Touching and letting go of the jog feels immediate. If it feels laggy, say so: that's the number one thing to tune.
- [ ] Holding CUE while moving a fader and a pad all work at once.
- [ ] Nothing's too small to hit on the unfolded screen, and nothing important sits badly on the crease.

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
- [ ] Tempo fader: at ±8% with KEY on, the pitch stays the same and artifacts are acceptable (this is a new stretcher, so compare it with what you're used to). With KEY off, the pitch follows the tempo.
- [ ] Hot cues and jumps are instant with KEY on, even with the deck far from 0%.
- [ ] No clicks when pressing play, pause, a hot cue, or at a loop point.
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
- [ ] ACAPELLA gives you a clean vocal and NO VOCAL a clean instrumental, on three different tracks you know well. Note the worst artifacts.
- [ ] How long does a 6-minute track take to separate on the phone, and does it get hot? Does anything stutter meanwhile?
- [ ] SOLO works, and soloing again restores what was on.
- [ ] Separating while the deck plays doesn't interrupt playback, and the second load of a track is instant.
- [ ] Echo on vocals only, then mute the vocal stem: the echo tail carries on.

### Mixer and FX
- [ ] EQ: each band kills fully at the far left, and boosts are modest. This is a new isolator; compare it with your hardware.
- [ ] EQ off centre: turn a knob slowly away from the centre, on a loud track. With all knobs centred the sound now skips the EQ entirely, so listen for any swish, pop or change in tone as the first knob leaves centre.
- [ ] Loud tracks: do they sound any different from before, punchier or cleaner? The EQ was raising their peaks by up to 5 dB and sending them into the limiter, even with every knob centred.
- [ ] `DUB`: turn it well round and back to the centre. The tail now rings on for about 5 seconds. Too long, or about right?
- [ ] The filter sweeps low-pass to the left and high-pass to the right, has no effect at centre, and doesn't click leaving centre.
- [ ] Two tracks at full level don't distort on the master, and the LIM light comes on.
- [ ] Tracks at different loudness come in at about the same level with "Match track loudness" on.
- [ ] Crossfader: SMOOTH has no volume dip at centre; SCRATCH cuts in sharply at the edges.
- [ ] Each of the 12 Beat FX sounds right: ECHO and PING PONG in time at 1/2 and 1 beat, tails ring out on release, ROLL and BRAKE and BACKSPIN behave.
- [ ] REC for 10+ minutes across 3+ tracks, then stop. "Saving mix…" appears, then the mix, `.txt` and `.cue` show up in Recordings (and in Files → Cheeks → Recordings).
- [ ] The tracklist times match when each track came in (±10 s). A track only previewed in the headphones (fader down) is *not* listed.
- [ ] The recording plays back in the Recordings screen with no gaps or clicks. Share sends the audio and the tracklists.
- [ ] Switch the format to WAV and record again; the file is lossless WAV.
- [ ] Tapping REC while recording asks before stopping.
- [ ] Crash test: start recording, play 2 minutes, force-quit the app, relaunch. The recording is recovered with its tracklist.
- [ ] "History <today>" lists the tracks that were played out.

### New: cues, sampler, FX and structure
- [ ] **Section names:** on tracks you know, do the names and starts match the song? Some sections still run about 2 minutes. Only someone listening can say if this is any use.
- [ ] **rekordbox import:** export your collection and import it. Are every memory cue, saved loop, hot loop, name and colour there? Does a track you know has a tempo drift follow it?
- [ ] **Phrases:** load five tracks you know well. Are the intro, chorus, breakdown and outro roughly where they should be? Tell me which ones are wrong and how, that's what's needed to tune it.
- [ ] **False tempo maps:** on anything played to a click, does the BPM stay still as it plays? If the number moves on a steady track, say which one.
- [ ] **FX chain:** echo into flanger into reverb. Does it sound like what you'd expect, or a mess? Do quantized releases feel tight or late?
- [ ] **Echo out:** end a track with OUT. Does the cut land right, and is the tail long enough?
- [ ] **Color FX:** DUB, SPACE, NOISE, CRUSH, PITCH, each way round. Which ones would you actually use? PITCH is the one most likely to sound rough.
- [ ] **Sampler:** grab a loop with the vocal muted, record the master onto a pad, and import a file. Does Q make pads feel locked in, or laggy?
- [ ] **Backup:** save one to iCloud Drive, delete the app, reinstall, import a few tracks, and restore.

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
