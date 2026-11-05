# Hands-on results, part 19, 2026-11-05

Commit tested: c0932fa

Device:
- **iPhone SE Cheeks:** 667×375 on its side, for the retest, what hadn't been run for a while, the long run and CPU.
- **Folded iPhone Duo:** 466×678 pt, upright phone layout, for `GB1`, `GB4` and the upright side of `GC1`, `GC2`, `GC9` and `GC11`.
- **iPhone 17:** 874×402 on its side, for the first-time user.

Tooling limits:
- **The full layout can't be pressed.** The Duo's still folded: the last `hingeState:` in SpringBoard's log says `Cl`, at 13:01 on 11-04. I didn't reboot it. So `GA` is blocked again.
- **Can't be checked here:** how anything sounds, haptics, the headphone output and a real finger. Levels are read from recordings and meter pixels.
- **Double-tap on a knob or fader:** two tool taps are too slow to count, so `I2`'s "double-tap brings it back" isn't tested.
- **Presses in a slide:** I sent them straight after the key, so by timing they were in or just after the slide. I didn't freeze the app.
- **Screen reading:** a logger read the top of the screen by OCR about twice a second. It stalled from 05:55:27 to 06:00:29 and from 06:20:22 to 06:20:54, and I restarted it. Screenshots and the recording cover those gaps. It was off for the CPU table.
- **Busy Mac:** the first-time user ran beside my retest until 06:06. Mac idle read 0.1% at 05:24 with three simulators splitting stems, so I closed the Duo's app until I needed it. Their tool took about 10 s a step, which is why several of their "no message" notes mean little. I only rely on those I reproduced. The CPU table came after they'd stopped, with Mac idle at 50 to 71%.
- **Crash reports:** the only one today is still `Cheeks-2026-11-05-013456.ips`, from `CheeksTests` at 01:34, before this commit. This round produced none. The faults in the small iPhone's log are UIKit animation assertions around 05:25:36 and 05:25:56, about when I opened the `BPM` menu, and the rest are from before my install.

## Summary

46 scripted tests including the long run: **41 PASS, 1 FAIL, 4 BLOCKED.** No crash reports. The failure is `GC9`, on one line: the first load's tip spills out of its capsule upright. The blocked ones are `GA1` to `GA4`.

**Everything that failed last round is fixed.**
- **`N28`, a mix from nothing on a track with its saved loop on:** it plans at once and runs past where the loop was.
- **`N29`, `SYNC` and what's left over:** all four cases do what the task says, and the first-time user had nothing like last round's 85 and 170.
- **`GB4`, the tip:** all of it, on two lines upright.
- **`N30`, `Done`:** it stays on all five sheets upright.
- **`N31`, an Echo throw's words:** gone, and the tip waits for a move it's true of.

**Your three questions:**
- **`GC10`: no, a real grab never missed for me,** including 6 pt past the cap, and the first-time user has no record of a miss. **A drag meant for the platter can still take it, but only by landing on the cap itself.** On the small iPhone, a drag from the platter stays with the platter even across the cap, x572 moves nothing and x576 takes the fader. That one went from +18.4% to -35.6% in 40 pt at `WIDE`, so when it happens it's big. See `GC10`.
- **`GC1`: yes, `+32.8%` at `WIDE` fits, reads and is useful,** on both layouts. The first-time user read the percentage correctly with no help. What's hard to find is the way back: `Back to Its Own Speed` is below the fold of the `BPM` menu on a phone on its side.
- **`GC11`: it's `EXIT`, in white on orange.** That's on a held `ROLL` and a held `SLICE`, on the small iPhone and upright on the folded Duo, in every frame I caught. I couldn't get last round's orange-on-orange (`gc11-held.png`, `gc11-roll.png`, `gc11-upright.png`, `gc11-slice-seq2.png`).

**The most important problems:**
1. **`N33`: dragging the tempo fader takes a deck off `SYNC` with no word.** 12 pt took a synced deck from 170 to 149.28 at `WIDE`. The only signs are the key going dark and the marker going orange. It's the sharpest example in the first-time user's worst thing, and I reproduced it.
2. **`N32` (`GC9`): a message's capsule doesn't grow with its text.** It's about 25 pt tall whether it holds one line or three. On three lines the text comes out of the top and bottom, onto the search field and the first row. Everyone upright sees this on their first load, for about 11 s.
3. **`N34`: what `AUTO` undoes, it undoes without a word.** Turn the new deck's `LOW` down and press `AUTO`: it's back at the centre at the press. Mute its vocal, or leave an effect on the old deck: both are gone by the end of the move. "A control you touch is yours" only covers what's touched after the start.

**The first-time user** could say what Auto DJ does at **+15:32**, against +13:25, +10:41 and +16:52 before. A message told them to watch `STEMS`, and watching got them there. The worst thing has moved from "things stay changed" to "it's hard to tell who's in charge". What they listed as still changed is mostly in the browser or the sheets. See **The first-time user**.

## Failures

