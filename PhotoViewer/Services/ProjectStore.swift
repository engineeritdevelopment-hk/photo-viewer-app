import Foundation

enum ProjectStoreError: LocalizedError {
    case unreadableProjectFile(detail: String)

    var errorDescription: String? {
        switch self {
        case .unreadableProjectFile(let detail):
            return """
            Couldn’t read projects.json (\(detail)). The app backed up the file as projects.json.bak and started fresh. Create a project or restore from the backup in Finder.

            ~/Library/Application Support/photo_viewer/
            """
        }
    }
}

enum ProjectStore {
    static func load() throws -> [LibraryProject] {
        let url = ApplicationPaths.projectsJSON
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }

        let data = try Data(contentsOf: url)
        let decoder = makeDecoder()

        if let wrapper = try? decoder.decode(ProjectsFile.self, from: data) {
            return sanitize(wrapper.projects.map(migrated))
        }

        if let projects = try? decoder.decode([LibraryProject].self, from: data) {
            return sanitize(projects.map(migrated))
        }

        if let salvaged = salvageProjects(from: data, decoder: decoder), !salvaged.isEmpty {
            try? save(salvaged)
            return salvaged
        }

        backupCorruptProjectsFile(at: url)
        let detail = (try? decoder.decode(ProjectsFile.self, from: data)).map { _ in "unknown schema" }
            ?? "format mismatch"
        throw ProjectStoreError.unreadableProjectFile(detail: detail)
    }

    static func save(_ projects: [LibraryProject]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let wrapper = ProjectsFile(projects: projects)
        let data = try encoder.encode(wrapper)
        try data.write(to: ApplicationPaths.projectsJSON, options: .atomic)
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                let withFraction = ISO8601DateFormatter()
                withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = withFraction.date(from: text) { return date }
                let standard = ISO8601DateFormatter()
                standard.formatOptions = [.withInternetDateTime]
                if let date = standard.date(from: text) { return date }
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date")
            }
            if let ms = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: ms > 10_000_000_000 ? ms / 1000 : ms)
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected date")
        }
        return decoder
    }

    private static func salvageProjects(from data: Data, decoder: JSONDecoder) -> [LibraryProject]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawProjects = root["projects"] as? [[String: Any]]
        else { return nil }

        var projects: [LibraryProject] = []
        for entry in rawProjects {
            guard let itemData = try? JSONSerialization.data(withJSONObject: entry),
                  let project = try? decoder.decode(LibraryProject.self, from: itemData)
            else { continue }
            projects.append(migrated(project))
        }
        return projects.isEmpty ? nil : sanitize(projects)
    }

    private static func sanitize(_ projects: [LibraryProject]) -> [LibraryProject] {
        projects.map { project in
            var copy = project
            copy.sourceBookmarks = project.sourceBookmarks.filter { !$0.bookmarkData.isEmpty }
            return copy
        }
    }

    private static func migrated(_ project: LibraryProject) -> LibraryProject {
        var copy = project
        copy.migrateLegacyFoldersIfNeeded()
        copy.sourceBookmarks = copy.sourceBookmarks.filter { !$0.bookmarkData.isEmpty }
        return copy
    }

    private static func backupCorruptProjectsFile(at url: URL) {
        let backup = url.deletingPathExtension().appendingPathExtension("json.bak")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.copyItem(at: url, to: backup)
    }
}