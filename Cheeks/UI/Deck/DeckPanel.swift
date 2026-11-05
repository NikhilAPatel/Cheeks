import SwiftUI

/// One deck, laid out like a controller's deck section with a screen above it. The tempo fader
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
        .overlay { DeckLoadingOverlay(deck: deck) }
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
        .needsATrack(on: deck)
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

}

/// With no track there's nothing for these to act on. They look it, as hardware would be dark, and a press says why.
private struct NeedsATrack: ViewModifier {
    @Environment(DJEngine.self) private var dj
    let deck: Deck
    let unless: Bool

    func body(content: Content) -> some View {
        let isEmpty = !unless && !deck.isLoaded && !deck.isLoading
        content
            .opacity(isEmpty ? 0.45 : 1)
            .overlay {
                // Under `?`, what's under this can say what it's for.
                if isEmpty, !WhatsThis.shared.isOn {
                    TouchSurface(onDown: { _ in dj.say("There's no track on deck \(deck.index + 1) yet. Load one from the browser.", .refused) })
                }
            }
    }
}

extension View {
    func needsATrack(on deck: Deck, unless: Bool = false) -> some View {
        modifier(NeedsATrack(deck: deck, unless: unless))
    }
}

/// Covers a deck while its track loads.
struct DeckLoadingOverlay: View {
    let deck: Deck

    var body: some View {
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

/// CUE above PLAY, like a club deck, at the bottom corner where the thumb rests.
struct TransportSection: View {
    let deck: Deck

    var body: some View {
        VStack(spacing: 7) {
            TransportButton(color: Theme.cue, lit: !deck.isPlaying && deck.isLoaded, accessibilityName: "Cue", onPress: deck.cueDown, onRelease: deck.cueUp) {
                Text("CUE").font(Theme.silk(12.5)).tracking(0.5)
            }
            TransportButton(color: Theme.play, lit: deck.isPlayingOrAboutTo, accessibilityName: deck.isPlayingOrAboutTo ? "Pause" : "Play", onPress: deck.togglePlay) {
                Image(systemName: deck.isPlayingOrAboutTo ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace.downUp))
            }
        }
        .needsATrack(on: deck)
    }
}

/// The tempo fader with its range key and the current percentage.
struct TempoSection: View {
    @Bindable var deck: Deck

    var body: some View {
        VStack(spacing: 3) {
            Key(deck.tempoRange >= 100 ? "WIDE" : "±\(Int(deck.tempoRange))", size: 8.5, help: "Tempo range", onPress: deck.stepTempoRange)
            .frame(height: 19)
            TempoFader(deck: deck)
            Text(String(format: "%+.1f", deck.tempoRatioPercent))
                .font(Theme.digits(10))
                .foregroundStyle(deck.tempoRatioPercent == 0 ? Theme.textTertiary : Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .whatsThis("Tempo percent")
        }
    }
}

/// SYNC, MASTER, quantize, slip, key lock and key controls, stacked on the inner side of the jog.
struct DeckKeys: View {
    @Environment(DJEngine.self) private var dj
    @Environment(\.screenLayout) private var layout
    @Bindable var deck: Deck
    /// Two columns, for a deck too short to stack them: a phone held upright.
    var sideBySide = false

    var body: some View {
        if sideBySide {
            HStack(spacing: 4) {
                VStack(spacing: 4) {
                    syncKeys
                    Spacer(minLength: 2)
                    switches
                }
                VStack(spacing: 4) {
                    jumpSection
                    Spacer(minLength: 2)
                    keySection
                }
            }
        } else {
            VStack(spacing: 4) {
                syncKeys
                Spacer(minLength: 2)
                jumpSection
                Spacer(minLength: 2)
                switches
                Spacer(minLength: 2)
                keySection
            }
        }
    }

