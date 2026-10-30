import Accelerate
import CoreML
import XCTest
@testable import Cheeks

/// Stands in for the model, the same as `FakeNetwork` in `tools/stems/gen_fixtures.py`: the time
/// branch scales with the chunk's own level, and the spectral branch is a gain on the input
/// spectrogram. Its outputs have padded strides, which Core ML is allowed to do too.
private final class FakeNetwork: HTDemucsNetwork {
    static let timeGain: [Float] = [0.11, 0.23, 0.31, 0.41]
    static let specGain: [Float] = [0.19, 0.07, 0.13, 0.17]

    private(set) var predictions = 0
    var poison = false
    var onPredict: () -> Void = {}

    func predict(mix: MLMultiArray, spec: MLMultiArray) throws -> (spec: MLMultiArray, time: MLMultiArray) {
        predictions += 1
        onPredict()
        let segment = HTDemucsPipeline.segment
        let frames = 336, bins = DemucsSTFT.bins

        let mixIn = mix.dataPointer.assumingMemoryBound(to: Float.self)
        let specIn = spec.dataPointer.assumingMemoryBound(to: Float.self)
        var level: Float = 0
        vDSP_meamgv(mixIn, 1, &level, vDSP_Length(2 * segment))
        level += 1

        let timeStride = segment + 16
        let time = try paddedArray(shape: [1, 4, 2, segment], strides: [8 * timeStride, 2 * timeStride, timeStride, 1])
        let timeOut = time.dataPointer.assumingMemoryBound(to: Float.self)
        for source in 0..<4 {
            for channel in 0..<2 {
                let gain = Self.timeGain[source] * level
                let out = timeOut + (source * 2 + channel) * timeStride
                for i in 0..<segment { out[i] = gain * mixIn[channel * segment + i] }
            }
        }

        let frameStride = frames + 4
        let channelStride = bins * frameStride
        let specOut = try paddedArray(
            shape: [1, 4, 4, bins, frames],
            strides: [16 * channelStride, 4 * channelStride, channelStride, frameStride, 1]
        )
        let specOutPointer = specOut.dataPointer.assumingMemoryBound(to: Float.self)
        for source in 0..<4 {
            for channel in 0..<4 {
                let gain = Self.specGain[source]
                for bin in 0..<bins {
                    let input = specIn + channel * bins * frames + bin * frames
                    let out = specOutPointer + (source * 4 + channel) * channelStride + bin * frameStride
                    for frame in 0..<frames { out[frame] = gain * input[frame] }
                }
            }
        }
        if poison { timeOut[1234] = .nan }
        return (specOut, time)
    }

    private func paddedArray(shape: [Int], strides: [Int]) throws -> MLMultiArray {
        let count = strides[0] * shape[0]
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: count)
        buffer.initialize(repeating: 0, count: count)
        return try MLMultiArray(
            dataPointer: buffer,
            shape: shape.map { NSNumber(value: $0) },
            dataType: .float32,
            strides: strides.map { NSNumber(value: $0) },
            deallocator: { _ in buffer.deallocate() }
        )
    }
}

private enum Signals {
    /// The same signal as `test_signal` in `tools/stems/gen_fixtures.py`.
    static func test(_ n: Int) -> (left: [Float], right: [Float]) {
        var state: UInt32 = 12345
        var left = [Float](repeating: 0, count: n), right = left
        for i in 0..<n {
            state = state &* 1664525 &+ 1013904223
            let noise = Double(state) / 4_294_967_296 * 2 - 1
            let t = Double(i)
            let l = 0.4 * sin(2 * .pi * 440 * t / 44100) + 0.2 * sin(2 * .pi * 1000.5 * t / 44100 + 0.3) + 0.1 * noise
            let r = 0.3 * sin(2 * .pi * 220 * t / 44100) + 0.1 * sin(2 * .pi * 3000.25 * t / 44100) - 0.05 * noise
            let envelope = 0.6 + 0.4 * sin(2 * .pi * 0.13 * t / 44100)
            left[i] = Float(l * envelope)
            right[i] = Float(r * envelope)
        }
        return (left, right)
    }

