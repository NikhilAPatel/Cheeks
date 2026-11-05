import Foundation

/// A control, in plain words, for someone who's never touched DJ gear. What it's called on the screen, and what it does.
struct Explanation: Identifiable, Hashable {
    let title: String
    let text: String
    /// What it's looked up by, if that isn't its title: accessibility names, or a control's `help`.
    var names: [String] = []
    /// What someone might search for who doesn't know this app's word for it: it calls a transition a move.
    var alsoFoundBy: String = ""
    var id: String { text }
}

/// Every note `?` can show, and the guide in Settings is the same list. Check a note against what the control does:
/// a wrong one's worse than none.
enum Explanations {
    struct Section {
        let title: String
        let entries: [Explanation]
    }

    /// Shows on the note if a control's name isn't here. `WhatsThisTests` walks the screens looking for it.
    static let missing = "There's no note on this one yet."

    static let opening = Explanation(
        title: "?",
        text: "Touch anything to see what it does. While this is lit, your touches won't change the music: controls only explain themselves, and only keys that move between pages still work. Press ? again when you're done.",
        names: ["What does this do?"])

    static func named(_ name: String) -> Explanation? { byName[name] }

    /// What the guide in Settings shows for a search.
    static func found(_ search: String) -> [Section] {
        guard !search.isEmpty else { return sections }
        return sections.compactMap { section in
            let found = section.entries.filter {
                $0.title.localizedCaseInsensitiveContains(search) || $0.text.localizedCaseInsensitiveContains(search) || $0.alsoFoundBy.localizedCaseInsensitiveContains(search)
            }
            return found.isEmpty ? nil : Section(title: section.title, entries: found)
        }
    }

    static let byName: [String: Explanation] = {
        var all: [String: Explanation] = [:]
        for entry in sections.flatMap(\.entries) {
            for name in entry.names.isEmpty ? [entry.title] : entry.names where all[name] == nil {
                all[name] = entry
            }
        }
        return all
    }()

    private static let holdOrTap = "Tap to leave it on, or hold it for as long as you want."

