import SwiftUI

/// The two-channel mixer column between the decks, as in rekordbox: trim, 3-band EQ, filter,
/// headphone CUE and the channel faders, with the level meters between them.
struct MixerView: View {
    @Environment(DJEngine.self) private var dj

    var body: some View {
        GeometryReader { geo in
            let knob = min(38, max(24, geo.size.height / 16))
            HStack(alignment: .top, spacing: 2) {
                ChannelStrip(deck: dj.decks[0], knobSize: knob)
                ChannelStrip(deck: dj.decks[1], knobSize: knob)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Theme.panel)
    }
}

struct ChannelStrip: View {
    @Bindable var deck: Deck
    var knobSize: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            Knob(value: $deck.trim, label: "TRIM", color: Theme.dim, size: knobSize * 0.85)
            Knob(value: $deck.eqHigh, label: "HIGH", size: knobSize)
            Knob(value: $deck.eqMid, label: "MID", size: knobSize)
            Knob(value: $deck.eqLow, label: "LOW", size: knobSize)
            Knob(value: $deck.filter, label: "FILTER", size: knobSize)
            Button { deck.headphoneCue.toggle() } label: {
                Text("CUE")
                    .font(Theme.legend(11, .semibold))
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .foregroundStyle(deck.headphoneCue ? Color.white : Theme.dim)
                    .background(RoundedRectangle(cornerRadius: 3).fill(deck.headphoneCue ? Theme.accent : Theme.raised))
            }
            .buttonStyle(.plain)
            // Meters sit between the two faders.
            HStack(spacing: 4) {
                if deck.index == 0 {
                    VerticalFader(value: $deck.fader)
                    LevelMeter(level: deck.level).frame(width: 5)
                } else {
                    LevelMeter(level: deck.level).frame(width: 5)
                    VerticalFader(value: $deck.fader)
                }
            }
            .padding(.top, 2)
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
    }
}

/// rekordbox's FX unit in Beat FX mode: channel assign, level, effect, beat length, on.
struct FXUnit: View {
    @Environment(DJEngine.self) private var dj

    var body: some View {
        @Bindable var dj = dj
        HStack(spacing: 5) {
            Text("FX").font(Theme.legend(12, .semibold)).foregroundStyle(Theme.dim)
            HStack(spacing: 2) {
                // 0 = deck 1, 1 = deck 2, 2 = both (rekordbox's M, for master)
                ForEach(0..<3, id: \.self) { target in
                    Button { dj.fxTarget = target } label: {
                        Text(["1", "2", "M"][target])
                            .font(Theme.legend(11, .semibold))
                            .frame(width: 24, height: 24)
                            .foregroundStyle(dj.fxTarget == target ? Color.white : Theme.dim)
                            .background(RoundedRectangle(cornerRadius: 3).fill(dj.fxTarget == target ? Theme.accent : Theme.raised))
                    }
                    .buttonStyle(.plain)
                }
            }
            Knob(value: $dj.fxLevel, range: 0...1, defaultValue: 0.5, label: "", size: 24)
            Menu {
                Picker("Effect", selection: $dj.fxType) {
                    ForEach(BeatFX.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(dj.fxType.rawValue).font(Theme.legend(11, .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(width: 84, height: 24)
                .background(RoundedRectangle(cornerRadius: 3).fill(Theme.raised))
            }
            HStack(spacing: 0) {
                Button { step(-1) } label: { Image(systemName: "chevron.left").frame(width: 22, height: 24) }
                Text(beatLabel(dj.fxBeats))
                    .font(Theme.readout(12, .medium))
                    .frame(minWidth: 30)
                Button { step(1) } label: { Image(systemName: "chevron.right").frame(width: 22, height: 24) }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .buttonStyle(.plain)
            ToggleChip(title: "ON", isOn: dj.fxOn, height: 24) { dj.fxOn.toggle() }
        }
        .fixedSize()
    }

    private func step(_ direction: Int) {
        let choices = DJEngine.fxBeatChoices
        let i = choices.firstIndex(of: dj.fxBeats) ?? 2
        dj.fxBeats = choices[min(choices.count - 1, max(0, i + direction))]
    }
}

/// rekordbox's bottom row: headphones on the left, the crossfader under the mixer,
/// master level and recording on the right.
struct BottomBar: View {
    @Environment(DJEngine.self) private var dj
    var crossfaderWidth: CGFloat
    @State private var confirmStopRecording = false

    var body: some View {
        @Bindable var dj = dj
        HStack(spacing: 8) {
            Image(systemName: "headphones").font(.system(size: 14)).foregroundStyle(Theme.dim)
            Knob(value: $dj.headphoneMix, range: 0...1, defaultValue: 0.25, label: "", size: 24)
            legend("MIX")
            Knob(value: $dj.headphoneVolume, range: 0...1, defaultValue: 0.8, label: "", size: 24)
            legend("LEVEL")
            ToggleChip(title: "SPLIT", isOn: dj.splitCue, height: 24) { dj.splitCue.toggle() }
            Spacer(minLength: crossfaderWidth + 40)
            legend("MASTER")
            Knob(value: $dj.masterVolume, range: 0...1, defaultValue: 0.9, label: "", size: 24)
            LevelMeter(level: dj.masterLevel, horizontal: true).frame(width: 80, height: 7)
            recordButton
        }
        .overlay {
            HStack(spacing: 6) {
                legend("1")
                Crossfader(value: $dj.crossfader).frame(width: crossfaderWidth)
                legend("2")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(Theme.panel)
    }

    private func legend(_ text: String) -> some View {
        Text(text).font(Theme.legend(10)).foregroundStyle(Theme.dim)
    }

    /// Stopping asks first, so a stray tap can't end a set's recording.
    private var recordButton: some View {
        Button {
            if dj.isRecording { confirmStopRecording = true } else { dj.toggleRecording() }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(dj.isRecording ? Color.red : Color.red.opacity(0.45)).frame(width: 12, height: 12)
                if let started = dj.recordingStarted {
                    Text(started, style: .timer).font(Theme.readout(12))
                    if !dj.setlist.isEmpty {
                        Text("· \(dj.setlist.count) tracks").font(Theme.legend(10)).foregroundStyle(Theme.dim)
                    }
                } else {
                    Text("REC").font(Theme.legend(11, .semibold))
                }
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 26)
            .background(RoundedRectangle(cornerRadius: 3).fill(Theme.raised))
        }
        .buttonStyle(.plain)
        .confirmationDialog("Stop recording?", isPresented: $confirmStopRecording, titleVisibility: .visible) {
            // It may have stopped by itself (storage full) while this was open; don't start a new one.
            Button("Stop and save", role: .destructive) { if dj.isRecording { dj.toggleRecording() } }
            Button("Keep recording", role: .cancel) {}
        }
    }
}
