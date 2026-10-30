import Accelerate
import CoreML

/// The model's interface. `mix` is `[1, 2, segment]`, `spec` is `[1, 4, 2048, 336]` with channels
/// L.re, L.im, R.re, R.im. The result is `spec` `[1, 4, 4, 2048, 336]` and `time` `[1, 4, 2, segment]`,
/// with sources in Demucs order: drums, bass, other, vocals.
protocol HTDemucsNetwork {
    func predict(mix: MLMultiArray, spec: MLMultiArray) throws -> (spec: MLMultiArray, time: MLMultiArray)
}

enum StemSeparationError: Error {
    case modelMismatch
    case invalidModelOutput
}

/// Runs a whole track through an `HTDemucsNetwork`, the same way as `demucs.apply.apply_model`
/// with `shifts=0, split=True, overlap=0.25` inside the normalisation of `demucs.api.Separator`.
///
/// Memory: nothing here is track-length except the Int16 stems being written. Segments overlap by
/// a quarter, so once one has been added in, the samples before the next segment's start are
/// final and are written out straight away. `tools/stems/pipeline.py` is the same algorithm in numpy.
struct HTDemucsPipeline {
    static let segment = 343_980 // int(44100 * 7.8)
    static let stride = 257_985 // int(0.75 * segment)

    let network: HTDemucsNetwork

    func separate(
        _ source: PCM16Stereo,
        progress: @escaping (Double) -> Void,
        isCancelled: @escaping () -> Bool
    ) throws -> [PCM16Stereo] {
        let n = source.frames
        let stems = Stem.allCases.map { _ in PCM16Stereo(frames: n) }
        guard n > 0 else {
            progress(1)
            return stems
        }

        let segment = Self.segment
        let statistics = Self.trackStatistics(source)
        let stft = DemucsSTFT(length: segment)
        let bins = DemucsSTFT.bins, frames = stft.frames

        // The model's inputs are wrapped around these, so filling them is all it takes.
        let mixBuffer = UnsafeMutablePointer<Float>.allocate(capacity: 2 * segment)
        let specBuffer = UnsafeMutablePointer<Float>.allocate(capacity: 4 * bins * frames)
        let mixArray = try MLMultiArray(
            dataPointer: mixBuffer,
            shape: [1, 2, NSNumber(value: segment)],
            dataType: .float32,
            strides: [NSNumber(value: 2 * segment), NSNumber(value: segment), 1],
            deallocator: { _ in mixBuffer.deallocate() }
        )
        let specArray = try MLMultiArray(
            dataPointer: specBuffer,
            shape: [1, 4, NSNumber(value: bins), NSNumber(value: frames)],
            dataType: .float32,
            strides: [NSNumber(value: 4 * bins * frames), NSNumber(value: bins * frames), NSNumber(value: frames), 1],
            deallocator: { _ in specBuffer.deallocate() }
        )

        let window = OverlapAddWindow(length: segment, stft: stft)
        var offset = 0
        progress(0)
        while offset < n {
            if isCancelled() { throw CancellationError() }

            // TensorChunk.padded: a final chunk that's short reaches back into earlier audio by
            // half the shortfall and is padded with zeros after the end of the track. The
            // prediction is then cut back to the chunk (center_trim).
            let length = min(segment, n - offset)
            let trim = (segment - length) / 2
            fill(mixBuffer, from: source, start: offset - trim, statistics: statistics)
            for channel in 0..<2 {
                stft.forward(
                    mixBuffer + channel * segment,
                    real: specBuffer + 2 * channel * bins * frames,
                    imag: specBuffer + (2 * channel + 1) * bins * frames,
                    binStride: frames,
                    frameStride: 1
                )
            }

            try autoreleasepool {
                let output = try network.predict(mix: mixArray, spec: specArray)
                try window.add(output, trim: trim, length: length)
            }

            // Everything before the next segment's start is final.
            let done = min(Self.stride, n - offset)
            window.drain(done, source: source, into: stems, at: offset, statistics: statistics)
            offset += Self.stride
            progress(Double(min(offset, n)) / Double(n))
        }
        return stems
    }

