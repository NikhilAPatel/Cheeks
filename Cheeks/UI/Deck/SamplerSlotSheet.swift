import SwiftUI

/// What's on a sampler pad and how it plays.
struct SamplerSlotSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DJEngine.self) private var dj
    let slot: Int
    @State private var name = ""
    @State private var importing = false
    @State private var problem: String?

    var body: some View {
        @Bindable var sampler = dj.sampler
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .onChange(of: name) { _, value in sampler.rename(slot, to: value) }
                    Picker("Plays", selection: Binding(get: { sampler.slots[slot].mode }, set: { sampler.setMode($0, slot: slot) })) {
                        ForEach(Sampler.Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Button("Choose a File…", systemImage: "folder") { importing = true }
                    ForEach(dj.decks, id: \.index) { deck in
                        Button("Grab Deck \(deck.index + 1)'s Loop", systemImage: "repeat") { grab(deck) }
                            .disabled(deck.renderer.loopEnd <= deck.renderer.loopStart)
                    }
                    Button("Record the Master", systemImage: "record.circle") {
                        Haptics.shared.confirm()
                        sampler.startRecording(slot: slot)
                        dismiss()
                    }
                    if sampler.hasOwnSound(slot) {
                        Button("Restore the Original Sound", systemImage: "arrow.uturn.backward", role: .destructive) {
                            sampler.restoreOriginal(slot)
                            dismiss()
                        }
                    }
                } header: {
                    Text("Sound")
                } footer: {
                    Text("A grabbed loop comes out as you're hearing it, so with the vocal muted it has no vocal. Samples can be up to a minute long, and recordings stop at 30 seconds.")
                }
            }
            .navigationTitle("Pad \(slot + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .onAppear { name = sampler.slots[slot].name ?? "" }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
            guard case .success(let url) = result else { return }
            Task {
                if let message = await sampler.importSample(from: url, slot: slot) {
                    Haptics.shared.deny()
                    problem = message
                } else {
                    Haptics.shared.confirm()
                    dismiss()
                }
            }
        }
        .alert("Sampler", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(problem ?? "")
        }
    }

    private func grab(_ deck: Deck) {
        if let message = dj.sampler.grabLoop(from: deck, slot: slot) {
            Haptics.shared.deny()
            problem = message
        } else {
            Haptics.shared.confirm()
            dismiss()
        }
    }
}
