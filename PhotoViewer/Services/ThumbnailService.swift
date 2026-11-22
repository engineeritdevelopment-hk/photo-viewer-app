import AppKit
import CryptoKit
import Foundation
import ImageIO

actor ThumbnailService {
    private let memory = NSCache<NSString, NSImage>()
    private let maxConcurrent = 6
    private let maxViewerConcurrent = 3
    private var active = 0
    private var viewerActive = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var viewerWaiters: [CheckedContinuation<Void, Never>] = []

    init() {
        memory.countLimit = 400
        memory.totalCostLimit = 128 * 1024 * 1024
    }

    func thumbnail(for url: URL, maxPixel: Int = 320) async -> NSImage? {
        await loadImage(for: url, maxPixel: maxPixel, viewerPriority: false)
    }

    func fullImage(for url: URL, maxPixel: Int = 2048) async -> NSImage? {
        await loadImage(for: url, maxPixel: maxPixel, viewerPriority: true)
    }

    func prefetchFullImage(for url: URL, maxPixel: Int = 2048) async {
        _ = await loadImage(for: url, maxPixel: maxPixel, viewerPriority: true)
    }

    private func loadImage(for url: URL, maxPixel: Int, viewerPriority: Bool) async -> NSImage? {
        let key = cacheKey(url: url, maxPixel: maxPixel) as NSString
        if let cached = memory.object(forKey: key) { return cached }
        if let disk = loadDisk(key: key as String) {
            memory.setObject(disk, forKey: key)
            return disk
        }

        if viewerPriority {
            await acquireViewerSlot()
        } else {
            await acquireSlot()
        }
        defer {
            if viewerPriority {
                releaseViewerSlot()
            } else {
                releaseSlot()
            }
        }

        if let cached = memory.object(forKey: key) { return cached }

        guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        memory.setObject(image, forKey: key)
        saveDisk(image: image, key: key as String)
        return image
    }

    private func cacheKey(url: URL, maxPixel: Int) -> String {
        let mod: TimeInterval
        do {
            mod = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate?.timeIntervalSince1970 ?? 0
        } catch {
            mod = 0
        }
        let digest = SHA256.hash(data: Data("\(url.path)|\(mod)|\(maxPixel)".utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func diskURL(key: String) -> URL {
        ApplicationPaths.thumbnailCache.appendingPathComponent("\(key).jpg")
    }

    private func loadDisk(key: String) -> NSImage? {
        let url = diskURL(key: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    private func saveDisk(image: NSImage, key: String) {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
        else { return }
        try? data.write(to: diskURL(key: key))
    }

    private func acquireSlot() async {
        if active < maxConcurrent {
            active += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        active += 1
    }

    private func releaseSlot() {
        active = max(0, active - 1)
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        }
    }

    private func acquireViewerSlot() async {
        if viewerActive < maxViewerConcurrent {
            viewerActive += 1
            return
        }
        await withCheckedContinuation { continuation in
            viewerWaiters.append(continuation)
        }
        viewerActive += 1
    }

    private func releaseViewerSlot() {
        viewerActive = max(0, viewerActive - 1)
        if let next = viewerWaiters.first {
            viewerWaiters.removeFirst()
            next.resume()
        }
    }
}