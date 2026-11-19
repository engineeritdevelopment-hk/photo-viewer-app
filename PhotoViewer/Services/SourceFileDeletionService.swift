import Foundation

enum SourceFileDeletionService {
    /// Moves files at the given paths to the Trash. Returns paths that could not be deleted.
    static func moveToTrash(paths: [String]) -> [String] {
        var failed: [String] = []
        let manager = FileManager.default
        for path in paths {
            let url = URL(fileURLWithPath: path)
            guard manager.fileExists(atPath: path) else {
                failed.append(path)
                continue
            }
            do {
                try manager.trashItem(at: url, resultingItemURL: nil)
            } catch {
                failed.append(path)
            }
        }
        return failed
    }
}