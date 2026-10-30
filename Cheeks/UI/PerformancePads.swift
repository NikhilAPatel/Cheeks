import SwiftUI

/// rekordbox-style 8 performance pads with modes: hot cue, beat loop, roll, beat jump, stems.
struct PerformancePads: View {
    @Bindable var deck: Deck

    private let loopSizes: [Double] = [1.0 / 4, 1.0 / 2, 1, 2, 4, 8, 16, 32]
    private let rollSizes: [Double] = [1.0 / 16, 1.0 / 8, 1.0 / 4, 1.0 / 2, 1, 2, 4, 8]
    private let jumpSizes: [Double] = [1, 4, 16, 32]

    var body: some View {
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            GridRow { ForEach(0..<4, id: \.self) { pad($0) } }
            GridRow { ForEach(4..<8, id: \.self) { pad($0) } }
        }
        .overlay(alignment: .center) { stemStatusOverlay }
    }

    @ViewBuilder
    private func pad(_ i: Int) -> some View {
        switch deck.padMode {
        case .hotCue:
            // rekordbox's hot cue list: a coloured letter tag, then the cue's time.
            let time = deck.track?.hotCues[i]
            let color = Theme.hotCueColors[i]
            PadButton(color: color, onPress: { deck.hotCue(i) }) {
                HStack(spacing: 6) {
                    Text(Theme.hotCueLetters[i])
                        .font(Theme.legend(11, .bold))
                        .foregroundStyle(time != nil ? Color.white : color)
                        .frame(width: 17, height: 17)
                        .background(RoundedRectangle(cornerRadius: 2).fill(time != nil ? color : .clear))
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(color.opacity(time != nil ? 0 : 0.6), lineWidth: 1))
                    Text(time.map(\.clockString) ?? "")
                        .font(Theme.readout(12))
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
            }
        case .beatLoop:
            let size = loopSizes[i]
            PadButton(beatLabel(size), color: Theme.loop, lit: deck.loopActive && abs(deck.loopBeats - size) < 0.0001) {
                deck.toggleBeatLoop(size)
            }
        case .roll:
            let size = rollSizes[i]
            PadButton(beatLabel(size), color: .cyan, onPress: { deck.rollBegin(size) }, onRelease: deck.rollEnd)
        case .beatJump:
            let beats = jumpSizes[i % 4] * (i < 4 ? -1 : 1)
            PadButton((beats < 0 ? "◀ " : "▶ ") + beatLabel(abs(beats)), color: .mint) { deck.beatJump(beats) }
        case .stems:
            let stem = Stem.allCases[i % 4]
            if i < 4 {
                PadButton(stem.label, color: stem.color, lit: deck.stemsOn[stem.rawValue]) { deck.toggleStem(stem) }
            } else {
                PadButton("SOLO", color: stem.color) { deck.soloStem(stem) }
            }
        }
    }

    @ViewBuilder
    private var stemStatusOverlay: some View {
        if deck.padMode == .stems {
            switch deck.stemStatus {
            case .separating:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Separating stems…").font(.caption2.bold())
                }
                .padding(6)
                .background(Capsule().fill(.black.opacity(0.8)))
                .allowsHitTesting(false)
            case .ready(let label):
                Text(label)
                    .font(.system(size: 8, weight: .heavy))
                    .padding(.horizontal, 5)
                    .background(Capsule().fill(.black.opacity(0.7)))
                    .allowsHitTesting(false)
            case .tooLong:
                Text("Stems need a track under \(Int(AudioConfig.maxStemSeconds / 60)) min")
                    .font(.caption2.bold())
                    .padding(6)
                    .background(Capsule().fill(.black.opacity(0.8)))
                    .allowsHitTesting(false)
            case .unavailable:
                EmptyView()
            }
        }
    }
}

/// rekordbox's pad mode dropdown ("HOT CUE ▾"), plus SHIFT for deleting cues.
struct PadModeMenu: View {
    @Bindable var deck: Deck

    var body: some View {
        HStack(spacing: 3) {
            Menu {
                Picker("Pad mode", selection: $deck.padMode) {
                    ForEach(PadMode.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(deck.padMode.rawValue).font(Theme.legend(11, .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(minWidth: 84, minHeight: 26)
                .background(RoundedRectangle(cornerRadius: 3).fill(Theme.raised))
            }
            ToggleChip(title: "SHIFT", isOn: deck.shift, color: Theme.cue) { deck.shift.toggle() }
        }
        .fixedSize()
    }
}
