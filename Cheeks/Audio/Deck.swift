import AVFoundation
import Observation

enum PadMode: String, CaseIterable, Identifiable {
    case hotCue = "CUE"
    case memory = "MEM"
    case beatLoop = "LOOP"
    case roll = "ROLL"
    case slicer = "SLICER"
    case beatJump = "JUMP"
    case stems = "STEMS"
    case fx = "FX"
    case sampler = "SAMPLER"
    var id: String { rawValue }
}

/// Beat FX. Most run on the deck's FX bus in the realtime core; roll, brake and backspin work the transport.
enum BeatFX: String, CaseIterable, Identifiable {
    case echo = "ECHO"
    case pingPong = "PING PONG"
    case spiral = "SPIRAL"
    case reverb = "REVERB"
    case flanger = "FLANGER"
    case phaser = "PHASER"
    case filterLFO = "FILTER"
    case gate = "TRANS"
    case crush = "CRUSH"
    case roll = "ROLL"
    case brake = "BRAKE"
    case backspin = "BACKSPIN"
    var id: String { rawValue }

    /// The realtime effect, or none for the ones that work the transport instead.
    var dsp: CheeksFXType {
        switch self {
        case .echo: CheeksFXEcho
        case .pingPong: CheeksFXPingPong
        case .spiral: CheeksFXSpiral
        case .reverb: CheeksFXReverb
        case .flanger: CheeksFXFlanger
        case .phaser: CheeksFXPhaser
        case .filterLFO: CheeksFXFilterLFO
        case .gate: CheeksFXGate
        case .crush: CheeksFXCrush
        case .roll, .brake, .backspin: CheeksFXNone
        }
    }

    static let beatChoices: [Double] = [1.0 / 8, 1.0 / 4, 1.0 / 2, 3.0 / 4, 1, 2, 4, 8, 16, 32]
}

enum StemStatus: Equatable {
    case unavailable
    /// Progress is 0...1, or nil while it's waiting its turn or the model is loading.
    case separating(Double?)
    case ready(String)
    /// Track is longer than `AudioConfig.maxStemSeconds`; four stems wouldn't fit in memory.
    case tooLong
}

/// One player deck: transport, beat grid, cues, loops, sync, stems and its mixer channel.
/// Realtime audio lives in `renderer`; this class is the main-thread control surface.
@MainActor
@Observable
final class Deck {
    let index: Int
    /// The deck in the realtime core. Signal chain: stems → FX bus → stretcher (if needed) → isolator EQ → filter → channel.
    let renderer = DeckRenderer(sampleRate: AudioConfig.sampleRate)

    @ObservationIgnored weak var library: Library?
    /// Called when anything affecting channel volume or tempo-synced FX changes.
    @ObservationIgnored var onMixChange: (@MainActor () -> Void)?
    /// A message for the status capsule.
    @ObservationIgnored var onMessage: (@MainActor (String) -> Void)?
    @ObservationIgnored var stemJob: StemJob?
    /// Called after something destructive, to offer a way back.
    @ObservationIgnored var offerUndo: (@MainActor (String, @escaping @MainActor () -> Void) -> Void)?

    // Track
    var track: Track? { didSet { gridChanged() } }
    var waveform: WaveformData? { didSet { waveRevision += 1 } }
    /// Per-stem waveforms, available once the track has been split.
    var stemWaveform: StemWaveformData? { didSet { stemWaveRevision += 1 } }
    var artwork: CGImage?
    /// Bumped when a waveform changes, so the live views know to rebuild their textures.
    @ObservationIgnored private(set) var waveRevision = 0
    @ObservationIgnored private(set) var stemWaveRevision = 0
    /// Seconds between the render callback and the speaker, for drawing what's actually being heard.
    @ObservationIgnored var outputLatency: Double = 0
    /// Where the beats are, or nil without a grid.
    @ObservationIgnored private(set) var grid: BeatGrid?
    /// The section of a variable-tempo track that the audio core was last told about.
    @ObservationIgnored private var gridSection = 0
    /// The tempo at the playhead. Only changes during a track that has tempo changes in it.
    private(set) var bpm: Double = 0
    /// Gain that brings this track to the target loudness, in dB, from its analysis.
    private(set) var autoGainDB: Float = 0
    private(set) var isLoading = false
    /// Bumped on every load so a slow, superseded load can't replace a newer one.
    @ObservationIgnored private(set) var loadGeneration = 0
    private(set) var loadError: String?

