import SwiftUI

/// Which arrangement of the performance screen fits. The full one needs the Duo unfolded or an iPad, and everything
/// else is a phone-sized screen held one way or the other.
enum ScreenLayout: Equatable {
    case full, landscape, portrait

    init(size: CGSize) {
        if size.width >= 900, size.height >= 600 {
            self = .full
        } else {
            self = size.width > size.height ? .landscape : .portrait
        }
    }

    var isCompact: Bool { self != .full }
}

private struct ScreenLayoutKey: EnvironmentKey {
    static let defaultValue = ScreenLayout.full
}

private struct CompactDeckStartsOnJogKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var screenLayout: ScreenLayout {
        get { self[ScreenLayoutKey.self] }
        set { self[ScreenLayoutKey.self] = newValue }
    }

    /// For the layout snapshots, which can't press anything.
    var compactDeckStartsOnJog: Bool {
        get { self[CompactDeckStartsOnJogKey.self] }
        set { self[CompactDeckStartsOnJogKey.self] = newValue }
    }
}

/// The performance screen on a phone: both waveforms, both decks' pads and a mixer, all still in reach. The jog and the
/// keys beside it are one tap away on each deck, and the controls you rarely touch mid-mix are in a sheet.
struct CompactScreen: View {
    @Environment(DJEngine.self) private var dj
    let layout: ScreenLayout
    @Binding var showLibrary: Bool
    var browserBuilt: Bool
    var keyboardHeight: CGFloat

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 2) {
                TopBar(showLibrary: $showLibrary)
                    .zIndex(1)
                // Both stay built, and only move out of sight, as with the full screen's panels.
                ZStack {
                    Offstage(showLibrary) {
                        if layout == .portrait {
                            portrait(size: geo.size)
                        } else {
                            landscape(size: geo.size)
                        }
                    }
                    if browserBuilt || showLibrary {
                        Offstage(!showLibrary, y: geo.size.height) {
                            BrowserView(isOpen: showLibrary, keyboardHeight: keyboardHeight)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .padding(.horizontal, 3)
                        }
                    }
                }
            }
            .padding(.bottom, 4)
            .animation(Theme.panel, value: showLibrary)
        }
    }

    private func landscape(size: CGSize) -> some View {
        VStack(spacing: 2) {
            WaveformPanel(waveHeight: max(24, min(50, size.height * 0.085)), overviewHeight: 9, phaseHeight: 5)
                .padding(.horizontal, 3)
            let mixer = min(190, max(156, size.width * 0.235))
            // Fixed widths, so nothing on a deck's page can ever push the screen sideways.
            let deck = (size.width - mixer - 10) / 2
            HStack(spacing: 2) {
                CompactDeck(deck: dj.decks[0]).frame(width: deck)
                CompactMixer(layout: .landscape).frame(width: mixer)
                CompactDeck(deck: dj.decks[1]).frame(width: deck)
            }
            .padding(.horizontal, 3)
        }
    }

    private func portrait(size: CGSize) -> some View {
        let width = size.width - 6
        let mixer = min(210, max(150, size.height * 0.22))
        return VStack(spacing: 2) {
            WaveformPanel(waveHeight: max(30, min(90, size.height * 0.07)), overviewHeight: 11, phaseHeight: 6)
            // Fixed heights, so one deck's page can never push the other off the screen.
            GeometryReader { geo in
                let deck = max(0, (geo.size.height - mixer - 4) / 2)
                VStack(spacing: 2) {
                    CompactDeck(deck: dj.decks[0], keysSideBySide: true).frame(width: width, height: deck)
                    CompactMixer(layout: .portrait).frame(height: mixer)
                    CompactDeck(deck: dj.decks[1], keysSideBySide: true).frame(width: width, height: deck)
                }
            }
        }
        .padding(.horizontal, 3)
    }
}

