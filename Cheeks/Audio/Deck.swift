import AVFoundation
import Observation

enum PadMode: String, CaseIterable, Identifiable {
    case hotCue = "HOT CUE"
    case beatLoop = "BEAT LOOP"
    case roll = "ROLL"
    case beatJump = "BEAT JUMP"
    case stems = "STEMS"
    var id: String { rawValue }
}

enum StemStatus: Equatable {
    case unavailable
    case separating
    case ready(String)
}

/// One player deck: transport, beat grid, cues, loops, sync, stems and its mixer channel.
/// Realtime audio lives in `renderer`; this class is the main-thread control surface.
@MainActor
@Observable
final class Deck {
    let index: Int
    let renderer = DeckRenderer(sampleRate: AudioConfig.sampleRate)

    // Signal chain: renderer → varispeed → timePitch → EQ/filter → echo → reverb → channel
    let varispeed = AVAudioUnitVarispeed()
    let timePitch = AVAudioUnitTimePitch()
    let eq = AVAudioUnitEQ(numberOfBands: 4)
    let delay = AVAudioUnitDelay()
    let reverb = AVAudioUnitReverb()
    let channel = AVAudioMixerNode()
    /// Pre-fader send to the headphone (cue) bus.
    let cueSend = AVAudioMixerNode()

    @ObservationIgnored weak var library: Library?
    /// Called when anything affecting channel volume or tempo-synced FX changes.
    @ObservationIgnored var onMixChange: (@MainActor () -> Void)?

    // Track
    var track: Track?
    var waveform: WaveformData?
    private(set) var isLoading = false
    private(set) var loadError: String?

    // Transport
    var isPlaying = false
    var cuePoint: Double = 0
    @ObservationIgnored var cuePreviewing = false
    var quantize = true
    var slipMode = false { didSet { if !slipMode { renderer.slipEngaged = false } } }
    var reverse = false { didSet { setReverse() } }

    // Tempo
    private(set) var tempo: Double = 0 { didSet { applyTempo() } }
    var tempoRange: Double = 10
    var keyLock = true { didSet { applyTempo() } }
    var keyShift = 0 { didSet { applyTempo() } }
    var syncOn = false

    // Performance
    var padMode: PadMode = .hotCue
    var shift = false
    var loopActive = false
    var loopBeats: Double = 4
    var stemStatus: StemStatus = .unavailable
    var stemsOn: [Bool] = [true, true, true, true] { didSet { applyStemGains() } }

    // Mixer channel (knobs are -1...1, 0 = centre)
    var trim: Float = 0 { didSet { onMixChange?() } }
    var eqHigh: Float = 0 { didSet { applyEQ() } }
    var eqMid: Float = 0 { didSet { applyEQ() } }
    var eqLow: Float = 0 { didSet { applyEQ() } }
    var filter: Float = 0 { didSet { applyFilter() } }
    var fader: Float = 0.85 { didSet { onMixChange?() } }
    var headphoneCue = false { didSet { onMixChange?() } }
    var level: Float = 0

    init(index: Int) {
        self.index = index
        let bands = eq.bands
        bands[0].filterType = .lowShelf
        bands[0].frequency = 120
        bands[1].filterType = .parametric
        bands[1].frequency = 1000
        bands[1].bandwidth = 1.6
        bands[2].filterType = .highShelf
        bands[2].frequency = 7000
        bands[3].filterType = .resonantLowPass
        bands[3].frequency = 20000
        bands[3].bandwidth = 0.6
        for band in bands.prefix(3) { band.gain = 0; band.bypass = false }
        bands[3].bypass = true

        delay.feedback = 45
        delay.lowPassCutoff = 9000
        delay.wetDryMix = 0
        delay.bypass = true
        reverb.loadFactoryPreset(.largeHall)
        reverb.wetDryMix = 0
        reverb.bypass = true
        applyTempo()
    }

    // MARK: Derived values

