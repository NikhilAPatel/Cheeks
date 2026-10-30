import SwiftUI

/// One deck, laid out like rekordbox's deck panel with the jog display made the main control:
/// track info and overview on top, then tempo fader and CUE/PLAY on the outer edge (under the
/// thumbs), the big jog, and the pads below. Deck 2 is mirrored so its controls are on the right.
struct DeckView: View {
    @Bindable var deck: Deck

    private var mirrored: Bool { deck.index == 1 }

    var body: some View {
        VStack(spacing: 0) {
            DeckInfo(deck: deck)
                .padding([.horizontal, .top], 5)
            GeometryReader { geo in
                let edge = min(76, max(48, geo.size.width * 0.14))
                let bottom = min(210, max(96, geo.size.height * 0.28))
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        if mirrored {
                            JogArea(deck: deck, mirrored: true)
                            TransportButtons(deck: deck).frame(width: edge)
                            TempoColumn(deck: deck).frame(width: 34)
                        } else {
                            TempoColumn(deck: deck).frame(width: 34)
                            TransportButtons(deck: deck).frame(width: edge)
                            JogArea(deck: deck, mirrored: false)
                        }
                    }
                    VStack(spacing: 4) {
                        HStack(spacing: 3) {
                            if mirrored {
                                LoopRow(deck: deck)
                                Spacer(minLength: 6)
                                PadModeMenu(deck: deck)
                            } else {
                                PadModeMenu(deck: deck)
                                Spacer(minLength: 6)
                                LoopRow(deck: deck)
                            }
                        }
                        .frame(height: 26)
                        PerformancePads(deck: deck)
                    }
                    .frame(height: bottom)
                }
                .padding(6)
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .controlSurface()
        .overlay {
            if deck.isLoading {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.6))
                    VStack(spacing: 8) {
                        ProgressView().tint(Theme.accent)
                        Text("Loading & analysing…").font(.caption).foregroundStyle(Theme.dim)
                    }
                }
            }
        }
    }
}

/// The jog display with Q, SLIP and MT (key lock) tucked into the corners around it.
struct JogArea: View {
    @Bindable var deck: Deck
    var mirrored: Bool

    var body: some View {
        JogWheel(deck: deck)
            .overlay(alignment: mirrored ? .topTrailing : .topLeading) {
                ToggleChip(title: "Q", isOn: deck.quantize) { deck.quantize.toggle() }
            }
            .overlay(alignment: mirrored ? .topLeading : .topTrailing) {
                ToggleChip(title: "SLIP", isOn: deck.slipMode) { deck.slipMode.toggle() }
            }
            .overlay(alignment: mirrored ? .bottomLeading : .bottomTrailing) {
                ToggleChip(title: "MT", isOn: deck.keyLock) { deck.keyLock.toggle() }
            }
    }
}

/// rekordbox-style deck header: title, artist, BPM and key, times, BEAT SYNC, key shift, overview.
struct DeckInfo: View {
    @Environment(DJEngine.self) private var dj
    @Bindable var deck: Deck

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .top, spacing: 7) {
                Text("\(deck.index + 1)")
                    .font(Theme.legend(12, .semibold))
                    .foregroundStyle(Theme.dim)
                VStack(alignment: .leading, spacing: 2) {
                    Text(deck.track?.title ?? "No track loaded")
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    HStack(spacing: 10) {
                        Text(deck.track?.artist.isEmpty == false ? deck.track!.artist : (deck.loadError ?? " "))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(1)
                        gridMenu
                    }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 3) {
                    ToggleChip(title: "BEAT SYNC", isOn: deck.syncOn, height: 22) { dj.toggleSync(deck) }
                    HStack(spacing: 8) {
                        times
                        keyShift
                    }
                }
            }
            OverviewWaveform(deck: deck)
                .frame(height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .padding(.horizontal, 7)
        .padding(.top, 5)
        .padding(.bottom, 5)
        .displayWell()
    }

    /// Tap the BPM to fix the beat grid.
    private var gridMenu: some View {
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
            HStack(spacing: 6) {
                Text(deck.bpm > 0 ? String(format: "%.2f", deck.bpm) : "--.--")
                Text(deck.track?.key.map(Camelot.musicalName) ?? "")
            }
            .font(Theme.readout(12))
            .foregroundStyle(.white)
            .fixedSize()
        }
        .disabled(!deck.isLoaded)
    }

    /// Remaining time large, elapsed small. The playhead isn't observed, so poll it.
    private var times: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let remaining = deck.duration - deck.position
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(deck.isLoaded ? "-" + Self.tenths(remaining) : "--:--.-")
                    .font(Theme.readout(17))
                    .foregroundStyle(deck.isLoaded && remaining < 30 ? Color.red : Color.white)
                Text(deck.isLoaded ? Self.tenths(deck.position) : "")
                    .font(Theme.readout(11))
                    .foregroundStyle(Theme.dim)
            }
            .fixedSize()
        }
    }

    /// `‹ 8A ±0 ›`: the key after shifting, and the shift. Double-tap to reset.
    private var keyShift: some View {
        HStack(spacing: 2) {
            Button { deck.keyShift = max(-12, deck.keyShift - 1) } label: { Image(systemName: "chevron.left").frame(width: 22, height: 22) }
            VStack(spacing: 0) {
                Text(deck.track?.key.map { Self.shifted($0, by: deck.keyShift) } ?? "--")
                    .font(Theme.readout(12, .medium))
                Text(deck.keyShift == 0 ? "±0" : String(format: "%+d", deck.keyShift))
                    .font(Theme.readout(9))
                    .foregroundStyle(deck.keyShift == 0 ? Theme.dim : Theme.accent)
            }
            .frame(minWidth: 30)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { deck.keyShift = 0 }
            Button { deck.keyShift = min(12, deck.keyShift + 1) } label: { Image(systemName: "chevron.right").frame(width: 22, height: 22) }
        }
        .font(.system(size: 11, weight: .semibold))
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    static func tenths(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "--:--.-" }
        let t = Int(max(0, seconds) * 10)
        return String(format: "%02d:%02d.%d", t / 600, t / 10 % 60, t % 10)
    }

    /// Each semitone up is seven steps round the Camelot wheel.
    static func shifted(_ key: String, by semitones: Int) -> String {
        guard let parsed = Camelot.parse(key) else { return key }
        let (number, minor) = parsed
        return "\(((number - 1 + 7 * semitones) % 12 + 12) % 12 + 1)\(minor ? "A" : "B")"
    }
}

