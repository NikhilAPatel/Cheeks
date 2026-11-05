import Foundation
import Observation

/// The AUTO key: plans a transition from the deck that's playing to the one that's waiting, auditions it offline, waits
/// for the right bar, and performs it through the same controls a person would use. Touching a control takes it back.
@MainActor
@Observable
final class AutoDJ {
    enum Phase: Equatable {
        case idle
        /// Both decks are ready to go except for their stems.
        case waitingForStems
        case planning
        /// There's no move to make, so the waiting track starts when this one's done.
        case waitingForTheEnd
        /// It's chosen its moment, and the audio core will start the clock when the deck gets there.
        case armed(TransitionMove)
        case running(TransitionMove)
    }

    /// A list being mixed from one end to the other.
    struct MixSet: Equatable {
        var name: String
        /// What's still to come, not counting what's on the decks.
        var queue: [UUID]
        /// The deck the audience is hearing.
        var onAir: Int
        /// Loaded onto the waiting deck, or on its way there.
        var next: UUID?
        /// The first track's still to be started.
        var needsStart = false
        /// The track a plan's been asked for, so it's only asked once.
        var plannedFor: UUID?
        /// How many times a plan's failed from where it was looking, so it looks further back in the track each time.
        var stepsBack = 0
        /// It's looked as far back as it can, and an echo out is what's left.
        var lastResort = false
        /// Something's just been said that matters more than what's up next, which the deck shows anyway.
        var keepsQuietAboutNext = false
        /// It's said that this is the last one.
        var saidItsTheLast = false
        /// How many tracks it's got, said again with what's up next, which comes straight after and would take its place.
        var opening: String?

        /// What's left to come in, counting what's waiting on the other deck.
        var tracksToGo: Int { queue.count + (next == nil ? 0 : 1) }

        /// For the browser. These were only said once, for a few seconds, and then nothing showed which list was on or what was left.
        var line: String {
            tracksToGo == 0 ? "Mixing through \(name). This is the last track." : "Mixing through \(name), \(Format.count(tracksToGo, "track")) to go."
        }
    }

    /// How a move that's been cut short is wrapped up, once the audio core has let go of the controls.
    private enum Ending {
        /// Everything stays where it is, apart from what the screen can't show.
        case decksAreYours
        /// The new deck's been stopped while the old one was still what people could hear.
        case oldCarriesOn
        /// The old deck's gone, and the new one's on, started now if the score hadn't got to it yet.
        case oldStops(startNew: Bool)
    }

    /// What getting ready for a move changed, so that a move that never happens leaves no trace.
    @MainActor
    private struct Prepared {
        @MainActor
        struct Settings {
            let tempo, tempoRange: Double
            let keyLock, syncOn: Bool
            let keyShift: Int
            let filter, eqLow, eqMid, eqHigh: Float
            let position: Double

            init(_ deck: Deck) {
                position = deck.position
                tempo = deck.tempo
                tempoRange = deck.tempoRange
                keyLock = deck.keyLock
                syncOn = deck.syncOn
                keyShift = deck.keyShift
                filter = deck.filter
                eqLow = deck.eqLow
                eqMid = deck.eqMid
                eqHigh = deck.eqHigh
            }
        }

        let before: Settings, after: Settings
        /// Undoes opening the channel, which waits for the clock to start.
        var undoMixer: () -> Void = {}
        /// Someone's sent the deck somewhere since, and that's where it stays.
        var movedByHand = false

        /// Puts back whatever's still as getting ready left it. What someone's changed since is theirs.
        func putBack(on deck: Deck) {
            if deck.tempoRange == after.tempoRange { deck.tempoRange = before.tempoRange }
            if deck.keyLock == after.keyLock { deck.keyLock = before.keyLock }
            if deck.keyShift == after.keyShift { deck.keyShift = before.keyShift }
            if deck.tempo == after.tempo { deck.setTempo(before.tempo) }
            if deck.filter == after.filter { deck.filter = before.filter }
            if deck.eqLow == after.eqLow { deck.eqLow = before.eqLow }
            if deck.eqMid == after.eqMid { deck.eqMid = before.eqMid }
            if deck.eqHigh == after.eqHigh { deck.eqHigh = before.eqHigh }
            if deck.syncOn == after.syncOn { deck.syncOn = before.syncOn }
            undoMixer()
        }
    }

    private(set) var phase: Phase = .idle
    /// Bars until the move starts, while it's armed.
    private(set) var barsToGo = 0
    private(set) var mixSet: MixSet?
    /// Starts a track loading on a deck, and says what it's called, or nil if it can't.
    @ObservationIgnored var loadTrack: ((UUID, Deck) -> String?)?
    /// The first bar a planned move may start on. Pressing AUTO wants it soon, so this is only set for a set.
    @ObservationIgnored private var leaveFrom = 0
    /// Tracks stems have been asked for during this set, so a failed split isn't tried over and over.
    @ObservationIgnored private var askedForStems = Set<UUID>()
    /// How moves have been rated, which leans on what's chosen next.
    @ObservationIgnored var ratings = TransitionRatings()
    /// Asks what someone thought of a move that's just ended: the move, and the tracks it went from and to.
    @ObservationIgnored var askForRating: ((TransitionMove, String, String) -> Void)?
    /// Moves it won't choose, for tests that are about one in particular.
    @ObservationIgnored var leavesOut = Set<TransitionMove>()
    /// Whether that's still on screen, where a passing message would take its place.
    @ObservationIgnored var isAskingForRating: () -> Bool = { false }
    /// A plan takes the crossfader to the middle, which it says if it moves it. It's been reported three rounds running as moving by itself.
    @ObservationIgnored var crossfaderIsCentred: () -> Bool = { true }
    /// Whether a track's been on air since the app opened, so a mix doesn't go back for it.
    @ObservationIgnored var hasBeenHeard: (UUID) -> Bool = { _ in false }
    /// Opens a crossfader that's shut on this deck, and gives back how to undo that. Nil if the deck can be heard already.
    @ObservationIgnored var openCrossfader: (Deck) -> (() -> Void)? = { _ in nil }
    /// Whether the crossfader's turned well away from this deck.
    @ObservationIgnored var crossfaderIsAway: (Deck) -> Bool = { _ in false }
    /// What the FILTER key's set to, which the knobs go back to once a move's finished with them.
    @ObservationIgnored var chosenColorFX: () -> ColorEffect = { .filter }