    // Transport
    var isPlaying = false
    var cuePoint: Double = 0
    @ObservationIgnored var cuePreviewing = false
    var quantize = true
    var slipMode = false { didSet { if !slipMode { renderer.cancelSlip() } } }
    var reverse = false { didSet { setReverse() } }

    // Tempo
    private(set) var tempo: Double = 0 { didSet { applyTempo() } }
    var tempoRange: Double = 10
    var keyLock = true { didSet { applyTempo() } }
    var keyShift = 0 { didSet { applyTempo() } }
    var syncOn = false

    // Performance
    var padMode: PadMode = .hotCue
    /// Which page of the saved cues and loops is on the pads.
    var memoryPage = 0
    /// Roll and slicer pads being held, so letting go of one doesn't end the other.
    @ObservationIgnored var heldMomentaryPads = 0
    var shift = false
    var loopActive = false
    var loopBeats: Double = 4
    var jumpBeats: Double = 4
    var stemStatus: StemStatus = .unavailable
    var stemsOn: [Bool] = [true, true, true, true] { didSet { applyStemGains() } }
    /// Each stem's level (0...1), on top of its on/off state.
    var stemLevels: [Float] = [1, 1, 1, 1] { didSet { applyStemGains() } }
    /// Set when the stems were last heard all on, for restoring after a solo.
    @ObservationIgnored var stemsBeforeSolo: [Bool]?

    // Beat FX
    var fxType: BeatFX = .echo
    var fxOn = false
    var fxBeats: Double = 0.5 { didSet { applyFX() } }
    var fxDepth: Float = 0.6 { didSet { applyFX() } }
    /// The stems the FX bus is applied to; all of them, or the whole track without stems.
    var fxStems: Set<Stem> = Set(Stem.allCases) { didSet { applyFX() } }

    // Mixer channel (knobs are -1...1, 0 = centre)
    var trim: Float = 0 { didSet { onMixChange?() } }
    var eqHigh: Float = 0 { didSet { applyEQ() } }
    var eqMid: Float = 0 { didSet { applyEQ() } }
    var eqLow: Float = 0 { didSet { applyEQ() } }
    var filter: Float = 0 { didSet { applyFilter() } }
    var fader: Float = 0.85 { didSet { onMixChange?() } }
    var headphoneCue = false { didSet { onMixChange?() } }
    /// Channel level, pre-fader. Not observed; meters poll it.
    var level: Float { renderer.peak }

    init(index: Int) {
        self.index = index
        applyTempo()
        applyFX()
    }

    // MARK: Derived values

    var sampleRate: Double { AudioConfig.sampleRate }
    var tempoRatio: Double { 1 + tempo / 100 }
    var effectiveBPM: Double { bpm * tempoRatio }
    var isLoaded: Bool { renderer.frameCount > 0 && !isLoading }
    /// Current playhead in seconds. Not observed; views poll it from a TimelineView.
    var position: Double { renderer.playhead / sampleRate }
    /// Where the audio coming out of the speakers is right now, in frames: the published position,
    /// carried forward to this moment and pulled back by the output latency.
    func heardFrame(hostTime: UInt64, secondsPerTick: Double, outputLatency: Double) -> Double {
        let state = renderer.displayState
        let elapsed = hostTime > state.hostTime ? Double(hostTime - state.hostTime) * secondsPerTick : 0
        let ahead = min(elapsed, 0.05) - outputLatency
        return max(0, state.position + state.rate * ahead * sampleRate)
    }
    var duration: Double { Double(renderer.frameCount) / sampleRate }
    var beatFrames: Double { bpm > 0 ? 60 / bpm * sampleRate : 0 }
    /// Where beat 0 would be at the current tempo, counting back from the section being played.
    var firstBeatFrame: Double {
        guard let grid else { return (track?.firstBeat ?? 0) * sampleRate }
        let section = grid.sections[gridSection]
        return (section.time - section.beat * section.secondsPerBeat) * sampleRate
    }
    /// The key being heard, after key shift (and tempo too, when key lock is off).
    var effectiveKey: String? {
        guard let key = track?.key else { return nil }
        var semitones = keyShift
        if !keyLock { semitones += Int((12 * log2(tempoRatio)).rounded()) }
        return Camelot.shifted(key, by: semitones)
    }

