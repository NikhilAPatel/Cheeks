// Runs the app's TrackMapper on the lab's split tracks, to check the port against tools/autodj/analyze.py.
//
//   app_map <tracks dir> <name> ...
import Foundation

let directory = CommandLine.arguments[1]
for name in CommandLine.arguments.dropFirst(2) {
    let file = try Data(contentsOf: URL(fileURLWithPath: "\(directory)/\(name)/stems.npy"), options: .alwaysMapped)
    // .npy: the header's length is at byte 8, and the array is (4, frames, 2) of Int16 after it.
    let headerLength = Int(file[8]) | Int(file[9]) << 8
    let offset = 10 + headerLength
    let frames = (file.count - offset) / 16
    let stems: [PCM16Stereo] = (0..<4).map { s in
        let stem = PCM16Stereo(frames: frames)
        file.withUnsafeBytes { raw in _ = memcpy(stem.data, raw.baseAddress! + offset + s * frames * 4, frames * 4) }
        return stem
    }
    let start = Date()
    guard let map = TrackMapper.map(stems: stems) else { print("\(name) no map"); continue }
    let elapsed = Date().timeIntervalSince(start)
    let row: [String: Any] = [
        "name": name, "seconds": elapsed, "bpm": map.bpm, "first": map.firstBeat, "drift": map.drift, "steady": map.isSteady, "first_bar": map.firstBar, "bars": map.barCount,
        "lattice": map.lattice, "key_root": map.keyRoot, "key_minor": map.keyIsMinor,
        "on": map.on.map { $0.map { $0 ? 1 : 0 } }, "kick": map.hasKick.map { $0 ? 1 : 0 }, "vocal": map.vocal, "boundaries": map.boundaries,
    ]
    print(String(data: try JSONSerialization.data(withJSONObject: row), encoding: .utf8)!)
}
