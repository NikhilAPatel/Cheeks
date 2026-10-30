import AVFoundation

/// Hot cues, loops, beat jump, rolls, scratching, sync and stems.
extension Deck {
    // MARK: Hot cues

    func hotCue(_ slot: Int) {
        guard isLoaded else { return }
        if shift {
            shift = false
            guard let removed = track?.hotCues[slot] else { return }
            updateTrack { $0.hotCues[slot] = nil }
            offerUndo?("Deleted hot cue \(Theme.hotCueLetters[slot])") { [weak self] in
                self?.updateTrack { $0.hotCues[slot] = removed }
            }
            return
        }
        guard let time = track?.hotCues[slot] else {
            let time = snap(renderer.playhead) / sampleRate
            updateTrack { $0.hotCues[slot] = time }
            return
        }
        let target = time * sampleRate
        if renderer.loopActive && (target < renderer.loopStart || target >= renderer.loopEnd) {
            exitLoop()
        }
        if quantize && isPlaying && beatFrames > 0 {
            // Keeps the current position within the beat, measured on the audio thread, so the jump lands in time.
            renderer.seekBeatLocked(target, beatFrames: beatFrames, firstBeatFrame: firstBeatFrame)
        } else {
            renderer.playhead = target
        }
        if !isPlaying { play() }
    }

    // MARK: Loops

    func toggleBeatLoop(_ beats: Double) {
        if loopActive && abs(loopBeats - beats) < 0.0001 {
            exitLoop()
        } else {
            setLoop(beats: beats, resizeExisting: loopActive)
        }
    }

    func setLoop(beats: Double, resizeExisting: Bool = true) {
        guard isLoaded, beatFrames > 0 else { return }
        let length = beats * beatFrames
        let start: Double
        if resizeExisting && loopActive {
            start = renderer.loopStart
        } else if quantize {
            let grid = min(beats, 1)
            start = firstBeatFrame + (beatPosition(renderer.playhead) / grid).rounded(.down) * grid * beatFrames
        } else {
            start = renderer.playhead
        }
        if slipMode && !renderer.slipEngaged { renderer.engageSlip() }
        renderer.setLoop(start: start, end: start + length, active: true)
        if renderer.playhead >= start + length || renderer.playhead < start {
            renderer.playhead = start + max(0, renderer.playhead - start).truncatingRemainder(dividingBy: length)
        }
        loopActive = true
        loopBeats = beats
    }

    func loopIn() {
        guard isLoaded else { return }
        let start = snap(renderer.playhead)
        renderer.setLoop(start: start, end: start, active: false)
        loopActive = false
    }

    func loopOut() {
        guard isLoaded else { return }
        let end = snap(renderer.playhead)
        guard end > renderer.loopStart + sampleRate * 0.01 else { return }
        if slipMode && !renderer.slipEngaged { renderer.engageSlip() }
        renderer.setLoop(start: renderer.loopStart, end: end, active: true)
        loopActive = true
        if beatFrames > 0 { loopBeats = (end - renderer.loopStart) / beatFrames }
    }

    func exitLoop() {
        renderer.loopActive = false
        loopActive = false
        if slipMode { renderer.releaseSlip() }
    }

    func reloop() {
        guard renderer.loopEnd > renderer.loopStart else { return }
        renderer.playhead = renderer.loopStart
        renderer.loopActive = true
        loopActive = true
        if !isPlaying { play() }
    }

    func halveLoop() {
        let beats = max(1.0 / 32, loopBeats / 2)
        if loopActive { setLoop(beats: beats) } else { loopBeats = beats }
    }

    func doubleLoop() {
        let beats = min(64, loopBeats * 2)
        if loopActive { setLoop(beats: beats) } else { loopBeats = beats }
    }

    /// Jumps by a number of beats; an active loop moves with it.
    func beatJump(_ beats: Double) {
        guard isLoaded, beatFrames > 0 else { return }
        let delta = beats * beatFrames
        if renderer.loopActive {
            renderer.setLoop(start: renderer.loopStart + delta, end: renderer.loopEnd + delta, active: true)
        }
        renderer.jump(by: delta)
    }

    /// Momentary loop: the track keeps running underneath and resumes in time on release.
    func rollBegin(_ beats: Double) {
        guard isLoaded, beatFrames > 0 else { return }
        if heldMomentaryPads == 0 { renderer.engageSlip() }
        heldMomentaryPads += 1
        renderer.loopActive = false
        loopActive = false
        setLoop(beats: beats, resizeExisting: false)
    }

    func rollEnd() { momentaryPadReleased() }

    /// When the last held pad comes up, the track returns to where it would have been.
    private func momentaryPadReleased() {
        heldMomentaryPads = max(0, heldMomentaryPads - 1)
        guard heldMomentaryPads == 0 else { return }
        renderer.loopActive = false
        loopActive = false
        renderer.releaseSlip()
    }

