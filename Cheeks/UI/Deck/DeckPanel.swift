import SwiftUI

/// One deck, laid out like a DDJ's deck section with rekordbox's screen above it. The tempo fader
/// and CUE/PLAY sit at the screen's outer edge, under the thumbs; deck 2 is mirrored.
struct DeckPanel: View {
    @Bindable var deck: Deck
    private var mirrored: Bool { deck.index == 1 }

    var body: some View {
        GeometryReader { geo in
            let bottom = min(300, max(148, geo.size.height * 0.315))
            VStack(spacing: 4) {
                DeckHeader(deck: deck)
                    .frame(height: 44)
                jogBand
                bottomBand
                    .frame(height: bottom)
            }
            .padding(4)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .controlSurface()
        .overlay { loadingOverlay }
    }

    private var jogBand: some View {
        HStack(spacing: 5) {
            if mirrored {
                DeckKeys(deck: deck).frame(width: 66)
                JogSection(deck: deck)
                TempoSection(deck: deck).frame(width: 38)
            } else {
                TempoSection(deck: deck).frame(width: 38)
                JogSection(deck: deck)
                DeckKeys(deck: deck).frame(width: 66)
            }
        }
    }

    private var bottomBand: some View {
        HStack(spacing: 6) {
            if mirrored {
                PadSection(deck: deck)
                TransportSection(deck: deck).frame(width: 60)
            } else {
                TransportSection(deck: deck).frame(width: 60)
                PadSection(deck: deck)
            }
        }
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if deck.isLoading {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.ultraThinMaterial).opacity(0.85)
                VStack(spacing: 8) {
                    ProgressView().tint(Theme.accent)
                    Text("Loading").silk(9.5, color: Theme.textSecondary)
                }
            }
            .transition(.opacity)
        }
    }
}

/// CUE above PLAY, like a CDJ, at the bottom corner where the thumb rests.
struct TransportSection: View {
    let deck: Deck

    var body: some View {
        VStack(spacing: 7) {
            TransportButton(color: Theme.cue, lit: !deck.isPlaying && deck.isLoaded, accessibilityName: "Cue", onPress: deck.cueDown, onRelease: deck.cueUp) {
                Text("CUE").font(Theme.silk(12.5)).tracking(0.5)
            }
            TransportButton(color: Theme.play, lit: deck.isPlaying, accessibilityName: deck.isPlaying ? "Pause" : "Play", onPress: deck.togglePlay) {
                Image(systemName: deck.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace.downUp))
            }
        }
    }
}

/// The tempo fader with its range key and the current percentage.
struct TempoSection: View {
    @Bindable var deck: Deck