    @ObservationIgnored private let core: OpaquePointer
    @ObservationIgnored private let decks: [Deck]
    @ObservationIgnored private let say: (String, StatusKind) -> Void
    /// Opens the channel for a deck that's coming in, and gives back how to undo that.
    @ObservationIgnored private let prepareMixer: (Deck) -> (() -> Void)
    @ObservationIgnored private var planning: Task<Void, Never>?
    @ObservationIgnored private var outgoing: Deck?
    @ObservationIgnored private var incoming: Deck?
    @ObservationIgnored private var score: TransitionScore?
    /// Each control the score moves, and the beat it starts moving, so the screen only follows ones it's reached.
    @ObservationIgnored private var lanes: [(deck: Deck, kind: CheeksAutoKind, index: Int, from: Double)] = []
    /// The moves played lately, oldest first, so the same few don't keep coming up.
    @ObservationIgnored private var recentMoves: [TransitionMove] = []
    @ObservationIgnored private var coreIsRunning = false
    @ObservationIgnored private var prepared: Prepared?
    /// The old deck of a move that was stopped part-way, which is still as the score left it.
    /// What a stopped move left on the screen, for pressing the key again to clear. A deck that was playing when it stopped
    /// can be either of the two, and whichever gets mixed out of next, it mustn't still be on the move's stems and EQ.
    @ObservationIgnored private var leftBehind: [(deck: Deck, wasOld: Bool)] = []
    /// A move's been cut short: how it'll end, and what to say when it has.
    @ObservationIgnored private var ending: (how: Ending, message: String)?
    /// Ticks since then. With the audio stopped the core never lets go, and there's nothing to wait for.
    @ObservationIgnored private var ticksEnding = 0
    @ObservationIgnored private var plannedA: UUID?
    @ObservationIgnored private var plannedB: UUID?
    /// Where a track has nothing left to hear.
    @ObservationIgnored private var silentFrom: (track: UUID, frame: Double)?
    @ObservationIgnored private var saidItsStarting = false
    /// It's said a control someone took is theirs, which only needs saying once a move.
    @ObservationIgnored private var saidItsYours = false
    /// Undoes opening a crossfader that was shut on the playing deck, if nothing comes of it.
    @ObservationIgnored private var earlyCrossfader: (() -> Void)?

    init(core: OpaquePointer, decks: [Deck], say: @escaping (String, StatusKind) -> Void, prepareMixer: @escaping (Deck) -> (() -> Void)) {
        self.core = core
        self.decks = decks
        self.say = say
        self.prepareMixer = prepareMixer
        for deck in decks {
            let index = Int32(deck.index)
            deck.onManualControl = { [weak self, weak deck] kind, control in
                cheeks_engine_auto_release(core, index, Int32(kind.rawValue), Int32(control))
                if let self, let deck { self.noticeTaken(deck, kind, control) }
            }
            deck.onMovedByHand = { [weak self, weak deck] in
                if let self, let deck { self.noticeMoved(deck) }
            }
            deck.onLoopChangedByHand = { [weak self, weak deck] in
                if let self, let deck { self.noticeLoopChanged(deck) }
            }
        }
    }

    var isActive: Bool { phase != .idle || mixSet != nil }

    /// What the key says.
    var legend: String {
        let name = mixSet == nil ? "AUTO" : "MIX"
        switch phase {
        // A mix with no plan yet is waiting for something, like a loop to end, and shouldn't look as if it's just sitting there.
        case .idle:
            guard let mixSet else { return name }
            // The last track on the list has nothing to wait for, and "MIX…" read as if it was still thinking.
            if mixSet.next == nil, mixSet.queue.isEmpty, !mixSet.needsStart { return name }
            return stemsPercent.map { "\(name) \($0)%" } ?? "\(name)…"
        // The clock starts a couple of bars ahead of the move, and it's still counting those.
        case .running: return barsToGo > 0 ? "\(name) \(barsToGo)" : name
        // "AUTO…" read like a clipped label for nearly 4 minutes, with nothing tying it to the percentage on the deck.
        case .waitingForStems: return stemsPercent.map { "\(name) \($0)%" } ?? "\(name)…"
        case .planning, .waitingForTheEnd: return "\(name)…"
        case .armed: return "\(name) \(barsToGo)"
        }
    }

    /// How far along the stems are that it's waiting for: the deck with furthest to go.
    private var stemsPercent: Int? {
        let waitingOn = decks.compactMap { deck -> Double? in
            guard deck.trackMap == nil, case .separating(let progress) = deck.stemStatus else { return nil }
            return progress ?? 0
        }
        return waitingOn.min().map { Int($0 * 100) }
    }

    func press() {
        let wasSet = mixSet != nil
        mixSet = nil
        switch phase {
        case .idle:
            if wasSet {
                undoEarlyCrossfader()
                say("Mix off. The track playing just carries on.", .info)
            } else {
                begin()
            }
        case .waitingForStems, .waitingForTheEnd, .planning, .armed:
            cancel()
            say(wasSet ? "Mix off. The track playing just carries on." : "Auto DJ off.", .info)
        case .running:
            let stopped = wasSet ? "Mix off." : "Auto DJ stopped."
            // Once the new track's taken over there's nothing left to take over from: the old one was on its way out.
            if let incoming, cheeks_engine_auto_beat(core) >= score?.handover ?? .infinity {
                endEarly(.oldStops(startNew: false), "\(stopped) Deck \(incoming.index + 1) is on.")
            } else {
                // On a phone's jog page there's no EXIT to show it, and only the shading says so.
                let looping = outgoing?.renderer.loopActive == true ? " Deck \((outgoing?.index ?? 0) + 1) is still looping." : ""
                endEarly(.decksAreYours, "\(stopped) The decks are yours.\(looping)")
            }
        }
    }

    // MARK: Mixing through a list

