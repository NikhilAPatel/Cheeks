import Accelerate
import AVFoundation
import Observation

/// What a status message is saying, which decides how the capsule looks.
enum StatusKind {
    case done, info, refused, problem
    /// Something's gone, with an Undo. Saving offers one too, so an Undo alone doesn't mean this: "Memory cue saved." had a bin on it.
    case removed
}

enum CrossfaderCurve: String, CaseIterable, Identifiable {
    case smooth = "SMOOTH"
    case scratch = "SCRATCH"
    var id: String { rawValue }
}

/// The mixer: hosts the realtime core in an AVAudioEngine, and owns both decks, the crossfader,
/// sync and recording. All audio processing happens in `DSP/Engine.cpp`; this class sets its controls.
@MainActor
@Observable
final class DJEngine {
    let decks: [Deck]
    let sampler: Sampler
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let core: OpaquePointer
    /// The AUTO key.
    @ObservationIgnored private(set) var autoDJ: AutoDJ!
    @ObservationIgnored private var sourceNode: AVAudioSourceNode?
    /// Session and engine calls can block for a while, so they stay off the main thread.
    @ObservationIgnored private let audioQueue = DispatchQueue(label: "com.nikhilpatel.seguedj.audio-session", qos: .userInitiated)

    var crossfader: Float = 0 { didSet { updateVolumes() } }
    /// What the COLOR knobs do, on both channels.
    var colorFX: ColorEffect = .filter { didSet { decks.forEach { $0.colorFX = colorFX } } }
    var crossfaderCurve: CrossfaderCurve = .smooth { didSet { updateVolumes() } }
    var masterVolume: Float = 0.9 { didSet { updateVolumes() } }

    // Headphones
    /// Split cue: master (mono) in the left ear, cue (mono) in the right — for a headphone splitter cable.
    var splitCue = false { didSet { updateVolumes() } }
    /// 0 = cue only, 0.5 = both, 1 = master only (in the cue ear).
    var headphoneMix: Float = 0.25 { didSet { updateVolumes() } }
    var headphoneVolume: Float = 0.8 { didSet { updateVolumes() } }
    /// Master level and limiter state. Not observed; meters poll them.
    var masterLevel: Float { cheeks_engine_master_peak(core) }
    var masterLevelRight: Float { cheeks_engine_master_peak_right(core) }
    var limiterReduction: Float { cheeks_engine_limiter_reduction(core) }
    /// True while the limiter's doing real work. Changes rarely, unlike the numbers above, so it's observed.
    private(set) var limiterWorking = false
    /// The engine's load in percent, in steps of 5, once it's high enough to mention. Otherwise 0.
    var engineError: String?
    /// Seconds between the render callback and the speaker, for drawing what's actually being heard.
    @ObservationIgnored private(set) var outputLatency: Double = 0

    /// The deck everything syncs to. It moves to whichever deck starts playing when the current one isn't.
    private(set) var masterIndex = 0
    /// What each channel contributes to the master right now, for on-air detection.
    @ObservationIgnored private var channelGains: [Float] = [0, 0]

    // Recording
    private(set) var isRecording = false
    private(set) var recordingStarted: Date?
    /// Tracks that were audible for 10+ seconds during the current recording.
    private(set) var setlist: [SetlistEntry] = []
    private(set) var savingRecordings = 0
    var recordingFormat: RecordingFormat = RecordingFormat(rawValue: UserDefaults.standard.string(forKey: "recordingFormat") ?? "") ?? .aac {
        didSet { UserDefaults.standard.set(recordingFormat.rawValue, forKey: "recordingFormat") }
    }
    /// Short message for the status capsule (saved, low storage, errors).
    /// A new message clears any Undo or rating offered with the last one, which it'd no longer apply to.
    var statusMessage: String? {
        didSet {
            statusSerial &+= 1
            statusKind = .done
            undoAction = nil
            rateAction = nil
        }
    }
    private(set) var statusKind: StatusKind = .done
    /// Counts messages, so the same words said again stay up for their full time. Pressing a dim control every 5 s, one
    /// press in two looked ignored, as the message went just as the next one said the same thing.
    private(set) var statusSerial = 0
    /// Set alongside a message when what just happened can be taken back.
    var undoAction: (@MainActor () -> Void)?
    /// Set alongside a message when Auto DJ's just finished a move, to say what you thought of it.
    var rateAction: (@MainActor (_ liked: Bool) -> Void)?

