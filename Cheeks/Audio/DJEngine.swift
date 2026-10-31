import Accelerate
import AVFoundation
import Observation

/// What a status message is saying, which decides how the capsule looks.
enum StatusKind {
    case done, info, refused, problem
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
    @ObservationIgnored private var sourceNode: AVAudioSourceNode?
    /// Session and engine calls can block for a while, so they stay off the main thread.
    @ObservationIgnored private let audioQueue = DispatchQueue(label: "com.nikhilpatel.cheeks.audio-session", qos: .userInitiated)

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
    var cpuLoad: Float { cheeks_engine_load(core) }
    /// True while the limiter's doing real work. Changes rarely, unlike the numbers above, so it's observed.
    private(set) var limiterWorking = false
    /// The engine's load in percent, in steps of 5, once it's high enough to mention. Otherwise 0.
    private(set) var loadWarning = 0
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
    /// A new message clears any Undo offered with the last one, which it'd no longer apply to.
    var statusMessage: String? {
        didSet {
            statusKind = .done
            undoAction = nil
        }
    }
    private(set) var statusKind: StatusKind = .done
    /// Set alongside a message when what just happened can be taken back.
    var undoAction: (@MainActor () -> Void)?

    // Preview
    /// The track being auditioned from the browser.
    private(set) var previewingTrack: UUID?
    @ObservationIgnored private var previewPCM: PCM16Stereo?
    private let recorder = MixRecorder()
    @ObservationIgnored private var recordingDrain: RecordingDrain?
    @ObservationIgnored private var recordingURL: URL?
    @ObservationIgnored private weak var library: Library?

    // On-air detection for the tracklist and History playlists
    @ObservationIgnored private var onAirSince: [Date?] = [nil, nil]
    /// Last track per deck added to History, and to the current recording's tracklist.
    @ObservationIgnored private var loggedTrack: [UUID?] = [nil, nil]
    @ObservationIgnored private var setlistTrack: [UUID?] = [nil, nil]
    private static let onAirSeconds: TimeInterval = 10

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
            deck.offerUndo = { [weak self] message, undo in
                self?.statusMessage = message
                self?.undoAction = undo
            }
        }
        buildGraph()
        updateVolumes()
        startAudio()
        observeSession()
        // .common mode keeps sync and transport state updating while a list is being scrolled.
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
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
            cheeks_engine_set_channel(core, Int32(deck.index), trim, fader, deck.headphoneCue ? cueLevel : 0)
        }
        cheeks_engine_set_master(core, masterVolume, headphoneVolume, programInCue, splitCue)
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
        if let playing = decks.first(where: { $0.isPlaying && $0.isLoaded && !$0.syncOn }) ?? decks.first(where: { $0.isPlaying && $0.isLoaded }) {
            masterIndex = playing.index
            playing.syncOn = false
        }
    }

    func toggleSync(_ deck: Deck) {
        if deck.syncOn {
            deck.syncOn = false
        } else {
            let leader = master(for: deck)
            // Syncing the master means following the other deck, so that one has to lead.
            if masterIndex == deck.index { masterIndex = leader.index }
            deck.sync(to: leader)
        }
    }

    func performUndo() {
        undoAction?()
        undoAction = nil
        statusMessage = nil
    }

    private func tick() {
        decks.forEach { $0.tick() }
        sampler.tick()
        let working = limiterReduction > 0.5
        if working != limiterWorking { limiterWorking = working }
        let load = cpuLoad
        let warning = load > 0.6 ? Int(load * 20) * 5 : 0
        if warning != loadWarning { loadWarning = warning }
        updateMaster()
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
    /// like rekordbox's history. It goes into today's History playlist and the recording's tracklist.
    private func trackOnAir() {
        let now = Date()
        for deck in decks {
            let i = deck.index
            guard let track = deck.track, deck.isPlaying, channelGains[i] > 0.05 else {
                onAirSince[i] = nil
                continue
            }
            let since = onAirSince[i] ?? now
            onAirSince[i] = since
            let audibleFor = now.timeIntervalSince(since)
            guard audibleFor >= Self.onAirSeconds else { continue }
            if loggedTrack[i] != track.id {
                loggedTrack[i] = track.id
                library?.logPlay(track.id)
            }
            if isRecording && setlistTrack[i] != track.id {
                setlistTrack[i] = track.id
                // Position in the captured audio when the track became audible.
                appendToSetlist(deck, at: recorder.recordedSeconds - audibleFor)
            }
        }
    }

    private func appendToSetlist(_ deck: Deck, at offset: TimeInterval) {
        guard let track = deck.track, let caf = recordingURL else { return }
        setlist.append(SetlistEntry(offset: max(0, offset), title: track.title, artist: track.artist,
                                    bpm: deck.bpm > 0 ? deck.effectiveBPM : nil, key: track.key))
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
        // Tracks already on air start the tracklist at 0:00; the rest are added as they come in.
        setlistTrack = [nil, nil]
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