    /// Mixes through these tracks in order. If a deck's playing, it carries on from that, and from that track's place
    /// in the list if it's on it, and then comes back for what's above it. Otherwise it starts from the top.
    func startSet(named name: String, tracks: [UUID]) {
        let playing = decks.filter(\.isPlaying)
        guard playing.count <= 1 else {
            // Not "the one you want next": the list decides that, and the stopped deck's track makes way for it.
            say("A mix carries on from one playing deck. Stop the other.", .refused)
            return
        }
        var queue = tracks
        if let air = playing.first {
            let id = air.track?.id
            // The note says the whole list, and from row 4 of 5 a first-time user got two tracks and then nothing.
            if let id, let here = queue.firstIndex(of: id) { queue = Array(queue[(here + 1)...]) + queue[..<here] }
            let others = queue.filter { $0 != id }
            // What's been played already doesn't come round again, whichever side of this track it's on.
            queue = others.filter { !hasBeenHeard($0) }
            guard !queue.isEmpty else {
                if others.isEmpty {
                    say("There's nothing left in \(name) to mix into.", .refused)
                } else {
                    say("You've played the rest of \(name). To go round again, stop the deck and press MIX.", .refused)
                }
                return
            }
        } else {
            guard queue.count >= 2 else {
                // A search or a filter can be hiding the rest, with the sidebar saying there's plenty.
                say("A mix needs at least two tracks, and \(queue.isEmpty ? "none are" : "only one's") showing.", .refused)
                return
            }
        }
        if phase != .idle { cancel() }
        askedForStems = []
        let count = Format.count(queue.count, "track")
        if let air = playing.first {
            getReadyToLeave(air)
            let opening = "\(letItBeHeard(air))Mixing through \(name), \(count) to go."
            mixSet = MixSet(name: name, queue: queue, onAir: air.index, opening: opening)
            say(opening, .info)
        } else {
            let opening = "Mixing through \(name), \(count)."
            // If the first track's on a deck already, that's the deck it starts on. It would have been loaded on the first deck as well.
            let first = decks.first { $0.track?.id == queue.first } ?? decks[0]
            mixSet = MixSet(name: name, queue: queue, onAir: first.index, needsStart: true, opening: opening)
            guard loadNext(onto: first) != nil else {
                mixSet = nil
                say("None of the tracks in \(name) can be loaded.", .refused)
                return
            }
            say(opening, .info)
        }
    }

    /// Takes the next track that'll load off the queue and starts it loading.
    private func loadNext(onto deck: Deck) -> UUID? {
        while let id = mixSet?.queue.first {
            mixSet?.queue.removeFirst()
            // What's there already stays as it is. Loading it again started its split over, and undid a tempo someone had set.
            if deck.loadError == nil, deck.isLoading ? deck.loadingTrack?.id == id : deck.track?.id == id { return id }
            if loadTrack?(id, deck) != nil { return id }
        }
        return nil
    }

    private func endSet(_ message: String, _ kind: StatusKind = .info) {
        mixSet = nil
        earlyCrossfader = nil
        say(message, kind)
    }

    /// Runs with the engine's tick, whenever there's no move being planned or played.
    private func advanceSet() {
        guard let set = mixSet, phase == .idle else { return }
        let air = decks[set.onAir]
        guard let waiting = decks.first(where: { $0 !== air }) else { return }

        if set.needsStart {
            if air.isLoading { return }
            if air.isLoaded, air.loadError == nil {
                // Its fader can be down, or the crossfader away from it, and a mix doesn't start in silence.
                _ = prepareMixer(air)
                air.play()
                mixSet?.needsStart = false
            } else if loadNext(onto: air) == nil {
                endSet("None of the tracks in \(set.name) can be loaded.", .refused)
            }
            return
        }

        guard let next = set.next else {
            if !air.isPlaying {
                if air.renderer.reachedEnd {
                    endSet("That's the end of \(set.name).", .done)
                } else {
                    endSet("Mix off: deck \(air.index + 1) was stopped.")
                }
            } else if let id = loadNext(onto: waiting) {
                mixSet?.next = id
                let title = waiting.loadingTrack?.title ?? waiting.track?.title
                // The deck shows what's next anyway, and this comes straight after a move, while it's asking about that.
                if let title, !isAskingForRating(), !set.keepsQuietAboutNext {
                    say("\(set.opening.map { $0 + " " } ?? "")Up next: \(title).", .info)
                }
                mixSet?.keepsQuietAboutNext = false
                mixSet?.opening = nil
            } else if !set.saidItsTheLast {
                mixSet?.saidItsTheLast = true
                if !isAskingForRating() { say("That's the last track in \(set.name). The mix ends with it.", .info) }
            }
            return
        }

        if waiting.isLoading { return }
        if waiting.loadError != nil {
            mixSet?.next = nil
            return
        }
        guard waiting.track?.id == next else {
            endSet("Mix off: deck \(waiting.index + 1) has something else on it now.")
            return
        }
        guard !waiting.isPlaying else {
            endSet("Mix off: you started deck \(waiting.index + 1) yourself.")
            return
        }
        if !air.isPlaying {
            guard air.renderer.reachedEnd else {
                endSet("Mix off: deck \(air.index + 1) was stopped.")
                return
            }
            startWithoutAMove(waiting, "No clean way in.")
            return
        }
        // Someone's holding this track in a loop, so it isn't leaving yet.
        if air.renderer.loopActive { return }
        if hasNothingLeftToHear(air) {
            air.pause()
            startWithoutAMove(waiting, "No clean way in.")
            return
        }

        for deck in [air, waiting] {
            guard let id = deck.track?.id, deck.trackMap == nil, !deck.stemsAreOnTheWay, !askedForStems.contains(id), StemSeparation.hasModel else { continue }
            askedForStems.insert(id)
            deck.prepareStems()
        }
        guard set.plannedFor != next, let map = air.trackMap, waiting.trackMap != nil else { return }
        // As late as it'll go, and no further back than a third of the way in: past that it's better to echo out from
        // where it would have left anyway, and past that to let the track finish.
        let usual = TransitionPlanner.setExit(in: map)
        var from = usual - TransitionPlanner.setStepBack * set.stepsBack
        let lookedEverywhere = set.stepsBack > 0 && from < map.barCount / 3
        if lookedEverywhere {
            guard !set.lastResort else {
                mixSet?.plannedFor = next
                say("No clean way in. Next track starts when this one ends.", .info)
                return
            }
            from = usual
            mixSet?.lastResort = true
        }
        outgoing = air
        incoming = waiting
        leaveFrom = from
        if planIfReady() {
            mixSet?.plannedFor = next
        } else {
            outgoing = nil
            incoming = nil
            mixSet?.lastResort = false
        }
    }

    /// The incoming deck's the one on air now, and the other one's free for what comes next.
    private func handOver(to deck: Deck) {
        mixSet?.onAir = deck.index
        mixSet?.next = nil
        mixSet?.plannedFor = nil
        mixSet?.stepsBack = 0
        mixSet?.lastResort = false
    }

    /// There was no move ready: stems weren't there in time, or there was no clean way in. The music mustn't stop.
    private func startWithoutAMove(_ deck: Deck, _ why: String) {
        // Its fader can be down, or the crossfader away from it, which a move would have seen to.
        _ = prepareMixer(deck)
        deck.setTempo(0)
        deck.play()
        handOver(to: deck)
        mixSet?.keepsQuietAboutNext = true
        say("\(why) Deck \(deck.index + 1) just started.", .info)
    }

    /// AUTO's been pressed and there's no move yet. Running out here left silence with the next track sitting ready, on a
    /// first-time user's first press, so it does what a mix does. Says whether that's the end of it.
    private func startNextIfThisOnesDone(_ from: Deck, _ to: Deck) -> Bool {
        let number = to.index + 1
        if to.isPlaying {
            cancel()
            say("Auto DJ stopped: you started deck \(number) yourself.", .info)
            return true
        }
        let why = phase == .waitingForStems ? "The stems didn't get there in time." : "No clean way in."
        if !from.isPlaying {
            let ranOut = from.renderer.reachedEnd
            let stopped = "Auto DJ stopped: deck \(from.index + 1) stopped before the stems were ready."
            cancel()
            if ranOut, to.isLoaded {
                startWithoutAMove(to, why)
            } else {
                say(stopped, .info)
            }
            return true
        }
        if !from.renderer.loopActive, to.isLoaded, hasNothingLeftToHear(from) {
            cancel()
            from.pause()
            startWithoutAMove(to, why)
            return true
        }
        return false
    }

    /// Whether a track on air has got to where it's faded away, so the next one needn't sit through the silence.
    private func hasNothingLeftToHear(_ deck: Deck) -> Bool {
        guard deck.renderer.frameCount > 0, let id = deck.track?.id else { return false }
        if silentFrom?.track != id {
            // Stems are stored at half level, so the same sound is half the size in one.
            let last = deck.renderer.stemSources?.map { $0.lastSound(above: Self.silence / 2) }.max()
                ?? deck.renderer.mixSource?.lastSound(above: Self.silence)
            silentFrom = (id, last.map(Double.init) ?? .infinity)
        }
        return deck.renderer.playhead >= silentFrom?.frame ?? .infinity
    }

    /// -50 dB, as a 16-bit sample. A fade below this isn't worth waiting for.
    private static let silence: Int16 = 104

    // MARK: Planning

    private func begin() {
        let playing = decks.filter(\.isPlaying)
        guard let from = playing.first else {
            say("Play a track first, then Auto DJ can mix out of it.", .refused)
            return
        }
        guard playing.count == 1 else {
            say("Auto DJ brings in a stopped deck. Stop the one you want next.", .refused)
            return
        }
        guard let to = decks.first(where: { $0 !== from }), to.isLoaded else {
            say("Load the next track on the other deck first.", .refused)
            return
        }
        getReadyToLeave(from)
        outgoing = from
        incoming = to
        if planIfReady() { return }
        // With "Prepare stems on load" off nobody's asked for them yet, and pressing this is asking. A track that's been split gets them straight back.
        if StemSeparation.hasModel {
            for deck in [from, to] where deck.trackMap == nil && !deck.stemsAreOnTheWay { deck.prepareStems() }
        }
        // A track that isn't splitting and has no map is never going to get one.
        guard [from, to].allSatisfy({ $0.trackMap != nil || $0.stemsAreOnTheWay }) else {
            say("Auto DJ needs stems, and this track doesn't have them.", .refused)
            outgoing = nil
            incoming = nil
            return
        }
        phase = .waitingForStems
        say("\(letItBeHeard(from))Auto DJ is waiting for the stems. If this track ends first, deck \(to.index + 1) starts.", .info)
    }

    /// A deck playing with the crossfader shut on it can't be heard. With no move to open it yet, that was a silent master for as
    /// long as the split took, up to 100 s, with the key lit and the deck's own meter full. Gives back what to say if it opens it.
    private func letItBeHeard(_ deck: Deck) -> String {
        guard let undo = openCrossfader(deck) else { return "" }
        earlyCrossfader = undo
        return "Crossfader to the middle. "
    }

    private func undoEarlyCrossfader() {
        earlyCrossfader?()
        earlyCrossfader = nil
    }

    /// A deck about to be mixed out of can't be held in a loop, or it'd never get to its moment. And pressing the key again
    /// after stopping a move is asking to start over, so what that move left on the deck goes as well.
    private func getReadyToLeave(_ deck: Deck) {
        for left in leftBehind { clearAfterMove(left.deck, isOld: left.wasOld) }
        leftBehind = []
        if deck.renderer.loopActive { deck.exitLoop() }
    }

    /// Starts planning if both tracks have been mapped.
    private func planIfReady() -> Bool {
        guard let outgoing, let incoming, let map = outgoing.trackMap, let mapB = incoming.trackMap,
              let stemsA = outgoing.renderer.stemSources, let stemsB = incoming.renderer.stemSources else { return false }
        phase = .planning
        // A move into this track may have left a key shift on it, which is what its notes will sound like.
        let mapA = map.heard(shiftedBy: outgoing.keyShift)
        let rateA = outgoing.tempoRatio
        let playingBPM = mapA.bpm * rateA
        // The first bar there's time to get ready for, allowing for the plan itself.
        let here = outgoing.position
        let soonest = Int(((here - mapA.firstBar) / mapA.barSeconds).rounded(.up)) + TransitionScore.leadBars + 1
        // The incoming fader gets brought up to at least this when the clock starts.
        let levelA = outgoing.channelTrim * outgoing.fader * outgoing.fader
        let faderB = max(incoming.fader, max(outgoing.fader, 0.5))
        let levelB = incoming.channelTrim * faderB * faderB
        let lagFor: (Deck, Double, Int) -> Double = { deck, rate, shift in
            abs(rate - 1) > 1e-6 || shift != 0 ? cheeks_deck_stem_lag(deck.renderer.handle, rate) : 0
        }
        let choice = TransitionChoice(mapA: mapA, mapB: mapB, stemsA: stemsA, stemsB: stemsB,
                                      deckA: Int32(outgoing.index), deckB: Int32(incoming.index), rateA: rateA, levelA: levelA, levelB: levelB,
                                      lagA: lagFor(outgoing, rateA, outgoing.keyShift), lagB: lagFor(incoming, playingBPM / mapB.bpm, 0),
                                      lagShifted: cheeks_deck_stem_lag(incoming.renderer.handle, playingBPM / mapB.bpm),
                                      earliest: max(soonest, leaveFrom), recentMoves: recentMoves,
                                      avoid: leavesOut.union(mixSet == nil ? [] : [.brakeDrop]), wantsTimeOnNext: mixSet != nil, taste: ratings.taste,
                                      // Someone's pressed the key and wants something to happen. A mix looks further back first.
                                      fallsBackToEchoOut: mixSet?.lastResort ?? true)
        planning = Task.detached(priority: .userInitiated) { [weak self] in
            let chosen = choice.choose(isCancelled: { Task.isCancelled })
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in self?.planFinished(chosen) }
        }
        return true
    }

