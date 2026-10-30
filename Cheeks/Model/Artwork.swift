import AVFoundation
import ImageIO
import UIKit

/// Cover art pulled from each file's metadata and kept as small JPEGs in the Caches folder.
enum ArtworkStore {
    private static let directory: URL = {
        let dir = URL.cachesDirectory.appending(path: "Artwork", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    nonisolated(unsafe) private static let memory: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 200
        return cache
    }()

    private static func url(_ id: UUID) -> URL { directory.appending(path: "\(id.uuidString).jpg") }

    /// Extracts the file's artwork, if it has any, and stores it. Safe to call again.
    static func extract(from asset: AVURLAsset, id: UUID) async {
        guard !FileManager.default.fileExists(atPath: url(id).path) else { return }
        guard let items = try? await asset.load(.commonMetadata) else { return }
        for item in items where item.commonKey == .commonKeyArtwork {
            guard let data = try? await item.load(.dataValue), !data.isEmpty,
                  let image = downsample(data, to: 512) else { continue }
            let encoded = UIImage(cgImage: image).jpegData(compressionQuality: 0.86)
            try? encoded?.write(to: url(id), options: .atomic)
            return
        }
    }

    /// Full-size artwork for a deck's jog and header.
    static func image(_ id: UUID) async -> CGImage? {
        let key = id.uuidString as NSString
        if let hit = memory.object(forKey: key) { return hit }
        let path = url(id)
        return await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: path), let image = downsample(data, to: 512) else { return nil }
            memory.setObject(image, forKey: key)
            return image
        }.value
    }

    /// A small version for a browser row.
    static func thumbnail(_ id: UUID) async -> CGImage? {
        let key = "\(id.uuidString)-thumb" as NSString
        if let hit = memory.object(forKey: key) { return hit }
        let path = url(id)
        return await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: path), let image = downsample(data, to: 96) else { return nil }
            memory.setObject(image, forKey: key)
            return image
        }.value
    }

    static func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(id))
    }

    private static func downsample(_ data: Data, to maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: maxPixels]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Tiny whole-track waveforms for the browser, drawn off the main thread and cached.
enum WaveformThumbnails {
    nonisolated(unsafe) private static let memory: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 300
        return cache
    }()

    static func image(_ id: UUID, width: Int, height: Int) async -> CGImage? {
        let key = id.uuidString as NSString
        if let hit = memory.object(forKey: key) { return hit }
        return await Task.detached(priority: .utility) {
            guard let wave = LibraryFiles.cachedWaveform(id), wave.count > 0 else { return nil }
            let image = render(wave, width: width, height: height)
            if let image { memory.setObject(image, forKey: key) }
            return image
        }.value
    }

    private static func render(_ wave: WaveformData, width: Int, height: Int) -> CGImage? {
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info) else { return nil }
        let perColumn = max(1, wave.count / width)
        let colors: [CGColor] = [
            CGColor(srgbRed: 0.07, green: 0.3, blue: 1, alpha: 1),
            CGColor(srgbRed: 0.98, green: 0.58, blue: 0.13, alpha: 1),
            CGColor(srgbRed: 1, green: 0.96, blue: 0.9, alpha: 1),
        ]
        for x in 0..<width {
            let start = x * wave.count / width
            var levels: [UInt8] = [0, 0, 0]
            for b in start..<min(start + perColumn, wave.count) {
                levels[0] = max(levels[0], wave.low[b])
                levels[1] = max(levels[1], wave.mid[b])
                levels[2] = max(levels[2], wave.high[b])
            }
            let scales: [CGFloat] = [1, 0.8, 0.55]
            for band in 0..<3 {
                let h = pow(CGFloat(levels[band]) / 255, 0.8) * CGFloat(height) * scales[band]
                context.setFillColor(colors[band])
                context.fill(CGRect(x: CGFloat(x), y: 0, width: 1, height: max(0.5, h)))
            }
        }
        return context.makeImage()
    }
}
