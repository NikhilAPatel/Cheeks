import SwiftUI

extension CueColor {
    var color: Color { Color(red: red, green: green, blue: blue) }

    init(_ color: Color) {
        let c = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(red: Double(min(1, max(0, r))), green: Double(min(1, max(0, g))), blue: Double(min(1, max(0, b))))
    }
}

/// Everything saved on the track on this deck, in a native list: names, colours, and which loop
/// turns on at load. It edits the track directly, so the pads and waveform change as you go.
struct CueListView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var deck: Deck

    private var hotSlots: [Int] { (deck.track?.hotCues.keys.sorted()) ?? [] }

    var body: some View {
        NavigationStack {
            List {
                if hotSlots.isEmpty && deck.memoryItems.isEmpty {
                    ContentUnavailableView("Nothing saved yet", systemImage: "bookmark",
                                           description: Text("Set hot cues on the CUE pads, and save cues and loops on the MEM pads."))
                        .listRowBackground(Color.clear)
                }
                if !hotSlots.isEmpty { hotCueSection }
                memoryCueSection
                savedLoopSection
            }
            .navigationTitle(deck.track?.title ?? "Cues and loops")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    private var hotCueSection: some View {
        Section("Hot cues") {
            ForEach(hotSlots, id: \.self) { slot in
                HStack(spacing: 10) {
                    Text(Theme.hotCueLetters[slot])
                        .font(Theme.silk(12))
                        .foregroundStyle(Color.black)
                        .frame(width: 20, height: 20)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(deck.hotCueColor(slot)))
                    TextField("Name", text: Binding(
                        get: { deck.track?.hotCueInfo[slot]?.name ?? "" },
                        set: { name in deck.updateTrack { $0.hotCueInfo[slot, default: HotCueInfo()].name = name } }))
                    if let time = deck.track?.hotCues[slot] {
                        Text(time.clockString).font(Theme.digits(13)).foregroundStyle(.secondary)
                    }
                    ColorPicker("Colour", selection: Binding(
                        get: { deck.hotCueColor(slot) },
                        set: { color in deck.updateTrack { $0.hotCueInfo[slot, default: HotCueInfo()].color = CueColor(color) } }),
                                supportsOpacity: false)
                        .labelsHidden()
                }
            }
            .onDelete { rows in
                let slots = rows.map { hotSlots[$0] }
                deck.updateTrack { t in
                    for slot in slots {
                        t.hotCues[slot] = nil
                        t.hotCueInfo[slot] = nil
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var memoryCueSection: some View {
        let cues = (deck.track?.memoryCues ?? []).sorted { $0.time < $1.time }
        if !cues.isEmpty {
            Section("Memory cues") {
                ForEach(cues) { cue in
                    HStack(spacing: 10) {
                        Image(systemName: "bookmark.fill").foregroundStyle(cue.color?.color ?? Theme.danger)
                        TextField("Name", text: Binding(
                            get: { deck.track?.memoryCues.first { $0.id == cue.id }?.name ?? "" },
                            set: { name in deck.updateTrack { t in
                                if let i = t.memoryCues.firstIndex(where: { $0.id == cue.id }) { t.memoryCues[i].name = name }
                            } }))
                        Button(cue.time.clockString) {
                            Haptics.shared.key()
                            deck.recall(cue)
                        }
                        .font(Theme.digits(13))
                        .buttonStyle(.borderless)
                    }
                }
                .onDelete { rows in
                    let gone = Set(rows.map { cues[$0].id })
                    deck.updateTrack { $0.memoryCues.removeAll { gone.contains($0.id) } }
                }
            }
        }
    }

    @ViewBuilder
    private var savedLoopSection: some View {
        let loops = (deck.track?.savedLoops ?? []).sorted { $0.start < $1.start }
        if !loops.isEmpty {
            Section {
                ForEach(loops) { loop in
                    HStack(spacing: 10) {
                        Image(systemName: "repeat").foregroundStyle(Theme.loop)
                        TextField("Name", text: Binding(
                            get: { deck.track?.savedLoops.first { $0.id == loop.id }?.name ?? "" },
                            set: { name in deck.updateTrack { t in
                                if let i = t.savedLoops.firstIndex(where: { $0.id == loop.id }) { t.savedLoops[i].name = name }
                            } }))
                        Button("\(loop.start.clockString), \(lengthText(loop))") {
                            Haptics.shared.key()
                            deck.recall(loop)
                        }
                        .font(Theme.digits(13))
                        .buttonStyle(.borderless)
                        Toggle("On at load", isOn: Binding(
                            get: { deck.track?.savedLoops.first { $0.id == loop.id }?.activeOnLoad ?? false },
                            set: { on in deck.updateTrack { t in
                                // Only one loop can be waiting at load.
                                for i in t.savedLoops.indices { t.savedLoops[i].activeOnLoad = on && t.savedLoops[i].id == loop.id }
                            } }))
                            .labelsHidden()
                    }
                }
                .onDelete { rows in
                    let gone = Set(rows.map { loops[$0].id })
                    deck.updateTrack { $0.savedLoops.removeAll { gone.contains($0.id) } }
                }
            } header: {
                Text("Saved loops")
            } footer: {
                Text("A loop switched on here is waiting when the track loads, and holds the deck once it gets there.")
            }
        }
    }

    private func lengthText(_ loop: SavedLoop) -> String {
        guard deck.grid != nil else { return String(format: "%.1f s", loop.end - loop.start) }
        let beats = deck.beatPosition(loop.end * deck.sampleRate) - deck.beatPosition(loop.start * deck.sampleRate)
        return "\(Format.beats((beats * 16).rounded() / 16)) beats"
    }
}
