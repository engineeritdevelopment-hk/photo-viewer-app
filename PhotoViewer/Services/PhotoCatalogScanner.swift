import Foundation
import UniformTypeIdentifiers

actor PhotoCatalogScanner {
    struct Progress: Sendable {
        var scanned: Int
        var currentSource: String?
        var pathsBatch: [String]
    }

    private struct ActiveScan {
        let id: UUID
        let task: Task<Void, Never>
    }

    private var activeScan: ActiveScan?

    func scan(
        sources: [(id: String, url: URL)],
        filter: PhotoFilter,
        index: PhotoIndexStore,
        batchSize: Int = 48
    ) -> AsyncStream<Progress> {
        activeScan?.task.cancel()
        let (stream, continuation) = AsyncStream.makeStream(of: Progress.self)
        let task = Task {
            await self.runScan(
                sources: sources,
                filter: filter,
                index: index,
                batchSize: batchSize,
                continuation: continuation
            )
            continuation.finish()
        }
        let scan = ActiveScan(id: UUID(), task: task)
        activeScan = scan
        continuation.onTermination = { _ in
            task.cancel()
        }
        return stream
    }

    /// Cancels the in-flight scan and waits until it has stopped writing index rows.
    func cancelAndWait() async {
        guard let current = activeScan else { return }
        current.task.cancel()
        await current.task.value
        if activeScan?.id == current.id {
            activeScan = nil
        }
    }

    private func runScan(
        sources: [(id: String, url: URL)],
        filter: PhotoFilter,
        index: PhotoIndexStore,
        batchSize: Int,
        continuation: AsyncStream<Progress>.Continuation
    ) async {
        var seen = Set<String>()
        var scanned = 0
        var batch: [String] = []

        for source in sources {
            if Task.isCancelled { return }
            continuation.yield(Progress(scanned: scanned, currentSource: source.url.lastPathComponent, pathsBatch: []))
            let fileManager = FileManager.default
            guard let enumerator = fileManager.enumerator(
                at: source.url,
                includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey, .contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                if Task.isCancelled { return }
                let path = fileURL.standardizedFileURL.path
                if path.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { continue }
                guard filter.allows(path: path) else { continue }
                guard seen.insert(path).inserted else { continue }

                let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let mod = values?.contentModificationDate ?? Date()
                let size = Int64(values?.fileSize ?? 0)
                try? await index.upsertCatalogRow(path: path, sourceId: source.id, modTime: mod, fileSize: size)
                if Task.isCancelled { return }
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
    }
}