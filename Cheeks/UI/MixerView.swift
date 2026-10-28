import SwiftUI

/// Two-channel DJ mixer: trim, 3-band EQ with kill, filter, faders, meters, crossfader and Beat FX.
struct MixerView: View {
    @Environment(DJEngine.self) private var dj

    var body: some View {
        @Bindable var dj = dj
        GeometryReader { geo in
            let knob = min(40, max(26, geo.size.height / 13))
            VStack(spacing: 6) {
                HStack(alignment: .top, spacing: 4) {
                    ChannelStrip(deck: dj.decks[0], knobSize: knob)
                    VStack(spacing: 6) {
                        Text("MASTER").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.dim)
                        LevelMeter(level: dj.masterLevel).frame(width: 8)
                        Knob(value: $dj.masterVolume, range: 0...1, defaultValue: 0.9, label: "VOL", size: knob * 0.8)
                    }
                    .frame(width: 34)
                    ChannelStrip(deck: dj.decks[1], knobSize: knob)
                }
                BeatFXPanel()
                Crossfader(value: $dj.crossfader)
                    .frame(height: 34)
            }
            .padding(8)
            .frame(width: geo.size.width, height: geo.size.height)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
        }
    }
}

struct ChannelStrip: View {
    @Bindable var deck: Deck
    var knobSize: CGFloat

    var body: some View {
        let color = Theme.deckColors[deck.index]
        VStack(spacing: 4) {
            Knob(value: $deck.trim, label: "TRIM", color: .gray, size: knobSize * 0.8)
            Knob(value: $deck.eqHigh, label: "HI", color: color, size: knobSize)
            Knob(value: $deck.eqMid, label: "MID", color: color, size: knobSize)
            Knob(value: $deck.eqLow, label: "LOW", color: color, size: knobSize)
            Knob(value: $deck.filter, label: "FILTER", color: .yellow, size: knobSize)
            HStack(spacing: 4) {
                LevelMeter(level: deck.level).frame(width: 6)
                VerticalFader(value: $deck.fader, color: color)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
    }
}

struct BeatFXPanel: View {
    @Environment(DJEngine.self) private var dj

    var body: some View {
        @Bindable var dj = dj
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                ForEach(BeatFX.allCases) { fx in
                    Button { dj.fxType = fx } label: {
                        Text(fx.rawValue)
                            .font(.system(size: 8, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, minHeight: 18)
                            .foregroundStyle(dj.fxType == fx ? Color.black : Theme.dim)
                            .background(RoundedRectangle(cornerRadius: 4).fill(dj.fxType == fx ? Color.white : Theme.raised))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 4) {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                Text(beatLabel(dj.fxBeats))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity)
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                Picker("Channel", selection: $dj.fxTarget) {
                    Text("1").tag(0)
                    Text("2").tag(1)
                    Text("1+2").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 84)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .bold))
            HStack(spacing: 6) {
                Knob(value: $dj.fxLevel, range: 0...1, defaultValue: 0.5, label: "LEVEL", color: .pink, size: 28)
                PadButton(dj.fxOn ? "FX ON" : "FX OFF", color: .pink, lit: dj.fxOn, onPress: { dj.fxOn.toggle() })
                    .frame(height: 34)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.3)))
    }

    private func step(_ direction: Int) {
        let choices = DJEngine.fxBeatChoices
        let i = choices.firstIndex(of: dj.fxBeats) ?? 2
        dj.fxBeats = choices[min(choices.count - 1, max(0, i + direction))]
    }
}
