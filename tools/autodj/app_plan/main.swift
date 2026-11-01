// Runs the app's own planner, moves and audition on the lab's split tracks, and writes what comes out, so what's rated
// in the Listening Room is exactly what the app plays.
//
//   app_plan <tracks dir> <out dir> <track A> <track B> [<press at, as a fraction of A>]
import Foundation

let arguments = CommandLine.arguments
let tracks = arguments[1], out = arguments[2], nameA = arguments[3], nameB = arguments[4]
let pressAt = arguments.count > 5 ? Double(arguments[5]) ?? 0.6 : 0.6

func stems(_ name: String) throws -> [PCM16Stereo] {
    let file = try Data(contentsOf: URL(fileURLWithPath: "\(tracks)/\(name)/stems.npy"), options: .alwaysMapped)
    let offset = 10 + (Int(file[8]) | Int(file[9]) << 8)
    let frames = (file.count - offset) / 16
    return (0..<4).map { s in
        let stem = PCM16Stereo(frames: frames)
        file.withUnsafeBytes { raw in _ = memcpy(stem.data, raw.baseAddress! + offset + s * frames * 4, frames * 4) }
        return stem
    }
}

/// Trim and fader together, as the live mixer has them by default, with loudness matching.
func level(_ name: String) -> Float {
    let lufs = (try? String(contentsOfFile: "\(tracks)/\(name)/lufs.txt", encoding: .utf8)).flatMap { Double($0) } ?? -11
    return pow(10, Float(max(-12, min(9, -11 - lufs))) / 20) * 0.85 * 0.85
}

func wav(_ path: String, _ left: [Float], _ right: [Float]) {
    var data = Data()
    func add<T>(_ v: T) { withUnsafeBytes(of: v) { data.append(contentsOf: $0) } }
    let bytes = UInt32(left.count * 4)
    data.append(contentsOf: "RIFF".utf8); add(36 + bytes); data.append(contentsOf: "WAVEfmt ".utf8)
    add(UInt32(16)); add(UInt16(1)); add(UInt16(2)); add(UInt32(44100)); add(UInt32(176400)); add(UInt16(4)); add(UInt16(16))
    data.append(contentsOf: "data".utf8); add(bytes)
    var samples = [Int16](repeating: 0, count: left.count * 2)
    for i in left.indices {
        samples[i * 2] = Int16(max(-1, min(1, left[i])) * 32767)
        samples[i * 2 + 1] = Int16(max(-1, min(1, right[i])) * 32767)
    }
    samples.withUnsafeBytes { data.append(contentsOf: $0) }
    try? data.write(to: URL(fileURLWithPath: path))
}

let stemsA = try stems(nameA), stemsB = try stems(nameB)
var clock = Date()
guard let mapA = TrackMapper.map(stems: stemsA), let mapB = TrackMapper.map(stems: stemsB) else { fatalError("no map") }
print("\(nameA) \(mapA.bpm) -> \(nameB) \(mapB.bpm), steady \(mapA.isSteady) \(mapB.isSteady), mapped both in \(String(format: "%.1f", Date().timeIntervalSince(clock))) s")
clock = Date()
let earliest = Int(Double(mapA.barCount) * pressAt)
let plans = TransitionPlanner.plans(from: mapA, to: mapB, playingBPM: mapA.bpm, earliest: earliest)
print("\(plans.count) plans from bar \(earliest) of \(mapA.barCount) in \(String(format: "%.2f", Date().timeIntervalSince(clock))) s")
let probe = DeckRenderer(sampleRate: AudioConfig.sampleRate)
let ownTempo = abs(mapA.bpm / mapB.bpm - 1) > TransitionPlanner.maxStretch
let rateB = ownTempo ? 1 : mapA.bpm / mapB.bpm
var firstChoice = true
var done = Set<TransitionMove>()
for plan in TransitionPlanner.shortlist(plans) where !done.contains(plan.move) {
    let lag = abs(rateB - 1) > 1e-6 || plan.shift != 0 ? cheeks_deck_stem_lag(probe.handle, rateB) : 0
    let score = TransitionScore(plan: plan, a: .init(deck: 0, map: mapA, rate: 1, lag: 0), b: .init(deck: 1, map: mapB, rate: rateB, lag: lag))
    var left: [Float] = [], right: [Float] = []
    clock = Date()
    guard let review = TransitionAudition.review(score, stemsA: stemsA, stemsB: stemsB, levelA: level(nameA), levelB: level(nameB), listen: { left += $0; right += $1 }) else {
        print("  \(plan.move.title): couldn't render")
        continue
    }
    let seconds = Date().timeIntervalSince(clock), audio = Double(left.count) / 44100
    let verdict = review.passes ? "kept" : review.problems.joined(separator: ", ")
    print("  \(plan.move.title) exit \(plan.exit) entry \(plan.entry) swap \(plan.swap) shift \(plan.shift) score \(String(format: "%.2f", plan.score)) change \(String(format: "%+.1f", review.change)) dB, \(String(format: "%.0f", audio)) s in \(String(format: "%.1f", seconds)) s: \(verdict)\(review.passes && firstChoice ? "  <- the app would play this" : "")")
    if review.passes {
        firstChoice = false
        done.insert(plan.move)
        wav("\(out)/\(nameA)__\(nameB)__\(plan.move.rawValue).wav", left, right)
        let notes: [String: Any] = ["move": plan.move.rawValue, "title": plan.move.title, "exit": plan.exit, "entry": plan.entry, "swap": plan.swap, "shift": plan.shift, "seconds": audio,
                                    "start_beat": score.start + 16, "length": score.length, "bpm_a": mapA.bpm, "bpm_b": mapB.bpm, "landing": score.landing ?? -1, "harmony": plan.harmonyAgrees]
        try? JSONSerialization.data(withJSONObject: notes).write(to: URL(fileURLWithPath: "\(out)/\(nameA)__\(nameB)__\(plan.move.rawValue).json"))
    }
}
