import AVFoundation

/// Swift's view of one deck in the realtime core (`DSP/Engine.cpp`).
///
/// `playhead` is what is being heard, in frames. Setters queue a change for the render thread and
/// getters read what it last published, so nothing here ever blocks on audio.
final class DeckRenderer {
    let sampleRate: Double
    let handle: OpaquePointer

    /// Strong references keep the buffers alive; the render thread only sees their raw pointers.
    private var sources: [PCM16Stereo] = []
    private(set) var frameCount = 0

    /// Gain that undoes the stems' storage headroom.
    private static let stemScale: Float = 1 / PCM16Stereo.stemHeadroom / 32768

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        handle = cheeks_deck_create(sampleRate)
    }

    deinit { cheeks_deck_destroy(handle) }

    var hasStems: Bool { sources.count == 4 }

    /// The full-mix buffer while no stems are loaded. Main thread only (it's the only writer).
    var mixSource: PCM16Stereo? { sources.count == 1 ? sources[0] : nil }

    /// Replaces the audio being played. Pass one buffer (full mix) or four (stems).
    func setSources(_ newSources: [PCM16Stereo]) {
        let slots: [UnsafePointer<Int16>?] = newSources.map { UnsafePointer($0.data) }
        let frames = newSources.first?.frames ?? 0
        slots.withUnsafeBufferPointer {
            cheeks_deck_set_sources(handle, $0.baseAddress, Int32(newSources.count), Int64(frames), Self.stemScale)
        }
        // Old buffers are released only once the render thread can no longer reach them.
        sources = newSources
        frameCount = frames
    }

    // MARK: Transport

    var playhead: Double {
        get { cheeks_deck_position(handle) }
        set { cheeks_deck_seek(handle, newValue) }
    }

    var isPlaying: Bool {
        get { cheeks_deck_playing(handle) }
        set { cheeks_deck_set_playing(handle, newValue) }
    }

    var reverse: Bool {
        get { cheeks_deck_reverse(handle) }
        set { cheeks_deck_set_reverse(handle, newValue) }
    }

    var reachedEnd: Bool {
        get { cheeks_deck_reached_end(handle) }
        set { if !newValue { cheeks_deck_clear_reached_end(handle) } }
    }

    /// Frames still to be added or removed by a pitch bend; decays as it's applied.
    var pendingNudge: Double {
        get { cheeks_deck_nudge(handle) }
        set { cheeks_deck_add_nudge(handle, newValue - pendingNudge) }
    }

    func nudge(by frames: Double) { cheeks_deck_add_nudge(handle, frames) }

    func jump(by frames: Double) { cheeks_deck_jump(handle, frames) }

    /// Jumps to `frame` plus the deck's current position within the beat, so the jump lands in time.
    func seekBeatLocked(_ frame: Double, beatFrames: Double, firstBeatFrame: Double) {
        cheeks_deck_seek_beat_locked(handle, frame, beatFrames, firstBeatFrame)
    }

    func setTempo(ratio: Double, keyLock: Bool, keyShift: Int) {
        cheeks_deck_set_tempo(handle, ratio, keyLock, Int32(keyShift))
    }

    var isStretching: Bool { cheeks_deck_is_stretching(handle) }

    // MARK: Scratch, brake, backspin

    var scratching: Bool { cheeks_deck_scratching(handle) }

    var scratchTarget: Double {
        get { cheeks_deck_scratch_target(handle) }
        set { cheeks_deck_scratch_move(handle, newValue - scratchTarget) }
    }

    func beginScratch() { cheeks_deck_scratch_begin(handle) }
    func moveScratch(byFrames frames: Double) { cheeks_deck_scratch_move(handle, frames) }
    func endScratch() { cheeks_deck_scratch_end(handle) }

    var braking: Bool { cheeks_deck_ramping(handle) }
    func startBrake(overFrames frames: Double) { cheeks_deck_brake(handle, frames) }
    func startBackspin(overFrames frames: Double) { cheeks_deck_backspin(handle, frames) }

    // MARK: Loop and slip

    var loopActive: Bool {
        get { cheeks_deck_loop_active(handle) }
        set { cheeks_deck_set_loop_active(handle, newValue) }
    }

    var loopStart: Double {
        get { cheeks_deck_loop_start(handle) }
        set { cheeks_deck_set_loop(handle, newValue, loopEnd, loopActive) }
    }

    var loopEnd: Double {
        get { cheeks_deck_loop_end(handle) }
        set { cheeks_deck_set_loop(handle, loopStart, newValue, loopActive) }
    }

    func setLoop(start: Double, end: Double, active: Bool) {
        cheeks_deck_set_loop(handle, start, end, active)
    }

    var slipEngaged: Bool { cheeks_deck_slip_engaged(handle) }
    var slipPlayhead: Double { cheeks_deck_slip_position(handle) }

    func engageSlip() { cheeks_deck_slip_engage(handle) }

    /// Ends slip and jumps back to where the track would have been.
    func releaseSlip() { cheeks_deck_slip_release(handle) }

    /// Ends slip and stays put.
    func cancelSlip() { cheeks_deck_slip_cancel(handle) }

    // MARK: Stems, FX and channel

    func setStemGain(_ stem: Int, _ gain: Float) { cheeks_deck_set_stem_gain(handle, Int32(stem), gain) }
    func stemPeak(_ stem: Int) -> Float { cheeks_deck_stem_level(handle, Int32(stem)) }

    func setGrid(beatFrames: Double, firstBeatFrame: Double) {
        cheeks_deck_set_grid(handle, beatFrames, firstBeatFrame)
    }

    func setFX(_ type: CheeksFXType, on: Bool, beats: Double, depth: Float, stemMask: Int) {
        cheeks_deck_set_fx(handle, type, on, beats, depth, Int32(stemMask))
    }

    func setEQ(low: Float, mid: Float, high: Float) { cheeks_deck_set_eq(handle, low, mid, high) }
    func setFilter(_ amount: Float) { cheeks_deck_set_filter(handle, amount) }
    var peak: Float { cheeks_deck_peak(handle) }

    /// Position, speed and the time they were captured, for drawing between audio callbacks.
    var displayState: CheeksDisplayState { cheeks_deck_display_state(handle) }

    // MARK: Offline rendering (used by tests)

    /// Renders `frames` frames of the source path: transport, stems, FX and the stretcher.
    func renderOffline(frames: Int) -> (left: [Float], right: [Float]) {
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                cheeks_deck_render_source(handle, l.baseAddress!, r.baseAddress!, Int32(frames))
            }
        }
        return (left, right)
    }

    /// Renders `frames` frames of the whole channel: the source path plus EQ and filter.
    func renderChannelOffline(frames: Int) -> (left: [Float], right: [Float]) {
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                cheeks_deck_render_channel(handle, l.baseAddress!, r.baseAddress!, Int32(frames))
            }
        }
        return (left, right)
    }
}
