import AVFoundation

enum AudioConfig {
    /// Everything internal runs at 44.1 kHz; AVAudioEngine converts to the hardware rate at the output.
    static let sampleRate: Double = 44_100
    /// Longest track that can be split into stems (four extra copies of the audio in memory).
    static let maxStemSeconds: Double = 20 * 60
}

/// Interleaved 16-bit stereo PCM kept in memory for the realtime renderer.
/// 16-bit halves memory use, which matters once a track is split into four stems.
/// Tracks are decoded straight into this format so a full-length Float copy never exists.
final class PCM16Stereo {
    private(set) var frames: Int
    private(set) var data: UnsafeMutablePointer<Int16>
    private var capacity: Int

    init(frames: Int) {
        self.frames = frames
        capacity = max(frames, 1)
        data = .allocate(capacity: capacity * 2)
        data.initialize(repeating: 0, count: capacity * 2)
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

    @inline(__always) func left(_ i: Int) -> Float { Float(data[i * 2]) / 32767 }
    @inline(__always) func right(_ i: Int) -> Float { Float(data[i * 2 + 1]) / 32767 }

    var duration: Double { Double(frames) / AudioConfig.sampleRate }

    // MARK: Building (decoder only, before the buffer is handed to a renderer)

    fileprivate func append(left l: UnsafePointer<Float>, right r: UnsafePointer<Float>, count: Int) {
        if frames + count > capacity {
            let newCapacity = max(capacity * 3 / 2, frames + count)
            let grown = UnsafeMutablePointer<Int16>.allocate(capacity: newCapacity * 2)
            grown.initialize(from: data, count: frames * 2)
            data.deallocate()
            data = grown
            capacity = newCapacity
        }
        for i in 0..<count {
            data[(frames + i) * 2] = Self.toInt16(l[i])
            data[(frames + i) * 2 + 1] = Self.toInt16(r[i])
        }
        frames += count
    }

    fileprivate func resetForAppending(capacity expected: Int) {
        data.deallocate()
        capacity = max(expected, 1)
        data = .allocate(capacity: capacity * 2)
        frames = 0
    }
}

enum AudioDecoder {
    enum DecodeError: Error { case unsupportedFormat }

    /// Decodes any format AVFoundation reads (mp3, aac, wav, aiff, flac, alac) to 16-bit stereo at `sampleRate`.
    static func decode(url: URL, sampleRate: Double) throws -> PCM16Stereo {
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

        let pcm = PCM16Stereo(frames: 0)
        pcm.resetForAppending(capacity: Int(Double(file.length) * ratio) + 4096)

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
                pcm.append(left: channelData[0], right: channelData[channels == 2 ? 1 : 0], count: n)
            }
            if status == .endOfStream || status == .error || (n == 0 && reachedEnd) { break }
        }
        return pcm
    }
}
