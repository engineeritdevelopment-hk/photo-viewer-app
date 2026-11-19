import Foundation

enum ApplicationPaths {
    private static var supportRootOverride: URL?

    /// Redirect app support paths to an isolated directory (unit tests only).
    static func useIsolatedSupportRoot(_ url: URL) {
        supportRootOverride = url
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func resetSupportRootOverride() {
        supportRootOverride = nil
    }

    static var supportRoot: URL {
        if let supportRootOverride { return supportRootOverride }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let root = base.appendingPathComponent("photo_viewer", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static var projectsJSON: URL {
        supportRoot.appendingPathComponent("projects.json")
    }

    static func indexDatabase(projectId: String) -> URL {
        let dir = supportRoot.appendingPathComponent("indexes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(projectId).sqlite")
    }

    static var thumbnailCache: URL {
        let dir = supportRoot.appendingPathComponent("thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var updateDownloads: URL {
        let dir = supportRoot.appendingPathComponent("updates/downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var updateStaging: URL {
        let dir = supportRoot.appendingPathComponent("updates/staging", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var geocodeCache: URL {
        supportRoot.appendingPathComponent("geocode-cache.json")
    }

    static func faceCrop(groupId: String) -> URL {
        let dir = supportRoot.appendingPathComponent("face-crops", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(groupId).jpg")
    }
}