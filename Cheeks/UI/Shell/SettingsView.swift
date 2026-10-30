import SwiftUI

/// App settings, in a native form, since that's what people expect a settings screen to be.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DJEngine.self) private var dj
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
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }
}
