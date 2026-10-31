import SwiftUI

/// App settings, in a native form, since that's what people expect a settings screen to be.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DJEngine.self) private var dj
    @Environment(Library.self) private var library
    @State private var backupDocument: LibraryBackupDocument?
    @State private var exportingBackup = false
    @State private var importingBackup = false
    @State private var libraryMessage: String?
    @State private var waveformStyle = Int(WaveformDisplay.shared.colorStyle)
    @State private var hapticsOn = Haptics.shared.isEnabled
    @AppStorage("autoGain") private var autoGain = true
    @AppStorage("prepareStemsOnLoad") private var prepareStems = true

    var body: some View {
        @Bindable var dj = dj
        NavigationStack {
            Form {
                Section("Mixing") {
                    Picker("Crossfader curve", selection: $dj.crossfaderCurve) {
                        ForEach(CrossfaderCurve.allCases) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    Toggle("Match track loudness", isOn: $autoGain)
                        .onChange(of: autoGain) { _, _ in dj.updateVolumes() }
                }
                Section {
                    Toggle("Prepare stems on load", isOn: $prepareStems)
                } header: {
                    Text("Stems")
                } footer: {
                    Text("Splits each track in the background as soon as it's loaded, so stems are ready when you want them. Split tracks are kept, so they load instantly next time.")
                }
                Section("Display") {
                    Picker("Waveform colours", selection: $waveformStyle) {
                        Text("3-band").tag(0)
                        Text("RGB").tag(1)
                    }
                    .onChange(of: waveformStyle) { _, value in WaveformDisplay.shared.colorStyle = Int32(value) }
                }
                Section {
                    Toggle("Haptics", isOn: $hapticsOn)
                        .onChange(of: hapticsOn) { _, value in
                            Haptics.shared.isEnabled = value
                            if value { Haptics.shared.confirm() }
                        }
                } header: {
                    Text("Feel")
                } footer: {
                    Text("Keys click, knobs and faders have detents, and you can feel beats and bars pass under your finger on the platter.")
                }
                Section("Recording") {
                    Picker("Format", selection: $dj.recordingFormat) {
                        ForEach(RecordingFormat.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                librarySection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .fileExporter(isPresented: $exportingBackup, document: backupDocument, contentType: .json, defaultFilename: library.suggestedBackupName) { result in
            switch result {
            case .success:
                Haptics.shared.confirm()
                libraryMessage = "Backup saved."
            case .failure: libraryMessage = "The backup couldn't be saved there."
            }
        }
        .fileImporter(isPresented: $importingBackup, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            restore(url)
        }
        .alert("Library", isPresented: Binding(get: { libraryMessage != nil }, set: { if !$0 { libraryMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(libraryMessage ?? "")
        }
    }

    private var librarySection: some View {
        Section {
            Button("Save a Backup…", systemImage: "square.and.arrow.up") {
                guard let data = try? library.backupData() else {
                    libraryMessage = "The backup couldn't be made."
                    return
                }
                backupDocument = LibraryBackupDocument(data: data)
                exportingBackup = true
            }
            Button("Restore from a Backup…", systemImage: "clock.arrow.circlepath") { importingBackup = true }
            if !library.missingFiles.isEmpty {
                LabeledContent("Tracks missing their file", value: "\(library.missingFiles.count)")
            }
            if let last = library.lastAutomaticBackup {
                LabeledContent("Last automatic copy") {
                    Text(last, style: .date)
                }
            }
        } header: {
            Text("Library")
        } footer: {
            Text("A backup holds your beat grids, cues, loops, keys and playlists, but not the music or sampler sounds. Cheeks keeps a copy each day in its Backups folder in the Files app, but deleting the app deletes those too, so save one to iCloud Drive or your Mac now and then.")
        }
    }

    private func restore(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let result = try? library.restore(from: data) else {
            Haptics.shared.deny()
            libraryMessage = "That file isn't a Cheeks backup."
            return
        }
        Haptics.shared.confirm()
        dj.decks.forEach { $0.refreshTrack() }
        var message = "Restored \(Format.count(result.matched, "track")) and \(Format.count(result.playlists, "playlist"))."
        if result.added == 1 {
            message += " 1 track is waiting for its music: import the file and it'll get its cues back."
        } else if result.added > 1 {
            message += " \(result.added) tracks are waiting for their music: import the files and they'll get their cues back."
        }
        libraryMessage = message
    }
}
