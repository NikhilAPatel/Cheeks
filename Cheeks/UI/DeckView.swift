import SwiftUI

struct DeckView: View {
    @Environment(DJEngine.self) private var dj
    @Bindable var deck: Deck

    private var color: Color { Theme.deckColors[deck.index] }

    var body: some View {
        VStack(spacing: 6) {
            DeckHeader(deck: deck)
            HStack(spacing: 8) {
                VStack(spacing: 8) {
                    JogWheel(deck: deck)
                    HStack(spacing: 10) {
                        PadButton(color: Theme.cue, lit: !deck.isPlaying && deck.isLoaded, cornerRadius: 22,
                                  onPress: deck.cueDown, onRelease: deck.cueUp) {
                            Text("CUE").font(.system(size: 13, weight: .heavy, design: .rounded))
                        }
                        PadButton(color: Theme.play, lit: deck.isPlaying, cornerRadius: 22, onPress: deck.togglePlay) {
                            Image(systemName: "playpause.fill").font(.system(size: 16, weight: .bold))
                        }
                    }
                    .frame(height: 44)
                }
                TempoColumn(deck: deck)
                    .frame(width: 70)
            }
            LoopRow(deck: deck)
            PerformancePads(deck: deck)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.25), lineWidth: 1))
        .overlay {
            if deck.isLoading {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.6))
                    VStack(spacing: 8) {
                        ProgressView().tint(color)
                        Text("Loading & analysing…").font(.caption).foregroundStyle(Theme.dim)
                    }
                }
            }
        }
    }
}

struct DeckHeader: View {
    let deck: Deck

    var body: some View {
        let color = Theme.deckColors[deck.index]
        HStack(alignment: .top, spacing: 8) {
            Text("\(deck.index + 1)")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(color))
                .foregroundStyle(.black)
            VStack(alignment: .leading, spacing: 1) {
                Text(deck.track?.title ?? "No track loaded")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(deck.track?.artist.isEmpty == false ? deck.track!.artist : (deck.loadError ?? " "))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let key = deck.track?.key {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(key + (deck.keyShift != 0 ? String(format: " %+d", deck.keyShift) : ""))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.5, green: 1, blue: 0.6))
                    Text(Camelot.musicalName(key)).font(.system(size: 10)).foregroundStyle(Theme.dim)
                }
            }
            // Tap the BPM to fix the beat grid.
            Menu {
                Section("Beat grid") {
                    Button("Double BPM (×2)") { deck.scaleBPM(2) }
                    Button("Halve BPM (÷2)") { deck.scaleBPM(0.5) }
                    Button("BPM +0.1") { deck.nudgeBPM(by: 0.1) }
                    Button("BPM −0.1") { deck.nudgeBPM(by: -0.1) }
                    Button("Grid earlier 10 ms") { deck.shiftGrid(milliseconds: -10) }
                    Button("Grid later 10 ms") { deck.shiftGrid(milliseconds: 10) }
                    Button("Set downbeat here") { deck.setDownbeatHere() }
                }
                Button("Save cue as memory cue") { deck.saveMemoryCue() }
            } label: {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(deck.bpm > 0 ? String(format: "%.2f", deck.effectiveBPM) : "--.--")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(deck.syncOn ? Theme.sync : .white)
                    Text(String(format: "%+.2f%%", deck.tempoRatioPercent))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.dim)
                }
            }
            .disabled(!deck.isLoaded)
        }
    }
}

struct TempoColumn: View {
    @Environment(DJEngine.self) private var dj
    @Bindable var deck: Deck

    var body: some View {
        VStack(spacing: 5) {
            ToggleChip(title: "SYNC", isOn: deck.syncOn, color: Theme.sync) { dj.toggleSync(deck) }
            ToggleChip(title: "KEY", isOn: deck.keyLock, color: .green) { deck.keyLock.toggle() }
            HStack(spacing: 2) {
                Button { deck.keyShift = max(-12, deck.keyShift - 1) } label: { Image(systemName: "minus") }
                Text(deck.keyShift == 0 ? "♮" : String(format: "%+d", deck.keyShift))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .onTapGesture(count: 2) { deck.keyShift = 0 }
                Button { deck.keyShift = min(12, deck.keyShift + 1) } label: { Image(systemName: "plus") }
            }
            .font(.system(size: 10, weight: .bold))
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            TempoSlider(deck: deck)
            Button {
                let ranges: [Double] = [6, 10, 16, 100]
                deck.tempoRange = ranges[((ranges.firstIndex(of: deck.tempoRange) ?? 0) + 1) % ranges.count]
            } label: {
                Text(deck.tempoRange >= 100 ? "WIDE" : "±\(Int(deck.tempoRange))%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.dim)
            }
            .buttonStyle(.plain)
            HStack(spacing: 3) {
                ToggleChip(title: "Q", isOn: deck.quantize, color: .red) { deck.quantize.toggle() }
                ToggleChip(title: "SLIP", isOn: deck.slipMode, color: .purple) { deck.slipMode.toggle() }
            }
            .scaleEffect(0.85)
        }
    }
}

/// Vertical pitch fader; down = faster, like a CDJ. Double-tap to reset.
struct TempoSlider: View {
    let deck: Deck
    @State private var dragStart: Double?

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let fraction = (deck.tempoRatioPercent / deck.tempoRange + 1) / 2 // 0 top … 1 bottom
            ZStack(alignment: .top) {
                Capsule().fill(Color.black.opacity(0.6)).frame(width: 6).frame(maxWidth: .infinity)
                Rectangle().fill(Color.green.opacity(0.7)).frame(width: 22, height: 1).offset(y: h / 2)
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(colors: [Color(white: 0.75), Color(white: 0.45)], startPoint: .top, endPoint: .bottom))
                    .overlay(Rectangle().fill(deck.syncOn ? Theme.sync : .white).frame(height: 2))
                    .frame(width: 40, height: 22)
                    .offset(y: CGFloat(min(1, max(0, fraction))) * (h - 22))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if dragStart == nil { dragStart = deck.tempoRatioPercent }
                        let delta = Double(g.translation.height / (h - 22)) * deck.tempoRange * 2
                        deck.setTempoManually(min(deck.tempoRange, max(-deck.tempoRange, dragStart! + delta)))
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { deck.setTempoManually(0) })
        }
    }
}

struct LoopRow: View {
    let deck: Deck

    var body: some View {
        HStack(spacing: 4) {
            PadButton("IN", color: Theme.loop, onPress: deck.loopIn)
            PadButton("OUT", color: Theme.loop, onPress: deck.loopOut)
            PadButton(deck.loopActive ? "EXIT" : "RELOOP", color: Theme.loop, lit: deck.loopActive) {
                deck.loopActive ? deck.exitLoop() : deck.reloop()
            }
            PadButton("½", color: .white, onPress: deck.halveLoop)
            PadButton(color: Theme.loop, lit: deck.loopActive, onPress: { deck.toggleBeatLoop(deck.loopBeats) }) {
                Text(beatLabel(deck.loopBeats)).font(.system(size: 13, weight: .heavy, design: .monospaced))
            }
            PadButton("×2", color: .white, onPress: deck.doubleLoop)
        }
        .frame(height: 30)
    }
}

func beatLabel(_ beats: Double) -> String {
    if beats >= 1 { return beats == beats.rounded() ? "\(Int(beats))" : String(format: "%.1f", beats) }
    return "1/\(Int((1 / beats).rounded()))"
}