    static let sections: [Section] = [
        // It said what every control does, and nowhere how to mix two tracks. Not looked up by a control.
        Section(title: "Start here", entries: [
            Explanation(title: "LOAD AND PLAY", text: "BROWSE opens your music. Press 1 or 2 on a track to put it on that deck. DECKS takes you back, and PLAY starts it.",
                        alsoFoundBy: "how do i begin start beginner first track"),
            Explanation(title: "MIX TWO TRACKS", text: "With one deck playing, load the other and press its SYNC so the beats match. Press PLAY, turn its LOW down and bring the crossfader across. Then swap the two LOW knobs as a new section starts.",
                        alsoFoundBy: "how do i transition blend crossfade fade by hand manually"),
            Explanation(title: "LET IT MIX", text: "With one deck playing and a track on the other, press AUTO for one transition. MIX in the browser does a whole list. To see how it's done, put both decks on STEMS.",
                        alsoFoundBy: "how do i transition blend automix automatic playlist set"),
        ]),
        Section(title: "Top bar", entries: [
            opening,
            Explanation(title: "BROWSE / DECKS", text: "Your music: load tracks, search them and build playlists. It says DECKS while that's open, and takes you back.", names: ["Browser"]),
            Explanation(title: "REC", text: "Records the mix, with a list of the tracks you played. While it's on, it shows the time and how many tracks so far. Press it again to stop and save, and it checks first.", names: ["Record", "Stop recording"]),
            Explanation(title: "RECORDINGS", text: "The mixes you've recorded, to play, share, rename or delete, each with its tracklist.", names: ["Recordings"]),
            Explanation(title: "SETTINGS", text: "The crossfader's curve, loudness matching, stems, waveform colours, haptics, recording format and backups, and a list of all these notes.", names: ["Settings"]),
            Explanation(title: "MASTER TEMPO", text: "The tempo of the deck that's leading. A deck with BEAT SYNC on follows it.", names: ["Master tempo"]),
        ]),
        Section(title: "Waveforms", entries: [
            Explanation(title: "WAVEFORM", text: "The track going past, and the line is what you're hearing. Drag to move, pinch to zoom, double-tap to reset it. Colours are lows, mids and highs, or stems. The number counts bars in the section. UP's a build-up, DOWN a breakdown.", names: ["Waveform"]),
            Explanation(title: "OVERVIEW", text: "The whole track. Touch it to go to that point. While the deck's playing, hold for a moment, so a stray touch doesn't move it. The flags are your cues, and the colours its sections.", names: ["Overview"]),
            Explanation(title: "BEAT BLOCKS", text: "Four blocks for each deck, one lit for each beat of the bar, mirrored about the middle, so you can see whether the two line up. Red is the first beat. The scale in the middle shows how far apart they are.", names: ["Phase strip"]),
        ]),
        Section(title: "Deck", entries: [
            Explanation(title: "TRACK", text: "What's on this deck and who it's by, or how far its stems have got. On an empty deck, touching this opens the browser.", names: ["Track details"]),
            Explanation(title: "TIME", text: "Time left, and time played underneath. It goes red for the last 30 seconds.", names: ["Time"]),
            Explanation(title: "BPM", text: "The tempo this deck is playing at. Touch it to fix the beats if they're off: double or halve what the track reads as, shift the grid, or set where the 1 is. The list of cues and loops is there too.", names: ["Beat grid"]),
            Explanation(title: "JOG WHEEL", text: "Touch the record to scratch. Turn the metal ring to push a playing track ahead or hold it back for a moment, to get it in time. On a stopped deck, any touch moves through the track.", names: ["Jog wheel"]),
            Explanation(title: "CUE", text: "On a stopped deck, marks this spot, and holding it plays from here until you let go. On a playing deck, goes back to the mark and stops.", names: ["Cue"]),
            Explanation(title: "PLAY", text: "Starts and stops the track.", names: ["Play", "Pause"]),
            Explanation(title: "TEMPO FADER", text: "How fast this deck plays. Down is faster, as on a club deck. It clicks at the centre, the track's own speed, and a deck stays at a synced speed until you double-tap for that. Slide sideways off it for finer control.", names: ["Tempo"]),
            Explanation(title: "±6 ±10 ±16 WIDE", text: "How far the tempo fader reaches, in percent. Smaller ranges are easier to set exactly. Each press moves to the next that can hold the speed the deck's at.", names: ["Tempo range"]),
            Explanation(title: "TEMPO %", text: "How far this deck is from the track's own speed.", names: ["Tempo percent"]),
            Explanation(title: "BEAT SYNC", text: "Locks this deck to the other's tempo and beat. Started from stopped, its bars line up too. The tempo fader takes it off. If half or double is nearer, it goes there and says so. The only deck playing has nothing to follow.", names: ["BEAT SYNC", "SYNC"]),
            Explanation(title: "MASTER", text: "The deck that leads, which a synced deck follows. Press it to make this one lead. A stopped deck can't lead, so the first one to start playing takes over.", names: ["MASTER"]),
            Explanation(title: "BEAT JUMP", text: "The arrows move the track back or forward by the number between them, and it stays in time. Press the number to change it. The JUMP pads have 1 beat either way.", names: ["BEAT JUMP", "Jump back", "Jump forward"]),
            Explanation(title: "JUMP SIZE", text: "How many beats the arrows beside it jump: 1, 2, 4, 8, 16 or 32. Each press moves to the next.", names: ["Jump size"]),
            Explanation(title: "Q", text: "Quantize. With it on, cues, loops and jumps land exactly on the beat, however loosely you press.", names: ["Q"]),
            Explanation(title: "SLIP", text: "With it on, the track keeps running silently while you loop, scratch or reverse. When you stop, it picks up where it would have got to, so you're still in time.", names: ["SLIP"]),
            Explanation(title: "KEY", text: "Key lock. With it on, changing the tempo leaves the track in the same key. With it off, faster is also higher, like a record.", names: ["KEY"]),
            Explanation(title: "REV", text: "Plays the track backwards, until you press it again.", names: ["REV"]),
            Explanation(title: "KEY − +", text: "Moves the track's key a semitone at a time, without changing its tempo. The number is how far it's moved. A semitone is 7 places round the key numbers, so +1 takes 1B to 8B.", names: ["Key down", "Key up", "Key shift"]),
            Explanation(title: "KEY SYNC", text: "Moves this track by the fewest semitones to a key that goes with the leading deck.", names: ["KEY SYNC"]),
            Explanation(title: "JOG / PADS", text: "Swaps this deck between its pads and its jog wheel, which has the tempo fader, Q, SLIP and the key controls beside it.", names: ["Deck page"]),
        ]),
        Section(title: "Pad pages", entries: [
            Explanation(title: "CUE PADS", text: "Hot cues A to H: marks in the track you can go straight to. They're saved with the track.", names: ["Cue pads"]),
            Explanation(title: "MEM PADS", text: "Cues and loops saved with this track, as many as you like, a page at a time. One touch goes there.", names: ["Mem pads"]),
            Explanation(title: "LOOP PADS", text: "Loops from a quarter of a beat to 32 beats. Press a pad to start one, and again to leave it.", names: ["Loop pads"]),
            Explanation(title: "ROLL PADS", text: "Hold a pad to repeat a tiny piece of the track. Let go and it carries on from where it would have got to.", names: ["Roll pads"]),
            Explanation(title: "SLICER PADS", text: "The bar you're in, cut into eight. Hold a pad to play that slice. Let go and the track's back in time.", names: ["Slicer pads"]),
            Explanation(title: "JUMP PADS", text: "Back on the top row and forward on the bottom, by 1, 4, 16 or 32 beats.", names: ["Jump pads"]),
            Explanation(title: "STEMS PADS", text: "The track split into vocals, instruments, bass and drums, to mute any of them or play just one. The split takes a while the first time, and is kept. Colours over the tab show which are in while some aren't.", names: ["Stems pads"]),
            Explanation(title: "FX PADS", text: "Twelve effects that stay on the beat, up to three at once. Tap to leave one on, or hold it. While holding, slide up and down for how strong, left and right for how long. A blue dot on the tab means one's on.", names: ["Fx pads"]),
            Explanation(title: "SAMPLE PADS", text: "Eight sounds to play over the mix. Press SET and then a pad to put your own on it: a file, a deck's loop, or a recording of the mix.", names: ["Sample pads"]),
            Explanation(title: "DEL", text: "Press this and then a pad to remove that cue or loop. You get an Undo.", names: ["DEL"]),
        ]),
        Section(title: "Cues and loops", entries: [
            Explanation(title: "HOT CUE", text: "On an empty pad, marks where the track is. On a lit pad, goes straight there. To remove one, press DEL and then the pad.", names: ["Hot cue"]),
            Explanation(title: "MEMORY PAD", text: "A saved cue or loop. One touch goes there. An empty pad's waiting for SAVE CUE or SAVE LOOP.", names: ["Memory pad"]),
            Explanation(title: "SAVE CUE", text: "Saves where the deck is as a memory cue, kept with the track.", names: ["SAVE CUE"]),
            Explanation(title: "SAVE LOOP", text: "Saves the loop that's set, kept with the track.", names: ["SAVE LOOP"]),
            Explanation(title: "PAGE", text: "Moves through the pages of saved cues and loops.", names: ["Previous page", "Next page"]),
            Explanation(title: "LIST", text: "Every saved cue and loop on this track, to name, colour or remove them, and to choose a loop that waits when the track loads.", names: ["LIST"]),
            Explanation(title: "IN", text: "Marks where a loop starts. Press OUT to close it.", names: ["IN"]),
            Explanation(title: "OUT", text: "Marks where a loop ends, and it starts going round.", names: ["OUT"]),
            Explanation(title: "RELOOP / EXIT / ARMED", text: "RELOOP goes back into the last loop. While a loop's running it says EXIT, and leaves the loop. ARMED means there's a loop up ahead, which will catch the deck when it gets there.", names: ["RELOOP"]),
            Explanation(title: "LOOP SIZE", text: "Starts a loop this many beats long from here, or leaves it if it's running. The arrows beside it halve and double it.", names: ["Beat loop"]),
            Explanation(title: "HALVE LOOP", text: "Makes the loop half as long.", names: ["Halve loop"]),
            Explanation(title: "DOUBLE LOOP", text: "Makes the loop twice as long.", names: ["Double loop"]),
            Explanation(title: "LOOP PAD", text: "Starts a loop this many beats long. Press it again to leave it.", names: ["Loop pad"]),
            Explanation(title: "ROLL PAD", text: "Repeats this many beats for as long as you hold it. The track keeps time underneath and carries on from there when you let go.", names: ["Roll pad"]),
            Explanation(title: "SLICE", text: "Plays this eighth of the bar for as long as you hold it. The track keeps time underneath and comes back in time when you let go.", names: ["Slice"]),
            Explanation(title: "JUMP PAD", text: "Moves the track back or forward this many beats, straight away.", names: ["Jump pad"]),
        ]),
        Section(title: "Stems", entries: [
            Explanation(title: "STEM", text: "One part of the track. Tap to mute it or bring it back, and slide up and down to set its level.", names: ["Stem"]),
            Explanation(title: "SOLO", text: "Plays only this part. Press it again to go back to what you had.", names: ["Solo"]),
            Explanation(title: "ACAPELLA / VOX", text: "Just the vocal.", names: ["ACAPELLA", "VOX"]),
            Explanation(title: "NO VOCAL / INST", text: "Everything except the vocal.", names: ["NO VOCAL", "INST"]),
            Explanation(title: "BEAT", text: "Just the drums and bass.", names: ["BEAT"]),
            Explanation(title: "ALL", text: "Every part back on.", names: ["ALL"]),
            Explanation(title: "STEM STATUS", text: "How the split's going. AI with a green dot means it's ready. ≈EQ is a rougher split by frequency, used when the full one isn't available.", names: ["Stem status"]),
        ]),
        Section(title: "Effects", entries: [
            Explanation(title: "ECHO", text: "Repeats what's playing, in time, dying away. " + holdOrTap, names: ["Echo"]),
            Explanation(title: "PING PONG", text: "An echo that bounces between left and right. " + holdOrTap, names: ["Ping Pong"]),
            Explanation(title: "SPIRAL", text: "An echo that hardly dies away, and bends downwards as it goes on. " + holdOrTap, names: ["Spiral"]),
            Explanation(title: "REVERB", text: "Puts the track in a big room. " + holdOrTap, names: ["Reverb"]),
            Explanation(title: "FLANGER", text: "A sweeping, jet-plane whoosh. " + holdOrTap, names: ["Flanger"]),
            Explanation(title: "PHASER", text: "A softer, swirling sweep. " + holdOrTap, names: ["Phaser"]),
            Explanation(title: "FILTER", text: "Sweeps a filter back and forth, in time. " + holdOrTap, names: ["Filter"]),
            Explanation(title: "TRANS", text: "Chops the sound on and off, in time. " + holdOrTap, names: ["Trans"]),
            Explanation(title: "CRUSH", text: "Breaks the sound up into rough digital grit. " + holdOrTap, names: ["Crush"]),
            Explanation(title: "ROLL", text: "Repeats a short piece of the track, in time. " + holdOrTap, names: ["Roll"]),
            Explanation(title: "BRAKE", text: "Slows the track to a stop, like a turntable switched off. The square on the pad says so: the deck stays stopped until you press PLAY, and a mix ends with it.", names: ["Brake"]),
            Explanation(title: "BACKSPIN", text: "Spins the track backwards, like a hand on the record, and stops it. The square on the pad says so: the deck stays stopped until you press PLAY, and a mix ends with it.", names: ["Backspin"]),
            Explanation(title: "EFFECT LENGTH", text: "How long each repeat or sweep lasts, in beats.", names: ["Shorter", "Longer"]),
            Explanation(title: "DEPTH", text: "How strong the effect is.", names: ["DEPTH"]),
            Explanation(title: "V I B D", text: "Which parts of the track the effect goes on: vocals, instruments, bass and drums. Echo just the vocal and then mute it, and the echo rings out over the rest.", names: ["FX stems"]),
            Explanation(title: "OUT", text: "Ends the track on its own echo: on the next beat it cuts, and only the repeats are left. Press it again to bring the track back.", names: ["Echo out"]),
        ]),
        Section(title: "Sampler", entries: [
            Explanation(title: "SAMPLE PAD", text: "Plays this sound. REC and a number is a piece of the mix you recorded onto this pad. To change what's on it, press SET and then the pad.", names: ["Sampler pad"]),
            Explanation(title: "SET", text: "Press this and then a pad to change what's on it: a file, a deck's loop, or a recording of the mix. A pad can be a one shot, a loop, or a gate, which plays only while you hold it.", names: ["SET"]),
            Explanation(title: "Q", text: "With it on, a pad starts on the leading deck's beat rather than straight away.", names: ["Sampler Q"]),
            Explanation(title: "VOLUME", text: "How loud the sampler is.", names: ["VOLUME"]),
            Explanation(title: "STOP", text: "Stops every sound the sampler's playing.", names: ["STOP"]),
            Explanation(title: "STOP RECORDING", text: "Ends the recording of the mix going onto this pad.", names: ["Stop sampling"]),
        ]),
        Section(title: "Mixer", entries: [
            Explanation(title: "TRIM", text: "This deck's level going in, ahead of its fader. Turn it down if its meter reaches red.", names: ["TRIM"]),
            Explanation(title: "HI", text: "The highs: hi-hats and sparkle. All the way left removes them. Double-tap for the centre.", names: ["HI"]),
            Explanation(title: "MID", text: "The middle: vocals and most instruments. All the way left removes it. Double-tap for the centre.", names: ["MID"]),
            Explanation(title: "LOW", text: "The lows: kick and bass. All the way left removes them, and that's how you stop two basslines fighting. Double-tap for the centre.", names: ["LOW"]),
            Explanation(title: "FILTER KNOB", text: "Off at the centre. With FILTER chosen, left leaves only the lows and right only the highs. The key with the arrows, under MIXER on a phone, gives it other effects, and its name changes. Auto DJ can borrow it for a filter.", names: ["Color knob"]),
            Explanation(title: "FILTER ↻", text: "Chooses what both FILTER knobs do: FILTER, DUB (echo), SPACE (reverb), NOISE, CRUSH or PITCH. Each press moves to the next.", names: ["Color effect"]),
            Explanation(title: "CUE", text: "Sends this deck to your headphones, so you can hear it before anyone else does. It takes SPLIT and a splitter cable, with the cue in your right ear. One output, like AirPods, can only play the mix.", names: ["Cue channel"]),
            Explanation(title: "CHANNEL FADER", text: "This deck's volume in the mix.", names: ["Channel fader"]),
            Explanation(title: "CROSSFADER", text: "Slides the mix between deck 1 and deck 2. In the middle, you hear both. Double-tap for the centre.", names: ["Crossfader"]),
            Explanation(title: "MASTER", text: "The volume of the main output. It doesn't change the level of a recording.", names: ["Master volume"]),
            Explanation(title: "CUE/MST", text: "What's in your headphones. Turned to the left, the decks you've cued. Turned to the right, the mix. Between, some of each. It needs SPLIT on.", names: ["CUE/MST"]),
            Explanation(title: "LEVEL", text: "The headphone volume. It needs SPLIT on.", names: ["LEVEL"]),
            Explanation(title: "SPLIT", text: "For a splitter cable with speakers on one side and headphones on the other: the mix in the left ear and your cue in the right.", names: ["SPLIT"]),
            Explanation(title: "AUTO", text: "Mixes the playing deck into the other, bringing parts in and out, which STEMS shows. Shows bars to go, % while the stems split, or … as it chooses. A control you touch is yours. Press to stop. MIX in the browser does a whole list.", names: ["Auto DJ"], alsoFoundBy: "transition blend automix"),
            Explanation(title: "MIX", text: "A mix through a list, started from the browser, which shows which list and what's left. Shows bars to the next move, % while the stems split, or … while it chooses. A control you touch is yours. Press to stop.", names: ["Mix on the mixer"], alsoFoundBy: "transition blend automix"),
            Explanation(title: "MIXER", text: "The mixer controls with no room here: TRIM, MASTER, the headphone controls, SPLIT and the FILTER knob's effects.", names: ["More mixer controls"]),
            Explanation(title: "LIM", text: "Lights when the mix is so loud that the limiter's holding it back. With two full tracks that's normal now and then. If it stays on, turn TRIM down: on a phone, that's under MIXER.", names: ["LIM"]),
            Explanation(title: "METERS", text: "How loud things are: deck 1, the mix left and right, and deck 2. Red means too hot.", names: ["Meters"]),
        ]),
        Section(title: "Auto DJ's moves", entries: [
            Explanation(title: "BASS SWAP", text: "A long blend. The new track's drums creep in under the old one, everything stops for one beat, and the new track lands whole on the downbeat."),
            Explanation(title: "LOOP BUILD", text: "The old track folds into smaller and smaller loops as it rises, stops for one beat, and the new track's drop lands."),
            Explanation(title: "ECHO THROW", text: "The old track's last beats go into an echo, it cuts, and the new track lands under the repeats. When nothing else works, it's an echo out, with the new track starting afterwards."),
            Explanation(title: "BRAKE DROP", text: "The old track slows to a stop like a turntable switched off, and the new one slams in. It's for tracks nothing else can join."),
            Explanation(title: "VOCAL TEASE", text: "The new track's vocal rides over the old track's instrumental for 8 bars, and then the new track's drop lands."),
            Explanation(title: "VOCAL RIDE", text: "On a downbeat the whole track changes under the singer. The old vocal carries on over the new track's instrumental, and then goes up an echo."),
            Explanation(title: "THUMBS UP / DOWN", text: "After a move, say whether you liked it. Auto DJ leans towards what you like, though it never rules a move out. Ratings stay on your device."),
        ]),
        Section(title: "Browser", entries: [
            Explanation(title: "IN KEY", text: "Shows only tracks in a key that goes with the deck that's leading.", names: ["In key filter"]),
            Explanation(title: "±6% BPM", text: "Shows only tracks within 6% of the leading deck's tempo, which can be matched without sounding wrong.", names: ["BPM filter"]),
            Explanation(title: "NEXT", text: "Puts the list in a good order to play from the leading deck, by how close the tempo is and how well the key goes. That deck's own track drops off the list while it's on, and what's been played, with a tick, goes last.", names: ["Best next first"]),
            Explanation(title: "MIX", text: "Auto DJ through the list on screen, in the order showing. With one of its tracks playing it goes on from there, then back for what's above it with no tick. Otherwise it plays the lot. AUTO does one move. Press again to stop.", names: ["Mix through this list", "Stop the mix"]),
            Explanation(title: "MIX LINE", text: "Which list the mix is going through, and how many tracks are left. It's only here while a mix is on.", names: ["Mix line"]),
            Explanation(title: "IMPORT", text: "Adds music from the Files app, or a library exported from your DJ software. If Files opens on an empty folder, go back from there to find your music.", names: ["IMPORT"]),
            Explanation(title: "PLAYLISTS", text: "Chooses which list you're looking at, and makes new ones. To put a track in one, press and hold the track. To rename or delete one, press and hold it in the sidebar, or choose it and open this menu on an upright phone.", names: ["Playlists"]),
            Explanation(title: "KEY", text: "The track's key: A is minor and B is major. The same number, or numbers next to each other, with 12 next to 1, go together. It lights up when it goes with the deck that's leading.", names: ["Track key"], alsoFoundBy: "camelot " + (1...12).map { "\($0)A \($0)B" }.joined(separator: " ")),
            Explanation(title: "TRACK ROW", text: "A track in this list. Press 1 or 2 to load it on that deck, swipe it either way to do the same, or hold it for more. A tick means it's been on air since the app opened.", names: ["Track row"]),
            Explanation(title: "1 / 2", text: "Loads this track onto that deck. A playing deck won't take one, so stop it first.", names: ["Load on deck"]),
            Explanation(title: "PREVIEW", text: "Touch a track's small waveform to hear it, or its picture on a phone: in the cue ear with SPLIT on, or over the mix without, though never on a recording. Holding the track offers it too.", names: ["Preview", "Stop preview"]),
        ]),
    ]
}