    private func planFinished(_ score: TransitionScore?) {
        guard phase == .planning else { return }
        planning = nil
        guard let score else {
            guard mixSet != nil else {
                // Too near the end, as a rule. Someone's pressed the key, and the music carries on all the same.
                if let outgoing, let incoming { say("\(letItBeHeard(outgoing))No clean way in from here. Deck \(incoming.index + 1) starts when this one ends.", .info) }
                phase = .waitingForTheEnd
                return
            }
            reset()
            // There may be a way from further back in the track, so the next tick asks again.
            mixSet?.stepsBack += 1
            mixSet?.plannedFor = nil
            return
        }
        arm(score)
    }

    // MARK: Performing

    private func arm(_ score: TransitionScore) {
        guard let outgoing, let incoming, outgoing.isPlaying else {
            reset()
            return
        }
        guard outgoing.renderer.playhead < score.armFrame else {
            // It took too long to think, or someone moved the deck. Try again from where it is now.
            _ = planIfReady()
            return
        }
        plannedA = outgoing.track?.id
        plannedB = incoming.track?.id
        prepare(incoming, for: score)
        let steps = score.steps
        let loaded = steps.withUnsafeBufferPointer {
            cheeks_engine_auto_load(core, $0.baseAddress, Int32($0.count), score.framesPerBeat, score.length)
        }
        guard loaded else {
            cancel()
            say("Auto DJ couldn't get that ready. Try again.", .problem)
            return
        }
        self.score = score
        lanes = steps.reduce(into: [(deck: Deck, kind: CheeksAutoKind, index: Int, from: Double)]()) { lanes, step in
            guard step.kind <= Int32(CheeksAutoFilter.rawValue) else { return }
            let deck = step.deck == Int32(outgoing.index) ? outgoing : incoming
            let kind = CheeksAutoKind(rawValue: UInt32(step.kind))
            if !lanes.contains(where: { $0.deck === deck && $0.kind == kind && $0.index == Int(step.index) }) {
                lanes.append((deck, kind, Int(step.index), step.startBeat))
            }
        }
        cheeks_engine_auto_arm(core, 0, Int32(outgoing.index), score.armFrame)
        phase = .armed(score.plan.move)
        updateBarsToGo()
        // A mix can be minutes from its next move, so there's no point saying so yet. No number either: this stays up for a few
        // bars with the key counting beside it, and they were up to 3 apart by the time anyone had read it.
        if mixSet == nil { say("\(score.plan.move.title) next. The key's counting down the bars.", .info) }
    }