    // MARK: Slicer

    /// Plays one eighth of the current bar for as long as it's held; the track keeps running
    /// underneath and comes back in time on release.
    func sliceBegin(_ slice: Int) {
        guard isLoaded, beatFrames > 0 else { return }
        if !isPlaying { play() }
        let length = beatFrames / 2
        let beat = beatPosition(renderer.playhead)
        let barStart = firstBeatFrame + (beat / 4).rounded(.down) * 4 * beatFrames
        let start = barStart + Double(slice) * length
        // A second pad while one's held plays that slice; the return point stays where it was.
        if heldMomentaryPads == 0 { renderer.engageSlip() }
        heldMomentaryPads += 1
        renderer.setLoop(start: start, end: start + length, active: true)
        renderer.playhead = start
        loopActive = true
    }

    func sliceEnd() { momentaryPadReleased() }

    // MARK: Key sync

    /// Shifts this deck by the smallest step that puts it in a key compatible with `master`.
    func keySync(to master: Deck) {
        guard let mine = track?.key, let theirs = master.effectiveKey else { return }
        let candidates = (-6...6).sorted { abs($0) < abs($1) }
        guard let shift = candidates.first(where: { Camelot.isCompatible(Camelot.shifted(mine, by: $0), theirs) }) else { return }
        keyShift = shift
        Haptics.shared.confirm()
    }

    // MARK: Jog wheel / waveform touch

    func scratchBegin() {
        guard isLoaded else { return }
        if slipMode { renderer.engageSlip() }
        renderer.beginScratch()
    }

    func scratchMove(seconds: Double) {
        renderer.moveScratch(byFrames: seconds * sampleRate)
    }

    func scratchEnd() {
        renderer.endScratch()
        if slipMode { renderer.releaseSlip() }
    }

    /// Pitch bend from the jog ring: speeds up or slows down briefly by `seconds` of audio.
    func bend(seconds: Double) {
        renderer.nudge(by: seconds * sampleRate)
    }

    func brake(beats: Double) {
        guard isPlaying, beatFrames > 0 else { return }
        renderer.startBrake(overFrames: beats * beatFrames / tempoRatio)
    }

    // MARK: Sync

    /// Matches tempo (allowing half/double time) and snaps beat phase to `master`.
    func sync(to master: Deck) {
        guard isLoaded, bpm > 0, master.bpm > 0 else { return }
        let target = matchedBPM(for: master.effectiveBPM)
        let newTempo = (target / bpm - 1) * 100
        if abs(newTempo) > tempoRange {
            tempoRange = [6, 10, 16, 100].first { $0 >= abs(newTempo) } ?? 100
        }
        setTempo(newTempo)
        syncOn = true
        alignPhase(to: master, smoothly: false)
    }

    /// Picks whichever of master, half or double time is closest to this track's own BPM.
    func matchedBPM(for masterBPM: Double) -> Double {
        [masterBPM, masterBPM / 2, masterBPM * 2].min { abs($0 - bpm) < abs($1 - bpm) } ?? masterBPM
    }

    /// Phase difference to master in this deck's beats, wrapped to -0.5...0.5.
    func phaseOffset(to master: Deck) -> Double {
        guard beatFrames > 0, master.beatFrames > 0, master.effectiveBPM > 0 else { return 0 }
        let scale = effectiveBPM / master.effectiveBPM
        let masterBeats = master.beatPosition(master.renderer.playhead) * scale
        let mine = beatPosition(renderer.playhead)
        var d = (masterBeats - masterBeats.rounded(.down)) - (mine - mine.rounded(.down))
        if d > 0.5 { d -= 1 }
        if d < -0.5 { d += 1 }
        return d
    }

    func alignPhase(to master: Deck, smoothly: Bool) {
        let d = phaseOffset(to: master)
        if smoothly {
            renderer.nudge(by: d * beatFrames)
        } else {
            renderer.jump(by: d * beatFrames)
        }
    }

    // MARK: Stems

    func toggleStem(_ stem: Stem) {
        prepareStems()
        guard stemStatus != .tooLong else { return }
        stemsBeforeSolo = nil
        stemsOn[stem.rawValue].toggle()
    }

    /// Solo a stem; soloing the already-soloed stem restores what was on before.
    func soloStem(_ stem: Stem) {
        prepareStems()
        guard stemStatus != .tooLong else { return }
        let alreadySolo = stemsOn.indices.allSatisfy { stemsOn[$0] == ($0 == stem.rawValue) }
        if alreadySolo {
            stemsOn = stemsBeforeSolo ?? [true, true, true, true]
            stemsBeforeSolo = nil
        } else {
            if stemsBeforeSolo == nil { stemsBeforeSolo = stemsOn }
            stemsOn = Stem.allCases.map { $0 == stem }
        }
    }

