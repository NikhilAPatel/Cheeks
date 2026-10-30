# Cheeks: hands-on test script, part 2 (new features)

**Who this is for:** a Claude session with computer use. Run this after part 1 (`docs/COMPUTER_USE_TEST.md`), on the code that includes these features.

**Your job:** run every test in order and write down exactly what happens. **Don't change any code.** Setup, how to take screenshots, and what can't be tested in a simulator are all in part 1; follow them. Then load a track on each deck and press PLAY on deck 1.

**What to hand back:** `docs/COMPUTER_USE_RESULTS_2.md`, in part 1's format, with screenshots in `docs/test-results-2/`. Commit only those to `master` with the message `Add hands-on test results, part 2`, and push with `git push git@github.com:NikhilAPatel/Cheeks.git master:master`. Never force-push.

## P. Memory cues and saved loops
1. Open the `MEM` tab. It should show `SAVE CUE`, `SAVE LOOP`, a page count, `LIST` and eight pads, with `DEL` on the tab row. Screenshot `p1-mem`.
2. Tap `SAVE CUE` twice. One red bookmark pad appears, and the second tap is refused with a capsule. A red triangle should appear on the waveform's top edge and on the overview.
3. Tap `SAVE LOOP` with no loop set: a capsule says to set one. Switch to `LOOP`, set a 4-beat loop, come back and tap it again: an orange pad appears, and an orange bar on the waveform's top edge.
4. Exit the loop and tap needle-search elsewhere. Tap the orange pad: the deck jumps to the loop and stays in it, and the pad lights. Tap it again: the loop ends.
5. Tap `DEL`, then a pad: it goes, and the capsule offers **Undo**. Tap Undo.
6. Tap `LIST`. A native list shows hot cues, memory cues and loops. Name a hot cue, change its colour and check the CUE pad and waveform flag change. Switch a loop's toggle on, reload the track, and check the loop is shown as active without the deck jumping to it. Screenshot `p6-list`.
7. Terminate and relaunch: is everything still there?

## Q. Sampler
1. Open the `SAMPLE` tab. Check the row: `SET`, `Q`, `VOLUME`, `STOP`. All eight pads should fire.
2. Tap `SET`, then a pad. A sheet opens. Screenshot `q2-sheet`. Are the grab buttons only there for decks with a loop set?
3. Set the mode to Gate and close. Hold the pad: it should stop when released. Set Loop: one tap starts it and the pad stays lit, the next stops it.
4. Set a loop on deck 1. `SET`, a pad, `Grab Deck 1's Loop`. The pad gets the name `LOOP 1` and goes round when tapped.
5. `SET`, a pad, `Record the Master`. A red timer replaces `SET`. Wait 5 seconds and tap it: the pad holds a recording of what was playing. Check the meters move when you play it.
6. `SET`, a pad with its own sound, `Restore the Original Sound`.
7. Drag `VOLUME` to the bottom: pads should go quiet (watch the meters). Put it back. `STOP` stops a looping pad.

## R. FX chain
1. On `FX`, tap `ECHO`, `FLANGER` and `TRANS` quickly: all three stay lit. Tap `CRUSH`: `ECHO` goes out and the other three stay lit. Screenshot `r1-chain`.
2. Slide on a lit pad: the row's `DEPTH` follows that effect, and the others keep theirs.
3. Let everything go. With a deck playing, tap `OUT`: it lights, and within a beat the track's own sound stops and only echoes are left (watch the meters fall away). Tap it again: the track returns at the point it's reached by then.
4. Tap `OUT` with the deck stopped: it should refuse.

## S. Color FX
1. In the mixer's middle column, tap `FILTER` repeatedly. It cycles DUB, SPACE, NOISE, CRUSH, PITCH, FILTER, and the label under both channels' bottom knobs changes to match. Screenshot `s1-color`.
2. For each one, with a deck playing, turn the knob each way. Check the meters respond, and report anything that goes silent, jumps to the top of the meter, or crashes. Double-tap brings it back.
3. With DUB, turn the knob well round and back to centre: the meters should keep moving for a few seconds with the channel fader up after pausing the deck.

## T. Phrases and tempo
1. On each deck, is there a strip of colour along the bottom of the overview and big waveform? Screenshot `t1-phrases`, and note how many sections each track got and their names.
2. Beside the playhead, the counter should read like `CHORUS 12.3` and count up. Does it restart at a section boundary?
3. Do the two test tracks' BPM readouts stay still while playing? If they change, that's a false tempo map: report it.

## U. Backup and restore
1. Open Settings and scroll down to **Library**. Tap **Save a Backup…** and save it to Files on the simulator (if the picker can't be driven, report that and carry on).
2. Delete a hot cue, then **Restore from a Backup…**. The cue should return and a summary should show.
3. Find the music file for one track in `"$(xcrun simctl get_app_container "iPad Pro 13-inch (M5)" com.nikhilpatel.cheeks data)/Documents/Music/"`. Move it out, terminate and relaunch. The track should show a warning triangle in the browser, and loading it should be refused with a message.
4. Copy the file back under the name it had when imported, into `Documents/`, and relaunch. The warning should go, and its cues should still be there. Note: the name matters, it's how the track is recognised.
5. Check `Documents/Backups/` has a dated JSON file in it.

## V. Performance
Measure as in part 1, section N, with both decks on stems, three FX on each, and DUB on both channels. Report the CPU figures next to part 1's.
