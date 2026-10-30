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
        .controlSurface()
    }
}

struct ChannelStrip: View {
    @Bindable var deck: Deck
    var knobSize: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            Text("CH \(deck.index + 1)")
                .font(Theme.legend(9, .bold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.75))
                .frame(maxWidth: .infinity, minHeight: 16)
                .displayWell(cornerRadius: 3)
            Knob(value: $deck.trim, label: "TRIM", color: Color(white: 0.75), size: knobSize * 0.85)
            Knob(value: $deck.eqHigh, label: "HIGH", size: knobSize)
            Knob(value: $deck.eqMid, label: "MID", size: knobSize)
            Knob(value: $deck.eqLow, label: "LOW", size: knobSize)
            Knob(value: $deck.filter, label: "FILTER", size: knobSize)
            Button { deck.headphoneCue.toggle() } label: {
                HStack(spacing: 3) {
                    Image(systemName: "headphones").font(.system(size: 9, weight: .bold))
                    Text("CUE").font(Theme.legend(10, .semibold)).tracking(0.4)
                }
                .frame(maxWidth: .infinity, minHeight: 26)
                .foregroundStyle(deck.headphoneCue ? Color.white : Theme.dim)
                .background(KeyCap(color: Theme.accent, lit: deck.headphoneCue))
            }
            .buttonStyle(.plain)
            // Meters sit between the two faders.
            HStack(spacing: 4) {
                if deck.index == 0 {
                    VerticalFader(value: $deck.fader)
                    DeckLevelMeter(deck: deck).frame(width: 5)
                } else {
                    DeckLevelMeter(deck: deck).frame(width: 5)
                    VerticalFader(value: $deck.fader)
                }
            }
            .padding(.top, 2)
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
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
            MasterMeter().frame(width: 80, height: 7)
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
        .controlSurface(cornerRadius: 0)
        // Carry the panel down behind the home indicator, so the screen doesn't end in a black strip.
        .background(Color(white: 0.075).ignoresSafeArea(edges: .bottom))
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
            .background(KeyCap())
        }
        .buttonStyle(.plain)
        .confirmationDialog("Stop recording?", isPresented: $confirmStopRecording, titleVisibility: .visible) {
            // It may have stopped by itself (storage full) while this was open; don't start a new one.
            Button("Stop and save", role: .destructive) { if dj.isRecording { dj.toggleRecording() } }
            Button("Keep recording", role: .cancel) {}
        }
    }
}

/// The master level, observed on its own so the meter can update without redrawing the bar.
struct MasterMeter: View {
    @Environment(DJEngine.self) private var dj

    var body: some View {
        LevelMeter(level: dj.masterLevel, horizontal: true)
    }
}
