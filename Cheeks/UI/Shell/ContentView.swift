import SwiftUI

/// The performance screen: a top bar, both waveforms full width with the beat display between
/// them, and deck · mixer · deck below. The browser slides in over the decks, and the mixer stays
/// reachable beside it, so you can keep mixing while you pick the next track.
struct ContentView: View {
    @Environment(DJEngine.self) private var dj
    @Environment(Library.self) private var library
    @State var showLibrary = false
    @State private var browserBuilt = false
    @State private var keyboardHeight: CGFloat = 0
    /// With no music yet, the first thing to see is where to add some.
    var opensBrowserWhenEmpty = true

    var body: some View {
        GeometryReader { geo in
            let mixerWidth = min(236, max(176, geo.size.width * 0.186))
            let waveHeight = max(58, min(120, geo.size.height * 0.1))
            let layout = ScreenLayout(size: geo.size)
            Group {
            if layout.isCompact {
                CompactScreen(layout: layout, showLibrary: $showLibrary, browserBuilt: browserBuilt, keyboardHeight: keyboardHeight)
            } else {
            VStack(spacing: 3) {
                TopBar(showLibrary: $showLibrary)
                WaveformPanel(waveHeight: waveHeight)
                    .padding(.horizontal, 3)
                panels(width: geo.size.width - 6, mixerWidth: mixerWidth)
                    .padding(.horizontal, 3)
                    .padding(.bottom, 8)
            }
            .animation(Theme.panel, value: showLibrary)
            }
            }
            .environment(\.screenLayout, layout)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                withAnimation(.easeOut(duration: 0.2)) { keyboardHeight = max(0, geo.size.height - frame.minY) }
            }
        }
        // The whole screen: nothing below here moves when the keyboard comes up, and the space by
        // the home indicator is too useful to leave empty. The indicator hides itself, and swipes
        // from that edge are deferred, so the first one doesn't leave the app.
        .overlay { WhatsThisNote() }
        .ignoresSafeArea(.all, edges: .bottom)
        .background(Theme.chassis.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .environment(\.openBrowser, { showLibrary = true })
        .onReceive(NotificationCenter.default.publisher(for: SelfTour.openBrowser)) { _ in showLibrary = true }
        .onReceive(NotificationCenter.default.publisher(for: SelfTour.closeBrowser)) { _ in showLibrary = false }
        // An audition belongs to the browser. With nothing on screen to stop it, it would play on, through the master without a split cable.
        .onChange(of: showLibrary) { _, isOpen in
            if !isOpen, dj.previewingTrack != nil { dj.stopPreview() }
        }
        .task {
            if opensBrowserWhenEmpty && library.tracks.isEmpty { showLibrary = true }
            // Built while nothing's going on yet, so the first open is as quick as the rest.
            try? await Task.sleep(for: .seconds(1.5))
            browserBuilt = true
        }
    }

