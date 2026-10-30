import AVFoundation
import Observation

/// The eight sampler pads. Each starts with one of the built-in sounds, and can hold a file, a loop
/// grabbed from a deck, or a recording of the master instead.
@MainActor
@Observable
final class Sampler {
    enum Mode: String, Codable, CaseIterable, Identifiable {
        /// Fires once. Pressing it again starts it again.
        case oneShot = "One shot"
        /// Plays for as long as the pad's held.
        case gate = "Gate"
        /// One press starts it going round, the next stops it.
        case loop = "Loop"
        var id: String { rawValue }
    }

    struct Slot: Codable, Equatable {
        /// Set when the pad's been named, or when it holds its own sound.
        var name: String?
        /// The sound in `Sampler.directory`, or nil for the pad's built-in sound.
        var fileName: String?
        var mode: Mode = .oneShot
    }

    private struct Settings: Codable {
        var slots: [Slot]
        var quantize: Bool
        var level: Float
    }

    static let longestSample: Double = 60
    private static let longestRecording: Double = 30
    private static let quantizeBeats = 0.25

    static let directory: URL = {
        let dir = URL.documentsDirectory.appending(path: "Samples", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    private static let settingsURL = directory.appending(path: "samples.json")

    private(set) var slots = [Slot](repeating: Slot(), count: 8)
    /// Pads going round in loop mode.
    private(set) var looping: Set<Int> = []
    private(set) var recordingSlot: Int?
    /// Pads start on the beat of the master deck when this is on.
    var quantize = false { didSet { saveSettings() } }
    var level: Float = 1 {
        didSet {
            cheeks_engine_set_sampler_level(core, level)
            // Written shortly after the last change: this moves on every frame of a drag.
            pendingSave?.cancel()
            pendingSave = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                self?.saveSettings()
            }
        }
    }
    /// SET is lit: the next pad pressed opens its settings.
    var isSetting = false
    var slotBeingEdited: Int?
    /// A message for the status capsule.
    @ObservationIgnored var onMessage: (@MainActor (String) -> Void)?

    @ObservationIgnored private let core: OpaquePointer
    /// Strong references keep the audio alive; the render thread only sees raw pointers.
    @ObservationIgnored private var buffers = [PCM16Stereo?](repeating: nil, count: 8)
    @ObservationIgnored private var builtIn: [PCM16Stereo] = []
    @ObservationIgnored private var captureBuffer: PCM16Stereo?
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    init(core: OpaquePointer) {
        self.core = core
        if let data = try? Data(contentsOf: Self.settingsURL),
           let saved = try? JSONDecoder().decode(Settings.self, from: data), saved.slots.count == 8 {
            slots = saved.slots
            quantize = saved.quantize
            level = saved.level
        }
        cheeks_engine_set_sampler_level(core, level)
        for i in slots.indices { cheeks_engine_set_sample_loop(core, Int32(i), slots[i].mode == .loop) }
    }

    /// Makes the built-in sounds and reads the pads' own, off the main thread.
    func loadSounds() {
        let saved = slots.map(\.fileName)
        Task.detached(priority: .utility) {
            let bank = SampleBank.render()
            let own = saved.map { name in
                name.flatMap { try? AudioDecoder.decode(url: Self.directory.appending(path: $0), sampleRate: AudioConfig.sampleRate) }
            }
            await MainActor.run {
                self.builtIn = bank
                for slot in 0..<8 { self.install(own[slot] ?? bank[slot], slot: slot, keepsIfCustom: own[slot] == nil) }
            }
        }
    }

    func name(_ slot: Int) -> String { slots[slot].name ?? SampleBank.names[slot] }

    func hasOwnSound(_ slot: Int) -> Bool { slots[slot].fileName != nil }

    /// Hands audio to the core. A pad that's been given its own sound in the meantime keeps it.
    private func install(_ pcm: PCM16Stereo, slot: Int, keepsIfCustom: Bool = false) {
        if keepsIfCustom && slots[slot].fileName != nil && buffers[slot] != nil { return }
        cheeks_engine_set_sample(core, Int32(slot), pcm.data, Int64(pcm.frames))
        // Only let go of the old audio once the core can no longer reach it.
        buffers[slot] = pcm
        looping.remove(slot)
    }

    // MARK: Playing

    func press(_ slot: Int, masterDeck: Int) {
        if recordingSlot == slot {
            stopRecording()
            return
        }
        if slots[slot].mode == .loop && looping.contains(slot) {
            stop(slot)
            return
        }
        cheeks_engine_set_sample_loop(core, Int32(slot), slots[slot].mode == .loop)
        if quantize {
            cheeks_engine_trigger_sample_quantized(core, Int32(slot), 1, Int32(masterDeck), Self.quantizeBeats)
        } else {
            cheeks_engine_trigger_sample(core, Int32(slot), 1)
        }
        if slots[slot].mode == .loop { looping.insert(slot) }
    }

    func release(_ slot: Int) {
        if slots[slot].mode == .gate { stop(slot) }
    }

    func stop(_ slot: Int) {
        cheeks_engine_stop_sample(core, Int32(slot))
        looping.remove(slot)
    }

    func stopAll() {
        for slot in 0..<8 { stop(slot) }
    }

    func isPlaying(_ slot: Int) -> Bool { cheeks_engine_sample_active(core, Int32(slot)) }

    // MARK: Changing a pad

    func setMode(_ mode: Mode, slot: Int) {
        stop(slot)
        slots[slot].mode = mode
        cheeks_engine_set_sample_loop(core, Int32(slot), mode == .loop)
        saveSettings()
    }

    func rename(_ slot: Int, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        slots[slot].name = trimmed.isEmpty ? nil : trimmed
        saveSettings()
    }

    /// Copies a file in and puts it on the pad. Returns what went wrong, if anything.
    func importSample(from url: URL, slot: Int) async -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let name = "pad\(slot + 1)-\(UUID().uuidString).\(url.pathExtension.lowercased())"
        let destination = Self.directory.appending(path: name)
        let title = url.deletingPathExtension().lastPathComponent
        let decoded: Result<PCM16Stereo, Error> = await Task.detached(priority: .userInitiated) {
            Result {
                let pcm = try AudioDecoder.decode(url: url, sampleRate: AudioConfig.sampleRate)
                if pcm.duration <= Self.longestSample { try FileManager.default.copyItem(at: url, to: destination) }
                return pcm
            }
        }.value
        switch decoded {
        case .failure:
            return "That file couldn't be opened."
        case .success(let pcm):
            guard pcm.frames > 0 else { return "That file has no audio in it." }
            guard pcm.duration <= Self.longestSample else { return "Samples can be up to \(Int(Self.longestSample)) seconds long." }
            useSound(pcm, fileName: name, title: title, slot: slot)
            return nil
        }
    }

