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
    case sampler = "SAMPLE"
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

/// One effect that's on: which link of the chain it's in, or none if it works the transport.
struct ActiveFX: Equatable {
    var effect: BeatFX
    var link: Int?
    var beats: Double
    var depth: Float
}

/// What the channel's COLOR knob does.
enum ColorEffect: String, CaseIterable, Identifiable {
    case filter = "FILTER"
    case dubEcho = "DUB"
    case space = "SPACE"
    case noise = "NOISE"
    case crush = "CRUSH"
    case pitch = "PITCH"
    var id: String { rawValue }

    var dsp: CheeksColorType {
        switch self {
        case .filter: CheeksColorFilter
        case .dubEcho: CheeksColorDubEcho
        case .space: CheeksColorSpace
        case .noise: CheeksColorNoise
        case .crush: CheeksColorCrush
        case .pitch: CheeksColorPitch
        }
    }
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
    @ObservationIgnored var onMessage: (@MainActor (String, StatusKind) -> Void)?
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
    /// The playhead in tenths of a second, for the labels that count. It only changes when one of
    /// those numbers would, so they cost nothing at all while the deck isn't moving.
    private(set) var clockTenths = 0
    /// Gain that brings this track to the target loudness, in dB, from its analysis.
    private(set) var autoGainDB: Float = 0
    private(set) var isLoading = false
    /// The track on its way, so the header can show it straight away.
    private(set) var loadingTrack: Track?
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
    /// IN has been pressed, and OUT hasn't yet.
    var loopInSet = false
    /// What the loop key said before a roll borrowed it.
    @ObservationIgnored var loopBeatsBeforePad: Double?
    var jumpBeats: Double = 4
    var stemStatus: StemStatus = .unavailable
    var stemsOn: [Bool] = [true, true, true, true] { didSet { applyStemGains() } }
    /// Each stem's level (0...1), on top of its on/off state.
    var stemLevels: [Float] = [1, 1, 1, 1] { didSet { applyStemGains() } }
    /// Set when the stems were last heard all on, for restoring after a solo.
    @ObservationIgnored var stemsBeforeSolo: [Bool]?

    // Beat FX
    /// The effects that are on, oldest first. Up to `CHEEKS_FX_LINKS` run at once as a chain.
    var activeFX: [ActiveFX] = []
    /// The effect the row of FX controls is showing.
    var fxType: BeatFX = .echo
    var fxOn: Bool { !activeFX.isEmpty }
    var fxBeats: Double = 0.5 { didSet { fxSettingsChanged() } }
    var fxDepth: Float = 0.6 { didSet { fxSettingsChanged() } }
    /// True from an echo out until the track's sound is brought back.
    var echoingOut = false
    /// The stems the FX bus is applied to; all of them, or the whole track without stems.
    var fxStems: Set<Stem> = Set(Stem.allCases) { didSet { applyFX() } }

    // Mixer channel (knobs are -1...1, 0 = centre)
    var trim: Float = 0 { didSet { onMixChange?() } }
    var eqHigh: Float = 0 { didSet { applyEQ() } }
    var eqMid: Float = 0 { didSet { applyEQ() } }
    var eqLow: Float = 0 { didSet { applyEQ() } }
    var filter: Float = 0 { didSet { applyFilter() } }
    /// What the COLOR knob does. Shared between channels, like a mixer's Color FX buttons.
    var colorFX: ColorEffect = .filter { didSet { applyFilter() } }
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
    var isLoaded: Bool {
        // Read first, so a view that asks while the deck's empty still hears about the load finishing.
        let loading = isLoading
        return renderer.frameCount > 0 && !loading
    }
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
        loadingTrack = newTrack
        loadError = nil
        loadGeneration += 1
        let generation = loadGeneration
        let url = library.url(for: newTrack)
        let id = newTrack.id
        let needsAnalysis = !newTrack.isAnalyzed || newTrack.loudness == nil
        let knownGrid = newTrack.grid
        Task.detached(priority: .userInitiated) {
            do {
                let pcm = try AudioDecoder.decode(url: url, sampleRate: AudioConfig.sampleRate)
                var waveform = LibraryFiles.cachedWaveform(id)
                var analysis: AnalysisResult?
                if needsAnalysis || waveform == nil {
                    let result = TrackAnalyzer.analyze(pcm, knownGrid: knownGrid)
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
                    self.loadingTrack = nil
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
        library?.update(id) { t in
            t.loudness = analysis.loudness
            t.phrases = analysis.phrases ?? t.phrases ?? []
        }
    }

    private func finishLoading(id: UUID, pcm: PCM16Stereo, waveform: WaveformData?, analysis: AnalysisResult?) {
        if let analysis { saveAnalysis(analysis, for: id) }
        library?.update(id) { $0.playCount += 1 }

        renderer.isPlaying = false
        // The whole loop, not just its switch, or the last track's loop shows on this one.
        renderer.setLoop(start: 0, end: 0, active: false)
        loopInSet = false
        heldMomentaryPads = 0
        loopBeatsBeforePad = nil
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
        clearFX()
        endEchoOut()
        stemStatus = .unavailable
        stemsOn = [true, true, true, true]
        stemLevels = [1, 1, 1, 1]
        stemsBeforeSolo = nil
        keyShift = 0
        autoGainDB = Self.autoGain(for: track?.loudness)
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
        loadingTrack = nil
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

    func setLoadingForTesting(_ loading: Bool) { isLoading = loading }
    func setAutoGainForTesting(loudness: Double?) { autoGainDB = Self.autoGain(for: loudness) }

    /// Brings a track to the target loudness, within reason.
    static func autoGain(for loudness: Double?) -> Float {
        max(-12, min(9, loudness.map { Float(targetLoudness - $0) } ?? 0))
    }

    /// The section of the song at a position in the track, and when it started.
    func phrase(atFrame frame: Double) -> Phrase? {
        guard let phrases = track?.phrases, !phrases.isEmpty else { return nil }
        let seconds = frame / sampleRate
        return phrases.last { $0.start <= seconds } ?? phrases.first
    }

    /// Picks up what the library's learned about the track that's loaded.
    func refreshTrack() {
        guard let id = track?.id, let fresh = library?.track(id) else { return }
        track = fresh
    }

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
        endEchoOut()
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
        let tenths = Int(position * 10)
        if tenths != clockTenths { clockTenths = tenths }
        if isPlaying != renderer.isPlaying && !cuePreviewing { isPlaying = renderer.isPlaying }
        if loopActive != renderer.loopActive { loopActive = renderer.loopActive }
        if !renderer.braking { activeFX.removeAll { $0.effect == .brake || $0.effect == .backspin } }
        // A deck that's stopped itself, by reaching the end or by a brake, has finished its echo out too.
        if echoingOut && !isPlaying { endEchoOut() }
    }
}