    var sampleRate: Double { AudioConfig.sampleRate }
    var bpm: Double { track?.bpm ?? 0 }
    var tempoRatio: Double { 1 + tempo / 100 }
    var effectiveBPM: Double { bpm * tempoRatio }
    var isLoaded: Bool { renderer.frameCount > 0 && !isLoading }
    /// Current playhead in seconds. Not observed; views poll it from a TimelineView.
    var position: Double { renderer.playhead / sampleRate }
    var duration: Double { Double(renderer.frameCount) / sampleRate }
    var beatFrames: Double { bpm > 0 ? 60 / bpm * sampleRate : 0 }
    var firstBeatFrame: Double { (track?.firstBeat ?? 0) * sampleRate }

    func beatPosition(_ frame: Double) -> Double {
        beatFrames > 0 ? (frame - firstBeatFrame) / beatFrames : 0
    }

    /// Nearest beat-grid frame when quantize is on.
    func snap(_ frame: Double) -> Double {
        guard quantize, beatFrames > 0 else { return frame }
        return firstBeatFrame + beatPosition(frame).rounded() * beatFrames
    }

    // MARK: Loading

    func load(_ newTrack: Track) {
        guard let library else { return }
        pause()
        isLoading = true
        loadError = nil
        let url = library.url(for: newTrack)
        let id = newTrack.id
        let needsAnalysis = !newTrack.isAnalyzed
        Task.detached(priority: .userInitiated) {
            do {
                let audio = try AudioDecoder.decode(url: url, sampleRate: AudioConfig.sampleRate)
                let pcm = PCM16Stereo(left: audio.left, right: audio.right)
                var waveform = LibraryFiles.cachedWaveform(id)
                var analysis: AnalysisResult?
                if needsAnalysis || waveform == nil {
                    let result = TrackAnalyzer.analyze(audio)
                    try? result.waveform.encoded().write(to: LibraryFiles.waveformURL(id), options: .atomic)
                    analysis = result
                    waveform = result.waveform
                }
                await MainActor.run { [waveform, analysis] in
                    self.finishLoading(id: id, pcm: pcm, waveform: waveform, analysis: analysis)
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.loadError = "Couldn't open this file"
                }
            }
        }
    }

    private func finishLoading(id: UUID, pcm: PCM16Stereo, waveform: WaveformData?, analysis: AnalysisResult?) {
        if let analysis {
            library?.update(id) { t in
                t.bpm = analysis.bpm
                t.firstBeat = analysis.firstBeat
                t.key = analysis.key
            }
        }
        library?.update(id) { $0.playCount += 1 }

        renderer.isPlaying = false
        renderer.loopActive = false
        renderer.slipEngaged = false
        renderer.scratching = false
        renderer.reachedEnd = false
        renderer.setSources([pcm])

        track = library?.track(id)
        self.waveform = waveform
        isPlaying = false
        loopActive = false
        syncOn = false
        reverse = false
        stemStatus = .unavailable
        stemsOn = [true, true, true, true]
        cuePoint = track?.memoryCue ?? track?.firstBeat ?? 0
        seek(to: cuePoint)
        isLoading = false
    }

    func updateTrack(_ change: (inout Track) -> Void) {
        guard var current = track else { return }
        change(&current)
        track = current
        library?.update(current.id, change)
    }

    // MARK: Transport

    func togglePlay() { isPlaying ? pause() : play() }

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
        let time = cuePoint
        updateTrack { $0.memoryCue = time }
    }

    /// Called by the slider: moving tempo by hand takes the deck out of sync.
    func setTempoManually(_ value: Double) {
        syncOn = false
        tempo = value
    }

    func setTempo(_ value: Double) { tempo = value }

    private func applyTempo() {
        let rate = Float(tempoRatio)
        if keyLock {
            varispeed.rate = 1
            timePitch.rate = rate
        } else {
            varispeed.rate = rate
            timePitch.rate = 1
        }
        timePitch.pitch = Float(keyShift * 100)
        varispeed.bypass = varispeed.rate == 1
        timePitch.bypass = timePitch.rate == 1 && keyShift == 0
        onMixChange?()
    }

    private func setReverse() {
        renderer.reverse = reverse
        guard slipMode else { return }
        if reverse { renderer.engageSlip() } else { renderer.releaseSlip() }
    }

    /// Keeps observable state in step with the audio thread (end of track, brake, etc.).
    func tick() {
        if isPlaying != renderer.isPlaying && !cuePreviewing { isPlaying = renderer.isPlaying }
        if loopActive != renderer.loopActive { loopActive = renderer.loopActive }
    }
}
