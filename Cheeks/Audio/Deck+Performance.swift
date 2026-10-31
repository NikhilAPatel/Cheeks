import AVFoundation
import SwiftUI

/// Hot cues, loops, beat jump, rolls, scratching, sync and stems.
extension Deck {
    // MARK: Hot cues

    func hotCue(_ slot: Int) {
        guard isLoaded else { return }
        if shift {
            shift = false
            guard let removed = track?.hotCues[slot] else { return }
            let info = track?.hotCueInfo[slot]
            updateTrack { t in
                t.hotCues[slot] = nil
                t.hotCueInfo[slot] = nil
            }
            offerUndo?("Deleted hot cue \(Theme.hotCueLetters[slot])") { [weak self] in
                self?.updateTrack { t in
                    t.hotCues[slot] = removed
                    t.hotCueInfo[slot] = info
                }
            }
            return
        }
        guard let time = track?.hotCues[slot] else {
            let time = snap(renderer.playhead) / sampleRate
            updateTrack { $0.hotCues[slot] = time }
            return
        }
        if let end = track?.hotCueInfo[slot]?.loopEnd, end > time {
            toggleLoop(start: time, end: end)
            return
        }
        jump(toSeconds: time)
        if !isPlaying { play() }
    }

    /// Goes to a point in the track. While playing with quantize on, it keeps the current position
    /// within the beat, measured on the audio thread, so the jump lands in time.
    private func jump(toSeconds time: Double) {
        let target = time * sampleRate
        if renderer.loopActive && (target < renderer.loopStart || target >= renderer.loopEnd) {
            exitLoop()
        }
        if quantize && isPlaying && beatFrames > 0 {
            renderer.seekBeatLocked(target, beatFrames: beatFrames, firstBeatFrame: firstBeatFrame)
        } else {
            renderer.playhead = target
        }
    }

    /// The colour a hot cue shows in: its own, or the slot's.
    func hotCueColor(_ slot: Int) -> Color {
        track?.hotCueInfo[slot]?.color?.color ?? Theme.hotCueColors[slot % 8]
    }

    // MARK: Memory cues and saved loops

    /// Adds a memory cue, unless there's already one here.
    func saveMemoryCue(at time: Double) {
        guard isLoaded, track?.memoryCues.contains(where: { abs($0.time - time) < 0.01 }) == false else { return }
        updateTrack { t in
            t.memoryCues.append(MemoryCue(time: time))
            t.memoryCues.sort { $0.time < $1.time }
        }
    }

    /// Everything saved on this track, in track order.
    var memoryItems: [MemoryItem] {
        guard let track else { return [] }
        return (track.memoryCues.map(MemoryItem.cue) + track.savedLoops.map(MemoryItem.loop)).sorted { $0.time < $1.time }
    }

    static let memoryItemsPerPage = 8
    var memoryPageCount: Int { max(1, (memoryItems.count + Self.memoryItemsPerPage - 1) / Self.memoryItemsPerPage) }

    /// Saves the cue point, or where the playhead is if the deck's playing.
    func saveMemoryCueHere() {
        guard isLoaded else { return }
        let time = isPlaying ? snap(renderer.playhead) / sampleRate : cuePoint
        guard track?.memoryCues.contains(where: { abs($0.time - time) < 0.01 }) == false else {
            onMessage?("There's already a memory cue here.", .refused)
            return
        }
        saveMemoryCue(at: time)
        Haptics.shared.confirm()
    }

    /// Saves the loop that's set, on or off.
    func saveCurrentLoop() {
        guard isLoaded, renderer.loopEnd > renderer.loopStart + sampleRate * 0.01 else {
            onMessage?("Set a loop first, then save it.", .refused)
            return
        }
        let start = renderer.loopStart / sampleRate, end = renderer.loopEnd / sampleRate
        guard track?.savedLoops.contains(where: { abs($0.start - start) < 0.01 && abs($0.end - end) < 0.01 }) == false else {
            onMessage?("This loop's already saved.", .refused)
            return
        }
        updateTrack { $0.savedLoops.append(SavedLoop(start: start, end: end)) }
        Haptics.shared.confirm()
    }