/// Outer-edge strip: tempo range above a full-height pitch fader.
struct TempoColumn: View {
    @Bindable var deck: Deck

    var body: some View {
        VStack(spacing: 4) {
            Button {
                let ranges: [Double] = [6, 10, 16, 100]
                deck.tempoRange = ranges[((ranges.firstIndex(of: deck.tempoRange) ?? 0) + 1) % ranges.count]
            } label: {
                Text(deck.tempoRange >= 100 ? "WIDE" : "±\(Int(deck.tempoRange))")
                    .font(Theme.legend(10, .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .background(KeyCap())
            }
            .buttonStyle(.plain)
            TempoSlider(deck: deck)
            Text("TEMPO").font(Theme.legend(8, .semibold)).tracking(0.6).foregroundStyle(Theme.dim)
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
            let capH: CGFloat = 22
            let fraction = (deck.tempoRatioPercent / deck.tempoRange + 1) / 2 // 0 top … 1 bottom
            ZStack(alignment: .top) {
                FaderScale(ticks: 10, inset: capH / 2, vertical: true)
                FaderSlot().padding(.vertical, capH / 2 - 3).frame(maxWidth: .infinity)
                Rectangle().fill(Theme.play).frame(width: 26, height: 1.5).offset(y: h / 2 - 0.75)
                    .shadow(color: Theme.play, radius: 2)
                FaderCap(color: deck.syncOn ? Theme.accent : .white, vertical: true)
                    .frame(width: min(30, geo.size.width), height: capH)
                    .offset(y: CGFloat(min(1, max(0, fraction))) * (h - capH))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if dragStart == nil { dragStart = deck.tempoRatioPercent }
                        let delta = Double(g.translation.height / (h - capH)) * deck.tempoRange * 2
                        deck.setTempoManually(min(deck.tempoRange, max(-deck.tempoRange, dragStart! + delta)))
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { deck.setTempoManually(0) })
        }
    }
}

/// rekordbox's round CUE and PLAY buttons, at the bottom of the edge column where the thumb rests.
struct TransportButtons: View {
    let deck: Deck

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            RoundButton(color: Theme.cue, lit: !deck.isPlaying && deck.isLoaded, onPress: deck.cueDown, onRelease: deck.cueUp) {
                Text("CUE").font(Theme.legend(13, .semibold))
            }
            RoundButton(color: Theme.play, lit: deck.isPlaying, onPress: deck.togglePlay) {
                Image(systemName: deck.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 18))
            }
        }
    }
}

/// Loop controls, as in rekordbox's deck: IN, OUT, RELOOP, then ‹ beat-loop size ›.
struct LoopRow: View {
    let deck: Deck

    var body: some View {
        HStack(spacing: 3) {
            PadButton("IN", color: Theme.loop, onPress: deck.loopIn).frame(width: 34)
            PadButton("OUT", color: Theme.loop, onPress: deck.loopOut).frame(width: 38)
            PadButton(deck.loopActive ? "EXIT" : "RELOOP", color: Theme.loop, lit: deck.loopActive) {
                deck.loopActive ? deck.exitLoop() : deck.reloop()
            }
            .frame(width: 54)
            PadButton(color: .white, onPress: deck.halveLoop) { Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)) }
                .frame(width: 26)
            PadButton(color: .white, lit: deck.loopActive, onPress: { deck.toggleBeatLoop(deck.loopBeats) }) {
                Text(beatLabel(deck.loopBeats)).font(Theme.readout(14, .medium))
            }
            .frame(width: 38)
            PadButton(color: .white, onPress: deck.doubleLoop) { Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)) }
                .frame(width: 26)
        }
    }
}

func beatLabel(_ beats: Double) -> String {
    if beats >= 1 { return beats == beats.rounded() ? "\(Int(beats))" : String(format: "%.1f", beats) }
    return "1/\(Int((1 / beats).rounded()))"
}
