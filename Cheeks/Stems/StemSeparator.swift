import CoreML
import SwiftUI

enum Stem: Int, CaseIterable, Identifiable {
    case vocals, melody, bass, drums
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .vocals: "VOCAL"
        case .melody: "INST"
        case .bass: "BASS"
        case .drums: "DRUMS"
        }
    }

    /// One or two letters, for tight spaces.
    var short: String {
        switch self {
        case .vocals: "V"
        case .melody: "I"
        case .bass: "B"
        case .drums: "D"
        }
    }

    var symbol: String {
        switch self {
        case .vocals: "mic.fill"
        case .melody: "pianokeys"
        case .bass: "speaker.wave.2.fill"
        case .drums: "circle.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .vocals: Color(red: 0.98, green: 0.26, blue: 0.56)
        case .melody: Color(red: 0.16, green: 0.86, blue: 0.62)
        case .bass: Color(red: 0.24, green: 0.48, blue: 1.0)
        case .drums: Color(red: 1.0, green: 0.74, blue: 0.14)
        }
    }
}

/// Splits a track into four stems in `Stem.allCases` order.
protocol StemSeparator {
    var name: String { get }
    /// True when the result is a real source separation rather than a frequency approximation.
    var isMachineLearning: Bool { get }
    func separate(_ source: PCM16Stereo) throws -> [PCM16Stereo]
}

enum StemSeparation {
    /// Uses a bundled Core ML model if one is present, otherwise the frequency splitter.
    static func makeSeparator() -> StemSeparator {
        CoreMLStemSeparator.load() ?? FrequencySplitSeparator()
    }
}

/// Works with no model: bass = lows, drums = cymbal/hat highs, vocals = the centre of the
/// vocal band, instruments = everything left over. The four always sum back to the original,
/// so all-on sounds identical to the track; isolation is approximate.
struct FrequencySplitSeparator: StemSeparator {
    let name = "Frequency split"
    let isMachineLearning = false

    func separate(_ source: PCM16Stereo) throws -> [PCM16Stereo] {
        let sr = AudioConfig.sampleRate
        let n = source.frames
        let stems = (0..<4).map { _ in PCM16Stereo(frames: n) }
        let vocals = stems[Stem.vocals.rawValue].data
        let melody = stems[Stem.melody.rawValue].data
        let bass = stems[Stem.bass.rawValue].data
        let drums = stems[Stem.drums.rawValue].data

        // 4th-order filters as two cascaded biquads each, run in a single streaming pass
        // so no full-length intermediate copies are needed.
        let lp = Biquad.lowpass(140, sampleRate: sr), hp = Biquad.highpass(6000, sampleRate: sr)
        var bassL = (lp, lp), bassR = (lp, lp), hatsL = (hp, hp), hatsR = (hp, hp)
        let vHP = Biquad.highpass(250, sampleRate: sr), vLP = Biquad.lowpass(5000, sampleRate: sr)
        var voice = (vHP, vHP, vLP, vLP)

        for i in 0..<n {
            let l = source.left(i), r = source.right(i)
            let bl = bassL.1.process(bassL.0.process(l)), br = bassR.1.process(bassR.0.process(r))
            let hl = hatsL.1.process(hatsL.0.process(l)), hr = hatsR.1.process(hatsR.0.process(r))
            // Vocals: centre (mid) channel of what remains, band-limited to 250 Hz – 5 kHz.
            let mid = ((l - bl - hl) + (r - br - hr)) * 0.5
            let v = voice.3.process(voice.2.process(voice.1.process(voice.0.process(mid))))
            let j = i * 2
            let g = PCM16Stereo.stemHeadroom
            bass[j] = PCM16Stereo.toInt16(bl * g); bass[j + 1] = PCM16Stereo.toInt16(br * g)
            drums[j] = PCM16Stereo.toInt16(hl * g); drums[j + 1] = PCM16Stereo.toInt16(hr * g)
            vocals[j] = PCM16Stereo.toInt16(v * g); vocals[j + 1] = vocals[j]
            melody[j] = PCM16Stereo.toInt16((l - bl - hl - v) * g)
            melody[j + 1] = PCM16Stereo.toInt16((r - br - hr - v) * g)
        }
        return stems
    }
}

/// Runs a source-separation model (e.g. HT-Demucs converted with coremltools) bundled as `Stems.mlpackage`.
///
/// Expected interface (see README):
///   input  "audio": Float32 [1, 2, chunk]       stereo, 44.1 kHz
///   output "stems": Float32 [1, 4, 2, chunk]    order drums, bass, other, vocals (Demucs order)
struct CoreMLStemSeparator: StemSeparator {
    let name = "Core ML model"
    let isMachineLearning = true
    let model: MLModel
    let chunk: Int

    static func load() -> CoreMLStemSeparator? {
        guard let url = Bundle.main.url(forResource: "Stems", withExtension: "mlmodelc") else { return nil }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        guard let model = try? MLModel(contentsOf: url, configuration: config),
              let shape = model.modelDescription.inputDescriptionsByName["audio"]?.multiArrayConstraint?.shape,
              shape.count == 3 else { return nil }
        return CoreMLStemSeparator(model: model, chunk: shape[2].intValue)
    }

    func separate(_ source: PCM16Stereo) throws -> [PCM16Stereo] {
        let n = source.frames
        // Demucs order → our Stem order (vocals, melody, bass, drums)
        let demucsIndex = [3, 2, 1, 0]
        let outputs = (0..<4).map { _ in PCM16Stereo(frames: n) }

        var start = 0
        while start < n {
            let length = min(chunk, n - start)
            let input = try MLMultiArray(shape: [1, 2, NSNumber(value: chunk)], dataType: .float32)
            let inStrides = input.strides.map(\.intValue)
            let inPtr = input.dataPointer.assumingMemoryBound(to: Float.self)
            for i in 0..<chunk {
                inPtr[i * inStrides[2]] = i < length ? source.left(start + i) : 0
                inPtr[inStrides[1] + i * inStrides[2]] = i < length ? source.right(start + i) : 0
            }

            let result = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["audio": input]))
            guard let stems = result.featureValue(for: "stems")?.multiArrayValue, stems.dataType == .float32 else {
                throw CocoaError(.featureUnsupported)
            }
            let s = stems.strides.map(\.intValue)
            let ptr = stems.dataPointer.assumingMemoryBound(to: Float.self)
            for stem in 0..<4 {
                let base = demucsIndex[stem] * s[1]
                let out = outputs[stem].data
                for i in 0..<length {
                    out[(start + i) * 2] = PCM16Stereo.toInt16(ptr[base + i * s[3]] * PCM16Stereo.stemHeadroom)
                    out[(start + i) * 2 + 1] = PCM16Stereo.toInt16(ptr[base + s[2] + i * s[3]] * PCM16Stereo.stemHeadroom)
                }
            }
            start += length
        }
        return outputs
    }
}
