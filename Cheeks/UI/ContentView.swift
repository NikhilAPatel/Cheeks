import SwiftUI

/// Landscape performance layout after rekordbox: top bar with the FX unit, both zoomed waveforms,
/// then deck · mixer · deck (or the browser), and the headphone/crossfader/master row.
struct ContentView: View {
    @Environment(DJEngine.self) private var dj
    @State var showLibrary = false

    var body: some View {
        GeometryReader { geo in
            let mixerWidth = min(150, max(108, geo.size.width * 0.125))
            VStack(spacing: 3) {
                TopBar(showLibrary: $showLibrary)
                VStack(spacing: 2) {
                    ForEach(dj.decks, id: \.index) { deck in
                        WaveformStrip(deck: deck)
                    }
                }
                .frame(height: max(90, geo.size.height * 0.16))

                if showLibrary {
                    HStack(spacing: 3) {
                        DeckInfo(deck: dj.decks[0])
                        DeckInfo(deck: dj.decks[1])
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    LibraryView()
                } else {
                    HStack(spacing: 3) {
                        DeckView(deck: dj.decks[0])
                        MixerView()
                            .frame(width: mixerWidth)
                        DeckView(deck: dj.decks[1])
                    }
                }
                BottomBar(crossfaderWidth: min(260, geo.size.width * 0.25))
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

/// A zoomed waveform, rekordbox style: edge to edge, deck number in the corner.
struct WaveformStrip: View {
    let deck: Deck

    var body: some View {
        ScrollingWaveform(deck: deck)
            .overlay(alignment: .topLeading) {
                Text("\(deck.index + 1)")
                    .font(Theme.legend(10, .semibold))
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .allowsHitTesting(false)
            }
    }
}

struct TopBar: View {
    @Environment(DJEngine.self) private var dj
    @Binding var showLibrary: Bool
    @State private var showRecordings = false

    var body: some View {
        @Bindable var dj = dj
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "smallcircle.filled.circle").font(.system(size: 14, weight: .semibold))
                Text("cheeks").font(.system(size: 15, weight: .semibold))
            }
            .padding(.trailing, 6)

            iconButton("list.bullet.rectangle", on: showLibrary) { withAnimation(.snappy) { showLibrary.toggle() } }
            iconButton("waveform.badge.mic", on: false) { showRecordings = true }
            Menu {
                Picker("Crossfader curve", selection: $dj.crossfaderCurve) {
                    ForEach(CrossfaderCurve.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                Picker("Recording format", selection: $dj.recordingFormat) {
                    ForEach(RecordingFormat.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                iconLabel("gearshape", on: false)
            }

            Rectangle().fill(Theme.stroke).frame(width: 1, height: 20).padding(.horizontal, 4)
            FXUnit()

            if let error = dj.engineError {
                Text(error).font(.caption2).foregroundStyle(.red).lineLimit(1)
            } else if let message = dj.statusMessage {
                Text(message).font(.caption2).foregroundStyle(Theme.dim).lineLimit(1)
            }
            if dj.savingRecordings > 0 {
                ProgressView().controlSize(.mini)
                Text("Saving mix…").font(.caption2).foregroundStyle(Theme.dim)
            }
            Spacer(minLength: 4)

            TimelineView(.everyMinute) { context in
                Text(context.date, style: .time)
                    .font(Theme.readout(13, .medium))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Theme.panel)
        .sheet(isPresented: $showRecordings) { RecordingsView().environment(dj) }
        .task(id: dj.statusMessage) { [dj] in
            guard dj.statusMessage != nil else { return }
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { dj.statusMessage = nil }
        }
    }

    private func iconButton(_ symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { iconLabel(symbol, on: on) }
            .buttonStyle(.plain)
    }

    /// rekordbox's square toolbar icons: blue when the view they open is showing.
    private func iconLabel(_ symbol: String, on: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .medium))
            .frame(width: 32, height: 26)
            .foregroundStyle(on ? Color.white : Theme.dim)
            .background(RoundedRectangle(cornerRadius: 3).fill(on ? Theme.accent : Theme.raised))
    }
}
