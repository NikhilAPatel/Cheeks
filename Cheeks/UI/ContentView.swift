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
    @State private var showRecordings = false
    @State private var confirmStopRecording = false

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
            } else if let message = dj.statusMessage {
                Text(message).font(.caption2).foregroundStyle(Theme.dim).lineLimit(1)
            }
            if dj.savingRecordings > 0 {
                ProgressView().controlSize(.mini)
                Text("Saving mix…").font(.caption2).foregroundStyle(Theme.dim)
            }
            Spacer()

            Menu {
                Picker("Crossfader curve", selection: $dj.crossfaderCurve) {
                    ForEach(CrossfaderCurve.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                Picker("Recording format", selection: $dj.recordingFormat) {
                    ForEach(RecordingFormat.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 14, weight: .semibold))
            }

            Button { showRecordings = true } label: {
                Image(systemName: "waveform.badge.mic").font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)

            // Stopping asks first, so a stray tap can't end a set's recording.
            Button {
                if dj.isRecording { confirmStopRecording = true } else { dj.toggleRecording() }
            } label: {
                HStack(spacing: 5) {
                    Circle().fill(dj.isRecording ? Color.red : Color.red.opacity(0.4)).frame(width: 9, height: 9)
                    if let started = dj.recordingStarted {
                        Text(started, style: .timer).font(.system(size: 11, weight: .semibold, design: .monospaced))
                        if !dj.setlist.isEmpty {
                            Text("· \(dj.setlist.count) tracks").font(.system(size: 10)).foregroundStyle(Theme.dim)
                        }
                    } else {
                        Text("REC").font(.system(size: 11, weight: .bold))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Theme.raised))
            }
            .buttonStyle(.plain)
            .confirmationDialog("Stop recording?", isPresented: $confirmStopRecording, titleVisibility: .visible) {
                Button("Stop and save", role: .destructive) { dj.toggleRecording() }
                Button("Keep recording", role: .cancel) {}
            }

            TimelineView(.everyMinute) { context in
                Text(context.date, style: .time)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.dim)
            }
        }
        .frame(height: 30)
        .sheet(isPresented: $showRecordings) { RecordingsView().environment(dj) }
        .task(id: dj.statusMessage) {
            guard dj.statusMessage != nil else { return }
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { dj.statusMessage = nil }
        }
    }
}