    /// `test_spectrogram`: channels L.re, L.im, R.re, R.im, each `bins`-by-`frames`.
    static func spectrogram(frames: Int) -> [Float] {
        let bins = DemucsSTFT.bins
        var out = [Float](repeating: 0, count: 4 * bins * frames)
        for b in 0..<bins {
            for f in 0..<frames {
                let bin = Double(b), frame = Double(f)
                let first = 100 * 0.5 / (1 + 0.01 * bin), second = 100 * 0.3 / (1 + 0.02 * bin)
                let i = b * frames + f
                out[i] = Float(first * cos(0.01 * bin + 0.2 * frame))
                out[bins * frames + i] = Float(first * sin(0.013 * bin - 0.1 * frame))
                out[2 * bins * frames + i] = Float(second * cos(0.002 * bin * frame / 10 + 1))
                out[3 * bins * frames + i] = Float(second * sin(0.005 * bin + 0.3 * frame + 1))
            }
        }
        return out
    }

    static func pcm(_ n: Int) -> PCM16Stereo {
        let signal = test(n)
        return PCM16Stereo(left: signal.left, right: signal.right)
    }
}

final class DemucsSTFTTests: XCTestCase {
    private let segment = HTDemucsPipeline.segment

    private func spectrogram(_ left: [Float], _ right: [Float], stft: DemucsSTFT) -> [Float] {
        let bins = DemucsSTFT.bins, frames = stft.frames
        var out = [Float](repeating: 0, count: 4 * bins * frames)
        out.withUnsafeMutableBufferPointer { buffer in
            let base = buffer.baseAddress!
            stft.forward(left, real: base, imag: base + bins * frames, binStride: frames, frameStride: 1)
            stft.forward(right, real: base + 2 * bins * frames, imag: base + 3 * bins * frames, binStride: frames, frameStride: 1)
        }
        return out
    }

    private func inverse(_ spectrogram: [Float], channel: Int, stft: DemucsSTFT) -> [Float] {
        let bins = DemucsSTFT.bins, frames = stft.frames
        var out = [Float](repeating: 0, count: stft.length)
        spectrogram.withUnsafeBufferPointer { z in
            let base = z.baseAddress! + 2 * channel * bins * frames
            stft.inverse(real: base, imag: base + bins * frames, binStride: frames, frameStride: 1, output: &out)
        }
        return out
    }

    func testFrameCountForASegment() {
        XCTAssertEqual(DemucsSTFT(length: segment).frames, 336)
        XCTAssertEqual(DemucsSTFT(length: 10240).frames, 10)
        XCTAssertEqual(DemucsSTFT(length: 10241).frames, 11)
    }

    func testForwardMatchesPyTorch() {
        let signal = Signals.test(segment)
        let stft = DemucsSTFT(length: segment)
        let z = spectrogram(signal.left, signal.right, stft: stft)
        let bins = DemucsSTFT.bins, frames = stft.frames

        XCTAssertEqual(StemFixtures.specPoints.count, StemFixtures.specValues.count)
        for (point, expected) in zip(StemFixtures.specPoints, StemFixtures.specValues) {
            let actual = z[point.channel * bins * frames + point.bin * frames + point.frame]
            XCTAssertEqual(actual, expected, accuracy: 1e-5, "\(point)")
        }
        for frame in 0..<frames {
            var energy = 0.0
            for channel in 0..<4 {
                for bin in 0..<bins {
                    let v = Double(z[channel * bins * frames + bin * frames + frame])
                    energy += v * v
                }
            }
            XCTAssertEqual(energy, Double(StemFixtures.specFrameEnergy[frame]), accuracy: 1e-4 * max(1, energy), "frame \(frame)")
        }
    }

    func testInverseMatchesPyTorch() {
        let stft = DemucsSTFT(length: segment)
        let z = Signals.spectrogram(frames: stft.frames)
        let indices = StemFixtures.ispecIndices
        for channel in 0..<2 {
            let y = inverse(z, channel: channel, stft: stft)
            for (position, index) in indices.enumerated() {
                let expected = StemFixtures.ispecValues[channel * indices.count + position]
                XCTAssertEqual(y[index], expected, accuracy: 2e-5, "channel \(channel), sample \(index)")
            }
            let energy = y.reduce(0.0) { $0 + Double($1) * Double($1) }
            XCTAssertEqual(energy, Double(StemFixtures.ispecEnergy[channel]), accuracy: 1e-4 * energy)
        }
    }

