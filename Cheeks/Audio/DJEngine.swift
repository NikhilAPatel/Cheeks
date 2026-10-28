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

    var crossfader: Float = 0 { didSet { updateVolumes() } }
    var crossfaderCurve: CrossfaderCurve = .smooth { didSet { updateVolumes() } }
    var masterVolume: Float = 0.9 { didSet { engine.mainMixerNode.outputVolume = masterVolume } }
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
    private let recorder = Recorder()

    @ObservationIgnored private var timer: Timer?

    static let fxBeatChoices: [Double] = [1.0 / 8, 1.0 / 4, 1.0 / 2, 3.0 / 4, 1, 2, 4, 8]

    init(library: Library) {
        decks = [Deck(index: 0), Deck(index: 1)]
        for deck in decks {
            deck.library = library
            deck.onMixChange = { [weak self] in
                self?.updateVolumes()
                self?.applyFX()
            }
        }
        buildGraph()
        configureSession()
        start()
        observeSession()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    // MARK: Graph

    private func buildGraph() {
        let format = AVAudioFormat(standardFormatWithSampleRate: AudioConfig.sampleRate, channels: 2)!
        for deck in decks {
            let chain: [AVAudioNode] = [deck.renderer.node, deck.varispeed, deck.timePitch, deck.eq, deck.delay, deck.reverb, deck.channel]
            chain.forEach(engine.attach)
            for (from, to) in zip(chain, chain.dropFirst()) {
                engine.connect(from, to: to, format: format)
            }
            engine.connect(deck.channel, to: engine.mainMixerNode, format: format)
            Self.installTap(on: deck.channel, recorder: nil) { [weak deck] level in deck?.level = level }
        }
        engine.mainMixerNode.outputVolume = masterVolume
        Self.installTap(on: engine.mainMixerNode, recorder: recorder) { [weak self] level in self?.masterLevel = level }
        updateVolumes()
    }

    /// Level meter tap (and, for the master bus, the recorder). Nonisolated so the tap
    /// closure is not tied to the main actor; it runs on an AVAudioEngine thread.
    nonisolated private static func installTap(on node: AVAudioNode, recorder: Recorder?, update: @escaping @MainActor (Float) -> Void) {
        node.installTap(onBus: 0, bufferSize: 2048, format: node.outputFormat(forBus: 0)) { buffer, _ in
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
        for deck in decks {
            let xf = deck.index == 0 ? a : b
            let trim = pow(10, deck.trim * 12 / 20)
            deck.channel.outputVolume = deck.fader * deck.fader * xf * trim
        }
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
    }

    // MARK: Recording

    func toggleRecording() {
        if isRecording {
            recorder.stop()
            isRecording = false
            recordingStarted = nil
            return
        }
        let dir = URL.documentsDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let stamp = formatter.string(from: Date())
        let url = dir.appending(path: "Mix \(stamp).m4a")
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        if recorder.start(url: url, format: format) {
            isRecording = true
            recordingStarted = Date()
        } else {
            engineError = "Couldn't start recording"
        }
    }
}

extension Deck {
    var tempoRatioPercent: Double { (tempoRatio - 1) * 100 }
}

/// Writes the master output to an AAC file from the tap thread.
final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?

    func start(url: URL, format: AVAudioFormat) -> Bool {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitRateKey: 256_000,
        ]
        guard let newFile = try? AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false) else {
            return false
        }
        lock.withLock { file = newFile }
        return true
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { try? file?.write(from: buffer) }
    }

    func stop() {
        lock.withLock { file = nil }
    }
}
