// Runs the app's own TrackAnalyzer on the Mac, to compare its grid and key with the lab's on the same music.
//
//   app_grid <raw stereo Int16 file> ...
import Foundation

for path in CommandLine.arguments.dropFirst() {
    let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
    let source = PCM16Stereo(frames: bytes.count / 4)
    bytes.withUnsafeBytes { raw in _ = memcpy(source.data, raw.baseAddress!, source.frames * 4) }
    let result = TrackAnalyzer.analyze(source)
    let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    let phrases = (result.phrases ?? []).map { "\($0.kind.rawValue)@\(Int($0.start))" }.joined(separator: " ")
    print("\(name) bpm \(result.bpm) first \(result.firstBeat) markers \(result.tempoMarkers?.count ?? 0) key \(result.key ?? "?") | \(phrases)")
}