    @ViewBuilder
    private var syncKeys: some View {
        // SYNC on a phone's pads page and BEAT SYNC here were one control with two names.
        Key("SYNC", lit: deck.syncOn, size: 8.5, feel: .toggle, onPress: {
            let wasOn = deck.syncOn
            dj.toggleSync(deck)
            if !wasOn && deck.syncOn { Haptics.shared.confirm() }
        })
        // On the smallest phone on its side, the page was 8 pt taller than its room, and pressing JOG moved everything above it.
        .frame(height: layout == .landscape ? 26 : 32)
        Key("MASTER", color: Theme.cue, lit: dj.masterIndex == deck.index && deck.isLoaded, size: 8.5, feel: .toggle, onPress: { dj.setMaster(deck) })
            .frame(height: layout == .landscape ? 20 : 22)
    }

    /// Quantize, slip, key lock and reverse.
    @ViewBuilder
    private var switches: some View {
        HStack(spacing: 3) {
            // A deck with nothing on it has nothing lit, like hardware that's off.
            Key("Q", lit: deck.quantize && deck.isLoaded, feel: .toggle, onPress: { deck.quantize.toggle() })
            Key("SLIP", lit: deck.slipMode, size: 8.5, feel: .toggle, onPress: { deck.slipMode.toggle() })
        }
        .frame(height: 24)
        HStack(spacing: 3) {
            Key("KEY", lit: deck.keyLock && deck.isLoaded, size: 8.5, feel: .toggle, onPress: { deck.keyLock.toggle() })
            Key("REV", color: Theme.danger, lit: deck.reverse, size: 8.5, feel: .toggle, onPress: { deck.reverse.toggle() })
        }
        .frame(height: 24)
    }

    /// Beat jump: tap the number to change how far.
    private var jumpSection: some View {
        VStack(spacing: 2) {
            Text("BEAT JUMP").silk(7.5, color: Theme.textTertiary).whatsThis("BEAT JUMP")
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
                    .whatsThis("Key shift")
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
        .whatsThis("Jog wheel")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Jog wheel")
        .accessibilityHint(Explanations.named("Jog wheel")?.text ?? "")
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
                Text(deck.loadingTrack == nil ? "NO TRACK" : "LOADING").silk(8.5 * unit, color: Theme.textTertiary)
            }
        }
    }

