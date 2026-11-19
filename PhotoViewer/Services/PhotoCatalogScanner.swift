import Foundation
import UniformTypeIdentifiers

actor PhotoCatalogScanner {
    struct Progress: Sendable {
        var scanned: Int
        var currentSource: String?
        var pathsBatch: [String]
    }

    func scan(
        sources: [(id: String, url: URL)],
        filter: PhotoFilter,
        index: PhotoIndexStore,
        batchSize: Int = 48
    ) async -> AsyncStream<Progress> {
        AsyncStream { continuation in
            Task {
                var seen = Set<String>()
                var scanned = 0
                var batch: [String] = []

                for source in sources {
                    continuation.yield(Progress(scanned: scanned, currentSource: source.url.lastPathComponent, pathsBatch: []))
                    let fileManager = FileManager.default
                    guard let enumerator = fileManager.enumerator(
                        at: source.url,
                        includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey, .contentModificationDateKey, .fileSizeKey],
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]
                    ) else { continue }

                    for case let fileURL as URL in enumerator {
                        if Task.isCancelled { break }
                        let path = fileURL.standardizedFileURL.path
                        if path.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { continue }
                        guard filter.allows(path: path) else { continue }
                        guard seen.insert(path).inserted else { continue }

                        let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                        let mod = values?.contentModificationDate ?? Date()
                        let size = Int64(values?.fileSize ?? 0)
                        try? await index.upsertCatalogRow(path: path, sourceId: source.id, modTime: mod, fileSize: size)
                        batch.append(path)
                        scanned += 1

                        if batch.count >= batchSize {
                            continuation.yield(Progress(scanned: scanned, currentSource: source.url.lastPathComponent, pathsBatch: batch))
                            batch = []
                            await Task.yield()
                        }
                    }
                }

                if !batch.isEmpty {
                    continuation.yield(Progress(scanned: scanned, currentSource: nil, pathsBatch: batch))
                }
                continuation.finish()
            }
        }
    }
}