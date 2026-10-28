import AVFoundation
import os

/// The realtime half of a deck: owns the playhead and produces audio on the render thread.
///
/// Scalar state (playhead, loop points, scratch target…) is written from the main thread
/// and read on the audio thread without locking; a stale read only delays a change by
/// one render cycle. Swapping the audio sources is the one structural change and is
/// guarded by an unfair lock that the render thread only ever *tries* to take.
final class DeckRenderer {
    let sampleRate: Double

    // Sources: one full mix, or four stems (see `Stem`).
    /// Strong references keep the buffers alive; the render thread only sees the raw slots below.
    private var sources: [PCM16Stereo] = []
    private let sourceSlots: UnsafeMutablePointer<UnsafeMutablePointer<Int16>?>
    private var sourceCount = 0
    /// Gain that undoes the stems' storage headroom (read on the audio thread, so precomputed).
    private let stemScale: Float = 1 / PCM16Stereo.stemHeadroom / 32768
    private(set) var frameCount = 0
    private let lock: UnsafeMutablePointer<os_unfair_lock>

    // Transport
    var playhead: Double = 0
    var isPlaying = false
    var reverse = false
    /// Frames still to be added (or removed) by a pitch bend; decays as it is applied.
    var pendingNudge: Double = 0
    /// Set once playback runs off the end of the track.
    var reachedEnd = false

    // Scratch: the jog wheel moves a target and the playhead chases it like vinyl under a finger.
    var scratching = false
    var scratchTarget: Double = 0
    private var scratchRate: Double = 0

    // Brake effect: playback slows to a stop over `brakeLength` frames.
    private(set) var braking = false
    private var brakeRate: Double = 1
    private var brakeStep: Double = 0

    // Loop
    var loopActive = false
    var loopStart: Double = 0
    var loopEnd: Double = 0

    // Slip: while engaged, a shadow playhead keeps running so the track resumes where it would have been.
    var slipEngaged = false
    private(set) var slipPlayhead: Double = 0

    // Stem gains (target) and smoothed current gains, order of `Stem.allCases`.
    let stemGains: UnsafeMutablePointer<Float>
    private let currentGains: UnsafeMutablePointer<Float>

