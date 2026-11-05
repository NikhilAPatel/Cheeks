import SwiftUI
import UIKit

/// `?` on the top bar: while it's on, touching a control says what it does and doesn't do it, so a question can't change
/// the mix. There's no hover on a touch screen, and a long press can't be it either, as a performance control acts on first
/// contact. The music carries on, and what moves from page to page still does, so every page can be asked about.
///
/// It's here rather than in the environment, because it has to reach across the `Offstage` hosts, and nothing but
/// turning it on and off gets observed.
@MainActor @Observable
final class WhatsThis {
    static let shared = WhatsThis()

    private(set) var isOn = false
    private(set) var shown = Explanations.opening
    /// Where the last touch was, as a fraction of the window. The note goes where that wasn't.
    private(set) var touch = CGPoint(x: 0.25, y: 0.75)
    /// The mixer's sheet has a note of its own, in the room below its controls. The screen's would show as well, on a phone's side.
    private(set) var isInSheet = false

    init() {
        // Coming back to a screen that won't respond, hours later, would look broken.
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isOn = false }
        }
    }

    func toggle() {
        isOn.toggle()
        shown = Explanations.opening
        touch = CGPoint(x: 0.25, y: 0.75)
        if isOn { announce() }
    }

    /// A touch on something that only explains itself while this is on.
    func explain(_ name: String, at point: CGPoint) {
        touch = point
        shown = Explanations.named(name) ?? Explanation(title: name.uppercased(), text: Explanations.missing)
        Haptics.shared.key()
        announce()
    }

    /// For what moves between pages, which goes on working: it says what it did as well.
    func note(_ name: String) {
        guard isOn else { return }
        shown = Explanations.named(name) ?? Explanation(title: name.uppercased(), text: Explanations.missing)
        announce()
    }

    func sheetOpened() { isInSheet = true }

    /// What it was saying was about something that's gone.
    func sheetClosed() {
        isInSheet = false
        shown = Explanations.opening
    }

    private func announce() {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: shown.title + ". " + shown.text)
    }
}

// MARK: Asking

extension View {
    /// Touching this while `?` is on says what it is, rather than doing what it does. `Key`, `Pad`, `TransportButton`,
    /// `Knob` and the faders have it built in, under their accessibility names, or their `help` where that changes.
    func whatsThis(_ name: String?, margin: CGFloat = 0) -> some View {
        modifier(WhatsThisSpot(name: name, margin: margin))
    }
}

private struct WhatsThisSpot: ViewModifier {
    let name: String?
    let margin: CGFloat

    func body(content: Content) -> some View {
        content.overlay {
            if WhatsThis.shared.isOn, let name {
                WhatsThisSurface(name: name).padding(-margin)
            }
        }
    }
}

private struct WhatsThisSurface: UIViewRepresentable {
    let name: String

    func makeUIView(context: Context) -> WhatsThisTouchView { WhatsThisTouchView() }

    func updateUIView(_ view: WhatsThisTouchView, context: Context) {
        view.name = name
    }
}

private final class WhatsThisTouchView: UIView {
    var name = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not used") }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let window else { return }
        let point = touch.location(in: window)
        WhatsThis.shared.explain(name, at: CGPoint(x: point.x / max(window.bounds.width, 1), y: point.y / max(window.bounds.height, 1)))
    }
}

// MARK: The key and the note

/// The `?` on the top bar. Once, as the first track arrives, it says what it's for.
struct WhatsThisKey: View {
    @Environment(DJEngine.self) private var dj
    @AppStorage("whatsThisHintShown") private var hintShown = false
    @AppStorage("swapTheLowsHintShown") private var lowsHintShown = false

    var body: some View {
        let help = WhatsThis.shared
        Key(color: Theme.accent, lit: help.isOn, feel: .toggle, accessibilityName: "What does this do?", actsDuringHelp: true, onPress: {
            hintShown = true
            help.toggle()
        }) {
            Text("?").font(Theme.silk(11))
        }
        .onChange(of: dj.decks.contains { $0.isLoaded }) { _, loaded in
            // Not over something it's already saying: it can wait for the next track.
            guard loaded, !hintShown, dj.statusMessage == nil else { return }
            hintShown = true
            dj.say("It's on the deck: DECKS takes you there. New to this? Press ? and tap anything to see what it does. The gear has the whole guide.", .info)
        }
        .onChange(of: dj.decks.allSatisfy(\.isPlaying)) { _, both in
            // The crossfader works, so nothing suggests there's more to it. A first-time user mixed that way for 15 minutes,
            // until the guide mentioned the LOWs. Not during a move, which has it in hand.
            guard both, !lowsHintShown, dj.statusMessage == nil, dj.autoDJ.phase == .idle, dj.autoDJ.mixSet == nil else { return }
            lowsHintShown = true
            dj.say("Two basslines clash. Turn the new track's LOW down, and swap the two LOWs as you crossfade.", .info)
        }
    }
}

/// What's just been asked about. Touches go straight through it. It sits where the finger wasn't, and on a wide screen it
/// keeps to one side, which also keeps it off a Duo's crease.
struct WhatsThisNote: View {
    @Environment(DJEngine.self) private var dj
    /// A sheet's controls are along its top, so its note goes below them, wherever the finger was.
    var inSheet = false

    var body: some View {
        let help = WhatsThis.shared
        ZStack {
            if help.isOn, inSheet || !help.isInSheet {
                GeometryReader { geo in
                    let wide = geo.size.width > geo.size.height
                    note(help.shown)
                        .frame(width: inSheet ? geo.size.width - 16 : wide ? min(440, geo.size.width * 0.46) : geo.size.width - 16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: inSheet ? .bottom : alignment(wide: wide, touch: help.touch))
                        .padding(.horizontal, !inSheet && wide ? 8 : 0)
                        .padding(.top, inSheet ? 0 : 30)
                        .padding(.bottom, 14)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: help.isOn)
        .allowsHitTesting(false)
    }

    /// Messages hang from the top, and that's where the note went. It hid the end of "Deck 2 has stopped, and deck 1 is playing with
    /// the…", the most important one a first-time user got, and it had gone by the time they'd closed this.
    private func alignment(wide: Bool, touch: CGPoint) -> Alignment {
        let messageUp = dj.statusMessage != nil
        if wide {
            let side: HorizontalAlignment = touch.x > 0.5 ? .leading : .trailing
            return Alignment(horizontal: side, vertical: messageUp ? .bottom : .top)
        }
        return touch.y > 0.5 && !messageUp ? .top : .bottom
    }

    private func note(_ shown: Explanation) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(shown.title).font(Theme.silk(11)).tracking(0.5).foregroundStyle(Theme.accent)
            Text(shown.text).font(Theme.text(13)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.black))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.accent.opacity(0.7), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("whatsThisNote")
    }
}

// MARK: The guide in Settings

/// All the same notes, for reading through or searching, from Settings.
struct ControlsGuide: View {
    @State private var search = ""

    private var sections: [Explanations.Section] { Explanations.found(search) }

    var body: some View {
        List {
            if sections.isEmpty { ContentUnavailableView.search(text: search) }
            ForEach(sections, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.entries) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.title).font(Theme.silk(11)).tracking(0.5).foregroundStyle(Theme.accent)
                            Text(entry.text).font(Theme.text(13))
                        }
                        .padding(.vertical, 1)
                    }
                }
            }
        }
        .hardTopEdge()
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        .navigationTitle("What everything does")
        .navigationBarTitleDisplayMode(.inline)
        .keepsItsBar()
    }
}
