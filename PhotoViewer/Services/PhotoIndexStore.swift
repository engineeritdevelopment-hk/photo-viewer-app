import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor PhotoIndexStore {
    private var db: OpaquePointer?
    private let dbURL: URL

    init(projectId: String) throws {
        try self.init(databaseAt: ApplicationPaths.indexDatabase(projectId: projectId))
    }

    init(databaseAt url: URL) throws {
        dbURL = url
        try open(allowWALRecovery: true)
        try migrate()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    private func open(allowWALRecovery: Bool) throws {
        let parent = dbURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        do {
            try openDatabase()
        } catch {
            guard allowWALRecovery else { throw error }
            quarantineWALSidecars()
            try openDatabase()
        }
    }

    private func openDatabase() throws {
        if let db {
            sqlite3_close(db)
            self.db = nil
        }

        var pointer: OpaquePointer?
        let code = sqlite3_open_v2(
            dbURL.path,
            &pointer,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard code == SQLITE_OK, let pointer else {
            let message = pointer.map { String(cString: sqlite3_errmsg($0)) } ?? "code \(code)"
            throw PhotoIndexError.openFailed(message)
        }
        db = pointer
        sqlite3_exec(pointer, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(pointer, "PRAGMA busy_timeout=10000;", nil, nil, nil)
        sqlite3_exec(pointer, "PRAGMA synchronous=NORMAL;", nil, nil, nil)
    }

    private func quarantineWALSidecars() {
        let wal = URL(fileURLWithPath: dbURL.path + "-wal")
        let shm = URL(fileURLWithPath: dbURL.path + "-shm")
        try? FileManager.default.removeItem(at: wal)
        try? FileManager.default.removeItem(at: shm)
    }

    private func migrate() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS photos (
            path TEXT PRIMARY KEY,
            source_id TEXT NOT NULL,
            mod_time REAL NOT NULL,
            file_size INTEGER NOT NULL,
            taken_at REAL,
            camera_make TEXT,
            camera_model TEXT,
            latitude REAL,
            longitude REAL,
            place_label TEXT,
            has_gps INTEGER NOT NULL DEFAULT 0,
            width INTEGER,
            height INTEGER,
            is_screenshot INTEGER NOT NULL DEFAULT 0,
            scene_labels TEXT,
            ocr_snippet TEXT,
            semantic_category TEXT,
            analysis_source TEXT,
            person_group_ids TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_photos_taken ON photos(taken_at);
        CREATE INDEX IF NOT EXISTS idx_photos_place ON photos(place_label);
        CREATE INDEX IF NOT EXISTS idx_photos_camera ON photos(camera_model);
        CREATE INDEX IF NOT EXISTS idx_photos_source ON photos(source_id);
        """)
    }

    func upsertCatalogRow(
        path: String,
        sourceId: String,
        modTime: Date,
        fileSize: Int64
    ) throws {
        let sql = """
        INSERT INTO photos (path, source_id, mod_time, file_size, has_gps, is_screenshot)
        VALUES (?, ?, ?, ?, 0, 0)
        ON CONFLICT(path) DO UPDATE SET
            source_id=excluded.source_id,
            mod_time=excluded.mod_time,
            file_size=excluded.file_size
        """
        try bind(sql, args: [
            .text(path),
            .text(sourceId),
            .real(modTime.timeIntervalSince1970),
            .int64(fileSize),
        ])
    }

    func updateMetadata(
        path: String,
        takenAt: Date?,
        cameraMake: String?,
        cameraModel: String?,
        latitude: Double?,
        longitude: Double?,
        hasGPS: Bool,
        width: Int?,
        height: Int?,
        isScreenshot: Bool
    ) throws {
        let sql = """
        UPDATE photos SET
            taken_at = ?,
            camera_make = ?,
            camera_model = ?,
            latitude = ?,
            longitude = ?,
            has_gps = ?,
            width = ?,
            height = ?,
            is_screenshot = ?
        WHERE path = ?
        """
        try bind(sql, args: [
            .optionalReal(takenAt?.timeIntervalSince1970),
            .optionalText(cameraMake),
            .optionalText(cameraModel),
            .optionalReal(latitude),
            .optionalReal(longitude),
            .int(hasGPS ? 1 : 0),
            .optionalInt(width),
            .optionalInt(height),
            .int(isScreenshot ? 1 : 0),
            .text(path),
        ])
    }

    func updatePlaceLabel(path: String, placeLabel: String?) throws {
        try bind(
            "UPDATE photos SET place_label = ? WHERE path = ?",
            args: [.optionalText(placeLabel), .text(path)]
        )
    }

    func updateAnalysis(
        path: String,
        sceneLabels: [String],
        ocrSnippet: String?,
        semanticCategory: String?,
        source: AnalysisSource
    ) throws {
        let labels = sceneLabels.joined(separator: "|")
        try bind(
            """
            UPDATE photos SET
                scene_labels = ?,
                ocr_snippet = ?,
                semantic_category = ?,
                analysis_source = ?
            WHERE path = ?
            """,
            args: [
                .optionalText(labels.isEmpty ? nil : labels),
                .optionalText(ocrSnippet),
                .optionalText(semanticCategory),
                .text(source.rawValue),
                .text(path),
            ]
        )
    }

    func updatePersonGroups(path: String, groupIds: [String]) throws {
        let joined = groupIds.joined(separator: "|")
        try bind(
            "UPDATE photos SET person_group_ids = ? WHERE path = ?",
            args: [.optionalText(joined.isEmpty ? nil : joined), .text(path)]
        )
    }

    func removeSource(_ sourceId: String) throws {
        try bind("DELETE FROM photos WHERE source_id = ?", args: [.text(sourceId)])
    }

    func removePath(_ path: String) throws {
        try bind("DELETE FROM photos WHERE path = ?", args: [.text(path)])
    }

    func removePaths(_ paths: [String]) throws {
        for path in paths {
            try removePath(path)
        }
    }

    func removePaths(withPathPrefix prefix: String) throws {
        try bind(
            "DELETE FROM photos WHERE path = ? OR path LIKE ?",
            args: [.text(prefix), .text(prefix + "/%")]
        )
    }

    func removePaths(notIn allowed: Set<String>) throws {
        guard !allowed.isEmpty else {
            try exec("DELETE FROM photos")
            return
        }
        let existing = try allPaths()
        let toDelete = existing.filter { !allowed.contains($0) }
        for path in toDelete {
            try bind("DELETE FROM photos WHERE path = ?", args: [.text(path)])
        }
    }

    func allPaths() throws -> [String] {
        var paths: [String] = []
        try query("SELECT path FROM photos") { stmt in
            if let cString = sqlite3_column_text(stmt, 0) {
                paths.append(String(cString: cString))
            }
        }
        return paths
    }

    /// Extensions present in the indexed library (from scanned sources), with photo counts.
    func mediaExtensionCounts() throws -> [(ext: String, count: Int)] {
        var counts: [String: Int] = [:]
        try query("SELECT path FROM photos") { stmt in
            guard let cString = sqlite3_column_text(stmt, 0) else { return }
            let path = String(cString: cString)
            let ext = (path as NSString).pathExtension.lowercased()
            guard !ext.isEmpty else { return }
            counts[ext, default: 0] += 1
        }
        return counts
            .map { (ext: $0.key, count: $0.value) }
            .sorted { $0.ext < $1.ext }
    }

    func count() throws -> Int {
        var total = 0
        try query("SELECT COUNT(*) FROM photos") { stmt in
            total = Int(sqlite3_column_int(stmt, 0))
        }
        return total
    }

    /// Earliest and latest capture/file dates in the index (`taken_at`, else `mod_time`).
    func indexedDateBounds() throws -> (earliest: Date, latest: Date)? {
        var minTs: Double?
        var maxTs: Double?
        try query("""
            SELECT MIN(COALESCE(taken_at, mod_time)), MAX(COALESCE(taken_at, mod_time))
            FROM photos
        """) { stmt in
            if sqlite3_column_type(stmt, 0) != SQLITE_NULL {
                minTs = sqlite3_column_double(stmt, 0)
            }
            if sqlite3_column_type(stmt, 1) != SQLITE_NULL {
                maxTs = sqlite3_column_double(stmt, 1)
            }
        }
        guard let minTs, let maxTs, minTs > 0, maxTs > 0 else { return nil }
        return (
            Date(timeIntervalSince1970: minTs),
            Date(timeIntervalSince1970: maxTs)
        )
    }

    func fetchPaths(
        limit: Int,
        offset: Int,
        metadata: MetadataFilter,
        projectFilter: PhotoFilter,
        extraPaths: Set<String>? = nil,
        sort: LibraryPhotoSort = .dateNewest
    ) throws -> [String] {
        var sql = "SELECT path FROM photos WHERE 1=1"
        var args: [SQLValue] = []

        if let extraPaths {
            if extraPaths.isEmpty { return [] }
            let placeholders = Array(repeating: "?", count: extraPaths.count).joined(separator: ",")
            sql += " AND path IN (\(placeholders))"
            args.append(contentsOf: extraPaths.sorted().map { .text($0) })
        }

        if let after = metadata.takenAfter {
            sql += " AND COALESCE(taken_at, mod_time) >= ?"
            args.append(.real(after.timeIntervalSince1970))
        }
        if let before = metadata.takenBefore {
            sql += " AND COALESCE(taken_at, mod_time) <= ?"
            args.append(.real(before.timeIntervalSince1970))
        }
        if metadata.requireGPS {
            sql += " AND has_gps = 1"
        }
        if !metadata.cameraModels.isEmpty {
            let placeholders = Array(repeating: "?", count: metadata.cameraModels.count).joined(separator: ",")
            sql += " AND camera_model IN (\(placeholders))"
            args.append(contentsOf: metadata.cameraModels.sorted().map { .text($0) })
        }
        if !metadata.placeQuery.isEmpty {
            sql += " AND (place_label LIKE ? COLLATE NOCASE)"
            args.append(.text("%\(metadata.placeQuery)%"))
        }
        if !metadata.itemQuery.isEmpty {
            sql += " AND (scene_labels LIKE ? OR ocr_snippet LIKE ? COLLATE NOCASE)"
            let pattern = "%\(metadata.itemQuery)%"
            args.append(.text(pattern))
            args.append(.text(pattern))
        }

        switch sort {
        case .dateNewest:
            sql += " ORDER BY COALESCE(taken_at, mod_time) DESC"
        case .dateOldest:
            sql += " ORDER BY COALESCE(taken_at, mod_time) ASC"
        case .fileName:
            sql += " ORDER BY path ASC"
        }
        sql += " LIMIT ? OFFSET ?"
        args.append(.int(limit))
        args.append(.int(offset))

        var paths: [String] = []
        try query(sql, args: args) { stmt in
            guard let cString = sqlite3_column_text(stmt, 0) else { return }
            let path = String(cString: cString)
            if projectFilter.allows(path: path) {
                paths.append(path)
            }
        }
        return paths
    }

    func record(for path: String) throws -> PhotoRecord? {
        var record: PhotoRecord?
        try query("SELECT * FROM photos WHERE path = ?", args: [.text(path)]) { stmt in
            record = Self.decodeRecord(stmt)
        }
        return record
    }

    func sidebarCounts() throws -> (screenshots: Int, withGPS: Int) {
        var screenshots = 0
        var gps = 0
        try query("SELECT COUNT(*) FROM photos WHERE is_screenshot = 1") { stmt in
            screenshots = Int(sqlite3_column_int(stmt, 0))
        }
        try query("SELECT COUNT(*) FROM photos WHERE has_gps = 1") { stmt in
            gps = Int(sqlite3_column_int(stmt, 0))
        }
        return (screenshots, gps)
    }

    func groupBySemantic() throws -> [(name: String, count: Int)] {
        var map: [String: Int] = [:]
        try query("SELECT semantic_category, COUNT(*) FROM photos WHERE semantic_category IS NOT NULL GROUP BY semantic_category") { stmt in
            guard let cString = sqlite3_column_text(stmt, 0) else { return }
            let name = String(cString: cString)
            map[name] = Int(sqlite3_column_int(stmt, 1))
        }
        return map.map { ($0.key, $0.value) }.sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
    }

    func groupByCamera() throws -> [(name: String, count: Int)] {
        var map: [String: Int] = [:]
        try query("""
            SELECT COALESCE(camera_make,'') || ' / ' || COALESCE(camera_model,'Unknown'), COUNT(*)
            FROM photos WHERE camera_model IS NOT NULL
            GROUP BY camera_make, camera_model
            """) { stmt in
            guard let cString = sqlite3_column_text(stmt, 0) else { return }
            let name = String(cString: cString)
            map[name] = Int(sqlite3_column_int(stmt, 1))
        }
        return map.map { ($0.key, $0.value) }.sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
    }

    func groupByYear() throws -> [(year: String, count: Int)] {
        var rows: [(String, Int)] = []
        try query("""
            SELECT strftime('%Y', datetime(COALESCE(taken_at, mod_time), 'unixepoch', 'localtime')) AS yr, COUNT(*)
            FROM photos
            WHERE COALESCE(taken_at, mod_time) IS NOT NULL
            GROUP BY yr
            HAVING yr IS NOT NULL AND yr != ''
            ORDER BY yr DESC
            """) { stmt in
            guard let cString = sqlite3_column_text(stmt, 0) else { return }
            let year = String(cString: cString)
            rows.append((year, Int(sqlite3_column_int(stmt, 1))))
        }
        return rows.map { (year: $0.0, count: $0.1) }
    }

    func pathsForYear(_ year: Int) throws -> [String] {
        var calendar = Calendar.current
        calendar.timeZone = .current
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(from: DateComponents(year: year, month: 12, day: 31, hour: 23, minute: 59, second: 59))
        else { return [] }
        let formatter = ISO8601DateFormatter()
        let rules = SmartAlbumRules(conditions: [
            SmartAlbumRule(type: .dateAfter, value: formatter.string(from: start)),
            SmartAlbumRule(type: .dateBefore, value: formatter.string(from: end)),
        ])
        return try pathsForSmartRules(rules)
    }

    func groupByPlace() throws -> [(name: String, count: Int)] {
        var map: [String: Int] = [:]
        try query("""
            SELECT COALESCE(NULLIF(place_label,''), 'No location') AS label, COUNT(*) FROM photos
            GROUP BY label
            """) { stmt in
            guard let cString = sqlite3_column_text(stmt, 0) else { return }
            let name = String(cString: cString)
            map[name] = Int(sqlite3_column_int(stmt, 1))
        }
        return map.map { ($0.key, $0.value) }.sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
    }

    func pathsForSmartRules(_ rules: SmartAlbumRules) throws -> [String] {
        guard !rules.conditions.isEmpty else { return [] }
        var sql = "SELECT path FROM photos WHERE "
        var parts: [String] = []
        var args: [SQLValue] = []

        for rule in rules.conditions {
            switch rule.type {
            case .semanticCategory:
                parts.append("semantic_category = ?")
                args.append(.text(rule.value))
            case .sceneLabelContains:
                parts.append("scene_labels LIKE ? COLLATE NOCASE")
                args.append(.text("%\(rule.value)%"))
            case .ocrContains:
                parts.append("ocr_snippet LIKE ? COLLATE NOCASE")
                args.append(.text("%\(rule.value)%"))
            case .personGroupId:
                parts.append("person_group_ids LIKE ?")
                args.append(.text("%\(rule.value)%"))
            case .hasFaces:
                parts.append("person_group_ids IS NOT NULL AND person_group_ids != ''")
            case .screenshot:
                parts.append("is_screenshot = 1")
            case .dateAfter:
                if let date = ISO8601DateFormatter().date(from: rule.value) {
                    parts.append("COALESCE(taken_at, mod_time) >= ?")
                    args.append(.real(date.timeIntervalSince1970))
                }
            case .dateBefore:
                if let date = ISO8601DateFormatter().date(from: rule.value) {
                    parts.append("COALESCE(taken_at, mod_time) <= ?")
                    args.append(.real(date.timeIntervalSince1970))
                }
            case .placeContains:
                parts.append("place_label LIKE ? COLLATE NOCASE")
                args.append(.text("%\(rule.value)%"))
            case .hasGPS:
                parts.append("has_gps = 1")
            case .cameraModelContains:
                parts.append("camera_model LIKE ? COLLATE NOCASE")
                args.append(.text("%\(rule.value)%"))
            case .sourcePathPrefix:
                parts.append("path LIKE ?")
                args.append(.text("\(rule.value)%"))
            }
        }

        sql += parts.joined(separator: " AND ")
        sql += " ORDER BY COALESCE(taken_at, mod_time) DESC"

        var paths: [String] = []
        try query(sql, args: args) { stmt in
            guard let cString = sqlite3_column_text(stmt, 0) else { return }
            paths.append(String(cString: cString))
        }
        return paths
    }

    private static func decodeRecord(_ stmt: OpaquePointer?) -> PhotoRecord? {
        guard let stmt,
              let pathCString = sqlite3_column_text(stmt, 0) else { return nil }
        let path = String(cString: pathCString)
        let sourceId = textColumn(stmt, 1) ?? ""
        let modTime = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
        let fileSize = sqlite3_column_int64(stmt, 3)
        let takenAt = optionalDate(stmt, 4)
        let cameraMake = textColumn(stmt, 5)
        let cameraModel = textColumn(stmt, 6)
        let latitude = optionalDouble(stmt, 7)
        let longitude = optionalDouble(stmt, 8)
        let placeLabel = textColumn(stmt, 9)
        let hasGPS = sqlite3_column_int(stmt, 10) == 1
        let width = optionalInt(stmt, 11)
        let height = optionalInt(stmt, 12)
        let isScreenshot = sqlite3_column_int(stmt, 13) == 1
        let sceneLabels = (textColumn(stmt, 14) ?? "").split(separator: "|").map(String.init)
        let ocrSnippet = textColumn(stmt, 15)
        let semanticCategory = textColumn(stmt, 16)
        let analysisRaw = textColumn(stmt, 17)
        let analysisSource = analysisRaw.flatMap(AnalysisSource.init(rawValue:))
        let personIds = (textColumn(stmt, 18) ?? "").split(separator: "|").map(String.init)

        return PhotoRecord(
            path: path,
            sourceId: sourceId,
            modificationDate: modTime,
            fileSize: fileSize,
            takenAt: takenAt,
            cameraMake: cameraMake,
            cameraModel: cameraModel,
            latitude: latitude,
            longitude: longitude,
            placeLabel: placeLabel,
            hasGPS: hasGPS,
            width: width,
            height: height,
            isScreenshot: isScreenshot,
            sceneLabels: sceneLabels,
            ocrSnippet: ocrSnippet,
            semanticCategory: semanticCategory,
            analysisSource: analysisSource,
            personGroupIds: personIds
        )
    }

    private static func textColumn(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cString)
    }

    private static func optionalDate(_ stmt: OpaquePointer?, _ index: Int32) -> Date? {
        let value = sqlite3_column_double(stmt, index)
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    private static func optionalDouble(_ stmt: OpaquePointer?, _ index: Int32) -> Double? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL { return nil }
        return sqlite3_column_double(stmt, index)
    }

    private static func optionalInt(_ stmt: OpaquePointer?, _ index: Int32) -> Int? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL { return nil }
        return Int(sqlite3_column_int(stmt, index))
    }

    // MARK: - SQLite helpers

    private enum SQLValue {
        case text(String)
        case optionalText(String?)
        case int(Int)
        case optionalInt(Int?)
        case int64(Int64)
        case real(Double)
        case optionalReal(Double?)
    }

    private func exec(_ sql: String) throws {
        guard let db else { throw PhotoIndexError.noDatabase }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown"
            if let errorMessage { sqlite3_free(errorMessage) }
            throw PhotoIndexError.exec(message)
        }
    }

    private func bind(_ sql: String, args: [SQLValue] = []) throws {
        guard let db else { throw PhotoIndexError.noDatabase }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw PhotoIndexError.prepare
        }
        defer { sqlite3_finalize(stmt) }

        for (index, arg) in args.enumerated() {
            let position = Int32(index + 1)
            switch arg {
            case .text(let value):
                sqlite3_bind_text(stmt, position, value, -1, SQLITE_TRANSIENT)
            case .optionalText(let value):
                if let value {
                    sqlite3_bind_text(stmt, position, value, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, position)
                }
            case .int(let value):
                sqlite3_bind_int(stmt, position, Int32(value))
            case .optionalInt(let value):
                if let value {
                    sqlite3_bind_int(stmt, position, Int32(value))
                } else {
                    sqlite3_bind_null(stmt, position)
                }
            case .int64(let value):
                sqlite3_bind_int64(stmt, position, value)
            case .real(let value):
                sqlite3_bind_double(stmt, position, value)
            case .optionalReal(let value):
                if let value {
                    sqlite3_bind_double(stmt, position, value)
                } else {
                    sqlite3_bind_null(stmt, position)
                }
            }
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            let message = String(cString: sqlite3_errmsg(db))
            throw PhotoIndexError.exec(message)
        }
    }

    private func query(_ sql: String, args: [SQLValue] = [], row: (OpaquePointer?) -> Void) throws {
        guard let db else { throw PhotoIndexError.noDatabase }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw PhotoIndexError.prepare
        }
        defer { sqlite3_finalize(stmt) }

        for (index, arg) in args.enumerated() {
            let position = Int32(index + 1)
            if case .text(let value) = arg {
                sqlite3_bind_text(stmt, position, value, -1, SQLITE_TRANSIENT)
            } else if case .int(let value) = arg {
                sqlite3_bind_int(stmt, position, Int32(value))
            } else if case .real(let value) = arg {
                sqlite3_bind_double(stmt, position, value)
            } else if case .int64(let value) = arg {
                sqlite3_bind_int64(stmt, position, value)
            }
        }

        while sqlite3_step(stmt) == SQLITE_ROW {
            row(stmt)
        }
    }
}

enum PhotoIndexError: Error, LocalizedError {
    case openFailed(String?)
    case noDatabase
    case prepare
    case step
    case exec(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            if let message, !message.isEmpty { return "Could not open photo index: \(message)" }
            return "Could not open photo index."
        case .noDatabase: return "Photo index database unavailable."
        case .prepare: return "Could not prepare SQL."
        case .step: return "Could not execute SQL step."
        case .exec(let message): return message
        }
    }
}