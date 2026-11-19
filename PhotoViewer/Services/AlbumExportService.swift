import Foundation

enum AlbumExportService {
    static func export(
        albumName: String,
        photoPaths: [String],
        destinationParent: URL,
        onProgress: @escaping @MainActor (Int, Int) async -> Void
    ) async throws -> Int {
        let destination = destinationParent.appendingPathComponent(albumName, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        var copied = 0
        let total = photoPaths.count
        for path in photoPaths {
            let source = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let unique = uniqueName(in: destination, basename: source.lastPathComponent)
            let target = destination.appendingPathComponent(unique)
            try FileManager.default.copyItem(at: source, to: target)
            copied += 1
            await onProgress(copied, total)
        }
        return copied
    }

    private static func uniqueName(in directory: URL, basename: String) -> String {
        var candidate = basename
        var suffix = 2
        let stem = (basename as NSString).deletingPathExtension
        let ext = (basename as NSString).pathExtension
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = ext.isEmpty ? "\(stem)-\(suffix)" : "\(stem)-\(suffix).\(ext)"
            suffix += 1
        }
        return candidate
    }
}