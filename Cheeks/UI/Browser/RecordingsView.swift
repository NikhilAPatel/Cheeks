import AVFoundation
import SwiftUI

/// Recorded mixes: play back, view the tracklist, share (audio + tracklists), rename, delete.
struct RecordingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DJEngine.self) private var dj
    @State private var recordings: [URL] = []
    @State private var player = RecordingPlayer()
    @State private var expanded: URL?
    @State private var renaming: URL?
    @State private var newName = ""
    @State private var deleting: URL?

    var body: some View {
        NavigationStack {
            List {
                if recordings.isEmpty {
                    ContentUnavailableView("No recordings yet", systemImage: "record.circle",
                                           description: Text("Tap REC at the top of the screen to record your mix. Recordings also appear in the Files app under Cheeks › Recordings, with a tracklist next to each one."))
                }
                ForEach(recordings, id: \.self) { url in
                    row(url)
                }
            }
            .navigationTitle("Recordings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear(perform: reload)
            .onChange(of: dj.savingRecordings) { _, _ in reload() }
            .onDisappear { player.stop() }
            // `presenting:` hands the file to the buttons, so it can't be cleared before they run.
            .alert("Rename recording", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
                   presenting: renaming) { url in
                TextField("Name", text: $newName)
                Button("Rename") { rename(url) }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Delete this recording and its tracklist?",
                                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible, presenting: deleting) { url in
                Button("Delete", role: .destructive) { delete(url) }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                // Previews play straight to the main output, so they're off while a deck is playing.
                let isPlaying = player.playing == url
                Button { player.toggle(url) } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 28))
                }
                .buttonStyle(.plain)
                .disabled(decksPlaying && !isPlaying)
                .accessibilityLabel("\(isPlaying ? "Pause" : "Play") \(url.deletingPathExtension().lastPathComponent)")
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.deletingPathExtension().lastPathComponent).font(.headline)
                    Text(details(url)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if tracklist(url) != nil {
                    Button { expanded = expanded == url ? nil : url } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                    .buttonStyle(.plain)
                }
                ShareLink(items: [url] + existingCompanions(url)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                Menu {
                    Button("Rename", systemImage: "pencil") {
                        newName = url.deletingPathExtension().lastPathComponent
                        renaming = url
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) { deleting = url }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.borderless)
            }
            if expanded == url, let text = tracklist(url) {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
            }
        }
        .padding(.vertical, 4)
    }

    private var decksPlaying: Bool { dj.decks.contains { $0.isPlaying } }

    private func reload() {
        recordings = Recordings.list()
    }

    private func details(_ url: URL) -> String {
        var parts: [String] = []
        if let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 {
            parts.append((Double(file.length) / file.fileFormat.sampleRate).clockString)
        }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
        }
        parts.append(url.pathExtension.uppercased())
        return parts.joined(separator: " · ")
    }

    private func tracklist(_ url: URL) -> String? {
        try? String(contentsOf: Recordings.companionFiles(for: url)[0], encoding: .utf8)
    }

    private func existingCompanions(_ url: URL) -> [URL] {
        Recordings.companionFiles(for: url).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func rename(_ url: URL) {
        renaming = nil
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        guard !name.isEmpty else { return }
        let target = Recordings.directory.appending(path: "\(name).\(url.pathExtension)")
        guard !FileManager.default.fileExists(atPath: target.path) else { return }
        if player.playing == url { player.stop() }
        let oldCompanions = Recordings.companionFiles(for: url)
        let newCompanions = Recordings.companionFiles(for: target)
        do {
            try FileManager.default.moveItem(at: url, to: target)
            for (old, new) in zip(oldCompanions, newCompanions) where FileManager.default.fileExists(atPath: old.path) {
                try? FileManager.default.moveItem(at: old, to: new)
            }
            // The CUE sheet names its audio file; point it at the new name.
            let cue = newCompanions[1]
            if let text = try? String(contentsOf: cue, encoding: .utf8) {
                try? text.replacingOccurrences(of: url.lastPathComponent, with: target.lastPathComponent)
                    .write(to: cue, atomically: true, encoding: .utf8)
            }
        } catch {}
        reload()
    }

    private func delete(_ url: URL) {
        deleting = nil
        if player.playing == url { player.stop() }
        try? FileManager.default.removeItem(at: url)
        for companion in Recordings.companionFiles(for: url) { try? FileManager.default.removeItem(at: companion) }
        reload()
    }
}

/// Plays a recorded mix. `AVAudioPlayer` activates the audio session when it starts, which can block
/// for a while, so it's only ever touched on its own queue and the screen never waits for it.
@MainActor
@Observable
final class RecordingPlayer {
    private(set) var playing: URL?
    @ObservationIgnored private let core = Core()

    init() {
        core.onFinished = { [weak self] url in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if self?.playing == url { self?.playing = nil }
                }
            }
        }
    }

    func toggle(_ url: URL) {
        if playing == url {
            stop()
        } else {
            playing = url
            core.play(url) { [weak self] started in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if !started && self?.playing == url { self?.playing = nil }
                    }
                }
            }
        }
    }

    func stop() {
        playing = nil
        core.stop()
    }

    private final class Core: NSObject, AVAudioPlayerDelegate {
        var onFinished: ((URL) -> Void)?
        private let queue = DispatchQueue(label: "com.nikhilpatel.cheeks.recording-player", qos: .userInitiated)
        private var player: AVAudioPlayer?

        func play(_ url: URL, started: @escaping (Bool) -> Void) {
            queue.async { [self] in
                player?.stop()
                player = try? AVAudioPlayer(contentsOf: url)
                player?.delegate = self
                started(player?.play() == true)
            }
        }

        func stop() {
            queue.async { [self] in
                player?.stop()
                player = nil
            }
        }

        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            if let url = player.url { onFinished?(url) }
        }
    }
}