    /// Inside the segment the pair is a perfect reconstruction, for a signal with nothing at Nyquist
    /// (`_spec` drops that bin). The edges fade by design, as `_ispec` has silent frames there.
    func testRoundTrip() {
        for length in [segment, 10_000, 8192] {
            let left = (0..<length).map { Float(0.4 * sin(2 * .pi * 440 * Double($0) / 44100) + 0.2 * sin(0.3 * Double($0))) }
            let right = (0..<length).map { Float(0.5 * sin(2 * .pi * 3000.25 * Double($0) / 44100 + 0.7)) }
            let stft = DemucsSTFT(length: length)
            let z = spectrogram(left, right, stft: stft)
            let outLeft = inverse(z, channel: 0, stft: stft)
            let outRight = inverse(z, channel: 1, stft: stft)
            let margin = 2560
            for i in margin..<(length - margin) {
                if abs(outLeft[i] - left[i]) > 1e-5 || abs(outRight[i] - right[i]) > 1e-5 {
                    XCTFail("length \(length), sample \(i): \(outLeft[i]) vs \(left[i]), \(outRight[i]) vs \(right[i])")
                    return
                }
            }
        }
    }
}

final class HTDemucsPipelineTests: XCTestCase {
    private func separate(_ source: PCM16Stereo, network: FakeNetwork = FakeNetwork()) throws -> [PCM16Stereo] {
        try HTDemucsPipeline(network: network).separate(source, progress: { _ in }, isCancelled: { false })
    }

    private func checkAgainstApplyModel(
        frames: Int, positions: [Int], values: [Float], mean: Float, std: Float, segments: Int
    ) throws {
        let source = Signals.pcm(frames)
        let statistics = HTDemucsPipeline.trackStatistics(source)
        XCTAssertEqual(statistics.mean, mean, accuracy: 1e-6)
        XCTAssertEqual(statistics.std, std, accuracy: 1e-5)

        let network = FakeNetwork()
        let stems = try separate(source, network: network)
        XCTAssertEqual(network.predictions, segments)
        XCTAssertEqual(stems.count, 4)
        XCTAssertTrue(stems.allSatisfy { $0.frames == frames })

        // Fixture layout: [source (Demucs order)][channel][position]. "other" isn't computed.
        let destinations: [(demucs: Int, stem: Stem)] = [(0, .drums), (1, .bass), (3, .vocals)]
        let tolerance: Float = 2.5 // LSB: float rounding in PyTorch's output plus the rounding to Int16
        for (demucs, stem) in destinations {
            for channel in 0..<2 {
                for (p, position) in positions.enumerated() {
                    let expected = values[(demucs * 2 + channel) * positions.count + p] * PCM16Stereo.stemHeadroom * 32767
                    let actual = Float(stems[stem.rawValue].data[position * 2 + channel])
                    XCTAssertEqual(actual, expected, accuracy: tolerance, "\(stem) channel \(channel) at \(position)")
                }
            }
        }
    }

    func testLongTrackMatchesApplyModel() throws {
        try checkAgainstApplyModel(
            frames: StemFixtures.longFrames, positions: StemFixtures.longPositions, values: StemFixtures.longValues,
            mean: StemFixtures.longMean, std: StemFixtures.longStd, segments: 4
        )
    }

    func testTrackShorterThanASegmentMatchesApplyModel() throws {
        try checkAgainstApplyModel(
            frames: StemFixtures.shortFrames, positions: StemFixtures.shortPositions, values: StemFixtures.shortValues,
            mean: StemFixtures.shortMean, std: StemFixtures.shortStd, segments: 1
        )
    }

    func testStemsSumBackToTheMixExactly() throws {
        let source = Signals.pcm(400_000)
        let stems = try separate(source)
        for j in 0..<(source.frames * 2) {
            let sum = stems.reduce(Int32(0)) { $0 + Int32($1.data[j]) }
            // Half of the mix sample, rounded: the stems are stored at half level.
            let target = Int32((Float(source.data[j]) * 0.5).rounded())
            if sum != target {
                XCTFail("sample \(j): \(sum) vs \(target)")
                return
            }
        }
    }

