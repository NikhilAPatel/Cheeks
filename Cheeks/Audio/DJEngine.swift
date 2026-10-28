import Accelerate
import AVFoundation
import Observation

enum BeatFX: String, CaseIterable, Identifiable {
    case echo = "ECHO"
    case reverb = "REVERB"
    case roll = "ROLL"
    case brake = "BRAKE"
    var id: String { rawValue }
}

enum CrossfaderCurve: String, CaseIterable, Identifiable {
    case smooth = "SMOOTH"
    case scratch = "SCRATCH"
    var id: String { rawValue }
}

/// The mixer: owns the AVAudioEngine graph, both decks, crossfader, Beat FX, sync and recording.
@MainActor
@Observable
final class DJEngine {
    let engine = AVAudioEngine()
    let decks: [Deck]
    /// The audience mix (both channels after faders/crossfader). Recorded and metered here.
    private let program = AVAudioMixerNode()
    /// Mono copy of the program for the left ear in split-cue mode.
    private let monoMaster = AVAudioMixerNode()
    /// Headphone bus: pre-fader cue sends plus some program, mono, right ear in split-cue mode.
    private let cueBus = AVAudioMixerNode()

    var crossfader: Float = 0 { didSet { updateVolumes() } }
    var crossfaderCurve: CrossfaderCurve = .smooth { didSet { updateVolumes() } }
    var masterVolume: Float = 0.9 { didSet { updateVolumes() } }

    // Headphones
    /// Split cue: master (mono) in the left ear, cue (mono) in the right — for a headphone splitter cable.
    var splitCue = false { didSet { updateVolumes() } }
    /// 0 = cue only, 0.5 = both, 1 = master only (in the cue ear).
    var headphoneMix: Float = 0.25 { didSet { updateVolumes() } }
    var headphoneVolume: Float = 0.8 { didSet { updateVolumes() } }
    var masterLevel: Float = 0
    var engineError: String?

    // Beat FX
    var fxType: BeatFX = .echo {
        willSet { if fxOn && newValue != fxType { fxOn = false } }
        didSet { applyFX() }
    }
    var fxBeats: Double = 0.5 { didSet { applyFX() } }
    var fxLevel: Float = 0.5 { didSet { applyFX() } }
    /// 0 = deck 1, 1 = deck 2, 2 = both
    var fxTarget = 2 { didSet { applyFX() } }
    var fxOn = false { didSet { fxToggled(oldValue) } }

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
    @ObservationIgnored private var recordingURL: URL?
    @ObservationIgnored private weak var library: Library?

    // On-air detection for the tracklist and History playlists
    @ObservationIgnored private var onAirSince: [Date?] = [nil, nil]
    @ObservationIgnored private var loggedTrack: [UUID?] = [nil, nil]
    private static let onAirSeconds: TimeInterval = 10

    @ObservationIgnored private var timer: Timer?

    static let fxBeatChoices: [Double] = [1.0 / 8, 1.0 / 4, 1.0 / 2, 3.0 / 4, 1, 2, 4, 8]

    init(library: Library) {
        decks = [Deck(index: 0), Deck(index: 1)]
        self.library = library
        for deck in decks {
            deck.library = library
            deck.onMixChange = { [weak self] in
                self?.updateVolumes()
                self?.applyFX()
            }
        }
        configureSession()
        buildGraph()
        start()
        observeSession()
        // .common mode keeps sync and transport state updating while a list is being scrolled.
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // Recordings interrupted by a crash or the app being killed get saved now.
        for caf in Recordings.unfinished() { finalize(caf) }
    }

    // MARK: Graph