    var body: some View {
        VStack(spacing: 3) {
            Key(deck.tempoRange >= 100 ? "WIDE" : "±\(Int(deck.tempoRange))", size: 8.5, onPress: {
                let ranges: [Double] = [6, 10, 16, 100]
                deck.tempoRange = ranges[((ranges.firstIndex(of: deck.tempoRange) ?? 0) + 1) % ranges.count]
            })
            .frame(height: 19)
            TempoFader(deck: deck)
            Text(String(format: "%+.1f", deck.tempoRatioPercent))
                .font(Theme.digits(10))
                .foregroundStyle(deck.tempoRatioPercent == 0 ? Theme.textTertiary : Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// SYNC, MASTER, quantize, slip, key lock and key controls, stacked on the inner side of the jog.
struct DeckKeys: View {
    @Environment(DJEngine.self) private var dj
    @Bindable var deck: Deck

    var body: some View {
        VStack(spacing: 4) {
            Key("BEAT SYNC", lit: deck.syncOn, size: 8.5, feel: .toggle, onPress: {
                let wasOn = deck.syncOn
                dj.toggleSync(deck)
                if !wasOn && deck.syncOn { Haptics.shared.confirm() }
            })
            .frame(height: 32)
            Key("MASTER", color: Theme.cue, lit: dj.masterIndex == deck.index && deck.isLoaded, size: 8.5, feel: .toggle, onPress: { dj.setMaster(deck) })
                .frame(height: 22)
            Spacer(minLength: 2)
            jumpSection
            Spacer(minLength: 2)
            HStack(spacing: 3) {
                Key("Q", lit: deck.quantize, feel: .toggle, onPress: { deck.quantize.toggle() })
                Key("SLIP", lit: deck.slipMode, size: 8.5, feel: .toggle, onPress: { deck.slipMode.toggle() })
            }
            .frame(height: 24)
            HStack(spacing: 3) {
                Key("KEY", lit: deck.keyLock, size: 8.5, feel: .toggle, onPress: { deck.keyLock.toggle() })
                Key("REV", color: Theme.danger, lit: deck.reverse, size: 8.5, feel: .toggle, onPress: { deck.reverse.toggle() })
            }
            .frame(height: 24)
            Spacer(minLength: 2)
            keySection
        }
    }

    /// Beat jump: tap the number to change how far.
    private var jumpSection: some View {
        VStack(spacing: 2) {
            Text("BEAT JUMP").silk(7.5, color: Theme.textTertiary)
            HStack(spacing: 2) {
                Key(color: Theme.accent, accessibilityName: "Jump back", onPress: { deck.beatJump(-deck.jumpBeats) }) {
                    Image(systemName: "backward.end.fill").font(.system(size: 8))
                }
                Key(color: Theme.accent, accessibilityName: "Jump size", onPress: {
                    let sizes: [Double] = [1, 2, 4, 8, 16, 32]
                    deck.jumpBeats = sizes[((sizes.firstIndex(of: deck.jumpBeats) ?? 2) + 1) % sizes.count]
                }) {
                    Text(Format.beats(deck.jumpBeats)).font(Theme.digits(11))
                        .contentTransition(.numericText())
                        .animation(Theme.press, value: deck.jumpBeats)
                }
                .frame(width: 24)
                Key(color: Theme.accent, accessibilityName: "Jump forward", onPress: { deck.beatJump(deck.jumpBeats) }) {
                    Image(systemName: "forward.end.fill").font(.system(size: 8))
                }
            }
            .frame(height: 22)
        }
    }

    /// `‹ 8A +1 ›` and key sync, which moves this deck to the nearest compatible key.
    private var keySection: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Key(color: Theme.accent, accessibilityName: "Key down", onPress: { deck.keyShift = max(-12, deck.keyShift - 1) }) {
                    Image(systemName: "minus").font(.system(size: 9, weight: .bold))
                }
                Text(deck.keyShift == 0 ? "±0" : String(format: "%+d", deck.keyShift))
                    .font(Theme.digits(11))
                    .foregroundStyle(deck.keyShift == 0 ? Theme.textTertiary : Theme.accent)
                    .frame(width: 20)
                    .contentTransition(.numericText())
                    .animation(Theme.press, value: deck.keyShift)
                Key(color: Theme.accent, accessibilityName: "Key up", onPress: { deck.keyShift = min(12, deck.keyShift + 1) }) {
                    Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                }
            }
            .frame(height: 22)
            Key("KEY SYNC", size: 8.5, feel: .toggle, onPress: {
                deck.keySync(to: dj.master(for: deck))
            })
            .frame(height: 20)
        }
    }
}

/// The big platter with its display: time left, tempo and key on the turning label.
struct JogSection: View {
    @Bindable var deck: Deck

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            JogPlatter(deck: deck)
                .frame(width: side, height: side)
                .overlay {
                    JogReadout(deck: deck, radius: side / 2)
                        .allowsHitTesting(false)
                }
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Jog wheel")
    }
}

/// The readouts on the jog's centre display.
struct JogReadout: View {
    @Bindable var deck: Deck
    var radius: CGFloat

    var body: some View {
        let unit = radius / 100
        if deck.isLoaded {
            readouts(unit)
        } else {
            VStack(spacing: 1 * unit) {
                Text("\(deck.index + 1)").font(Theme.digits(34 * unit)).foregroundStyle(Theme.textTertiary)
                Text("NO TRACK").silk(8.5 * unit, color: Theme.textTertiary)
            }
        }
    }

    private func readouts(_ unit: CGFloat) -> some View {
        VStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                let remaining = deck.duration - deck.position
                Text(deck.isLoaded ? "-" + Format.tenths(remaining) : "--:--.-")
                    .font(Theme.digits(10.5 * unit))
                    .foregroundStyle(deck.isLoaded && remaining < 30 ? Theme.danger : Theme.textPrimary.opacity(0.85))
            }
            bpm(unit)
            HStack(spacing: 5 * unit) {
                Text(String(format: "%+.2f%%", deck.tempoRatioPercent))
                    .foregroundStyle(deck.tempoRatioPercent == 0 ? Theme.textPrimary.opacity(0.6) : Theme.textPrimary)
                if let key = deck.effectiveKey {
                    Text(key).foregroundStyle(Theme.keyColor(key))
                }
            }
            .font(Theme.digits(9.5 * unit))
        }
        .shadow(color: .black.opacity(0.9), radius: 2)
    }

    private func bpm(_ unit: CGFloat) -> some View {
        let text = deck.bpm > 0 ? String(format: "%.2f", deck.effectiveBPM) : "0.00"
        let parts = text.split(separator: ".")
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(String(parts[0])).font(Theme.digits(30 * unit))
            Text("." + String(parts.count > 1 ? parts[1] : "00")).font(Theme.digits(16 * unit))
        }
        .foregroundStyle(deck.syncOn ? Theme.accent : Color.white)
        .opacity(deck.bpm > 0 ? 1 : 0.3)
    }
}