    func testProgressAndCancellation() throws {
        let source = Signals.pcm(900_000)
        var reported: [Double] = []
        let stems = try HTDemucsPipeline(network: FakeNetwork()).separate(
            source, progress: { reported.append($0) }, isCancelled: { false }
        )
        XCTAssertEqual(stems.count, 4)
        XCTAssertEqual(reported.first, 0)
        XCTAssertEqual(reported.last, 1)
        XCTAssertEqual(reported, reported.sorted())
        XCTAssertGreaterThan(reported.count, 2)

        let network = FakeNetwork()
        var cancelled = false
        network.onPredict = { cancelled = true }
        XCTAssertThrowsError(
            try HTDemucsPipeline(network: network).separate(source, progress: { _ in }, isCancelled: { cancelled })
        ) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(network.predictions, 1)
    }

    func testEdgeCaseLengths() throws {
        XCTAssertEqual(try separate(PCM16Stereo(frames: 0))[0].frames, 0)
        let one = PCM16Stereo(left: [0.25], right: [-0.25])
        XCTAssertEqual(try separate(one)[0].frames, 1)
        // Exactly one segment, and exactly one stride so that the last chunk has a single sample's overrun.
        XCTAssertEqual(try separate(Signals.pcm(HTDemucsPipeline.segment)).first?.frames, HTDemucsPipeline.segment)
        let network = FakeNetwork()
        XCTAssertEqual(try separate(Signals.pcm(HTDemucsPipeline.stride + 1), network: network).first?.frames, HTDemucsPipeline.stride + 1)
        XCTAssertEqual(network.predictions, 2)
    }

    func testSilenceStaysSilentAndFinite() throws {
        let stems = try separate(PCM16Stereo(frames: 30_000))
        for stem in stems {
            XCTAssertTrue((0..<60_000).allSatisfy { stem.data[$0] == 0 })
        }
    }

    func testNotANumberIsAnErrorNotACrash() {
        let network = FakeNetwork()
        network.poison = true
        XCTAssertThrowsError(try separate(Signals.pcm(50_000), network: network)) {
            guard case StemSeparationError.invalidModelOutput = $0 else { return XCTFail("\($0)") }
        }
    }

    func testFrequencySplitterHasTheSameProgressAndCancellation() throws {
        let source = Signals.pcm(300_000)
        var reported: [Double] = []
        let stems = try FrequencySplitSeparator().separate(source, progress: { reported.append($0) }, isCancelled: { false })
        XCTAssertEqual(stems.count, 4)
        XCTAssertEqual(reported.first, 0)
        XCTAssertEqual(reported.last, 1)
        XCTAssertThrowsError(
            try FrequencySplitSeparator().separate(source, progress: { _ in }, isCancelled: { true })
        ) { XCTAssertTrue($0 is CancellationError) }
    }
}

final class StemModelHostTests: XCTestCase {
    private enum Failure: Error { case gpu, cpu }

    private struct Run {
        var loads: [MLComputeUnits] = []
        var predictions: [MLComputeUnits] = []
    }

    private final class Harness {
        var run = Run()
        var gpuLoadFails = false
        var gpuPredictionFails = false
        var cpuFails = false

        lazy var host = StemModelHost(preferredUnits: .cpuAndGPU) { [unowned self] units in
            self.run.loads.append(units)
            if units != .cpuOnly, self.gpuLoadFails { throw Failure.gpu }
            return { [unowned self] _ in
                self.run.predictions.append(units)
                if units == .cpuOnly, self.cpuFails { throw Failure.cpu }
                if units != .cpuOnly, self.gpuPredictionFails { throw Failure.gpu }
                return try Harness.outputs()
            }
        }

        static func outputs() throws -> MLFeatureProvider {
            let array = try MLMultiArray(shape: [1], dataType: .float32)
            return try MLDictionaryFeatureProvider(dictionary: ["spec_out": array, "time_out": array])
        }

