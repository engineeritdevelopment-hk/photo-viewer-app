import Foundation

// MARK: - Image extensions

enum ImageFileRules {
    static let extensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "bmp", "tif", "tiff",
    ]

    static func isImage(path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return extensions.contains(ext)
    }

    static func normalizedExtension(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return trimmed }
        return trimmed.hasPrefix(".") ? String(trimmed.dropFirst()) : trimmed
    }
}

struct PhotoFilter: Codable, Equatable, Sendable {
    var excludedExtensions: [String] = []
    var excludedNameFragments: [String] = []

    func allows(path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        guard ImageFileRules.extensions.contains(ext) else { return false }

        let excluded = Set(excludedExtensions.map(ImageFileRules.normalizedExtension))
        if excluded.contains(ext) { return false }

        let name = (path as NSString).lastPathComponent.lowercased()
        for fragment in excludedNameFragments {
            let needle = fragment.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !needle.isEmpty, name.contains(needle) { return false }
        }
        return true
    }
}

struct PhotoAnnotation: Codable, Equatable, Identifiable, Sendable {
    var id: String { path }
    var path: String
    var place: String = ""
    var items: [String] = []
    var faces: [String] = []
    /// On-device title suggestion for export (does not rename source files).
    var suggestedTitle: String?
}

struct PersonGroup: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var displayName: String?
    var memberPhotoPaths: [String]
    var thumbnailPath: String?
    /// Cropped face JPEG in Application Support (`face-crops/`).
    var faceCropPath: String?
    /// Framed from a photo and searched. Listed under Filter in the sidebar.
    var isLookedUp: Bool

    init(
        id: String,
        displayName: String? = nil,
        memberPhotoPaths: [String] = [],
        thumbnailPath: String? = nil,
        faceCropPath: String? = nil,
        isLookedUp: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.memberPhotoPaths = memberPhotoPaths
        self.thumbnailPath = thumbnailPath
        self.faceCropPath = faceCropPath
        self.isLookedUp = isLookedUp
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case memberPhotoPaths
        case thumbnailPath
        case faceCropPath
        case isLookedUp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        memberPhotoPaths = try container.decodeIfPresent([String].self, forKey: .memberPhotoPaths) ?? []
        thumbnailPath = try container.decodeIfPresent(String.self, forKey: .thumbnailPath)
        faceCropPath = try container.decodeIfPresent(String.self, forKey: .faceCropPath)
        isLookedUp = try container.decodeIfPresent(Bool.self, forKey: .isLookedUp) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encode(memberPhotoPaths, forKey: .memberPhotoPaths)
        try container.encodeIfPresent(thumbnailPath, forKey: .thumbnailPath)
        try container.encodeIfPresent(faceCropPath, forKey: .faceCropPath)
        try container.encode(isLookedUp, forKey: .isLookedUp)
    }
}

enum AlbumKind: String, Codable, Sendable {
    case manual
    case smart
    /// System album for starred photos (not user-created).
    case favorites
}

extension Album {
    var isFavorites: Bool {
        id == AlbumConstants.favoritesAlbumId || kind == .favorites
    }
}

enum AlbumConstants {
    static let favoritesAlbumId = "favorites"
    static let favoritesAlbumName = "Favorites"
}

struct SmartAlbumRule: Codable, Equatable, Sendable {
    enum RuleType: String, Codable, Sendable {
        case semanticCategory
        case sceneLabelContains
        case ocrContains
        case personGroupId
        case hasFaces
        case screenshot
        case dateAfter
        case dateBefore
        case placeContains
        case hasGPS
        case cameraModelContains
        case sourcePathPrefix
    }

    var type: RuleType
    var value: String
}

struct SmartAlbumRules: Codable, Equatable, Sendable {
    var conditions: [SmartAlbumRule] = []
}

struct Album: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var kind: AlbumKind
    var memberPaths: [String] = []
    var rules: SmartAlbumRules?
    var lastEvaluatedAt: Date?
}

struct SourceBookmark: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var displayPath: String
    var bookmarkData: Data

    enum CodingKeys: String, CodingKey {
        case id
        case displayPath
        case bookmarkData
        case bookmarkDataBase64
    }

    init(id: String, displayPath: String, bookmarkData: Data) {
        self.id = id
        self.displayPath = displayPath
        self.bookmarkData = bookmarkData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayPath = try container.decode(String.self, forKey: .displayPath)
        if let data = try? container.decode(Data.self, forKey: .bookmarkData), !data.isEmpty {
            bookmarkData = data
        } else if let base64 = try? container.decode(String.self, forKey: .bookmarkData),
                  let data = Data(base64Encoded: base64)
        {
            bookmarkData = data
        } else if let base64 = try? container.decode(String.self, forKey: .bookmarkDataBase64),
                  let data = Data(base64Encoded: base64)
        {
            bookmarkData = data
        } else {
            bookmarkData = Data()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayPath, forKey: .displayPath)
        try container.encode(bookmarkData, forKey: .bookmarkData)
    }
}