    // Preview
    /// The track being auditioned from the browser.
    private(set) var previewingTrack: UUID?
    @ObservationIgnored private var previewPCM: PCM16Stereo?
    private let recorder = MixRecorder()
    @ObservationIgnored private var recordingDrain: RecordingDrain?
    @ObservationIgnored private var recordingURL: URL?
    @ObservationIgnored private weak var library: Library?

    // On-air detection for the tracklist and History playlists
    @ObservationIgnored private var historyLog = OnAirLog()
    /// What's been on air since the app opened, which NEXT doesn't offer again until there's nothing else.
    private(set) var heardThisSession = Set<UUID>()
    @ObservationIgnored private var setlistLog = OnAirLog()

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var nowPlaying: NowPlaying?

    init(library: Library) {
        let newDecks = [Deck(index: 0), Deck(index: 1)]
        let handles: [OpaquePointer?] = newDecks.map { $0.renderer.handle }
        decks = newDecks
        core = handles.withUnsafeBufferPointer { cheeks_engine_create(AudioConfig.sampleRate, $0.baseAddress, Int32($0.count)) }
        sampler = Sampler(core: core)
        self.library = library
        for deck in decks {
            deck.library = library
            deck.onMixChange = { [weak self] in self?.updateVolumes() }
            deck.onMessage = { [weak self] message, kind in self?.say(message, kind) }
            deck.onTrackEdited = { [weak self, weak deck] in
                self?.decks.filter { $0 !== deck && $0.track?.id == deck?.track?.id }.forEach { $0.refreshTrack() }
            }
            deck.offerUndo = { [weak self] message, kind, undo in
                self?.statusMessage = message
                self?.statusKind = kind
                self?.undoAction = undo
            }
        }
        autoDJ = AutoDJ(core: core, decks: decks, say: { [weak self] message, kind in self?.say(message, kind) }, prepareMixer: { [weak self] incoming in
            self?.openChannel(for: incoming) ?? {}
        })
        autoDJ.takeBack = { [weak self] message in
            if self?.statusMessage == message { self?.statusMessage = nil }
        }
        autoDJ.loadTrack = { [weak self] id, deck in
            guard let self, let track = self.library?.track(id), self.load(track, onto: deck) else { return nil }
            return track.title
        }
        for deck in decks {
            deck.syncLeader = { [unowned self, unowned deck] in self.master(for: deck) }
        }
        autoDJ.isAskingForRating = { [weak self] in self?.rateAction != nil }
        autoDJ.crossfaderIsCentred = { [weak self] in self?.crossfader == 0 }
        autoDJ.hasBeenHeard = { [weak self] in self?.heardThisSession.contains($0) == true }
        autoDJ.openCrossfader = { [weak self] deck in self?.openCrossfader(for: deck) }
        autoDJ.crossfaderIsAway = { [weak self] deck in (self?.crossfaderGain(for: deck) ?? 1) < 0.5 }
        autoDJ.chosenColorFX = { [weak self] in self?.colorFX ?? .filter }
        autoDJ.askForRating = { [weak self] move, from, to in
            self?.rateAction = { [weak self] liked in
                self?.autoDJ.ratings.add(TransitionRating(move: move, from: from, to: to, liked: liked, at: Date()))
                self?.say(liked ? "Got it. More like that." : "Got it. Less like that.", .done)
            }
        }
        LaunchLog.mark("  engine: decks and Auto DJ made")
        buildGraph()
        LaunchLog.mark("  engine: audio graph built")
        updateVolumes()
        startAudio()
        LaunchLog.mark("  engine: audio started")
        observeSession()
        // .common mode keeps sync and transport state updating while a list is being scrolled.
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        if LaunchLog.isOn {
            let core = core
            LaunchLog.audioLoad = { cheeks_engine_load(core) }
        }
        LiveRenderer.shared.isBusy = { [weak self] in self?.decks.contains { $0.isPlaying || $0.renderer.scratching } ?? false }
        sampler.onMessage = { [weak self] message, kind in self?.say(message, kind) }
        sampler.loadSounds()
        library.isBusy = { [weak self] in
            let thermal = ProcessInfo.processInfo.thermalState
            return thermal == .serious || thermal == .critical || self?.decks.contains { $0.isPlaying } == true
        }
        library.onAnalyzed = { [weak self] id in
            self?.decks.filter { $0.track?.id == id }.forEach { $0.refreshTrack() }
        }
        // Recordings interrupted by a crash or the app being killed get saved now.
        for caf in Recordings.unfinished() { finalize(caf, recovered: true) }
        nowPlaying = NowPlaying(engine: self)
    }