        func predict() throws {
            let array = try MLMultiArray(shape: [1], dataType: .float32)
            _ = try host.predict(mix: array, spec: array)
        }
    }

    func testLoadsOnceAndOnlyWhenFirstNeeded() throws {
        let harness = Harness()
        harness.host.jobStarted()
        XCTAssertEqual(harness.run.loads, [])
        try harness.predict()
        try harness.predict()
        harness.host.jobFinished()
        XCTAssertEqual(harness.run.loads, [.cpuAndGPU])
        XCTAssertEqual(harness.run.predictions, [.cpuAndGPU, .cpuAndGPU])
    }

    /// As when the app goes to the background partway through a track.
    func testFailedGPUPredictionRetriesOnCPUForTheRestOfTheJob() throws {
        let harness = Harness()
        harness.host.jobStarted()
        try harness.predict()
        harness.gpuPredictionFails = true
        try harness.predict()
        harness.gpuPredictionFails = false
        try harness.predict()
        XCTAssertEqual(harness.run.predictions, [.cpuAndGPU, .cpuAndGPU, .cpuOnly, .cpuOnly])
        harness.host.jobFinished()

        // Back in the foreground, the next job tries the GPU again.
        harness.host.jobStarted()
        try harness.predict()
        harness.host.jobFinished()
        XCTAssertEqual(harness.run.predictions.last, .cpuAndGPU)
        XCTAssertEqual(harness.run.loads, [.cpuAndGPU, .cpuOnly, .cpuAndGPU])
    }

    func testFailedGPULoadFallsBackToCPU() throws {
        let harness = Harness()
        harness.gpuLoadFails = true
        harness.host.jobStarted()
        try harness.predict()
        harness.host.jobFinished()
        XCTAssertEqual(harness.run.loads, [.cpuAndGPU, .cpuOnly])
        XCTAssertEqual(harness.run.predictions, [.cpuOnly])
    }

    func testFailureOnTheCPUIsReported() {
        let harness = Harness()
        harness.gpuPredictionFails = true
        harness.cpuFails = true
        harness.host.jobStarted()
        XCTAssertThrowsError(try harness.predict()) {
            guard case Failure.cpu = $0 else { return XCTFail("\($0)") }
        }
        harness.host.jobFinished()
    }

    func testReleaseDropsTheModelAndTheNextJobLoadsItAgain() throws {
        let harness = Harness()
        harness.host.jobStarted()
        try harness.predict()
        harness.host.jobFinished()
        harness.host.release()
        harness.host.jobStarted()
        try harness.predict()
        harness.host.jobFinished()
        XCTAssertEqual(harness.run.loads, [.cpuAndGPU, .cpuAndGPU])
    }

    func testReleaseWaitsForTheRunningJob() throws {
        let harness = Harness()
        harness.host.jobStarted()
        try harness.predict()
        harness.host.release()
        try harness.predict()
        XCTAssertEqual(harness.run.loads, [.cpuAndGPU], "a running job keeps its model")
        harness.host.jobFinished()

        harness.host.jobStarted()
        try harness.predict()
        harness.host.jobFinished()
        XCTAssertEqual(harness.run.loads, [.cpuAndGPU, .cpuAndGPU], "released once the job ended")
    }

    func testPreloadSparesTheFirstJobTheLoad() throws {
        let harness = Harness()
        try harness.host.preload()
        XCTAssertEqual(harness.run.loads, [.cpuAndGPU])
        harness.host.jobStarted()
        try harness.predict()
        harness.host.jobFinished()
        XCTAssertEqual(harness.run.loads, [.cpuAndGPU])
    }
}

