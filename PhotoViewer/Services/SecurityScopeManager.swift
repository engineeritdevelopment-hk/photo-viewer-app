import Foundation

/// Keeps security-scoped folder access alive while indexing or reading files (required for external volumes).
final class SecurityScopeManager {
    private var activeBySourceID: [String: URL] = [:]

    func beginAccess(sourceID: String, bookmarkData: Data) throws -> URL {
        if let existing = activeBySourceID[sourceID] {
            return existing
        }
        let url = try BookmarkStore.resolve(bookmarkData)
        guard BookmarkStore.startAccess(url) else {
            throw BookmarkStore.BookmarkError.accessDenied(url)
        }
        activeBySourceID[sourceID] = url
        return url
    }

    func release(sourceID: String) {
        if let url = activeBySourceID.removeValue(forKey: sourceID) {
            BookmarkStore.stopAccess(url)
        }
    }

    func releaseAll() {
        for url in activeBySourceID.values {
            BookmarkStore.stopAccess(url)
        }
        activeBySourceID.removeAll()
    }

    func activeRoots() -> [URL] {
        Array(activeBySourceID.values)
    }
}