    /// Calls up a memory cue: it becomes the cue point and the deck goes there, as on a CDJ.
    func recall(_ cue: MemoryCue) {
        guard isLoaded else { return }
        cuePoint = cue.time
        jump(toSeconds: cue.time)
    }

    /// Calls up a saved loop, and leaves it again if it's already on.
    func recall(_ loop: SavedLoop) {
        guard isLoaded else { return }
        toggleLoop(start: loop.start, end: loop.end)
    }

    func isCurrentLoop(start: Double, end: Double) -> Bool {
        loopActive && abs(renderer.loopStart / sampleRate - start) < 0.01 && abs(renderer.loopEnd / sampleRate - end) < 0.01
    }

    private func toggleLoop(start: Double, end: Double) {
        if isCurrentLoop(start: start, end: end) {
            exitLoop()
            return
        }
        let startFrame = start * sampleRate, endFrame = end * sampleRate
        let here = renderer.playhead
        if slipMode && !renderer.slipEngaged { renderer.engageSlip() }
        if here < startFrame || here >= endFrame {
            // Leave any other loop first, so the jump isn't caught by it.
            renderer.loopActive = false
            jump(toSeconds: start)
        }
        renderer.setLoop(start: startFrame, end: endFrame, active: true)
        loopActive = true
        showLength(ofLoopFrom: startFrame, to: endFrame)
        if !isPlaying { play() }
    }

    func delete(_ item: MemoryItem) {
        switch item {
        case .cue(let cue):
            updateTrack { $0.memoryCues.removeAll { $0.id == cue.id } }
            offerUndo?("Deleted memory cue") { [weak self] in self?.updateTrack { $0.memoryCues.append(cue) } }
        case .loop(let loop):
            updateTrack { $0.savedLoops.removeAll { $0.id == loop.id } }
            offerUndo?("Deleted saved loop") { [weak self] in self?.updateTrack { $0.savedLoops.append(loop) } }
        }
        memoryPage = min(memoryPage, memoryPageCount - 1)
    }

    /// A pad on the MEM page: calls up what's saved there, or deletes it after DEL.
    func pressMemory(_ item: MemoryItem) {
        if shift {
            shift = false
            delete(item)
            return
        }
        switch item {
        case .cue(let cue): recall(cue)
        case .loop(let loop): recall(loop)
        }
    }

    /// A loop marked "on at load" is waiting when the track comes up, and holds the deck once it gets there.
    func armSavedLoops() {
        guard let loop = track?.savedLoops.first(where: \.activeOnLoad) else { return }
        // If the track loads past the loop, the deck would be pulled back into it. It's left set
        // instead, for RELOOP.
        let ahead = cuePoint < loop.end
        renderer.setLoop(start: loop.start * sampleRate, end: loop.end * sampleRate, active: ahead)
        loopActive = ahead
        if ahead { showLength(ofLoopFrom: loop.start * sampleRate, to: loop.end * sampleRate) }
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
        let start: Double
        if !(resizeExisting && loopActive) { chosenLoopBeats = nil }
        if resizeExisting && loopActive {
            start = renderer.loopStart
        } else if quantize {
            let step = min(beats, 1)
            start = frame(atBeat: (beatPosition(renderer.playhead) / step).rounded(.down) * step)
        } else {
            start = renderer.playhead
        }
        let length = frame(atBeat: beatPosition(start) + beats) - start
        if slipMode && !renderer.slipEngaged { renderer.engageSlip() }
        loopInSet = false
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
        loopInSet = true
    }

    func loopOut() {
        guard isLoaded else { return }
        let end = snap(renderer.playhead)
        guard end > renderer.loopStart + sampleRate * 0.01 else { return }
        if slipMode && !renderer.slipEngaged { renderer.engageSlip() }
        renderer.setLoop(start: renderer.loopStart, end: end, active: true)
        loopActive = true
        loopInSet = false
        showLength(ofLoopFrom: renderer.loopStart, to: end)
    }

