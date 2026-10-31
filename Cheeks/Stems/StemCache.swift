import Foundation

/// Finished stems on disk, one file per track, so reloading a track doesn't separate it again.
///
/// Lives in Caches, where iOS may also delete it. Files are written to a temporary name and renamed,
/// so a crash leaves either the old file or none. Anything that doesn't validate on load (truncated,
/// another format version) is deleted and reported as a miss.
///
/// File format, little-endian:
///
///     0   UInt64  magic "CHKSTEMS"
///     8   UInt32  format version
///     12  UInt32  stem count (4)
///     16  UInt64  frames per stem
///     24  UInt32  sample rate
///     28  UInt32  stem headroom (Float bit pattern)
///     32  UInt64  FNV-1a hash of bytes 0 ..< 32
///     40  Int16   interleaved stereo stems, one after the other, in `Stem.allCases` order
final class StemCache {
    enum CacheError: Error {
        case wrongStemCount
        case mismatchedLengths
        case writeFailed(Int32)
    }

    static let shared = StemCache()
    static let defaultCapacity: Int64 = 8 << 30

    private static let magic: UInt64 = 0x534D_4554_534B_4843 // "CHKSTEMS"
    private static let version: UInt32 = 1
    private static let headerSize = 40
    private static let fileExtension = "stems"
    private static let temporaryExtension = "tmp"
    /// Older than this and a temporary file can't belong to a write still in progress.
    private static let temporaryFileLifetime: TimeInterval = 3600

    let directory: URL
    let capacity: Int64
    private let lock = NSLock()

    init(directory: URL? = nil, capacity: Int64 = StemCache.defaultCapacity) {
        self.directory = directory ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stems", isDirectory: true)
        self.capacity = capacity
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension(Self.fileExtension)
    }

    // MARK: Loading

