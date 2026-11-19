import Foundation

enum TempDirectory {
    static func create() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoViewerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}