    private func readouts(_ unit: CGFloat) -> some View {
        VStack(spacing: 0) {
            DeckClock(deck: deck) {
                let remaining = deck.timeLeft
                Text(deck.isLoaded ? Format.toGo(remaining) : "--:--.-")
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
    @Environment(\.screenLayout) private var layout
    @Bindable var deck: Deck
    /// Short of room above the browser: the title gets two lines, in place of the artist.
    var compact = false
    /// A phone's deck has no room for the artwork.
    var showsArt = true
    @State private var showCueList = false

    /// A phone on its side has little room here, and a title got broken mid-word: "Skyl / an…". The title's what you read.
    private var tight: Bool { layout == .landscape }

    /// The track on its way if there is one, so the old title doesn't sit there through the load.
    private var shownTrack: Track? { deck.loadingTrack ?? deck.track }

    var body: some View {
        HStack(spacing: 7) {
            if showsArt {
                DeckArt(deck: deck)
                    .frame(width: 34, height: 34)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(shownTrack?.title ?? "No track loaded")
                    .font(Theme.text(compact ? 11.5 : 12.5, .semibold))
                    .foregroundStyle(shownTrack == nil ? Theme.textTertiary : Theme.textPrimary)
                    .lineLimit(compact && stemsProgress == nil ? 2 : 1)
                if !compact || stemsProgress != nil {
                    // With the time left if there's room for it.
                    ViewThatFits(in: .horizontal) {
                        if compact, let stemsTimeLeft {
                            subtitleText((stemsProgress ?? "") + " · " + stemsTimeLeft)
                        }
                        subtitleText(compact ? stemsProgress ?? "" : subtitle)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .whatsThis("Track details")
            gridMenu.whatsThis("Beat grid")
            times.whatsThis("Time")
        }
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .displayWell()
        // An empty deck's screen is a shortcut to the music.
        .contentShape(Rectangle())
        .onTapGesture {
            guard deck.track == nil, !WhatsThis.shared.isOn else { return }
            Haptics.shared.key()
            openBrowser()
        }
        .sheet(isPresented: $showCueList) { CueListView(deck: deck).presentationDetents([.large]) }
    }

    private var subtitle: String {
        if let error = deck.loadError { return error }
        guard let track = shownTrack else { return "Open the browser to load one" }
        let artist = track.artist.isEmpty ? "Unknown artist" : track.artist
        guard let stemsProgress else { return artist }
        return [artist, stemsProgress, stemsTimeLeft].compactMap { $0 }.joined(separator: " · ")
    }

    private func subtitleText(_ text: String) -> some View {
        Text(text)
            .font(Theme.text(10.5))
            .foregroundStyle(deck.loadError == nil ? Theme.textSecondary : Theme.danger)
            .lineLimit(1)
    }

    /// Only ever a rough idea, and it's worked out afresh each time the percentage moves.
    private var stemsTimeLeft: String? {
        deck.stemsTimeLeft.map(Format.roughly)
    }

    /// The stems page shows this itself, so it's only needed from everywhere else.
    private var stemsProgress: String? {
        // During a load, that's still the last track's progress, under the new track's name.
        guard deck.padMode != .stems, !deck.isLoading, case .separating(let progress) = deck.stemStatus else { return nil }
        // 100% didn't fit on the small iPhone, for the moment it showed, and it isn't done until it's done.
        return "Stems " + (progress.map { "\(min(99, Int($0 * 100)))%" } ?? "waiting")
    }

    /// The tempo it's playing at, as the jog shows it. Tap it to fix the beat grid, which belongs to the
    /// track and so is labelled at the track's own speed.
    private var gridMenu: some View {
        Menu {
            // First, as it's what someone comes here in a hurry for. Last, it was below the fold on a phone on its side.
            if deck.tempo != 0 {
                Button("Back to Its Own Speed", systemImage: "arrow.uturn.backward") {
                    let was = deck.tempo, wasSynced = deck.syncOn
                    deck.backToOwnSpeed()
                    // It's under the finger that opened the menu, and a playing deck jumped from 140 to 148 with no word.
                    guard deck.isPlaying else { return }
                    deck.offerUndo?("Deck \(deck.index + 1)'s back at its own speed.", .info) {
                        deck.setTempo(was)
                        deck.syncOn = wasSynced
                    }
                }
            }
            Section("Beat grid: " + String(format: "%.2f", deck.bpm) + " BPM at normal speed") {
                // It's what the track's read as, and not its speed. "Halve BPM" sounds like a speed control.
                Button("Double the Reading", systemImage: "multiply") { deck.scaleBPM(2) }
                Button("Halve the Reading", systemImage: "divide") { deck.scaleBPM(0.5) }
                if deck.grid?.isVariable == true {
                    Button("Use one steady tempo", systemImage: "metronome") { deck.flattenGrid() }
                } else {
                    Button("BPM + 0.1", systemImage: "plus") { deck.nudgeBPM(by: 0.1) }
                    Button("BPM − 0.1", systemImage: "minus") { deck.nudgeBPM(by: -0.1) }
                }
                Button("Grid 10 ms earlier", systemImage: "arrow.left") { deck.shiftGrid(milliseconds: -10) }
                Button("Grid 10 ms later", systemImage: "arrow.right") { deck.shiftGrid(milliseconds: 10) }
                Button("Set downbeat here", systemImage: "scope") { deck.setDownbeatHere() }
            }
            Button("Save cue as memory cue", systemImage: "bookmark") { deck.saveMemoryCue() }
            Button("Cues and loops…", systemImage: "list.bullet") { showCueList = true }
        } label: {
            VStack(alignment: .trailing, spacing: 0) {
                Text(deck.isLoaded && deck.bpm > 0 ? String(format: "%.2f", deck.effectiveBPM) : "–")
                    .font(Theme.digits(13))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 2) {
                    // On a phone the tempo fader's on another page, and a deck stayed a third from its own speed with nothing to show it.
                    if compact, deck.isLoaded, abs(deck.tempo) >= 0.05 {
                        Text(String(format: "%+.1f%%", deck.tempo)).silk(7.5, color: Theme.accent).lineLimit(1).minimumScaleFactor(0.7)
                    } else {
                        Text("BPM").silk(7.5, color: Theme.textTertiary)
                    }
                    Image(systemName: "chevron.down").font(.system(size: 6, weight: .bold)).foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(width: 42, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .menuOrder(.fixed)
        .disabled(!deck.isLoaded || WhatsThis.shared.isOn)
        .simultaneousGesture(TapGesture().onEnded { Haptics.shared.key() })
        .accessibilityLabel("Beat grid")
        .accessibilityValue(deck.isLoaded && deck.bpm > 0 ? String(format: "%.2f BPM", deck.effectiveBPM) : "No track")
    }

    /// Remaining time large, elapsed small.
    private var times: some View {
        DeckClock(deck: deck) {
            let remaining = deck.timeLeft
            VStack(alignment: .trailing, spacing: 0) {
                Text(deck.isLoaded ? Format.toGo(remaining) : "–")
                    .font(Theme.digits(tight ? 12.5 : 18))
                    .foregroundStyle(deck.isLoaded && remaining < 30 ? Theme.danger : Theme.textPrimary)
                Text(deck.isLoaded ? Format.tenths(deck.position) : " ")
                    .font(Theme.digits(tight ? 8.5 : 9.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(width: tight ? 46 : 66, alignment: .trailing)
        }
    }
}

/// Redraws its content as the deck's clock moves, and not otherwise. A short `TimelineView` would do
/// the same, but keeps SwiftUI's display link running and re-renders its whole graph every frame.
struct DeckClock<Content: View>: View {
    @Environment(\.isOffstage) private var isOffstage
    let deck: Deck
    @ViewBuilder var content: () -> Content

    var body: some View {
        let _ = isOffstage ? 0 : deck.clockTenths
        content()
    }
}

/// Track artwork, or a generated label when the file has none.
struct DeckArt: View {
    let deck: Deck

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3.5, style: .continuous)
        ZStack {
            if deck.loadingTrack != nil {
                // Blank until the new track's art is known, so the old one doesn't sit beside the new title.
                shape.fill(Color(white: 0.09))
            } else if let art = deck.artwork {
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
    /// A time that's only ever a rough idea.
    static func roughly(_ seconds: Double) -> String {
        if seconds >= 90 { return "\(Int((seconds / 60).rounded())) min" }
        if seconds >= 45 { return "1 min" }
        // It sat at "5 s" for several seconds at the end of a split.
        if seconds < 7.5 { return "a moment" }
        return "\(Int((seconds / 5).rounded()) * 5) s"
    }

    /// "1 track", "2 tracks".
    static func count(_ number: Int, _ noun: String) -> String {
        "\(number.formatted()) \(noun)\(number == 1 ? "" : "s")"
    }

    /// Time left. With none left, there's nothing to take away from it.
    static func toGo(_ seconds: Double) -> String {
        (seconds.isFinite && seconds >= 0.1 ? "-" : "") + tenths(seconds)
    }

    static func tenths(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "--:--.-" }
        let t = Int(max(0, seconds) * 10)
        return String(format: "%02d:%02d.%d", t / 600, t / 10 % 60, t % 10)
    }

    static func beats(_ beats: Double) -> String {
        // %g turns a long loop into "1.3e+02".
        if beats >= 10 { return "\(Int(beats.rounded()))" }
        if beats >= 1 { return beats == beats.rounded() ? "\(Int(beats))" : String(format: "%.2g", beats) }
        if abs(beats - 0.75) < 0.0001 { return "3/4" }
        return "1/\(Int((1 / beats).rounded()))"
    }
}
