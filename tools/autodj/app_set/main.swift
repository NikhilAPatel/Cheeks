// Runs a whole set through the app's own planner and audition, on the lab's split tracks, and reports what it would do:
// which move joins each pair, and how much of each track gets played. It renders nothing to disk.
//
//   app_set <tracks dir> <track> <track> [<track> ...]
//
// With CHEEKS_SET_ORDER=next in the environment, it plays them in the order the NEXT key gives, from the first one.
import Foundation

let arguments = CommandLine.arguments
let tracks = arguments[1]
var names = Array(arguments[2...])

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

func level(_ name: String) -> Float {
    let lufs = (try? String(contentsOfFile: "\(tracks)/\(name)/lufs.txt", encoding: .utf8)).flatMap { Double($0) } ?? -11
    return pow(10, Float(max(-12, min(9, -11 - lufs))) / 20) * 0.85 * 0.85
}

if ProcessInfo.processInfo.environment["CHEEKS_SET_ORDER"] == "next" {
    let known = try names.map { name -> (name: String, bpm: Double, key: String) in
        guard let map = TrackMapper.map(stems: try stems(name)) else { fatalError("no map") }
        return (name, map.bpm, Camelot.code(pitchClass: map.keyRoot, minor: map.keyIsMinor))
    }
    let first = known[0]
    let rest = SetOrder.order(Array(known.dropFirst()), from: SetOrder.Place(bpm: first.bpm, key: first.key), bpm: { $0.bpm }, key: { $0.key })
    names = [first.name] + rest.map(\.name)
    for item in [first] + rest { print(String(format: "  %6.1f %-4@ %@", item.bpm, item.key as NSString, item.name as NSString)) }
}

let probe = DeckRenderer(sampleRate: AudioConfig.sampleRate)
var stemsA = try stems(names[0])
guard var mapA = TrackMapper.map(stems: stemsA) else { fatalError("no map") }
var rateA = 1.0, shiftA = 0, recentMoves: [TransitionMove] = []
// Where the track on air was picked up, in its own bars.
var enteredAt = 0
var counts: [String: Int] = [:]
var joined = 0, failed = 0, shortest = (fraction: 1.0, name: "")
var plays: [Double] = [], blends = 0, shifts = 0, stretchTotal = 0.0

for (index, nameB) in names.enumerated().dropFirst() {
    let nameA = names[index - 1]
    let stemsB = try stems(nameB)
    guard let mapB = TrackMapper.map(stems: stemsB) else { fatalError("no map") }
    let playingBPM = mapA.bpm * rateA
    let rateNext = abs(playingBPM / mapB.bpm - 1) > TransitionPlanner.maxStretch ? 1 : playingBPM / mapB.bpm
    let lagA = abs(rateA - 1) > 1e-6 || shiftA != 0 ? cheeks_deck_stem_lag(probe.handle, rateA) : 0
    let lagB = abs(rateNext - 1) > 1e-6 ? cheeks_deck_stem_lag(probe.handle, rateNext) : 0
    let heard = mapA.heard(shiftedBy: shiftA)
    let soonest = enteredAt + TransitionScore.leadBars + 1
    func attempt(from bar: Int) -> TransitionScore? {
        TransitionChoice(mapA: heard, mapB: mapB, stemsA: stemsA, stemsB: stemsB, rateA: rateA, levelA: level(nameA), levelB: level(nameB),
                         lagA: lagA, lagB: lagB, lagShifted: cheeks_deck_stem_lag(probe.handle, rateNext), earliest: max(soonest, bar),
                         recentMoves: recentMoves, avoid: [.brakeDrop], wantsTimeOnNext: true).choose()
    }
    let usual = TransitionPlanner.setExit(in: mapA)
    var chosen = attempt(from: usual)
    var how = "usual"
    var back = 1
    while chosen == nil, usual - TransitionPlanner.setStepBack * back >= mapA.barCount / 3 {
        chosen = attempt(from: usual - TransitionPlanner.setStepBack * back)
        how = "\(back) back"
        back += 1
    }
    let bpmText = String(format: "%.1f>%.1f", playingBPM, mapB.bpm)
    guard let score = chosen else {
        failed += 1
        print("\(nameA) -> \(nameB) \(bpmText): NO WAY IN, plays out to the end")
        stemsA = stemsB
        mapA = mapB
        rateA = 1
        shiftA = 0
        enteredAt = 0
        continue
    }
    joined += 1
    let plan = score.plan
    counts[plan.move.title, default: 0] += 1
    let played = Double(plan.exit - enteredAt) / Double(max(mapA.barCount, 1))
    if played < shortest.fraction { shortest = (played, nameA) }
    plays.append(played)
    if plan.move == .bassSwap || plan.move == .vocalTease || plan.move == .acapellaRide { blends += 1 }
    if plan.shift != 0 { shifts += 1 }
    stretchTotal += abs(score.b.rate - 1)
    print("\(nameA) -> \(nameB) \(bpmText): \(plan.move.title), leaves bar \(plan.exit) of \(mapA.barCount) (from \(usual), \(how)), enters bar \(plan.entry), shift \(plan.shift), \(String(format: "%.0f%%", played * 100)) of the track played")
    // The next track's on from wherever the move hands over.
    let landing = plan.entry + (plan.move == .bassSwap ? plan.swap : 0)
    enteredAt = landing
    stemsA = stemsB
    mapA = mapB
    rateA = score.b.rate
    shiftA = plan.shift
    recentMoves = Array((recentMoves + [plan.move]).suffix(4))
}
print("joined \(joined), no way in \(failed). Moves: \(counts.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))")
print("shortest play: \(String(format: "%.0f%%", shortest.fraction * 100)) of \(shortest.name)")
let sortedPlays = plays.sorted()
if !sortedPlays.isEmpty {
    print(String(format: "median play %.0f%%, moves that overlap two tracks %d, key shifts %d, mean stretch %.1f%%",
                 sortedPlays[sortedPlays.count / 2] * 100, blends, shifts, stretchTotal / Double(max(joined, 1)) * 100))
}