final class StemCacheTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("StemCacheTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func stems(frames: Int, seed: Int16 = 1) -> [PCM16Stereo] {
        (0..<4).map { stem in
            let pcm = PCM16Stereo(frames: frames)
            for i in 0..<(frames * 2) { pcm.data[i] = Int16(truncatingIfNeeded: i) &* seed &+ Int16(stem) }
            return pcm
        }
    }

    private func file(_ id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("stems")
    }

    private func assertEqual(_ a: [PCM16Stereo], _ b: [PCM16Stereo], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.count, b.count, file: file, line: line)
        for (x, y) in zip(a, b) {
            XCTAssertEqual(x.frames, y.frames, file: file, line: line)
            XCTAssertEqual(memcmp(x.data, y.data, x.frames * 4), 0, file: file, line: line)
        }
    }

    func testRoundTrip() throws {
        let cache = StemCache(directory: directory)
        let id = UUID()
        XCTAssertNil(cache.load(id))
        let original = stems(frames: 5000)
        try cache.store(id, stems: original)
        assertEqual(try XCTUnwrap(cache.load(id)), original)
        XCTAssertEqual(cache.storedBytes, 40 + 4 * 5000 * 4)
    }

    func testEmptyStems() throws {
        let cache = StemCache(directory: directory)
        let id = UUID()
        try cache.store(id, stems: stems(frames: 0))
        XCTAssertEqual(try XCTUnwrap(cache.load(id))[0].frames, 0)
    }

    func testStoreReplaces() throws {
        let cache = StemCache(directory: directory)
        let id = UUID()
        try cache.store(id, stems: stems(frames: 100))
        let replacement = stems(frames: 200, seed: 3)
        try cache.store(id, stems: replacement)
        assertEqual(try XCTUnwrap(cache.load(id)), replacement)
    }

    func testTruncatedFileIsAMissAndDeleted() throws {
        let cache = StemCache(directory: directory)
        for keep in [0, 10, 39, 40, 41, 40 + 1000, 40 + 4 * 5000 * 4 - 1] {
            let id = UUID()
            try cache.store(id, stems: stems(frames: 5000))
            let handle = try FileHandle(forWritingTo: file(id))
            try handle.truncate(atOffset: UInt64(keep))
            try handle.close()
            XCTAssertNil(cache.load(id), "kept \(keep) bytes")
            XCTAssertFalse(FileManager.default.fileExists(atPath: file(id).path), "kept \(keep) bytes")
        }
    }

    func testExtraBytesAreAMissAndDeleted() throws {
        let cache = StemCache(directory: directory)
        let id = UUID()
        try cache.store(id, stems: stems(frames: 100))
        let handle = try FileHandle(forWritingTo: file(id))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([1, 2]))
        try handle.close()
        XCTAssertNil(cache.load(id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file(id).path))
    }

    /// Every header field, including a changed format version, invalidates the file.
    func testChangedHeaderIsAMissAndDeleted() throws {
        let cache = StemCache(directory: directory)
        for offset in [0, 8, 12, 16, 24, 28, 32] {
            let id = UUID()
            try cache.store(id, stems: stems(frames: 100))
            var bytes = try Data(contentsOf: file(id))
            bytes[offset] ^= 0x01
            try bytes.write(to: file(id))
            XCTAssertNil(cache.load(id), "offset \(offset)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: file(id).path), "offset \(offset)")
        }
    }

    func testLeastRecentlyUsedGoesFirst() throws {
        let frames = 1000
        let entry = Int64(40 + 4 * frames * 4)
        let cache = StemCache(directory: directory, capacity: 3 * entry)
        let ids = (0..<3).map { _ in UUID() }
        for (age, id) in ids.enumerated() {
            try cache.store(id, stems: stems(frames: frames))
            // Oldest first, spaced so the order doesn't hinge on timestamp resolution.
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSinceNow: Double(age - 10) * 60)],
                ofItemAtPath: file(id).path
            )
        }
        // Using the oldest makes the second one the least recently used.
        XCTAssertNotNil(cache.load(ids[0]))

        let newest = UUID()
        try cache.store(newest, stems: stems(frames: frames))
        XCTAssertNil(cache.load(ids[1]))
        XCTAssertNotNil(cache.load(ids[0]))
        XCTAssertNotNil(cache.load(ids[2]))
        XCTAssertNotNil(cache.load(newest))
        XCTAssertLessThanOrEqual(cache.storedBytes, 3 * entry)
    }

    func testAnEntryOverTheCapacityIsStillKept() throws {
        let cache = StemCache(directory: directory, capacity: 100)
        let old = UUID(), new = UUID()
        try cache.store(old, stems: stems(frames: 100))
        try cache.store(new, stems: stems(frames: 100))
        XCTAssertNil(cache.load(old))
        XCTAssertNotNil(cache.load(new))
    }

    func testStaleTemporaryFilesAreCleanedUp() throws {
        let cache = StemCache(directory: directory)
        try cache.store(UUID(), stems: stems(frames: 10))
        let stale = directory.appendingPathComponent("leftover.tmp")
        let fresh = directory.appendingPathComponent("inprogress.tmp")
        try Data([1]).write(to: stale)
        try Data([1]).write(to: fresh)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -7200)], ofItemAtPath: stale.path)
        try cache.store(UUID(), stems: stems(frames: 10))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
    }

    func testRejectsMalformedInput() {
        let cache = StemCache(directory: directory)
        XCTAssertThrowsError(try cache.store(UUID(), stems: Array(stems(frames: 10).prefix(3))))
        XCTAssertThrowsError(try cache.store(UUID(), stems: stems(frames: 10).dropLast() + [PCM16Stereo(frames: 11)]))
    }

    func testDefaultLocationIsCaches() {
        XCTAssertTrue(StemCache().directory.path.contains("/Caches/"))
        XCTAssertEqual(StemCache.defaultCapacity, 8 * 1024 * 1024 * 1024)
    }
}