struct LibraryProject: Codable, Identifiable, Sendable {
    var id: String
    var name: String
    var sources: [String] = []
    var sourceBookmarks: [SourceBookmark] = []
    var filter: PhotoFilter = PhotoFilter()
    var albums: [Album] = []
    var annotations: [PhotoAnnotation] = []
    var personGroups: [PersonGroup] = []
    /// Staging list of absolute paths pending deletion from source.
    var deleteBinPaths: [String] = []
    /// Set when a full analysis pass completes; used to detect stale categories/faces after new sources.
    var analysisCheckpoint: AnalysisCheckpoint?

    // Migration from Flutter `folders`
    var folders: [LegacyVirtualFolder]?

    struct LegacyVirtualFolder: Codable {
        var id: String
        var name: String
        var photoPaths: [String]
    }

    mutating func migrateLegacyFoldersIfNeeded() {
        guard let legacy = folders, !legacy.isEmpty, albums.isEmpty else { return }
        albums = legacy.map { folder in
            Album(id: folder.id, name: folder.name, kind: .manual, memberPaths: folder.photoPaths)
        }
        folders = nil
    }
}

struct AnalysisCheckpoint: Codable, Equatable, Sendable {
    var completedAt: Date
    var indexedPathCount: Int
    var sourceFingerprint: String
}

struct AnalysisStaleHint: Equatable, Sendable {
    var newPhotoCount: Int
    var sourcesChanged: Bool
    var neverAnalyzed: Bool
}

struct ProjectsFile: Codable {
    var projects: [LibraryProject]
}

// MARK: - Catalog row (index)

struct PhotoRecord: Identifiable, Equatable, Sendable {
    var id: String { path }
    var path: String
    var sourceId: String
    var modificationDate: Date
    var fileSize: Int64
    var takenAt: Date?
    var cameraMake: String?
    var cameraModel: String?
    var latitude: Double?
    var longitude: Double?
    var placeLabel: String?
    var hasGPS: Bool
    var width: Int?
    var height: Int?
    var isScreenshot: Bool
    var sceneLabels: [String]
    var ocrSnippet: String?
    var semanticCategory: String?
    var analysisSource: AnalysisSource?
    var personGroupIds: [String]
    var objectLabels: [String] = []
}

enum LibraryPhotoSort: String, CaseIterable, Identifiable, Sendable {
    case dateNewest
    case dateOldest
    case fileName

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dateNewest: return "Date (newest first)"
        case .dateOldest: return "Date (oldest first)"
        case .fileName: return "File name"
        }
    }

    var shortTitle: String {
        switch self {
        case .dateNewest: return "Newest"
        case .dateOldest: return "Oldest"
        case .fileName: return "Name"
        }
    }
}

enum LibraryGroupBy: String, CaseIterable, Identifiable {
    case none
    case date
    case location
    case camera
    case semantic
    case screenshots
    case people
    case albums
    case sources

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "All Photos"
        case .date: return "Date"
        case .location: return "Location"
        case .camera: return "Camera"
        case .semantic: return "Semantic"
        case .screenshots: return "Screenshots"
        case .people: return "People"
        case .albums: return "Albums"
        case .sources: return "Sources"
        }
    }
}

struct MetadataFilter: Equatable, Sendable {
    var takenAfter: Date?
    var takenBefore: Date?
    var cameraModels: Set<String> = []
    var requireGPS: Bool = false
    var placeQuery: String = ""
    var placeAnnotationQuery: String = ""
    var itemQuery: String = ""
    var personQuery: String = ""
}

struct LibraryActivity: Equatable, Sendable {
    var catalogScanned: Int = 0
    var catalogTotal: Int?
    var currentSourceName: String?
    var isCataloging = false

    var metadataDone: Int = 0
    var metadataTotal: Int = 0
    var isMetadataing = false

    var analyzed: Int = 0
    var analyzeTotal: Int = 0
    var isAnalyzing = false
    var analysisTitle = "Analyzing…"

    var facesProcessed: Int = 0
    var faceTotal: Int = 0
    var isFaceProcessing = false

    var faceSearchDone = 0
    var faceSearchTotal = 0
    var isSearchingFaces = false

    var geocoded: Int = 0
    var geocodeTotal: Int = 0
    var isGeocoding = false

    var exportCopied: Int = 0
    var exportTotal: Int = 0
    var isExporting = false

    var errorMessage: String?
}