    func beatPosition(_ frame: Double) -> Double {
        grid?.beat(at: frame / sampleRate) ?? 0
    }

    /// The frame a position on the beat grid falls on.
    func frame(atBeat beat: Double) -> Double {
        (grid?.seconds(atBeat: beat) ?? 0) * sampleRate
    }

    /// Nearest beat-grid frame when quantize is on.
    func snap(_ frame: Double) -> Double {
        guard quantize, grid != nil else { return frame }
        return self.frame(atBeat: beatPosition(frame).rounded())
    }

    // MARK: Loading

    func load(_ newTrack: Track) {
        guard let library else { return }
        pause()
        stemJob?.cancel()
        stemJob = nil
        isLoading = true
        loadError = nil
        loadGeneration += 1
        let generation = loadGeneration
        let url = library.url(for: newTrack)
        let id = newTrack.id
        let needsAnalysis = !newTrack.isAnalyzed || newTrack.loudness == nil
        Task.detached(priority: .userInitiated) {
            do {
                let pcm = try AudioDecoder.decode(url: url, sampleRate: AudioConfig.sampleRate)
                var waveform = LibraryFiles.cachedWaveform(id)
                var analysis: AnalysisResult?
                if needsAnalysis || waveform == nil {
                    let result = TrackAnalyzer.analyze(pcm)
                    try? result.waveform.encoded().write(to: LibraryFiles.waveformURL(id), options: .atomic)
                    // A track with an existing grid (analysed or from rekordbox) only needs its waveform.
                    analysis = needsAnalysis ? result : nil
                    waveform = result.waveform
                }
                await MainActor.run { [waveform, analysis] in
                    guard self.loadGeneration == generation else {
                        // Superseded by a newer load, but keep the analysis work.
                        if let analysis { self.saveAnalysis(analysis, for: id) }
                        return
                    }
                    self.finishLoading(id: id, pcm: pcm, waveform: waveform, analysis: analysis)
                }
            } catch {
                await MainActor.run {
                    guard self.loadGeneration == generation else { return }
                    self.isLoading = false
                    self.loadError = "Couldn't open this file"
                }
            }
        }
    }

    /// Stores fresh analysis unless the track gained a grid meanwhile (e.g. from rekordbox).
    private func saveAnalysis(_ analysis: AnalysisResult, for id: UUID) {
        library?.update(id) { t in
            guard t.bpm == nil else { return }
            t.bpm = analysis.bpm
            t.firstBeat = analysis.firstBeat
            t.tempoMarkers = analysis.tempoMarkers
            if t.key == nil { t.key = analysis.key }
        }
        library?.update(id) { $0.loudness = analysis.loudness }
    }

    private func finishLoading(id: UUID, pcm: PCM16Stereo, waveform: WaveformData?, analysis: AnalysisResult?) {
        if let analysis { saveAnalysis(analysis, for: id) }
        library?.update(id) { $0.playCount += 1 }

        renderer.isPlaying = false
        renderer.loopActive = false
        renderer.cancelSlip()
        renderer.endScratch()
        renderer.reachedEnd = false
        renderer.setSources([pcm])

        track = library?.track(id)
        self.waveform = waveform
        stemWaveform = nil
        artwork = nil
        isPlaying = false
        loopActive = false
        syncOn = false
        reverse = false
        fxOn = false
        applyFX()
        stemStatus = .unavailable
        stemsOn = [true, true, true, true]
        stemLevels = [1, 1, 1, 1]
        stemsBeforeSolo = nil
        keyShift = 0
        autoGainDB = track?.loudness.map { Float(Self.targetLoudness - $0) } ?? 0
        autoGainDB = max(-12, min(9, autoGainDB))
        onMixChange?()
        Task { [weak self] in
            let image = await ArtworkStore.image(id)
            guard let self, self.track?.id == id else { return }
            self.artwork = image
        }
        cuePoint = track?.memoryCue ?? track?.firstBeat ?? 0
        seek(to: cuePoint)
        memoryPage = 0
        armSavedLoops()
        isLoading = false
        // Without the model, stems are only a rough filter split: not worth their memory until asked for.
        // When the phone's hot, leave the GPU alone until they're asked for too.
        let thermal = ProcessInfo.processInfo.thermalState
        if StemSeparation.hasModel, thermal != .serious, thermal != .critical,
           UserDefaults.standard.object(forKey: "prepareStemsOnLoad") as? Bool ?? true {
            prepareStems()
        }
    }

