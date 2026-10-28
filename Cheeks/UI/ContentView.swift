import SwiftUI

/// Landscape performance layout: waveforms on top, then deck · mixer · deck (or the browser).
struct ContentView: View {
    @Environment(DJEngine.self) private var dj
    @State private var showLibrary = false

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 6) {
                TopBar(showLibrary: $showLibrary)
                VStack(spacing: 4) {
                    ForEach(dj.decks, id: \.index) { deck in
                        WaveformStrip(deck: deck)
                    }
                }
                .frame(height: geo.size.height * (showLibrary ? 0.22 : 0.27))

                if showLibrary {
                    LibraryView()
                } else {
                    HStack(spacing: 6) {
                        DeckView(deck: dj.decks[0])
                        MixerView()
                            .frame(width: min(300, geo.size.width * 0.25))
                        DeckView(deck: dj.decks[1])
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

struct WaveformStrip: View {
    let deck: Deck

    var body: some View {
        HStack(spacing: 4) {
            Rectangle().fill(Theme.deckColors[deck.index]).frame(width: 3)
            VStack(spacing: 2) {
                ScrollingWaveform(deck: deck)
                OverviewWaveform(deck: deck).frame(height: 16)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct TopBar: View {
    @Environment(DJEngine.self) private var dj
    @Binding var showLibrary: Bool

    var body: some View {
        @Bindable var dj = dj
        HStack(spacing: 10) {
            Button { withAnimation(.snappy) { showLibrary.toggle() } } label: {
                Label(showLibrary ? "DECKS" : "BROWSE", systemImage: showLibrary ? "dial.medium" : "music.note.list")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.raised))
            }
            .buttonStyle(.plain)

            Text("CHEEKS").font(.system(size: 13, weight: .black, design: .rounded)).foregroundStyle(Theme.dim)

            if let error = dj.engineError {
                Text(error).font(.caption2).foregroundStyle(.red).lineLimit(1)
            }
            Spacer()

            Menu {
                Picker("Crossfader curve", selection: $dj.crossfaderCurve) {
                    ForEach(CrossfaderCurve.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
            } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 14, weight: .semibold))
            }

            Button { dj.toggleRecording() } label: {
                HStack(spacing: 5) {
                    Circle().fill(dj.isRecording ? Color.red : Color.red.opacity(0.4)).frame(width: 9, height: 9)
                    if let started = dj.recordingStarted {
                        Text(started, style: .timer).font(.system(size: 11, weight: .semibold, design: .monospaced))
                    } else {
                        Text("REC").font(.system(size: 11, weight: .bold))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Theme.raised))
            }
            .buttonStyle(.plain)

            TimelineView(.everyMinute) { context in
                Text(context.date, style: .time)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.dim)
            }
        }
        .frame(height: 30)
    }
}
