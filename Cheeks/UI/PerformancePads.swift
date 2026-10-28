import SwiftUI

/// rekordbox-style 8 performance pads with modes: hot cue, beat loop, roll, beat jump, stems.
struct PerformancePads: View {
    @Bindable var deck: Deck

    private let loopSizes: [Double] = [1.0 / 4, 1.0 / 2, 1, 2, 4, 8, 16, 32]
    private let rollSizes: [Double] = [1.0 / 16, 1.0 / 8, 1.0 / 4, 1.0 / 2, 1, 2, 4, 8]
    private let jumpSizes: [Double] = [1, 4, 16, 32]

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                ForEach(PadMode.allCases) { mode in
                    Button { deck.padMode = mode } label: {
                        Text(mode.rawValue)
                            .font(.system(size: 9, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity, minHeight: 20)
                            .foregroundStyle(deck.padMode == mode ? Color.black : Theme.dim)
                            .background(RoundedRectangle(cornerRadius: 4).fill(deck.padMode == mode ? Color.white : Theme.raised))
                    }
                    .buttonStyle(.plain)
                }
                ToggleChip(title: "SHIFT", isOn: deck.shift, color: .yellow) { deck.shift.toggle() }
            }
            Grid(horizontalSpacing: 5, verticalSpacing: 5) {
                GridRow { ForEach(0..<4, id: \.self) { pad($0) } }
                GridRow { ForEach(4..<8, id: \.self) { pad($0) } }
            }
            .overlay(alignment: .center) { stemStatusOverlay }
        }
    }

    @ViewBuilder
    private func pad(_ i: Int) -> some View {
        switch deck.padMode {
        case .hotCue:
            let time = deck.track?.hotCues[i]
            PadButton(color: Theme.hotCueColors[i], lit: time != nil, onPress: { deck.hotCue(i) }) {
                VStack(spacing: 0) {
                    Text(Theme.hotCueLetters[i]).font(.system(size: 15, weight: .heavy, design: .rounded))
                    if let time { Text(time.clockString).font(.system(size: 8, design: .monospaced)) }
                }
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
            case .unavailable:
                EmptyView()
            }
        }
    }
}
