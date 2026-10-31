import SwiftUI

/// The performance screen: a top bar, both waveforms full width with the beat display between
/// them, and deck · mixer · deck below. The browser slides in over the decks, and the mixer stays
/// reachable beside it, so you can keep mixing while you pick the next track.
struct ContentView: View {
    @Environment(DJEngine.self) private var dj
    @Environment(Library.self) private var library
    @State var showLibrary = false
    @State private var keyboardHeight: CGFloat = 0
    /// With no music yet, the first thing to see is where to add some.
    var opensBrowserWhenEmpty = true

    var body: some View {
        GeometryReader { geo in
            let mixerWidth = min(236, max(176, geo.size.width * 0.186))
            let waveHeight = max(58, min(120, geo.size.height * 0.1))
            VStack(spacing: 3) {
                TopBar(showLibrary: $showLibrary)
                WaveformPanel(waveHeight: waveHeight)
                    .padding(.horizontal, 3)
                HStack(spacing: 3) {
                    if showLibrary {
                        VStack(spacing: 3) {
                            MiniDecks()
                            BrowserView()
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                // Only the list makes way for the keyboard; the mixer stays put.
                                .padding(.bottom, keyboardHeight)
                        }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    } else {
                        DeckPanel(deck: dj.decks[0])
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    // Stays the same view when the browser opens, so its meters and knobs carry on.
                    MixerPanel().frame(width: mixerWidth)
                    if !showLibrary {
                        DeckPanel(deck: dj.decks[1])
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 3)
                .padding(.bottom, 8)
            }
            .animation(Theme.panel, value: showLibrary)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                withAnimation(.easeOut(duration: 0.2)) { keyboardHeight = max(0, geo.size.height - frame.minY) }
            }
        }
        // The whole screen: nothing below here moves when the keyboard comes up, and the space by
        // the home indicator is too useful to leave empty. The indicator hides itself, and swipes
        // from that edge are deferred, so the first one doesn't leave the app.
        .ignoresSafeArea(.all, edges: .bottom)
        .background(Theme.chassis.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .environment(\.openBrowser, { showLibrary = true })
        .task {
            if opensBrowserWhenEmpty && library.tracks.isEmpty { showLibrary = true }
        }
    }
}

/// The two waveforms, framed by their overviews, with the beat display between them.
struct WaveformPanel: View {
    @Environment(DJEngine.self) private var dj
    var waveHeight: CGFloat

    var body: some View {
        VStack(spacing: 1) {
            OverviewWaveform(deck: dj.decks[0]).frame(height: 14)
            ScrollingWaveform(deck: dj.decks[0]).frame(height: waveHeight)
            PhaseStrip(decks: dj.decks, positions: { dj.positions }).frame(height: 8)
            ScrollingWaveform(deck: dj.decks[1]).frame(height: waveHeight)
            OverviewWaveform(deck: dj.decks[1]).frame(height: 14)
        }
        .background(Color.black)
        .displayWell(cornerRadius: 5)
        .overlay(alignment: .topLeading) { deckBadge(dj.decks[0]).offset(x: 4, y: 18) }
        .overlay(alignment: .bottomLeading) { deckBadge(dj.decks[1]).offset(x: 4, y: -18) }
        .overlay { BarCounters(decks: dj.decks, waveHeight: waveHeight) }
    }

    private func deckBadge(_ deck: Deck) -> some View {
        Text("\(deck.index + 1)")
            .font(Theme.digits(10))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: 14, height: 14)
            .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.black.opacity(0.65)))
            .allowsHitTesting(false)
    }
}

/// "16.4" and a phrase count beside each playhead, in the same spot rekordbox prints its bar count.
private struct BarCounters: View {
    let decks: [Deck]
    var waveHeight: CGFloat