    /// Puts the incoming deck where the score expects it.
    private func prepare(_ deck: Deck, for score: TransitionScore) {
        let before = Prepared.Settings(deck)
        deck.pause()
        deck.syncOn = false
        deck.renderer.setLoop(start: deck.renderer.loopStart, end: deck.renderer.loopEnd, active: false)
        deck.clearFX()
        deck.filter = 0
        deck.eqLow = 0
        deck.eqMid = 0
        deck.eqHigh = 0
        deck.keyLock = true
        deck.keyShift = score.plan.shift
        let tempo = (score.b.rate - 1) * 100
        if abs(tempo) > deck.tempoRange { deck.tempoRange = [6, 10, 16, 100].first { $0 >= abs(tempo) } ?? 100 }
        // Stems and the grid go by what the map found, and the tempo's relative to what the deck thinks its BPM is.
        deck.setTempo(deck.bpm > 0 ? (score.b.map.bpm * score.b.rate / deck.bpm - 1) * 100 : tempo)
        // Cued where it'll come in, as a DJ would. It sat wherever it was until the score moved it, for up to a minute, and a
        // first-time user watching a deck at its very end had nothing to say it was coming.
        deck.seek(to: score.incomingFrom / AudioConfig.sampleRate)
        prepared = Prepared(before: before, after: Prepared.Settings(deck))
    }

    private func updateBarsToGo() {
        guard let score, let outgoing else { return }
        let frames = score.armFrame - outgoing.renderer.playhead
        let bar = score.a.map.barSeconds * AudioConfig.sampleRate
        let bars = max(0, Int((frames / bar).rounded(.up))) + TransitionScore.leadBars
        if bars != barsToGo { barsToGo = bars }
    }

    /// Whether someone's changed what the plan was made for: the track on either deck, or started the waiting deck.
    private var planStillHolds: Bool {
        guard let outgoing, let incoming, score != nil, ending == nil else { return true }
        guard outgoing.track?.id == plannedA, incoming.track?.id == plannedB else {
            cancelForChange("the track changed.")
            return false
        }
        if incoming.renderer.isPlaying, !scoreCouldHaveStarted(incoming) {
            cancelForChange("you started deck \(incoming.index + 1) yourself.")
            return false
        }
        return true
    }

