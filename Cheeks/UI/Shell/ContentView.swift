import SwiftUI

/// The performance screen: a top bar, both waveforms full width with the beat display between
/// them, and deck · mixer · deck below. The browser slides in over the decks, and the mixer stays
/// reachable beside it, so you can keep mixing while you pick the next track.
struct ContentView: View {
    @Environment(DJEngine.self) private var dj
    @Environment(Library.self) private var library
    @State var showLibrary = false
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
                        }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        MixerPanel().frame(width: mixerWidth)
                    } else {
                        DeckPanel(deck: dj.decks[0])
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        MixerPanel().frame(width: mixerWidth)
                        DeckPanel(deck: dj.decks[1])
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 3)
                .padding(.bottom, 3)
            }
            .animation(Theme.panel, value: showLibrary)
        }
        .background(Theme.chassis.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .overlay(alignment: .top) { StatusCapsule().padding(.top, 2) }
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
            PhaseStrip(decks: dj.decks).frame(height: 8)
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
                TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                    Text(label(deck))
                        .font(Theme.digits(10))
                        .foregroundStyle(Theme.accent)
                        .shadow(color: .black, radius: 1.5)
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
            DeckHeader(deck: deck)
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
            MasterTempo()
            Spacer(minLength: 4)

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
        .padding(.horizontal, 6)
        .frame(height: 26)
        .sheet(isPresented: $showRecordings) { RecordingsView().environment(dj) }
        .sheet(isPresented: $showSettings) { SettingsView().environment(dj).environment(library) }
        .confirmationDialog("Stop recording?", isPresented: $confirmStopRecording, titleVisibility: .visible) {
            // It may have stopped by itself (storage full) while this was open; don't start a new one.
            Button("Stop and save", role: .destructive) { if dj.isRecording { dj.toggleRecording() } }
            Button("Keep recording", role: .cancel) {}
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
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let load = dj.cpuLoad
            if load > 0.6 {
                Text("DSP \(Int(load * 100))%")
                    .silk(8, color: load > 0.85 ? Theme.danger : Theme.warn)
            }
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
struct StatusCapsule: View {
    @Environment(DJEngine.self) private var dj

    var body: some View {
        Group {
            if let error = dj.engineError {
                capsule(error, symbol: "exclamationmark.triangle.fill", tint: Theme.danger)
            } else if let message = dj.statusMessage {
                capsule(message, symbol: dj.undoAction == nil ? "checkmark.circle.fill" : "trash.circle.fill",
                        tint: dj.undoAction == nil ? Theme.play : Theme.textSecondary)
            } else if dj.savingRecordings > 0 {
                capsule("Saving your mix…", symbol: nil, tint: Theme.accent)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.74), value: dj.statusMessage)
        .animation(.spring(response: 0.42, dampingFraction: 0.74), value: dj.savingRecordings)
        .task(id: dj.statusMessage) {
            guard dj.statusMessage != nil else { return }
            try? await Task.sleep(for: .seconds(5))
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
            Text(text).font(Theme.text(11.5, .medium)).foregroundStyle(.white).lineLimit(1)
            if dj.undoAction != nil {
                Button("Undo") {
                    Haptics.shared.confirm()
                    dj.performUndo()
                }
                .font(Theme.text(11.5, .semibold))
                .tint(Theme.accent)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(Capsule().fill(.black))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.6), radius: 8, y: 3)
        .frame(maxWidth: 520)
        .transition(.asymmetric(insertion: .scale(scale: 0.5, anchor: .top).combined(with: .opacity),
                                removal: .scale(scale: 0.8, anchor: .top).combined(with: .opacity)))
    }
}
