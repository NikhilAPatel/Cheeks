import AVFoundation
import XCTest
@testable import Cheeks

/// Measures what loading a 6-minute track and splitting it into stems adds to the app's memory,
/// through the same decode → analyse → separate path a deck uses. Opt-in, as it takes a while:
///
///     TEST_RUNNER_CHEEKS_MEMORY=1 xcodebuild test … -only-testing:CheeksTests/MemoryFootprint
final class MemoryFootprint: XCTestCase {
    func testSixMinuteTrackAndStems() throws {
        guard ProcessInfo.processInfo.environment["CHEEKS_MEMORY"] != nil else {
            throw XCTSkip("Set TEST_RUNNER_CHEEKS_MEMORY=1 to measure memory")
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "six-minutes.m4a")
        try writeAAC(seconds: 360, to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let base = Self.footprint()
        var pcm: PCM16Stereo? = try AudioDecoder.decode(url: url, sampleRate: AudioConfig.sampleRate)
        let decoded = Self.footprint()
        let analysis = TrackAnalyzer.analyze(pcm!)
        let analysed = Self.footprint()
        var stems: [PCM16Stereo]? = try FrequencySplitSeparator().separate(pcm!)
        let separated = Self.footprint()
        let peak = Self.peakFootprint()

        func mb(_ bytes: Int64) -> String { String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        print("MEMORY: decoded 6-min track: +\(mb(decoded - base)) (PCM is \(mb(Int64(pcm!.frames * 4))))")
        print("MEMORY: after analysis: +\(mb(analysed - base)); waveform bins \(analysis.waveform.count)")
        print("MEMORY: four stems: +\(mb(separated - analysed))")
        print("MEMORY: process peak: \(mb(peak)), now \(mb(separated))")

        XCTAssertEqual(stems?.count, 4)
        stems = nil
        pcm = nil
    }

    /// A 6-minute stereo AAC file written in small blocks, so making it doesn't skew the numbers.
    private func writeAAC(seconds: Double, to url: URL) throws {
        let sr = AudioConfig.sampleRate
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sr,
                                       AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 256_000]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let block: AVAudioFrameCount = 8192
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: block))
        let total = Int(seconds * sr)
        var written = 0
        while written < total {
            let n = min(Int(block), total - written)
            for i in 0..<n {
                let t = Double(written + i) / sr
                let beat = t.truncatingRemainder(dividingBy: 60 / 124.0)
                let v = 0.6 * sin(2 * .pi * 55 * t) * exp(-beat * 8) + 0.2 * sin(2 * .pi * 440 * t)
                buffer.floatChannelData![0][i] = Float(v)
                buffer.floatChannelData![1][i] = Float(v)
            }
            buffer.frameLength = AVAudioFrameCount(n)
            try file.write(from: buffer)
            written += n
        }
    }

    private static func vmInfo() -> task_vm_info_data_t {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return info
    }

    static func footprint() -> Int64 { Int64(vmInfo().phys_footprint) }
    static func peakFootprint() -> Int64 { Int64(vmInfo().ledger_phys_footprint_peak) }
}