    /// Puts the loop on a deck onto a pad, as you're hearing it: with stems muted, it's without them.
    func grabLoop(from deck: Deck, slot: Int) -> String? {
        let start = deck.renderer.loopStart, end = deck.renderer.loopEnd
        guard end > start + 64 else { return "There's no loop set on deck \(deck.index + 1)." }
        guard (end - start) / AudioConfig.sampleRate <= Self.longestSample else { return "That loop's too long for a pad." }
        let gains = (0..<4).map { deck.stemsOn[$0] ? deck.stemLevels[$0] : 0 }
        let pcm = deck.renderer.copyAudio(fromFrame: Int(start), toFrame: Int(end), stemGains: gains)
        guard let name = save(pcm, slot: slot) else { return "The loop couldn't be saved." }
        useSound(pcm, fileName: name, title: "LOOP \(deck.index + 1)", slot: slot, mode: .loop)
        return nil
    }

    /// Starts recording the master onto a pad. Press the pad or STOP to finish.
    func startRecording(slot: Int) {
        stopRecording()
        let buffer = PCM16Stereo(frames: Int(Self.longestRecording * AudioConfig.sampleRate))
        captureBuffer = buffer
        recordingSlot = slot
        cheeks_engine_capture_start(core, buffer.data, Int64(buffer.frames))
    }

    func stopRecording() {
        guard let slot = recordingSlot, let buffer = captureBuffer else { return }
        let frames = Int(cheeks_engine_capture_stop(core))
        recordingSlot = nil
        captureBuffer = nil
        guard frames > 64 else { return }
        let pcm = buffer.slice(from: 0, count: frames)
        guard let name = save(pcm, slot: slot) else {
            onMessage?("The recording couldn't be saved.")
            return
        }
        useSound(pcm, fileName: name, title: "REC \(slot + 1)", slot: slot)
    }

    var recordedSeconds: Double { Double(cheeks_engine_capture_frames(core)) / AudioConfig.sampleRate }

    /// Goes back to the pad's built-in sound.
    func restoreOriginal(_ slot: Int) {
        stop(slot)
        removeOwnFile(slot)
        slots[slot] = Slot()
        if slot < builtIn.count { install(builtIn[slot], slot: slot) }
        cheeks_engine_set_sample_loop(core, Int32(slot), false)
        saveSettings()
    }

    /// A recording reaching its limit stops itself.
    func tick() {
        guard recordingSlot != nil, recordedSeconds >= Self.longestRecording else { return }
        stopRecording()
    }

    private func save(_ pcm: PCM16Stereo, slot: Int) -> String? {
        let name = "pad\(slot + 1)-\(UUID().uuidString).caf"
        do {
            try pcm.write(to: Self.directory.appending(path: name))
            return name
        } catch {
            return nil
        }
    }

    private func useSound(_ pcm: PCM16Stereo, fileName: String, title: String, slot: Int, mode: Mode? = nil) {
        stop(slot)
        removeOwnFile(slot)
        install(pcm, slot: slot)
        slots[slot].fileName = fileName
        slots[slot].name = title.uppercased()
        if let mode { slots[slot].mode = mode }
        cheeks_engine_set_sample_loop(core, Int32(slot), slots[slot].mode == .loop)
        saveSettings()
    }

    private func removeOwnFile(_ slot: Int) {
        if let old = slots[slot].fileName { try? FileManager.default.removeItem(at: Self.directory.appending(path: old)) }
    }

    private func saveSettings() {
        let settings = Settings(slots: slots, quantize: quantize, level: level)
        if let data = try? JSONEncoder().encode(settings) { try? data.write(to: Self.settingsURL, options: .atomic) }
    }
}