    /// deck chain → channel fader → program ─┬─────────────→ main (normal)
    ///            ↘ cue send ──→ cue bus ←────┤               main L (split)
    ///                               └─ mono → main R (split)  └→ mono master ─┘
    private func buildGraph() {
        let stereo = AVAudioFormat(standardFormatWithSampleRate: AudioConfig.sampleRate, channels: 2)!
        let mono = AVAudioFormat(standardFormatWithSampleRate: AudioConfig.sampleRate, channels: 1)!
        let main = engine.mainMixerNode
        [program, monoMaster, cueBus].forEach(engine.attach)

        for deck in decks {
            let chain: [AVAudioNode] = [deck.renderer.node, deck.varispeed, deck.timePitch, deck.eq, deck.delay, deck.reverb]
            (chain + [deck.channel, deck.cueSend]).forEach(engine.attach)
            for (from, to) in zip(chain, chain.dropFirst()) {
                engine.connect(from, to: to, format: stereo)
            }
            // Fan out after FX: one path to the channel fader, one pre-fader to the cue bus.
            engine.connect(deck.reverb, to: [AVAudioConnectionPoint(node: deck.channel, bus: 0),
                                             AVAudioConnectionPoint(node: deck.cueSend, bus: 0)],
                           fromBus: 0, format: stereo)
            engine.connect(deck.channel, to: program, fromBus: 0, toBus: deck.index, format: stereo)
            engine.connect(deck.cueSend, to: cueBus, fromBus: 0, toBus: deck.index, format: stereo)
            Self.installTap(on: deck.channel, recorder: nil) { [weak deck] level in deck?.level = level }
        }

        engine.connect(program, to: [AVAudioConnectionPoint(node: main, bus: 0),
                                     AVAudioConnectionPoint(node: monoMaster, bus: 0),
                                     AVAudioConnectionPoint(node: cueBus, bus: 2)],
                       fromBus: 0, format: stereo)
        engine.connect(monoMaster, to: main, fromBus: 0, toBus: 1, format: mono)
        engine.connect(cueBus, to: main, fromBus: 0, toBus: 2, format: mono)
        monoMaster.pan = -1
        cueBus.pan = 1
        main.outputVolume = 1

        Self.installTap(on: program, recorder: recorder) { [weak self] level in
            guard let self else { return }
            masterLevel = level * masterVolume
        }
        updateVolumes()
    }

    /// Level meter tap (and, for the master bus, the recorder). Nonisolated so the tap
    /// closure is not tied to the main actor; it runs on an AVAudioEngine thread.
    nonisolated private static func installTap(on node: AVAudioNode, recorder: MixRecorder?, update: @escaping @MainActor (Float) -> Void) {
        node.installTap(onBus: 0, bufferSize: 2048, format: nil) { buffer, _ in
            recorder?.write(buffer)
            let level = peak(buffer)
            Task { @MainActor in update(level) }
        }
    }

