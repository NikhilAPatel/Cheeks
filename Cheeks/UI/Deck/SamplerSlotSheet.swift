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
                        // Filled in with what the pad says, which isn't a change of name.
                        .onChange(of: name) { _, value in if value != sampler.name(slot) { sampler.rename(slot, to: value) } }
                    Picker("Plays", selection: Binding(get: { sampler.slots[slot].mode }, set: { sampler.setMode($0, slot: slot) })) {
                        ForEach(Sampler.Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Button { importing = true } label: {
                        PickerRow(title: "Choose a File…", systemImage: "folder", isOpening: importing)
                    }
                    // Only decks with a loop set: there's nothing to grab from the others.
                    ForEach(dj.decks.filter { $0.renderer.loopEnd > $0.renderer.loopStart }, id: \.index) { deck in
                        Button("Grab Deck \(deck.index + 1)'s Loop", systemImage: "repeat") { grab(deck) }
                    }
                    Button("Record the Master", systemImage: "record.circle") {
                        Haptics.shared.confirm()
                        sampler.startRecording(slot: slot)
                        dismiss()
                    }
                    if sampler.hasOwnSound(slot) {
                        Button("Restore the Original Sound", systemImage: "arrow.uturn.backward") {
                            sampler.restoreOriginal(slot)
                            dismiss()
                        }
                    }
                } header: {
                    Text("Sound")
                } footer: {
                    let grabbing = dj.decks.contains { $0.renderer.loopEnd > $0.renderer.loopStart } ? "A grabbed loop comes out as you're hearing it, so with the vocal muted it has no vocal. " : ""
                    Text(grabbing + "Samples can be up to a minute long, and recordings stop at 30 seconds.")
                }
            }
            .font(Theme.text(13))
            // On a phone on its side it was 39 pt too tall, so a flick moved its rows under a finger for 0.7 s, and that cost a
            // first-time user two wrong rows, one of which recorded over a pad.
            .listSectionSpacing(.compact)
            .environment(\.defaultMinListRowHeight, 34)
            .contentMargins(.top, 0, for: .scrollContent)
            .scrollBounceBehavior(.basedOnSize)
            .scrollContentBackground(.hidden)
            .background(Color(white: 0.07))
            .navigationTitle("Pad \(slot + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .onAppear { name = sampler.name(slot) }
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