    /// PLAY on the new deck early in a move got no reply, and nothing to hear as its stems were down. The score then took it
    /// somewhere else by itself. The core sets the deck going before it publishes the beat, so it gets a little leeway.
    private func scoreCouldHaveStarted(_ deck: Deck) -> Bool {
        let beat = cheeks_engine_auto_beat(core)
        let clockIsGoing = cheeks_engine_auto_running(core)
        switch phase {
        case .armed: return clockIsGoing
        // With the clock run out the move's over, and the tick's about to say so.
        case .running: return !clockIsGoing || beat + 0.25 >= score?.incomingStarts ?? 0
        default: return true
        }
    }

    /// How it starts saying it's been stopped from outside, whichever kind of thing was going on.
    private var stoppedBy: String { mixSet == nil ? "Auto DJ stopped" : "Mix off" }

    private func cancelForChange(_ why: String) {
        var message = "\(stoppedBy): \(why)"
        mixSet = nil
        if case .running = phase, let outgoing {
            // The new deck's gone, the same as if it had been stopped.
            if outgoing.renderer.isPlaying {
                message += " Deck \(outgoing.index + 1) carries on."
                endEarly(.oldCarriesOn, message)
            } else {
                endEarly(.oldStops(startNew: false), message)
            }
        } else {
            cancel()
            say(message, .info)
        }
    }

    /// Runs with the engine's tick.
    func tick() {
        defer { advanceSet() }
        guard planStillHolds else { return }
        switch phase {
        case .waitingForStems:
            guard let outgoing, let incoming, !startNextIfThisOnesDone(outgoing, incoming) else { return }
            if planIfReady() {
                // "Waiting for the stems" stayed up for up to 13 s after they'd finished.
                say("The stems are ready. Auto DJ is choosing a move.", .info)
            } else if ![outgoing, incoming].allSatisfy({ $0.trackMap != nil || $0.stemsAreOnTheWay }) {
                cancel()
                say("Auto DJ needs stems, and this track doesn't have them.", .refused)
            }
        case .waitingForTheEnd:
            guard let outgoing, let incoming else { return reset() }
            _ = startNextIfThisOnesDone(outgoing, incoming)
        case .armed(let move):
            updateBarsToGo()
            if cheeks_engine_auto_running(core) {
                coreIsRunning = true
                phase = .running(move)
                lendKnobsToTheScore()
                openTheChannel()
                countIn(move)
            } else if let score, let outgoing {
                let number = outgoing.index + 1
                if !outgoing.isPlaying {
                    cancel()
                    // A mix says so itself, as it goes on to see what's become of the deck.
                    if mixSet == nil { say("Auto DJ stopped: deck \(number) was stopped.", .info) }
                } else if outgoing.renderer.playhead > score.armFrame + AudioConfig.sampleRate {
                    cancel()
                    if mixSet == nil {
                        say("Auto DJ lost its moment when the deck moved.", .info)
                    } else {
                        // A mix just plans again from wherever the deck's got to.
                        mixSet?.plannedFor = nil
                    }
                } else if isHeldBack(outgoing, before: score.armFrame) {
                    cancel()
                    if mixSet == nil {
                        say("Auto DJ stopped: deck \(number) is in a loop.", .info)
                    } else {
                        mixSet?.plannedFor = nil
                        say("The mix will carry on when deck \(number)'s loop ends.", .info)
                    }
                }
            }
        case .running(let move):
            if ending == nil {
                followControls()
                if cheeks_engine_auto_running(core) {
                    countIn(move)
                    noticeStoppedDeck()
                } else {
                    finish()
                }
            } else {
                ticksEnding += 1
                if !cheeks_engine_auto_running(core) || ticksEnding > 15 { finish() }
            }
        case .idle:
            bringInWhatsLeftAfterAStoppedMove()
            // Back at the centre, by hand, a knob left on FILTER is doing nothing, and the key beside it still says DUB.
            for left in leftBehind where left.deck.filter == 0 { giveKnobBack(left.deck) }
        case .planning:
            // The plan's for a track that's over by the time it comes. A mix sees to this for itself.
            if mixSet == nil, let outgoing, let incoming { _ = startNextIfThisOnesDone(outgoing, incoming) }
        }
    }

    /// The score sweeps a filter, so a knob it's turning has to say FILTER, but only from now on. A plan comes minutes ahead in a
    /// mix, and in all that time someone turning a knob labelled FILTER would have been expecting DUB, or the other way round.
    private func lendKnobsToTheScore() {
        for lane in lanes where lane.kind == CheeksAutoFilter && lane.deck.colorFX != .filter { lane.deck.colorFX = .filter }
    }