    /// The decks, the mixer, and the browser that takes the decks' place. Everything stays built and only moves out of
    /// sight (`offstage`), as building a screenful of views again was nearly all of what opening the browser cost.
    private func panels(width: CGFloat, mixerWidth: CGFloat) -> some View {
        let deck = (width - mixerWidth - 6) / 2
        let browser = width - mixerWidth - 3
        return ZStack(alignment: .leading) {
            Offstage(showLibrary, x: -deck - 3) {
                DeckPanel(deck: dj.decks[0])
            }
            .frame(width: deck)
            Offstage(showLibrary, x: deck + 3) {
                DeckPanel(deck: dj.decks[1])
            }
            .frame(width: deck)
            .offset(x: deck + mixerWidth + 6)
            if browserBuilt || showLibrary {
                Offstage(!showLibrary, x: -browser - 3) {
                    VStack(spacing: 3) {
                        MiniDecks()
                        BrowserView(isOpen: showLibrary, keyboardHeight: keyboardHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                }
                .frame(width: browser)
            }
            // Never out of sight when the browser opens, so its meters and knobs carry on.
            MixerPanel()
                .frame(width: mixerWidth)
                // Without this, SwiftUI hands an animating position down to every leaf, and redraws them on each frame.
                .geometryGroup()
                .offset(x: showLibrary ? browser + 3 : deck + 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct IsOffstageKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// This part of the screen is built but out of sight, so what it does by itself every frame or tenth of a second can stop.
    var isOffstage: Bool {
        get { self[IsOffstageKey.self] }
        set { self[IsOffstageKey.self] = newValue }
    }
}

/// A part of the screen that stays built while it's out of sight, ready to come straight back. It slides away, and then its
/// view leaves the window, so nothing can find it: VoiceOver and touch can't, and it isn't drawn. Its state and all it's built
/// from stay. That takes a controller of its own, as SwiftUI's own ways of hiding a view leave it where VoiceOver can find it.
struct Offstage<Content: View>: View {
    let isOffstage: Bool
    let x: CGFloat
    let y: CGFloat
    @ViewBuilder var content: () -> Content

    init(_ isOffstage: Bool, x: CGFloat = 0, y: CGFloat = 0, @ViewBuilder content: @escaping () -> Content) {
        self.isOffstage = isOffstage
        self.x = x
        self.y = y
        self.content = content
    }

    var body: some View {
        OffstageHost(isOffstage: isOffstage, content: content)
            .offset(x: isOffstage ? x : 0, y: isOffstage ? y : 0)
            .opacity(isOffstage ? 0 : 1)
            .allowsHitTesting(!isOffstage)
    }
}

private final class OffstageController: UIViewController {
    let host: UIHostingController<AnyView>
    private var leaving: DispatchWorkItem?

    init(rootView: AnyView) {
        host = UIHostingController(rootView: rootView)
        // What's around it has already allowed for the home indicator and the keyboard.
        host.safeAreaRegions = []
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        host.view.backgroundColor = .clear
        addChild(host)
        attach()
        host.didMove(toParent: self)
    }

    private func attach() {
        guard host.view.superview == nil else { return }
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
    }

    func update(isOffstage: Bool) {
        leaving?.cancel()
        leaving = nil
        guard isOffstage else {
            attach()
            return
        }
        guard host.view.superview != nil else { return }
        // Once it's finished sliding. Built out of sight, this also gives a list time to make its first rows.
        let leave = DispatchWorkItem { [weak host] in host?.view.removeFromSuperview() }
        leaving = leave
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: leave)
    }
}

private struct OffstageHost<Content: View>: UIViewControllerRepresentable {
    let isOffstage: Bool
    let content: () -> Content

    func makeUIViewController(context: Context) -> OffstageController {
        OffstageController(rootView: rooted(context))
    }

    func updateUIViewController(_ controller: OffstageController, context: Context) {
        controller.host.rootView = rooted(context)
        controller.update(isOffstage: isOffstage)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: OffstageController, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    /// The view hosted, with everything it would have had if it weren't hosted.
    private func rooted(_ context: Context) -> AnyView {
        AnyView(content().environment(\.isOffstage, isOffstage).environment(\.self, context.environment))
    }
}

/// The two waveforms, framed by their overviews, with the beat display between them.
struct WaveformPanel: View {
    @Environment(DJEngine.self) private var dj
    var waveHeight: CGFloat
    var overviewHeight: CGFloat = 14
    var phaseHeight: CGFloat = 8

    var body: some View {
        VStack(spacing: 1) {
            OverviewWaveform(deck: dj.decks[0]).frame(height: overviewHeight).whatsThis("Overview")
            ScrollingWaveform(deck: dj.decks[0]).frame(height: waveHeight).whatsThis("Waveform")
            PhaseStrip(decks: dj.decks, positions: { dj.positions }).frame(height: phaseHeight).whatsThis("Phase strip")
            ScrollingWaveform(deck: dj.decks[1]).frame(height: waveHeight).whatsThis("Waveform")
            OverviewWaveform(deck: dj.decks[1]).frame(height: overviewHeight).whatsThis("Overview")
        }
        .background(Color.black)
        .displayWell(cornerRadius: 5)
        .overlay(alignment: .topLeading) { deckBadge(dj.decks[0]).offset(x: 4, y: overviewHeight + 4) }
        .overlay(alignment: .bottomLeading) { deckBadge(dj.decks[1]).offset(x: 4, y: -overviewHeight - 4) }
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

/// "16.4" and a phrase count beside each playhead, where a bar count usually goes.
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
            .needsATrack(on: deck)
            TransportButton(color: Theme.play, lit: deck.isPlayingOrAboutTo, accessibilityName: deck.isPlayingOrAboutTo ? "Pause" : "Play", onPress: deck.togglePlay) {
                Image(systemName: deck.isPlayingOrAboutTo ? "pause.fill" : "play.fill").font(.system(size: 11, weight: .semibold))
            }
            .frame(width: 34)
            .needsATrack(on: deck)
            DeckHeader(deck: deck, compact: true)
            Key("SYNC", lit: deck.syncOn, size: 8.5, feel: .toggle, onPress: { dj.toggleSync(deck) })
                .frame(width: 36, height: 36)
                .needsATrack(on: deck)
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
    @Environment(\.screenLayout) private var layout
    @Environment(DJEngine.self) private var dj
    @Environment(Library.self) private var library
    @Binding var showLibrary: Bool
    @State private var showRecordings = false
    @State private var showSettings = false
    @State private var confirmStopRecording = false

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 5) {
            if !layout.isCompact {
                HStack(spacing: 4) {
                    CheeksMark(size: 13)
                    Text("SEGUE DJ").font(Theme.silk(12)).tracking(1).foregroundStyle(Theme.textPrimary).fixedSize()
                }
                .padding(.horizontal, 3)
            }

            Key(color: Theme.accent, lit: showLibrary, feel: .toggle, accessibilityName: "Browser", actsDuringHelp: true, onPress: { showLibrary.toggle() }) {
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
                .overlay { if !layout.isCompact { StatusCapsule() } }
            AnalysisIndicator()
            if !layout.isCompact {
                TimelineView(.everyMinute) { context in
                    Text(context.date, style: .time)
                        .font(Theme.digits(12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            WhatsThisKey()
                .frame(width: 26, height: 20)
            Key(color: Theme.accent, accessibilityName: "Settings", onPress: { showSettings = true }) {
                Image(systemName: "gearshape.fill").font(.system(size: 9))
            }
            .frame(width: 26, height: 20)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 6)
        .frame(height: 26)
        // On a phone there's no room for a message in the bar, so it hangs just below it for its few seconds. On its side it
        // used to stay in the bar, and lost its second half, which is usually the part you act on.
        .overlay(alignment: .top) {
            if layout.isCompact { StatusCapsule().padding(.horizontal, 6).offset(y: 28) }
        }
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
        .whatsThis("Master tempo")
    }
}

/// How hard the audio engine is working, as a pro app would show it. It only appears when it matters.
private struct AnalysisIndicator: View {
    @Environment(Library.self) private var library
    @Environment(\.screenLayout) private var layout

    var body: some View {
        if let analyzing = library.analyzing, let track = library.track(analyzing) {
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                // Upright, there's only room left for "A…".
                if layout != .portrait { Text("Analysing \(track.title)").font(Theme.text(9.5)).foregroundStyle(Theme.textTertiary).lineLimit(1) }
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

    private var shown: (text: String, symbol: String?, tint: Color)? {
        if let error = dj.engineError { return (error, StatusKind.problem.symbol, StatusKind.problem.tint) }
        if let message = dj.statusMessage {
            return dj.undoAction != nil ? (message, "trash.circle.fill", Theme.textSecondary) : (message, dj.statusKind.symbol, dj.statusKind.tint)
        }
        return dj.savingRecordings > 0 ? ("Saving your mix…", nil, Theme.accent) : nil
    }

    var body: some View {
        ZStack {
            if let shown {
                capsule(shown.text, symbol: shown.symbol, tint: shown.tint)
                    .transition(.asymmetric(insertion: .scale(scale: 0.5, anchor: .top).combined(with: .opacity),
                                            removal: .scale(scale: 0.8, anchor: .top).combined(with: .opacity)))
            }
            // The key's touch is in a copy that's laid out the same and never moves, so a press lands
            // on it from the first frame, while the capsule's still arriving.
            if let shown, hasKeys {
                row(shown.text, symbol: shown.symbol, tint: shown.tint, touchOnly: true)
                    .transition(.identity)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.74), value: dj.statusMessage)
        .animation(.spring(response: 0.42, dampingFraction: 0.74), value: dj.savingRecordings)
        .task(id: dj.statusSerial) {
            guard dj.statusMessage != nil else { return }
            // One with keys stays around longer: you may need a moment to realise you want them.
            try? await Task.sleep(for: .seconds(hasKeys ? 8 : 5))
            if !Task.isCancelled { dj.statusMessage = nil }
        }
    }

    private func capsule(_ text: String, symbol: String?, tint: Color) -> some View {
        row(text, symbol: symbol, tint: tint, touchOnly: false)
            .background(Capsule().fill(.black))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.6), radius: 8, y: 3)
            // What's underneath still works. The keys' touches are in the copy over this.
            .allowsHitTesting(false)
    }

    private func row(_ text: String, symbol: String?, tint: Color, touchOnly: Bool) -> some View {
        HStack(spacing: 6) {
            Group {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
                        .symbolEffect(.bounce, value: text)
                } else {
                    ProgressView().controlSize(.mini)
                }
                Text(text).font(Theme.text(11.5, .medium)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.75)
            }
            .opacity(touchOnly ? 0 : 1)
            if dj.undoAction != nil {
                if touchOnly {
                    Color.clear.frame(width: 46, height: 18).overlay {
                        TouchSurface(onDown: { _ in undo() }).padding(-6)
                    }
                } else {
                    // A key like every other on this bar, acting on first contact. These sit right at
                    // the screen's top edge, where a SwiftUI button didn't reliably get the tap.
                    Key("UNDO", color: Theme.accent, size: 8.5, feel: .none, accessibilityName: "Undo", touchMargin: 6, onPress: undo)
                        .frame(width: 46, height: 18)
                }
            }
            if dj.rateAction != nil {
                rateKey(liked: true, touchOnly: touchOnly)
                rateKey(liked: false, touchOnly: touchOnly)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, hasKeys ? 3 : 10)
        .frame(height: 24)
        .accessibilityHidden(touchOnly)
    }

    /// As with Undo, the touch is in the copy that never moves. These two sit side by side, so they only reach past
    /// their edges up and down.
    @ViewBuilder
    private func rateKey(liked: Bool, touchOnly: Bool) -> some View {
        if touchOnly {
            Color.clear.frame(width: 30, height: 18).overlay {
                TouchSurface(onDown: { _ in rate(liked) }).padding(.vertical, -6).padding(.horizontal, -2)
            }
        } else {
            Key(color: Theme.accent, feel: .none, accessibilityName: liked ? "That was good" : "That wasn't good", onPress: { rate(liked) }) {
                Image(systemName: liked ? "hand.thumbsup.fill" : "hand.thumbsdown.fill").font(.system(size: 9, weight: .semibold))
            }
            .frame(width: 30, height: 18)
        }
    }

    private var hasKeys: Bool { dj.undoAction != nil || dj.rateAction != nil }

    private func rate(_ liked: Bool) {
        Haptics.shared.confirm()
        dj.rateAction?(liked)
    }

    private func undo() {
        Haptics.shared.confirm()
        dj.performUndo()
    }
}
