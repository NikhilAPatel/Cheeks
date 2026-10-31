import SwiftUI

/// The lower half of a deck: a row of controls for the current mode, the mode tabs, and the pads.
private struct OpenBrowserKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    /// Slides the browser in, from anywhere in the deck.
    var openBrowser: @MainActor () -> Void {
        get { self[OpenBrowserKey.self] }
        set { self[OpenBrowserKey.self] = newValue }
    }
}

struct PadSection: View {
    @Bindable var deck: Deck

    var body: some View {
        VStack(spacing: 4) {
            controlRow
                .frame(height: 24)
            PadTabs(deck: deck)
                .frame(height: 19)
            PadBank(deck: deck)
        }
    }

    @ViewBuilder
    private var controlRow: some View {
        switch deck.padMode {
        case .memory: MemoryControlRow(deck: deck)
        case .stems: StemControlRow(deck: deck)
        case .fx: FXControlRow(deck: deck)
        case .sampler: SamplerControlRow(deck: deck)
        default: LoopRow(deck: deck)
        }
    }
}

/// Loop in, out, reloop, and the auto-loop length.
struct LoopRow: View {
    let deck: Deck

    var body: some View {
        HStack(spacing: 3) {
            Key("IN", color: Theme.loop, lit: deck.loopInSet, size: 9, onPress: deck.loopIn)
            Key("OUT", color: Theme.loop, size: 9, onPress: deck.loopOut)
            Key(deck.loopActive ? "EXIT" : "RELOOP", color: Theme.loop, lit: deck.loopActive, size: 8.5) {
                deck.loopActive ? deck.exitLoop() : deck.reloop()
            }
            .frame(minWidth: 46)
            Spacer(minLength: 3)
            Key(color: Theme.loop, accessibilityName: "Halve loop", onPress: deck.halveLoop) {
                Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold))
            }
            .frame(width: 22)
            Key(color: Theme.loop, lit: deck.loopActive, accessibilityName: "Beat loop", onPress: { deck.toggleBeatLoop(deck.loopBeats) }) {
                Text(Format.beats(deck.loopBeats)).font(Theme.digits(12))
                    .contentTransition(.numericText())
                    .animation(Theme.press, value: deck.loopBeats)
            }
            .frame(width: 34)
            Key(color: Theme.loop, accessibilityName: "Double loop", onPress: deck.doubleLoop) {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
            }
            .frame(width: 22)
        }
    }
}

/// Pad modes, always one tap away. Real tabs rather than a menu, because you're changing mode mid-mix.
struct PadTabs: View {
    @Bindable var deck: Deck

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PadMode.allCases) { mode in
                let selected = deck.padMode == mode
                ZStack {
                    Text(mode.rawValue)
                        .font(Theme.silk(8.5))
                        .tracking(0.3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(selected ? Color.white : Theme.textTertiary)
                    VStack {
                        Spacer(minLength: 0)
                        Capsule().fill(selected ? Theme.accent : Color.clear)
                            .frame(height: 2)
                            .padding(.horizontal, 5)
                            .shadow(color: selected ? Theme.accent : .clear, radius: 3)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    TouchSurface(onDown: { _ in
                        guard deck.padMode != mode else { return }
                        Haptics.shared.toggle(true)
                        // No fade: pads on their way out still take touches, and would fire the old page.
                        deck.padMode = mode
                    })
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(mode.rawValue.capitalized + " pads")
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { deck.padMode = mode }
            }
            Key("DEL", color: Theme.danger, lit: deck.shift, size: 8, feel: .toggle, onPress: { deck.shift.toggle() })
                .frame(width: 30)
                .opacity(deck.padMode == .hotCue || deck.padMode == .memory ? 1 : 0.0)
                .allowsHitTesting(deck.padMode == .hotCue || deck.padMode == .memory)
        }
    }
}

/// The eight performance pads; six across two rows of twelve in FX mode, where there's more to choose from.
struct PadBank: View {
    @Environment(DJEngine.self) private var dj
    @Bindable var deck: Deck