    func setStems(_ on: Set<Stem>) {
        prepareStems()
        guard stemStatus != .tooLong else { return }
        stemsBeforeSolo = nil
        stemsOn = Stem.allCases.map { on.contains($0) }
    }

    func applyStemGains() {
        for i in 0..<4 { renderer.setStemGain(i, stemsOn[i] ? stemLevels[i] : 0) }
    }

    // MARK: Beat FX

    /// Presses an FX pad. The effect is on for as long as it's held, or until `fxRelease`.
    func fxEngage(_ type: BeatFX) {
        if fxOn && fxType != type { fxRelease() }
        fxType = type
        fxOn = true
        switch type {
        case .roll:
            rollBegin(fxBeats)
        case .brake:
            brake(beats: max(fxBeats, 1) * 2)
        case .backspin:
            if isPlaying, beatFrames > 0 { renderer.startBackspin(overFrames: max(fxBeats, 1) * beatFrames / tempoRatio) }
        default:
            break
        }
        applyFX()
    }

    func fxRelease() {
        guard fxOn else { return }
        if fxType == .roll { rollEnd() }
        fxOn = false
        applyFX()
    }

    func applyFX() {
        var mask = 0
        for stem in fxStems { mask |= 1 << stem.rawValue }
        renderer.setFX(fxType.dsp, on: fxOn && fxType.dsp != CheeksFXNone, beats: fxBeats, depth: fxDepth, stemMask: mask == 0 ? 0xF : mask)
    }

    /// Splits the loaded track into stems in the background, then swaps them in seamlessly. A track
    /// that's been split before comes straight back from the cache.
    func prepareStems() {
        // Separates the audio already loaded on the deck, so there's no second decode.
        guard let track, !isLoading, stemStatus == .unavailable, let mix = renderer.mixSource else { return }
        guard mix.duration <= AudioConfig.maxStemSeconds else {
            stemStatus = .tooLong
            return
        }
        stemStatus = .separating(nil)
        let id = track.id
        // Results from a separation started before another track was loaded are dropped.
        let generation = loadGeneration
        let job = StemJob()
        stemJob = job
        StemJob.started()
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let (stems, label) = try StemJob.stems(for: id, mix: mix, job: job) { progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.loadGeneration == generation, case .separating = self.stemStatus else { return }
                        self.stemStatus = .separating(progress)
                    }
                }
                let waves = StemWaveformData(stems: stems)
                await MainActor.run {
                    StemJob.finished()
                    guard let self, self.loadGeneration == generation, self.track?.id == id else { return }
                    self.renderer.setSources(stems)
                    self.applyStemGains()
                    self.stemWaveform = waves
                    self.stemStatus = .ready(label)
                }
            } catch {
                let wasCancelled = error is CancellationError
                await MainActor.run {
                    StemJob.finished()
                    guard let self, self.loadGeneration == generation else { return }
                    self.stemStatus = .unavailable
                    if !wasCancelled { self.onMessage?("Couldn't split this track into stems.") }
                }
            }
        }
    }

    // MARK: Beat grid editing

    private var barSeconds: Double { bpm > 0 ? 4 * 60 / bpm : 0 }

    /// Fixes half/double-time detection (multiplier 2 or 0.5).
    func scaleBPM(_ multiplier: Double) {
        guard let current = track?.bpm else { return }
        updateTrack { $0.bpm = current * multiplier }
    }

    func nudgeBPM(by delta: Double) {
        guard let current = track?.bpm else { return }
        updateTrack { $0.bpm = max(40, ((current + delta) * 100).rounded() / 100) }
    }

    /// Slides the whole grid earlier/later.
    func shiftGrid(milliseconds: Double) {
        guard barSeconds > 0, let first = track?.firstBeat else { return }
        let bar = barSeconds
        var moved = (first + milliseconds / 1000).truncatingRemainder(dividingBy: bar)
        if moved < 0 { moved += bar }
        updateTrack { $0.firstBeat = moved }
    }

    /// Makes the playhead (snapped to the nearest beat when quantize is on) the first beat of a bar.
    func setDownbeatHere() {
        guard barSeconds > 0 else { return }
        let bar = barSeconds
        let here = snap(renderer.playhead) / sampleRate
        var first = here.truncatingRemainder(dividingBy: bar)
        if first < 0 { first += bar }
        updateTrack { $0.firstBeat = first }
    }

    // MARK: EQ / filter

    /// Knob to linear gain: fully left removes the band, centre is flat, fully right is +6 dB.
    func applyEQ() {
        func gain(_ v: Float) -> Float { v <= -0.97 ? 0 : pow(10, (v < 0 ? v * 26 : v * 6) / 20) }
        renderer.setEQ(low: gain(eqLow), mid: gain(eqMid), high: gain(eqHigh))
    }

    /// One knob: left sweeps a low-pass down, right sweeps a high-pass up.
    func applyFilter() {
        renderer.setFilter(abs(filter) < 0.015 ? 0 : filter)
    }
}
