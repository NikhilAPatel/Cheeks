// Runs the app's Swift pipeline natively on the Mac, where the GPU and Neural Engine are available
// (the simulator only has the CPU). See build_harness.sh and README.md.
//
//   swift_eval <Stems.mlmodelc> <cpuOnly|cpuAndGPU|cpuAndNeuralEngine|all> <input dir> <output dir>
//
// Input: raw stereo Int16 files named *.pcm. Output: <name>.<vocals|melody|bass|drums>.pcm, plus
// one line per file with the time taken. `--bench` in place of the output dir does a timing run of
// one file only, without writing anything.

import CoreML
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 5 else {
    fail("usage: swift_eval <Stems.mlmodelc> <units> <input dir> <output dir|--bench>")
}

let units: MLComputeUnits
switch arguments[2] {
case "cpuOnly": units = .cpuOnly
case "cpuAndGPU": units = .cpuAndGPU
case "cpuAndNeuralEngine": units = .cpuAndNeuralEngine
case "all": units = .all
default: fail("unknown compute units \(arguments[2])")
}

let inputDirectory = URL(fileURLWithPath: arguments[3])
let bench = arguments[4] == "--bench"
let outputDirectory = URL(fileURLWithPath: arguments[4])
if !bench {
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
}

let separator = CoreMLStemSeparator(modelURL: URL(fileURLWithPath: arguments[1]), computeUnits: units)
print("load: \(String(format: "%.2f", try separator.preload())) s")

var files = try FileManager.default.contentsOfDirectory(at: inputDirectory, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "pcm" }
    .sorted { $0.path < $1.path }
if bench { files = Array(files.prefix(1)) }

var totalSeconds = 0.0
var totalAudio = 0.0
var totalSegments = 0
for file in files {
    let bytes = try Data(contentsOf: file)
    let source = PCM16Stereo(frames: bytes.count / 4)
    bytes.withUnsafeBytes { raw in
        _ = memcpy(source.data, raw.baseAddress!, source.frames * 4)
    }

    var progressTimes: [Date] = []
    let start = Date()
    let stems = try separator.separate(source, progress: { _ in progressTimes.append(Date()) }, isCancelled: { false })
    let elapsed = Date().timeIntervalSince(start)
    let segments = max(progressTimes.count - 1, 1)
    totalSeconds += elapsed
    totalAudio += source.duration
    totalSegments += segments

    let times = zip(progressTimes.dropFirst(), progressTimes).map { $0.timeIntervalSince($1) }
    let list = times.map { String(format: "%.3f", $0) }.joined(separator: " ")
    print("\(file.lastPathComponent): \(String(format: "%.1f", source.duration)) s of audio, \(segments) segments, "
        + "\(String(format: "%.2f", elapsed)) s [\(list)]")

    if !bench {
        let base = file.deletingPathExtension().lastPathComponent
        for stem in Stem.allCases {
            let data = Data(bytes: stems[stem.rawValue].data, count: source.frames * 4)
            try data.write(to: outputDirectory.appendingPathComponent("\(base).\(stem).pcm"))
        }
    }
}
print("total: \(String(format: "%.2f", totalSeconds)) s for \(String(format: "%.1f", totalAudio)) s of audio, "
    + "\(totalSegments) segments, \(String(format: "%.3f", totalSeconds / Double(max(totalSegments, 1)))) s per segment")