    /// A manual or saved loop shows its own length on the key. The length you chose comes back when
    /// the loop ends, so one loop you set by hand doesn't change what the key does next.
    private func showLength(ofLoopFrom start: Double, to end: Double) {
        guard beatFrames > 0 else { return }
        let length = beatPosition(end) - beatPosition(start)
        guard abs(length - loopBeats) > 0.0001 else { return }
        if chosenLoopBeats == nil { chosenLoopBeats = loopBeats }
        loopBeats = length
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
        showLength(ofLoopFrom: renderer.loopStart, to: renderer.loopEnd)
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
        let here = renderer.playhead
        let delta = frame(atBeat: beatPosition(here) + beats) - here
        if renderer.loopActive {
            renderer.setLoop(start: renderer.loopStart + delta, end: renderer.loopEnd + delta, active: true)
        }
        renderer.jump(by: delta)
    }

    /// Momentary loop: the track keeps running underneath and resumes in time on release.
    func rollBegin(_ beats: Double) {
        guard isLoaded, beatFrames > 0 else { return }
        borrowLoop()
        heldMomentaryPads += 1
        renderer.loopActive = false
        loopActive = false
        setLoop(beats: beats, resizeExisting: false)
    }

    func rollEnd() { momentaryPadReleased() }

    /// A held roll or slice takes over the loop for a moment, so remember what it's replacing.
    private func borrowLoop() {
        guard heldMomentaryPads == 0 else { return }
        renderer.engageSlip()
        borrowedLoop = BorrowedLoop(start: renderer.loopStart, end: renderer.loopEnd, beats: chosenLoopBeats ?? loopBeats, inSet: loopInSet)
    }

    /// When the last held pad comes up, the track returns to where it would have been. Whatever loop
    /// was set before comes back as it was, or else RELOOP and SAVE LOOP would find the roll's.
    private func momentaryPadReleased() {
        heldMomentaryPads = max(0, heldMomentaryPads - 1)
        guard heldMomentaryPads == 0 else { return }
        renderer.loopActive = false
        loopActive = false
        renderer.releaseSlip()
        if let borrowed = borrowedLoop {
            renderer.setLoop(start: borrowed.start, end: borrowed.end, active: false)
            loopBeats = borrowed.beats
            loopInSet = borrowed.inSet
        }
        borrowedLoop = nil
    }

    // MARK: Slicer