    /// Tracks are brought to about this loudness (LUFS), which leaves headroom for mixing two together.
    static let targetLoudness = -11.0

    func updateTrack(_ change: (inout Track) -> Void) {
        guard var current = track else { return }
        change(&current)
        track = current
        library?.update(current.id, change)
        onMixChange?() // BPM may have changed; keep beat-synced FX in time
    }

    // MARK: Transport

    func togglePlay() {
        // PLAY while holding CUE means "keep going from here", as on a CDJ.
        if cuePreviewing {
            play()
        } else if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        guard isLoaded else { return }
        cuePreviewing = false
        renderer.reachedEnd = false
        renderer.isPlaying = true
        isPlaying = true
    }

    func pause() {
        renderer.isPlaying = false
        isPlaying = false
    }

    func seek(to seconds: Double) {
        let maxFrame = Double(max(renderer.frameCount - 1, 0))
        renderer.playhead = max(0, min(seconds * sampleRate, maxFrame))
        renderer.reachedEnd = false
    }

    /// CDJ-style cue: while playing, jump back to the cue and stop; while paused, set the
    /// cue here (if moved) and play for as long as the button is held.
    func cueDown() {
        guard isLoaded else { return }
        if isPlaying && !cuePreviewing {
            pause()
            seek(to: cuePoint)
        } else {
            if abs(position - cuePoint) > 0.01 {
                cuePoint = snap(renderer.playhead) / sampleRate
            }
            seek(to: cuePoint)
            renderer.isPlaying = true
            isPlaying = true
            cuePreviewing = true
        }
    }

    func cueUp() {
        guard cuePreviewing else { return }
        cuePreviewing = false
        pause()
        seek(to: cuePoint)
    }

    func saveMemoryCue() {
        saveMemoryCue(at: cuePoint)
    }

    /// Called by the slider: moving tempo by hand takes the deck out of sync.
    func setTempoManually(_ value: Double) {
        syncOn = false
        tempo = value
    }

    func setTempo(_ value: Double) { tempo = value }

    private func applyTempo() {
        renderer.setTempo(ratio: tempoRatio, keyLock: keyLock, keyShift: keyShift)
        onMixChange?()
    }

    private func gridChanged() {
        grid = track?.grid
        gridSection = grid?.sectionIndex(at: position) ?? 0
        applyLocalTempo()
    }

    /// Tells everything that works in single beats what the tempo is at the playhead.
    private func applyLocalTempo() {
        bpm = grid.map { $0.sections[gridSection].bpm } ?? 0
        renderer.setGrid(beatFrames: beatFrames, firstBeatFrame: firstBeatFrame)
    }

    /// A track with tempo changes hands over to its next section as the playhead reaches it.
    private func followTempoMap() {
        guard let grid, grid.isVariable else { return }
        let section = grid.sectionIndex(at: position)
        guard section != gridSection else { return }
        gridSection = section
        applyLocalTempo()
    }

    private func setReverse() {
        renderer.reverse = reverse
        guard slipMode else { return }
        if reverse { renderer.engageSlip() } else { renderer.releaseSlip() }
    }

    /// Keeps observable state in step with the audio thread (end of track, brake, etc.).
    func tick() {
        followTempoMap()
        if isPlaying != renderer.isPlaying && !cuePreviewing { isPlaying = renderer.isPlaying }
        if loopActive != renderer.loopActive { loopActive = renderer.loopActive }
        if fxOn && (fxType == .brake || fxType == .backspin) && !renderer.braking { fxOn = false }
    }
}
