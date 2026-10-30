import Accelerate
import AVFoundation
import Observation

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
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let core: OpaquePointer
    @ObservationIgnored private var sourceNode: AVAudioSourceNode?
    /// Session and engine calls can block for a while, so they stay off the main thread.
    @ObservationIgnored private let audioQueue = DispatchQueue(label: "com.nikhilpatel.cheeks.audio-session", qos: .userInitiated)

    var crossfader: Float = 0 { didSet { updateVolumes() } }
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
    var limiterReduction: Float { cheeks_engine_limiter_reduction(core) }
    var cpuLoad: Float { cheeks_engine_load(core) }
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
    /// Short message for the top bar (saved, low storage, errors).
    var statusMessage: String?
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

    init(library: Library) {
        let newDecks = [Deck(index: 0), Deck(index: 1)]
        let handles: [OpaquePointer?] = newDecks.map { $0.renderer.handle }
        decks = newDecks
        core = handles.withUnsafeBufferPointer { cheeks_engine_create(AudioConfig.sampleRate, $0.baseAddress, Int32($0.count)) }
        self.library = library
        for deck in decks {
            deck.library = library
            deck.onMixChange = { [weak self] in self?.updateVolumes() }
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
        // Recordings interrupted by a crash or the app being killed get saved now.
        for caf in Recordings.unfinished() { finalize(caf, recovered: true) }
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
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
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
        for deck in decks {
            let xf = deck.index == 0 ? a : b
            let trim = pow(10, deck.trim * 12 / 20)
            let fader = deck.fader * deck.fader * xf
            channelGains[deck.index] = fader * trim
            cheeks_engine_set_channel(core, Int32(deck.index), trim, fader, deck.headphoneCue ? cueLevel : 0)
        }
        cheeks_engine_set_master(core, masterVolume, headphoneVolume, programInCue, splitCue)
    }

    // MARK: Sampler and preview

    func setSample(_ slot: Int, pcm: PCM16Stereo) {
        cheeks_engine_set_sample(core, Int32(slot), pcm.data, Int64(pcm.frames))
    }

    func triggerSample(_ slot: Int, gain: Float = 1) { cheeks_engine_trigger_sample(core, Int32(slot), gain) }
    func stopSample(_ slot: Int) { cheeks_engine_stop_sample(core, Int32(slot)) }
    func isSampleActive(_ slot: Int) -> Bool { cheeks_engine_sample_active(core, Int32(slot)) }

    func setPreview(pcm: PCM16Stereo?) {
        cheeks_engine_set_preview(core, pcm?.data, Int64(pcm?.frames ?? 0))
    }

    func setPreviewPlaying(_ playing: Bool) {
        // Without a split cable there's no cue bus to hear, so it plays through the master at a safe level.
        cheeks_engine_set_preview_routing(core, 1, splitCue ? 0 : 0.8)
        cheeks_engine_set_preview_playing(core, playing)
    }

    func seekPreview(toFrame frame: Double) { cheeks_engine_seek_preview(core, frame) }
    var previewFrame: Double { cheeks_engine_preview_position(core) }

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
            deck.sync(to: master(for: deck))
        }
    }

    private func tick() {
        decks.forEach { $0.tick() }
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
                let drift = deck.phaseOffset(to: master)
                if abs(drift) > 0.0002 { deck.alignPhase(to: master, smoothly: true) }
            }
        }
        trackOnAir()
        if isRecording && recorder.didFail {
            stopRecording()
            statusMessage = "Recording stopped: storage is full. Everything up to now was saved."
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
            statusMessage = "Not enough free space to record."
            return
        }
        let url = Recordings.directory.appending(path: Recordings.newBaseName() + Recordings.inProgressSuffix)
        let format = AVAudioFormat(standardFormatWithSampleRate: AudioConfig.sampleRate, channels: 2)!
        do {
            try recorder.start(url: url, format: format)
        } catch {
            statusMessage = "Couldn't start recording."
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
            statusMessage = "Free space for about \(Int(minutesLeft)) min of recording."
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
            do {
                let saved = try RecordingFinalizer.finalize(caf, format: format, recovered: recovered)
                message = (recovered ? "Recovered " : "Saved ") + saved.deletingPathExtension().lastPathComponent
            } catch RecordingFinalizer.FinalizeError.empty {
                message = "The recording was empty, so nothing was saved."
            } catch {
                message = "Couldn't convert a recording; the full-quality raw file is in Recordings."
            }
            await MainActor.run {
                self.savingRecordings -= 1
                self.statusMessage = message
            }
        }
    }
}

extension Deck {
    var tempoRatioPercent: Double { (tempoRatio - 1) * 100 }
}
