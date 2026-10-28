import AVFoundation

/// Hot cues, loops, beat jump, rolls, scratching, sync and stems.
extension Deck {
    // MARK: Hot cues

    func hotCue(_ slot: Int) {
        guard isLoaded else { return }
        if shift {
            updateTrack { $0.hotCues[slot] = nil }
            return
        }
        guard let time = track?.hotCues[slot] else {
            let time = snap(renderer.playhead) / sampleRate
            updateTrack { $0.hotCues[slot] = time }
            return
        }
        var target = time * sampleRate
        if quantize && isPlaying && beatFrames > 0 {
            // Keep the current position within the beat so the jump lands in time.
            let beat = beatPosition(renderer.playhead)
            target += (beat - beat.rounded(.down)) * beatFrames
        }
        if renderer.loopActive && (target < renderer.loopStart || target >= renderer.loopEnd) {
            exitLoop()
        }
        renderer.playhead = target
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
        renderer.loopStart = start
        renderer.loopEnd = start + length
        if renderer.playhead >= renderer.loopEnd || renderer.playhead < start {
            renderer.playhead = start + max(0, renderer.playhead - start).truncatingRemainder(dividingBy: length)
        }
        renderer.loopActive = true
        loopActive = true
        loopBeats = beats
    }

    func loopIn() {
        guard isLoaded else { return }
        renderer.loopActive = false
        loopActive = false
        renderer.loopStart = snap(renderer.playhead)
        renderer.loopEnd = renderer.loopStart
    }

    func loopOut() {
        guard isLoaded else { return }
        let end = snap(renderer.playhead)
        guard end > renderer.loopStart + sampleRate * 0.01 else { return }
        if slipMode && !renderer.slipEngaged { renderer.engageSlip() }
        renderer.loopEnd = end
        renderer.loopActive = true
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
            renderer.loopStart += delta
            renderer.loopEnd += delta
        }
        renderer.playhead = max(0, renderer.playhead + delta)
    }

    /// Momentary loop: the track keeps running underneath and resumes in time on release.
    func rollBegin(_ beats: Double) {
        guard isLoaded, beatFrames > 0 else { return }
        renderer.engageSlip()
        renderer.loopActive = false
        loopActive = false
        setLoop(beats: beats, resizeExisting: false)
    }

    func rollEnd() {
        renderer.loopActive = false
        loopActive = false
        renderer.releaseSlip()
    }

    // MARK: Jog wheel / waveform touch

    func scratchBegin() {
        guard isLoaded else { return }
        if slipMode { renderer.engageSlip() }
        renderer.beginScratch()
    }

    func scratchMove(seconds: Double) {
        renderer.scratchTarget += seconds * sampleRate
    }

    func scratchEnd() {
        renderer.scratching = false
        if slipMode { renderer.releaseSlip() }
    }

    /// Pitch bend from the jog ring: speeds up or slows down briefly by `seconds` of audio.
    func bend(seconds: Double) {
        renderer.pendingNudge += seconds * sampleRate
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
            renderer.pendingNudge = d * beatFrames
        } else {
            renderer.playhead += d * beatFrames
        }
    }

    // MARK: Stems

    func toggleStem(_ stem: Stem) {
        prepareStems()
        stemsOn[stem.rawValue].toggle()
    }

    /// Solo a stem; soloing the already-soloed stem brings all back.
    func soloStem(_ stem: Stem) {
        prepareStems()
        let alreadySolo = stemsOn.indices.allSatisfy { stemsOn[$0] == ($0 == stem.rawValue) }
        stemsOn = alreadySolo ? [true, true, true, true] : Stem.allCases.map { $0 == stem }
    }

    func applyStemGains() {
        for i in 0..<4 { renderer.stemGains[i] = stemsOn[i] ? 1 : 0 }
    }

    /// Splits the loaded track into stems in the background, then swaps them in seamlessly.
    func prepareStems() {
        // Separates the audio already loaded on the deck, so there's no second decode.
        guard let track, stemStatus == .unavailable, let mix = renderer.mixSource else { return }
        guard mix.duration <= AudioConfig.maxStemSeconds else {
            stemStatus = .tooLong
            return
        }
        stemStatus = .separating
        let id = track.id
        Task.detached(priority: .userInitiated) {
            do {
                let separator = StemSeparation.makeSeparator()
                let label = separator.isMachineLearning ? "AI" : "≈EQ"
                let stems = try separator.separate(mix)
                await MainActor.run {
                    guard self.track?.id == id else { return }
                    self.renderer.setSources(stems)
                    self.applyStemGains()
                    self.stemStatus = .ready(label)
                }
            } catch {
                await MainActor.run { self.stemStatus = .unavailable }
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

    func applyEQ() {
        func gain(_ v: Float) -> Float { v <= -0.97 ? -96 : (v < 0 ? v * 26 : v * 6) }
        eq.bands[0].gain = gain(eqLow)
        eq.bands[1].gain = gain(eqMid)
        eq.bands[2].gain = gain(eqHigh)
    }

    /// One knob: left sweeps a low-pass down, right sweeps a high-pass up.
    func applyFilter() {
        let band = eq.bands[3]
        let amount = Double(abs(filter))
        if filter < -0.03 {
            band.filterType = .resonantLowPass
            band.frequency = Float(20000 * pow(100.0 / 20000, amount))
            band.bypass = false
        } else if filter > 0.03 {
            band.filterType = .resonantHighPass
            band.frequency = Float(20 * pow(9000.0 / 20, amount))
            band.bypass = false
        } else {
            band.bypass = true
        }
    }
}
