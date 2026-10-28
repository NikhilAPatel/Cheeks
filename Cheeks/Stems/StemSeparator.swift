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

    var color: Color {
        switch self {
        case .vocals: Color(red: 0.95, green: 0.3, blue: 0.55)
        case .melody: Color(red: 0.3, green: 0.85, blue: 0.6)
        case .bass: Color(red: 0.35, green: 0.5, blue: 1.0)
        case .drums: Color(red: 1.0, green: 0.75, blue: 0.2)
        }
    }
}

/// Splits a track into four stems in `Stem.allCases` order.
protocol StemSeparator {
    var name: String { get }
    /// True when the result is a real source separation rather than a frequency approximation.
    var isMachineLearning: Bool { get }
    func separate(_ audio: DecodedAudio) throws -> [PCM16Stereo]
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

    func separate(_ audio: DecodedAudio) throws -> [PCM16Stereo] {
        let sr = audio.sampleRate
        let n = audio.frames

        let bassL = Biquad.cascade(.lowpass(140, sampleRate: sr), audio.left)
        let bassR = Biquad.cascade(.lowpass(140, sampleRate: sr), audio.right)
        let hatsL = Biquad.cascade(.highpass(6000, sampleRate: sr), audio.left)
        let hatsR = Biquad.cascade(.highpass(6000, sampleRate: sr), audio.right)

        // Vocals: centre (mid) channel of what remains, band-limited to 250 Hz – 5 kHz.
        var mid = [Float](repeating: 0, count: n)
        for i in 0..<n {
            mid[i] = ((audio.left[i] - bassL[i] - hatsL[i]) + (audio.right[i] - bassR[i] - hatsR[i])) * 0.5
        }
        let vocals = Biquad.cascade(.lowpass(5000, sampleRate: sr), Biquad.cascade(.highpass(250, sampleRate: sr), mid))

        var melodyL = [Float](repeating: 0, count: n)
        var melodyR = [Float](repeating: 0, count: n)
        for i in 0..<n {
            melodyL[i] = audio.left[i] - bassL[i] - hatsL[i] - vocals[i]
            melodyR[i] = audio.right[i] - bassR[i] - hatsR[i] - vocals[i]
        }

        return [
            PCM16Stereo(left: vocals, right: vocals),
            PCM16Stereo(left: melodyL, right: melodyR),
            PCM16Stereo(left: bassL, right: bassR),
            PCM16Stereo(left: hatsL, right: hatsR),
        ]
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

    func separate(_ audio: DecodedAudio) throws -> [PCM16Stereo] {
        let n = audio.frames
        // Demucs order → our Stem order (vocals, melody, bass, drums)
        let demucsIndex = [3, 2, 1, 0]
        var outL = Array(repeating: [Float](repeating: 0, count: n), count: 4)
        var outR = Array(repeating: [Float](repeating: 0, count: n), count: 4)

        var start = 0
        while start < n {
            let length = min(chunk, n - start)
            let input = try MLMultiArray(shape: [1, 2, NSNumber(value: chunk)], dataType: .float32)
            let inStrides = input.strides.map(\.intValue)
            let inPtr = input.dataPointer.assumingMemoryBound(to: Float.self)
            for i in 0..<chunk {
                inPtr[i * inStrides[2]] = i < length ? audio.left[start + i] : 0
                inPtr[inStrides[1] + i * inStrides[2]] = i < length ? audio.right[start + i] : 0
            }

            let result = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["audio": input]))
            guard let stems = result.featureValue(for: "stems")?.multiArrayValue, stems.dataType == .float32 else {
                throw CocoaError(.featureUnsupported)
            }
            let s = stems.strides.map(\.intValue)
            let ptr = stems.dataPointer.assumingMemoryBound(to: Float.self)
            for stem in 0..<4 {
                let base = demucsIndex[stem] * s[1]
                for i in 0..<length {
                    outL[stem][start + i] = ptr[base + i * s[3]]
                    outR[stem][start + i] = ptr[base + s[2] + i * s[3]]
                }
            }
            start += length
        }
        return (0..<4).map { PCM16Stereo(left: outL[$0], right: outR[$0]) }
    }
}