    var body: some View {
        GeometryReader { geo in
            let x = geo.size.width * CGFloat(WaveformDisplay.playheadFraction)
            ForEach(decks, id: \.index) { deck in
                DeckClock(deck: deck) {
                    let text = label(deck)
                    // On a dark backing, so a loop or cue line running through it can't cut it in half.
                    Text(text)
                        .font(Theme.digits(10))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 3)
                        .background(Capsule().fill(Color.black.opacity(text.isEmpty ? 0 : 0.72)))
                        .fixedSize()
                        .position(x: x - 36, y: deck.index == 0 ? 14 + 1 + 8 : geo.size.height - 14 - 1 - waveHeight + 8)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func label(_ deck: Deck) -> String {
        guard deck.isLoaded, deck.bpm > 0 else { return "" }
        let here = deck.renderer.playhead
        // With sections worked out, the count is within the section, which is what you're mixing by.
        if let phrase = deck.phrase(atFrame: here) {
            let start = (deck.beatPosition(phrase.start * deck.sampleRate) / 4).rounded() * 4
            let beats = max(0, deck.beatPosition(here) - start)
            return "\(phrase.kind.rawValue) \(Int(beats / 4) + 1).\(Int(beats.truncatingRemainder(dividingBy: 4)) + 1)"
        }
        let beats = deck.beatPosition(here)
        guard beats >= 0 else { return "" }
        return "\(Int(beats / 4) + 1).\(Int(beats.truncatingRemainder(dividingBy: 4)) + 1) BARS"
    }
}

/// Shown above the browser in place of the full decks: enough to keep the mix running.
struct MiniDecks: View {
    @Environment(DJEngine.self) private var dj

    var body: some View {
        HStack(spacing: 3) {
            MiniDeck(deck: dj.decks[0])
            MiniDeck(deck: dj.decks[1])
        }
        .frame(height: 50)
    }
}

/// A deck, in one row. Tracks can be dragged straight onto it from the browser.
struct MiniDeck: View {
    @Environment(Library.self) private var library
    @Environment(DJEngine.self) private var dj
    @Bindable var deck: Deck
    @State private var targeted = false

    var body: some View {
        HStack(spacing: 6) {
            TransportButton(color: Theme.cue, lit: !deck.isPlaying && deck.isLoaded, accessibilityName: "Cue", onPress: deck.cueDown, onRelease: deck.cueUp) {
                Text("CUE").font(Theme.silk(9))
            }
            .frame(width: 34)
            TransportButton(color: Theme.play, lit: deck.isPlaying, accessibilityName: deck.isPlaying ? "Pause" : "Play", onPress: deck.togglePlay) {
                Image(systemName: deck.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 11, weight: .semibold))
            }
            .frame(width: 34)
            DeckHeader(deck: deck, compact: true)
            Key("SYNC", lit: deck.syncOn, size: 8.5, feel: .toggle, onPress: { dj.toggleSync(deck) })
                .frame(width: 36, height: 36)
        }
        .padding(4)
        .controlSurface()
        .overlay {
            if targeted {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 2)
                    .shadow(color: Theme.accent, radius: 6)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let first = items.first, let id = UUID(uuidString: first), let track = library.track(id) else { return false }
            return dj.load(track, onto: deck)
        } isTargeted: { targeted = $0 }
        .animation(.easeOut(duration: 0.12), value: targeted)
    }
}

/// The slim bar along the top: browser, recording, settings and the clock.
struct TopBar: View {
    @Environment(DJEngine.self) private var dj
    @Environment(Library.self) private var library
    @Binding var showLibrary: Bool
    @State private var showRecordings = false
    @State private var showSettings = false
    @State private var confirmStopRecording = false

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 5) {
            HStack(spacing: 4) {
                CheeksMark(size: 13)
                Text("cheeks").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 3)

            Key(color: Theme.accent, lit: showLibrary, feel: .toggle, accessibilityName: "Browser", onPress: { showLibrary.toggle() }) {
                HStack(spacing: 3) {
                    Image(systemName: "music.note.list").font(.system(size: 9, weight: .semibold))
                    Text("BROWSE").font(Theme.silk(8.5))
                }
            }
            .frame(width: 66, height: 20)

            recordKey

            Key(color: Theme.accent, accessibilityName: "Recordings", onPress: { showRecordings = true }) {
                Image(systemName: "waveform").font(.system(size: 9, weight: .semibold))
            }
            .frame(width: 26, height: 20)
            Spacer(minLength: 4)
            }
            .frame(maxWidth: .infinity)

            MasterTempo()

            // Laid out with the bar rather than floated over it, so it can't cover the tempo. Both
            // sides take the same width, which keeps the tempo in the middle of the screen.
            HStack(spacing: 5) {
            // On something with a size, because with no message showing the capsule has none.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay { StatusCapsule() }
            AnalysisIndicator()
            EngineLoad()
            TimelineView(.everyMinute) { context in
                Text(context.date, style: .time)
                    .font(Theme.digits(12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Key(color: Theme.accent, accessibilityName: "Settings", onPress: { showSettings = true }) {
                Image(systemName: "gearshape.fill").font(.system(size: 9))
            }
            .frame(width: 26, height: 20)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 6)
        .frame(height: 26)
        .sheet(isPresented: $showRecordings) { RecordingsView().environment(dj) }
        .sheet(isPresented: $showSettings) { SettingsView().environment(dj).environment(library) }
        // Here rather than on the pads, since both decks can be showing them at once.
        .sheet(isPresented: Binding(get: { dj.sampler.slotBeingEdited != nil }, set: { if !$0 { dj.sampler.slotBeingEdited = nil } })) {
            if let slot = dj.sampler.slotBeingEdited { SamplerSlotSheet(slot: slot).environment(dj) }
        }
        // An alert, because on this screen a confirmation dialog becomes a popover: its arrow points at
        // the middle of the bar, and it leaves out the cancel button.
        .alert("Stop recording?", isPresented: $confirmStopRecording) {
            Button("Keep recording", role: .cancel) {}
            // It may have stopped by itself (storage full) while this was open; don't start a new one.
            Button("Stop and save", role: .destructive) { if dj.isRecording { dj.toggleRecording() } }
        }
    }

    /// Stopping asks first, so a stray tap can't end a set's recording.
    private var recordKey: some View {
        Key(color: Theme.danger, lit: dj.isRecording, feel: .toggle, accessibilityName: dj.isRecording ? "Stop recording" : "Record", onPress: {
            if dj.isRecording {
                confirmStopRecording = true
            } else {
                dj.toggleRecording()
                if dj.isRecording { Haptics.shared.confirm() }
            }
        }) {
            HStack(spacing: 3) {
                Circle().fill(dj.isRecording ? Color.white : Theme.danger).frame(width: 7, height: 7)
                if let started = dj.recordingStarted {
                    Text(started, style: .timer).font(Theme.digits(10))
                    if !dj.setlist.isEmpty {
                        Text("· \(dj.setlist.count)").font(Theme.digits(9)).opacity(0.75)
                    }
                } else {
                    Text("REC").font(Theme.silk(8.5))
                }
            }
        }
        .frame(width: dj.isRecording ? 92 : 48, height: 20)
        .animation(Theme.panel, value: dj.isRecording)
    }
}

/// The tempo everything's locked to, in the centre of the bar.
private struct MasterTempo: View {
    @Environment(DJEngine.self) private var dj

    var body: some View {
        let master = dj.decks[dj.masterIndex]
        HStack(spacing: 5) {
            Text("MASTER \(master.index + 1)").silk(7.5, color: Theme.textTertiary)
            Text(master.bpm > 0 ? String(format: "%.2f", master.effectiveBPM) : "–")
                .font(Theme.digits(13))
                .foregroundStyle(master.bpm > 0 ? Theme.textPrimary : Theme.textTertiary)
                .frame(minWidth: 44, alignment: .leading)
        }
        .opacity(master.isLoaded ? 1 : 0.5)
    }
}

/// How hard the audio engine is working, as a pro app would show it. It only appears when it matters.
private struct EngineLoad: View {
    @Environment(DJEngine.self) private var dj

    var body: some View {
        if dj.loadWarning > 0 {
            Text("DSP \(dj.loadWarning)%")
                .silk(8, color: dj.loadWarning > 85 ? Theme.danger : Theme.warn)
        }
    }
}

private struct AnalysisIndicator: View {
    @Environment(Library.self) private var library

    var body: some View {
        if let analyzing = library.analyzing, let track = library.track(analyzing) {
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Analysing \(track.title)").font(Theme.text(9.5)).foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
            .frame(maxWidth: 170)
            .transition(.opacity)
        }
    }
}

/// Messages appear in a capsule that grows out of the top of the screen and tucks itself away again.
extension StatusKind {
    var symbol: String {
        switch self {
        case .done: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .refused: "hand.raised.fill"
        case .problem: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .done: Theme.play
        case .info: Theme.textSecondary
        case .refused: Theme.warn
        case .problem: Theme.danger
        }
    }
}

struct StatusCapsule: View {
    @Environment(DJEngine.self) private var dj

    var body: some View {
        Group {
            if let error = dj.engineError {
                capsule(error, symbol: StatusKind.problem.symbol, tint: StatusKind.problem.tint)
            } else if let message = dj.statusMessage {
                if dj.undoAction != nil {
                    capsule(message, symbol: "trash.circle.fill", tint: Theme.textSecondary)
                } else {
                    capsule(message, symbol: dj.statusKind.symbol, tint: dj.statusKind.tint)
                }
            } else if dj.savingRecordings > 0 {
                capsule("Saving your mix…", symbol: nil, tint: Theme.accent)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.74), value: dj.statusMessage)
        .animation(.spring(response: 0.42, dampingFraction: 0.74), value: dj.savingRecordings)
        .task(id: dj.statusMessage) {
            guard dj.statusMessage != nil else { return }
            // Undo stays around longer: you may need a moment to realise you want it.
            try? await Task.sleep(for: .seconds(dj.undoAction == nil ? 5 : 8))
            if !Task.isCancelled {
                dj.statusMessage = nil
                dj.undoAction = nil
            }
        }
    }

    private func capsule(_ text: String, symbol: String?, tint: Color) -> some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
                    .symbolEffect(.bounce, value: text)
            } else {
                ProgressView().controlSize(.mini)
            }
            Text(text).font(Theme.text(11.5, .medium)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.75)
            if dj.undoAction != nil {
                // A key like every other on this bar, acting on first contact. These sit right at
                // the screen's top edge, where a SwiftUI button didn't reliably get the tap.
                Key("UNDO", color: Theme.accent, size: 8.5, feel: .none, accessibilityName: "Undo", touchMargin: 6, onPress: {
                    Haptics.shared.confirm()
                    dj.performUndo()
                })
                .frame(width: 46, height: 18)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, dj.undoAction == nil ? 10 : 3)
        .frame(height: 24)
        .background(Capsule().fill(.black))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.6), radius: 8, y: 3)
        .transition(.asymmetric(insertion: .scale(scale: 0.5, anchor: .top).combined(with: .opacity),
                                removal: .scale(scale: 0.8, anchor: .top).combined(with: .opacity)))
    }
}
