import AVFoundation

enum AudioConfig {
    /// Everything internal runs at 44.1 kHz; AVAudioEngine converts to the hardware rate at the output.
    static let sampleRate: Double = 44_100
}

/// Whole-track stereo audio as Float32, used for analysis and stem separation.
struct DecodedAudio {
    var left: [Float]
    var right: [Float]
    var sampleRate: Double
    var frames: Int { left.count }
}

/// Interleaved 16-bit stereo PCM kept in memory for the realtime renderer.
/// 16-bit halves memory use, which matters once a track is split into four stems.
final class PCM16Stereo {
    let frames: Int
    let data: UnsafeMutablePointer<Int16>

    init(frames: Int) {
        self.frames = frames
        data = .allocate(capacity: max(frames, 1) * 2)
        data.initialize(repeating: 0, count: max(frames, 1) * 2)
    }

    convenience init(left: [Float], right: [Float]) {
        self.init(frames: left.count)
        left.withUnsafeBufferPointer { l in
            right.withUnsafeBufferPointer { r in
                for i in 0..<frames {
                    data[i * 2] = Self.toInt16(l[i])
                    data[i * 2 + 1] = Self.toInt16(r[i])
                }
            }
        }
    }

    deinit { data.deallocate() }

    /// Stems are stored at half level: filtering shifts phase, so an individual stem can peak
    /// well above the original track. The renderer applies the gain back when mixing stems.
    static let stemHeadroom: Float = 0.5

    @inline(__always) static func toInt16(_ x: Float) -> Int16 {
        Int16(max(-1, min(1, x)) * 32767)
    }
}

enum AudioDecoder {
    enum DecodeError: Error { case unsupportedFormat }

    /// Decodes any format AVFoundation reads (mp3, aac, wav, aiff, flac, alac) to stereo at `sampleRate`.
    static func decode(url: URL, sampleRate: Double) throws -> DecodedAudio {
        let file = try AVAudioFile(forReading: url)
        let inFormat = file.processingFormat
        let channels: AVAudioChannelCount = inFormat.channelCount >= 2 ? 2 : 1
        guard let outFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw DecodeError.unsupportedFormat
        }
        if inFormat.channelCount > 2 { converter.downmix = true }

        let inCapacity: AVAudioFrameCount = 32_768
        let ratio = sampleRate / inFormat.sampleRate
        guard let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: inCapacity),
              let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: AVAudioFrameCount(Double(inCapacity) * ratio) + 4096) else {
            throw DecodeError.unsupportedFormat
        }

        let expected = Int(Double(file.length) * ratio) + 4096
        var left: [Float] = []
        var right: [Float] = []
        left.reserveCapacity(expected)
        right.reserveCapacity(expected)

        var reachedEnd = false
        while true {
            outBuffer.frameLength = 0
            var conversionError: NSError?
            let status = converter.convert(to: outBuffer, error: &conversionError) { _, inputStatus in
                if reachedEnd {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                do {
                    try file.read(into: inBuffer, frameCount: inCapacity)
                } catch {
                    reachedEnd = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                if inBuffer.frameLength == 0 {
                    reachedEnd = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                inputStatus.pointee = .haveData
                return inBuffer
            }
            if let conversionError { throw conversionError }

            let n = Int(outBuffer.frameLength)
            if n > 0, let channelData = outBuffer.floatChannelData {
                left.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: n))
                right.append(contentsOf: UnsafeBufferPointer(start: channelData[channels == 2 ? 1 : 0], count: n))
            }
            if status == .endOfStream || status == .error || (n == 0 && reachedEnd) { break }
        }
        return DecodedAudio(left: left, right: right, sampleRate: sampleRate)
    }
}