/// One deck on a phone: a line of track details, CUE and PLAY at the outer edge, and either the pads or the jog.
struct CompactDeck: View {
    @Environment(\.compactDeckStartsOnJog) private var startsOnJog
    @Environment(DJEngine.self) private var dj
    @Bindable var deck: Deck
    /// Upright, a deck is wide and short, so the keys beside the jog go in two columns.
    var keysSideBySide = false
    @State private var showJog = false
    private var mirrored: Bool { deck.index == 1 }

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                if mirrored {
                    pageKey
                    if !showJog { syncKey }
                }
                DeckHeader(deck: deck, compact: true, showsArt: false)
                if !mirrored {
                    if !showJog { syncKey }
                    pageKey
                }
            }
            .frame(height: 30)
            HStack(spacing: 4) {
                if mirrored {
                    page
                    TransportSection(deck: deck).frame(width: 50)
                } else {
                    TransportSection(deck: deck).frame(width: 50)
                    page
                }
            }
        }
        .padding(3)
        .controlSurface()
        .overlay { DeckLoadingOverlay(deck: deck) }
        .onAppear { if startsOnJog { showJog = true } }
    }

    /// It's the second thing anyone needs, so the pads page keeps it. The jog page has it among its keys.
    private var syncKey: some View {
        Key("SYNC", lit: deck.syncOn, size: 8, feel: .toggle, accessibilityName: "Beat sync, deck \(deck.index + 1)", help: "SYNC", onPress: { dj.toggleSync(deck) })
            .frame(width: keyWidth)
            .needsATrack(on: deck)
    }

    /// Swaps the pads for the jog and the keys beside it.
    private var pageKey: some View {
        Key(showJog ? "PADS" : "JOG", lit: showJog, size: 8, feel: .toggle, accessibilityName: showJog ? "Show pads, deck \(deck.index + 1)" : "Show jog, deck \(deck.index + 1)", help: "Deck page", actsDuringHelp: true, onPress: { showJog.toggle() })
            .frame(width: keyWidth)
    }

    /// On its side, what these give up goes to the track's title.
    private var keyWidth: CGFloat { keysSideBySide ? 38 : 32 }

    @ViewBuilder
    private var page: some View {
        if showJog {
            let keys = DeckKeys(deck: deck, sideBySide: keysSideBySide).frame(width: keysSideBySide ? 128 : 62)
            HStack(spacing: 4) {
                if mirrored {
                    keys
                    JogSection(deck: deck)
                    TempoSection(deck: deck).frame(width: 32)
                } else {
                    TempoSection(deck: deck).frame(width: 32)
                    JogSection(deck: deck)
                    keys
                }
            }
            .needsATrack(on: deck)
        } else {
            PadSection(deck: deck)
        }
    }
}

/// The mixer on a phone: EQ, filter, channel faders and the crossfader. TRIM, the master and headphone controls and
/// the Color FX choice are in a sheet.
struct CompactMixer: View {
    @Environment(DJEngine.self) private var dj
    let layout: ScreenLayout
    @State private var showMore = false

    var body: some View {
        @Bindable var dj = dj
        GeometryReader { geo in
            VStack(spacing: 2) {
                HStack(alignment: .top, spacing: 3) {
                    strip(dj.decks[0], in: geo.size)
                    centre
                    strip(dj.decks[1], in: geo.size)
                }
                .frame(maxHeight: .infinity)
                HStack(spacing: 4) {
                    Text("1").silk(8)
                    CrossfaderControl(value: $dj.crossfader)
                    Text("2").silk(8)
                }
                .frame(height: 28)
            }
            .padding(3)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .controlSurface()
        .sheet(isPresented: $showMore) { MixerMoreSheet().environment(dj) }
    }

    @ViewBuilder
    private func strip(_ deck: Deck, in size: CGSize) -> some View {
        if layout == .portrait {
            CompactStripWide(deck: deck, knobSize: max(26, min(36, (size.height - 44) / 2 - 10)))
        } else {
            // Two across, as wide as the strip allows, which leaves the fader most of the height.
            CompactStripTall(deck: deck, knobSize: max(20, min(34, ((size.width - 50) / 2 - 2) / 2 - 1)))
        }
    }

    private var centre: some View {
        VStack(spacing: 3) {
            AutoKey().frame(height: 22)
            // Not "MORE": the pad tabs have one of those, which does something else.
        Key("MIXER", color: Theme.accent, size: 7, accessibilityName: "More mixer controls", actsDuringHelp: true, onPress: { showMore = true })
                .frame(height: 22)
            LimiterLight()
            CentreMeters().frame(maxHeight: .infinity)
        }
        .frame(width: 38)
    }
}

/// A channel with its knobs in a square above its fader, for a phone on its side.
private struct CompactStripTall: View {
    @Bindable var deck: Deck
    var knobSize: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Knob(value: $deck.eqHigh, label: "HI", size: knobSize)
                Knob(value: $deck.eqMid, label: "MID", size: knobSize)
            }
            HStack(spacing: 2) {
                Knob(value: $deck.eqLow, label: "LOW", size: knobSize)
                Knob(value: $deck.filter, label: deck.colorFX.rawValue, color: Theme.accent, size: knobSize, help: "Color knob")
            }
            CueChannelKey(deck: deck).frame(height: 18)
            ChannelFader(value: $deck.fader, label: "Channel \(deck.index + 1) fader")
                .frame(maxHeight: .infinity)
        }
    }
}