    /// Plays one eighth of the current bar for as long as it's held; the track keeps running
    /// underneath and comes back in time on release.
    func sliceBegin(_ slice: Int) {
        guard isLoaded, beatFrames > 0 else { return }
        if !isPlaying { play() }
        // Bars count from the grid, so this works whatever the tempo's doing here.
        let barStart = (beatPosition(renderer.playhead) / 4).rounded(.down) * 4
        let start = frame(atBeat: barStart + Double(slice) / 2)
        let length = frame(atBeat: barStart + Double(slice + 1) / 2) - start
        // A second pad while one's held plays that slice; the return point stays where it was.
        borrowLoop()
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

    /// Phase difference to master in this deck's beats, wrapped to -0.5...0.5. With both decks
    /// live, pass positions from `DJEngine.positions` so they're from the same moment.
    func phaseOffset(to master: Deck, frame: Double? = nil, masterFrame: Double? = nil) -> Double {
        guard beatFrames > 0, master.beatFrames > 0, master.effectiveBPM > 0 else { return 0 }
        let scale = effectiveBPM / master.effectiveBPM
        let masterBeats = master.beatPosition(masterFrame ?? master.renderer.playhead) * scale
        let mine = beatPosition(frame ?? renderer.playhead)
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

    func isFXOn(_ effect: BeatFX) -> Bool { activeFX.contains { $0.effect == effect } }

    /// Presses an FX pad. The effect joins the chain and stays on until it's released. If the chain's
    /// already full, the effect that's been on longest makes way.
    func fxEngage(_ type: BeatFX) {
        if isFXOn(type) {
            focusFX(type)
            return
        }
        // Letting another effect go moves the controls to a different one, so remember these.
        let beats = fxBeats, depth = fxDepth
        if type.dsp == CheeksFXNone {
            fxType = type
            activeFX.append(ActiveFX(effect: type, link: nil, beats: fxBeats, depth: fxDepth))
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
            return
        }
        let chained = activeFX.compactMap(\.link)
        if chained.count == Int(CHEEKS_FX_LINKS), let oldest = activeFX.first(where: { $0.link != nil }) {
            fxRelease(oldest.effect, quantized: false)
        }
        fxType = type
        if fxBeats != beats { fxBeats = beats }
        if fxDepth != depth { fxDepth = depth }
        let used = Set(activeFX.compactMap(\.link))
        let link = (0..<Int(CHEEKS_FX_LINKS)).first { !used.contains($0) } ?? 0
        activeFX.append(ActiveFX(effect: type, link: link, beats: beats, depth: depth))
        renderer.setFXLink(link, type: type.dsp, on: true, beats: beats, depth: depth)
    }

    /// Makes the FX controls show this effect, and changing them change it.
    func focusFX(_ effect: BeatFX) {
        guard let active = activeFX.first(where: { $0.effect == effect }) else { return }
        fxType = effect
        if fxBeats != active.beats { fxBeats = active.beats }
        if fxDepth != active.depth { fxDepth = active.depth }
    }

    /// Lets one effect go. With quantize on, it ends on the next beat of its own length, so a gate
    /// or a flanger finishes in time and an echo's tail starts from a beat.
    func fxRelease(_ effect: BeatFX, quantized: Bool = true) {
        guard let index = activeFX.firstIndex(where: { $0.effect == effect }) else { return }
        let active = activeFX.remove(at: index)
        if effect == .roll { rollEnd() }
        if let link = active.link {
            if quantized && quantize && isPlaying && beatFrames > 0 {
                let step = min(active.beats, 1)
                let next = ((beatPosition(renderer.playhead) / step).rounded(.down) + 1) * step
                renderer.releaseFX(link: link, atBeat: next)
            } else {
                renderer.setFXLink(link, type: effect.dsp, on: false, beats: active.beats, depth: active.depth)
            }
        }
        if let latest = activeFX.last { focusFX(latest.effect) }
    }

    /// Lets everything go, straight away.
    func fxRelease() {
        for active in activeFX { fxRelease(active.effect, quantized: false) }
    }

    /// The controls change whichever effect they're showing.
    func fxSettingsChanged() {
        guard let index = activeFX.firstIndex(where: { $0.effect == fxType }) else { return }
        activeFX[index].beats = fxBeats
        activeFX[index].depth = fxDepth
        if let link = activeFX[index].link {
            renderer.setFXLink(link, type: fxType.dsp, on: true, beats: fxBeats, depth: fxDepth)
        }
    }

    func applyFX() {
        var mask = 0
        for stem in fxStems { mask |= 1 << stem.rawValue }
        renderer.setFXStems(mask == 0 ? 0xF : mask)
    }

    /// Everything off, for a new track. Effects still ringing carry on until they've died away.
    func clearFX() {
        activeFX = []
        for link in 0..<Int(CHEEKS_FX_LINKS) {
            renderer.setFXLink(link, type: CheeksFXNone, on: false, beats: fxBeats, depth: fxDepth)
        }
    }

    /// Ends a track on its own echo: the echo fills up, and on the next beat that's at least half a
    /// beat away the track's sound cuts and only the repeats are left. Pressing it again brings the
    /// track straight back.
    func toggleEchoOut() {
        guard isLoaded else { return }
        if echoingOut {
            endEchoOut()
            return
        }
        guard isPlaying, beatFrames > 0 else {
            onMessage?("Echo out needs the deck playing.", .refused)
            return
        }
        echoingOut = true
        // The key's only on the FX page, and a silent deck needs explaining from anywhere else.
        onMessage?("Echo out on deck \(index + 1). Press OUT again to bring it back.", .info)
        let here = beatPosition(renderer.playhead)
        let cut = (here + 0.5).rounded(.up)
        // The echo's input closes on the same beat as the cut, so what's in the line rings out.
        if !isFXOn(.echo) {
            fxBeats = max(0.5, min(fxBeats, 1))
            fxDepth = max(fxDepth, 0.7)
            fxEngage(.echo)
        }
        renderer.cutSource(atBeat: cut)
        if let index = activeFX.firstIndex(where: { $0.effect == .echo }), let link = activeFX[index].link {
            activeFX.remove(at: index)
            renderer.releaseFX(link: link, atBeat: cut)
        }
    }

    func endEchoOut() {
        guard echoingOut else { return }
        echoingOut = false
        renderer.restoreSource()
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
                    if !wasCancelled { self.onMessage?("Couldn't split this track into stems.", .problem) }
                }
            }
        }
    }

    // MARK: Beat grid editing

    private var barSeconds: Double { bpm > 0 ? 4 * 60 / bpm : 0 }

    /// Fixes half/double-time detection (multiplier 2 or 0.5).
    func scaleBPM(_ multiplier: Double) {
        guard let current = track?.bpm else { return }
        updateTrack { t in
            t.bpm = current * multiplier
            t.tempoMarkers = t.tempoMarkers?.map { TempoMarker(time: $0.time, bpm: $0.bpm * multiplier, beatInBar: $0.beatInBar) }
        }
    }

    func nudgeBPM(by delta: Double) {
        guard let current = track?.bpm, track?.tempoMarkers == nil else { return }
        updateTrack { $0.bpm = max(40, ((current + delta) * 100).rounded() / 100) }
    }

    /// Slides the whole grid earlier/later.
    func shiftGrid(milliseconds: Double) {
        guard barSeconds > 0, let first = track?.firstBeat else { return }
        let bar = barSeconds
        var moved = (first + milliseconds / 1000).truncatingRemainder(dividingBy: bar)
        if moved < 0 { moved += bar }
        updateTrack { t in
            t.firstBeat = moved
            t.tempoMarkers = t.tempoMarkers?.map { TempoMarker(time: $0.time + milliseconds / 1000, bpm: $0.bpm, beatInBar: $0.beatInBar) }
        }
    }

    /// Makes the playhead (snapped to the nearest beat when quantize is on) the first beat of a bar.
    func setDownbeatHere() {
        guard barSeconds > 0 else { return }
        if track?.tempoMarkers != nil {
            // The beats stay where they are; only which one counts as the "1" changes.
            let offset = Int(beatPosition(snap(renderer.playhead)).rounded())
            updateTrack { t in
                t.tempoMarkers = t.tempoMarkers?.map { m in
                    TempoMarker(time: m.time, bpm: m.bpm, beatInBar: ((m.beatInBar - offset) % 4 + 4) % 4)
                }
            }
            return
        }
        let bar = barSeconds
        let here = snap(renderer.playhead) / sampleRate
        var first = here.truncatingRemainder(dividingBy: bar)
        if first < 0 { first += bar }
        updateTrack { $0.firstBeat = first }
    }

    /// Replaces tempo changes with one steady tempo, for when the detected changes are wrong.
    func flattenGrid() {
        guard let first = grid?.seconds(atBeat: 0), let average = track?.bpm else { return }
        updateTrack { t in
            t.tempoMarkers = nil
            t.firstBeat = first
            t.bpm = average
        }
    }

    // MARK: EQ / filter

    /// Knob to linear gain: fully left removes the band, centre is flat, fully right is +6 dB.
    func applyEQ() {
        func gain(_ v: Float) -> Float { v <= -0.97 ? 0 : pow(10, (v < 0 ? v * 26 : v * 6) / 20) }
        renderer.setEQ(low: gain(eqLow), mid: gain(eqMid), high: gain(eqHigh))
    }

    /// One knob, whatever it's set to do. As a filter, left sweeps a low-pass down and right sweeps a high-pass up.
    func applyFilter() {
        let amount = abs(filter) < 0.015 ? 0 : filter
        renderer.setFilter(colorFX == .filter ? amount : 0)
        renderer.setColor(colorFX.dsp, amount: colorFX == .filter ? 0 : amount)
    }
}