    private let loopSizes: [Double] = [1.0 / 4, 1.0 / 2, 1, 2, 4, 8, 16, 32]
    private let rollSizes: [Double] = [1.0 / 16, 1.0 / 8, 1.0 / 4, 1.0 / 2, 1, 2, 4, 8]
    private let jumpSizes: [Double] = [1, 4, 16, 32]

    var body: some View {
        let columns = deck.padMode == .fx ? 6 : 4
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            ForEach(0..<2, id: \.self) { row in
                GridRow {
                    ForEach(0..<columns, id: \.self) { col in
                        pad(row * columns + col)
                            .id("\(deck.padMode.rawValue)-\(row * columns + col)")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pad(_ i: Int) -> some View {
        switch deck.padMode {
        case .hotCue: HotCuePad(deck: deck, slot: i)
        case .memory: MemoryPad(deck: deck, index: i)
        case .beatLoop:
            let size = loopSizes[i]
            sizePad(Format.beats(size), color: Theme.loop, lit: deck.loopActive && abs(deck.loopBeats - size) < 0.0001, name: "\(Format.beats(size)) beat loop") {
                deck.toggleBeatLoop(size)
            }
        case .roll:
            let size = rollSizes[i]
            sizePad(Format.beats(size), color: Color(red: 0.1, green: 0.8, blue: 0.95), lit: false, name: "\(Format.beats(size)) beat roll",
                    onPress: { deck.rollBegin(size) }, onRelease: deck.rollEnd)
        case .slicer:
            sizePad("\(i + 1)", color: Color(red: 0.6, green: 0.4, blue: 1), lit: false, name: "Slice \(i + 1)",
                    onPress: { deck.sliceBegin(i) }, onRelease: deck.sliceEnd)
        case .beatJump:
            let beats = jumpSizes[i % 4] * (i < 4 ? -1 : 1)
            Pad(color: Color(red: 0.2, green: 0.85, blue: 0.62), accessibilityName: "Jump \(Int(abs(beats))) beats \(beats < 0 ? "back" : "forward")", onPress: { deck.beatJump(beats) }) {
                HStack(spacing: 3) {
                    Image(systemName: beats < 0 ? "backward.end.fill" : "forward.end.fill").font(.system(size: 8))
                    Text(Format.beats(abs(beats))).font(Theme.digits(14))
                }
            }
        case .stems:
            let stem = Stem.allCases[i % 4]
            if i < 4 {
                StemPad(deck: deck, stem: stem)
            } else {
                let soloed = deck.stemsOn.indices.allSatisfy { deck.stemsOn[$0] == ($0 == stem.rawValue) }
                Pad(color: stem.color, lit: soloed, accessibilityName: "Solo \(stem.label.capitalized)", onPress: { deck.soloStem(stem) }) {
                    VStack(spacing: 0) {
                        Text("SOLO").font(Theme.silk(8)).opacity(0.8)
                        Text(stem.short).font(Theme.silk(11))
                    }
                }
            }
        case .fx:
            FXPad(deck: deck, effect: BeatFX.allCases[i])
        case .sampler:
            SamplerPad(slot: i, masterDeck: dj.masterIndex)
        }
    }

    private func sizePad(_ title: String, color: Color, lit: Bool, name: String,
                         onPress: @escaping @MainActor () -> Void, onRelease: @escaping @MainActor () -> Void = {}) -> some View {
        Pad(color: color, lit: lit, accessibilityName: name, onPress: onPress, onRelease: onRelease) {
            Text(title).font(Theme.digits(16))
        }
    }
}

/// A hot cue: lit in its colour when set, showing its letter and time. Pressing DEL first removes it.
struct HotCuePad: View {
    @Bindable var deck: Deck
    let slot: Int

    var body: some View {
        let time = deck.track?.hotCues[slot]
        let info = deck.track?.hotCueInfo[slot]
        let color = deck.hotCueColor(slot)
        let loopEnd = info?.loopEnd
        let looping = time.flatMap { start in loopEnd.map { deck.isCurrentLoop(start: start, end: $0) } } ?? false
        Pad(color: color, lit: time != nil, dimmed: time == nil,
            accessibilityName: time == nil ? "Set hot cue \(Theme.hotCueLetters[slot])" : "Hot cue \(Theme.hotCueLetters[slot])" + (info?.name.isEmpty == false ? ", \(info!.name)" : ""),
            onPress: { deck.hotCue(slot) }) {
            ZStack(alignment: .topLeading) {
                Color.clear
                HStack(spacing: 3) {
                    Text(Theme.hotCueLetters[slot])
                        .font(Theme.silk(12))
                    if loopEnd != nil {
                        Image(systemName: "repeat").font(.system(size: 8, weight: .bold))
                            .opacity(looping ? 1 : 0.7)
                    }
                }
                .padding(.leading, 6)
                .padding(.top, 4)
                if let time {
                    VStack {
                        Spacer(minLength: 0)
                        HStack {
                            Spacer(minLength: 0)
                            // A name says more than a time does, once you've gone to the trouble.
                            Text(info?.name.isEmpty == false ? info!.name : time.clockString)
                                .font(info?.name.isEmpty == false ? Theme.silk(9) : Theme.digits(10))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .foregroundStyle(Color.white.opacity(0.92))
                                .padding(.horizontal, 6)
                                .padding(.bottom, 4)
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
    }
}

// MARK: Memory

/// A saved cue or loop, called up with one tap. Red for cues and orange for loops, like the marks
/// they make on the waveform.
struct MemoryPad: View {
    @Bindable var deck: Deck
    let index: Int

    var body: some View {
        let items = deck.memoryItems
        let position = deck.memoryPage * Deck.memoryItemsPerPage + index
        if position < items.count {
            let item = items[position]
            Pad(color: color(item), lit: isOn(item), accessibilityName: description(item), onPress: { deck.pressMemory(item) }) {
                VStack(spacing: 1) {
                    Image(systemName: icon(item)).font(.system(size: 10, weight: .semibold))
                    Text(item.name.isEmpty ? item.time.clockString : item.name)
                        .font(item.name.isEmpty ? Theme.digits(10) : Theme.silk(9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 3)
                }
            }
        } else {
            Pad(color: Theme.textTertiary, dimmed: true, accessibilityName: "Empty", onPress: {}) { Color.clear }
        }
    }

    private func isOn(_ item: MemoryItem) -> Bool {
        switch item {
        case .cue(let cue): abs(deck.cuePoint - cue.time) < 0.01
        case .loop(let loop): deck.isCurrentLoop(start: loop.start, end: loop.end)
        }
    }

    private func color(_ item: MemoryItem) -> Color {
        switch item {
        case .cue(let cue): cue.color?.color ?? Theme.danger
        case .loop: Theme.loop
        }
    }

    private func icon(_ item: MemoryItem) -> String {
        switch item {
        case .cue: "bookmark.fill"
        case .loop(let loop): loop.activeOnLoad ? "repeat.circle.fill" : "repeat"
        }
    }

    private func description(_ item: MemoryItem) -> String {
        let name = item.name.isEmpty ? item.time.clockString : item.name
        switch item {
        case .cue: return "Memory cue, \(name)"
        case .loop: return "Saved loop, \(name)"
        }
    }
}

/// Saving, paging through what's saved, and the full list.
struct MemoryControlRow: View {
    @Bindable var deck: Deck
    @State private var showList = false

    var body: some View {
        HStack(spacing: 3) {
            Key("SAVE CUE", color: Theme.danger, size: 8, onPress: deck.saveMemoryCueHere)
            Key("SAVE LOOP", color: Theme.loop, size: 8, onPress: deck.saveCurrentLoop)
            Key(color: Theme.accent, accessibilityName: "Previous page", onPress: { page(-1) }) {
                Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold))
            }
            .frame(width: 20)
            Text("\(deck.memoryPage + 1)/\(deck.memoryPageCount)")
                .font(Theme.digits(10))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 24)
            Key(color: Theme.accent, accessibilityName: "Next page", onPress: { page(1) }) {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
            }
            .frame(width: 20)
            Key("LIST", color: Theme.accent, size: 8, onPress: { showList = true })
                .frame(width: 30)
        }
        .sheet(isPresented: $showList) { CueListView(deck: deck) }
    }

    private func page(_ step: Int) {
        deck.memoryPage = min(deck.memoryPageCount - 1, max(0, deck.memoryPage + step))
    }
}

// MARK: Stems

/// One stem. Tap to mute, instantly. Slide up or down to set its level. Its colour matches the
/// waveform, and its fill shows the level.
struct StemPad: View {
    @Bindable var deck: Deck
    let stem: Stem
    @State private var startLevel: Float?
    @State private var dragged = false
    @State private var lastStep: Int?
    @State private var toggledOnPress = false

    var body: some View {
        let on = deck.stemsOn[stem.rawValue]
        let level = deck.stemLevels[stem.rawValue]
        Pad(color: stem.color, lit: on, accessibilityName: stem.label.capitalized, onPress: {
            startLevel = level
            dragged = false
            lastStep = nil
            deck.toggleStem(stem)
        }, onRelease: {
            startLevel = nil
        }, onDrag: { translation in
            guard let startLevel else { return }
            if !dragged && abs(translation.height) > 8 {
                dragged = true
                // It was a slide, not a tap: put the mute back the way it was.
                deck.toggleStem(stem)
            }
            guard dragged else { return }
            let next = min(1, max(0, startLevel + Float(-translation.height / 70)))
            let step = Int(next * 10)
            if let lastStep, lastStep != step { Haptics.shared.tick() }
            lastStep = step
            deck.stemLevels[stem.rawValue] = next
        }) {
            ZStack(alignment: .bottom) {
                // The level, as a dark band coming down from the top of the lit pad.
                GeometryReader { geo in
                    Rectangle().fill(Color.black.opacity(on ? 0.34 : 0))
                        .frame(height: geo.size.height * CGFloat(1 - level))
                }
                .allowsHitTesting(false)
                VStack(spacing: 1) {
                    Image(systemName: stem.symbol).font(.system(size: 13, weight: .semibold))
                    Text(stem.label).font(Theme.silk(9)).tracking(0.3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

/// Quick stem combinations, and the state of the separation.
struct StemControlRow: View {
    @Bindable var deck: Deck

    var body: some View {
        HStack(spacing: 3) {
            Key("ACAPELLA", color: Stem.vocals.color, lit: only([.vocals]), size: 8, onPress: { deck.setStems([.vocals]) })
            Key("NO VOCAL", color: Stem.melody.color, lit: only([.melody, .bass, .drums]), size: 8, onPress: { deck.setStems([.melody, .bass, .drums]) })
            Key("BEAT", color: Stem.drums.color, lit: only([.drums, .bass]), size: 8, onPress: { deck.setStems([.drums, .bass]) })
            Key("ALL", color: Theme.accent, lit: false, size: 8, onPress: { deck.setStems(Set(Stem.allCases)) })
                .frame(width: 30)
            status
                .frame(width: 56)
        }
    }

    private func only(_ set: Set<Stem>) -> Bool {
        Stem.allCases.allSatisfy { deck.stemsOn[$0.rawValue] == set.contains($0) }
    }

    @ViewBuilder
    private var status: some View {
        switch deck.stemStatus {
        case .unavailable:
            Text("STEMS").silk(8, color: Theme.textTertiary)
        case .separating(let progress):
            VStack(spacing: 2) {
                Text(progress.map { "\(Int($0 * 100))%" } ?? "WAIT").font(Theme.digits(9)).foregroundStyle(Theme.textSecondary)
                ProgressView(value: progress ?? 0).tint(Theme.accent).scaleEffect(y: 0.6)
            }
        case .ready(let label):
            HStack(spacing: 3) {
                Circle().fill(Theme.play).frame(width: 5, height: 5)
                Text(label).silk(8.5, color: Theme.textSecondary)
            }
        case .tooLong:
            Text("TOO LONG").silk(8, color: Theme.danger)
        }
    }
}

// MARK: Sampler

/// A sound. What the press does depends on its mode: fire it, hold it, or start and stop a loop.
struct SamplerPad: View {
    @Environment(DJEngine.self) private var dj
    let slot: Int
    let masterDeck: Int

    var body: some View {
        let sampler = dj.sampler
        let setting = sampler.slots[slot]
        let recording = sampler.recordingSlot == slot
        // Lit for as long as it's sounding, so even a quick tap shows that it fired.
        Pad(color: recording ? Theme.danger : SampleBank.color(slot), lit: recording || sampler.looping.contains(slot) || sampler.sounding.contains(slot),
            accessibilityName: sampler.name(slot).capitalized, onPress: {
                if sampler.isSetting {
                    sampler.isSetting = false
                    sampler.slotBeingEdited = slot
                } else {
                    sampler.press(slot, masterDeck: masterDeck)
                }
            }, onRelease: {
                sampler.release(slot)
            }) {
            VStack(spacing: 1) {
                if setting.mode != .oneShot || recording {
                    Image(systemName: recording ? "record.circle.fill" : setting.mode == .loop ? "repeat" : "hand.point.up.left.fill")
                        .font(.system(size: 8, weight: .bold))
                }
                Text(sampler.name(slot))
                    .font(Theme.silk(9.5))
                    .tracking(0.3)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)
                    .padding(.horizontal, 3)
            }
        }
    }
}

/// SET picks a pad to change; the rest apply to all of them.
struct SamplerControlRow: View {
    @Environment(DJEngine.self) private var dj
    let deck: Deck

    var body: some View {
        @Bindable var sampler = dj.sampler
        HStack(spacing: 3) {
            if sampler.recordingSlot != nil {
                Key(color: Theme.danger, lit: true, accessibilityName: "Stop recording", onPress: { sampler.stopRecording() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "stop.fill").font(.system(size: 8))
                        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                            Text(sampler.recordedSeconds.clockString).font(Theme.digits(10))
                        }
                    }
                }
                .frame(width: 58)
            } else {
                Key("SET", color: Theme.accent, lit: sampler.isSetting, size: 8.5, feel: .toggle, onPress: { sampler.isSetting.toggle() })
                    .frame(width: 58)
            }
            Key("Q", lit: sampler.quantize, feel: .toggle, onPress: { sampler.quantize.toggle() })
                .frame(width: 26)
            DepthBar(value: $sampler.level, label: "VOLUME")
            Key("STOP", color: Theme.danger, size: 8, onPress: { sampler.stopAll() })
                .frame(width: 36)
        }
    }
}

// MARK: Beat FX

/// One effect. Hold for as long as you want it, or tap to latch it on. While holding, slide up and
/// down to set its depth and left and right to change its beat length.
struct FXPad: View {
    @Bindable var deck: Deck
    let effect: BeatFX
    @State private var pressTime: Date?
    @State private var startDepth: Float = 0
    @State private var startBeatIndex = 0
    @State private var wasOn = false

    var body: some View {
        let isOn = deck.isFXOn(effect)
        Pad(color: effect.color, lit: isOn, accessibilityName: effect.rawValue.capitalized, onPress: {
            pressTime = Date()
            wasOn = isOn
            deck.fxEngage(effect)
            startDepth = deck.fxDepth
            startBeatIndex = BeatFX.beatChoices.firstIndex(of: deck.fxBeats) ?? 2
        }, onRelease: {
            let held = Date().timeIntervalSince(pressTime ?? Date())
            // A quick tap latches; pressing a latched one or holding one lets it go on release.
            if wasOn || held > 0.25 { deck.fxRelease(effect) }
            pressTime = nil
        }, onDrag: { translation in
            let depth = min(1, max(0, startDepth + Float(-translation.height / 80)))
            if abs(depth - deck.fxDepth) > 0.001 { deck.fxDepth = depth }
            let steps = Int((translation.width / 26).rounded())
            let index = min(BeatFX.beatChoices.count - 1, max(0, startBeatIndex + steps))
            if BeatFX.beatChoices[index] != deck.fxBeats {
                Haptics.shared.tick()
                deck.fxBeats = BeatFX.beatChoices[index]
            }
        }) {
            Text(effect.rawValue)
                .font(Theme.silk(8.5))
                .tracking(0.2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .lineLimit(2)
                .padding(.horizontal, 2)
        }
    }
}

/// The FX settings: beat length, depth, and which stems the effect goes on.
struct FXControlRow: View {
    @Bindable var deck: Deck

    var body: some View {
        HStack(spacing: 3) {
            Key(color: Theme.accent, accessibilityName: "Shorter", onPress: { step(-1) }) {
                Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold))
            }
            .frame(width: 20)
            Text(Format.beats(deck.fxBeats))
                .font(Theme.digits(12))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 26)
                .contentTransition(.numericText())
                .animation(Theme.press, value: deck.fxBeats)
            Key(color: Theme.accent, accessibilityName: "Longer", onPress: { step(1) }) {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
            }
            .frame(width: 20)
            DepthBar(value: $deck.fxDepth)
            ForEach(Stem.allCases) { stem in
                Key(stem.short, color: stem.color, lit: deck.fxStems.contains(stem), size: 8.5, feel: .toggle) {
                    if deck.fxStems.contains(stem) {
                        if deck.fxStems.count > 1 { deck.fxStems.remove(stem) }
                    } else {
                        deck.fxStems.insert(stem)
                    }
                }
                .frame(width: 21)
            }
            Key("OUT", color: Theme.danger, lit: deck.echoingOut, size: 8, feel: .toggle, accessibilityName: "Echo out", onPress: deck.toggleEchoOut)
                .frame(width: 28)
        }
    }

    private func step(_ direction: Int) {
        let choices = BeatFX.beatChoices
        let i = choices.firstIndex(of: deck.fxBeats) ?? 2
        deck.fxBeats = choices[min(choices.count - 1, max(0, i + direction))]
    }
}

/// A slim horizontal level bar.
struct DepthBar: View {
    @Binding var value: Float
    var label = "DEPTH"
    @State private var start: Float?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black)
                Capsule().fill(Theme.accent).frame(width: max(4, geo.size.width * CGFloat(value)))
                Text(label).silk(7, color: .white.opacity(0.8)).padding(.leading, 5)
            }
            .frame(height: 13)
            .frame(maxHeight: .infinity)
            .overlay {
                TouchSurface(onDown: { _ in start = value; Haptics.shared.grab() }, onMove: { _, t in
                    guard let start else { return }
                    value = min(1, max(0, start + Float(t.width / geo.size.width)))
                }, onUp: { start = nil })
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.capitalized)
        .accessibilityValue("\(Int(value * 100)) percent")
        .accessibilityAdjustableAction { value = min(1, max(0, value + ($0 == .increment ? 0.05 : -0.05))) }
    }
}

extension BeatFX {
    /// Effects are coloured by family, so you can find one without reading it.
    var color: Color {
        switch self {
        case .echo, .pingPong, .spiral: Color(red: 0.14, green: 0.56, blue: 1)
        case .reverb: Color(red: 0.42, green: 0.42, blue: 1)
        case .flanger, .phaser: Color(red: 0.72, green: 0.34, blue: 1)
        case .filterLFO, .gate, .crush: Color(red: 0.1, green: 0.8, blue: 0.72)
        case .roll, .brake, .backspin: Color(red: 1, green: 0.48, blue: 0.1)
        }
    }
}