/// A channel with its knobs in a square beside its fader, for a phone held upright.
private struct CompactStripWide: View {
    @Bindable var deck: Deck
    var knobSize: CGFloat

    var body: some View {
        HStack(spacing: 3) {
            if deck.index == 1 { faderColumn }
            VStack(spacing: 1) {
                HStack(spacing: 2) {
                    Knob(value: $deck.eqHigh, label: "HI", size: knobSize)
                    Knob(value: $deck.eqMid, label: "MID", size: knobSize)
                }
                HStack(spacing: 2) {
                    Knob(value: $deck.eqLow, label: "LOW", size: knobSize)
                    Knob(value: $deck.filter, label: deck.colorFX.rawValue, color: Theme.accent, size: knobSize, help: "Color knob")
                }
            }
            if deck.index == 0 { faderColumn }
        }
    }

    private var faderColumn: some View {
        VStack(spacing: 2) {
            CueChannelKey(deck: deck).frame(height: 20)
            ChannelFader(value: $deck.fader, label: "Channel \(deck.index + 1) fader")
                .frame(maxHeight: .infinity)
        }
    }
}

private struct CueChannelKey: View {
    @Environment(DJEngine.self) private var dj
    @Bindable var deck: Deck

    var body: some View {
        Key(color: Theme.accent, lit: deck.headphoneCue, feel: .toggle, accessibilityName: "Cue channel \(deck.index + 1)", help: "Cue channel", onPress: { dj.toggleCue(deck) }) {
            Image(systemName: "headphones").font(.system(size: 8, weight: .bold))
        }
    }
}

/// What doesn't fit on a phone's mixer.
struct MixerMoreSheet: View {
    @Environment(DJEngine.self) private var dj
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var dj = dj
        @Bindable var one = dj.decks[0]
        @Bindable var two = dj.decks[1]
        VStack(spacing: 14) {
            HStack {
                Text("Mixer").font(Theme.text(15, .semibold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("Done") { dismiss() }
                    .font(Theme.text(15, .semibold))
                    .foregroundStyle(Theme.accent)
            }
            HStack(alignment: .top, spacing: 18) {
                Knob(value: $one.trim, label: "TRIM 1", color: Theme.textPrimary, size: 40, help: "TRIM")
                Knob(value: $two.trim, label: "TRIM 2", color: Theme.textPrimary, size: 40, help: "TRIM")
                Knob(value: $dj.masterVolume, range: 0...1, defaultValue: 0.9, label: "MASTER", color: Theme.textPrimary, size: 40, scale: .unipolar, help: "Master volume")
                Knob(value: $dj.headphoneMix, range: 0...1, defaultValue: 0.25, label: "CUE/MST", color: Theme.textPrimary, size: 40, scale: .unipolar)
                Knob(value: $dj.headphoneVolume, range: 0...1, defaultValue: 0.8, label: "LEVEL", color: Theme.textPrimary, size: 40, scale: .unipolar)
            }
            HStack(spacing: 8) {
                Key("SPLIT", lit: dj.splitCue, size: 9, feel: .toggle, onPress: { dj.splitCue.toggle() })
                    .frame(width: 110)
                Key(color: dj.colorFX == .filter ? Theme.textPrimary : Theme.accent, lit: dj.colorFX != .filter,
                    feel: .toggle, accessibilityName: "Color effect, \(dj.colorFX.rawValue.capitalized)", help: "Color effect", onPress: {
                    let all = ColorEffect.allCases
                    dj.colorFX = all[((all.firstIndex(of: dj.colorFX) ?? 0) + 1) % all.count]
                }) {
                    HStack(spacing: 3) {
                        KeyLegend(title: dj.colorFX.rawValue, size: 9)
                        Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 8, weight: .bold))
                    }
                }
                .frame(width: 110)
            }
            .frame(height: 34)
            Spacer(minLength: 0)
        }
        .padding(16)
        // Over the sheet as well: the one on the screen's underneath it.
        .overlay { WhatsThisNote() }
        .presentationDetents([.medium])
        .background(Theme.chassis)
        .preferredColorScheme(.dark)
    }
}
