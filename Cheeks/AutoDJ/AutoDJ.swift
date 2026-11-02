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
    /// Whether that's still on screen, where a passing message would take its place.
    @ObservationIgnored var isAskingForRating: () -> Bool = { false }

    @ObservationIgnored private let core: OpaquePointer
    @ObservationIgnored private let decks: [Deck]
    @ObservationIgnored private let say: (String, StatusKind) -> Void
    @ObservationIgnored private let prepareMixer: (Deck) -> Void
    @ObservationIgnored private var planning: Task<Void, Never>?
    @ObservationIgnored private var outgoing: Deck?
    @ObservationIgnored private var incoming: Deck?
    @ObservationIgnored private var score: TransitionScore?
    /// Each control the score moves, and the beat it starts moving, so the screen only follows ones it's reached.
    @ObservationIgnored private var lanes: [(deck: Deck, kind: CheeksAutoKind, index: Int, from: Double)] = []
    /// The moves played lately, oldest first, so the same few don't keep coming up.
    @ObservationIgnored private var recentMoves: [TransitionMove] = []
    @ObservationIgnored private var coreIsRunning = false
    @ObservationIgnored private var plannedA: UUID?
    @ObservationIgnored private var plannedB: UUID?

    init(core: OpaquePointer, decks: [Deck], say: @escaping (String, StatusKind) -> Void, prepareMixer: @escaping (Deck) -> Void) {
        self.core = core
        self.decks = decks
        self.say = say
        self.prepareMixer = prepareMixer
        for deck in decks {
            let index = Int32(deck.index)
            deck.onManualControl = { kind, control in cheeks_engine_auto_release(core, index, Int32(kind.rawValue), Int32(control)) }
        }
    }

    var isActive: Bool { phase != .idle || mixSet != nil }

    /// What the key says.
    var legend: String {
        let name = mixSet == nil ? "AUTO" : "MIX"
        switch phase {
        case .idle, .running: return name
        case .waitingForStems, .planning: return "\(name)…"
        case .armed: return "\(name) \(barsToGo)"
        }
    }

    func press() {
        let wasSet = mixSet != nil
        mixSet = nil
        switch phase {
        case .idle:
            if wasSet {
                say("Mix off. The track playing just carries on.", .info)
            } else {
                begin()
            }
        case .waitingForStems, .planning, .armed:
            cancel()
            say(wasSet ? "Mix off. The track playing just carries on." : "Auto DJ off.", .info)
        case .running:
            stopPerforming()
            say("Auto DJ stopped. The decks are yours.", .info)
        }
    }

    // MARK: Mixing through a list

    /// Mixes through these tracks in order. If a deck's playing, it carries on from that, and from that track's place
    /// in the list if it's on it. Otherwise it starts from the top.
    func startSet(named name: String, tracks: [UUID]) {
        let playing = decks.filter(\.isPlaying)
        guard playing.count <= 1 else {
            say("Auto DJ brings in a stopped deck. Stop the one you want next.", .refused)
            return
        }
        var queue = tracks
        if let air = playing.first {
            if let id = air.track?.id, let here = queue.firstIndex(of: id) { queue.removeFirst(here + 1) }
            guard !queue.isEmpty else {
                say("There's nothing after this track in \(name).", .refused)
                return
            }
        } else {
            guard queue.count >= 2 else {
                say("A mix needs at least two tracks.", .refused)
                return
            }
        }
        if phase != .idle { cancel() }
        askedForStems = []
        if let air = playing.first {
            mixSet = MixSet(name: name, queue: queue, onAir: air.index)
            say("Mixing through \(name).", .info)
        } else {
            mixSet = MixSet(name: name, queue: queue, onAir: decks[0].index, needsStart: true)
            guard loadNext(onto: decks[0]) != nil else {
                mixSet = nil
                say("None of the tracks in \(name) can be loaded.", .refused)
                return
            }
            say("Mixing through \(name).", .info)
        }
    }

    /// Takes the next track that'll load off the queue and starts it loading.
    private func loadNext(onto deck: Deck) -> UUID? {
        while let id = mixSet?.queue.first {
            mixSet?.queue.removeFirst()
            if loadTrack?(id, deck) != nil { return id }
        }
        return nil
    }

    private func endSet(_ message: String, _ kind: StatusKind = .info) {
        mixSet = nil
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
                if let title, !isAskingForRating() { say("Up next: \(title).", .info) }
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
            // It ran out with no move ready: stems weren't there in time, or there was no clean way in.
            waiting.setTempo(0)
            waiting.play()
            handOver(to: waiting)
            say("\(waiting.track?.title ?? "The next track") is on, without a transition: there wasn't a clean way in.", .info)
            return
        }

        for deck in [air, waiting] {
            guard let id = deck.track?.id, deck.trackMap == nil, !deck.stemsAreOnTheWay, !askedForStems.contains(id), StemSeparation.hasModel else { continue }
            askedForStems.insert(id)
            deck.prepareStems()
        }
        guard set.plannedFor != next, let map = air.trackMap, waiting.trackMap != nil else { return }
        // As late as it'll go, and no further back than a third of the way in: past that it's better to let the track finish.
        let from = TransitionPlanner.setExit(in: map) - TransitionPlanner.setStepBack * set.stepsBack
        guard set.stepsBack == 0 || from >= map.barCount / 3 else {
            mixSet?.plannedFor = next
            say("No clean way into the next track, so it'll start when this one ends.", .info)
            return
        }
        outgoing = air
        incoming = waiting
        leaveFrom = from
        if planIfReady() {
            mixSet?.plannedFor = next
        } else {
            outgoing = nil
            incoming = nil
        }
    }

    /// The incoming deck's the one on air now, and the other one's free for what comes next.
    private func handOver(to deck: Deck) {
        mixSet?.onAir = deck.index
        mixSet?.next = nil
        mixSet?.plannedFor = nil
        mixSet?.stepsBack = 0
    }

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
        outgoing = from
        incoming = to
        if planIfReady() { return }
        // A track that isn't splitting and has no map is never going to get one.
        guard [from, to].allSatisfy({ $0.trackMap != nil || $0.stemsAreOnTheWay }) else {
            say("Auto DJ needs stems, and this track doesn't have them.", .refused)
            outgoing = nil
            incoming = nil
            return
        }
        phase = .waitingForStems
        say("Auto DJ is waiting for the stems to finish.", .info)
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
        // The incoming fader gets brought up to at least this when the move's armed.
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
                                      avoid: mixSet == nil ? [] : [.brakeDrop], wantsTimeOnNext: mixSet != nil, taste: ratings.taste)
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
            reset()
            guard mixSet != nil else {
                say("Auto DJ couldn't find a clean way between these two from here.", .refused)
                return
            }
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
        prepare(incoming, for: score)
        prepareMixer(incoming)
        let steps = score.steps
        let loaded = steps.withUnsafeBufferPointer {
            cheeks_engine_auto_load(core, $0.baseAddress, Int32($0.count), score.framesPerBeat, score.length)
        }
        guard loaded else {
            reset()
            say("Auto DJ couldn't get that ready. Try again.", .problem)
            return
        }
        self.score = score
        plannedA = outgoing.track?.id
        plannedB = incoming.track?.id
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
        // A mix can be minutes from its next move, so there's no point saying so yet.
        if mixSet == nil { say("\(score.plan.move.title) in \(barsToGo) bars.", .info) }
    }

    /// Puts the incoming deck where the score expects it.
    private func prepare(_ deck: Deck, for score: TransitionScore) {
        deck.pause()
        deck.syncOn = false
        deck.renderer.setLoop(start: deck.renderer.loopStart, end: deck.renderer.loopEnd, active: false)
        deck.clearFX()
        deck.colorFX = .filter
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
        outgoing?.colorFX = .filter
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
        guard let outgoing, let incoming, score != nil else { return true }
        guard outgoing.track?.id == plannedA, incoming.track?.id == plannedB else {
            cancelForChange("Auto DJ stopped: the track changed.")
            return false
        }
        // Once the clock's running, it's the score that starts it.
        if case .armed = phase, incoming.renderer.isPlaying, !cheeks_engine_auto_running(core) {
            cancelForChange("Auto DJ stopped: you started deck \(incoming.index + 1) yourself.")
            return false
        }
        return true
    }

    private func cancelForChange(_ message: String) {
        if let outgoing, case .running = phase { cheeks_deck_restore_source(outgoing.renderer.handle) }
        cancel()
        mixSet = nil
        say(message, .info)
    }

    /// Runs with the engine's tick.
    func tick() {
        defer { advanceSet() }
        guard planStillHolds else { return }
        switch phase {
        case .waitingForStems:
            guard let outgoing, let incoming else { return }
            if !outgoing.isPlaying {
                cancel()
                return
            }
            if !planIfReady(), ![outgoing, incoming].allSatisfy({ $0.trackMap != nil || $0.stemsAreOnTheWay }) {
                cancel()
                say("Auto DJ needs stems, and this track doesn't have them.", .refused)
            }
        case .armed(let move):
            updateBarsToGo()
            if cheeks_engine_auto_running(core) {
                coreIsRunning = true
                phase = .running(move)
            } else if let score, let outgoing, !outgoing.isPlaying || outgoing.renderer.playhead > score.armFrame + AudioConfig.sampleRate {
                cancel()
                if mixSet == nil {
                    say("Auto DJ lost its moment when the deck moved. Press AUTO to plan again.", .info)
                } else {
                    // A mix just plans again from wherever the deck's got to.
                    mixSet?.plannedFor = nil
                }
            }
        case .running:
            followControls()
            if !cheeks_engine_auto_running(core) { finish() }
        case .idle, .planning:
            break
        }
    }

    /// Moves what's on screen with what the score's doing, so the knobs turn by themselves.
    private func followControls() {
        let beat = cheeks_engine_auto_beat(core)
        for lane in lanes where beat >= lane.from {
            let value = cheeks_engine_auto_value(core, Int32(lane.deck.index), Int32(lane.kind.rawValue), Int32(lane.index))
            lane.deck.followAuto(lane.kind, index: lane.index, value: value)
        }
    }

    private func finish() {
        guard let outgoing, let incoming else { return reset() }
        let title = score?.plan.move.title ?? "Transition"
        let move = score?.plan.move
        let from = outgoing.track?.title ?? "", to = incoming.track?.title ?? ""
        if let move { recentMoves.append(move) }
        recentMoves = Array(recentMoves.suffix(4))
        outgoing.pause()
        clearAfterMove(outgoing)
        clearAfterMove(incoming)
        cheeks_engine_auto_stop(core)
        let number = incoming.index + 1
        if mixSet != nil { handOver(to: incoming) }
        reset()
        Haptics.shared.confirm()
        say("\(title) done. Deck \(number) is on.", .done)
        if let move { askForRating?(move, from, to) }
    }

    /// Hands a deck back with everything neutral.
    private func clearAfterMove(_ deck: Deck) {
        cheeks_deck_restore_source(deck.renderer.handle)
        deck.renderer.setLoop(start: deck.renderer.loopStart, end: deck.renderer.loopEnd, active: false)
        deck.clearFX()
        deck.followAuto(CheeksAutoEQ, index: 0, value: 1)
        deck.followAuto(CheeksAutoFilter, index: 0, value: 0)
        for stem in Stem.allCases { deck.followAuto(CheeksAutoStem, index: stem.rawValue, value: 1) }
        deck.applyFilter()
    }

    /// Someone took over part-way: the clock stops, and everything stays where it is except a deck that's been cut.
    private func stopPerforming() {
        cheeks_engine_auto_stop(core)
        if let outgoing { cheeks_deck_restore_source(outgoing.renderer.handle) }
        reset()
    }

    private func cancel() {
        planning?.cancel()
        planning = nil
        cheeks_engine_auto_stop(core)
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
    }
}
