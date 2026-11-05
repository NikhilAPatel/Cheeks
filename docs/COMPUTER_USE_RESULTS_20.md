# Hands-on results, part 20, 2026-11-05

Commit tested: c577553

Device:
- **iPhone SE Cheeks:** 667×375 on its side, for the retest, what hadn't been run for a while, the long run and CPU. Upright (375×667) for `GB1`, `GC1`, `GC2`, `GC3`, `GC4`, `GC7`, `GC8` and `GC10`.
- **Folded iPhone Duo:** 466×678 pt, upright phone layout, for `GB1` and `GC4`, including a 400-row playlist.
- **iPhone 17:** 402×874 upright, for the first-time user, and on its side for `GC3` and the `RELOOP` video.

Tooling limits:
- **The full layout can't be pressed.** The Duo's still folded: the last `hingeState:` in SpringBoard's log says `Closed`, at 13:01 on 11-04. I didn't reboot it. The iPad's touch access request wasn't answered. So `GA` is blocked again.
- **Can't be checked here:** how anything sounds, haptics, the headphone output and a real finger. Levels are read from recordings and meter pixels. So "a buzz, nothing else" in `GB5` means I saw nothing else.
- **Double-tap on a knob:** two tool taps are too slow to count. In `GC3`, my two taps on `TRIM 1` about 1 s apart did nothing, as you'd expect.
- **Screen reading:** a logger read the top of the screen by OCR about twice a second. It was off for the CPU table, and I restarted it each time I turned the phone.
- **Presses in a slide:** for the long run, I froze the app with SIGSTOP so `BROWSE` and the press arrived together, twice. That's two presses, not a study.
- **Busy Mac:** the first-time user ran beside my tests from 09:34 to 10:20. `cheeks-6d` was also running UI tests on a new simulator, `iPhone SE Cheeks B`, at 09:19, when load average read 750 and the Mac was at 0% idle. Other projects' jobs were running as well.
- **Crash reports:** none from anything I ran. Four came in today from the iPad at 09:08 and 09:10, none from these simulators (`Cheeks-2026-11-05-090814.ips`, `090828`, `091005`, `091017`). The two I opened are the same one: an exclusivity conflict, `AutoDJ.mixSet.getter` called from `foundAQuickerWay` in `lookForAQuickerWay`. Neither function is in c577553, so it's from work that isn't in this round. `cheeks-6d`: worth a look if that's yours.
- **Logged faults:** the small iPhone's log has about 114 each of UIKit's "Decomposition of 'position'/'bounds' was requested" assertions, in ones to threes, mostly while I was in the browser and sheets. Nothing I could see came of them.
- **The rows' menu holding the app busy:** my tool didn't wait at that step. A 1 s hold returned on time, and a screenshot straight after took the usual 1 to 2 s.

## Summary

55 scripted tests including the long run: **50 PASS, 1 FAIL, 4 BLOCKED.** No crash reports from this commit. The failure is the drop message in `GC4`. The blocked ones are `GA1` to `GA4`.

**Everything that failed or was new last round is fixed.**
- **`N32`, the capsule:** it grows with its words, on one, two and three lines, on every phone. Nothing comes out of it, including `AUTO`'s longest message at 375 pt wide.
- **`N33`, the tempo fader:** "Deck 2's off SYNC: you moved its tempo fader." with `UNDO`. `UNDO` puts back the speed and `SYNC`, in step.
- **`N34`, what `AUTO` takes over:** the sentence is there, it lists the right things, and it's gone when everything's neutral.
- **`N35`:** `Back to Its Own Speed` is first in the menu and on screen.
- **`N36`:** every line of it, including stopping a move and pressing straight away.

**The two you wanted a hard look at:**
- **`GC4`'s message on dropping a lifted row: it never appears.** See the failure below. That's 5 drops I can vouch for, on two phones.
- **`GC7`'s dim load key on a phone: it works.** "Deck 2 is playing. Stop it first." with the hand, and the key shakes on video (`gc7-dimkey.png`, `a2-refused.png`, `a2-shake.png`).

**And last round's mystery, orange on orange: found.** It's a moment on letting go of a held pad, not the hold itself. `EXIT` turns to a grey `RELOOP` at once, while the key's orange takes a moment to fade (`N41`, `n-reloop-on-orange.png`). That's probably why I couldn't catch it in stills last round, and first-time users watching the key could.

**The most important problems:**
1. **`N37`: sliding from a hold can take a track out of a playlist, with no word and no way back.** It's the gesture anyone tries to drag a row with. No alert, no message and no `UNDO`, unlike every other removal in the app. It happened 2 times out of 3 on the folded Duo.
2. **`N38`: a deck playing with its channel fader down gets no word.** The meter on the deck moves, the mix's columns stay empty and nothing's coming out. The same silence from the crossfader gets a sentence. The first-time user found this and I reproduced it.
3. **`GC4` (the failure): the drop message doesn't appear,** so a row still lifts, goes nowhere and says nothing, which is what it was added to fix.

**The first-time user** could say what Auto DJ does at **+10:09**, against +15:32 last time, though only for tempos that are close. They didn't need telling to watch `STEMS`: the knobs and pads gave it away. "It's hard to tell who's in charge" has gone as the worst thing. Their worst now is that their first `AUTO` and first `MIX` both ended in a hard cut, "The stems didn't get there in time", with nothing saying beforehand how long stems take.

## Failures

### GC4: dropping a lifted row in a playlist says nothing
- **Steps:** in a playlist, hold a row for about 0.5 s and move off quickly. Hold much longer and the menu opens instead. Let go on a row, or on the blank space below the list.
- **Expected:** "To change the order, hold a row and choose Change the Order."
- **Actual:** the row lifts, follows the finger and floats back. No message, and the order stays as it was. That's 5 drops with a drag session in UIKit's log: 3 on the small iPhone on its side, on the blank space, and 2 on the folded Duo, on rows. Earlier tries of mine on the small iPhone gave no message either, but I can't say they were all drags. My one upright try on the small iPhone opened the menu.
- **It's a real drag, not my tool.** The row lifts in the video, and UIKit's log has a drag session each time. All the way through it says `takePotentialDrop: operation=0`, and it ends `dragEndedWithOperation:0`. So nothing was accepting the drop, and `.dropDestination` at `BrowserView.swift:282` may never be asked. A test of this needs a real drag, as the message doesn't come from anything but one.
- **Screenshot:** `gc4-drop-nomessage.png`, frames from a video at 2.5 a second.

## New problems

### N37 (new): sliding from a hold can remove a playlist's row at once
- **Steps:** on the folded Duo, in a playlist, hold a row until its menu opens (0.65 s and 1 s both did it), slide down about 270 pt without letting go, and let go on `Remove from Playlist`.
- **What happens:** the row's gone. No alert, no message, no `UNDO`. `library.json` went from 400 rows to 399, then 398. That's 2 times out of 3, and nothing happened the other time. The frames show the menu with the item highlighted, then the row gone.
- **Why it matters:** this is what someone does trying to drag a row, the thing the new mode's there to replace. On a long list, the first they'd know is a track missing later, and no one would be able to say which.
- **What you asked:** on a phone, a row in All Tracks doesn't lift, as you said. Sliding to an item there chooses it, and `Delete from Library` asks first (`gc4-slide-delete.png`), so that one's fine. `Load` does load, as you filmed last round. On the small iPhone on its side, a 114 pt slide in a playlist left the menu open twice, so it may need the longer slide. It wants a real thumb.
- **Screenshots:** `gc4-slide-removes.png`, `gc4-menu.png`.

### N38 (new, from the first-time user, reproduced): a playing deck with its fader down gets no word
- **Steps:** both decks stopped, pull deck 1's channel fader to the bottom, press `PLAY`.
- **What happens:** the clock runs, the waveform moves and deck 1's own meter moves, as it reads ahead of the fader. The mix's two columns stay empty. No message for 9 s and up. The first-time user sat at it for 15 s.
- **Compare:** the crossfader shut on the playing deck gets "Nothing's coming out."
- **How they got there:** a stopped `AUTO` had left their fader down where they'd put it, and they loaded the next track. So it's easy to reach mid-session.
- **Screenshots:** `n-fader-down.png`, `fu-playing-fader-down-no-warning.png`.

### N39 (new, from the first-time user, reproduced): holding `CUE` on the waiting deck ends the mix
- **Steps:** a mix on, deck 2 waiting, hold deck 2's `CUE` for 1.2 s.
- **What happens:** "Mix off: you started deck 2 yourself." and it's over, with 6 tracks to go and no way back but `MIX`. Its tempo goes back too.
- **Why it matters:** that's how you'd check a track you're about to hear, and the deck goes back to its cue when you let go. It's the rule as written, so it's a call for you or the owner. The wording also reads as blame, the first-time user says.

### N40 (new, small): `EXIT` just after a move gets a message that takes the question
- **Steps:** press `EXIT` on a build's old deck, meaning to hand back, just after it ends. Mine landed 0.7 s after "Loop build done."
- **What happens:** "There's no loop to go back to yet. Press a loop size, or IN and OUT." That's true, but it replaces the question, and it's the same late press as `N36`, on the other key that hands back.
- **Log:** 10:17:02.8 and 10:17:03.5.

### N41 (new, small): a grey `RELOOP` on bright orange, on letting go of a held pad
- **What happens:** while a `SLICE` or `ROLL` pad's held, it's `EXIT`, white on orange, and fine (`gc-slice-held.png`). On letting go, the word changes to a grey `RELOOP` at once, while the orange fades over about 0.4 s. For the first part of that it's grey on bright orange, and hard to read.
- **Seen on:** a video on iPhone 17 upright. Read the rows of `n-reloop-on-orange.png` left to right. `LoopRow` is the same on every layout.
- **The first-time user's words:** "The RELOOP word goes dim on bright orange: unreadable." It's last round's orange on orange, as far as I can tell.

## Blocked

| Test | Why |
|---|---|
| `GA1` Browser on video on the Duo | Folded (`Closed`, 13:01 on 11-04) and no iPad access |
| `GA2` Logo, frame by frame | The same |
| `GA3` Launch sweep, five launches on the Duo | The same. The small iPhone's is `B2` |
| `GA4` Pressing during the slide on the full layout | The same. I did press in a frozen slide on the small iPhone, and it landed on what was arriving |

## Looks wrong

