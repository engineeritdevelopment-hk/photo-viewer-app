import Foundation

/// How photos under a source folder are shown in the grid.
enum SourceFolderView: String, CaseIterable, Sendable {
    /// Every photo under the source, including nested folders.
    case allNested
    /// Each folder on its own. A folder shows only the photos directly inside it.
    case byFolder

    var title: String {
        switch self {
        case .allNested: return "All"
        case .byFolder: return "By folder"
        }
    }
}

struct SourceFolderNode: Identifiable, Hashable, Sendable {
    var path: String
    var sourcePath: String
    /// Path relative to the source root, such as `2024` or `2024/Trip`.
    var relativePath: String
    var name: String
    var count: Int
    var depth: Int

    var id: String { path }
}

enum SourceFolderIndex {
    static func normalize(_ path: String) -> String {
        path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// True when `sourcePath` contains photos in two or more directories.
    static func sourceHasMultipleFolders(
        folderCounts: [(folder: String, count: Int)],
        sourcePath: String
    ) -> Bool {
        let root = normalize(sourcePath)
        let directories = folderCounts.map(\.folder).filter { folder in
            folder == root || folder.hasPrefix(root + "/")
        }
        return Set(directories).count >= 2
    }

    static func canBrowseByFolder(
        folderCounts: [(folder: String, count: Int)],
        sourcePaths: [String]
    ) -> Bool {
        sourcePaths.contains { sourceHasMultipleFolders(folderCounts: folderCounts, sourcePath: $0) }
    }

    /// Child folders of each source that contain photos directly. The source root stays the source row.
    static func nodes(
        folderCounts: [(folder: String, count: Int)],
        sourcePaths: [String]
    ) -> [SourceFolderNode] {
        let roots = sourcePaths.map(normalize).sorted { $0.count > $1.count }
        var nodes: [SourceFolderNode] = []
        for entry in folderCounts where entry.count > 0 {
            let folder = normalize(entry.folder)
            guard let root = roots.first(where: { folder.hasPrefix($0 + "/") }) else { continue }
            let relative = String(folder.dropFirst(root.count + 1))
            guard !relative.isEmpty else { continue }
            let parts = relative.split(separator: "/").map(String.init)
            nodes.append(
                SourceFolderNode(
                    path: folder,
                    sourcePath: root,
                    relativePath: relative,
                    name: parts.last ?? relative,
                    count: entry.count,
                    depth: parts.count
                )
            )
        }
        return nodes.sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
    }
}