    /// The crossfader and the new deck's fader, only now that it's near. A plan can be minutes ahead in a mix, and they moved at
    /// once, however far off the move was. Reported in three rounds as moving by itself.
    private func openTheChannel() {
        guard let incoming else { return }
        let moves = !crossfaderIsCentred()
        prepared?.undoMixer = prepareMixer(incoming)
        if moves, !isAskingForRating() { say("Crossfader to the middle, \(mixSet == nil ? "to hear both" : "ready for what's next").", .info) }
    }

    /// The clock starts a couple of bars ahead of the move, to get the new deck going. Round 12 saw "starting" come with the
    /// key still counting, as that went by the clock and the count by the move. Both go by the move now: it's when knobs move
    /// and a loop appears, and without this nothing says why.
    private func countIn(_ move: TransitionMove) {
        guard let score, !saidItsStarting else { return }
        let left = max(0, Int(((score.firstHeard - cheeks_engine_auto_beat(core)) / 4).rounded(.up)))
        if left != barsToGo { barsToGo = left }
        guard left == 0 else { return }
        saidItsStarting = true
        if !isAskingForRating() {
            say(mixSet == nil ? "\(move.title) starting. Touch a control to take it back." : "\(move.title) into \(incoming?.track?.title ?? "the next track").", .info)
        }
    }

    /// A move stopped part-way leaves the new deck running with its stems down. Stopping the old deck then leaves nothing to
    /// hear, with PLAY lit and the meters dark: 8 s of silence in round 10, until someone pressed something. Nobody stops the
    /// only deck they can hear to listen to that, and a stopped deck during a move brings the new one in the same way.
    private func bringInWhatsLeftAfterAStoppedMove() {
        guard let old = leftBehind.first(where: { $0.wasOld })?.deck, let new = leftBehind.first(where: { !$0.wasOld })?.deck,
              !old.renderer.isPlaying, new.renderer.isPlaying else { return }
        clearAfterMove(new, isOld: false)
        leftBehind.removeAll { $0.deck === new }
        say("Deck \(new.index + 1) is on.", .info)
    }

    /// A loop that ends before this frame, with the deck in it or on its way to it, means the deck will never get there. A
    /// held roll or slice isn't one, as it's over when it's let go: it said the mix was waiting for a loop nobody had set.
    private func isHeldBack(_ deck: Deck, before frame: Double) -> Bool {
        deck.borrowedLoop == nil && deck.renderer.loopActive && deck.renderer.loopEnd <= frame && deck.renderer.playhead < deck.renderer.loopEnd
    }

    /// Moves what's on screen with what the score's doing, so the knobs turn by themselves.
    private func followControls() {
        let beat = cheeks_engine_auto_beat(core)
        for lane in lanes where beat >= lane.from {
            let deck = Int32(lane.deck.index), kind = Int32(lane.kind.rawValue), index = Int32(lane.index)
            // Once someone's taken it the core stops reporting it, and showing that would take it back from them.
            guard !cheeks_engine_auto_released(core, deck, kind, index) else { continue }
            lane.deck.followAuto(lane.kind, index: lane.index, value: cheeks_engine_auto_value(core, deck, kind, index))
        }
    }

    /// A move can't go on without a deck someone's stopped. The score starts one deck and stops the other itself, so
    /// only what happens outside that counts.
    private func noticeStoppedDeck() {
        guard let score, let outgoing, let incoming else { return }
        let beat = cheeks_engine_auto_beat(core)
        let oldIsOnAir = beat < score.handover
        if !incoming.renderer.isPlaying, beat > score.incomingStarts + 0.5 {
            let stopped = "\(stoppedBy): deck \(incoming.index + 1) was stopped."
            mixSet = nil
            if oldIsOnAir, outgoing.renderer.isPlaying {
                endEarly(.oldCarriesOn, "\(stopped) Deck \(outgoing.index + 1) carries on.")
            } else {
                endEarly(.oldStops(startNew: false), "\(stopped) Deck \(outgoing.index + 1) has stopped too.")
            }
        } else if !outgoing.renderer.isPlaying, oldIsOnAir, beat < score.outgoingStops {
            // Nobody's left to wait for, so what was coming comes now. Past the handover it's only what the score was doing anyway.
            let message = "\(stoppedBy): deck \(outgoing.index + 1) was stopped. Deck \(incoming.index + 1) is on."
            mixSet = nil
            endEarly(.oldStops(startNew: true), message)
        }
    }

    /// "Touch a control to take it back", and then nothing said it had. A knob calls this on every step it's turned.
    private func noticeTaken(_ deck: Deck, _ kind: CheeksAutoKind, _ control: Int) {
        guard case .running = phase, ending == nil, !saidItsYours,
              lanes.contains(where: { $0.deck === deck && $0.kind == kind && $0.index == control }) else { return }
        saidItsYours = true
        if !isAskingForRating() { say("That's yours now. Auto DJ carries on with the rest.", .info) }
    }

    /// Sending the old deck somewhere else means taking it, or the score's loop would take it straight back, with no word.
    /// Past the handover it's on its way out, and the score can carry on seeing it off.
    private func noticeMoved(_ deck: Deck) {
        if deck === incoming { prepared?.movedByHand = true }
        guard case .running = phase, ending == nil, deck === outgoing, let score, cheeks_engine_auto_beat(core) < score.handover else { return }
        let message = "\(stoppedBy): deck \(deck.index + 1) was moved. The decks are yours."
        mixSet = nil
        endEarly(.decksAreYours, message)
    }

    /// Leaving a Loop build's loop looked as if it had worked, until the score's next loop took the deck back with no word.
    /// Only that move's score loops the old deck, so anywhere else it's between someone and their own loop.
    private func noticeLoopChanged(_ deck: Deck) {
        guard case .running(.loopDrop) = phase, ending == nil, deck === outgoing, let score, cheeks_engine_auto_beat(core) < score.handover else { return }
        let message = "\(stoppedBy): deck \(deck.index + 1)'s loop was changed. The decks are yours."
        mixSet = nil
        endEarly(.decksAreYours, message)
    }

    /// Stops the clock. The next tick finishes up, when nothing in the audio core can still be writing to the controls.
    private func endEarly(_ how: Ending, _ message: String) {
        guard ending == nil else { return }
        ending = (how, message)
        ticksEnding = 0
        cheeks_engine_auto_stop(core)
    }

    private func finish() {
        guard let outgoing, let incoming else { return reset() }
        if let ending {
            finishEarly(ending.how, outgoing, incoming)
            forgetTheScoresLoop(outgoing)
            var message = ending.message
            if case .decksAreYours = ending.how { message += stemsStillDown(on: [outgoing, incoming]) }
            reset()
            say(message, .info)
            return
        }
        let title = score?.plan.move.title ?? "Transition"
        let move = score?.plan.move
        let from = outgoing.track?.title ?? "", to = incoming.track?.title ?? ""
        if let move { recentMoves.append(move) }
        recentMoves = Array(recentMoves.suffix(4))
        outgoing.pause()
        clearAfterMove(outgoing, isOld: true)
        clearAfterMove(incoming, isOld: false)
        forgetTheScoresLoop(outgoing)
        cheeks_engine_auto_stop(core)
        let number = incoming.index + 1
        // It's theirs, but it can leave the new deck turned down or off, with nothing to say why.
        let away = crossfaderIsAway(incoming) ? " The crossfader's still turned away from it." : ""
        if mixSet != nil { handOver(to: incoming) }
        reset()
        Haptics.shared.confirm()
        // The question's what says what the thumbs beside it are for.
        let question = move != nil && askForRating != nil ? " More like that?" : ""
        say("\(title) done. Deck \(number) is on.\(away)\(question)", .done)
        if let move { askForRating?(move, from, to) }
    }

    /// RELOOP took a deck back a minute and a half, to a loop nobody set. One someone's still in is theirs now.
    private func forgetTheScoresLoop(_ deck: Deck) {
        guard score?.plan.move == .loopDrop, !deck.renderer.loopActive else { return }
        deck.renderer.setLoop(start: 0, end: 0, active: false)
    }

    private func finishEarly(_ how: Ending, _ outgoing: Deck, _ incoming: Deck) {
        switch how {
        case .decksAreYours:
            // Stems, EQ, the filter knob and the loop are all on the screen, and they stay as they are. The score's
            // effects and its noise aren't, so nobody could turn them off.
            followControls()
            cheeks_deck_restore_source(outgoing.renderer.handle)
            outgoing.restoreFXChain()
            // Barely started, a sweep can't be heard, and it left a knob on FILTER with a dot of blue and the key saying DUB.
            if abs(outgoing.filter) < Self.barelySwept, !cheeks_engine_auto_released(core, Int32(outgoing.index), Int32(CheeksAutoFilter.rawValue), 0) {
                outgoing.followAuto(CheeksAutoFilter, index: 0, value: 0)
            }
            // With the filter still swept, FILTER's what the knob is doing. Otherwise it goes back to what the key says.
            if outgoing.filter == 0 { giveKnobBack(outgoing) }
            outgoing.applyFilter()
            // The key beside it said 4, its old length, and RELOOP then came back as the 16 beats it really was.
            if outgoing.renderer.loopActive { outgoing.showLength(ofLoopFrom: outgoing.renderer.loopStart, to: outgoing.renderer.loopEnd) }
            // Nobody's heard the new deck yet, so there's no reason for it to be left quiet or at another tempo. The score starts it
            // a couple of bars early with every stem down, and left there it was a lit PLAY with nothing to hear, and nothing to say so.
            if !Stem.allCases.contains(where: incoming.stemIsHeard) { incoming.pause() }
            if !incoming.renderer.isPlaying {
                clearAfterMove(incoming, isOld: false)
                putBackPrepared()
            }
            leftBehind = [(outgoing, true)]
            if incoming.renderer.isPlaying { leftBehind.append((incoming, false)) }
        case .oldCarriesOn:
            clearAfterMove(outgoing, isOld: true)
            clearAfterMove(incoming, isOld: false)
            putBackPrepared()
        case .oldStops(let startNew):
            outgoing.pause()
            clearAfterMove(outgoing, isOld: true)
            if startNew, !incoming.renderer.isPlaying, let score {
                incoming.seek(to: score.b.map.seconds(atBar: score.plan.entry))
                incoming.play()
            }
            clearAfterMove(incoming, isOld: false)
            // Stopped by hand, it can't still be at the move's speed.
            if !incoming.renderer.isPlaying {
                incoming.setTempo(0)
                incoming.keyShift = 0
            }
        }
    }

    /// Below this a filter can't be heard.
    private static let barelySwept: Float = 0.03

    /// A stem's level only shows on the STEMS page, so a deck left quiet or thin needs saying.
    private func stemsStillDown(on decks: [Deck]) -> String {
        let down = decks.filter { $0.renderer.isPlaying && $0.stemsAltered }
        guard let first = down.first else { return "" }
        return down.count == 1 ? " ALL brings back deck \(first.index + 1)'s stems." : " ALL brings back each deck's stems."
    }

    /// Hands a deck back with everything neutral. On a deck that's still playing, whatever someone's taken stays as they
    /// set it, because that's what people are hearing.
    private func clearAfterMove(_ deck: Deck, isOld: Bool) {
        let playing = deck.renderer.isPlaying
        func isFree(_ kind: CheeksAutoKind, _ index: Int) -> Bool {
            !playing || !cheeks_engine_auto_released(core, Int32(deck.index), Int32(kind.rawValue), Int32(index))
        }
        cheeks_deck_restore_source(deck.renderer.handle)
        // A score only loops and fires effects on the old deck, so anything on the new one is someone's own.
        if isOld {
            deck.renderer.setLoop(start: deck.renderer.loopStart, end: deck.renderer.loopEnd, active: false)
            if playing { deck.restoreFXChain() } else { deck.clearFX() }
            if !playing, deck.reverse { deck.reverse = false }
            // Stopped, it's on its way out, and these were only ever the move's. A deck still playing has them because that's how it sounds.
            if !playing {
                deck.setTempo(0)
                deck.keyShift = 0
            }
        }
        for band in 0..<3 where isFree(CheeksAutoEQ, band) { deck.followAuto(CheeksAutoEQ, index: band, value: 1) }
        if isFree(CheeksAutoFilter, 0) {
            deck.followAuto(CheeksAutoFilter, index: 0, value: 0)
            giveKnobBack(deck)
        }
        for stem in Stem.allCases where isFree(CheeksAutoStem, stem.rawValue) { deck.followAuto(CheeksAutoStem, index: stem.rawValue, value: 1) }
        deck.applyFilter()
    }

    /// The knobs read FILTER from then on while the key still said DUB, and the key's next press skipped what it said.
    private func giveKnobBack(_ deck: Deck) {
        let chosen = chosenColorFX()
        if deck.colorFX != chosen { deck.colorFX = chosen }
    }

    private func putBackPrepared() {
        defer { prepared = nil }
        guard let incoming, let prepared else { return }
        prepared.putBack(on: incoming)
        // Where it was as well, unless it's playing or it's been sent somewhere since. A different track starts from its own place.
        if !incoming.renderer.isPlaying, !prepared.movedByHand, incoming.track?.id == plannedB { incoming.seek(to: prepared.before.position) }
    }

    /// Calls off anything before the clock starts.
    private func cancel() {
        planning?.cancel()
        planning = nil
        cheeks_engine_auto_stop(core)
        putBackPrepared()
        undoEarlyCrossfader()
        reset()
    }

    /// Calls off a plan without ending the mix, and stops it planning again for this track.
    func stopForTesting() {
        cancel()
        let next = mixSet?.next
        mixSet?.plannedFor = next
    }

    private func reset() {
        phase = .idle
        coreIsRunning = false
        outgoing = nil
        incoming = nil
        score = nil
        plannedA = nil
        plannedB = nil
        lanes = []
        barsToGo = 0
        leaveFrom = 0
        prepared = nil
        saidItsStarting = false
        saidItsYours = false
        earlyCrossfader = nil
        ending = nil
    }
}
