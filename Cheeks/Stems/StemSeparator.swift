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

/// Splits a track into four stems in `Stem.allCases` order, stored at `PCM16Stereo.stemHeadroom`.
/// The four always sum back to the original.
protocol StemSeparator {
    var name: String { get }
    /// True when the result is a real source separation rather than a frequency approximation.
    var isMachineLearning: Bool { get }
    /// Blocks until done, so call it off the main thread. `progress` gets 0...1 on the calling
    /// thread. When `isCancelled` turns true, this throws `CancellationError`.
    func separate(
        _ source: PCM16Stereo,
        progress: @escaping (Double) -> Void,
        isCancelled: @escaping () -> Bool
    ) throws -> [PCM16Stereo]
}

extension StemSeparator {
    func separate(_ source: PCM16Stereo) throws -> [PCM16Stereo] {
        try separate(source, progress: { _ in }, isCancelled: { false })
    }
}

enum StemSeparation {
    /// The bundled model's separator. There's one, so that everything shares the loaded model.
    private static let bundled: CoreMLStemSeparator? = CoreMLStemSeparator.bundledModelURL.map {
        CoreMLStemSeparator(modelURL: $0)
    }

    /// The Core ML separator if the app was built with `Stems.mlpackage`, otherwise the frequency
    /// splitter. Loading the model waits until the first separation.
    static func makeSeparator() -> StemSeparator {
        bundled ?? FrequencySplitSeparator()
    }

    /// Frees the model's memory, for when no separation is pending. A running job keeps it until
    /// it ends. The next separation loads it again.
    static func releaseModel() {
        bundled?.releaseModel()
    }
}

/// Works with no model: bass = lows, drums = cymbal/hat highs, vocals = the centre of the
/// vocal band, instruments = everything left over. The four always sum back to the original,
/// so all-on sounds identical to the track; isolation is approximate.
struct FrequencySplitSeparator: StemSeparator {
    let name = "Frequency split"
    let isMachineLearning = false

    func separate(
        _ source: PCM16Stereo,
        progress: @escaping (Double) -> Void,
        isCancelled: @escaping () -> Bool
    ) throws -> [PCM16Stereo] {
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

        // About a second of audio between checks.
        let checkInterval = 1 << 16
        progress(0)
        for i in 0..<n {
            if i & (checkInterval - 1) == 0, i > 0 {
                if isCancelled() { throw CancellationError() }
                progress(Double(i) / Double(n))
            }
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
        progress(1)
        return stems
    }
}