    nonisolated private static func peak(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData else { return 0 }
        var peak: Float = 0
        for ch in 0..<Int(buffer.format.channelCount) {
            var m: Float = 0
            vDSP_maxmgv(data[ch], 1, &m, vDSP_Length(buffer.frameLength))
            peak = max(peak, m)
        }
        return peak
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setPreferredSampleRate(AudioConfig.sampleRate)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            engineError = "Audio session: \(error.localizedDescription)"
        }
    }

    func start() {
        guard !engine.isRunning else { return }
        do {
            engine.prepare()
            try engine.start()
            engineError = nil
        } catch {
            engineError = "Audio engine: \(error.localizedDescription)"
        }
    }

    private func observeSession() {
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated {
                if raw == AVAudioSession.InterruptionType.ended.rawValue {
                    try? AVAudioSession.sharedInstance().setActive(true)
                    self?.start()
                }
            }
        }
        center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.start() }
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
            deck.channel.outputVolume = deck.fader * deck.fader * xf * trim
            deck.cueSend.outputVolume = deck.headphoneCue ? cueLevel * trim : 0
        }
        let main = engine.mainMixerNode
        program.destination(forMixer: main, bus: 0)?.volume = splitCue ? 0 : masterVolume
        program.destination(forMixer: cueBus, bus: 2)?.volume = programInCue
        monoMaster.outputVolume = splitCue ? masterVolume : 0
        cueBus.outputVolume = splitCue ? headphoneVolume : 0
    }

    // MARK: Beat FX

    private var fxDecks: [Deck] { fxTarget == 2 ? decks : [decks[fxTarget]] }

    func applyFX() {
        for deck in decks {
            let active = fxOn && fxDecks.contains { $0 === deck }
            let bpm = deck.effectiveBPM > 0 ? deck.effectiveBPM : 120
            deck.delay.delayTime = min(2, fxBeats * 60 / bpm)
            deck.delay.wetDryMix = active && fxType == .echo ? fxLevel * 70 : 0
            deck.delay.feedback = 35 + fxLevel * 35
            deck.delay.bypass = !(active && fxType == .echo)
            deck.reverb.wetDryMix = active && fxType == .reverb ? fxLevel * 80 : 0
            deck.reverb.bypass = !(active && fxType == .reverb)
        }
    }

    private func fxToggled(_ wasOn: Bool) {
        guard wasOn != fxOn else { return }
        switch fxType {
        case .roll:
            for deck in fxDecks { fxOn ? deck.rollBegin(fxBeats) : deck.rollEnd() }
        case .brake:
            if fxOn {
                for deck in fxDecks { deck.brake(beats: max(fxBeats, 1) * 2) }
            }
        case .echo, .reverb:
            break
        }
        applyFX()
    }

    // MARK: Sync & housekeeping

    /// The deck others sync to: the other deck when one is synced, else whichever is playing.
    func master(for deck: Deck) -> Deck {
        decks[1 - deck.index]
    }

    func toggleSync(_ deck: Deck) {
        if deck.syncOn {
            deck.syncOn = false
        } else {
            deck.sync(to: master(for: deck))
        }
    }

    private func tick() {
        for deck in decks {
            deck.tick()
            guard deck.syncOn else { continue }
            let master = master(for: deck)
            guard master.isLoaded, master.bpm > 0, !master.syncOn || master.index == 0 else { continue }
            // Follow the master's tempo…
            let wanted = (deck.matchedBPM(for: master.effectiveBPM) / deck.bpm - 1) * 100
            if abs(wanted - deck.tempoRatioPercent) > 0.001 { deck.setTempo(wanted) }
            // …and gently correct any phase drift while both play.
            if deck.isPlaying && master.isPlaying && !deck.renderer.scratching && deck.renderer.pendingNudge == 0 {
                let drift = deck.phaseOffset(to: master)
                if abs(drift) > 0.02 { deck.alignPhase(to: master, smoothly: true) }
            }
        }
        if fxOn && fxType == .brake && !fxDecks.contains(where: { $0.renderer.braking }) {
            fxOn = false
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
            guard let track = deck.track, deck.isPlaying, deck.channel.outputVolume > 0.05 else {
                onAirSince[i] = nil
                continue
            }
            let since = onAirSince[i] ?? now
            onAirSince[i] = since
            guard loggedTrack[i] != track.id, now.timeIntervalSince(since) >= Self.onAirSeconds else { continue }
            loggedTrack[i] = track.id
            library?.logPlay(track.id)
            if isRecording, let start = recordingStarted {
                appendToSetlist(deck, at: since.timeIntervalSince(start))
            }
        }
    }

    private func appendToSetlist(_ deck: Deck, at offset: TimeInterval) {
        guard let track = deck.track, let caf = recordingURL else { return }
        setlist.append(SetlistEntry(offset: max(0, offset), title: track.title, artist: track.artist,
                                    bpm: deck.bpm > 0 ? deck.effectiveBPM : nil, key: track.key))
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
        do {
            try recorder.start(url: url, format: program.outputFormat(forBus: 0))
        } catch {
            statusMessage = "Couldn't start recording."
            return
        }
        recordingURL = url
        recordingStarted = Date()
        isRecording = true
        setlist = []
        // Tracks already playing out start the tracklist at 0:00.
        for deck in decks where deck.track != nil && loggedTrack[deck.index] == deck.track?.id && onAirSince[deck.index] != nil {
            appendToSetlist(deck, at: 0)
        }
        if let minutesLeft, minutesLeft < 120 {
            statusMessage = "Free space for about \(Int(minutesLeft)) min of recording."
        }
    }

    private func stopRecording() {
        recorder.stop()
        isRecording = false
        recordingStarted = nil
        guard let caf = recordingURL else { return }
        recordingURL = nil
        finalize(caf)
    }

    /// Converts the raw capture to the chosen format in the background and writes the tracklist.
    private func finalize(_ caf: URL) {
        savingRecordings += 1
        let format = recordingFormat
        Task.detached(priority: .userInitiated) {
            let saved = try? RecordingFinalizer.finalize(caf, format: format)
            await MainActor.run {
                self.savingRecordings -= 1
                if let saved {
                    self.statusMessage = "Saved \(saved.deletingPathExtension().lastPathComponent)"
                } else {
                    self.statusMessage = "Couldn't convert a recording; the raw .caf is kept in Recordings."
                }
            }
        }
    }
}

extension Deck {
    var tempoRatioPercent: Double { (tempoRatio - 1) * 100 }
}
