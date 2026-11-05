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
                Section {
                    NavigationLink("What everything does") { ControlsGuide() }
                } header: {
                    Text("Help")
                } footer: {
                    Text("Every control, explained. On the decks, press ? and touch a control to see just that one.")
                }
                Section {
                    Picker("Crossfader curve", selection: $dj.crossfaderCurve) {
                        ForEach(CrossfaderCurve.allCases) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    Toggle("Match track loudness", isOn: $autoGain)
                        .onChange(of: autoGain) { _, _ in dj.updateVolumes() }
                } header: {
                    Text("Mixing")
                } footer: {
                    Text("Smooth fades a deck out as the crossfader goes away from it. Scratch keeps both at full until the very end, for quick cuts. Matching brings loud and quiet tracks to about the same level.")
                }
                Section {
                    Toggle("Prepare stems on load", isOn: $prepareStems)
                } header: {
                    Text("Stems")
                } footer: {
                    Text("Splits each track in the background as soon as it's loaded, so stems are ready when you want them. Split tracks are kept, so they load instantly next time.")
                }
                Section {
                    Picker("Waveform colours", selection: $waveformStyle) {
                        Text("3-band").tag(0)
                        Text("RGB").tag(1)
                    }
                    .onChange(of: waveformStyle) { _, value in WaveformDisplay.shared.colorStyle = Int32(value) }
                } header: {
                    Text("Display")
                } footer: {
                    Text("3-band draws the lows, mids and highs in colours of their own. RGB is one shape, coloured by the balance between them. A deck on STEMS shows its stems' colours with either.")
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
            .keepsItsBar()
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
        .alert("Backup", isPresented: Binding(get: { libraryMessage != nil }, set: { if !$0 { libraryMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(libraryMessage ?? "")
        }
    }

    private var librarySection: some View {
        Section {
            Button {
                guard let data = try? library.backupData() else {
                    libraryMessage = "The backup couldn't be made."
                    return
                }
                backupDocument = LibraryBackupDocument(data: data)
                exportingBackup = true
            } label: {
                PickerRow(title: "Save a Backup…", systemImage: "square.and.arrow.up", isOpening: exportingBackup)
            }
            Button {
                importingBackup = true
            } label: {
                PickerRow(title: "Restore from a Backup…", systemImage: "clock.arrow.circlepath", isOpening: importingBackup)
            }
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
            Text("A backup holds your beat grids, cues, loops, keys and playlists, but not the music or sampler sounds. Segue DJ keeps a copy each day in its Backups folder in the Files app, but deleting the app deletes those too, so save one to iCloud Drive or your Mac now and then.")
        }
    }

    private func restore(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let result = try? library.restore(from: data) else {
            Haptics.shared.deny()
            libraryMessage = "That file isn't a Segue DJ backup."
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

/// A row that opens the Files picker, which can take a few seconds to appear. The spinner says it's on
/// its way, and goes when the picker's closed.
struct PickerRow: View {
    var title: String
    var systemImage: String
    var isOpening: Bool

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            if isOpening { ProgressView() }
        }
    }
}

extension View {
    /// On iOS 27, upright, a navigation bar goes away on scrolling down, and with it `Done`, or the way back, leaving only a swipe
    /// to get out. These sheets have nothing to gain from the room. Only a first-time user upright on the folded Duo found it.
    @ViewBuilder func keepsItsBar() -> some View {
        if #available(iOS 27.0, *) {
            toolbarMinimizationBehavior(.never, for: .navigationBar)
        } else {
            self
        }
    }

    /// A search bar floats over its list from iOS 26, and what's scrolled under it showed through, across what's being typed.
    @ViewBuilder func hardTopEdge() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            self
        }
    }
}