    /// Mean and standard deviation of the mono mix across the whole track, as `Separator.separate_tensor`.
    struct Statistics {
        let mean: Float
        let std: Float
    }

    static func trackStatistics(_ source: PCM16Stereo) -> Statistics {
        // In units of half an LSB (L + R), where the sums are exact: 20 min of full-scale audio
        // gives a sum of squares near 2^58.
        var sum: Int64 = 0, squares: Int64 = 0
        let data = source.data
        for i in 0..<source.frames {
            let mono = Int64(data[2 * i]) + Int64(data[2 * i + 1])
            sum += mono
            squares += mono * mono
        }
        let n = Double(source.frames)
        let unit = 2.0 * 32767
        let mean = Double(sum) / n
        // torch.std is unbiased: N - 1.
        let variance = n > 1 ? max(0, Double(squares) - Double(sum) * mean) / (n - 1) : 0
        return Statistics(mean: Float(mean / unit), std: Float(variance.squareRoot() / unit + 1e-8))
    }

    /// Writes the normalised samples `start ..< start + segment` to `buffer` as L then R. Anything
    /// off the ends of the track is zero: apply_model pads after normalising.
    private func fill(
        _ buffer: UnsafeMutablePointer<Float>,
        from source: PCM16Stereo,
        start: Int,
        statistics: Statistics
    ) {
        let segment = Self.segment
        let n = source.frames
        let data = source.data
        let left = buffer, right = buffer + segment
        let mean = statistics.mean, std = statistics.std
        for i in 0..<segment {
            let s = start + i
            if s >= 0, s < n {
                left[i] = (Float(data[2 * s]) / 32767 - mean) / std
                right[i] = (Float(data[2 * s + 1]) / 32767 - mean) / std
            } else {
                left[i] = 0
                right[i] = 0
            }
        }
    }
}

/// One segment's worth of overlap-add for the three sources that get computed. Melody isn't among
/// them: it's defined as whatever the others leave of the mix, which is "other" plus the residual.
private final class OverlapAddWindow {
    /// Demucs source index and destination stem of each accumulated source.
    private static let sources: [(demucsIndex: Int, stem: Stem)] = [(3, .vocals), (1, .bass), (0, .drums)]

    private let length: Int
    private let stft: DemucsSTFT
    private let accumulated: UnsafeMutablePointer<Float>
    private let totalWeight: UnsafeMutablePointer<Float>
    private let weight: UnsafeMutablePointer<Float>
    private let scratch: UnsafeMutablePointer<Float>
    private var accumulatedCount: Int { Self.sources.count * 2 * length }

    init(length: Int, stft: DemucsSTFT) {
        self.length = length
        self.stft = stft
        accumulated = .allocate(capacity: Self.sources.count * 2 * length)
        accumulated.initialize(repeating: 0, count: Self.sources.count * 2 * length)
        totalWeight = .allocate(capacity: length)
        totalWeight.initialize(repeating: 0, count: length)
        scratch = .allocate(capacity: length)
        weight = .allocate(capacity: length)
        // Triangle peaking in the middle of the segment, normalised to 1.
        let half = length / 2
        let peak = Float(max(half, length - half))
        for i in 0..<half { weight[i] = Float(i + 1) / peak }
        for i in half..<length { weight[i] = Float(length - i) / peak }
    }

    deinit {
        accumulated.deallocate()
        totalWeight.deallocate()
        scratch.deallocate()
        weight.deallocate()
    }

