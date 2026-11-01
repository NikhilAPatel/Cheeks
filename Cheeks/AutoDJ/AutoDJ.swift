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

    private(set) var phase: Phase = .idle
    /// Bars until the move starts, while it's armed.
    private(set) var barsToGo = 0

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
    /// So the same move doesn't come up twice in a row.
    @ObservationIgnored private var lastMove: TransitionMove?
    @ObservationIgnored private var coreIsRunning = false

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

    var isActive: Bool { phase != .idle }

    /// What the key says.
    var legend: String {
        switch phase {
        case .idle, .running: "AUTO"
        case .waitingForStems, .planning: "AUTO…"
        case .armed: "AUTO \(barsToGo)"
        }
    }

    func press() {
        switch phase {
        case .idle:
            begin()
        case .waitingForStems, .planning, .armed:
            cancel()
            say("Auto DJ off.", .info)
        case .running:
            stopPerforming()
            say("Auto DJ stopped. The decks are yours.", .info)
        }
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
        guard let outgoing, let incoming, let mapA = outgoing.trackMap, let mapB = incoming.trackMap,
              let stemsA = outgoing.renderer.stemSources, let stemsB = incoming.renderer.stemSources else { return false }
        phase = .planning
        let rateA = outgoing.tempoRatio
        let playingBPM = mapA.bpm * rateA
        // The first bar there's time to get ready for, allowing for the plan itself.
        let here = outgoing.position
        let earliest = Int(((here - mapA.firstBar) / (mapA.barSeconds / rateA)).rounded(.up)) + TransitionScore.leadBars + 1
        // The incoming fader gets brought up to at least this when the move's armed.
        let levelA = outgoing.channelTrim * outgoing.fader * outgoing.fader
        let faderB = max(incoming.fader, max(outgoing.fader, 0.5))
        let levelB = incoming.channelTrim * faderB * faderB
        let lagFor: (Deck, Double, Int) -> Double = { deck, rate, shift in
            abs(rate - 1) > 1e-6 || shift != 0 ? cheeks_deck_stem_lag(deck.renderer.handle, rate) : 0
        }
        let lagA = lagFor(outgoing, rateA, 0)
        let lagB = lagFor(incoming, playingBPM / mapB.bpm, 0)
        let lagShifted = cheeks_deck_stem_lag(incoming.renderer.handle, playingBPM / mapB.bpm)
        let last = lastMove
        let deckA = Int32(outgoing.index), deckB = Int32(incoming.index)
        planning = Task.detached(priority: .userInitiated) { [weak self] in
            var plans = TransitionPlanner.plans(from: mapA, to: mapB, playingBPM: playingBPM, earliest: earliest)
            if let last { plans = plans.map { var p = $0; if p.move == last { p.score -= 0.3 }; return p }.sorted { $0.score > $1.score } }
            let stretched = abs(playingBPM / mapB.bpm - 1)
            let ownTempo = stretched > TransitionPlanner.maxStretch
            var chosen: TransitionScore?
            for plan in TransitionPlanner.shortlist(plans) {
                if Task.isCancelled { return }
                let rateB = ownTempo ? 1 : playingBPM / mapB.bpm
                let score = TransitionScore(
                    plan: plan,
                    a: .init(deck: deckA, map: mapA, rate: rateA, lag: lagA),
                    b: .init(deck: deckB, map: mapB, rate: rateB, lag: plan.shift != 0 ? lagShifted : (ownTempo ? 0 : lagB)))
                guard let review = TransitionAudition.review(score, stemsA: stemsA, stemsB: stemsB, levelA: levelA, levelB: levelB, isCancelled: { Task.isCancelled }) else { continue }
                if review.passes {
                    chosen = score
                    break
                }
            }
            let result = chosen
            await MainActor.run { [weak self] in self?.planFinished(result) }
        }
        return true
    }

    private func planFinished(_ score: TransitionScore?) {
        guard phase == .planning else { return }
        planning = nil
        guard let score else {
            reset()
            say("Auto DJ couldn't find a clean way between these two from here.", .refused)
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
        say("\(score.plan.move.title) in \(barsToGo) bars.", .info)
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

    /// Runs with the engine's tick.
    func tick() {
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
                say("Auto DJ lost its moment when the deck moved. Press AUTO to plan again.", .info)
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
        lastMove = score?.plan.move
        outgoing.pause()
        clearAfterMove(outgoing)
        clearAfterMove(incoming)
        cheeks_engine_auto_stop(core)
        let number = incoming.index + 1
        reset()
        say("\(title) done. Deck \(number) is on.", .done)
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

    private func reset() {
        phase = .idle
        coreIsRunning = false
        outgoing = nil
        incoming = nil
        score = nil
        lanes = []
        barsToGo = 0
    }
}