/// The screen at the top of a deck: artwork, title and artist, key, BPM and time.
struct DeckHeader: View {
    @Environment(\.openBrowser) private var openBrowser
    @Bindable var deck: Deck

    var body: some View {
        HStack(spacing: 7) {
            DeckArt(deck: deck)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(deck.track?.title ?? "No track loaded")
                    .font(Theme.text(12.5, .semibold))
                    .foregroundStyle(deck.track == nil ? Theme.textTertiary : Theme.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(Theme.text(10.5))
                    .foregroundStyle(deck.loadError == nil ? Theme.textSecondary : Theme.danger)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            gridMenu
            times
        }
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .displayWell()
        // An empty deck's screen is a shortcut to the music.
        .contentShape(Rectangle())
        .onTapGesture {
            guard deck.track == nil else { return }
            Haptics.shared.key()
            openBrowser()
        }
    }

    private var subtitle: String {
        if let error = deck.loadError { return error }
        guard let track = deck.track else { return "Open the browser to load one" }
        return track.artist.isEmpty ? "Unknown artist" : track.artist
    }

    /// Tap the BPM to fix the beat grid.
    private var gridMenu: some View {
        Menu {
            Section("Beat grid") {
                Button("Double BPM", systemImage: "multiply") { deck.scaleBPM(2) }
                Button("Halve BPM", systemImage: "divide") { deck.scaleBPM(0.5) }
                Button("BPM + 0.1", systemImage: "plus") { deck.nudgeBPM(by: 0.1) }
                Button("BPM − 0.1", systemImage: "minus") { deck.nudgeBPM(by: -0.1) }
                Button("Grid 10 ms earlier", systemImage: "arrow.left") { deck.shiftGrid(milliseconds: -10) }
                Button("Grid 10 ms later", systemImage: "arrow.right") { deck.shiftGrid(milliseconds: 10) }
                Button("Set downbeat here", systemImage: "scope") { deck.setDownbeatHere() }
            }
            Button("Save cue as memory cue", systemImage: "bookmark") { deck.saveMemoryCue() }
        } label: {
            VStack(alignment: .trailing, spacing: 0) {
                Text(deck.bpm > 0 ? String(format: "%.2f", deck.bpm) : "–")
                    .font(Theme.digits(13))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 2) {
                    Text("BPM").silk(7.5, color: Theme.textTertiary)
                    Image(systemName: "chevron.down").font(.system(size: 6, weight: .bold)).foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(width: 42, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .disabled(!deck.isLoaded)
        .simultaneousGesture(TapGesture().onEnded { Haptics.shared.key() })
    }

    /// Remaining time large, elapsed small. The playhead isn't observed, so poll it.
    private var times: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let remaining = deck.duration - deck.position
            VStack(alignment: .trailing, spacing: 0) {
                Text(deck.isLoaded ? "-" + Format.tenths(remaining) : "–")
                    .font(Theme.digits(18))
                    .foregroundStyle(deck.isLoaded && remaining < 30 ? Theme.danger : Theme.textPrimary)
                Text(deck.isLoaded ? Format.tenths(deck.position) : " ")
                    .font(Theme.digits(9.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(width: 66, alignment: .trailing)
        }
    }
}

/// Track artwork, or a generated label when the file has none.
struct DeckArt: View {
    let deck: Deck

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3.5, style: .continuous)
        ZStack {
            if let art = deck.artwork {
                Image(decorative: art, scale: 1).resizable().aspectRatio(contentMode: .fill)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else if let track = deck.track {
                GeneratedArt(title: track.title)
            } else {
                shape.fill(Color(white: 0.09))
                Text("\(deck.index + 1)").font(Theme.digits(16)).foregroundStyle(Theme.textTertiary)
            }
        }
        .animation(.easeOut(duration: 0.25), value: deck.artwork != nil)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
    }
}

/// A two-tone sleeve for tracks without artwork, chosen from the title so it's always the same.
struct GeneratedArt: View {
    let title: String

    var body: some View {
        let color = Theme.label(for: title)
        LinearGradient(colors: [color, color.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                Text(String(title.prefix(1)).uppercased())
                    .font(Theme.silk(15))
                    .foregroundStyle(.white.opacity(0.85))
            }
    }
}

enum Format {
    static func tenths(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "--:--.-" }
        let t = Int(max(0, seconds) * 10)
        return String(format: "%02d:%02d.%d", t / 600, t / 10 % 60, t % 10)
    }

    static func beats(_ beats: Double) -> String {
        if beats >= 1 { return beats == beats.rounded() ? "\(Int(beats))" : String(format: "%.2g", beats) }
        if abs(beats - 0.75) < 0.0001 { return "3/4" }
        return "1/\(Int((1 / beats).rounded()))"
    }
}