/// Opt-in: runs the real model, on the CPU in the simulator. It needs `Cheeks/Stems.mlpackage` in
/// the build. `CHEEKS_STEM_INPUT` optionally names a raw stereo Int16 file and `CHEEKS_STEM_OUTPUT`
/// a folder for the four stems as raw Int16 (`<name>.pcm`), for scoring with `tools/stems/validate.py`.
///
///     TEST_RUNNER_CHEEKS_STEM_MODEL=1 xcodebuild test ... -only-testing:CheeksTests/StemModelTests
final class StemModelTests: XCTestCase {
    func testRealModelOnAClip() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["CHEEKS_STEM_MODEL"] != nil else {
            throw XCTSkip("set TEST_RUNNER_CHEEKS_STEM_MODEL=1 to run")
        }
        XCTAssertNotNil(CoreMLStemSeparator.bundledModelURL, "build with Cheeks/Stems.mlpackage present")
        let separator = StemSeparation.makeSeparator()
        XCTAssertTrue(separator.isMachineLearning)

        let source: PCM16Stereo
        if let path = environment["CHEEKS_STEM_INPUT"] {
            let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
            source = PCM16Stereo(frames: bytes.count / 4)
            bytes.withUnsafeBytes { raw in
                _ = memcpy(source.data, raw.baseAddress!, source.frames * 4)
            }
        } else {
            source = Synth.track(bpm: 126, firstBeat: 0.2, seconds: 12, chords: Synth.aMinor)
        }

        var reported: [Double] = []
        let start = Date()
        let stems = try separator.separate(source, progress: { reported.append($0) }, isCancelled: { false })
        let elapsed = Date().timeIntervalSince(start)
        print("STEMS: \(source.duration) s of audio in \(elapsed) s on the CPU, \(reported.count - 1) segments")

        XCTAssertEqual(stems.count, 4)
        XCTAssertEqual(reported.last, 1)

        var energy = [Double](repeating: 0, count: 4)
        var worst: Int32 = 0
        for j in 0..<(source.frames * 2) {
            var sum: Int32 = 0
            for (index, stem) in stems.enumerated() {
                let value = stem.data[j]
                sum += Int32(value)
                energy[index] += Double(value) * Double(value)
            }
            worst = max(worst, abs(sum - Int32((Float(source.data[j]) * 0.5).rounded())))
        }
        print("STEMS: energy per stem (vocals, melody, bass, drums): \(energy)")
        XCTAssertEqual(worst, 0, "stems must sum back to the mix")
        XCTAssertGreaterThan(energy.reduce(0, +), 0)

        if let folder = environment["CHEEKS_STEM_OUTPUT"] {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            for stem in Stem.allCases {
                let data = Data(bytes: stems[stem.rawValue].data, count: source.frames * 4)
                try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(stem).pcm"))
            }
        }
        StemSeparation.releaseModel()
    }
}