- **First `AUTO` on a fresh track with little time left (the first-time user's worst thing).** It waits, then "The stems didn't get there in time. Deck 1 just started." I got the same with under 30 s left, upright, and it's what a newcomer does. The deck's header knows "Stems 15% · 2 min" and the other deck knows its time left, so it could say at the press that it won't make it. Their first `MIX` went the same way.
- **What's taken over isn't visibly taken yet (`GB3`).** "It's taken over deck 2's SYNC, EQ and stems, and deck 1's effects." `SYNC` and `EQ` go at the press, but `NO VOCAL` and `FLANGER` are still lit while it's saying so (`gb1-long-se.png`). The first-time user: "my knob didn't appear to move. I don't know what taking over means until something happens."
- **A control touched during the count stays as you set it, with no word.** I turned deck 2's `LOW` down at `5 BARS`. It stayed down through the move, and the deck came in with it down (`gb3-count.png`, `gb3-count3.png`). That's probably right, but it isn't what "From here, a control you touch is yours" suggests, as that comes after.
- **A mix doesn't say what it's taken over.** `whatItTakesOver` only runs outside a mix. The first-time user pressed `MIX` and their fader, fourth knob and crossfader went back, with no word they saw. I didn't reproduce that.
- **`That's yours` and the old deck.** The first-time user took `FILTER` on the old deck, was told "That's yours for this move", and it snapped back at the end. That's the rule (the old deck goes neutral), and "for this move" does cover it, but they noticed.
- **`NEXT`'s note against what you see.** "with tempo counting for more than key" reads wrong when the tempos are all out of reach. From 170, their list put 129.5 above 148. As far as I can read `SetOrder`, that's because neither's within reach and key decides. It didn't settle it for the first-time user, who still couldn't explain the order. It also doesn't say that what's on the other deck goes low: with Gepzene on air, Houston (126, on deck 1) came below Severe (148) (`gc4-next-both.png`).
- **Two messages on top of each other.** A new message comes in over one that's fading, unreadable for a moment (`n-overlap.png`, and the log at 10:18:18). The first-time user lost a tip to this. On a phone's browser, a fading message also shows the column headings through it (`k3-missing.png`).
- **The bars count doesn't say what's coming.** `13 BARS` under `AUTO` was read correctly, but not what's at the end of it. The words under the key are also 5 pt (`MixerPanel.swift:88`), and can shrink to 4. They're readable in a screenshot at twice the size, and I'd want a real phone to say. The first-time user saw `STEMS 26%` under `MIX` with 38% in the title line, as they're different tracks.
- **`?`'s note in the Mixer sheet.** At two lines, it sits against the bottom of `SPLIT` and `FILTER`, and it covers the sheet's own text (`gc3-help2.png`).
- **`?`'s note on `MASTER`, says the first-time user.** "A stopped deck can't lead", but `MASTER` lit on a stopped deck and the top bar followed it. I didn't check it.
- **"key" meaning a button** in the notes ("only keys that move between pages", "The key with the arrows", "Keys click"), on a screen with a `KEY` control and musical keys. Noted by the first-time user. Likewise `CUE` for the big key and for headphones, and "split" for stems and for `SPLIT`.
- **Fast Bird's numbers.** 139.7 in the library, 140.59 on the deck, 140.06 after stems, then 140.1 in the library. The first-time user read the master tempo as 148.06 to 150.09 while it followed. You've left this as its first analysis, and it's on its second first-time user now.
- **The playlist's name isn't on screen upright,** says the first-time user, and I see the same. Only the blue button says you're in one, and you have to open its menu to see which.
- **The row menu on a phone on its side is cut off.** `Re-analyse` is cut by the bottom edge and `Delete from Library` is below it, with nothing but the cut to say there's more (`gc4-menu.png`).
- **The sheet's top edge cuts the second line of the deck titles** on iPhone 17 on its side (`gc3-i17.png`). It's small, and the first line says enough.

## All results

| Test | Result | Notes |
|---|---|---|
| GA1 to GA4 | BLOCKED | Above |
| GB1 | PASS | Three lines inside the capsule, upright on the folded Duo (`gb1-tip.png`). Longest I could get: three lines at 375 pt (`gb1-long-se.png`). Details below |
| GB2 | PASS | 170 to 149.28 from 12 pt, with the sentence and `UNDO`, and more dragging says nothing more. `UNDO`: 170.00, `SYNC` on, marker green (`gb2-1.png`, `gb2-4.png`) |
| GB3 | PASS | Your steps gave your sentence word for word. Neutral: no such sentence. Start: "From here, a control you touch is yours." Details below |
| GB4 | PASS | First in the menu, on screen with no scroll, and it works (`gb4-menu.png`) |
| GB5 | PASS | All four cases, below (`gb5-q.png`, `gb5-f.png`) |
| GC1 | PASS | `CHOOSING`, `13 BARS`, `1 BAR`, `STEMS 25%`, `MIX 98 BARS`, `WAITING`, `AT THE END`. They all fit on the small iPhone and upright, without covering the key's name (`gc1-up.png`, `gc1-w.png`, `gc1-end.png`). Size: see Looks wrong |
| GC2 | PASS | `SYNC` on every page. Pads page: `MASTER` under it on the deck followed. Jog page: the `MASTER` key under it, lit orange (`gc2-a.png`, `gc2-up.png`, `b6-bpm.png`). It tells me who's following, with `MASTER 1` in the top bar |
| GC3 | PASS | Stays on the bottom edge, waveforms and headers above it, on the small iPhone and iPhone 17. All there, knobs turn (100 pt on `TRIM 1`, 80 pt on `MASTER`), the sheet doesn't move. Upright as before (`gc3-sheet.png`, `gc3-i17.png`, `gc3-i17b.png`, `gc3-knob.png`, `gc3-up.png`) |
| GC4 | **FAIL** | The drop message. Everything else passes: details below |
| GC5 | PASS | "3 of 5 showing, with ±6% BPM on." With a mix on, both lines (`gc5-filter.png`, `gc5-both.png`) |
| GC6 | PASS | Note at the bottom, message at the top, both readable (`gc6-a.png`) |
| GC7 | PASS | Every line seen, below |
| GC8 | PASS | Below |
| GC9 | PASS | Playing: carries on, 0:10 to 0:13 across the rename. Paused: stays paused at 0:19 (`gc9.png`, `gc9-p.png`) |
| GC10 | PASS | A hard edge under the bar, on its side and upright, with only a faint blur in it (`gc10-side.png`, `gc10-up.png`) |
| A2 | PASS | Doesn't load, the key shakes (`a2-shake.png`), a hand and "Deck 1 is playing. Stop it first." The swipe's `Deck 2` action says the same (`a2-refused.png`, `gc7-dimkey.png`) |
| A3 | PASS | Table below |
| B2 | PASS | On video, the meters run up and back once as the logo lifts, and stay down |
| B3 | PASS | Below the top bar on a phone, with `MASTER`'s number clear |
| B4 | PASS | 11 of 11 green, at x 663 to 670 of 1334, so centred, from 10:04:52 to 10:07:00. My first run lost its last 4 samples as a track ran out (`b4-marker.png`) |
| B5 | PASS | The jog shows the tempo, not `NO TRACK`, 1 s after closing (`b5-jog.png`) |
| B6 | PASS | Header and jog both 129.90, and the menu's title has the track's own speed (`b6-bpm.png`) |
| C4 | PASS | Stop and save, and Keep recording. Both work (`c4-alert.png`) |
| C7 | PASS | Whole titles in the browser, and two lines on a compact deck (`c7-titles.png`, `lr-1.png`) |
| C8 | PASS | A plate keeps the loop's line off the text (`c8-counter.png`) |
| C9 | PASS | All the same size on a phone, and `DEL` has room. `ROLL` and `STEMS` are the closest pair |
| D1 | PASS | Lit while soloed, and a second tap restores it (`d1-solo.png`) |
| D5 | PASS | New title straight away |
| D6 | PASS | `Stems 6%` on the deck's header. A phone has no compact deck in the browser, so it's seen on closing it, or on `MIX STEMS 8%` (`gb1-stems-se.png`) |
| D7 | PASS | 32 after the roll (`d7.png`) |
| D8 | PASS | The old loop doesn't follow (`d8.png`) |
| D9 | PASS | `.cue` and `.txt` use the new name inside and out |
| D10 | PASS | The mint layer has shape between the drum hits, on Gepzene (`d10-stems.png`) |
| D12 | PASS | Normal, then stem colours with a dim ghost, then normal (`d12-both.png`, `d12-c.png`) |
| E | PASS | The log lists nothing (a header line only). Pause while playing, play at the end (`e-c.png`, `e-d.png`) |
| F1 | PASS | `SAVE CUE`, `SAVE LOOP`, `LIST`, eight pads (`f1-mem.png`) |
| F2 | PASS | "Memory cue saved. The track loads here now." with `UNDO`, then "There's already a memory cue here." (`f2-save-cue.png`) |
| F3 | PASS | "Set a loop first, then save it." Then an orange pad and a bar (`f3-saved-loop.png`) |
| F4 | PASS | Jumps, holds and lights, and a second tap ends it (`f4-saved-loop.png`) |
| F5 | PASS | `DEL`, a pad, `UNDO`. My first `UNDO` came after it had gone (`f5-undone.png`) |
| F6 | PASS | "Drop", in green, reaches the pad. The loop's switch: on reload `RELOOP` reads `ARMED`, and the deck stays where it is (`f6-menu.png`, `f6-pad.png`, `f6-armed.png`) |
| F7 | PASS | All there after a relaunch: 1 hot cue, 1 memory cue, 1 loop |
| J1 | PASS | Skylander 8 sections, Gepzene 6, Exhilarate 6, Houston 9, Severe 13 (`j1-phrases.png`) |
| J2 | PASS | Counts up, and restarts at a boundary: `UP 8.3` to `CHORUS 2.4` in the log's sampling, `CHORUS 31.3` to `DOWN 1.4` |
| J3 | PASS | Exhilarate reads 170.00 only across the log, Severe 148.00. See Looks wrong for Fast Bird |
| K1 | PASS | Saved in Files, "Backup saved." Its alert's title is Backup (`gc7-backup-alert.png`) |
| K2 | PASS | "Restored 7 tracks and 2 playlists." and the cue's back, name and colour too (`k2-restored.png`) |
| K3 | PASS | Triangle, and "Skylander's file is missing. Import it again and it'll get its cues back." (`k3-missing.png`) |
| K4 | PASS | Copied back to `Documents/` under its imported name: moved home, same ID, with its cue, memory cue and loop, and no second row (`k4-back.png`) |
| K5 | PASS | `Segue DJ Library 2026-11-05.json`, and `Before restore 2026-11-05 100033.json` |
| Long run | PASS | Below. 15:10 with `DUB`, no crash, every gap explained |

### GB1: the capsule

| Message | Where | Lines | Inside? | What it covers |
|---|---|---|---|---|
| The first load's tip | Folded Duo, upright, in the browser | 3 | Yes | The column headings and the top of the first row, about 11 s (`gb1-tip.png`) |
| The same | Small iPhone on its side | 2 | Yes | The headings and the first row's top (`gb1-se-tip.png`) |
| "Echo throw next... It's taken over deck 2's SYNC, EQ and stems, and deck 1's effects. AUTO's counting down the bars." | Small iPhone upright, 375 pt | 3 | Yes | The top of deck 1's waveform and its section name (`gb1-long-se.png`) |
| "Moved the crossfader to the middle. Auto DJ is waiting for the stems. If this track finishes first, deck 1 starts." | Folded Duo upright | 2 | Yes | The top of deck 1's waveform (`gb1-long.png`) |
| The same | Small iPhone upright | 3 | Yes | (`gb1-stems-up.png`) |
| The same | Small iPhone on its side | 1 | Yes | The top of deck 1's waveform (`gb1-stems-se.png`) |

**Is what it covers a problem?** Not for me. The waveform's top and a section name for a few seconds cost nothing, as the bars count's still on the key. In the browser, it covers the first row's top for about 11 s, and I'd wait before pressing that row. The thing I'd watch is a message over `UP` or `CHORUS` on deck 1 for someone counting to a drop.

### GB3: does that settle who's in charge?

**For me, mostly.** The press says what it's taken, and the start says what's mine. It no longer feels like a guess, and the first-time user agrees: "It's taken over" raised the question and "From here" and "That's yours for this move" settled it. What's left is smaller, and it's under Looks wrong: what's "taken over" that hasn't visibly been, a touch during the count, and the old deck's control snapping back.

The words:
- **09:14:13, your steps:** "Loop build next, with deck 2 cued at 126 BPM. It's taken over deck 2's SYNC, EQ and stems, and deck 1's effects. AUTO's counting down the bars." (`gb3-msg.png`, with `gb3-before.png`).
- **09:17:16, all neutral:** "Echo throw next, with deck 1 cued at 126 BPM. AUTO's counting down the bars."
- **09:14:36, starting:** "Loop build starting. Put both decks on STEMS to watch it. From here, a control you touch is yours." (`gb3-start.png`). 09:21:58: "Echo throw starting. From here, a control you touch is yours."
- **10:16:09, after a handed-back build:** no "taken over" sentence, though deck 1's `LOW`, filter and stems were off. They go back at the press, which is right, as they were the score's and not the user's (`lr-hb2.png`, `lr-8.png`).

### GB5: `AUTO` just after a move

| When | Press | What happened |
|---|---|---|
| 09:20:27.2, 0.4 s after "Loop build done", question up | First | Nothing started, and the question stayed (`gb5-q.png`) |
| 09:20:34 | A press after that | `CHOOSING`, then the next move |
| 09:17:14, about 2 minutes after the move | First | The next move starts |
| 09:22:14.6, under 1 s after "Echo throw done", question gone (I'd pressed `SYNC`) | First | "That move's just finished. Press AUTO again for the next one." (`gb5-f.png`) |
| 10:18:18 | First, then a second at once | The same, then `6 BARS` and the next move |
| 09:21:42, stopped 1 bar before a move started | Pressed 3 s after | "Auto DJ stopped. The decks are yours." then the next move, no refusal (`gb5-d.png`, `gb5-e.png`) |
| 09:20:58, stopped as a move started, both decks playing | Pressed at once | "Auto DJ brings in a stopped deck. Stop the one you want next." That's right, as both were playing, and it's a refusal only for that |

### GC4: changing a playlist's order

| Asked | Result |
|---|---|
| Hold a row in a playlist: `Change the Order` | There, below `Remove from Playlist` (`gc4-menu.png`) |
| Handles, a line along the bottom, `DONE` | "Drag the handles to change the order." (`gc4-mode.png`) |
| Drag some rows | Houston to the top and Exhilarate to the bottom, as asked (`gc4-drag1.png`, `gc4-done.png`) |
| A long way in a long list | 400 rows on the folded Duo: Row 001 went to place 30 in a 6 s hold at the bottom edge, which is slow for 400 rows. It scrolls, and it lands where you let go (`gc4-long.png`) |
| `DONE`, reopen, relaunch | It stays, in `library.json` and on screen (`f7b.png`) |
| `MIX` plays that order | "Mixing through Order Test, 4 tracks to go. Up next: Severe Tire Damage - High Quality." after Houston (`lr-mix0.png`) |
| From a sort, `NEXT` or a filter | All three go back to its own order first (`gc4-sort-both.png`, `gc4-next-both.png`, `gc4-from-filter.png`) |
| Changing list or closing the browser ends it | Yes, both |
| History doesn't offer it | It doesn't (`gc4-history.png`) |
| **Dropping a lifted row says so** | **No. It says nothing: the failure above** |
| On a phone, a row in All Tracks doesn't lift | It doesn't: no drag session in the log, and the menu opens (`at-after.png`) |
| What does sliding to a menu item do? | `Delete from Library` asks. `Load` loads. **`Remove from Playlist` just does it: `N37`** |

### GC7: words

| Line | Seen |
|---|---|
| "The stems didn't get there in time. Deck 1 just started." | 09:31:52, `AUTO` on, upright, as the other track ran out |
| "Analysed Exhilarate again: 170.0 BPM, 12B." | 09:25:30 |
| "The bar starts here now." with `UNDO` | 09:26:01 (`gc7-downbeat.png`). The 10 ms keys: "Beat grid moved 10 ms later." (`gc7-10ms.png`) |
| "A file you picked in Files stays there." | `gc4-slide-delete.png`. The backup's alert says Backup (`gc7-backup-alert.png`) |
| "Deck 2 is now 24% slower than its own 170 BPM, to follow." | 10:04:37 (`gc7-slower.png`). "33% faster than its own 128" at 09:05:30 |
| "That's yours for this move. The mix carries on with the rest." | 10:10:52, on a filter being swept (`gc7-yours.png`). **Not on every grab:** `HI` on the same deck got no word at 10:10:30. I think that's because the score wasn't moving it |
| `NEXT`'s note | Read. It explains the chain, and the first-time user still couldn't explain their order. See Looks wrong (`gc7-next-note.png`) |
| `TIME`'s note | "A new track waits at its first beat or its memory cue, so it can read a little way in before it's played." (`gc7-time.png`). Clear |
| A dim load key on a phone | "Deck 2 is playing. Stop it first." 09:24:37, with a hand (`gc7-dimkey.png`) |

### GC8: pads

- **`START`:** with Prepare stems off, Skylander's `STEMS` page offers it, and it starts the split: `STEMS 25%` on `AUTO`'s key by 09:31:41 (`gc8-start.png`).
- **`SET`:** "Now press the pad you want to change." (`gc8-set.png`).
- **The sampler's sheet:** "One shot plays to its end, Gate while you hold the pad, and Loop until you press it again." It fits on its side, all of it (`gc8-sheet.png`).
- **The tips:** once each. `STEMS`: "On this page, the waveform shows each part in the colour of its pad." `MEM`: "SAVE CUE or SAVE LOOP fills the next pad, and it stays with the track." (`gc8-stems-tip.png`, `gc8-more1.png`).
- **`MORE` round:** the tabs beside it don't move, and each name fits (`gc8-more-round.png`). It still doesn't say what's next.

## Timings and measurements

### CPU, small iPhone, this simulator's process only

Each row is six 5 s samples after the first, with the Mac busy beside it (the first-time user, plus `cheeks-6d`'s builds at times). Stems had finished.

| State | Now, average | Peak | Memory | Mac idle | Last round |
|---|---|---|---|---|---|
| Idle, nothing loaded, 25 s after launch | 2.9% | 3.2% | 73 MB | 23% | 3.8% |
| Two tracks loaded, paused | 3.7% | 4.2% | 246 MB | 14% | 4.5% |
| One deck playing | 10.1% | 14.1% | 246 MB | 7% | 9.3% |
| Both playing and synced, tempo offset | 16.2% | 19.0% | 246 MB | 8% | 14.8% |
| Both of those, plus stems and an echo | 15.8% | 16.7% | 394 MB | 17% | 15.5% |

The rise when both are playing looks like the Mac's load: the same state with stems and an echo on top read lower, with 17% idle against 8%.

### The long run

**Small iPhone, `DUB` throughout. Recording 10:09:28 to 10:24:40: 909.7 s, 15:10, mean -15 dB, peak -0.1 dB. 7 moves ran or were handed back.**

| Time | Done | What happened |
|---|---|---|
| 10:09:21 | `DUB` chosen, then `REC` | |
| 10:09:33 | `MIX` on Order Test, nothing playing | "Mixing through Order Test, 4 tracks to go. Up next: Severe Tire Damage - High Quality." Starts at its order's top (`lr-mix0.png`) |
| 10:09:47 | ±6% on | "3 of 5 showing" and the mix's line, both (`gc5-both.png`) |
| 10:10:08 | Seek Houston to about 3:05 | `MIX 96 BARS` to `9 BARS` |
| 10:10:29 | | **Loop build into Severe,** at 126 and 148 |
| 10:10:30 | Grabbed `HI` | Nothing said. I think the score wasn't moving it |
| 10:10:52 | Grabbed the swept filter | "That's yours for this move." |
| **10:11:04** | **`AUTO`, 35 s in** | **"Mix off. Deck 2 is on."** Houston stopped, Severe plays clean (`lr-hb1.png`) |
| 10:11:33 | `MIX` on All Tracks, Severe playing | "3 not played yet. Up next: Gepzene" (`lr-mix2.png`) |
| 10:11:40 | **Load on the waiting deck:** Fast Bird on 1 | "Up next: Fast Bird. The mix carries on." `MIX STEMS 8%`, then it counted |
| 10:14:34 | **Seek past the exit:** Severe to 6:44 | "No clean way in. Next track starts when this one ends." |
| 10:14:37 | | Fast Bird starts as Severe's sound ends: 0.58 s under -50 dB |
| 10:14:42 | | "No clean way in. Deck 1 just started." Gepzene's next: `MIX 89 BARS` by 10:14:53 |
| 10:14:58 | Seek Fast Bird to about 2:20 | `MIX 15 BARS` |
| 10:15:23 | | **Loop build into Gepzene** |
| **10:15:50** | **`EXIT`, 27 s in, the build's last bars** | **"Mix off: deck 1's loop was changed. The decks are yours. ALL brings back deck 1's stems."** Gepzene back at its start and stopped, Fast Bird carries on, its `LOW` and filter showing (`lr-hb2.png`) |
| 10:16:08 | Seek Fast Bird back, `AUTO` | They go back at the press (`lr-8.png`). "Loop build next, with deck 2 cued at 128 BPM." |
| 10:16:31 to 10:17:02 | | A whole Loop build, 31 s |
| 10:17:03.5 | `EXIT`, too late | `N40` |
| 10:17:29 | Load Severe on 1, `AUTO` | Echo throw, 10:18:04 to 10:18:17 |
| 10:18:18 | **`AUTO` just after, question gone** | "That move's just finished." Second press: `6 BARS`. Third: off |
| 10:18:30 | Load Fast Bird on 2, `AUTO` | **"Bass swap next, with deck 2 cued at 148 BPM."** |
| 10:18:47 to 10:19:18 | | **Bass swap,** breath 0.36 s at 10:19:04.9 (`lr-bs.png`) |
| 10:19:27 | `MIX` on All Tracks, Fast Bird playing | "1 not played yet. Up next: Skylander." (`lr-mix3.png`) |
| 10:19:50 | Seek Fast Bird to 2:18 | `MIX 19 BARS` |
| 10:20:17 | | "Loop build into Skylander. Put both decks on STEMS to watch it." |
| **10:20:42** | **`EXIT` on deck 2, 24 s in** | **"Mix off: deck 2's loop was changed. The decks are yours. ALL brings back deck 2's stems."** (`lr-hb4.png`) |
| 10:20:56 | `MIX` again | "1 not played yet. Up next: Skylander." Echo throw into Skylander, 10:21:06 to 10:21:20, with 14 s left |
| 10:21:29 | **Load on a mix's last track:** Exhilarate on 2 | "This is the last track." then "Up next: Exhilarate. The mix carries on." (`lr-last.png`, `lr-last2.png`) |
| 10:22:31 | | Skylander, its saved loop armed, passed 1:44 mid-mix and wasn't caught |
| 10:22:38 | Stopped deck 1 | "Mix off: deck 1 was stopped." |
| 10:22:57 | **`MIX` with Skylander loaded, its saved loop on,** sort by `BPM` | "6 tracks to go. Up next: Houston." `MIX 115 BARS` |
| 10:23:33 | Seek to before the loop | Skylander past 1:44 at 1:53, loop off |
| 10:23:36 | Held `CUE` on the waiting deck | `N39` |
| 10:23:53 | **Frozen: `BROWSE`, then `1` on a row** | Landed on the arriving row: "Deck 1 is playing. Stop it first." |
| 10:24:03 | **Frozen: `DECKS`, then `PLAY` on deck 2** | Deck 2 starts, and no cue's been set (`lr-slide2.png`) |
| 10:24:40 | `REC` off | "Saving your mix..." Saved within about 25 s |

**Every gap under -50 dB of 0.2 s or more:**

| In the recording | Length | What it is |
|---|---|---|
| 0.00 | 4.89 s | Before I pressed `MIX` |
| 41.16 | 0.23 s | Houston's own, at 3:06 |
| 308.71 | 0.58 s | Severe's own silence at its end, with Fast Bird starting: no way in, as I'd sent it there |
| 343.34, 344.61 | 0.26, 0.93 s | Fast Bird's own, at 2:34 to 2:36. They come back on the second pass |
| 446.53 to 465.24 | Six, 0.24 to 0.35 s | Gepzene's own, 0:11 to 0:30, 435.3 s off at each |
| 510.28 | 0.24 s | Gepzene's own, at 1:15 |
| **576.88** | **0.36 s** | **The Bass swap's breath** |
| 637.62, 638.81 | 0.22, 0.88 s | Fast Bird's own again |
| 789.01 | 19.33 s | I stopped the only deck playing, then pressed `MIX` |

Afterwards, nothing was left silent, looping or filtered that the screen didn't show. After both `EXIT`s, the stems were off on a deck playing on, with a sentence, the dots on the tab and the knobs all saying so.

## First impressions

**1. Does it look like $1000 pro software?** With both decks running on its side, yes. It's still the first impression I'd show anyone. Three things break it most:
- **Stock menus.** A row's menu is iOS's on a screen that's otherwise a controller, cut off at the bottom on a phone on its side.
- **Messages over the music.** Three lines are readable now, and that's a fix, but they sit over deck 1's waveform, and two can overlap as one fades.
- **Sheets.** The Mixer sheet's far better on its side. Recordings and Settings are still plain iOS on black, with a lot of nothing.

**2. What felt slow, confusing or surprising?**
- **Nothing felt slow in the app itself.** The wait for stems is the one slow thing, and it's on the simulator's CPU.
- **Holding `CUE` ending a mix.** I'd have called that the safest thing to do.
- **What a mix leaves out.** After a while, everything's ticked, and "To go round again, stop the deck and press MIX" means stopping the music to go on.
- **A row going from a playlist with no word,** when I'd been trying to drag it.

**3. Which control was hardest to find or hit?** Hardest to find is still the tempo fader, for the first-time user: about 4 minutes, even with `TEMPO` under `JOG`. Hardest to hit is the knobs on the small iPhone, and `UNDO`, which sits in a different place for each message. I missed it twice this round by waiting too long, as it's gone after about 8 s.

## The first-time user

`iPhone 17` upright, 09:34:21 to 10:20:47, 46:26, with their last touch at 10:18:50. Fresh install, music in Files, no backups in Files, no docs or code. They know more about DJing than a real newcomer, and say so, so treat their times as the fastest case. Their screenshots are in `docs/test-results-20/fu-*.png` at 500 px wide.

| Stage | From opening |
|---|---|
| Music in | 0:44 |
| First sound | 1:11 |
| Two tracks together | 1:49 |
| First move, by hand, finished | 2:29 |
| First `?` | 2:44 |
| First `AUTO` | 6:29, and it gave up at 7:45 |
| First `AUTO` that ran | 8:39 to 10:09 |
| First `MIX` | 17:24 |
| First beat-match by hand | 24:09 |

**How long until they could say what Auto DJ does: +10:09** (09:44:30), against +15:32, +13:25, +10:41 and +16:52 before. "It finds where the new track comes in, matches its tempo, counts down, loops the old track, fades it out part by part, then stops it." That's true for close tempos. They couldn't explain an echo throw until the guide, at +21:59, and not a Loop build between 128 and 170, where neither tempo moved. I can't say how that sounds, and it's one for the owner's ears: mine had one too, 126 and 148 (`lr-hb1.png`).

**Is it clear who's in charge?** "Mostly clear." "It's taken over..." raised the question, and "From here, a control you touch is yours." and "That's yours for this move." settled it. They stopped being sure at: `FILTER` snapping back after the move, `AUTO` moving the crossfader with no message they saw (09:42:06, 09:55:40), a deck dropping `SYNC` by itself when the other ran out (10:10:25), and tapping the `MIX` key or holding `CUE` ending the mix outright.

**What's still doing nothing with no word?**
- `SLICE` pads when tapped. A tip was lost in a message overlap.
- Dragging a playing waveform. The overview has its tip now, and the waveform doesn't.
- `KEY SYNC`: it had acted, and undone a `−`, but nothing showed it.
- A deck with its fader down (`N38`).
- `PITCH` moved only its arc, which may be audible.
- Thumbs up: they saw no answer, though thumbs down said "Got it. Less like that." It may have passed.

**The words under `AUTO`:** readable on enlarged screenshots, they can't vouch for real size. `BARS` and `STEMS` read as what they are. `CHOOSING` as "picking a move", which nothing confirmed.

**`SYNC` with `MASTER` under it:** partly. They read it as "this deck leads", and `MASTER 1` in the top bar and the blue `SYNC` on the other deck did more of the work.

**`?` notes that didn't help:** `MIX`'s, as it doesn't say what's coming. `DEPTH`'s is thin. `NOISE`, `CRUSH` and `PITCH` are only names. They didn't read them all.

**They never used Change the Order.** They saw it at about 10:12, on a playlist of one track.

**Best thing:** "it explains itself at the moment you need it, in plain English, without stopping the music."

**Worst thing:** "the first try at both one-press features ended in a hard cut", with the fader-down silence close behind.

**No crashes,** and they never had to restart. Their own full report is below, unchanged. Some of their taps came long after what they were aimed at, as their tool takes 1 to 3 s a step, and they've corrected the ones they caught.

**How I left things:** apps closed on all simulators, no recorder or logger running. 103 GB free. `iPhone 17` is upright with their settings changed in its install: waveform colours RGB, Pad 1 replaced, two recordings, a playlist. The small iPhone's on its side, with Prepare stems back on, and with my playlist `Order Test` and recording `Round TwentyRound 20`, the name being my tool's typing and not the app's fault.

### Not tested
- **`GA`:** pressing during the full layout's slide, the Duo's video, its logo and its sweep.
- **A real thumb** on anything, above all `N37` and the fader.
- **How anything sounds,** haptics, double-tap.
- **`Grab Deck 2's Loop` replacing a sample with no word,** which the first-time user reported (09:51:25). I only read that the button shows for any deck with a loop set, running or not.
- **The first-time user's `MIX` resetting a fader,** and `MASTER` on a stopped deck. Both are theirs alone.

---

# The first-time user's report, unchanged

# Segue DJ - first-time user report (fu20)

Session opened 09:34:21.

## Running notes
- 09:34:21 launch. Splash with turntable logo about 4s, then library screen with "No music yet". Empty-state text tells me exactly what to do. (fu-first-screen.png, fu-no-music-yet.png)
- 09:34:30 tapped the highlighted import button. Menu: "Music files..." and "DJ library (XML)...". Took "Music files...". "Opening Files..." toast, then about 4s until the picker appeared. (fu-files-picker.png)
- Picker first showed an empty sheet titled Segue DJ, then jumped to On My iPhone by itself. My Music has 7 items; Segue DJ folder says "2 items".
- 09:35:03 Open tapped, about 09:35:05 "Added 7 tracks." Columns BPM and KEY fill in with "..." (fu-added-7-tracks.png)
- 09:35:14 tapped a track row expecting something to happen. Got a useful toast: "Press 1 or 2 to load this, or hold the row for more."
- 09:35:20ish pressed 1 on Houston: title goes blue, 1 lights, MASTER 1 126.00 appears top. No visible deck yet. Severe Tire Damage's 5A went into a filled pink pill: nothing says why (same key as loaded track, I assume).
- 09:35:25 DECKS button: huge screen, deck 1 top, mixer middle, deck 2 bottom. Dense but familiar.
- 09:35:32 played deck 1: green pause button, timer counts, meters move, waveform scrolls. (fu-first-sound.png)
- 09:35:50ish back to BROWSE. Deck 1's 1 buttons now dim because it's playing; pressed 2 on Skylander (125).
- 09:36:00 SYNC on deck 2: goes blue, 125 -> 126.00, +0.8% shown.
- 09:36:08 play deck 2. Both playing. A tip appeared unprompted: "Two basslines clash. Turn the new track's LOW down, and swap the two LOWs as you crossfade." (fu-basslines-tip.png)
- 09:36:26-09:36:50 followed the tip: dragged deck 2 LOW down (knob turns on a vertical drag, first try), then moved crossfader to 2 in two drags, cut deck 1 LOW, raised deck 2 LOW. (fu-crossfaded-to-2.png)
- Deck 2 LOW did not return to dead centre: small blue arc sits just right of noon. Dragging back by eye can't land on zero; I don't know yet if double tap resets.
- With crossfader fully at 2, leftmost meter column still reads high: meters seem to be before the fader and the four columns are not labelled.
- Then pressed ? (09:36:55ish).
- 09:37 help mode (fu-help-mode.png): "Touch anything to see what it does." Great idea: music keeps going, nothing changes. AUTO, MIXER, FILTER, SPLIT, CUE/MST and METERS all explained clearly. Meters explained: deck 1, mix L+R, deck 2.
- Wording: help says "only keys that move between pages still work", and Mixer sheet says "The key with the arrows chooses what each deck's fourth knob does." "Key" is used to mean "button" in an app where KEY is also a musical thing and a labelled button.
- In help mode inside Mixer, the help box covers the last line of the sheet's own text (the arrow-key line was hidden until a shorter help showed). "One output, like AirPods..." line also touches the box.
- 09:37:50-09:39:20 still in help mode. Beat blocks, overview, track, time, Q, SLIP, KEY, KEY SYNC, jog, DEL, MEM, SLICE, JUMP, SMPL all have clear text. Help box flips top or bottom to avoid the control; it covers waveforms or pads while up. (fu-jog-page.png)
- Waveform icon next to BROWSE/DECKS turned out to be RECORDINGS: I'd not have guessed; a waveform icon reads as "audio view".
- JOG/TEMPO button swaps the deck panel to a turntable page, label becomes PADS. No other way to reach the tempo fader. Tab MORE > cycles MEM > SLICE > JUMP > SMPL > MEM; the MORE label changes to whichever page you're on, so "MORE" disappears.
- 09:39:25 STEMS page on deck 1 once its analysis finished (about 4 min after loading): VOCAL/INST/BASS/DRUMS with SOLO row; ACAPELLA, NO VOCAL, BEAT, ALL. Waveform recolours by part; ACAPELLA left a pink-only waveform and deck 1's meter dropped. (fu-stems-page.png)
- 09:39:45 tried to load on playing deck: toast "Deck 1 is playing. Stop it first." Clear. Loading is blocked on a playing deck.
- 09:39:55 hold row: Load on Deck 1, Load on Deck 2, Preview, Re-analyse, Delete from Library. Preview toast: "This preview's over the mix, as SPLIT's off. It won't be on a recording."
- 09:40 KEY filter: "2 of 7 showing, with KEY on."  +-6% filter: "4 of 7 showing". NEXT re-sorts by "good order to play". Order was 128, 129.5, 170, 148, 139.7: the jump 129.5 to 170 looks odd given the help says tempo counts more than key.
- ~09:40:15 Houston reached the end while list was on screen: MASTER changed to 2 by itself and the NEXT list reshuffled under my finger.
- 09:40:50 loaded DJ Karda on deck 1 while Skylander played, then pressed AUTO. Button becomes "AUTO / STEMS 6%". Toast: "Auto DJ is waiting for the stems. If this track finishes first, deck 1 starts." Clear, honest, but it means AUTO's one transition will sit for a couple of minutes. (fu-auto-pressed.png)
- 09:41:10 gear > Settings > "What everything does": a searchable manual, with "Start here": LOAD AND PLAY, MIX TWO TRACKS, LET IT MIX. Very good, but I only found it because I went looking in Settings: 7 minutes in. The MIX TWO TRACKS recipe matches what I'd done. (fu-what-everything-does.png)
- 09:41:40 in manual, search "knob" finds FILTER KNOB and MIXER but not HI/MID/LOW, which is what I wanted. "double" found "LOW ... Double-tap for the centre", so that answered it, by luck of the word I picked.
- Keyboard auto-capitalised "double" to "Double" in search box: harmless. While typing "knob" the list showed the unfiltered list at "k" for a moment. Minor.
- Settings also has crossfader curve, match loudness, prepare stems on load, waveform colours, haptics, recording format, backups.
- 09:42:06 AUTO outcome: "The stems didn't get there in time. Deck 1 just started." Skylander ran to 00:00.0, deck 1 started on its own a few secs before that, crossfader jumped to centre, AUTO light off. No transition happened: AUTO gave up after 70s. (fu-auto-stems-not-in-time.png)
- That means pressing AUTO on a fresh track with under ~2 min left is a dead end, and the app did warn me but nothing told me how long stems would take (65% after 75s, then 67%).
- Deck 1 LOW was still fully down from my earlier transition, so DJ Karda started with no bass. Neither the load nor AUTO reset or mentioned it. I noticed only because I'd been looking at the knob.
- 09:42:40-50 tried double-tap on LOW knobs to centre them, as manual says. Nothing happened. Fair warning: my taps arrive about 2s apart through this tool, so that isn't a real double-tap: not an app fault that I can claim. Dragged them back instead. Right knob snapped to centre; left one overshot and won't land dead on (tiny blue arc left).
- Deck 1 stems finished at 09:42:45, about 2 min after load (Prepare stems on load). The little % bar became a green dot "AI". Nothing explains what "AI" means. Waveform changes colours on its own as soon as stems are ready (because I was on STEMS page).
- 09:43:00 pressed AUTO with Houston (stems already done) on deck 2. Button reads "AUTO / CHOOSING". (fu-auto-choosing.png)
- 09:43:06 AUTO toast: "Loop build next, with deck 2 cued at 130 BPM. It's taken over deck 1's EQ. AUTO's counting down the bars." Button counts bars (24 BARS ... 4 BARS). Deck 2 moved to 129.53 (+2.8%), jumped to CHORUS and waits there, without me asking. Clear and rather good. (fu-auto-countdown.png)
- "It's taken over deck 1's EQ" is honest, but my knob didn't appear to move. I don't know what taking over means until something happens.
- Question-mark mode: STEM STATUS explains AI/green dot. ?-mode works during AUTO without disturbing it.
- 09:43:54 "Loop build starting. From here, a control you touch is yours." Deck 1 loop shown as orange band; the time goes backwards (01:55 back to 01:53) so loop is on. Waveform loses pink/green, drums and bass only, but VOCAL and INST pads stay lit on deck 1. I can't tell from the pads which parts are playing. FILTER knob moves on its own. Deck 2 pads go dim: all four parts off, ready to fade in, I assume. (fu-auto-loop-build.png)
- 09:44:30 AUTO worked this time (started 09:43:00, done about 90 secs later): "Loop build done. Deck 2 is on. More loop builds?" with thumbs up and down. Deck 1 stopped, EQ reset to centre, MASTER moved to 2. Knobs moved visibly while it worked, and the pad fill showed BASS sinking: lovely to watch. (fu-auto-done.png)
- During it I didn't know: is thumbs for me to teach it? "More loop builds?" reads as an offer: I'd have thought thumbs up would do another. Nothing says it means "give me more of this kind in future".
- Crossfader sat in the centre the whole time, moves via stems and EQ rather than the crossfader. Fine, but now the crossfader remains in the middle with deck 2 on.
- After AUTO, deck 1 is stopped at 01:52 with its CUE lit at -02:45: nothing to tell me what to do with deck 1 next. Fine but I'd want "load next" nudging.
- 09:44:40 thumbs up on "More loop builds?" Banner went straight away, no confirmation at all. I still don't know what I told it.
- 09:44:50 Loop page: tapped 4: band shows, EXIT lit, track time keeps counting up (01:52 etc.) though the position is looping. Changing to 2 by tapping 2 worked, tapping 4 again worked and tap on lit pad turned loop off. Good.
- 09:45:00 Roll page shows a toast only because I'd tapped once: "ROLL pads play for as long as you hold them." Handy. Hold 1/4 for 2s: band short; EXIT/RELOOP goes dim-orange; on letting go track jumped on as if it had kept going (position 12.4 afterwards). Clear to see on waveform.
- 09:45:15 FX page: 12 effects. Tapped ECHO: lit, dot appears above FX tab so I can see it's on from any page. Waveform thins as echo plays.
- ? mode on V I B D, OUT, DEPTH: the V/I/B/D explanation is good. DEPTH: "How strong the effect is." Fine. "Beats" arrows not tried yet.
- 09:46:00 OUT: "Echo out on deck 2. Press OUT again to bring it back." Waveform shows gaps. Deck 2's meter fell. ECHO pad unlit itself. But track position keeps running while it's silent. (fu-echo-out.png)
- 09:46 BRAKE: deck 2 waveform slowed, deck stopped, play button returned to green triangle. The little square on BRAKE and BACKSPIN apparently means "this will stop the track". Nice.
- 09:46:10 REC turned red at once with a timer, no question asked. Timer read 0:04 while I was in browse. Count "1", then "2" after second deck played: that count is unexplained until ? tells me it's number of tracks.
- 09:46:25 loaded Gepzene on deck 1. Very sparse thin-spike opening in the waveform, but labelled "CHORUS 1.1" from the first beat. Looks wrong: an intro labelled chorus. Same track's first mark has a blue "CHORUS". (fu-gepzene-chorus-label.png wanted)
- 09:46:35 headphone button on deck 1: "You'll hear the cue with SPLIT on and a splitter cable." Clear about a thing I couldn't have guessed, and nice to learn. But the word CUE now means two things: the big CUE button and the headphones.
- 09:46:50 ? on beat blocks: "mirrored about the middle ... The scale in the middle shows how far apart they are." With sync on, green dot in the centre. Now I understand that strip, took 12 minutes. Sensible explanation.
- 09:47:20 REC stop: "Stop recording? Stop and save / Keep recording". Good: can't lose it. Toast "Saved Mix 2026-11-05 09.46.12". It took about 4 sec between pressing and REC going off, during which the timer ran on (1:06 > 1:10), so it's not quite instant but fine.
- 09:47:30 Recordings: "A recording plays out loud, over the mix. To listen to one, stop both decks." Play button grey. Tracklist icon gives timestamps: "00:03 Solxis - Houston (129.5 BPM, 5A)", "00:23 Gepzene - Can't be Serious (129.5 BPM, 1A)". (fu-recording-tracklist.png) Lovely. Recorded 1:10, 2.3 MB, M4A.
- First tap on tracklist icon just expanded the sheet from half to full height and the tap was lost. Had to tap again. Small, but looked broken.
- 09:48:20 Tapped the small "+2.8% v" under deck 2's BPM out of curiosity. Menu: Back to Its Own Speed; "Beat grid: 126.00 BPM at normal speed"; Double/Halve the Reading; BPM +/- 0.1; Grid 10 ms earlier/later; Set downbeat here; Save cue as memory cue. (fu-bpm-menu.png) Great power, totally hidden behind a tiny arrow and I found it by accident 14 min in. Capitalisation mixed: "Back to Its Own Speed", "Double the Reading" v "Set downbeat here", "Save cue as memory cue".
- 09:48:25 Selecting "Back to Its Own Speed" on deck 2: back to 126.00, arrow under BPM stays; SYNC off too. Good and quick.
- 09:48:30 JOG page on deck 2 with a stopped deck: tempo fader up one drag moved it to -9.3% and 114.27 BPM. So fader up = slower: the "wrong way" for beginners (though I knew that decks do this). Nothing explains it. Fader snapped to centre with "+0.0" on the way back. ± button (range) not explored yet.
- Key +1 changes 5A to 12A at the plate. Fine but it doesn't look like "one higher" to a person who doesn't know the Camelot wheel: 5A +1 becoming 12A looks random.
- Jog drag on stopped deck moved the track by a second (-01:54.8 to -01:53.9) and needle moved. Works. A cue ring appears round the platter as I drag.
- 09:49 Confused: tapping - then KEY SYNC twice looked like "minus does nothing" (+1 each time). Actually minus worked (±0, 5A) and KEY SYNC set it straight back to +1 (12A, beside deck 1's 1A). KEY SYNC gives no message when pressed, no lit state after. Took me 60 secs. (No screenshot: nothing visibly happens, that is the problem.)
- 09:49:40 CUE pads: tap empty A sets a hot cue at the spot: A goes red with time 2:56 and a red marker appears on waveform and overview. Tap again jumps. No help needed. DEL: tap DEL (goes red), tap pad: "Deleted hot cue A" with UNDO. That is well done.
- 09:49:55 UNDO put hot cue A back, cue marker returns on overview.
- 09:50:00 MEM page: SAVE CUE, SAVE LOOP, LIST, DEL. Save cue: "Memory cue saved. The track loads here now." with UNDO. Tells me the point at last. Bookmark pad with time 3:20 appears, red triangle on overview.
- 09:50:10 BROKEN-ish (visual): tapped MORE to SLICE page while the "Memory cue saved" toast was still fading. Two toasts drawn on top of each other for a second: unreadable jumble. (Transient: couldn't catch it as a file, I saw it in my view at 09:50:10.) MORE tab changes its name to SLICE, MEM etc.
- Deck time goes red under 30 secs left. Good cue without any words.
- 09:50:25 Deck 1 ran out with crossfader hard on 1 and deck 2 playing. Warning, unprompted: "Deck 1 has stopped, and deck 2 is playing with the crossfader away from it. Nothing's coming out." (fu-silence-fader-on-1.png) Best moment so far. I'd left it there deliberately to see, a real newcomer wouldn't have known why it had gone quiet. MASTER moved to 2 by itself.
- 09:50:35 SLICE: tap did nothing I could see, on pads 1 and 2. A hold of 2 secs lit pad 2 and RELOOP. The tip telling you it's hold-to-play had been lost in the toast collision above. The RELOOP word goes dim on bright orange: unreadable (fu-slice-page.png is before that).
- 09:51 JUMP pad back 32: position 04:14 to 03:58: fine, labels with arrow icons clear.
- SMPL: AIR HORN, SIREN, RISER, IMPACT, LASER, CLAP, RIM, REWIND, VOLUME bar, SET, Q, STOP. Deck 2 meter doesn't respond to it? I'll check. (fu-sampler.png)
- 09:51:10 SET on sampler: "Now press the pad you want to change." Then Pad 1 sheet: AIR HORN name field, One shot / Gate / Loop, Choose a File, Grab Deck 2's Loop, Record the Master. Text underneath explains all of it. Good.
- 09:51:25 BUG?: pressed Grab Deck 2's Loop while no loop was on. Pad became "LOOP 2", air horn gone, sheet closed with no message. I don't know what it grabbed or for how long, nor how to get air horn back. (fu-grabbed-loop-no-loop.png)
- First tap on the half-height sheet again only grew the sheet: tap lost. Second time now, so that's a pattern: half-height sheets eat the first tap.
- 09:51:45 "MIX" in Browse (next to NEXT): "Mixing through all your tracks, 3 not played yet. Up next: Severe Tire Damage - High Quality." Status strip at the bottom: "Mixing through all your tracks, 3 tracks to go." (fu-mix-through.png) I'd skipped past this button for 17 minutes because "MIX" didn't tell me it was a whole-set autopilot.
- 09:51:50 MIX, 10 seconds later: Houston was finished and deck 1 started Severe Tire Damage (148), deck 2 got Fast Bird, centre button "MIX STEMS 0%". Toast again: "The stems didn't get there in time. Deck 1 just started." (fu-mix-stems-late.png) My Houston had 20s left when I pressed MIX, so a hard cut was unavoidable, but the wording sounds like a failure I caused. Note the new deck 2 opens with its fader at +0.59% (140.59) without a tempo change from me.
- Deck 2 went directly to CHORUS 1.1 without being asked. MASTER changed to 1.
- Odd: the sampler LOOP 2 pad is still lit, playing on its own for 30s behind all of this: nothing else told me a sampler pad's still running.
- 09:52:15 Waveform swipe while playing: nothing moved. No message. Tap on overview: tip "Hold the overview for a moment to jump while the deck's playing." Tip's good and it stops an accidental jump live. Stems line now says "Stems 16% . 2 min": an ETA at last, in the track's title block, but only once it has run a while (first said "Stems 0%" then "3 min").
- 09:52:25 Held overview: jumped to 05:11 with the blue label reading "CHORUS 185.4". 185 bars of chorus in an instrumental 7 min track: section labels on this one look like guesses. Then a green VERSE at 05:25.
- 09:52:40 Mixer sheet: FILTER cycle key, FILTER > DUB > SPACE > NOISE > CRUSH > PITCH. Both decks' 4th knob renamed PITCH together. (fu-pitch-knob.png) Help still calls it "FILTER KNOB" and explains filtering, not what PITCH or DUB do. "under MIXER on a phone" reads like copy written for an iPad too.
- Stems % seen in three places (title line of the deck, % bar next to AI spot, under MIX button) and the numbers disagree: Fast Bird 38% in the title, 26% on the other two at the same moment, because they mean different tracks, but nothing says which is which.
- 09:53:15 PITCH knob up on deck 1: blue arc, BPM stayed 148.00, waveform same, no numeric readout at all. Nothing visible changed except arc: can't tell what it did without ears.
- 09:53:25 Tapped MIX button in the mixer to learn what it was: "Mix off. The track playing just carries on." Instantly cancelled, no confirm. Clear wording, but this is the button I tapped in order to look at it. I'd expected a Mix status panel. To see status you must use ? mode first.
- 09:53:40 Second manual try. SYNC + play deck 2 at +5.3%. Tapped NO VOCAL before stems ready: "That happens when the split's done. It's at 39%." Lovely: pad and four little dots above STEMS show the queued state straight away, and the word "split" means stems here. Note the app has two "splits": this one and the SPLIT cue button. Both ON state meanings differ.
- Meters: mix L+R briefly touched red with two tracks at centre, LIM stayed off.
- 09:54:05 History Nov 5 in the playlist menu, made for me. Houston listed three times running: I did play it three times (load, AUTO, a restart after BRAKE), but three identical rows with no times look like a bug. Fast Bird not listed although it had been playing 30s and audible with the crossfader at 2.
- BPM creeping: with Fast Bird as master the top BPM read 148.06, then 148.10, then 148.12 with nothing touched, % moved +5.3 to +6.0. Fast Bird is "139.7" in the library but "140.59" on the deck when it loaded (at 0%). A newcomer reads that as sync not holding, or the app changing tempo by itself. May be the track's varying tempo, but no message says so.
- 09:54:40 Master BPM kept swinging with Fast Bird playing: 148.12, 149.03, 149.02, 148.07, 150.09, 148.48. About 2 BPM swing, top of screen, all within a minute. Library says 139.7. I can't tell if that's the track or a fault. Times in my notes, will check with deck on screen.
- 09:54:30 New playlist: "Warmup". Lands in it straight away, with empty state "Go to All Tracks, press and hold a track, and add it from there." Add to Playlist in hold menu, submenu has "Warmup". Worked first try.
- 09:55 Fast Bird's "Beat grid: 140.06 BPM at normal speed" at this point, but it read 140.59 at load and 139.7 in library. So one track has three BPMs, and the top reading jumps around as it plays. Then it sat still at 148.48 for 40+ secs.
- With NEXT on, the track on the master deck vanishes from the list (Fast Bird wasn't listed), no "6 of 7 showing" note. I went looking for it.
- 09:55:30 AUTO with deck 1 Gepzene (128) and deck 2 Fast Bird running at 148.48: "Echo throw next, with deck 1 cued at 128 BPM." So it tells me the technique name. "AUTO's counting down the bars." Countdown 8 BARS. I don't know what an echo throw is, and help doesn't say either until I look. Different technique from last time: it seems to choose by tempo gap.
- 09:55:40 Echo throw ran, about 15 secs from "starting" to "done". AUTO moved my crossfader from 2 to centre at the start, then "Echo throw done. Deck 1 is on. More echo throws?" Deck 2 stopped, its fader tempo reset to 140.06. (fu-auto-echo-throw.png, fu-echo-throw-done.png) Deck 1 had been cued at the song's own 128 and deck 2 running at 148, so this one is a hand-off without beat-matching. Top meter columns show it fine.
- 09:56:20 Manual search works well when you know the word: "echo throw" found a clear section called "Auto DJ's moves", "thumb" says ratings lean future choices and stay on device. Answered exactly what had confused me 12 mins earlier. "The number counts bars in the section" explains "CHORUS 185.4". "Drag to move, pinch to zoom, double-tap to reset" for the waveform.
- 09:57 Stems: SOLO row, BEAT and ALL all do what the waveform and meter say. Small dots over the STEMS tab show which parts are up from any page, which I'd never have seen without looking twice. (fu-fx-page.png) FX: 12 pads, beat length 1/2 to 3/4 by arrows, DEPTH bar, V I B D for which parts get it, OUT. Tapping V dims it, and TRANS on the pad lights. Only the ? help said V I B D meant "which parts": from looks alone they read like four more pads.
- Search "auto dj" in the manual gives filter knob, thumbs, MIX but not AUTO nor the move names. Search is literal.
- 09:58 Loop page on deck 1: IN then OUT made a loop, which snapped to 3 beats and lights EXIT and "3" between the arrows. EXIT then RELOOP is clear. Waveform drag on a stopped deck moves it; drag on a playing deck does nothing and gives no message (tried at 09:52). Pinch zooms both waveforms together, stops the moment you take fingers off.
- 09:58:30 Beat-matched by hand: deck 2 DJ Karda 129.53 via fader to 128.14 (-1.1%), played without SYNC, then nudged with the platter's edge. Bar in the strip between waveforms moved from off to the right towards the centre with each nudge. (fu-hand-beatmatch.png) That strip is really what I'd want, once explained. No labels on it. Fader is very sensitive: 1pt or so = 0.2%; a real thumb couldn't hit 128.00 exactly. Fader readout under it is 1 decimal, hub 2, title 1, and top BPM reads to 2.
- 09:58:45 SLIP + REV: position counts down, section bar count falls, and turning REV off puts the track where it'd have been (00:32.8 to 00:44.7). Exactly what I'd hoped. No help needed once ? told me.
- 09:59:05 Mixer sheet: both trims full lights LIM (and the sheet's meter copies the main one). SPLIT lights "MIXER / SPLIT" on the main screen so you can tell without opening the sheet. The text changes to "SPLIT's on: the mix in the left ear and your cue in the right": good. (fu-trims-up-lim.png)
- Getting trims back to dead centre by drag alone: not possible, still a little off. I never got the double-tap to work; my taps are too slow through this tool, so I can't say whether it does.
- Mixer sheet leaves the bottom third of the screen empty and covers the crossfader while open. The sheet is half-height so the decks stay usable; crossfader can't be reached though.
- 10:00:15 KEY column: ? explains "A is minor and B is major. The same number, or numbers next to each other, with 12 next to 1, go together. It lights up when it goes with the master deck." Lovely single sentence. It answered the pink-pill question from 09:35, 25 minutes later. Nothing on the main screen hints that it means "matches".
- 10:00:25 "DJ library (XML)..." toast: "Choose the XML your DJ software exported." then Files. Clear, doesn't say which DJ software. Picker closes with no harm when cancelled.
- Search "kevin" filters as you type by artist. Works.
- 10:00:45 Re-analyse Exhilarate: "Analysing Exhilarate again." BPM/KEY dots, then back.
- 10:00:30 Delete from Library: "This removes it from Segue DJ, with its cues, loops and stems. A file you picked in Files stays there." Perfect. Cancelled.
- 10:00:40 Second MIX, from the list with one unplayed track left: "Mixing through all your tracks, 1 not played yet. Up next: Exhilarate." Tells me the ticks mean "played" (the only place the app says so). Only unplayed tracks go, so my session's ticks limit the mix. I didn't know until now; no way to clear the ticks seen so far.
- 10:01:30 MIX waits on Exhilarate's stems: button "MIX / STEMS 48%", title "Stems 48% . 30 s". Waveform setting RGB takes effect instantly. Exhilarate opens with 3-4 secs of flat line that the app labels "CHORUS 1.1", with no CUE point set to the first beat (playhead at 00:00.0 with nothing to hear yet: first sound off to the right).
- 10:01:40 ? on tempo fader: "down is faster, as on a club deck. It clicks at the centre, the track's own speed, and a deck stays at a synced speed until you double-tap for that. Slide sideways for finer control." So my 09:48 complaint is answered, but I only read it after 13 minutes of guessing, and sideways fine control isn't hinted anywhere on the fader.
- 10:01:30 Mix is on Exhilarate (170 BPM) from DJ Karda (128 BPM): no message saying a transition is on its way this time, only MIX / "22 BARS" counting down, and it cued Exhilarate 3 secs in (00:02.8) on its own: it skipped the flat bit that I'd worried about. REC running while I watch.
- 10:01:50 In ? mode "MIX" says "It says what it's counting or waiting for". On the button it reads only "13 BARS": it doesn't say what's coming at the end. The deck 2 fourth knob changed from PITCH (which I'd set) to FILTER at 10:02:11 on its own, deck 1's stayed PITCH, without a word. (fu-mix-loop-into-170.png)
- 10:02:15 "Loop build into Exhilarate." Exhilarate is at 170, DJ Karda at 128.14; I'm watching to see how it handles a 42 BPM gap, deck 1 hasn't changed its BPM.
- 10:02:35 Grabbed FILTER mid-move. Toast: "That's yours for this move. The mix carries on with the rest." (fu-thats-yours.png) Exactly right. The moment a newcomer is scared of breaking it, it says it's fine. Bass pad filling down at the same time.
- 10:02:45 "Loop build done. Deck 1 is on." BUT numbers show no beat matching took place: deck 1 at 170.00 running alongside deck 2 at 128.14 from 10:02:40 to 10:02:50 (position 00:01 to 00:10.7). Deck 1 hadn't moved its tempo at all, SYNC off. Earlier AUTO on a small gap pulled the new deck's tempo to match. On this big gap the app said nothing about tempo and the same "Loop build" name. I can only report what the numbers showed. (fu-mix-deck1-started.png, fu-mix-done-170.png)
- 10:02:42 Deck 1's position stepped BACK from 00:02.8 to 00:01.1 just before it started (with a green-ringed play icon): I think it's a run-up so that it lands on the beat. Nothing says so. Looked like a glitch.
- At the end of the move, the FILTER knob I'd said was "mine" snapped back to centre, and the label returned to PITCH on deck 2. A move resets a control I'd taken over: fair, but unannounced.
- Second thumbs test: thumbs down, same as thumbs up: banner goes without any acknowledgement.
- CORRECTION to my thumbs-down note: by the time I tapped (20 secs later) the banner had gone by itself, so that tap hit the waveform and I learned nothing about thumbs down. The banner timing out while I read is itself a small point: the question disappears.
- 10:03:40 After MIX's last move: MIX button stays lit with nothing left to do, deck 2 left stopped at 04:05.5, 31 secs of its track unplayed, cued where the move ended. Sensible, but the button's still "on". "MIX" through a list with the one remaining track behaved as a single transition.
- 10:04 Second recording's tracklist has both tracks with times and BPM (Karda at 128.1, which is my adjusted speed, not its own 129.5, and "Kevin MacLeod - Exhilarate" 01:31). Top bar's "1"/"2" is the track count. (fu-recording-second-tracklist.png)
- 10:04:10 SYNC with a huge tempo gap: "Deck 2 is now 31% faster than its own 130 BPM, to follow." + UNDO. (fu-sync-31-percent.png) Honest and undoable. It took the app 31% rather than half-speed, which a DJ might have wanted, but a beginner gets told exactly what happened. Remaining time on deck 2 shortens (31.8 to 24.1) as it should. "to follow" is slightly odd English.
- 10:04:35 Tapped column BPM to sort, arrow appears, TITLE/KEY columns work the same. Status bar says "This is the last track." Loading Gepzene on deck 2 myself while MIX runs: "Up next: Gepzene - Can't be Serious. The mix carries on." and "1 track to go". Very good. I feel in charge and it follows.
- NEXT said DJ Karda (129.5) was the best follow for Exhilarate (170), above Severe Tire (148), although the ? help said tempo counts for more than key. Odd ordering to me.
- Toast over the BROWSE column heading: text in the toast mixes with "TITLE" and "BPM" as they show through it for its fade.
- 10:05 Fourth Auto move watched: "Echo throw into Gepzene" at the tail of Exhilarate (170 into 128). Deck 2 started 1.5 s back from its cued spot with its waveform dark and pads dim, then pads and waveform lit together as deck 1 went quiet. Then "Echo throw done. Deck 2 is on. More echo throws?" (No tempo match; both decks stayed at own BPMs.)
- 10:05:20 CORRECTION: thumbs down gives "Got it. Less like that." (fu-thumbs-down-got-it.png) So my 09:44:40 note ("no confirmation") was wrong or the toast passed between my taps and my next look. The wording is good. Still doesn't tell me what's being rated: the move or the pair.
- 10:05:50 Stopped both decks. Warning row vanishes, play goes from grey to white. Plays with a progress slider, can drag to 1:52. Time runs up. Good. REC's playback warning explained itself by going away. Share took about 7 secs from tap to sheet, no spinner (might be the simulator). Sheet reads "Plain Text and 2 Documents, 4.5 MB": I shared one mix, what are the 3 things? (fu-share-sheet.png) Didn't send anything.
- 10:06:40 Reloaded Houston: comes up at 03:20, my memory cue, with hot cue A 2:56 ready, on the other deck too. It did what the 09:50 toast promised. A good first-session surprise.
- I don't know whether the recording that I left playing when closing Recordings kept going: meters at rest, no sign on deck screen. (10:06:10)
- 10:07:20 Hand stems swap: Gepzene NO VOCAL + Houston ACAPELLA: waveforms show only what's left, pad colours and the row of dots agree. The "one voice over another track's music" idea that I'd want to try worked first time. (fu-stem-swap-manual.png) I can only say it looked right.
- 10:07:30 Add the same file twice: Exhilarate again gives "That track's already in your library." Good. Files picker: the Segue DJ folder rose from 2 to 4 items: that's my recordings, I assume; a real user may find that's where to get them. The picker sheet slides off in two stages, taking 2 secs. A top-of-screen filename check: my files are jam1051513 etc., and the app displayed proper titles: nice.
- 10:08:30 Memory page LIST: "Houston": Hot cues (A) with name field, time, colour dot; Memory cues with name. Name and colour-change work (palette of 8), simple. There's no way to reach this from hot cue page; only from under MEM. Tapping into a Name while the sheet's still sliding up loses your typing silently ("Drop" went nowhere, 10:08:05, may be just my slow tool).
- Deck 2's parts stayed at VOCAL only after I'd moved to MEM page: decks look dark on the waveform, four tiny dots above STEMS are all that says why.
- 10:08:40 Deck 1 fader down, AUTO with both playing: "Auto DJ brings in a stopped deck. Stop the one you want next." Clear. Stopped deck 1 and pressed AUTO. Old toast and new toast drawn one over the other for a moment, again. (fu-auto-fader-down.png is about then)
- 10:09:00 "Moved deck 1's fader up, to hear both." (fu-moved-fader-up.png) Deck 1 was still at Hot cue with its CHORUS 1.1 waveform on 1 BAR countdown. It told me what it did to a control that I'd left down. I'd never have thought of it; great.
- 10:09:25 AUTO cancelled mid-move: "Auto DJ stopped. The decks are yours. Deck 2 is still looping." (fu-auto-stopped-midway.png) It put back everything it had changed: deck 1's fader down at the bottom where I'd left it, SYNC on, position 03:09 where I'd stopped it. Very tidy. But deck 2's 4th knob stays labelled FILTER, slightly up, while deck 1's says PITCH, so the two 4th knobs now disagree, and the toast's "Deck 2 is still looping" doesn't say how to end the loop or show EXIT on this page (I was on STEMS).
- 10:10:30 Pad settings again: since I'd replaced it, "Restore the Original Sound" has now appeared, so air horn's not lost. Good, and it explains: "A grabbed loop comes out as you're hearing it, so with the vocal muted it has no vocal. Samples can be up to a minute long, and recordings stop at 30 seconds. One shot plays to its end, Gate while you hold the pad, and Loop until you press it again." Answers most of the sampler in one paragraph. Grab with no loop going still worked (I don't know what it took) and silently changed mode to Loop.
- CORRECTION: 09:52 note that LOOP 2 was "still lit, playing": it had been, and STOP or a tap ends it. (Colour fades when it's off.) STOP is only on this page: a looping sample from deck 1's page can't be stopped from deck 2's page without opening SMPL there.
- 10:10:20 Record the Master: SET key becomes red timer, pressing it finishes. "Pad 1 has your recording. SET and then the pad can restore its original sound." Pad now REC 1 (fu-pad-recording.png). Clear all the way.
- 10:10:25 Gepzene finished. Deck 1 (stopped, but synced) quietly dropped SYNC and went back from 128 to 126. MASTER 2 and 128.00 remain lit though deck 2 is stopped and finished. No message. Small. Did I lose anything? Not clear.
- 10:10:55 Halve the Reading on 170 Exhilarate: "Deck 2's track reads 85 BPM now. Its speed hasn't changed." That's a sentence that heads off exactly the fear I'd have. Whoever writes these toasts knows what newcomers think. (But "Double the Reading" as a label wouldn't mean anything to me until I'd seen this.)
- 10:11 SYNC on 85-reading deck against 126: "Deck 2 follows at half tempo: 63 against 126." with UNDO. UNDO puts back 85. Compared with the earlier "31% faster", this is how to get half-time. Reading is reversible with Double. So 170-reading vs 126 is +31% unless you know this trick: reasonable, but a newcomer couldn't guess it. Only found out because I was poking.
- 10:12 ? on MASTER: "A stopped deck can't lead, so the first one to start playing takes over." Yet I pressed MASTER on stopped deck 2 and it lit orange and top bar read MASTER 2 170.00, with both decks stopped. Small contradiction. Also, ? on Q and ±6 ±10 ±16 WIDE both clear. ± is sticky across a load? Not sure. SLIP, Q, KEY stayed lit on the Jog page when I loaded a new track on that deck, and BPM 170.00 reset the fader so I assume only tempo resets.
- Slide-sideways fine control on the tempo fader works: about half the sensitivity. Only known from the ? text.
- 10:12:30 Playlists: blue menu button tells me I'm in a playlist but no name appears anywhere on screen: only by reopening the menu. Hold row gets Remove from Playlist and Change the Order. Rename and Delete in the menu only when a playlist is open.
- Fast Bird in the library now 140.1, it had been 139.7 at 09:40: the library value changed after the track had played. No notice.
- 10:12:45 Silence with no warning: AUTO stop had left deck 1's channel fader at the bottom (where I'd put it). I loaded DJ Karda on deck 1, pressed play: deck plays, its own meter moves, mix L+R columns stay empty, so nothing is coming out: 15+ secs and no message. (fu-playing-fader-down-no-warning.png) Compare with the crossfader case at 09:50, which gets a clear warning. Same symptom, a newcomer would be just as lost, and this is the more likely one after loading a fresh track.
- Also, "Play a track first, then Auto DJ can mix out of it." if both decks are stopped: clear.
- 10:13:40 Second reading of Settings: every section ends with a line of plain English. "Keys click, knobs and faders have detents" again uses "keys" for buttons. Backup footer's warning about losing the Backups folder when deleting the app is honest, useful.
- 10:13:10 Accident: tapped REV where I'd meant play (REV lit red on a stopped deck, position moved 00:00.2 to 00:00.3). Harmless.
- 10:13:55 Pressed MIX with every track ticked and deck 2 playing: "Everything else here has been played. To go round again, stop the deck and press MIX." Clear rule, but it does tell me the ticks limit MIX, and "stop the deck" means silence, which is an odd thing to ask of a DJ. In NEXT list the track I'd just stopped sits at the top with a matching 1B pill, as the "good one to play", though I'd just heard it.
- 10:14:10 Stopped, then MIX: "Mixing through all your tracks, 6 tracks to go. Up next: DJ Karda - Alone." It restarted deck 2 from my stop? No: the next-loaded track carried on playing on deck 2. So a tap on MIX gave "6 to go" though the toast seconds earlier said "stop the deck" first, and in that gap deck 2 kept playing because my play tap on deck 2 had toggled it on and off: my taps were out of step. Button goes to a square (stop) icon while running.
- MIX also quietly reset deck 2's channel fader, the FILTER knob, and the crossfader to centre. "55 BARS". It does tidy up. It doesn't say so.
- 10:14:25 Held CUE on deck 1 with MIX running: "Mix off: you started deck 1 yourself." Fair. It lets a long CUE hold preview and snaps back on release, but it quit a 6-track mix for a preview. No undo, no confirm, and the toast reads like blame.
- 10:14:40 Tapped CUE on playing deck 2: instantly stopped and returned to INTRO 1.1. Normal club-deck behaviour, but a stray touch beside a green PAUSE button stops the music in the middle of a set with no undo. (Big button right above PLAY.)
- 10:15 Manual on the waveform: "Drag to move, pinch to zoom, double-tap to reset it." Doesn't say that dragging only works when stopped. "UP's a build-up, DOWN a breakdown" explains labels I'd been guessing at for 40 minutes. Search "noise" only gets "FILTER ...chooses what both FILTER knobs do: FILTER, DUB (echo), SPACE (reverb), NOISE, CRUSH or PITCH": NOISE, CRUSH and PITCH aren't explained, and says "both" although the two knobs disagreed at 10:02 and 10:09.
- 10:16:20 Fifth Auto move, Karda (129.53, 1B) into Gepzene (128 pushed to 129.53, 1A): "Loop build next, with deck 2 cued at 130 BPM." During it deck 1's fourth knob quietly relabels from PITCH to FILTER and turns; LOW sinks; dots over STEMS drop blue. Readable once you know what you're looking at. (fu-auto-filter-relabel.png)
- 10:16:50 Recording ... menu: Rename and Delete, Rename field pre-filled and works; cancelled. Beat-jump number on the jog page taps through sizes (4 to 8).
- CORRECTION: fu-auto-filter-relabel.png was taken about 8 secs too late. It shows "Loop build done", not the relabelled knob. I saw the relabel in my own view at 10:16:20.
- 10:18:35 Started deck 1 by hand with deck 2 playing, same BPM, no SYNC: strip's marker sits amber, off centre. Pressed SYNC: marker jumps to centre and goes green, blue blocks mirror. So SYNC lines up the beats as well as the tempo, and the strip shows it. A tidy way to learn what the strip means if you watch it at that moment. Both decks at full with centre crossfader: mix L+R touches red, LIM stays off. (fu-end-of-session.png)
- 10:18:50 Held FX ROLL for 2 secs on synced deck 1: the strip marker sat amber, right of centre, at 10:18:51 and was back green and centred by 10:18:57. LIM lit red at 10:18:57 with both decks full in a chorus. fu-synced-marker-off-centre.png was taken too late, so despite its name it shows the marker back in the centre.

---

# THE REPORT

The five sections you asked for start here. Everything above this line is my raw log in time order, and where the log and this section disagree, this section is the corrected one.

**How to read the times.** Clock times come from `date`, checked every minute or so. Treat anything to the second as give or take 20 seconds. A few log entries were stamped slightly ahead of the real clock (the ones stamped 10:00:45, 10:01:30 and 10:13:40 were written at 10:00:21, 10:01:10 and 10:13:29). My taps land about 1 to 3 seconds apart and I only see the screen when I ask for it, so a message I "didn't see" may simply have come and gone. I can't hear anything: every "worked" below means I saw it in numbers, waveforms or meters.

**Corrections to the log**
- 09:44:40, "thumbs up gives no confirmation": probably wrong. Thumbs down at 10:05:20 said "Got it. Less like that." (fu-thumbs-down-got-it.png). I never caught a thumbs-up message, but it may have gone before I looked.
- 09:46:25, Gepzene's start labelled CHORUS 1.1: unconfirmed. At 10:12:22 the same track read INTRO 1.1. Either the label changed or I misread it. fu-gepzene-chorus-label.png was never taken. Exhilarate's flat opening labelled CHORUS 1.1 at 10:10:50 is firm.
- 09:50:00, "time goes red under 30 seconds": I only saw red at 26 seconds and below. The exact point is a guess.
- 09:52:05, sampler pad running with nothing telling me: it was playing, and I learned STOP lives on the SMPL page only.
- 10:14:10: my entry is muddled. What happened: MIX refused while deck 2 was playing, I stopped deck 2, pressed MIX, and it restarted deck 2 from where I'd stopped it, put DJ Karda on deck 1 as next, and reset deck 2's fader, its fourth knob and the crossfader. I saw no message about those resets, but I was on the Browse screen when it happened.

## 1. Every moment I wasn't sure what to do

| When | What I wanted | What I tried first | What happened | How long | Screenshot |
|---|---|---|---|---|---|
| 09:34:30 | Get music in | The highlighted button the empty screen pointed at | Two choices, "Music files..." was obvious. The Files sheet opened empty, then jumped to On My iPhone by itself | No doubt, about 35 s including picking 7 files one at a time | fu-no-music-yet, fu-files-picker |
| 09:35:14 | Load a track | Tapped the row | Tip: "Press 1 or 2 to load this, or hold the row for more." | 6 s | none (tip gone) |
| 09:35:20 | See the deck I'd loaded | Looked for it after pressing 1 | Only the title colour and top bar changed. Found DECKS top left | 5 s | fu-added-7-tracks, fu-decks-first-look |
| 09:35:20 | Why one KEY value is a filled pink pill | Guessed "same key" | Not explained until ? on KEY at 10:00:15 | 25 min, on and off | fu-added-7-tracks |
| 09:36:26 | Put a knob back to the middle after turning it | Dragged it back | Lands near the middle, not on it. Manual says double-tap, which I can't do at tool speed | Never settled | fu-crossfaded-to-2 |
| 09:36:50 | Why a meter stays high with the crossfader fully over | Stared at four unlabelled columns | ? explained: deck 1, mix L and R, deck 2 | About 1 min | fu-crossfaded-to-2, fu-help-mode |
| 09:37:48 | What the waveform icon by BROWSE is | Assumed a display option | It's Recordings. ? told me; I opened it at 09:47 | 10 s to learn | fu-help-mode, fu-recordings |
| 09:38:00 | Change tempo by hand | Looked on the deck for a fader | Only on the page behind JOG/TEMPO. Found through ? mode | About 4 min from first wanting it | fu-jog-page |
| 09:38:40 | Find the rest of the pads | Tapped MORE | Tab renames itself MEM, SLICE, JUMP, SMPL as you tap, so MORE vanishes. Took four taps to see the pattern | 30 s | fu-mem-page, fu-slice-page, fu-sampler |
| 09:40:50 | One-press transition | AUTO on a just-loaded track, under 2 min left on the other | Waited for stems, then "The stems didn't get there in time. Deck 1 just started." No transition. Understood why at once, not how long stems take | 75 s wasted | fu-auto-pressed, fu-auto-stems-not-in-time |
| 09:42:10 | Why the new track had no bass | Looked at the deck, found my own LOW still down from earlier | Nothing resets or warns on load | Noticed in 10 s, only because I was looking | fu-auto-stems-not-in-time |
| 09:44:40 | What the thumbs do | Read "More loop builds?" as an offer to do another, so pressed thumbs up | Banner went. Manual explained at 09:56: ratings lean later choices | 12 min | fu-auto-done |
| 09:46:10 | What the number by the REC time means | Guessed seconds or takes | ? says tracks so far | 30 s | fu-recording-tracklist |
| 09:48:30 | Slow a track down | Pushed the tempo fader up | Up is slower. Help explains this ("down is faster, as on a club deck"), but I read that at 10:01 | One drag to see it, 13 min to have it explained | fu-bpm-menu (nearby) |
| 09:49:00 | Whether minus works on the key shift | Pressed minus, then KEY SYNC | KEY SYNC quietly undid the minus, no message and nothing lit, so it looked like minus was broken | 60 s | none: nothing visible, which is the problem |
| 09:50:35 | Make SLICE pads do something | Tapped them | Nothing. They need holding. The hint was lost in a message overlap | 30 s | fu-slice-page |
| 09:51:25 | Pick a different sample | Pressed "Grab Deck 2's Loop" with no loop on | Air horn replaced by LOOP 2, mode changed to Loop, sheet closed, no message. "Restore the Original Sound" only appears after you've replaced it; I found it at 10:09:50 | 18 min believing the air horn was gone | fu-grabbed-loop-no-loop |
| 09:51:45 | What MIX in Browse does | Ignored it for 17 min, then pressed it | Plays through the whole library. Name gave no hint | 17 min before trying | fu-mix-through, fu-mix-stems-late |
| 09:52:15 | Move along a playing track | Dragged the waveform | Nothing and no message. Overview tap got a tip saying to hold | 20 s | none |
| 09:52:40 | What DUB, NOISE, CRUSH and PITCH do on the fourth knob | Turned PITCH, read ?, searched the manual | Names only. PITCH moved no number I could see | Never settled | fu-pitch-knob |
| 09:53:25 | Read what the MIX button in the mixer is showing | Tapped it | It cancelled the mix ("Mix off") with no check. Should have used ? first | 5 s, cost me the mix | none |
| 09:54:30 | Which playlist I'm in | Looked for a name | None on screen, only a blue button. Reopen the menu to see the tick | 15 s | fu-history-houston-3x |
| 09:55:30 | What an "echo throw" is | Watched it, then searched the manual | Manual explains it well once you know to search | 50 s | fu-auto-echo-throw, fu-echo-throw-done |
| 10:04:10 | Sync a 130 track to a 170 one sensibly | Pressed SYNC | "31% faster than its own 130 BPM". Half-time needs "Halve the Reading" in a menu behind a tiny arrow; found by chance | 7 min between needing it and connecting the two | fu-sync-31-percent, fu-bpm-menu |
| 10:12:45 | Why nothing's coming out | Looked at the meters | Deck 1's own meter moves, mix columns empty: channel fader at the bottom. No warning, unlike the crossfader case | 20 s for me; a newcomer could stay stuck | fu-playing-fader-down-no-warning |
| 10:13:55 | Run MIX again | Pressed MIX | "Everything else here has been played. To go round again, stop the deck and press MIX." Clear, but stopping means silence | 15 s | none |
| 10:14:25 | Preview with a long press on CUE | Held CUE while MIX ran | "Mix off: you started deck 1 yourself." A preview ended the whole mix | Instant, no undo | none |

**Help, as I used it**
- **? mode (09:37, used all session):** explained nearly every control in a sentence or two while the music played on and nothing changed. It covered meters, beat strip, KEY colours, tempo fader direction, MASTER. It was less use on the fourth knob's modes, and its box hides whatever is under it.
- **"What everything does" (Settings, found 09:41):** a searchable manual with "Start here", and it answered things ? didn't (thumbs, Auto DJ's moves, UP and DOWN section labels). I'd never have looked in Settings without being asked to explore. Search is literal: "knob" missed HI, MID and LOW, and "auto dj" missed AUTO itself.
- **Unprompted tips:** the ones that came at the right moment taught me most, above all "Two basslines clash. Turn the new track's LOW down, and swap the two LOWs as you crossfade."

## 2. How long each stage took, from opening

| Stage | Clock | From opening |
|---|---|---|
| App opened | 09:34:21 | 0:00 |
| "No music yet" on screen | 09:34:27 | 0:06 |
| Music in ("Added 7 tracks") | 09:35:05 | 0:44 |
| First track on a deck | 09:35:20 | 0:59 |
| First sound (timer, waveform and meters moving) | 09:35:32 | 1:11 |
| Two tracks playing together | 09:36:10 | 1:49 |
| First move from one to the other, started | 09:36:26 | 2:05 |
| First move, finished (crossfader over, EQ swapped) | 09:36:50 | 2:29 |
| First use of ? | 09:37:05 | 2:44 |
| First stems ready (Houston, loaded 09:35:20) | 09:39:25 at the latest | 5:04 |
| First AUTO pressed | 09:40:50 | 6:29 |
| Found the manual | 09:41:10 | 6:49 |
| First AUTO gave up | 09:42:06 | 7:45 |
| First AUTO transition that ran, start to finish | 09:43:00 to 09:44:30 | 8:39 to 10:09 |
| First effect | 09:45:15 | 10:54 |
| First recording saved | 09:47:20 | 12:59 |
| First MIX | 09:51:45 | 17:24 |
| First beat-match by hand, no SYNC | 09:58:30 | 24:09 |
| First hand-made vocal over another track's music | 10:07:00 | 32:39 |

The 2:05 to the first move is flattering. I went straight for EQ and crossfader because I know what they're for, and the bass tip appeared at the perfect time. A real newcomer would take longer. Stems times are on a simulator and may not match a phone: DJ Karda took about 2 min from load (09:40:50 to 09:42:45), and Exhilarate about 1 min after MIX loaded it (10:00:38 to about 10:01:30).

## 3. What I still can't explain, and wording

**Still can't explain**
- What NOISE, CRUSH and PITCH on the fourth knob do. PITCH changed no BPM or key number I could see.
- Why Fast Bird's numbers moved. Library 139.7, 140.59 at load, grid 140.06, library later 140.1. The master readout wandered 148.06 to 150.09 while it played synced, nothing touched.
- How NEXT orders tracks. At 09:40 it gave 128, 129.5, 170, 148, 139.7, which looks odd against the help's "tempo counts for more than key". At 10:04 it put 129.5 above 148 after a 170 track.
- How AUTO picks a move. I saw loop builds on tempo gaps of 1 to 3% and echo throws on bigger ones (148 into 128, 170 into 128), but MIX called a 128 into 170 a loop build too.
- What thumbs rate: the move, the pair of tracks, or both.
- What "Grab Deck 2's Loop" captured with no loop running.
- Why the Share sheet says "Plain Text and 2 Documents" for one mix (fu-share-sheet).
- Whether a recording I left playing kept going after closing Recordings at 10:06:10.
- What was in the Segue DJ folder in Files before I'd made anything (2 items, 4 by 10:07).
- Why deck 1's position stepped back just before Auto started it (00:02.8 to 00:01.1, 10:02:42). I assume a run-up. It looked like a glitch.

**Wrong, misleading or no help**
- **"key" meaning button.** "Only keys that move between pages still work", "The key with the arrows", "Keys click". KEY is also a labelled button and a musical key on the same screen.
- **"CUE" means two things:** the big CUE button, and "you'll hear the cue" for the headphones.
- **"split" means two things:** "That happens when the split's done" (stems) and the SPLIT button.
- **"The stems didn't get there in time."** Sounds like something broke. It doesn't say the track was cut rather than mixed, or how long stems take.
- **"Mix off: you started deck 1 yourself."** Reads as blame, and doesn't say how to resume.
- **"More loop builds?"** Reads as an offer, not a rating.
- **"It's taken over deck 1's EQ."** Honest, but I couldn't see what that meant until knobs moved 50 s later.
- **"Deck 2 is now 31% faster than its own 130 BPM, to follow."** "To follow" is awkward, and it doesn't mention half-time.
- **MORE >** stops saying MORE after one tap.
- **"Double the Reading" and "Halve the Reading":** meaningless until the toast explains. The menu also mixes title and sentence case.
- **Fourth knob:** manual says "both FILTER knobs", but the two showed different modes at 10:02:11 and 10:09:25. ? still calls it FILTER KNOB when it says PITCH.
- **Waveform help:** "Drag to move" doesn't say stopped decks only.
- **MASTER help:** "A stopped deck can't lead", yet MASTER lit on stopped deck 2 and the top bar followed (10:11:40).
- **Section labels:** a flat, silent opening labelled CHORUS 1.1 (Exhilarate, 10:10:50), and CHORUS 185.4 on an instrumental (Fast Bird, 09:52:25). They look like guesses.
- **Key arithmetic:** +1 turns 5A into 12A. Correct on the wheel, random-looking to anyone who doesn't know it.

## 4. Anything that looked broken

No crashes in the whole session, and I never had to restart.

| Time | What | Screenshot |
|---|---|---|
| 09:34:40 | Files sheet opens empty, then moves itself to On My iPhone. May be the system | fu-files-picker |
| 09:40:15 | NEXT list reshuffled under my finger when the master track ended | none |
| 09:42:06 | AUTO gave up, crossfader jumped to centre by itself | fu-auto-stems-not-in-time |
| 09:47:30, 09:51:25 | First tap on a half-height sheet only grew the sheet, tap lost. Could be my timing | fu-recordings |
| 09:50:10, 10:08:40 | Two messages drawn on top of each other for about a second, unreadable. Happens when pressing something new as one fades | fu-auto-fader-down (about then) |
| 09:51:00 | RELOOP text dim on bright orange, unreadable while lit | none |
| 09:51:25 | Grab loop with no loop running silently replaced a sample | fu-grabbed-loop-no-loop |
| 09:54:00 to 09:55:20 | Master readout wandered 148.06, 148.12, 149.03, 149.02, 148.07, 150.09, 148.48 on a synced Fast Bird with nothing touched. Then held 148.48 for 40 s | none |
| 09:54:05 | History lists Houston 3 times with no times, and Fast Bird not at all though it had been playing 30 s | fu-history-houston-3x |
| 10:02:11, 10:09:25 | The two fourth knobs show different modes (FILTER and PITCH) | fu-mix-loop-into-170, fu-auto-stopped-midway |
| 10:02:40 to 10:02:50 | "Loop build into Exhilarate": deck 1 at 170.00 and deck 2 at 128.14 playing together, neither tempo moved, then "Loop build done". An earlier Auto with a small gap had pulled the tempo to match. I can't say how it sounded | fu-mix-deck1-started, fu-mix-done-170 |
| 10:03:40 | MIX stayed lit with nothing left to do | none |
| 10:05:50 | Share took about 7 s from tap to sheet, no spinner. May be the simulator | fu-share-sheet |
| 10:08:05 | "Drop", typed into a cue name just after the list opened, went nowhere with no message. May be my timing | none |
| 10:10:25 | When deck 2 finished, stopped deck 1 dropped SYNC and went from 128 to 126, no message. MASTER stayed on the finished deck until I loaded another track | fu-pad-recording |
| 10:11:40 | MASTER lit on a stopped deck against its own help text | none |
| 10:12:45 | Deck playing, fader down, silence, no warning | fu-playing-fader-down-no-warning |
| 10:18:51 | After a 2 s FX ROLL on a synced deck, the beat strip showed amber off centre, green again by 10:18:57. May be normal | fu-synced-marker-off-centre (too late, shows it recovered) |

## 5. Best and worst for a newcomer

**Best:** it explains itself at the moment you need it, in plain English, without stopping the music. ? mode is the core of it, and the unprompted lines are better still: the bass tip, "Deck 1 has stopped, and deck 2 is playing with the crossfader away from it. Nothing's coming out." (09:50:25), and "That's yours for this move. The mix carries on with the rest." (10:02:35). I went from nothing to a clean-looking transition in about 2.5 minutes without a tutorial. Watching AUTO turn the knobs was also a good free lesson.

**Worst:** the first try at both one-press features ended in a hard cut. AUTO at 09:40:50 and MIX at 09:51:45 both gave "The stems didn't get there in time", because the stems weren't ready and nothing warns you beforehand how long that takes. Pressing it near the end of a track, on something just loaded, is exactly what a newcomer does. Close second: the fader-down silence at 10:12:45, the one silent-output case with no warning, and just the kind of thing a beginner leaves behind them.

## 6. What I can't un-know

- **DJ knowledge.** The brief says I know roughly what a DJ does, but I actually know a lot: EQ swaps, beat-matching, hot cues, slip, quantize, stems, why a club fader goes down for faster, and the key wheel. So the pink pill, 5A going to 12A and "bass swap" cost me less than they'd cost a real newcomer. Treat my times as the fastest case.
- **Session setup text.** Before opening the app, my session details listed working folders named `cheeks-autodj` and `cheeks-stems`, plus a project folder called Cheeks. I never opened them, but I half expected an auto DJ and stems. I also saw the bundle ID in the launch command.
- **The brief.** It told me help might exist, so I went looking at 2:44. It told me to work through 45 minutes, so I toured ? mode methodically and deliberately poked edge cases (fader down, grab with no loop, AUTO with nothing to mix) that a casual user might not.
- **The app's own names I now use:** Auto DJ, MIX, stems, memory cue, loop build, echo throw. None of those did I bring with me except stems, memory cue and loop.

**What I left changed on the phone:** 7 tracks imported, two recordings, a playlist "Warmup" holding Severe Tire Damage, hot cue A and a memory cue on Houston, hot cue renamed "Big bit" (I didn't check it stuck), Pad 1 replaced with REC 1, waveform colours set to RGB, some thumbs ratings, Exhilarate re-analysed once. Both decks ran to their ends and sit stopped at 00:00.0 (fu-both-decks-ran-out.png, 10:20:47: silence with no message, and MASTER 2 and 129.53 still showing). The app is still open. I didn't send or share anything.

**Session times:** opened 09:34:21, last look at the app 10:20:47. My last touch on the screen was 10:18:50, then I wrote this report while the two tracks ran out, and looked again at the end.

---

## What happened next

### Fixed
- **`N37`, sliding from a hold takes a row out of a playlist: it says so, with `UNDO`.** "Took Houston out of Friday." `UNDO` puts it back where it was. The slide itself is iOS's own, so it can still happen, and now it can be seen and taken back. `testAPlaylistsRowsCanBeDraggedIntoAnotherOrder` goes through it on the phone.
- **`GC4`, the failure: there's no message any more, and no lift.** You were right that nothing was ever asked about a drop on the list. On a phone a row doesn't lift in any list now, as the browser covers the decks and there's nowhere to drop one. Holding opens the menu, and that has `Change the Order`. On the full layout a row still lifts, to go on a deck.
- **`N38`, a deck playing with its fader down: it says so.** Two seconds in, "Deck 1 is playing with its fader down. Nothing's coming out." Once, and not with its headphone `CUE` lit, as someone cueing a track means to. The crossfader gets the same.
- **`N39`, holding `CUE` on the waiting deck: it's a preview, and the mix carries on.** I made the call: it goes back when you let go, so nothing's been started. If you're still holding it a bar before the move needs the deck, the preview's over. `PLAY` during the hold is still starting it, and ends the mix as before.
- **`N40`, `EXIT` just after a move:** with the question up it just buzzes, as `AUTO` does, and the question stays.
- **`N41`, grey on orange: a key goes dark at once, with its word.** It only fades lighting up now. Please look again on video, as I've gone by your frames.
- **Two messages on top of each other:** one on its way out now goes in 0.12 s, not 0.4 s or more, so what's arriving can be read.
- **A control touched during the count:** "That's yours for this move." now comes from when there's a plan, not only from when it starts.
- **"It's taken over" with things still lit:** it says "It takes over deck 2's SYNC, EQ and stems, and deck 1's effects."
- **The playlist's name upright:** the search field says "Search Friday".
- **`Grab Deck 2's Loop` with no word:** "Pad 3 plays deck 2's loop now. This sheet can bring back the original sound."
- **`KEY SYNC` with no word:** it says what it did, including when that's undoing a shift, and why it couldn't.
- **The crossfader moving when a next track just starts:** "...Deck 2 just started, with the crossfader moved to the middle."
- **Notes:** `MASTER` said a stopped deck can't lead, and a paused one does. `NEXT` says tempos within reach come first, then key, and that what's on a deck goes last. "Key" for a button has gone from the two notes that had it.
- **The words under `AUTO`:** 6 pt, and 4 at the very least.

### What the first-time user said, and what I did
- **Their worst thing, the first `AUTO` and first `MIX` both ending in a cut:** as soon as it can tell, it says "The stems need 2 min, and this track has 40 s left. Deck 2 will just start at the end, with no move." That takes about 5 s, as it needs to see them moving. And "The stems didn't get there in time" sounded broken, so it's "The stems weren't ready in time, so there's no move."
- **Everything played, and having to stop the music to go on:** `MIX` goes round again. "You've played all of Friday, so this goes round again, 4 tracks to go."
- **Wanting to go now:** see below.
- **"Who's in charge":** it's gone as the worst thing, so I've only made the changes above.

### New, from me
- **A freeze I put in last round, which you had no way to see.** Every time the browser opened or closed, it built all 2,000 rows: about 200 ms frozen each way, and 70 MB more memory, in c577553, the commit you tested. `LiftsIfItCan`, a modifier of my own on each row, stopped the list being able to tell a row's one row without building it. The old commit showed 50 to 100 ms. Now it's nothing at 50 ms or more, in all but one of the opens and closes I measured, memory's 67 MB at rest and 164 MB playing, from 127 and 238, and CPU in the browser's 12%, from 20%. `testTheListOnlyBuildsTheRowsShowing` fails without the fix, with 1,002 rows built, and `tools/self-tour.sh` is now in my gate. Nothing in the suite had noticed.
- **Saving's off the main thread.** All 2,000 tracks were written out on it after every change, 34 ms on a Mac, and a pretty-printed backup every 5 minutes. `saveNow` still waits, for going to the background.
- **`GO NOW`.** While a move's more than 24 bars off, or a mix has given up on one, a key under `MIXER` on a phone, under `AUTO` on the full layout, and on the mix's line in the browser. It looks for a way in over the next 16 bars or so. What it's counting down to stays until it finds one, so finding nothing costs nothing.
- **`Choose Several`.** Hold a row, tap the ones you want, searching between them if you like, and `ADD TO` a playlist, with `UNDO`.

### The Loop build between 128 and 170 where neither tempo moves
That's as designed: too far apart to stretch, so the new track lands at its own tempo with a beat of air between them. You and the first-time user are right that it's worth an ear, so it's in `docs/TEST_PLAN.md` for the owner.

### Left as they are
- **`NEXT`'s list moving when the master track ends:** it holds for 2 s and then it's a different list, as what it's next from has changed.
- **`FILTER` on the old deck snapping back after "That's yours for this move":** that's the rule, and "for this move" covers it.
- **A deck dropping `SYNC` when what it follows runs out:** it's stopped, and nobody's heard that speed.
- **Fast Bird's numbers:** still its first analysis, and the stems settle it. It's on its second first-time user, so it may get a look if it comes up a third time.
- **A mix not saying what it's taken over:** it can be minutes ahead, and you couldn't reproduce what they saw.
- **The row menu cut off on its side:** that's iOS's menu, and it scrolls.
- **"More loop builds?" read as an offer:** pressing thumbs up on that still means what it should.
- **`?`'s note in the Mixer sheet, and the sheet's top edge on the deck titles:** small, and in a sheet that's only there briefly.
- **The crash reports from the iPad at 09:08 and 09:10:** those were mine, `GO NOW` before it was finished, and a test caught it. They're fixed, and none of it reached you.