    /// Every deck's position, in frames, all from the same moment in the render.
    var positions: [Double] {
        var out = [Double](repeating: 0, count: decks.count)
        cheeks_engine_positions(core, &out, Int32(out.count))
        return out
    }

    /// The realtime core, for a test that renders from another thread.
    var coreForTesting: OpaquePointer { core }

    /// The deck the audience is hearing most: for the Lock Screen.
    var loudestDeck: Deck? {
        decks.filter { $0.isPlaying && channelGains[$0.index] > 0.02 }.max { channelGains[$0.index] < channelGains[$1.index] }
    }

    // MARK: Graph

    /// One source node runs the whole core, so both decks and the mixer share a single sample clock.
    private func buildGraph() {
        let stereo = AVAudioFormat(standardFormatWithSampleRate: AudioConfig.sampleRate, channels: 2)!
        let core = self.core
        // Only captures a raw pointer, so the render thread does no reference counting.
        let node = AVAudioSourceNode(format: stereo) { _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            cheeks_engine_render(core, left, right, Int32(frameCount))
            return noErr
        }
        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: stereo)
        engine.mainMixerNode.outputVolume = 1
    }

    /// Sets up the session and starts the engine. Stays off the main thread, as both can take a moment.
    func startAudio() {
        audioQueue.async { [engine, weak self] in
            let session = AVAudioSession.sharedInstance()
            var failure: String?
            do {
                try session.setCategory(.playback, mode: .default)
                try session.setPreferredSampleRate(AudioConfig.sampleRate)
                try session.setPreferredIOBufferDuration(0.005)
                try session.setActive(true)
                if !engine.isRunning {
                    engine.prepare()
                    try engine.start()
                }
            } catch {
                failure = "Audio: \(error.localizedDescription)"
            }
            let latency = session.outputLatency + session.ioBufferDuration
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.engineError = failure
                    self?.outputLatency = latency
                    self?.decks.forEach { $0.outputLatency = latency }
                }
            }
        }
    }

    private func observeSession() {
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated {
                if raw == AVAudioSession.InterruptionType.ended.rawValue { self?.startAudio() }
            }
        }
        center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.startAudio() }
        }
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            // Setting the category reports a route change of its own, which mustn't start a loop.
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard raw != AVAudioSession.RouteChangeReason.categoryChange.rawValue else { return }
            MainActor.assumeIsolated { self?.startAudio() }
        }
    }

    // MARK: Mixer

    private func crossfaderGains() -> (Float, Float) {
        let x = (crossfader + 1) / 2 // 0 = full left, 1 = full right
        switch crossfaderCurve {
        case .smooth:
            let a: Float = x <= 0.5 ? 1 : cos((x - 0.5) * .pi)
            let b: Float = x >= 0.5 ? 1 : cos((0.5 - x) * .pi)
            return (a, b)
        case .scratch:
            return (x > 0.97 ? 0 : 1, x < 0.03 ? 0 : 1)
        }
    }

    private func crossfaderGain(for deck: Deck) -> Float {
        let (a, b) = crossfaderGains()
        return deck.index == 0 ? a : b
    }

    /// Opens a crossfader that's all but shut on a deck, and gives back how to undo that. Nil if the deck can be heard already.
    private func openCrossfader(for deck: Deck) -> (() -> Void)? {
        guard crossfaderGain(for: deck) < 0.25 else { return nil }
        let was = crossfader
        crossfader = 0
        return { [weak self] in
            if let self, self.crossfader == 0 { self.crossfader = was }
        }
    }

    /// Makes sure a deck Auto DJ's bringing in can be heard: the crossfader's centred, and its fader's up.
    /// Gets a deck ready to be heard, and gives back how to undo that if it never is.
    private func openChannel(for deck: Deck) -> () -> Void {
        let crossfaderWas = crossfader, faderWas = deck.fader
        if crossfader != 0 { crossfader = 0 }
        let other = decks.first { $0 !== deck }?.fader ?? 0.85
        if deck.fader < max(other, 0.5) { deck.fader = max(other, 0.5) }
        let faderNow = deck.fader
        return { [weak self, weak deck] in
            if let self, self.crossfader == 0 { self.crossfader = crossfaderWas }
            if let deck, deck.fader == faderNow { deck.fader = faderWas }
        }
    }

    func updateVolumes() {
        let (a, b) = crossfaderGains()
        // Mix knob: centre plays both at full level, each end fades the other out.
        let cueLevel = min(1, 2 * (1 - headphoneMix))
        let programInCue = min(1, 2 * headphoneMix)
        let automatic = UserDefaults.standard.object(forKey: "autoGain") as? Bool ?? true
        for deck in decks {
            let xf = deck.index == 0 ? a : b
            let trim = pow(10, (deck.trim * 12 + (automatic ? deck.autoGainDB : 0)) / 20)
            let fader = deck.fader * deck.fader * xf
            channelGains[deck.index] = fader * trim
            deck.channelTrim = trim
            cheeks_engine_set_channel(core, Int32(deck.index), trim, fader, deck.headphoneCue ? cueLevel : 0)
        }
        cheeks_engine_set_master(core, masterVolume, headphoneVolume, programInCue, splitCue)
    }

    /// The cue only reaches anyone with SPLIT on, as without it the output's all the mix. A key that lights and changes
    /// nothing you can hear looks broken, so it says so.
    func toggleCue(_ deck: Deck) {
        deck.headphoneCue.toggle()
        if deck.headphoneCue, !splitCue { say("You'll hear the cue with SPLIT on and a splitter cable.", .info) }
    }

    // MARK: Loading

    /// Loads a track, unless the deck is playing: replacing a track mid-set by mistake is the worst
    /// thing a DJ app can do. A refused load shakes off with a little buzz.
    @discardableResult
    func load(_ track: Track, onto deck: Deck) -> Bool {
        guard !deck.isPlaying else {
            refuseLoad(onto: deck)
            return false
        }
        guard library?.isMissing(track) != true else {
            say("\(track.title)'s file is missing. Import it again and it'll get its cues back.", .refused)
            return false
        }
        Haptics.shared.load()
        deck.load(track)
        return true
    }

    /// Says why a load didn't happen.
    func refuseLoad(onto deck: Deck) {
        say("Deck \(deck.index + 1) is playing. Stop it first.", .refused)
    }

    /// Puts up a message with `UNDO` beside it.
    func offerUndo(_ message: String, _ kind: StatusKind, undo: @escaping @MainActor () -> Void) {
        say(message, kind)
        undoAction = undo
    }

    /// Puts up a message. A refusal also buzzes, so it's felt as well as seen.
    func say(_ message: String, _ kind: StatusKind = .info) {
        statusMessage = message
        statusKind = kind
        if kind == .refused { Haptics.shared.deny() }
    }

    // MARK: Sampler and preview

    /// Auditions a track from about a quarter of the way in, where the music has usually started.
    func togglePreview(_ track: Track) {
        if previewingTrack == track.id {
            stopPreview()
            return
        }
        stopPreview()
        guard let library, !library.isMissing(track) else {
            Haptics.shared.deny()
            return
        }
        previewingTrack = track.id
        let id = track.id, url = library.url(for: track)
        Task.detached(priority: .userInitiated) {
            guard let pcm = try? AudioDecoder.decode(url: url, sampleRate: AudioConfig.sampleRate) else { return }
            await MainActor.run {
                guard self.previewingTrack == id else { return }
                self.previewPCM = pcm
                cheeks_engine_set_preview(self.core, pcm.data, Int64(pcm.frames))
                cheeks_engine_seek_preview(self.core, Double(pcm.frames) * 0.25)
                // Without a split cable there's no cue bus to hear, so it plays through the master, more quietly.
                cheeks_engine_set_preview_routing(self.core, 1, self.splitCue ? 0 : 0.7)
                cheeks_engine_set_preview_playing(self.core, true)
                if !self.splitCue, self.decks.contains(where: \.isPlaying) {
                    self.say("This preview's over the mix, as SPLIT's off. It won't be on a recording.", .info)
                }
            }
        }
    }

    func stopPreview() {
        previewingTrack = nil
        cheeks_engine_set_preview_playing(core, false)
        cheeks_engine_set_preview(core, nil, 0)
        previewPCM = nil
    }

    /// How far through the preview is, 0...1. Not observed; poll it.
    var previewFraction: CGFloat {
        guard let frames = previewPCM?.frames, frames > 0 else { return 0 }
        return CGFloat(cheeks_engine_preview_position(core) / Double(frames))
    }

    /// Renders the whole mix offline, for tests.
    func renderOffline(frames: Int) -> (left: [Float], right: [Float]) {
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                cheeks_engine_render(core, l.baseAddress!, r.baseAddress!, Int32(frames))
            }
        }
        return (left, right)
    }

    func tickForTesting() { tick() }

    /// Stops the realtime audio engine, so a test can render by hand without a second thread rendering too.
    func stopRealtimeForTesting() {
        audioQueue.sync { engine.stop() }
    }

    // MARK: Sync & housekeeping

    /// The deck a given deck syncs to: the tempo master, or the other deck if it's the master itself.
    func master(for deck: Deck) -> Deck {
        masterIndex == deck.index ? decks[1 - deck.index] : decks[masterIndex]
    }

    func setMaster(_ deck: Deck) {
        masterIndex = deck.index
        deck.syncOn = false
    }

    /// A deck that isn't playing can't lead, so the first deck to start playing takes over.
    private func updateMaster() {
        let current = decks[masterIndex]
        if current.isPlaying && current.isLoaded { return }
        // What a stopped deck was following has run out, or gone for a new load, and nobody's heard it at that speed. Left there,
        // it led the next track to it: a 126 went to 85, following a stopped 128 that was still at 170.
        if !current.isLoaded || current.isAtEnd {
            for deck in decks where deck !== current && deck.syncOn && !deck.isPlaying { deck.backToOwnSpeed() }
        }
        // The top bar read "MASTER 2 –" for an empty deck, with a track on deck 1.
        if !current.isLoaded, !current.isPlaying, let loaded = decks.first(where: { $0.isLoaded }) { masterIndex = loaded.index }
        if let playing = decks.first(where: { $0.isPlaying && $0.isLoaded && !$0.syncOn }) ?? decks.first(where: { $0.isPlaying && $0.isLoaded }) {
            masterIndex = playing.index
            if playing.syncOn {
                playing.syncOn = false
                // Playing, so it can't just change speed. But SYNC's light going out was all that said so, at 31% from its own.
                if abs(playing.tempo) > Self.farToStretch {
                    say(String(format: "Deck %d has nothing to follow now, and stays at %.0f BPM, %.0f%% %@ than its own.", playing.index + 1, playing.effectiveBPM, abs(playing.tempo), playing.tempo < 0 ? "slower" : "faster"), .info)
                }
            }
        }
    }

    func toggleSync(_ deck: Deck) {
        if deck.syncOn {
            deck.syncOn = false
        } else {
            let leader = master(for: deck)
            guard leader.isLoaded else {
                say("There's nothing to sync to yet: the other deck's empty.", .refused)
                return
            }
            // On the only deck playing, it took what's on air to the tempo of a stopped deck: 170 to 125, in one press, with a
            // first-time user and then a tester each caught by it. Real decks don't follow anything nobody can hear.
            if masterIndex == deck.index, deck.isPlaying, !leader.isPlaying {
                say("Deck \(deck.index + 1)'s the master, with nothing playing to follow. SYNC on deck \(leader.index + 1) brings that one to this tempo.", .refused)
                return
            }
            // A track that's over has no tempo worth following. A first-time user's 126 went to 85 from one sitting at 170, on its
            // way to a track 2 BPM from it, and that was the worst thing about the app for them.
            if leader.isAtEnd {
                say("Deck \(leader.index + 1)'s track has finished, so there's no tempo to follow. Load the next one first.", .refused)
                return
            }
            // Syncing the master means following the other deck, so that one has to lead.
            if masterIndex == deck.index { masterIndex = leader.index }
            let settlesOn = deck.matchedBPM(for: leader.effectiveBPM), theirs = leader.effectiveBPM
            let tempoWas = deck.tempo, rangeWas = deck.tempoRange
            deck.sync(to: leader)
            // Both of these are a big change someone may not have meant, and the way back was hard to find.
            let undo = { [weak deck] in
                deck?.syncOn = false
                deck?.setTempo(tempoWas)
                deck?.tempoRange = rangeWas
            }
            // A first-time user's 126 went to 85 with nothing to say why, and stayed there when the other deck ended.
            if deck.isLoaded, deck.bpm > 0, settlesOn != theirs {
                deck.offerUndo?("Deck \(deck.index + 1) follows at \(settlesOn < theirs ? "half" : "double") tempo: \(String(format: "%.0f", settlesOn)) against \(String(format: "%.0f", theirs)).", .info, undo)
            } else if deck.isLoaded, abs(deck.tempo) > Self.farToStretch {
                // A long way to stretch a track can be heard, and 170 going to 128 had nothing to say so, where half tempo did.
                deck.offerUndo?(String(format: "Deck %d is now %.0f%% %@ than its own %.0f BPM, to follow.", deck.index + 1, abs(deck.tempo), deck.tempo < 0 ? "slower" : "faster", deck.bpm), .info, undo)
            }
        }
    }

    /// Percent. Past this, stretching starts to be heard.
    private static let farToStretch = 12.0

    /// A phone's browser covers the decks, and track after track ran out behind it with nothing said. The browser asks, while it's
    /// open. Only for what the music depends on: not with the other deck playing as well, and a mix sees to itself.
    func warnIfRunningOut() {
        let playing = decks.filter(\.isPlaying)
        guard playing.count == 1, let deck = playing.first, let id = deck.track?.id, id != warnedRunningOut,
              statusMessage == nil, autoDJ.phase == .idle, autoDJ.mixSet == nil, !deck.renderer.loopActive else { return }
        let left = deck.timeLeft
        guard left <= Self.runningOut, left >= 1 else { return }
        warnedRunningOut = id
        say("Deck \(deck.index + 1) runs out in \(Int(left)) s.", .info)
    }

    /// Seconds. The deck's own clock goes red from here too.
    private static let runningOut = 30.0
    @ObservationIgnored private var warnedRunningOut: UUID?

    /// The track someone could hear has stopped, and what's still playing can't reach the output. A first-time user's track ran
    /// out with the crossfader over on it, and the other played on for 2 minutes with the meters dark.
    private func noticeNothingComingOut() {
        let heard = decks.first { $0.isPlaying && channelGains[$0.index] > 0.05 }?.index
        defer { heardDeck = heard }
        guard heard == nil, autoDJ.phase == .idle, autoDJ.mixSet == nil, let left = decks.first(where: \.isPlaying) else {
            ticksUnheard = 0
            return
        }
        let why = crossfaderGain(for: left) < 0.05 ? "the crossfader away from it" : "its fader down"
        if let was = heardDeck, !decks[was].isPlaying {
            ticksUnheard = Self.ticksBeforeSayingUnheard + 1
            say("Deck \(was + 1) has stopped, and deck \(left.index + 1) is playing with \(why). Nothing's coming out.", .problem)
            return
        }
        // A deck started with its fader down, and nothing else on. The deck's own meter moves, as it reads ahead of the fader, and only
        // the mix's stay empty: a first-time user sat at that for 15 s. Someone cueing it in their headphones means to.
        ticksUnheard += 1
        if ticksUnheard == Self.ticksBeforeSayingUnheard, !decks.contains(where: { $0.headphoneCue || $0.cuePreviewing }) {
            say("Deck \(left.index + 1) is playing with \(why). Nothing's coming out.", .problem)
        }
    }

    @ObservationIgnored private var heardDeck: Int?
    @ObservationIgnored private var ticksUnheard = 0
    /// 2 s at 30 a second. Anyone starting a deck and bringing the fader up has done so by then.
    private static let ticksBeforeSayingUnheard = 60

    func performUndo() {
        undoAction?()
        undoAction = nil
        statusMessage = nil
    }

    private func tick() {
        decks.forEach { $0.tick() }
        autoDJ.tick()
        sampler.tick()
        let working = limiterReduction > 0.5
        if working != limiterWorking { limiterWorking = working }
        updateMaster()
        noticeNothingComingOut()
        for deck in decks where deck.syncOn && deck.index != masterIndex {
            let master = decks[masterIndex]
            guard master.isLoaded, master.bpm > 0, deck.bpm > 0 else { continue }
            // Follow the master's tempo…
            let wanted = (deck.matchedBPM(for: master.effectiveBPM) / deck.bpm - 1) * 100
            if abs(wanted - deck.tempoRatioPercent) > 0.0005 { deck.setTempo(wanted) }
            // …and gently correct phase while both play. Both decks run on one clock, so this
            // only ever has to undo a jog nudge, a jump or the tempo glide at the moment sync engages.
            if deck.isPlaying && master.isPlaying && !deck.renderer.scratching && deck.renderer.pendingNudge == 0 {
                let frames = positions
                let drift = deck.phaseOffset(to: master, frame: frames[deck.index], masterFrame: frames[master.index])
                if abs(drift) > 0.0002 { deck.alignPhase(to: master, smoothly: true) }
            }
        }
        trackOnAir()
        nowPlaying?.update()
        if isRecording && recorder.didFail {
            stopRecording()
            say("Recording stopped: storage is full. Everything up to now was saved.", .problem)
        }
    }

    /// A track counts as played once it has been audible on the master for 10 seconds,
    /// like DJ software's history. It goes into today's History playlist and the recording's tracklist.
    private func trackOnAir() {
        let now = Date()
        for deck in decks {
            let i = deck.index
            let audible = deck.isPlaying && channelGains[i] > 0.05
            if let track = deck.track, historyLog.update(deck: i, track: track.id, audible: audible, now: now) != nil {
                library?.logPlay(track.id)
                heardThisSession.insert(track.id)
            }
            guard isRecording else { continue }
            if let since = setlistLog.update(deck: i, track: deck.track?.id, audible: audible, now: now) {
                // Position in the captured audio when the track became audible.
                appendToSetlist(deck, at: recorder.recordedSeconds - now.timeIntervalSince(since))
            }
        }
    }

    private func appendToSetlist(_ deck: Deck, at offset: TimeInterval) {
        guard let entry = SetlistEntry(heardOn: deck, at: offset), let caf = recordingURL else { return }
        setlist.append(entry)
        setlist.sort { $0.offset < $1.offset }
        Setlist.save(setlist, forRecording: caf) // kept on disk so a crash doesn't lose the tracklist
    }

    // MARK: Recording

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        let minutesLeft = Recordings.minutesOfStorageLeft()
        if let minutesLeft, minutesLeft < 10 {
            say("Not enough free space to record.", .refused)
            return
        }
        let url = Recordings.directory.appending(path: Recordings.newBaseName() + Recordings.inProgressSuffix)
        let format = AVAudioFormat(standardFormatWithSampleRate: AudioConfig.sampleRate, channels: 2)!
        do {
            try recorder.start(url: url, format: format)
        } catch {
            say("Couldn't start recording.", .problem)
            return
        }
        recordingDrain = RecordingDrain(core: core, recorder: recorder, format: format)
        recordingURL = url
        recordingStarted = Date()
        isRecording = true
        setlist = []
        // Tracks already on air start the tracklist at 0:00, once they've had their 10 s; the rest are added as they come in.
        setlistLog = OnAirLog()
        trackOnAir()
        if let minutesLeft, minutesLeft < 120 {
            say("Free space for about \(Int(minutesLeft)) min of recording.", .info)
        }
    }

    private func stopRecording() {
        cheeks_engine_set_recording(core, false)
        isRecording = false
        recordingStarted = nil
        let caf = recordingURL
        recordingURL = nil
        // The tail of the ring reaches the file and the file closes before it's converted.
        recordingDrain?.finish { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let caf { self?.finalize(caf, recovered: false) }
                }
            }
        }
        recordingDrain = nil
    }

    /// Converts the raw capture to the chosen format in the background and writes the tracklist.
    private func finalize(_ caf: URL, recovered: Bool) {
        savingRecordings += 1
        let format = recordingFormat
        Task.detached(priority: .userInitiated) {
            let message: String
            let kind: StatusKind
            do {
                let saved = try RecordingFinalizer.finalize(caf, format: format, recovered: recovered)
                message = (recovered ? "Recovered " : "Saved ") + saved.deletingPathExtension().lastPathComponent
                kind = .done
            } catch RecordingFinalizer.FinalizeError.empty {
                message = "The recording was empty, so nothing was saved."
                kind = .info
            } catch {
                message = "Couldn't convert a recording; the full-quality raw file is in Recordings."
                kind = .problem
            }
            await MainActor.run {
                self.savingRecordings -= 1
                self.say(message, kind)
            }
        }
    }
}

extension Deck {
    var tempoRatioPercent: Double { (tempoRatio - 1) * 100 }
}