    private(set) lazy var node: AVAudioSourceNode = makeNode()

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
        stemGains = .allocate(capacity: 4)
        stemGains.initialize(repeating: 1, count: 4)
        currentGains = .allocate(capacity: 4)
        currentGains.initialize(repeating: 1, count: 4)
        sourceSlots = .allocate(capacity: 4)
        sourceSlots.initialize(repeating: nil, count: 4)
    }

    deinit {
        lock.deallocate()
        stemGains.deallocate()
        currentGains.deallocate()
        sourceSlots.deallocate()
    }

    var hasStems: Bool { sources.count == 4 }

    /// The full-mix buffer while no stems are loaded. Main thread only (it's the only writer).
    var mixSource: PCM16Stereo? { sources.count == 1 ? sources[0] : nil }

    /// Replaces the audio being played. Pass one buffer (full mix) or four (stems).
    func setSources(_ newSources: [PCM16Stereo]) {
        os_unfair_lock_lock(lock)
        sources = newSources
        for i in 0..<4 { sourceSlots[i] = i < newSources.count ? newSources[i].data : nil }
        sourceCount = min(newSources.count, 4)
        frameCount = newSources.first?.frames ?? 0
        if playhead > Double(frameCount) { playhead = 0 }
        os_unfair_lock_unlock(lock)
    }

    func startBrake(overFrames frames: Double) {
        brakeRate = 1
        brakeStep = 1 / max(frames, 1)
        braking = true
    }

    func beginScratch() {
        scratchTarget = playhead
        scratchRate = isPlaying ? 1 : 0
        scratching = true
    }

    func engageSlip() {
        slipPlayhead = playhead
        slipEngaged = true
    }

    /// Ends slip and jumps back to where the track would have been.
    func releaseSlip() {
        guard slipEngaged else { return }
        slipEngaged = false
        playhead = slipPlayhead
    }

    /// Renders `frames` frames outside of an audio engine (used by tests).
    func renderOffline(frames: Int) -> (left: [Float], right: [Float]) {
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                render(l.baseAddress!, r.baseAddress!, frames)
            }
        }
        return (left, right)
    }

    private func makeNode() -> AVAudioSourceNode {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        // unowned(unsafe): no reference counting on the audio thread; the renderer lives as long as its deck.
        return AVAudioSourceNode(format: format) { [unowned(unsafe) self] _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            self.render(left, right, Int(frameCount))
            return noErr
        }
    }

    private func render(_ outL: UnsafeMutablePointer<Float>, _ outR: UnsafeMutablePointer<Float>, _ n: Int) {
        guard os_unfair_lock_trylock(lock) else {
            outL.update(repeating: 0, count: n)
            outR.update(repeating: 0, count: n)
            return
        }
        defer { os_unfair_lock_unlock(lock) }

        let count = frameCount
        let sourceCount = self.sourceCount
        guard count > 1, sourceCount > 0 else {
            outL.update(repeating: 0, count: n)
            outR.update(repeating: 0, count: n)
            return
        }
        let lastFrame = Double(count - 1)
        let usesStems = sourceCount == 4
        let scale: Float = usesStems ? stemScale : 1 / 32768

        for i in 0..<n {
            // 1. Work out how fast the playhead moves this sample.
            var rate: Double
            if scratching {
                let wanted = max(-8, min(8, (scratchTarget - playhead) / (sampleRate * 0.015)))
                scratchRate += (wanted - scratchRate) * 0.01
                rate = scratchRate
            } else if braking {
                brakeRate -= brakeStep
                if brakeRate <= 0 {
                    braking = false
                    isPlaying = false
                    brakeRate = 1
                    rate = 0
                } else {
                    rate = brakeRate
                }
            } else if isPlaying {
                rate = reverse ? -1 : 1
                if pendingNudge != 0 {
                    let bend = max(-0.3, min(0.3, pendingNudge * 0.0004))
                    rate += bend
                    pendingNudge -= bend
                    if abs(pendingNudge) < 0.5 { pendingNudge = 0 }
                }
            } else {
                rate = 0
            }

            // 2. Read the (interpolated) sample, mixing stems with their gains.
            var l: Float = 0
            var r: Float = 0
            let pos = playhead
            if rate != 0 && pos >= 0 && pos < lastFrame {
                let i0 = Int(pos)
                let frac = Float(pos - Double(i0))
                for s in 0..<sourceCount {
                    var gain: Float = 1
                    if usesStems {
                        currentGains[s] += (stemGains[s] - currentGains[s]) * 0.002
                        gain = currentGains[s]
                        if gain < 0.0001 { continue }
                    }
                    let p = sourceSlots[s].unsafelyUnwrapped
                    let a0 = Float(p[i0 * 2]), a1 = Float(p[i0 * 2 + 2])
                    let b0 = Float(p[i0 * 2 + 1]), b1 = Float(p[i0 * 2 + 3])
                    l += gain * (a0 + (a1 - a0) * frac)
                    r += gain * (b0 + (b1 - b0) * frac)
                }
            }
            outL[i] = l * scale
            outR[i] = r * scale

            // 3. Advance.
            playhead += rate
            if slipEngaged {
                if isPlaying { slipPlayhead += 1 }
            } else {
                slipPlayhead = playhead
            }
            if loopActive && rate > 0 && playhead >= loopEnd && loopEnd > loopStart {
                playhead -= (loopEnd - loopStart)
            }
            if playhead >= lastFrame {
                playhead = lastFrame
                if isPlaying && !scratching {
                    isPlaying = false
                    reachedEnd = true
                }
            } else if playhead < 0 {
                playhead = 0
            }
        }
    }
}
