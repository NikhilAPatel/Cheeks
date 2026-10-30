import CoreML
import Foundation

/// HT-Demucs on Core ML. The network is `Stems.mlpackage`, built by `tools/stems/convert.py` and
/// compiled by Xcode to `Stems.mlmodelc` in the app bundle; the STFT and the segment loop are in
/// `DemucsSTFT` and `HTDemucsPipeline`.
///
/// The model is loaded when the first job needs it and stays loaded until `releaseModel()`.
/// Jobs are safe to run concurrently; their predictions take turns, so that two decks loading at
/// once cost the memory of one prediction.
final class CoreMLStemSeparator: StemSeparator {
    let name = "HT-Demucs"
    let isMachineLearning = true

    /// The GPU in the foreground. Not `.all`, which would bring in the Neural Engine: on an M1 Pro
    /// it comes back with audio that's wrong (see tools/stems/README.md). The simulator has only the CPU.
    static var defaultComputeUnits: MLComputeUnits {
        #if targetEnvironment(simulator)
        return .cpuOnly
        #else
        return .cpuAndGPU
        #endif
    }

    static var bundledModelURL: URL? {
        Bundle.main.url(forResource: "Stems", withExtension: "mlmodelc")
    }

    private let host: StemModelHost

    init(modelURL: URL, computeUnits: MLComputeUnits = CoreMLStemSeparator.defaultComputeUnits) {
        host = StemModelHost(preferredUnits: computeUnits) { units in
            let configuration = MLModelConfiguration()
            configuration.computeUnits = units
            let model = try MLModel(contentsOf: modelURL, configuration: configuration)
            guard Self.hasExpectedInterface(model) else { throw StemSeparationError.modelMismatch }
            return { try model.prediction(from: $0) }
        }
    }

    func separate(
        _ source: PCM16Stereo,
        progress: @escaping (Double) -> Void,
        isCancelled: @escaping () -> Bool
    ) throws -> [PCM16Stereo] {
        host.jobStarted()
        defer { host.jobFinished() }
        return try HTDemucsPipeline(network: host).separate(source, progress: progress, isCancelled: isCancelled)
    }

    /// Frees the model (several hundred MB once loaded). With a job running, this takes effect when
    /// the last job ends; the next job loads it again.
    func releaseModel() {
        host.release()
    }

    /// Loads the model if needed, so the first job doesn't pay for it, and returns the time that
    /// took in seconds.
    @discardableResult
    func preload() throws -> TimeInterval {
        try host.preload()
    }

    /// The package is git-ignored and copied in by hand, so it could be left over from an earlier
    /// conversion. Catch that here, not with a crash partway through a track.
    private static func hasExpectedInterface(_ model: MLModel) -> Bool {
        let inputs = model.modelDescription.inputDescriptionsByName
        func shape(_ name: String) -> [Int]? {
            inputs[name]?.multiArrayConstraint?.shape.map(\.intValue)
        }
        return shape("mix") == [1, 2, HTDemucsPipeline.segment]
            && shape("spec") == [1, 4, DemucsSTFT.bins, 336]
            && model.modelDescription.outputDescriptionsByName["spec_out"] != nil
            && model.modelDescription.outputDescriptionsByName["time_out"] != nil
    }
}

/// Holds the loaded model and decides when to load it, release it, and fall back from the GPU to
/// the CPU. The loading itself is passed in, so all of this can be tested without a model.
final class StemModelHost: HTDemucsNetwork {
    typealias Prediction = (MLFeatureProvider) throws -> MLFeatureProvider
    typealias Loader = (MLComputeUnits) throws -> Prediction

    private let preferredUnits: MLComputeUnits
    private let loader: Loader
    private let lock = NSLock()
    private var prediction: Prediction?
    private var units: MLComputeUnits
    private var jobs = 0
    private var releaseWhenIdle = false

    init(preferredUnits: MLComputeUnits, loader: @escaping Loader) {
        self.preferredUnits = preferredUnits
        self.loader = loader
        units = preferredUnits
    }

    func jobStarted() {
        lock.lock()
        defer { lock.unlock() }
        jobs += 1
        releaseWhenIdle = false
        // An earlier job may have fallen back to the CPU. Try the preferred units again.
        if jobs == 1, units != preferredUnits {
            units = preferredUnits
            prediction = nil
        }
    }

    func jobFinished() {
        lock.lock()
        defer { lock.unlock() }
        jobs -= 1
        if jobs == 0, releaseWhenIdle {
            prediction = nil
            releaseWhenIdle = false
        }
    }

    func release() {
        lock.lock()
        defer { lock.unlock() }
        if jobs == 0 {
            prediction = nil
        } else {
            releaseWhenIdle = true
        }
    }

    func preload() throws -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        let start = Date()
        _ = try loadedPrediction()
        return Date().timeIntervalSince(start)
    }

    func predict(mix: MLMultiArray, spec: MLMultiArray) throws -> (spec: MLMultiArray, time: MLMultiArray) {
        let input = try MLDictionaryFeatureProvider(dictionary: ["mix": mix, "spec": spec])
        lock.lock()
        defer { lock.unlock() }
        do {
            return try Self.outputs(of: loadedPrediction()(input))
        } catch {
            // iOS doesn't allow GPU work from the background, and the GPU can also run out of
            // memory. Finish this job on the CPU; the next one tries the GPU again.
            guard units != .cpuOnly else { throw error }
            units = .cpuOnly
            prediction = nil
            return try Self.outputs(of: loadedPrediction()(input))
        }
    }

    private func loadedPrediction() throws -> Prediction {
        if let prediction { return prediction }
        let loaded: Prediction
        do {
            loaded = try loader(units)
        } catch {
            guard units != .cpuOnly else { throw error }
            units = .cpuOnly
            return try loadedPrediction()
        }
        prediction = loaded
        return loaded
    }

    private static func outputs(of result: MLFeatureProvider) throws -> (spec: MLMultiArray, time: MLMultiArray) {
        guard let spec = result.featureValue(for: "spec_out")?.multiArrayValue,
              let time = result.featureValue(for: "time_out")?.multiArrayValue else {
            throw StemSeparationError.invalidModelOutput
        }
        return (spec, time)
    }
}