    /// The stems for a track, or nil on a miss. Marks the entry as recently used.
    func contains(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: url(for: id).path)
    }

    func load(_ id: UUID) -> [PCM16Stereo]? {
        let file = url(for: id)
        let descriptor = open(file.path, O_RDONLY)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        guard let stems = read(from: descriptor) else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        // A nil time list means "now": the modification date is what the LRU goes by.
        utimes(file.path, nil)
        return stems
    }

    private func read(from descriptor: Int32) -> [PCM16Stereo]? {
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_size >= Self.headerSize else { return nil }

        var header = [UInt8](repeating: 0, count: Self.headerSize)
        guard header.withUnsafeMutableBytes({ Self.readFully(descriptor, $0.baseAddress!, $0.count) }) else { return nil }
        guard let frames = Self.validatedFrames(header: header, fileSize: Int64(info.st_size)) else { return nil }

        let stems = Stem.allCases.map { _ in PCM16Stereo(frames: frames) }
        for stem in stems where frames > 0 {
            guard Self.readFully(descriptor, stem.data, frames * 2 * MemoryLayout<Int16>.stride) else { return nil }
        }
        return stems
    }

    private static func validatedFrames(header: [UInt8], fileSize: Int64) -> Int? {
        header.withUnsafeBytes { raw -> Int? in
            guard raw.loadUnaligned(fromByteOffset: 0, as: UInt64.self) == magic,
                  raw.loadUnaligned(fromByteOffset: 8, as: UInt32.self) == version,
                  raw.loadUnaligned(fromByteOffset: 12, as: UInt32.self) == UInt32(Stem.allCases.count),
                  raw.loadUnaligned(fromByteOffset: 24, as: UInt32.self) == UInt32(AudioConfig.sampleRate),
                  raw.loadUnaligned(fromByteOffset: 28, as: UInt32.self) == PCM16Stereo.stemHeadroom.bitPattern,
                  raw.loadUnaligned(fromByteOffset: 32, as: UInt64.self) == hash(raw[0..<32]) else { return nil }
            // Divide rather than multiply, so a wild frame count can't overflow.
            let bytesPerFrame = Int64(Stem.allCases.count * 2 * MemoryLayout<Int16>.stride)
            let payload = fileSize - Int64(headerSize)
            let frames = raw.loadUnaligned(fromByteOffset: 16, as: UInt64.self)
            guard payload % bytesPerFrame == 0, frames == UInt64(payload / bytesPerFrame) else { return nil }
            return Int(frames)
        }
    }

    // MARK: Storing

    /// Writes the stems for a track, replacing any already there, then evicts the least recently
    /// used entries to get back under the capacity.
    func store(_ id: UUID, stems: [PCM16Stereo]) throws {
        guard stems.count == Stem.allCases.count else { throw CacheError.wrongStemCount }
        let frames = stems[0].frames
        guard stems.allSatisfy({ $0.frames == frames }) else { throw CacheError.mismatchedLengths }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(Self.temporaryExtension)
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { throw CacheError.writeFailed(errno) }

        var written = false
        defer {
            close(descriptor)
            if !written { try? FileManager.default.removeItem(at: temporary) }
        }

        let header = Self.makeHeader(frames: frames)
        try header.withUnsafeBytes { try Self.writeFully(descriptor, $0.baseAddress!, $0.count) }
        for stem in stems where frames > 0 {
            try Self.writeFully(descriptor, stem.data, frames * 2 * MemoryLayout<Int16>.stride)
        }
        guard rename(temporary.path, url(for: id).path) == 0 else { throw CacheError.writeFailed(errno) }
        written = true

        evict(keeping: id)
    }

    private static func makeHeader(frames: Int) -> [UInt8] {
        var header = [UInt8](repeating: 0, count: headerSize)
        header.withUnsafeMutableBytes { raw in
            raw.storeBytes(of: magic, toByteOffset: 0, as: UInt64.self)
            raw.storeBytes(of: version, toByteOffset: 8, as: UInt32.self)
            raw.storeBytes(of: UInt32(Stem.allCases.count), toByteOffset: 12, as: UInt32.self)
            raw.storeBytes(of: UInt64(frames), toByteOffset: 16, as: UInt64.self)
            raw.storeBytes(of: UInt32(AudioConfig.sampleRate), toByteOffset: 24, as: UInt32.self)
            raw.storeBytes(of: PCM16Stereo.stemHeadroom.bitPattern, toByteOffset: 28, as: UInt32.self)
            let digest = hash(UnsafeRawBufferPointer(raw)[0..<32])
            raw.storeBytes(of: digest, toByteOffset: 32, as: UInt64.self)
        }
        return header
    }

    // MARK: Housekeeping

    func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Total size of the stored stems.
    var storedBytes: Int64 {
        entries().reduce(0) { $0 + $1.size }
    }

    private struct Entry {
        let url: URL
        let size: Int64
        let modified: Date
    }

    private func entries() -> [Entry] {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))) ?? []
        return urls.compactMap { url in
            guard url.pathExtension == Self.fileExtension,
                  let values = try? url.resourceValues(forKeys: keys),
                  let size = values.fileSize, let modified = values.contentModificationDate else { return nil }
            return Entry(url: url, size: Int64(size), modified: modified)
        }
    }

    private func evict(keeping id: UUID) {
        lock.lock()
        defer { lock.unlock() }

        let keep = url(for: id).lastPathComponent
        var total = storedBytes
        for entry in entries().sorted(by: { $0.modified < $1.modified }) where total > capacity {
            guard entry.url.lastPathComponent != keep else { continue }
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }

        // A crash during a write leaves its temporary file behind.
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for url in urls where url.pathExtension == Self.temporaryExtension {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if Date().timeIntervalSince(modified) > Self.temporaryFileLifetime {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: Low-level

    private static func hash(_ bytes: UnsafeRawBufferPointer.SubSequence) -> UInt64 {
        var value: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in bytes {
            value = (value ^ UInt64(byte)) &* 0x100_0000_01B3
        }
        return value
    }

    private static func readFully(_ descriptor: Int32, _ destination: UnsafeMutableRawPointer, _ count: Int) -> Bool {
        var done = 0
        while done < count {
            let got = Darwin.read(descriptor, destination + done, count - done)
            if got > 0 {
                done += got
            } else if got == 0 || errno != EINTR {
                return false
            }
        }
        return true
    }

    private static func writeFully(_ descriptor: Int32, _ source: UnsafeRawPointer, _ count: Int) throws {
        var done = 0
        while done < count {
            let put = Darwin.write(descriptor, source + done, count - done)
            if put > 0 {
                done += put
            } else if errno != EINTR {
                throw CacheError.writeFailed(errno)
            }
        }
    }
}
