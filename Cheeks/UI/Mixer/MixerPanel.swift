import SwiftUI

/// The mixer, laid out like a two-channel DJM: channel strips on either side, master and headphone
/// controls down the middle, the meters between the faders, and the crossfader along the bottom.
struct MixerPanel: View {
    @Environment(DJEngine.self) private var dj

    var body: some View {
        @Bindable var dj = dj
        GeometryReader { geo in
            let knob = min(52, max(36, (geo.size.height - 170) / 6.3))
            let channelWidth = (geo.size.width - 14 - 44) / 2
            VStack(spacing: 4) {
                HStack(alignment: .top, spacing: 3) {
                    ChannelStrip(deck: dj.decks[0], knobSize: knob).frame(width: channelWidth)
                    centreColumn(knob: knob).frame(width: 44)
                    ChannelStrip(deck: dj.decks[1], knobSize: knob).frame(width: channelWidth)
                }
                .frame(maxHeight: .infinity)
                crossfaderSection
                    .frame(height: 40)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 5)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .controlSurface()
    }

    @ViewBuilder
    private func centreColumn(knob: CGFloat) -> some View {
        @Bindable var dj = dj
        VStack(spacing: 3) {
            Knob(value: $dj.masterVolume, range: 0...1, defaultValue: 0.9, label: "MASTER", color: Theme.textPrimary, size: min(40, knob * 0.92), scale: .unipolar)
            Rectangle().fill(Theme.silk).frame(height: 0.5).padding(.horizontal, 4).padding(.vertical, 1)
            Image(systemName: "headphones").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.legend)
            Knob(value: $dj.headphoneMix, range: 0...1, defaultValue: 0.25, label: "CUE/MST", color: Theme.textPrimary, size: 30, scale: .unipolar)
            Knob(value: $dj.headphoneVolume, range: 0...1, defaultValue: 0.8, label: "LEVEL", color: Theme.textPrimary, size: 30, scale: .unipolar)
            Key("SPLIT", lit: dj.splitCue, size: 8, feel: .toggle, onPress: { dj.splitCue.toggle() })
                .frame(height: 20)
                .padding(.top, 1)
            Key(color: dj.colorFX == .filter ? Theme.textPrimary : Theme.accent, lit: dj.colorFX != .filter,
                feel: .toggle, accessibilityName: "Color effect, \(dj.colorFX.rawValue.capitalized)", onPress: {
                let all = ColorEffect.allCases
                dj.colorFX = all[((all.firstIndex(of: dj.colorFX) ?? 0) + 1) % all.count]
            }) {
                // The arrows say it steps through effects, rather than switching the filter on and off.
                HStack(spacing: 0) {
                    KeyLegend(title: dj.colorFX.rawValue, size: 7.5)
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 6.5, weight: .bold))
                }
            }
            .frame(height: 20)
            .padding(.top, 1)
            Spacer(minLength: 2)
            LimiterLight()
            CentreMeters()
                .frame(maxHeight: .infinity)
        }
    }

    private var crossfaderSection: some View {
        @Bindable var dj = dj
        return HStack(spacing: 5) {
            Text("1").silk(9)
            CrossfaderControl(value: $dj.crossfader)
            Text("2").silk(9)
        }
    }
}

/// Lights when the master limiter is working, so you know to pull the trim down.
private struct LimiterLight: View {
    @Environment(DJEngine.self) private var dj

    var body: some View {
        let working = dj.limiterWorking
        HStack(spacing: 2) {
            Circle().fill(working ? Theme.danger : Theme.danger.opacity(0.14)).frame(width: 4, height: 4)
            Text("LIM").silk(7, color: working ? Theme.danger : Theme.textTertiary)
        }
    }
}

/// Channel 1, master left and right, channel 2: the row of LEDs between the faders.
private struct CentreMeters: View {
    @Environment(DJEngine.self) private var dj

    var body: some View {
        let decks = dj.decks
        HStack(spacing: 3) {
            LEDMeter { [decks[0].level] }.frame(width: 6)
            LEDMeter(bars: 2) { [dj.masterLevel, dj.masterLevelRight] }.frame(width: 14)
            LEDMeter { [decks[1].level] }.frame(width: 6)
        }
    }
}

struct ChannelStrip: View {
    @Bindable var deck: Deck
    var knobSize: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            Knob(value: $deck.trim, label: "TRIM", color: Theme.textPrimary, size: knobSize * 0.86)
            Knob(value: $deck.eqHigh, label: "HI", size: knobSize)
            Knob(value: $deck.eqMid, label: "MID", size: knobSize)
            Knob(value: $deck.eqLow, label: "LOW", size: knobSize)
            Knob(value: $deck.filter, label: deck.colorFX.rawValue, color: Theme.accent, size: knobSize)
            Key(color: Theme.accent, lit: deck.headphoneCue, feel: .toggle, accessibilityName: "Cue channel \(deck.index + 1)", onPress: { deck.headphoneCue.toggle() }) {
                HStack(spacing: 2) {
                    Image(systemName: "headphones").font(.system(size: 8, weight: .bold))
                    Text("CUE").font(Theme.silk(8.5))
                }
            }
            .frame(height: 22)
            .padding(.top, 2)
            ChannelFader(value: $deck.fader, label: "Channel \(deck.index + 1) fader")
                .frame(maxHeight: .infinity)
                .padding(.top, 3)
        }
    }
}
