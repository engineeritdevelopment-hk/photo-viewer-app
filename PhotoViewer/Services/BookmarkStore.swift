import AppKit
import Foundation

enum BookmarkStore {
    enum BookmarkError: LocalizedError {
        case accessDenied(URL)
        case createFailed(URL, underlying: Error)
        case resolveFailed

        var errorDescription: String? {
            switch self {
            case .accessDenied(let url):
                return "Couldn’t access “\(url.lastPathComponent)”. Choose the folder again in the file picker so macOS can grant access (required for external drives)."
            case .createFailed(let url, let underlying):
                let detail = underlying.localizedDescription
                if detail.localizedCaseInsensitiveContains("correct format")
                    || detail.localizedCaseInsensitiveContains("couldn’t be opened")
                {
                    return "Couldn’t save access to “\(url.lastPathComponent)”. Choose the folder again with Add folder… so macOS can grant access."
                }
                return "Couldn’t save access to “\(url.path)”: \(detail)"
            case .resolveFailed:
                return "This source folder isn’t available. Plug in the drive or choose the folder again."
            }
        }
    }

    /// Call while the URL is active from `NSOpenPanel` or after `startAccessingSecurityScopedResource()`.
    static func makeBookmark(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: [.volumeIsRemovableKey],
                relativeTo: nil
            )
        } catch {
            throw BookmarkError.createFailed(url, underlying: error)
        }
    }

  static func resolve(_ data: Data) throws -> URL {
        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            if stale {
                // Still usable; caller may refresh bookmark after successful access.
                NSLog("Photo Viewer: security-scoped bookmark is stale for \(url.path)")
            }
            return url
        } catch {
            throw BookmarkError.resolveFailed
        }
    }

    @discardableResult
    static func startAccess(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    static func stopAccess(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}