### GC9 and N32: a message's capsule doesn't grow with its text
- Steps: clean install, upright on the folded Duo, first track loaded from the browser.
- Expected: "It's on the deck: DECKS takes you there. New to this? ..." in a capsule, readable, on three lines.
- Actual: the capsule stays about 25 pt tall, and the 3 lines spill out of it. The first line sits on the search row and the third on the first row's title, so "the whole guide." is written across "Severe Tire Damage" (`n32-three-lines.png`, seen on the clean install and again with the flag reset). It stays up about 11 s, as it should for that many words.
- **On two lines, the text touches the capsule's top and bottom.** That's on every phone: the small iPhone on its side (`gc9-first-load-se.png`), iPhone 17 on its side (`fu-03-first-load-toast.png`, "two lines of text squeezed into a one-line pill") and the Duo upright (`n32-auto-crop.png`, `gc1-upright.png`). `lineLimit(3)` is what's new, and two lines were already this tight.
- **Nothing's cut any more.** Every message I saw ended properly, at up to 129 characters. The other long ones in the code (`Deck N's leading, ...`, a `letItBeHeard` in front of "Auto DJ is waiting for the stems...") didn't come up upright, so I can't say how those look.
- Where I'd look: `ContentView.swift:702` makes the text fixed-size, so it's free to overflow what's around it. The capsule's background goes on `row`, which is in an overlay on a bar with `.frame(height: 26)` (`:507`, `:512`). An overlay's offered its parent's size, and 26 pt is about what I measure, so I think the background's taking that and not the text's height.

The rest are new and outside the script.

### N33 (new, from the first-time user, reproduced): dragging the tempo fader takes a deck off SYNC with no word
- Steps, on the small iPhone: Exhilarate (170) playing on deck 1, Gepzene on deck 2 playing and synced at 170 (+32.8%). Drag the cap up by 12 pt.
- Actual: 170.00 becomes 149.28 (+16.6%), `BEAT SYNC` goes dark, the cap goes from blue to white and the marker between the waveforms goes orange. No message, for the 3 s I watched and in the log (`n33-fader-takes-sync-off.png`, 06:36:43).
- The guide says this happens, and the first-time user read that later. But the app has a sentence for nearly everything else, including a stray touch that does nothing. A miss gets "Drag the tempo fader by its cap. A stray touch can't change the speed.", and a touch that really takes a live deck off `SYNC` gets nothing. The rule at `Faders.swift:252` is `setTempoManually`.
- The first-time user's words: "A newcomer could drift out of time and not know why."

### N34 (new, from the first-time user, reproduced): what AUTO undoes, it undoes without a word
- Steps, on the small iPhone: Houston playing on deck 1 with `FLANGER` on. Gepzene stopped on deck 2 with `VOCAL` muted and `LOW` turned down. Press `AUTO` (06:42:23).
- Actual:
  - **At the press:** deck 2's `LOW` is back at the centre, its cue goes from 0:00.2 to 0:09.5, and it's at 126 BPM (`n34-a.png`). The message is "Loop build next, with deck 2 cued at 126 BPM. AUTO's counting down the bars." It mentions the cue and the tempo, and not the `LOW`.
  - **At the end:** `VOCAL` is back on deck 2. `FLANGER` is off on deck 1, and the blue dot on `FX` has gone (`n34-after.png`, against `n34-started.png`). No word for either.
- These are the rules as written: "a plan cues the new deck", "at the end of a move the old deck goes back to neutral", and "A control you touch is yours" for after the start. So it's your call. The first-time user read that last sentence as covering everything, and lost a stem mute and an effect that way. It's the same family as last round's "`AUTO` undid the `SYNC`".

### N35 (new, small): `Back to Its Own Speed` is below the fold on a phone on its side
- The `BPM` menu has its title, seven items, then that, so on the small iPhone it needs a scroll (`gc1-bpm-menu.png`, `gc1-bpm-menu2.png`). It's the one item in that menu someone's looking for in a hurry, and the first-time user's notes of the menu don't mention it. It works: 170 to 128.00, `BEAT SYNC` off (`gc1-own-speed.png`).

### N36 (new, small): `AUTO` just after a move starts the next one
- At 06:20:22 I pressed `AUTO` to hand back a Loop build, about 1.5 s too late. The move had just ended, so it started another: "Echo throw next, with deck 1 cued at 128 BPM." (`lr-k.png`). That's back into the track that had just gone, and the rating question went with it. It said so, and another press gave "Auto DJ stopped. The decks are yours." Nothing was lost, and I don't see a clean rule for it. Somebody will do this.

## Blocked

- **`GA1` to `GA4`:** the Duo's folded and nobody has opened it in Device Hub. Nobody has yet pressed during the slide on the full layout, or filmed the browser, logo or sweep on the Duo.
- **One part of `GC4`:** nothing in a mix in a track's last 30 s with the browser open. My mixes were never there with the browser up, so I can only give the code for that.

## Looks wrong

- **`NEXT`'s lit key and its order are measuring different things.** The first-time user couldn't work this out in 25 minutes. With Skylander (125, 11A) leading, the order was Houston (126, 5A), Severe (148, 5A), Fast Bird (139.7, 10A): the lit key's third, and closer in tempo than the track above it (`fu-13-next-sort.png`). The code explains it. `SetOrder.order` builds a chain, so Severe follows Houston because of Houston's key. The lit key is against the deck. The note says "a good order to play from the leading deck", which is what they took it to mean.
- **`MIX`'s bare number:** bars with no unit, and % in the same place at other times. They read the `?` note and still took `MIX 78` for a percentage. Last round's first impressions said the same.
- **`SYNC` and `BEAT SYNC` are one control with two names,** on the pads page and the jog page (`gc1-jog-page.png` shows both).
- **The BPM moves on Fast Bird before its stems are done:** I read 139.72, 140.69, 139.70 and then 140.06 once split. The first-time user saw 140.59 on the deck beside 139.7 in the library, and it reached them as a mystery. I take it as the first analysis, which you've said to expect from section names. It isn't one of `J3`'s two test tracks.
- **`SPACE` turns the master's top LED red** for about 1 to 2 s when it's turned: both ways on Exhilarate, and down only on Gepzene. Nothing else did. It may just be how hot those tracks are.
- **The `?` note can cover a warning.** The first-time user's first "Nothing's coming out" was behind their note, and gone when they closed help. They only read the whole sentence the second time. I didn't reproduce this.
- **"No clean way in. Deck 1 just started."** doesn't say why. For the first-time user the reason was unfinished stems, and for me (05:52:31) a track with 3 s left.
- **What I can't confirm, from the first-time user:**
  - "Analysing Fast Bird again." never says it's done.
  - Renaming a playing recording stops it.
  - The guide's search bar floats over the list, with text showing through (`fu-12-guide-search-overlap.png`).
  - During a move at 05:44, the fourth knob read `DUB` on one deck and `FILTER` on the other (`fu-29`, `fu-30`). That's what you've described, and it reached them as a question.

## About the first-time user's report

It's careful and corrects itself. Four things to know.
- **Thumbs:** their report said two taps got no response. Asked again, they found both came after the question had gone, because their tool takes about 10 s a step. So thumbs are untested by them. `GC5` is mine.
- **"No message that I saw":** for most of these, take it as "not by the time my screenshot ran". `N33` is the exception, as I reproduced it.
- **`AUTO` undoing things:** reproduced, as `N34`.
- **`NEXT`'s order:** they marked it never resolved, and it's explained above.

## All results

| Test | Result | Notes |
|---|---|---|
| GA1 | BLOCKED | Duo folded |
| GA2 | BLOCKED | Duo folded |
| GA3 | BLOCKED | Duo folded |
| GA4 | BLOCKED | No full layout to press |
| GB1 | PASS | All of it on two lines (`gb1-tip-upright.png`). See `GC9` for what a third line does |
| GB2 | PASS | See below |
| GB3 | PASS | All four. See below |
| GB4 | PASS | Settings, the guide, Recordings, `LIST` and a sampler pad's sheet, scrolled upright: the title, and `Done` or the way back, stay (`gb4-*.png`) |
| GB5 | PASS | See below |
| GC1 | PASS | See below. `N35` is the catch |
| GC2 | PASS | See below |
| GC3 | PASS | See below |
| GC4 | PASS | See below. In a mix not seen |
| GC5 | PASS | 6 of 6 taps counted, and 2 of 2 long presses gave no rating. See below |
| GC6 | PASS | DJ Karda, last round's `-00:00.4`, reads `00:00.0` at 04:37.3, and `PLAY` starts from its cue (`gc6-pair.png`) |
| GC7 | PASS | See below |
| GC8 | PASS | `SLICE`'s tip gone within a second of leaving (`gc8-slice.png`). "Everything else here has been played" gone within 1.5 s of changing the list |
| GC9 | **FAIL** | One line of nine: `N32`. See below |
| GC10 | PASS | See below |
| GC11 | PASS | `EXIT`. See the summary |
| A1 | PASS | 4 of 4: default tap and 0.2 s press, paused and playing. The cue comes back and the capsule goes (`a1-pair.png`, `a1-rest.png`) |
| B1 | PASS | 8 presses on `BROWSE`, 339 frames: no coloured pixel in the master meters. The same count on a playing shot reads 6,616 |
| C1 | PASS | By pixels, the tempo cap's line is within about 0.5 pt of the centre mark. Crossfader's at 333.25 pt, with the screen's centre at 333.5 (`c1-caps.png`) |
| C2 | PASS | From 31 pt out to 2 pt short of centre, it lands on 333.25. +2 stays, +4 leaves to 337.25 |
| C3 | PASS | A phone has no mixer here. The search field stays visible over the keyboard (`c3-keyboard.png`) |
| C5 | PASS | A pad at y366 and the crossfader at y364 register first time, with no system gesture. The first-time user saw the home bar flash after crossfader drags, without it taking them |
| C6 | PASS | `BROWSE`, `REC` and the gear at y3 (`c6-all.png`). The `REC` alert has both choices |
| D2 | PASS | From video: each pad jumps (39 to 150) and settles at about 100 within 0.4 s. A held `SLICE` pad is clearly brighter (`gc11-held.png`) |
| D3 | PASS | From video: `AIR HORN` stays lit about 1.3 s, `CLAP` about 0.4 s |
| D4 | PASS | `IN` lights at once. A thin orange line shows on a stopped deck, on the next beat with `Q` on (`d4-stopped-c.png`, `d4zz.png`). On a playing deck I never caught it on the big waveform, so it's either faint or had scrolled off by my screenshots |
| D11 | PASS | The bar's end follows the finger, shorter after a drag to x125 and longer after one to x140 (`d11-pair.png`). I didn't measure how exactly |
| G1 | PASS | `SET`, `Q`, `VOLUME`, `STOP`. I pressed four pads, not all eight: `AIR HORN`, `SIREN`, `RISER` and `CLAP`, and all four fired |
| G2 | PASS | Grab buttons only with a loop set (`g2-sheet.png`) |
| G3 | PASS | Gate lit for a 2 s hold, and out on release. Loop: one tap on, next off |
| G4 | PASS | `LOOP 1`, and goes round (`g4-b.png`) |
| G5 | PASS | Red timer in place of `SET`. Meters move with only that pad playing (`g5-pair.png`) |
| G6 | PASS | Restores the original |
| G7 | PASS | `VOLUME` down, meters low (`g7-pair.png`). `STOP` stops a looping pad |
| H1 | PASS | Three lit, then `CRUSH` takes `ECHO` out (`h1-chain.png`, on `FLANGER`, `TRANS`, `CRUSH`) |
| H2 | PASS | `DEPTH` follows the effect you slide on, and the others keep theirs (`h2-tri.png`) |
| H3 | PASS | "Echo out on deck 1. Press OUT again to bring it back." Meters from 5,696 lit pixels to 0 in about 1.8 s, with the clock running on |
| H4 | PASS | Stopped: "Echo out needs the deck playing." Paused during one and played again: not silent (`h4-pair.png`) |
| I1 | PASS | `DUB`, `SPACE`, `NOISE`, `CRUSH`, `PITCH`, `FILTER`, and both labels follow (`i1-color.png`) |
| I2 | PASS | Each way on each, on deck 2. Nothing silent, no crash. `SPACE` as under **Looks wrong**. Double-tap not testable. My first go at this moved the wrong things, as my drags back started on the overview and a channel fader. That was me, and I redid it |
| I3 | PASS | `DUB` turned up 4 s and back to centre, then paused: the meters fall steadily, half-way at about 1.4 s and at 0 at about 2.7 s. With it not turned, they're half-way at 0.4 s, with only a small tail after 1 s. With the knob left up, they were still falling at 8 s |
| Long run | PASS | 15:18, 12 moves. Every gap explained. See below |

### GB2: a mix from nothing on a track with its saved loop on
- **With the loop on:** Severe on deck 2 with its 3:01 loop switched on in `LIST`, reloaded, nothing playing. `MIX` at 05:37:02: "Mixing through all your tracks, 4 tracks to go. Up next: Houston." A plan by the time I got back to the decks 8 s later (`MIX 116`). I sought to 3:00.5 and it ran on to 3:07.8 (`gb2-past-loop.png`). A Loop build at 05:37:40. In the long run the same: `MIX 128` by 06:13:03.
- **A loop by hand before a plan:** 05:52:58, "The mix will carry on when deck 1's loop ends.", about 8 s, and not again. `EXIT` at 05:53:15 gave `MIX 57` within 10 s (`gb2-hand-loop.png`).

### GB3: `SYNC` and what's left over
| Case | What happened |
|---|---|
| My own steps | "Deck 2's 33% faster than its own 128 BPM, to follow." Stop deck 1, load Houston: Gepzene back at 128 and off `SYNC` (`gb3-gepzene-back.png`). `SYNC` on deck 1: Houston at 128.00, +1.6% (`gb3-houston-128.png`) |
| A deck that's run out | "Deck 2's track has finished, so there's no tempo to follow. Load the next one first.", with a hand. Nothing moved (`gb3-finished-refusal.png`) |
| Only paused | Still leads (`gb3-paused-leads.png`). Loading something else on it let the follower go back as well (`gb3-load-leader.png`) |
| Both playing, leader stopped by hand | "Deck 1 follows at half tempo: 85 against 170." then, on the stop, "Deck 1 has nothing to follow now, and stays at 85 BPM, 33% slower than its own..." (`gb3-pair.png`) |

### GB5: an Echo throw's words
| Move | How | Words |
|---|---|---|
| Echo throw | `MIX` | "Echo throw into Exhilarate." Nothing about `STEMS` (05:41:08, 05:46:02, 06:14:32, 06:17:28) |
| Echo throw | `AUTO` | "Echo throw starting. A control you touch is yours." (06:21:12, 06:22:01) |
| Loop build | `MIX`, first move | "Loop build into Houston. Put both decks on STEMS to watch it." (05:37:40) |
| Loop build | `AUTO` | "Loop build starting. Put both decks on STEMS to watch it. A control you touch is yours." (06:19:43) |
| Loop build | `MIX`, both on `STEMS` | "Loop build into Skylander." (06:15:22) |
| Bass swap | `MIX`, first move | "Bass swap into Fast Bird. Put both decks on STEMS to watch it." (06:25:57) |
| **Brake drop** | `AUTO` | "Brake drop starting. A control you touch is yours." (06:19:04). This is the one I couldn't see last round |

**A mix's tip waits, as asked.** In the mix from 06:12, the first move was an Echo throw with no tip, and the second a Loop build with me already on `STEMS`, also none. The next Loop build, after I'd left `STEMS`, had it (06:18:32).

### GC1: the way back from `SYNC`
- **`UNDO`:** on "33% faster than its own", pressed twice: the speed back to 128.00, the range back and `SYNC` off (`gc1-undo-pair.png`). "follows at half tempo" offers it (`gb3-pair.png`), though I didn't press that one. 18% has one too. A +1.6% `SYNC` has no message at all.
- **`BPM` menu:** works, and it's `N35`. "Only when it's away" I've taken from the code (`DeckPanel.swift:431`).
- **`+32.8%`:** blue, in the place of `BPM`, and it fits at `WIDE` on its side and upright (`gc1-jog-page.png`, `gc1-upright.png`). It's the smallest type on the header, and readable. It's what I wanted to know: how far from its own speed, and which way.
- **The first-time user:** it was there from +1:19 at +1.2%, and they first wrote about it at +10:32. They took it to mean the right thing, and later used it to learn which way the fader works. They never saw a value that large.

### GC2: `MIXER` says `SPLIT`
- Lit blue with `SPLIT` under its name, and readable (`gc2-split-crop.png`). The first-time user noticed at once, and took it as "something's on". After a few minutes it stopped reading as anything to act on, and they left it on for the rest of the session.
- The sheet upright is 280 pt, with its last line on screen and room to spare (`gc2-sheet-upright.png`). "The key with the arrows chooses what each deck's fourth knob does." does the job. Above it you keep both waveforms, deck 1's clock and its pads, and lose deck 2's. That's useful, if lopsided. On its side the sheet is half empty, as before (`gc2-sheet-se.png`).

### GC3: nothing coming out
- Stopping deck 1 by hand and letting it run out both give the sentence (`gc3-nothing-coming-out.png`).
- Moving the crossfader across and back myself (05:28:57 to 05:29:03): no word. Nor in 13 moves and mixes.
- The first-time user at 05:51:15 dragged the crossfader back straight away: "The sentence names the crossfader, so the fix was obvious."

### GC4: running out behind the browser
- "Deck 1 runs out in 29 s." at 05:49:35, with one deck playing and the browser up (`gc4-warned.png`). Not again for that track when I reopened it.
- Nothing with the other deck playing (05:50:13 to 05:50:39), nor on a loop (05:51:01 to 05:51:15).
- **Is it when I'd want it? Yes.** The first-time user saw it twice, at 18 s and 29 s, and both times it pulled them back. The 18 s one was too late for stems, so `AUTO` could only start the next deck. That isn't the message's fault.

### GC5: the thumbs
- **Taps:** 6 of 6 counted while the question was up, each in `auto-dj-ratings.json` with the right word (05:41:25, 06:14:52, 06:17:44, 06:21:28, 06:22:19, 06:38:12).
- **Long presses:** 0.5 s at 05:38:20 and 0.3 s at 06:38:11: no rating and no seek. The first ended as the question's 8 s ran out (`gc5-pair.png`). On the second the question stayed up (`gc5-hold.png`), and a tap straight after it counted.
- **Late presses:** 0.3 s at about 06:19:22 and a tap at about 06:16:11, both after the question had gone: no rating and no seek. I can't say whether either was inside the 2 s that still count.

### GC7: `LIST`'s switch
- **Off, with the loop up ahead:** Severe reloaded with it on, then off in `LIST`. It ran from 03:00.3 to 03:09.1, straight through the loop at 3:01 to 3:03 (`gc7-off-ahead.png`, `gc7-ran-past.png`).
- **Off, with the deck in it:** it stays, 03:01.3 to 03:02.2 and round (`gc7-stays.png`). The flag in `library.json` follows the switch both times.

### GC9: words
| Words | Result |
|---|---|
| "Moved the crossfader to the middle, to hear both." | Seen 06:37:39, with the clock (`gc9-hear-both.png`). With no plan: "Moved the crossfader to the middle. No clean way in from here. Deck 1 starts when this one ends." (`gc3-auto-b.png`) |
| "Mixing through all your tracks, 4 not played yet." | With a track playing and some played (05:52:57). "4 tracks to go" and "6 tracks to go" with nothing playing (05:36:58, 06:12:49). The first-time user noticed both forms on one screen, the capsule's and the line under the list's (`fu-21-mix-started.png`). They called it minor |
| The first load's tip | **Three lines upright do get in the way.** `N32`. On its side it's two lines, tight but readable |
| Notes for `HI`, `MID`, `LOW`, `FILTER KNOB`, `CUE/MST` | Say down and up. Read on screen for `HI`, `LOW`, `FILTER KNOB` (`gc9-low.png`), and in `Explanations.swift` for the other two |
| `MIX TWO TRACKS` | "With one deck playing and the crossfader over on it" is there, in `Explanations.swift:60` |
| Column headings with `?` on | A note, and the order doesn't change (`gc9-column.png`). The first-time user says nothing suggests they can be tapped, and found the sort by trying |
| The playlist icon, upright | Lines and a note. It reads as a music list to me. The first-time user was on their side, with a sidebar, so has no view |
| `Stems 99% · a moment` | Not caught. I read `21% • 3 min` and a bare `99%` from the logger, and the end of a split goes by quickly |

### GC10: the tempo fader, small iPhone on its side
| Drag | Start | What happened |
|---|---|---|
| Up its column, away from the cap | y325 to y200 | Nothing moved. "Drag the tempo fader by its cap. A stray touch can't change the speed." (`gc10-a.png`) |
| The same, synced | y200 to y235 | Nothing moved, and `SYNC` stays on (`gc10-b.png`) |
| On the cap | y266 to y236 | Moves, as before (`gc10-a.png`) |
| 6 pt past the cap | y255 to y235 | Moves |
| On the platter's edge | x565, y280 to x600, y240 | Only the platter (`gc10-c.png`, left) |
| Between platter and fader | x572, y280 to y240 | Nothing at all, and no word (middle) |
| The cap's edge beside the platter | x576, y280 to y240 | **Takes it: 148.00 to 80.55, +18.4% to -35.6%** (right) |

The same again at ±10 and +0, with the cap at its most level with the platter (`gc10-p1.png`, `gc10-p2.png`):

| Drag | Start | What happened |
|---|---|---|
| Up the platter's edge | x555, y262 to y222 | Only the platter |
| **From the platter across the cap** | x555, y266 to x600, y240 | **Only the platter** |
| Up the platter's very edge | x566, y266 to y246 | Only the platter |
| In the gap | x572, y266 to y246 | Nothing, and no word |
| On the cap's edge | x576, y266 to y246 | Takes it: 125 to 121.63 |

- So the column's safe, and a drag that starts on the platter never takes the fader, even crossing over it. What's left is a thumb coming down on the cap itself. The drawn cap starts about 5 pt from the drawn platter, and at +0 it's level with the platter's centre. So that's one for a real thumb.
- **`WIDE` makes a slip big:** about 1.35 points per pt here, so 12 pt is 16 points.
- **The first-time user** aimed every drag at the cap from a screenshot, with no record of a miss or of the message. They found the fader by pressing `JOG` out of curiosity with `?` on (+4:42), and have no record of reading `TEMPO`.

## Timings and measurements

### CPU, small iPhone, this simulator's process only

| State | Average | Peak | Memory | Mac idle | Last round |
|---|---|---|---|---|---|
| Idle, nothing loaded | 3.8% | 4.1% | 67M | 71% | 4.0% |
| Two tracks loaded, paused | 4.5% | 5.4% | 328M | 68% | 4.5% |
| One deck playing | 9.3% | 9.6% | 331M | 55% | 9.5% |
| Both playing, synced, tempo offset | 14.8% | 15.7% | 331M | 52% | 15.0% |
| Both, plus stems and an echo | 15.5% | 16.0% | 334M | 50% | 15.5% |

Also running on the Mac: `pairedsyncd`, `backboardd`, `mds` and a `Slevens` archive from another project sitting idle. Exhilarate ran out in the last second of the last row, so that row's all good.

### The long run

Small iPhone, `DUB` throughout, recording from 06:12:45 to 06:28:05: **15:18,** mean -15.1 dB, peak 0.0 dB. No crash, and the decks were usable at every point. At the end Houston was playing and Fast Bird stopped, with every knob at the centre, every stem up and no loop (`lr-end.png`).

| Time | What I did | What happened |
|---|---|---|
| 06:12:50 | **`MIX` on Severe, its saved loop on** | "Mixing through all your tracks, 6 tracks to go. Up next: Skylander." `MIX 128` by 06:13:03 (`lr-mix.png`) |
| 06:13:11 | **A load on the waiting deck** | "Up next: Houston. The mix carries on." (`lr-waiting.png`) |
| 06:13:14 | `BROWSE`, then deck keys and tabs straight after | Landed on what was arriving: both decks on `STEMS` |
| 06:13:28, 06:13:41 | **Seeks past the exit,** 0:45 to 4:30, then to 5:39 | `MIX 100` to 70 to 31 |
| 06:14:32 | | Echo throw into Houston, done 06:14:46 |
| 06:15:00 | **Seek past the exit** | `MIX 98` to 12 |
| 06:15:22 | | Loop build into Skylander |
| 06:15:50 | I meant `EXIT` and pressed `INST`, at the same place on `STEMS` | "That's yours for this move. Auto DJ carries on with the rest." It did, and was done by 06:16:02 (`lr-m2p.png`) |
| 06:16:43 | **A load on the waiting deck** | "Up next: Fast Bird. The mix carries on." |
| 06:17:06 | **Seek past the exit** | `MIX 62` to 13. Echo throw at 06:17:28, done 06:17:44 |
| 06:17:52 | **A load on the waiting deck** | "Up next: Gepzene - Can't be Serious. The mix carries on." |
| 06:18:08 | **Seek past the exit** | `MIX 79` to 13. Loop build at 06:18:32, with the tip |
| 06:18:43 | **`EXIT` on the old deck,** 11 s in and not in the last bars | "Mix off: deck 2's loop was changed. The decks are yours." Gepzene back to 0:00.2, cued (`lr-h.png`) |
| 06:18:58 | `AUTO` | **Brake drop.** Starting 06:19:04, done 06:19:11, Fast Bird stopped at -00:19.5 (`lr-brake.png`, `lr-i.png`) |
| 06:19:36 | `AUTO` on Houston | Loop build, starting 06:19:43, done 06:20:20 |
| 06:20:22 | `AUTO`, too late | `N36`. Called off at 06:20:45 |
| 06:21:06 | `AUTO` on Skylander | Echo throw, done 06:21:28 |
| 06:21:40 | `AUTO` on Fast Bird, then `BROWSE` twice and deck 2's `FX` tab in the slide | Echo throw, done 06:22:15. The tab landed (`lr-slide1.png`) |
| 06:22:27 | `AUTO` on Houston | Loop build, 16 bars, starting 06:22:55 |
| **06:23:20** | **`AUTO` in the build's last bars** | "Auto DJ stopped. The decks are yours. Deck 2 is still looping. ALL brings back deck 2's stems." Houston back to 0:00 at 126. Deck 2's `LOW` down and `FILTER` swept, both showing (`lr-handback-auto.png`) |
| 06:23:3x | `ALL`, `LOW`, `EXIT`, `FILTER` by hand | All normal, and the fourth knob back to `DUB` |
| 06:24:03 | `AUTO` | Loop build, starting 06:24:08 |
| **06:24:32** | **`EXIT` in the build's last bars** | "Auto DJ stopped: deck 2's loop was changed. The decks are yours. ALL brings back deck 2's stems." (`lr-handback-exit.png`) |
| 06:25:14 | Stopped Fast Bird by hand, `±6%` on | The one hole, and it's mine |
| 06:25:19 | `MIX` on a list of two | "Mixing through this list, 1 track to go. Up next: Fast Bird." |
| 06:25:3x | **Seek past the exit** | `MIX 234` to 12 |
| 06:25:57 | | **Bass swap into Fast Bird,** done 06:26:23 (`lr-bs1.png`) |
| 06:26:38 | **A load on the mix's last track** | "Up next: Houston. The mix carries on." (`lr-last.png`) |
| 06:26:5x | **Seek past the exit** | `MIX 57` to 17 |
| 06:27:23 | | Loop build into Houston, done 06:27:56 |

**Every gap under -50 dB of 0.2 s or more:**

| Recording | Length | What it is |
|---|---|---|
| 0.00 to 3.56 | 3.56 s | `REC` before `MIX` |
| 133.29, 135.21, 137.10 | 0.22 s each | Houston's own at 3:02 to 3:06, where I'd just sought |
| 333.25, 334.52 | 0.26 s, 0.93 s | Fast Bird's own: down to -50 dB at about 2:34, then silent 2:35.4 to 2:36.3 |
| 381.41 to 400.40, six of them | 0.24 to 0.35 s | Gepzene's own, 0:11 to 0:30, the same lengths as in the file |
| 493.47 to 499.78, eight of them | 0.21 to 0.23 s | Houston's own, 1:09 to 1:16 |
| 748.18 to 752.68 | 4.50 s | Mine: stopped Fast Bird, pressed `MIX` |
| **803.96** | **0.37 s** | **The Bass swap's breath** |
| 865.92, 867.11 | 0.22 s, 0.87 s | Fast Bird's own again at +5.7%. By the deck's clock it reached 2:35.4 at 06:27:13, and 0.92 s at that speed is 0.87 s |

**Hand-backs, as asked:** `AUTO` and `EXIT` in a build's last bars, one of each, and `EXIT` once earlier. Last round's `MIX` key I didn't repeat. **The saved-loop mix, the waiting deck and the last track** all behaved.

## First impressions

**1. Does it look like $1000 pro software?** On the small iPhone on its side with both decks running, yes for a screenshot of the decks. Three things break it most:
- **Text out of its capsule (`N32`).** It's the first thing a new user sees after loading a track.
- **The sheets.** Hardware gives way to stock iOS and black. The Mixer sheet on its side is a row of knobs and half a screen of nothing (`gc2-sheet-se.png`).
- **A bare number on the main key.** `MIX 128` looks like a tempo, on a screen full of tempos.

**2. What felt slow, confusing or surprising?**
- **Nothing felt slow in the app itself.**
- **How far `WIDE` moves.** After a big `SYNC`, the fader's range stays wide, and my small drags were big changes. I'd only notice by looking at the number, which is why `N33` matters.
- **A row of keys that changes under the same thumb.** `EXIT` on `LOOP` is where `INST` is on `STEMS`, and I hit the wrong one mid-move. It said what it had done, and the move went on.

**3. Which control was hardest to find or hit?** Hardest to find is `Back to Its Own Speed`, behind a scroll in a menu that's labelled as being about something else ("Beat grid"). Hardest to hit is the mixer's knobs on the small iPhone. They're small and close to the channel faders. Two of my drags started on the wrong thing, though that was my aim, and it wants a real thumb.

## The first-time user

On `iPhone 17` on its side, from 05:19:58 to 06:06:52, 46:54 from opening. Clean install, with no backups in its Files. No crash.

| Stage | From opening |
|---|---|
| Music in | 0:31 |
| First sound | 1:00 |
| Both playing | 1:10 |
| First crossfade, new track's `LOW` down | 2:06 |
| First `?` | 3:25 |
| Pressed `JOG` with `?` on: found the tempo fader | 4:42 |
| First `AUTO` (no stems, so it just started the next deck) | 5:28 |
| Opened the guide | 8:33 |
| First full `AUTO` move | 14:32 to 15:37 |
| **Could say what Auto DJ does** | **15:32** |
| First whole-list `MIX` | 15:44 |

They knew DJ words before starting and say so, so treat these as a best case.

**What I asked afterwards, in their words as near as I can:**

1. **What Auto DJ does.** At about 05:35:30: "It picks a way out, counts down the bars, then works the crossfader, knobs and stems itself until the cued track has taken over, and resets the old deck." They got there by watching the `STEMS` pads, "which I only did because a message told me to."
2. **What stayed changed with nothing on the decks screen to show it.**
   - The `IN KEY` and `±6%` filters, lit only in the browser. These cost them a short while, as `±6%` hid a track.
   - The browser's sort, which decided what `MIX` started.
   - The ticks, which cost one failed press.
   - `KEY` off, not visible on the pads page.
   - A memory cue, shown only on `MEM`.
   - Prepare stems off and `RGB`, which they set themselves, and possibly the cause of the grey `STEMS` puzzle.
   - A sampler pad's recording.
   Against last round's list, `SPLIT` now shows, the crossfader has a sentence and the speed has a number.
3. **What did nothing, with no word.**
   - A long press on a deck's title.
   - Dropping a dragged row.
   - The grey `STEMS` label.
   - Set downbeat here, which may have worked invisibly.
   - One dim load key at 05:38, which they may have missed.
   - One tap on a `SLICE` pad, which needs a hold.
4. **The tempo fader.** See `GC10`.
5. **The percentage.** See `GC1`. They saw `UNDO` at 05:33:21 and didn't press it, and have no record of `Back to Its Own Speed`.
6. **`SPLIT` under `MIXER`.** See `GC2`.
7. **"Nothing's coming out."** See `GC3`.
8. **"Deck 1 runs out."** See `GC4`.
9. **The thumbs.** See **About the first-time user's report**.
10. **Icons and headings.** See `GC9`.

**How they use `?`:** "? is excellent. Controls stop firing, it carries on working inside MIXER, and the best entries tell you what to do rather than what a thing is." Still a mystery after it: `NEXT`'s order, the grey `STEMS`, dragging a row, which software the XML means, how to reorder a playlist.

**Best thing:** "It tells you the next thing at the moment you need it."

**Worst thing:** "It's hard to tell who's in charge of what." That's `N33`, `N34`, `MIX`'s bare number, and both decks showing `SYNC` with only a small label to say which leads.

**An ordinary phone:** nothing they found is about the screen's size, beyond the two-line capsule and the home bar flashing after crossfader drags. They say to treat their times as a best case, as they knew the words.

**Their brief was kept, by their own account.** They read no source, docs or history, and looked at Settings and Recordings once more at the end to confirm how they'd left them. They left `SPLIT` on, stems' preparation off and `RGB` on, on `iPhone 17` only.

**Their report follows unchanged,** with its corrections to itself, and mine are above. Their raw notes come first, and their finished report overrides them.

---

# Segue DJ - newcomer session, raw notes as I go

Opened 05:19:58.

- 05:19:58 First screen is the library, phone on its side. "No music yet", blue IMPORT button. Very clear. (fu-01-first-open.png)
- 05:20:04 Import menu: "Music files..." or "DJ library (XML)...". Chose Music files. Took a few seconds for the Files sheet to appear with an "Opening Files..." pill. Opens on Recents, which is empty - the note in the empty state said to go back, so I hit Browse.
- 05:20:29 Picker: selected all, Open. "Added 7 tracks." (fu-02-added-7-tracks.png). BPM and KEY show "..." at first.
- 05:20:45 Pressed 1 on Alone. BPM/KEY all filled within ~10s. Toast: "It's on the deck: DECKS takes you there. New to this? Press ? and tap anything to see what it does. The gear has the whole guide." Good. But wraps to 2 lines and clips (fu-03-first-load-toast.png). Toast also still on screen over the waveform on DECKS.
- 05:20:55 Decks screen first look: a lot at once but looks like a real controller. (fu-04-decks-first-look.png). Time showed 00:01.6 before I'd pressed play - didn't understand (track's silent start skipped?).
- 05:21:00 Pressed play on 1. Meters move, clock runs.
- 05:21:13 Pressed SYNC on 2 then play. Both running. Toast: "Two basslines clash. Turn the new track's LOW down, and swap the two LOWs as you crossfade." (fu-05-two-playing.png) - exactly the sort of thing I'd want.
- 05:21:40 LOW knob: vertical drag works, blue arc shows the value.
- 05:22:12 Crossfader drag to right. (fu-06-crossfaded-to-2.png)
- 05:23 ? mode: lit blue, bubble explains. Controls don't fire. JOG still swaps pages. MIXER opens sheet and help carries on inside it. Very good.
- 05:25:03 Deck 2 ran out while I was reading help. Red warning toast "Deck 2 has stopped, and deck 1 is playing with the..." - rest of sentence HIDDEN behind the help bubble (fu-07-warning-hidden-by-help.png). When I closed help it was gone. Never read the end of it.
- 05:25:20 On Browse: "Deck 1 runs out in 18 s." Good nudge. Loaded Skylander on 2, hit AUTO with 8s left. "Auto DJ is waiting for the stems. If this track finishes first, deck 2 starts." then "The stems didn't get there in time. Deck 2 just started." (fu-08, fu-09). Crossfader jumped to centre by itself. Nothing went silent. Good failsafe. AUTO is off afterwards.
- 05:26:00 STEMS tab. VOCAL pad press while splitting: "That happens when the split's done. It's at 37%." Pad goes dim anyway, so it looks done but isn't (toast says otherwise). Clear enough.
- 05:26:15 LOOP pad 4: orange region on waveform, RELOOP turns to EXIT, < halves. Clean.
- 05:26:30 First ROLL: "ROLL pads play for as long as you hold them." First FX: "FX pads slide: up and down for depth, left and right for the beat." Coaching on first touch is really nice (fu-10-fx-tab.png).
- 05:27:30 MORE tab: pressing it goes MEM > SLICE > JUMP > SMPL > MEM. The tab label changes every press and the other tabs shift sideways a few pixels. There's no sign of what's next. It's just "MORE >" the first time and never again.
- 05:28 Settings: clean. Guide "What everything does" is good and searchable. Search bar floats over the list and the text bleeds through the bar, hard to read (fu-12-guide-search-overlap.png). Search "key" shows lots of entries. A semitone is "7 places round the key numbers, so +1 takes 1B to 8B" - I had no way to guess that.
- 05:29 MEM: SAVE CUE: "Memory cue saved. The track loads here now." with UNDO. Good but surprising: means next load starts at 3:37? Told clearly at least.
- 05:30 IN KEY filter stays on when switching to a playlist. History says 4 but only 1 row shown; count doesn't reflect filter. Filter button is lit so it's findable.
- 05:30 History Nov 5: Alone is listed TWICE, I only played it once (I did fade back to it). No idea if that's intended.
- 05:30 NEXT sort with Skylander (125, 11A) leading: Houston (126, 5A), Severe Tire Damage (148, 5A), Fast Bird (139.7, 10A - lit as "goes with"), Exhilarate (170, 12B). Why is 148/5A above 139.7/10A? Fast Bird is closer in tempo AND in key. Doesn't match what the guide says NEXT does. (fu-13-next-sort.png)
- 05:30:30 Houston on deck 1: BEAT SYNC then KEY SYNC. 126 -> 125, -0.8%. Key moved -1, 5A -> 10A shown on the platter only. Nice. Deck header doesn't show a key at all - platter centre text is tiny.
- 05:30:51 Full manual mix done: crossfader on 2, deck 1 LOW down, play, crossfade, swap lows, crossfade all the way. (fu-14-manual-mix-done.png). Meters and clocks all look right. Took 30 seconds.
- 05:31:05 Paused deck 2: MASTER at top flips 2->1, deck 1 MASTER lights, BEAT SYNC on deck 1 un-lights. Tempo stayed.
- My low knob ended slightly above centre. No visible way to reset; guide says double-tap on crossfader. Not sure about knobs.
- 05:31:10 Waveform icon at top = Recordings list. I thought it was a waveform view option. Empty state clear. (fu-15-waveform-icon-is-recordings.png)
- 05:31:30 REC: starts instantly, counts 0:01. Shows "0:20 - 1" after a while. The "1" is tracks so far (guide told me). Stop prompts "Stop recording?" Stop and save / Keep recording. Good.
- 05:31:40 JOG/PADS on deck 1: both decks now pads. Tabs lay out same on both sides. 
- 05:31:50 FX on deck 1: tapping ECHO latches it. Blue dot on FX tab tells you an FX is on when you've moved away - only noticed by accident. Stems: Skylander never finished splitting by 05:32.
- 05:32:30 Stems finished on Houston: waveform turned multi-coloured. Lovely moment - no announcement but obvious. VOCAL pad mute works, waveform loses pink. VOX/INST/BEAT/ALL row: INST = "mute vocal", BEAT = mute vocal+inst. Label INST lit turned VOCAL pad off, which is reasonable but it took me two tries to read. I wouldn't have guessed BEAT = bass + drums.
- 05:32:55 SOLO pads under the mutes. "AI" with green dot next to ALL - didn't explain itself.
- 05:33:10 Tried to load on deck 1 while it was playing: "Deck 1 is playing. Stop it first." with a hand. Button is dimmed, so I hadn't noticed it was disabled. OK.
- 05:33:15 Loaded Exhilarate (170) on 2 and pressed SYNC: "Deck 2's 26% slower than its own 170 BPM, to follow." with UNDO. Wording is awkward ("Deck 2's 26%"), but it's honest. Good warning.
- 05:33:30 BPM menu: tap BPM on deck: "Beat grid: 170.00 BPM at normal speed" Double/Halve/BPM +-0.1/Grid 10ms earlier/later/Set downbeat here. Halve: "Deck 2's track reads 85 BPM now. Its speed hasn't changed." But deck now shows 62.50 BPM, -26.5%, not 125. (fu-17-halved-62bpm.png) So sync's still locked -26.5% from the old setting and the deck's playing at half the master - I expected the point of halving to be 85 -> 125. This is the one place I went "wait, what?"
- 05:34:10 SYNC off and back on: "Deck 2 follows at half tempo: 62 against 125." with UNDO. So it IS deliberate. Toast explains it - says 62 where the deck says 62.50. Double the Reading: back to 125, -26.5%.
- 05:34:30 AUTO with 58s left and both split: SYNC on deck 2 turned off by itself and deck 2 jumped to 170 BPM, not playing, time 00:02.8. Toast "Loop build next, with deck 2 cued at 170 BPM. AUTO's counting down the bars." (fu-18-auto-with-stems.png). AUTO button counts 8,7..1. Crossfader goes to middle by itself: "Moved the crossfader to the middle, to hear both." Deck 2's waveform goes almost black - all four stems muted, little dim bars above its STEMS tab. Then "Loop build starting. Put both decks on STEMS to watch it. A control you touch is yours." (fu-19-loop-build.png). I did. Love that it tells you where to look.
- 05:35 AUTO loop build watched on screen: loop on deck 1 shrinks, BASS pad drains from the top like a level, LOW and FILTER knobs move on their own, then deck 2 starts, rewinds to 00:01.6, all stems open at once, and deck 1's meter drops to nothing. All in 2 minutes-ish. No hands. This was the most impressive thing I've seen.
- 05:35:30 "Loop build done. Deck 2 is on. More loop builds?" with thumbs. Text wraps to 2 lines and sits right at the top and bottom edges of the pill (fu-20-loop-build-done-thumbs.png). Deck 1 got put back: 126 BPM, knobs centred, stems all on, not playing. But the crossfader stays in the middle, and I'd moved my own low-knob earlier: AUTO reset MY knobs too.
- The deck jumped tempo from 125 to 170 at the change - it's what the toast warned me about, "cued at 170 BPM". But I had just pressed SYNC, and AUTO turned that off without telling me in so many words. 
- 05:35:45 MIX button in Browse. Immediately starts: "Mixing through all your tracks, 2 not played yet. Up next: Severe Tire Damage - High Quality." Hm: pressing it just started it, no confirm. Sort went by BPM. Button turned stop-square. Band at the bottom of Browse "Mixing through all your tracks, 2 tracks to go."
- 05:35:50 On DECKS: centre button now says "MIX 4%" and above deck 1 a little 4% with progress bar where AI dot was. Which is the mix percent? It took me a beat: it's the stems split of the track that's about to play, I think, and MIX is waiting for it. AUTO and MIX share a button, so AUTO has disappeared from here. (fu-22-mix-progress.png)
- 05:36:05 MIXER sheet: TRIM 1/2, MASTER, CUE/MST, LEVEL, SPLIT, FILTER<->DUB toggle. Bottom text: "One output, like AirPods, only plays the mix. SPLIT's for a splitter cable. The key with the arrows chooses what each deck's fourth knob does." That text is exactly what I'd have wanted. Filter button cycles FILTER > DUB (... others?). The knob label on main screen changes to DUB on both.
- 05:36:15 DUB knob moved. Blue arc goes from centre to about 3 o'clock.
- 05:36:30 Help on WAVEFORM ("The number counts bars in the section. UP's a build-up, DOWN a breakdown.") and BEAT BLOCKS ("Four blocks for each deck... Red is the first beat.") and STEM STATUS ("AI with a green dot means it's ready. ≈EQ is a rougher split by frequency"). I finally know what AI meant.
- 05:37 JOG page on deck 1 (paused): fader, platter, BEAT JUMP, Q, SLIP, KEY, REV, -/±0/+, KEY SYNC. ±10 tapped to ±16. Dragging tempo fader UP made it SLOWER (-8.8%). I know some gear does that but my finger expected up = faster. Dragged paused platter: 0.8 s forward. Remaining time is tempo-scaled: 6:51 became 7:30.
- 05:37:30 Double-tap on tempo fader to reset: two taps through my tool arrive too far apart, so can't test. NOT the app's fault.
- 05:37:50 Remaining time on deck 2 goes RED at about 23-25s left. Helpful.
- 05:38:10 "No clean way in. Deck 1 just started." MIX waited for deck 1's stems, which were at 72%, and at about 2-3 s from the end of deck 2 it gave up and started deck 1 at 148, resetting my -8.8% tempo change without mention. Deck 2 instantly swapped to Fast Bird, showing MIX 0%. (fu-23-no-clean-way-in.png)
  Wording: "No clean way in" is short and honest but I'd want "stems weren't ready, so I just started the next one".
  Fast Bird shows 140.59 BPM on the deck vs 139.7 in the library, with "BPM" under it so no tempo offset. Is it re-analysing?
- 05:38 Browse while MIX runs: load buttons for deck 1 dimmed (it's on air). Tapping a dim one does nothing visible here (earlier it gave "Deck 1 is playing. Stop it first").
- 05:38 NEXT off gives a shuffled-looking order (import order?). Tap "BPM" heading: sorts high to low with a small chevron. Good. "NEXT" and column sort fight: pressing column turned NEXT off silently? NEXT was already off when I tapped.
- 05:38:10 Press-and-hold a track: Load on Deck 1/2, Preview, Re-analyse, Delete from Library. Add to Playlist only appears once a playlist exists. Fine.
- 05:38:20 Preview from hold menu: "This preview's over the mix, as SPLIT's off. It won't be on a recording." Excellent, I'd never have thought about it. (fu-24-preview-over-mix.png) Art turns into a ring with a stop square. Tap art again to stop. Tapping a different track's art starts a preview there too, so that's the fast way (found by accident).
- 05:38:45 New Playlist: Warmup. Empty state "Go to All Tracks, press and hold a track, and add it from there." Exactly right.
- 05:39:20 Add to Playlist submenu: my first tap went to the wrong place because the sub-menu expands. Fine. "Added to Warmup." 
- 05:40 MIX stop: "Mix off. The track playing just carries on." Clear. Restart in Warmup: "Mixing through Warmup, 2 tracks to go. Up next: Gepzene - Can't be Serious." So MIX uses whichever list you're looking at. Help on MIX: "Shows bars to the next move, % while the stems split, or ... while it chooses." That's what the number was. Nice. Before reading I thought "MIX 45" was seconds.
- 05:40:30 MIX has cued deck 2 at 00:09.5 "UP 1.1", not at the start. So it picks a spot. Didn't tell me it did. Crossfader stays middle.
- 05:41 CUE tab: A-H pads, IN OUT RELOOP, 4, DEL. Tap A: pad fills red, 2:46, red flag on both waveforms. Tap again: jumps back. DEL lights, tap A: "Deleted hot cue A" + UNDO, DEL un-lights by itself. Great. UNDO brought it back.
- 05:41 Set a loop during MIX. "The mix will carry on when deck 1's loop ends." (wraps to two lines, top/bottom clipped). "MIX..." then. Exit loop: MIX 15, replanned, deck 2 back to 00:09.5 "UP 1.1". While it was deciding, deck 2 briefly went to 00:00.2 "INTRO 1.1" with its DUB knob turned to 3 o'clock on its own (did the mix do that?) and then went back. So deck 2 changes under me without my touching it. (fu-25-mix-replans-after-loop.png)
- 05:41:30 MIX count 2: deck 2 starts rolling at 00:06.7, dimmed stems, 3 s early. "Echo throw into Gepzene - Can't be Serious." at 10:02 on the recording. Deck 1 stays at 148, deck 2 at 128, no tempo match (it's a throw, ok). Peak: one red segment on deck 1's meter at the moment of the throw (around 05:41:32). LIM stays dark.
- After the throw (05:41:40) deck 1's meter is empty, its waveform dimmed, clock and platter still running, its play button still lit, and "MASTER 1 148.00" still at the top even though all the sound is from deck 2 at 128. Odd. (fu-26-after-echo-throw.png)
- "Echo throw" isn't explained in-context. I roughly know. A newcomer wouldn't but it's still fine as a label for what's happening.
- 05:42 Stop REC: "Stop and save / Keep recording", then "Saving your mix..." Recordings sheet: "Mix 2026-11-05 05.31.24  10:34 20.2 MB M4A". Icons: list = tracklist (timestamps, BPM and key as actually played: Houston 125.0, 10A). Lovely surprise - nothing told me that existed. Share and ... (rename, delete). Fast Bird got loaded but never played and it's rightly absent. (fu-27-recording-tracklist.png)
- 05:42:20 Play button on recording while MIX runs: nothing at all happens. It's a little grey. Sentence above says stop both decks. It holds up.
- 05:42:50 MORE on deck 1: MEM (SAVE CUE, SAVE LOOP, LIST + 8 blank pads with no labels, no hint), SLICE, JUMP (<<1 4 16 32 / >>1 4 16 32, obvious), SMPL (AIR HORN, SIREN, RISER, IMPACT, LASER, CLAP, RIM, REWIND; SET, Q, VOLUME, STOP).
- 05:43 LIST with nothing saved: "Nothing saved yet. Set hot cues on the CUE pads, and save cues and loops on the MEM pads." Good.
- 05:43:10 AIR HORN: tapped - a screenshot straight after shows no change. RISER: pad lights gold while it runs, goes dark a few seconds later. So the short ones are invisible by the time I look.
- 05:43:30 SET: lit blue, no message saying what to do. Tapped CLAP: "Pad 6" sheet, One shot / Gate / Loop (not explained here), Choose a File, Record the Master. "Samples can be up to a minute long, and recordings stop at 30 seconds." Record the Master starts straight away, sheet closes, pad goes red with a dot, SET turns to red "stop 0:01". Very clear. (fu-28-sampler-recording.png)
- 05:44 Stop sampler record: "Pad 6 has your recording. SET and then the pad can restore its original sound." Pad renamed REC 6. Top/bottom of toast cut. Tap plays it, lights green.
- 05:44:10 ? on Q (sampler): "With it on, a pad starts on the leading deck's beat rather than straight away." Clear.
- 05:44:40 MIX counting down bars: at MIX 1 deck 1's stems go dim, and deck 2's fourth knob changes from DUB (my pick from MIXER) to FILTER on its own. Deck 1's stays DUB. No word about it. Then "Loop build into Houston."
- 05:44:50 Tested "a control you touch is yours": pressed deck 2 BASS mid-build. "That's yours for this move. Auto DJ carries on with the rest." Worked, the app stayed off it. But now it's called Auto DJ in the same breath as the button reading MIX. (fu-29-thats-yours.png)
- 05:44:40 Loop build into Houston after I took BASS: deck 2's loop shrinks to tiny, time stuck at 02:47, FILTER and HI turn on their own, deck 1 starts at the same moment. Beat blocks on both decks go in step. "Loop build done. Deck 1 is on. More loop builds?" Thumbs up/down: asks me to rate. No idea if that changes anything, the toast doesn't say. (fu-30-loop-build-done-with-play.png)
- Deck 2 now stopped at 02:47, 1:01 left. My BASS mute has been undone, so "yours for this move" means only that move - matches its wording.
- Deck 1's time had read 00:22.8 throughout; while it was loading the build it jumped BACK to 00:19.7 and played into it. Reasonable.
- 05:45 Browse during last track of Warmup: "Mixing through Warmup. This is the last track." MIX button on deck just reads MIX with no number. Help for that state doesn't exist, but Browse says it.
- 05:45:30 ROLL 1/4 held 3 s: RELOOP goes orange, size reads 1/4, pad lights. Let go: clock carries on as if nothing had happened (slip-style). Nice; nothing on screen says it would.
- 05:46 Help on V I B D: "Which parts of the track the effect goes on. Echo just the vocal and then mute it, and the echo rings out over the rest." Help on OUT: "Ends the track on its own echo..." Best help text in the app, it tells me what to DO with it. Waveform changes colour depending on which pad tab is up: orange/white on FX or ROLL, stem colours on STEMS. Nothing says so; I thought the track had changed.
- 05:46:10 OUT pressed: "Echo out on deck 1. Press OUT again to bring it back." OUT goes red. Meters fall. Clock keeps running. Blue dot by FX tab.
- 05:46:20 BRAKE pad (has a little square): deck 1 stops: "Mix off: deck 1 was stopped." So pads with a square stop the deck. Now I get it, after doing it. Toast wraps to two narrow lines and clips, with plenty of room to be one line. (fu-31-brake-mix-off-toast-wrap.png)
- AUTO is back in the centre where MIX was. Good. Silence at that point, neither deck playing. Self-inflicted.
- 05:47 Big CUE button when stopped: track jumps to 00:00.0 (earlier saved no cue on this track). Top strip (overview) tap jumps the track to the spot. Dragging the big waveform scrubs. Two-finger pinch zooms BOTH decks' waveforms together. Nothing told me these, I only tried because that's how phones work.
- 05:47:30 JOG on playing deck: REV lights red, clock runs backward. SLIP + REV: on release, clock jumps forward to where it would have been. Works. No on-screen marker of the "ghost" position, you just have to trust it.
- Fader: handle sits BELOW centre for +1.6. So down is faster. Scale runs 'upside down' to my phone-trained thumb. Label at the bottom reads +1.6 and the ±16 button above.
- 05:48 Settings: Save a Backup opens system save sheet, "Backup saved." Alert title is "Library" which is odd but fine. Curve explanation helps. RGB waveform works, reads as green here, and deck 2 on STEMS keeps stems colours as promised ("A deck on STEMS shows its stems' colours with either"). The earlier change-of-colour puzzle is explained HERE, in Settings, not at the moment you see it.
- 05:49 Key + on deck 1 with KEY unlocked: readout +1, platter 5A -> 12A. OK. After "KEY" off the +1 persisted.
- 05:49 MIXER: 4th-knob key cycles FILTER > DUB > SPACE > NOISE > CRUSH > PITCH > FILTER. No one-line description of each in this sheet, you find out by turning. Change affects both decks at once. SPLIT turned on: explanation swaps to "the mix in the left ear and your cue in the right, for a splitter cable", and MIXER key on the main screen shows little "SPLIT" under it and goes blue. Great that it stays visible.
- 05:49:40 Deck 1 ended with deck 2 stopped, no warning. Clock reads 00:00.0 red. Fine. Deck 1 still shows pause button until the very end, and CUE lights when it stops.
- 05:49:50 Recording plays when both decks are stopped. Scrub bar appears only while playing. Rename: keyboard covers half the screen but alert moves up. The name stayed old for a second, then changed, and PLAYBACK STOPPED (position lost). Small. Leaving the sheet with it playing: stopped too, nothing said.
- 05:50:30 Browse with ±6% BPM on against 128: Alone 129.5, Gepzene, Houston 126, Skylander 125 - correct. All Tracks count still says 7 with 4 showing. 1B gets a filled chip next to 1A playing: "goes with it" but no legend says the filled chip means that, it's in the help only.
- 05:51 Loading a new track reset my key shift, KEY, tempo. Good. Dragging tempo fader while BEAT SYNC is lit TURNS SYNC OFF with no message: number goes white, button unlit, bpm 134 against master 128. (fu-32-fader-breaks-sync-silently.png). AUTO's and SYNC's toasts are chatty everywhere else; this one's silent, and it's the likeliest way for a newcomer to drift out of time without knowing why. A tiny green tick on the fader scale marks "where sync was". I only guessed.
- 05:51:10 Deck 2 ended while deck 1 was playing with crossfader on 2: full red warning this time, readable: "Deck 2 has stopped, and deck 1 is playing with the crossfader away from it. Nothing's coming out." THAT'S the sentence I lost at 05:25. Very good warning. (fu-33-nothings-coming-out.png) Meters: deck 1's still move, though nothing's "coming out". Master meter shows only left? Reading: the deck meter bars do move but the outputs are empty.
- 05:51:40 SLICE: tap is ignored unless you hold. Help: "Plays this eighth of the bar for as long as you hold it." OK. Help bubble covers the whole left half of the waveform, which is what I want to watch.
- 05:52 ±6% BPM filter stayed on as I left Browse and returned, and it's what hid Fast Bird once. Long press on a track while filtered: Re-analyse: "Analysing Fast Bird again." Fast Bird's BPM: 139.7 in the library at first, 140.1 in the long-press preview a minute ago, 140.59 on the deck at 05:37, and 139.7 now the row is back. (fu-34-fast-bird-three-bpms.png) It's also the only row with no tick: it was loaded but never played. Tick = "played". Took me till now to work that out.
- 05:52:30 Re-import a track: "That track's already in your library." Clean. The file picker shows my files as "jam1051513" etc: the app shows them properly named/tagged, nice. File picker also shows a "Segue DJ" folder, 5 items: that's the app's own, Recent list stays empty.
- 05:53 Memory cue: Skylander loaded at 03:37.4 as promised. It also remembered my hot cues A and B from the earlier play (flags on waveform). MEM tab shows it as a red bookmark pad. I never saw an empty-pad hint before that: 8 blank pads.
- 05:53:20 LIST sheet: naming and colouring cues. Found by accident; I wouldn't have looked under LIST for "rename". Named A "Drop", colour green.
- 05:53:30 Named cue: pad A goes green, shows "Drop" rather than the time. Flag goes green on the waveform. Worked first time.
- 05:53:50 BPM menu on Skylander: "Set downbeat here" tapped: no toast, no undo, nothing changed on screen as the marker was already on a .1. So I can't tell it did anything. Everywhere else the app tells you.
- 05:54 MIXER: dragged TRIM 1 and MASTER to high: LIM goes red, meters top out. Knob snaps back at centre when dragged through it, so getting 12 o'clock is easy. My drag starting near the top edge pulled the mixer sheet instead (fair enough).
- 05:54:30 "Prepare stems on load" off, load Fast Bird: label by the status becomes grey "STEMS" rather than the green-dot "AI". Tapping that grey word did nothing visible. Tapping the VOCAL pad muted the vocal and the label flipped to green "AI" at once (the track had been split before). So with the setting off, stems still work on demand. I can't explain what the grey "STEMS" means or whether it's a button.
- 05:54:50 While that happened Fast Bird's BPM on the deck changed by itself from 140.59 to 140.06 (no touch of mine beyond the pad; not on sync; the sub-label says plain "BPM"). Library says 139.7; the long-press preview said 140.1. So Fast Bird has shown FOUR tempos now. (fu-36-fast-bird-14006.png) Nobody told me which is right. It's the one track that was re-analysed. Could be a re-analysis landing; I can't tell.
- 05:55 AUTO with deck 1 at 16 s left, deck 2 unplayed: "Echo throw next, with deck 2 cued at 140 BPM. AUTO's counting down the bars." AUTO 8, 7, 5, 4... The waveform on deck 1 tapers to nothing ahead of the playhead BEFORE it's played, showing the fade it's planned. Neat. "Echo throw starting. A control you touch is yours." Crossfader moved to middle. VOCAL mute I'd set on deck 2 gets undone by AUTO without saying so, even though "a control you touch is yours" (I touched it before pressing AUTO, so maybe that's the rule). MASTER moves from 1 to 2 and the top readout goes to 140.06. AUTO stays lit afterwards, no thumbs this time.
- 05:56 NEXT again, Fast Bird (140, 10A) leading: order Severe Tire Damage 148 5A, Houston 126 5A, Gepzene 128 1A, Alone 129.5 1B, Skylander 125 11A (the only one with a lit chip), Exhilarate. Help on NEXT says "by how close the tempo is and how well the key goes". Help on KEY says neighbours go together and "lights up when it goes with the deck that's leading". So the only track the app itself lights is 5th of 6, and Houston (126, unlit) is above Gepzene and Alone, which are closer in tempo. Can't explain the order. (Everything has a tick now, so "played go last" doesn't separate them.)
- 05:56 BEAT JUMP number: tap doubles it (4 > 8). Delete from Library asks with a clear sentence: "This removes its file from Segue DJ, along with its cues, loops and stems." I cancelled. Doesn't say the original in Files is safe.
- 05:57 Guide: "Start here" at the top has LOAD AND PLAY, MIX TWO TRACKS, LET IT MIX. It's exactly the recipe I had worked out from the toast. I only found it 37 minutes in, on my second visit (first time I went straight to search). Its "press its SYNC" and "PLAY": deck shows BEAT SYNC on JOG page and SYNC on PADS page; PLAY's only a triangle.
- 05:57 Guide for tempo fader: "down is faster, as on a club deck", "a deck stays at a synced speed until you double-tap", "Slide sideways for finer control". Answers my fader puzzle IF you read it. BEAT SYNC: "The tempo fader takes it off." Same.
- 05:57:20 Sliding sideways off the tempo fader first gave about a third of the movement per point, so finer control works (58 pt down gave +4.3 where 25 pt straight gave +4.7). Not guessable; guide only. KEY lit: platter key 8B back to 1B at +4.3%, so that's how key lock reads. KEY unlit lets the key follow tempo. Clear once you've seen both.
- 05:57:50 Load onto the playing deck 2: hand icon, "Deck 2 is playing. Stop it first." Fine.
- 05:58 DJ library (XML): just "Choose the XML your DJ software exported." then the Files picker. No idea which software counts. In that picker a tap on the "Segue DJ" folder looked like it slid in and bounced back; could be the picker not the app, and I was told to stay in the app, so left it.
- 05:58 Houston (126) synced to Fast Bird at 140: goes to +11.2% with no warning, while at 05:33 a -26% got a warning toast. KEY stayed lit across loading a new track (so key lock's a deck setting; my earlier note that loading "reset" things was only about tempo and key shift). Fader cap shows a BLUE line when synced, white when not. That's the only hint besides the button.
- 05:58:20 AUTO with both decks already playing: hand, "Auto DJ brings in a stopped deck. Stop the one you want next." Exactly right. Toast stays up for 8 s or so and blocks the top of the waveform.
- 05:58:30 Tapping MASTER on deck 1 makes it master. Deck 1's BEAT SYNC un-lights and nothing is now locked to anything: both decks run at 140.06 with neither one synced. No word about it. Is deck 2 still following? Its SYNC isn't lit, so I'd say no.
- 05:58:40 Channel fader 1 down, crossfader to 1: outer meter columns (decks) stay full, the two inner ones (master) fall. So deck meters are before the fader. Not labelled anywhere on screen.
- 05:58:45 Home indicator bar flashes up at the very bottom after a crossfader drag at y=381: the crossfader lives in the iOS swipe-up area. Didn't trigger the app switcher in any of my drags though. (Tool-driven drags, so a thumb may differ.)
- 05:59 NEXT on, aiming at Houston's "2" where it had been a moment ago: loaded Gepzene instead. With NEXT on, the track on the leading deck drops off the list, so the rows jump up one under your finger. Help text does say it drops off. A real misfire, though harmless since deck 2 was stopped. To put the leading track on the other deck you have to turn NEXT off first.
- 05:59:10 Same track on both decks: allowed, works, row shows both 1 and 2 lit. Bottom sync locks. (fu-37-same-track-both-decks.png)
- 05:59:20 Fast Bird runs for 80+ bars called CHORUS ("CHORUS 1.1" right at 00:00, "CHORUS 80.2" at 02:16). Might be how it is; I can't hear. Looks wrong for a track's very first bar to be a chorus. Earlier at 05:37 I hadn't noted this label, so I can't say if re-analysing changed it.
- 05:59:30 Big CUE hold on a stopped deck: plays while held, jumps back on release. As the bubble says. The bubble's the only place that says so.
- 05:59:40 LIM: dot lights red when my channel fader is pushed up past its centre detent. Meters rarely reach the red. Nothing tells me what to do about it apart from the guide.
- 06:00 Help on LIM: "With two full tracks that's normal now and then. If it stays on, turn TRIM down: on a phone, that's under MIXER." Exactly the advice wanted. Help on METERS answered my column question (deck 1, mix L, mix R, deck 2). Crossfader help: "Double-tap for the centre."
- 06:00:30 Beat jump while synced: deck 1 skipped 8 beats (2 bars), both stayed on the same beat of the bar. Good.
- 06:00:40 SYNC on the deck that was master: lights, and MASTER at the top silently flips to 2 while deck 2's SYNC is also lit. So both say SYNC and one is master, and with both on PADS, the MASTER key isn't on screen. I can't tell who's following whom except by the small top label. (fu-38-both-sync-lit-master2.png)
- 06:00:50 Long-press on a deck's title does nothing. I never found a way to empty a deck. Not needed, just curious.
- 06:01 IN then OUT by hand, about 1.4 s apart: makes a 4-beat loop, pad 4 lights, RELOOP turns to EXIT. So it snaps to a neat length. With Q on. Good. EXIT carries on. IN lit orange till OUT: the one state where you have to guess what's next.
- 06:01:10 Fast Bird's Browse row now reads 140.1 (was 139.7 until after my re-analyse) so re-analysing did take effect, with no "done" message. "Analysing Fast Bird again." then silence.
- 06:01:15 MIX with both decks playing: hand, "A mix carries on from one playing deck. Stop the other." Two lines squeezed into a one-line pill (tops of letters touch the edge). Help is right, layout's not.
- 06:01:20 MIX with one deck playing and everything ticked: hand, "Everything else here has been played. To go round again, stop the deck and press MIX." Clear and honest. I'd never have guessed the tick matters.
- 06:01:30 Stopped both, MIX: instantly loads the first row (Exhilarate, 170) on deck 1 and PLAYS IT with no further press. "Mixing through all your tracks, 6 tracks to go. Up next: Severe Tire Damage - High Quality." So a newcomer can go from import to a full mix with one button. The first track is whatever's on top of the current sort, which here was my leftover BPM sort. Did not expect it to pick and start music by itself. A confirm wouldn't be right either; it's just a surprise.
- 06:01:40 During MIX, pressing 2 on Alone: "Up next: DJ Karda - Alone. The mix carries on." So you can overrule what's next just by loading. Lovely, and the toast says so. MIX 78 was the stems % for the next track; a split had to start again for my new choice. All 7 ticked but "6 tracks to go": so after "everything has been played" it's reset, as the earlier hand toast promised. Deck 2 showed the title on two lines ("Severe Tire / Damage - Hig...") squeezing into the header but still readable.
- 06:02 CORRECTION to my last note: MIX 78 and MIX 57 are BARS, not %. I watched it go 57 > 50 in 9 s at 170 BPM, about right for bars. It only showed "%" (MIX 4%) while splitting. So the same button shows bars with no unit or percent with a sign. I misread it twice in this session, even after reading the help.
- 06:02 SOLO D on deck 1: waveform goes all drums, other pads go dim. Clean.
- 06:02 MIX on the deck screen: one tap stops the whole mix, "Mix off. The track playing just carries on." and deck 2's chosen cue goes back to 00:01.6. No confirm. Reasonable, but it's right next to MIXER.
- 06:02:10 Search with no match: standard "No Results" screen, clear.
- 06:02:20 Hold on a playlist name: Rename / Delete. Worked out by trying. Swipe a row left: big "Deck 2" button; swipe right: "Deck 1". Nothing mentions it (I didn't find it in the guide, though I didn't search for "swipe"). Hold on a row in a playlist also gives "Remove from Playlist".
- 06:02:50 Hold and drag a row picks it up as a floating card, but with a pink "H" square, not the cover art. Dropping on the list does nothing, it snaps back and order is unchanged. So I couldn't reorder a playlist, and I don't know what dragging is for. (fu-42-drag-card-after-release.png shows the snap-back.)
- 06:03 Deck 1 ran down to under 30 s with deck 2 cued: "Deck 1 runs out in 29 s." shown on Browse. Good nudge.
- 06:03:20 AUTO from stems view, third move type: "Brake drop next, with deck 2 cued at 130 BPM." Label "AUTO 10" counted down. "Moved deck 2's fader up, to hear both." (it told me!). Deck 2 cued 3 bars early and landed on "CHORUS 1.1" exactly as deck 1 stopped. "Brake drop done. Deck 2 is on. More brake drops?" with thumbs. Deck 1 left stopped at 02:17.6 with 7.8 s unplayed, red clock frozen. (fu-43-brake-drop-done.png). Top reads MASTER 2 129.53. Good: nothing I had to do. "AUTO" in a blue lit state for a moment, then normal. Toast thumbs here sit on one line: fine. On the earlier loop-build one they wrapped.


---------------------------------------------------------------------

# FINISHED REPORT

Everything above this line is my raw notes, left as I wrote them. Where they disagree with this section, this section is right. The corrections are listed near the end.

**Session:** opened 05:19:58, last touched the app 06:06:52, so 46:54. No crash, freeze or restart. From 06:15 to 06:18 I looked at Settings and Recordings again only to confirm how I'd left them, which isn't part of the test.

**How to read the evidence**
- I can't hear anything. "Sound" means the meters moved. "Worked" means the numbers and waveforms changed.
- † means I read those words on screen and noted them, but no saved screenshot shows them. Messages vanish after a few seconds, and most had gone by the time the save ran, so several screenshots show what came just after the message.
- Times with a screenshot are good to about 5 seconds. Times in the raw notes run up to 25 s ahead, because I typed them before the clock came back, so search the logs with a margin. fu-06's deck clocks read about 34 s later than the time I noted beside it, so I think that one save ran late.
- A double-tap needs two touches closer together than my tools can manage, so anything that relies on one is untested.


## 1. Every moment I wasn't sure what to do

1. **Finding my music, 05:20:04 to 05:20:29 (25 s).** I wanted my files. I pressed IMPORT, then Music files. After a few seconds of "Opening Files..."† the picker opened on an empty Recents. The first screen had warned me about this and said to go back, so I pressed Browse and found them. fu-01, fu-02.
2. **The clock before I pressed play, 05:20:52.** Deck 1 read 00:01.6 and deck 2 read 00:00.1, so I wondered whether deck 1 had already started. I pressed play anyway. I assume it skips silence, but nothing says so. Unresolved. fu-04.
3. **LIM lit red, 05:21:14.** On my first mix a red LIM came on and I wondered if I'd done something wrong. I ignored it. I only pressed ? on it at 06:00: "With two full tracks that's normal now and then. If it stays on, turn TRIM down: on a phone, that's under MIXER."† The answer was one tap away all along. fu-05.
4. **The warning I couldn't read, about 05:25:00.** Deck 2 ran out while I was reading help, with the crossfader on it. A red warning began "Deck 2 has stopped, and deck 1 is playing with the..."† and the rest was behind the help bubble. I closed help and it had gone. I didn't read the whole sentence until the same thing happened at 05:51:15. fu-07 shows the situation but not the warning; fu-33 shows the whole sentence.
5. **Muting a stem too early, 05:26:00 (10 s).** I pressed VOCAL while the track was still splitting. The pad went dim as if muted, but the message said "That happens when the split's done. It's at 37%."† The look and the words disagree.
6. **MORE, 05:27:26 to 05:27:46 (20 s).** I wanted to see what was under it. Each press swaps the tab's name: MEM, SLICE, JUMP, SMPL, then MEM again, and the tabs beside it shift slightly. Nothing shows what comes next or how many there are. fu-28 (SMPL), fu-33 (SLICE).
7. **The order NEXT gives, 05:30:02 and 05:56:30. Never resolved.** With Skylander (125, 11A) leading I expected the best match on top. I got Houston (126, 5A), Severe Tire Damage (148, 5A), then Fast Bird (139.7, 10A), Exhilarate. Fast Bird is the only one with a lit key, and it's closer in tempo than Severe Tire Damage, yet it comes below it. The help says the order goes "by how close the tempo is and how well the key goes"†. At 05:56, with Fast Bird leading, the only lit track was fifth of six†. fu-13.
8. **The waveform icon at the top, 05:31:10 (seconds).** I expected a waveform display option. It's Recordings. The empty screen explains itself well. fu-15.
9. **The word AI, 05:32:55 to 05:36:30.** I saw "AI" with a green dot and didn't know what it meant. I only asked at 05:36:30 and ? told me it means the stems are ready†. fu-16.
10. **Halving a fast track, 05:33:30 to 05:34:10 (40 s).** I wanted 170 BPM to work against 125. Halve took the deck to 62.50 beside a master of 125, with SYNC still lit, which looked broken. The message said "Its speed hasn't changed"†, and pressing SYNC again said "Deck 2 follows at half tempo: 62 against 125."† So it does what it says. It just isn't what I hoped for. fu-16 before, fu-17 after.
11. **The number on MIX, 05:35:50 to 06:02:00, on and off.** At first I read it as how far through the mix I was. The help explains it: "Shows bars to the next move, % while the stems split, or ... while it chooses."† Even after reading that, I took "MIX 78" for a percentage at 06:01:40. I only got it when it fell by 32 in 46 s at 170 BPM, which is bars. fu-22 (42%), fu-26 (72), fu-40 (73), fu-41 (41).
12. **The tempo fader, 05:37, not settled until 05:57.** I dragged up to go faster and got -8.8%. Down is faster. The guide says so†, but I only read it 20 minutes later. fu-32 shows +3.5 with the handle below centre.
13. **SET on the sampler, 05:43:30 (10 s).** It lit with no instruction. I tried a pad and got a sheet with One shot, Gate and Loop†, none explained there. fu-28 shows the recording I then started.
14. **"A control you touch is yours", 05:34:50 to 05:55.** I tested it by pressing BASS during a move and got "That's yours for this move. Auto DJ carries on with the rest."† It held. But anything set before pressing AUTO gets undone without a word: deck 2's LOW (fu-17 then fu-18), deck 1's effect (the dot on FX in fu-19, gone in fu-20), and deck 2's VOCAL mute at 05:55†.
15. **The thumbs, 05:35:30 to 06:03:49.** "More loop builds?"† with thumbs gave no hint whether rating changes anything. The guide says: "After a move, say whether you liked it. Auto DJ leans towards what you like, though it never rules a move out. Ratings stay on your device."† I tapped where the thumb was at 05:44:56 and 06:03:34 and saw no response, so I can't say a rating ever registered.
16. **The waveform changing colour, 05:46 (2 minutes).** I thought the track had changed. It follows the pad tab: stem colours on STEMS, orange on the others. fu-31 shows both side by side. It's explained only in Settings†.
17. **The little square on BRAKE, 05:46:20.** I pressed it to find out. The deck stopped and the mix ended†. So I think the square means "this stops the deck", but I learned that by doing it. fu-31 shows the squares.
18. **SLICE, 05:51:40 (15 s).** A tap seemed to do nothing. ? says: "Plays this eighth of the bar for as long as you hold it."† fu-33 shows the pads.
19. **Set downbeat here, 05:53:50.** I pressed it and saw no message and no change†. I can't tell whether it did anything.
20. **A grey STEMS label, 05:54:30. Never resolved.** With "Prepare stems on load" off, the status beside the stem buttons read STEMS in grey instead of AI†. Tapping it did nothing. Tapping VOCAL muted the vocal and the label turned to a green AI†. fu-36 shows the after.
21. **DJ library (XML), 05:57:35.** "Choose the XML your DJ software exported."† I don't know which software counts, and I had no file to try.
22. **Who follows whom, 05:58:30 and 06:00:20. Never resolved.** I made deck 1 master and both decks stayed at 140.06 with neither one synced†. Later both showed SYNC lit, and only the small "MASTER 2" at the top separated them, because the MASTER button isn't on the pads page. fu-37, fu-38.
23. **Rows moving under my finger, 05:59:06 to 05:59:20.** I wanted Houston on deck 2 and tapped where its 2 had been. Gepzene loaded instead†. With NEXT on, the leading track's row drops off and the rest move up. The help does say this. I turned NEXT off to get the track I wanted, which fu-37 shows.
24. **Reordering a playlist, 06:02:20 to 06:03:50. Never resolved.** I held a row in Warmup and dragged. It floated as a card†, and when I let go nothing changed. fu-42 shows the same order afterwards. I found Remove from Playlist under hold†, but no way to reorder, and I still don't know what the drag is for.


## 2. How long each stage took

Each step includes the time my tools take, so a finger would be faster.

| Stage | Clock | From opening | Notes |
|---|---|---|---|
| Pressed IMPORT | 05:20:03 | 0:05 | |
| Getting music in | 05:20:29 | 0:31 | "Added 7 tracks"† |
| BPM and key shown for all 7 | by 05:20:48 | 0:50 | fu-03 |
| First track on a deck | 05:20:42 | 0:44 | |
| Reached the decks screen | 05:20:52 | 0:54 | fu-04 |
| First sound (meters moving) | 05:20:58 | 1:00 | worked out from deck 1's clock in fu-05 |
| First time two tracks played together | 05:21:08 | 1:10 | synced; from deck 2's clock in fu-05 |
| First time I moved from one to the other | 05:22:04 | 2:06 | by hand, new track's LOW down, fu-06 |
| First used ? | 05:23:23 | 3:25 | |
| First AUTO | 05:25:26 | 5:28 | too late for a real move, so it just started deck 2 (fu-08, fu-09) |
| First opened the guide | 05:28:31 | 8:33 | |
| First mix with key sync and swapped LOWs | 05:30:51 | 10:53 | fu-14 |
| First recording started | 05:31:24 | 11:26 | |
| First stem mute that worked | about 05:32:30 | about 12:30 | the try at 05:26:00 came too soon |
| First complete AUTO move | 05:34:30 to 05:35:35 | 14:32 to 15:37 | loop build, fu-18, fu-19, fu-20 |
| First whole-list MIX | 05:35:42 | 15:44 | fu-21 |
| First recording played back | about 05:49:40 | about 29:40 | both decks must be stopped (fu-27) |


## 3. What I still can't explain, and wording

**What I can't explain**
- Why NEXT puts tracks in the order it does (item 7 above).
- What the grey STEMS label means, or whether it's a button (item 20).
- Why a deck reads 00:01.6 before it has played (item 2).
- Why Fast Bird read 140.59 on the deck and 139.7 in the library before I re-analysed it, when other tracks matched (fu-23, fu-34). Which value is right, I can't tell.
- Why so many sections are called CHORUS, including the very first bar of three tracks: Gepzene (fu-04), Exhilarate (fu-16) and Fast Bird (fu-23). It may be right. I can't hear it, but it looks wrong to me.
- What decides how often a track appears in History. Alone was there twice at 05:30†, and at 06:04 there were 15 rows for 7 tracks†.
- What SPIRAL, TRANS, NOISE, CRUSH and PITCH do, and how One shot, Gate and Loop differ. Those explain themselves by ear, which I don't have.

**Wording that was wrong, misleading or no help**
- MIX with a bare number: bars with no unit, and % in the same place at other times (item 11).
- SYNC on the pads page and BEAT SYNC on the jog page are the same control (fu-38, fu-32). The guide says SYNC. The help also says "the leading deck" where the buttons say MASTER.
- AUTO, MIX and "Auto DJ" overlap. "That's yours for this move. Auto DJ carries on with the rest."† appeared while the button read MIX.
- "No clean way in. Deck 1 just started."† It doesn't say the stems weren't ready, which I believe was the reason.
- "Deck 2's 26% slower than its own 170 BPM, to follow." (fu-16) I had to read it twice.
- "A control you touch is yours." Cryptic at first, and it only covers what you touch after pressing AUTO (item 14).
- MORE > stops saying MORE after the first press (item 6).
- NEXT's help text doesn't match the order it gives (item 7).
- "This removes its file from Segue DJ, along with its cues, loops and stems."† It doesn't say whether my original in Files is safe.
- The backup message is titled "Library"†, which tells me nothing.
- "A semitone is 7 places round the key numbers, so +1 takes 1B to 8B." (fu-12) It's clear, but the first I knew of it was seeing a key jump to a number that looked unrelated.
- "Mixing through all your tracks, 2 not played yet" and "2 tracks to go" are the same fact in two forms on one screen (fu-21). Minor.
- The deck's current key isn't on the pads page at all. It's only on the small platter on the jog page (fu-14, fu-38).

**What the help did and didn't do**
- ? is excellent. Controls stop firing, it carries on working inside MIXER, and the best entries tell you what to do rather than what a thing is. For V I B D it says: "Echo just the vocal and then mute it, and the echo rings out over the rest."†
- It answered LIM, the meters (deck 1, mix left, mix right, deck 2)†, AI, the MIX number, and what a tick means. A tick means it's been on air since the app opened†. Swiping a row is under TRACK ROW†.
- The guide's "Start here" is the recipe I had pieced together from messages. It's at the top of the guide, and I opened the guide at 05:28:31, but I scrolled and searched instead and only read it at 05:56:30. That miss is partly mine. It's also two taps away behind the gear.
- It didn't help with NEXT's order, the grey STEMS label, dragging a row, which software the XML means, or how to reorder a playlist.
- The ? bubble covers the waveform you may be trying to watch, and it hid the most important warning I got (item 4).


## 4. Anything that looked broken

No crash or freeze. All of these are small. Several may be intended.

| Time | What I saw | Evidence |
|---|---|---|
| 05:20:48 | Two lines of text squeezed into a one-line pill, sitting over the COLLECTION label | fu-03 |
| about 05:25:00 | Warning hidden by the ? bubble and gone when help closed | † fu-07 shows the situation only |
| 05:28:51, 06:05:04 | Guide search bar floats over the list and the text shows through it | fu-12 |
| 05:35:30, 05:41:05, 05:44:05, 05:46:20, 06:00:55 | Other messages wrapped into a pill too small for them, touching its top and bottom edges | † |
| 05:37:49 | Fast Bird 140.59 on the deck, 139.7 in the library | fu-23, fu-34 |
| about 05:37:35 | "No clean way in"†: MIX gave up waiting for stems. They were 42% at 05:36:49 and 78% at 05:37:49 (36% a minute here), so a split takes about 2:45. MIX was started with about 1:55 left on the playing track. This is a simulator, so a real phone may differ | fu-22, fu-23 |
| about 05:41:05 | Deck 2 jumped to 00:00.2 INTRO 1.1 with its DUB knob up while MIX re-planned after my loop, then went back to 00:09.5 | † fu-25 shows the after |
| 05:41:37 | MASTER 1 148.00 at the top with deck 1's meter empty and all the sound on deck 2. Gone within about 10 s | † fu-26 shows the after |
| 05:44:19 | During a move the fourth knob read DUB on deck 1 and FILTER on deck 2, though the guide says the key sets both. Both read DUB again by 05:44:56 | fu-29, fu-30 |
| about 05:49:50 | Renaming a playing recording stopped it and lost my place; the name took a moment to change. Closing Recordings also stopped it, with no message | † |
| 05:51:02 | Moving the fader took the deck off sync with no message that I saw. The guide does say this happens | fu-32 |
| about 05:52 | "Analysing Fast Bird again."† and never a "done". New values were there by 05:54:32 (deck 140.06) and 06:00:56 (library 140.1) | fu-36, fu-39 |
| 05:53:50 | Set downbeat here: no message and no visible change | † |
| 05:54:30 | Grey STEMS label did nothing when tapped | † |
| 05:57:35 | In the XML file picker, the Segue DJ folder slid in and bounced back. Could be iOS rather than the app | † |
| about 05:58:30 | The home bar flashes after crossfader drags, as the crossfader sits in the swipe-up zone. It never opened the app switcher, but my drags come from a tool, not a thumb | † |
| 06:02:50 | Dragged row showed a pink H letter though Houston's row has cover art, and dropping it did nothing | † fu-42 shows the row and order |
| 06:03:49 | Guide search: I cleared it, typed "drag" and pressed Return. The field looked empty and the guide showed Start here. My next word produced "Dragswipe" and No Results. Could be my typing tool | † |
| 05:38 | Tapping a dim load button gave no message, though the same action at 05:33 and 05:57 gave "Deck N is playing. Stop it first." I may have missed it | † |


## 5. The best and the worst for a newcomer

**Best: it tells you the next thing at the moment you need it.** The first-load message (fu-03) points to ?, the bass tip† tells you how to mix when two tracks first overlap, and ? explains anything without firing it. I had two tracks crossfaded 2:06 after opening, without reading a manual. It also caught my mistakes: pressing AUTO with seconds left still got deck 2 going (fu-09). A close second is watching a loop build with both decks on STEMS (fu-19).

**Worst: it's hard to tell who's in charge of what.** The sharpest case is that moving the tempo fader takes a deck off sync with no message that I saw (fu-32), in an app that talks about nearly everything else. A newcomer could drift out of time and not know why. The same problem shows up elsewhere: AUTO undoes settings you made before pressing it (item 14), MIX shows a number with no unit, and both decks can show SYNC while the only sign of which one leads is a small label at the top (fu-38).


## 6. What I can't un-know

- **I know more than the brief says.** You said roughly what a DJ does. I know the 1A to 12B key numbering, quantise, slip, hot cues, loop rolls, stems, key lock, beat grids and swapping basslines. So I got through SYNC, MASTER, Q, SLIP and the pad pages faster than a true newcomer would, and I under-report confusion there. Treat my times as a best case.
- **My session was told some names before I started.** It listed a working folder called Cheeks and cache folders called cheeks-autodj and cheeks-stems. I never opened them, but the names told me to expect an auto-DJ and stem splitting. It also mentioned other agents, and the folder name fu19 suggests earlier rounds. I read no source, docs or history.
- **Things I knew from your brief:** the name Segue DJ, the music being in Files, and the phone staying on its side.
- **What the app calls itself:** Segue DJ, on the first screen, in its Files folder, and in the delete message. Its automatic mixing is "Auto DJ" in messages and the guide, AUTO for one move, MIX for a whole list. It names its moves too: loop build, echo throw and brake drop.


## Corrections to my raw notes

I checked my notes against the saved screenshots after the session. Reading those screenshots back was the only other thing I did in the folder.

1. **Screenshots that don't show the message their name suggests**, because it had gone by the save: fu-05 (bass tip), fu-07 (warning), fu-09 ("too late"), fu-19 ("Loop build starting"), fu-20 and fu-30 (thumbs), fu-23 ("No clean way in"), fu-24 (preview), fu-29 ("yours"), fu-31 ("Mix off"), fu-43 ("Brake drop done"). Those wordings rest on my notes alone.
2. **Other misleading names:** fu-34 shows only Fast Bird's 139.7 row. fu-39 shows the "Everything else here has been played" message. fu-40 is the one showing MIX started from stopped. fu-42 shows the list after I let go, not the card or the snap-back.
3. **fu-26:** my note reads as if MASTER stayed wrong after the echo throw. The saved shot 11 s later shows MASTER 2 128.00, with Houston paused and cued on deck 1. It was brief, not lasting.
4. **Fast Bird:** I wrote "four tempos". It's three: 139.7 and 140.59 before re-analysis, and 140.06 after, which the library rounds to 140.1.
5. **CHORUS on Fast Bird:** I said I couldn't tell whether re-analysis caused it. It didn't, as fu-23 shows the label before I re-analysed.
6. **Meters at 05:51:** I queried them. They're right. Deck 1's column moves and the two mix columns are empty, which matches "Nothing's coming out" (fu-33).
7. **Swiping a row:** I said I hadn't found it in the guide. It's there, under TRACK ROW†.
8. **"MIX 78 was the stems %, a split had to start again" (06:01:40):** wrong. It's bars, and no new split is shown.
9. **"Loading a new track reset my KEY":** wrong. Tempo and key shift reset, but key lock stays as set (fu-32).
10. **"Bottom sync locks" (05:59:10):** ignore it, I can't defend that sentence. fu-37 shows deck 2 synced to deck 1 on the same track.
11. **Fast Bird "had been split before" (05:54:30):** that was a guess. At last sight it was at 8% (fu-23).
12. **Stage times:** the notes say 05:21:13 and 05:22:12. The table's 05:21:08 and 05:22:04 are better, as they come from the deck clocks and capture times.


## Not tested

Anything by ear, including headphone cueing and SPLIT. Double-tap to reset. Importing a real XML file. Choosing a sample from a file. Restoring the backup or sharing a recording.


## How I left the app

- Both decks stopped: Exhilarate on 1, DJ Karda - Alone on 2 (fu-44).
- Settings changed from how I found them: SPLIT on (since about 05:49), Prepare stems on load off (since 05:54), Waveform colours RGB (since 05:48). Crossfader curve is Smooth and Match track loudness is on.
- Added: 7 tracks, playlist Warmup with 2 tracks, recording "First go" (10:34), and a backup saved to Files.
- Track edits: Skylander has hot cues A (green, "Drop") and B and a memory cue at 03:37. Severe Tire Damage has hot cue A at 2:46. Fast Bird was re-analysed. I pressed Set downbeat here on Skylander, and halved then doubled Exhilarate's reading.
- One sampler pad, pad 6 on deck 1, now holds my recording of the master.