    /// Adds one prediction, spectral branch through the iSTFT plus time branch, keeping
    /// `trim ..< trim + count` of it.
    func add(_ output: (spec: MLMultiArray, time: MLMultiArray), trim: Int, length count: Int) throws {
        let specStrides = output.spec.strides.map(\.intValue)
        let timeStrides = output.time.strides.map(\.intValue)
        guard output.spec.dataType == .float32, output.time.dataType == .float32,
              specStrides.count == 5, timeStrides.count == 4 else {
            throw StemSeparationError.invalidModelOutput
        }
        try output.spec.withUnsafeBufferPointer(ofType: Float.self) { specBuffer in
            try output.time.withUnsafeBufferPointer(ofType: Float.self) { timeBuffer in
                let spec = specBuffer.baseAddress!, time = timeBuffer.baseAddress!
                for (slot, source) in Self.sources.enumerated() {
                    for channel in 0..<2 {
                        let specBase = source.demucsIndex * specStrides[1] + 2 * channel * specStrides[2]
                        stft.inverse(
                            real: spec + specBase,
                            imag: spec + specBase + specStrides[2],
                            binStride: specStrides[3],
                            frameStride: specStrides[4],
                            output: scratch
                        )
                        let timeBase = source.demucsIndex * timeStrides[1] + channel * timeStrides[2]
                        vDSP_vadd(scratch, 1, time + timeBase, vDSP_Stride(timeStrides[3]), scratch, 1, vDSP_Length(length))

                        // A NaN would trap on the conversion to Int16, and means the prediction is junk.
                        var magnitude: Float = 0
                        vDSP_svemg(scratch, 1, &magnitude, vDSP_Length(length))
                        guard magnitude.isFinite else { throw StemSeparationError.invalidModelOutput }

                        let values = accumulated + (slot * 2 + channel) * length
                        vDSP_vma(scratch + trim, 1, weight, 1, values, 1, values, 1, vDSP_Length(count))
                    }
                }
            }
        }
        vDSP_vadd(totalWeight, 1, weight, 1, totalWeight, 1, vDSP_Length(count))
    }

    /// Writes the first `count` samples of the window to the stems at `position`, then slides the
    /// window along.
    func drain(
        _ count: Int,
        source: PCM16Stereo,
        into stems: [PCM16Stereo],
        at position: Int,
        statistics: HTDemucsPipeline.Statistics
    ) {
        let scale = statistics.std * PCM16Stereo.stemHeadroom * 32767
        let offset = statistics.mean * PCM16Stereo.stemHeadroom * 32767
        for (slot, entry) in Self.sources.enumerated() {
            let out = stems[entry.stem.rawValue].data
            for channel in 0..<2 {
                let values = accumulated + (slot * 2 + channel) * length
                for i in 0..<count {
                    let value = (values[i] / totalWeight[i] * scale + offset).rounded()
                    out[(position + i) * 2 + channel] = Int16(max(-32768, min(32767, value)))
                }
            }
        }

        // The stems have to sum back to the track exactly, so melody takes the rest.
        let vocals = stems[Stem.vocals.rawValue].data
        let bass = stems[Stem.bass.rawValue].data
        let drums = stems[Stem.drums.rawValue].data
        let melody = stems[Stem.melody.rawValue].data
        let mix = source.data
        for j in (position * 2)..<((position + count) * 2) {
            let target = Int32((Float(mix[j]) * PCM16Stereo.stemHeadroom).rounded())
            melody[j] = Int16(clamping: target - Int32(vocals[j]) - Int32(bass[j]) - Int32(drums[j]))
        }

        let remaining = length - count
        for slot in 0..<(Self.sources.count * 2) {
            let values = accumulated + slot * length
            memmove(values, values + count, remaining * MemoryLayout<Float>.stride)
            vDSP_vclr(values + remaining, 1, vDSP_Length(count))
        }
        memmove(totalWeight, totalWeight + count, remaining * MemoryLayout<Float>.stride)
        vDSP_vclr(totalWeight + remaining, 1, vDSP_Length(count))
    }
}
