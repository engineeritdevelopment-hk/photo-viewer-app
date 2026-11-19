import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class LibraryViewModel {
    var project: LibraryProject
    var activity = LibraryActivity()
    var visiblePaths: [String] = []
    var groupBy: LibraryGroupBy = .none
    var selectedSidebarKey: String?
    var selectedAlbumId: String?
    var metadataFilter = MetadataFilter()
    /// File extensions in the index (`ext`, count), sorted.
    var detectedMediaExtensions: [(ext: String, count: Int)] = []
    /// Included types for the grid; when equal to all detected, no media-type filter is applied.
    var selectedMediaExtensions: Set<String> = []
    var photoSort: LibraryPhotoSort = .dateNewest
    var categoryDetectionOn = false
    var analyzeFacesOn = false
    var isSelectingPhotos = false
    var selectedPaths: Set<String> = []
    var isCombiningPeople = false
    var peopleMergeSelection: Set<String> = []

    /// Auto-detected semantic categories for the chip row (not created as albums until pinned).
    var detectedCategories: [(title: String, count: Int, rule: SmartAlbumRule)] = []
    var analysisStaleHint: AnalysisStaleHint?
    private var analysisStaleBannerSuppressed = false
    var sidebarYears: [(year: String, count: Int)] = []
    var sidebarPlaces: [(name: String, count: Int)] = []
    var sidebarCameras: [(name: String, count: Int)] = []
    var sidebarScreenshotCount = 0
    /// Bounds for date filter placeholders (full indexed library).
    var indexedDateEarliest: Date?
    var indexedDateLatest: Date?

    var deleteBinCount: Int { project.deleteBinPaths.count }

    var isViewingDeleteBin: Bool { selectedSidebarKey == "bin" }

    var shouldShowAnalysisStaleBanner: Bool {
        guard analysisStaleHint != nil, !analysisStaleBannerSuppressed else { return false }
        return !isAnalysisRunning && !activity.isCataloging
    }

    private let thumbnails = ThumbnailService()
    private let catalog = PhotoCatalogScanner()
    private let analysis = AnalysisPipeline()
    private let placeService = PlaceLabelService()
    private var index: PhotoIndexStore?
    private var catalogTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var visiblePathsReloadToken = 0
    private var appliedVisiblePathsQueryFingerprint: String?
    private var generation = 0
    private let projects: ProjectsViewModel
    private let securityScope = SecurityScopeManager()

    init(project: LibraryProject, projects: ProjectsViewModel) {
        self.project = project
        self.projects = projects
    }

    func onAppear() {
        normalizeFavoritesAlbum()
        startIfNeeded()
    }

    /// Ensures the Favorites album uses `AlbumKind.favorites` (legacy projects used `.manual`).
    func normalizeFavoritesAlbum() {
        guard let index = project.albums.firstIndex(where: {
            $0.id == AlbumConstants.favoritesAlbumId
                || ($0.name == AlbumConstants.favoritesAlbumName && $0.kind == .manual)
        }) else { return }
        var album = project.albums[index]
        album.id = AlbumConstants.favoritesAlbumId
        album.name = AlbumConstants.favoritesAlbumName
        album.kind = .favorites
        project.albums[index] = album
        project.albums.removeAll { other in
            other.id != album.id
                && other.name == AlbumConstants.favoritesAlbumName
                && other.kind == .manual
        }
        projects.update(project)
    }

    func close() {
        generation += 1
        let priorCatalog = catalogTask
        let priorAnalysis = analysisTask
        catalogTask = nil
        analysisTask = nil
        priorCatalog?.cancel()
        priorAnalysis?.cancel()
        Task {
            await priorCatalog?.value
            await priorAnalysis?.value
            securityScope.releaseAll()
        }
    }

    private func ensureIndex() throws {
        if index == nil {
            index = try PhotoIndexStore(projectId: project.id)
        }
    }

    func startIfNeeded() {
        generation += 1
        let current = generation
        analysisTask?.cancel()

        let priorCatalog = catalogTask
        priorCatalog?.cancel()

        catalogTask = Task {
            if let priorCatalog {
                await priorCatalog.value
            }
            guard !Task.isCancelled, current == generation else { return }

            do {
                try ensureIndex()
            } catch {
                activity.errorMessage = error.localizedDescription
                return
            }

            activity.isCataloging = true
            activity.catalogScanned = 0
            activity.catalogTotal = nil
            visiblePaths = []

            let sources = resolvedSources()
            guard !sources.isEmpty else {
                activity.isCataloging = false
                return
            }

            guard let store = index else { return }
            let stream = await catalog.scan(sources: sources, filter: project.filter, index: store)
            var lastGridRefresh = Date.distantPast
            for await progress in stream {
                guard !Task.isCancelled, current == generation else { return }
                activity.catalogScanned = progress.scanned
                activity.currentSourceName = progress.currentSource
                if !progress.pathsBatch.isEmpty {
                    let now = Date()
                    if now.timeIntervalSince(lastGridRefresh) > 0.35
                        || progress.scanned == 1
                        || progress.pathsBatch.count >= 96
                    {
                        await reloadVisiblePaths()
                        lastGridRefresh = now
                    }
                }
                await Task.yield()
            }

            guard !Task.isCancelled, current == generation else { return }
            activity.isCataloging = false
            analysisStaleBannerSuppressed = false
            if let counts = try? await store.mediaExtensionCounts() {
                syncDetectedMediaTypes(counts)
            }
            await refreshSidebarBuckets()
            appliedVisiblePathsQueryFingerprint = nil
            await reloadVisiblePaths()
            await refreshAnalysisStaleHint()
        }
    }

    func refreshSidebarBuckets() async {
        guard let store = index else { return }
        sidebarYears = (try? await store.groupByYear()) ?? []
        sidebarPlaces = ((try? await store.groupByPlace()) ?? []).filter { $0.count > 0 }
        sidebarCameras = ((try? await store.groupByCamera()) ?? []).filter { $0.count > 0 }
        if let counts = try? await store.sidebarCounts() {
            sidebarScreenshotCount = counts.screenshots
        }
        await loadDetectedCategories()
        await refreshIndexedDateRange()
    }

    func defaultDateFilterFrom() -> Date {
        if let indexedDateEarliest {
            return startOfDay(indexedDateEarliest)
        }
        return startOfDay(Date())
    }

    func defaultDateFilterTo() -> Date {
        if let indexedDateLatest {
            return startOfDay(indexedDateLatest)
        }
        return startOfDay(Date())
    }

    private func refreshIndexedDateRange() async {
        guard let store = index else {
            indexedDateEarliest = nil
            indexedDateLatest = nil
            return
        }
        guard let bounds = try? await store.indexedDateBounds() else {
            indexedDateEarliest = nil
            indexedDateLatest = nil
            return
        }
        indexedDateEarliest = bounds.earliest
        indexedDateLatest = bounds.latest
    }

    var isAnalysisRunning: Bool {
        activity.isMetadataing || activity.isAnalyzing || activity.isFaceProcessing || activity.isGeocoding
    }

    var canStartAnalysis: Bool {
        (categoryDetectionOn || analyzeFacesOn)
            && !isAnalysisRunning
            && !activity.isCataloging
            && index != nil
    }

    func startAnalysis() {
        guard canStartAnalysis else { return }
        Task { await runAnalysisIfNeeded(generation: generation) }
    }

    func stopAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        Task { await analysis.setPaused(false) }
        activity.isMetadataing = false
        activity.isAnalyzing = false
        activity.isFaceProcessing = false
        activity.isGeocoding = false
    }

    private func resolvedSources() -> [(id: String, url: URL)] {
        var resolved: [(String, URL)] = []
        var errors: [String] = []

        for bookmark in project.sourceBookmarks {
            do {
                let url = try securityScope.beginAccess(sourceID: bookmark.id, bookmarkData: bookmark.bookmarkData)
                resolved.append((bookmark.id, url))
            } catch {
                errors.append(error.localizedDescription)
            }
        }

        // Legacy path-only sources (pre-bookmark); user must re-add for sandbox + external disks.
        for path in project.sources where !project.sourceBookmarks.contains(where: { $0.displayPath == path }) {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            if FileManager.default.fileExists(atPath: path) {
                resolved.append((path, url))
            } else {
                errors.append("Source missing: \(path). Re-add the folder after connecting the drive.")
            }
        }

        if !errors.isEmpty {
            activity.errorMessage = errors.joined(separator: "\n")
        } else if activity.errorMessage?.contains("correct format") == true
            || activity.errorMessage?.contains("couldn’t be opened") == true
        {
            activity.errorMessage = nil
        }

        return resolved
    }

    func addSourceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Source"
        panel.message = "Choose a folder of photos (read-only)."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Panel URLs are security-scoped; access must be active while creating the bookmark.
        let panelAccess = url.startAccessingSecurityScopedResource()
        defer {
            if panelAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard panelAccess else {
            activity.errorMessage = BookmarkStore.BookmarkError.accessDenied(url).localizedDescription
            return
        }

        do {
            let data = try BookmarkStore.makeBookmark(for: url)
            let sourceID = UUID().uuidString
            let bookmark = SourceBookmark(
                id: sourceID,
                displayPath: url.path,
                bookmarkData: data
            )
            project.sourceBookmarks.append(bookmark)
            if !project.sources.contains(url.path) {
                project.sources.append(url.path)
            }
            projects.update(project)
            _ = try? securityScope.beginAccess(sourceID: sourceID, bookmarkData: data)
            activity.errorMessage = nil
            analysisStaleBannerSuppressed = false
            do {
                try ensureIndex()
            } catch {
                activity.errorMessage = error.localizedDescription
            }
            Task { await refreshAnalysisStaleHint() }
            startIfNeeded()
        } catch {
            activity.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func removeSource(id: String) {
        securityScope.release(sourceID: id)
        let removedPath = project.sourceBookmarks.first(where: { $0.id == id })?.displayPath
        project.sourceBookmarks.removeAll { $0.id == id }
        if let removedPath {
            project.sources.removeAll { $0 == removedPath }
        }
        projects.update(project)
        Task {
            try? await index?.removeSource(id)
            analysisStaleBannerSuppressed = false
            await reloadVisiblePaths()
            await refreshAnalysisStaleHint()
        }
    }

    func deleteAlbum(id: String) {
        guard id != AlbumConstants.favoritesAlbumId else { return }
        project.albums.removeAll { $0.id == id }
        if selectedAlbumId == id {
            clearAlbumFilter(reload: false)
        }
        projects.update(project)
        scheduleReloadVisiblePaths()
    }

    func selectAlbum(id: String) {
        if groupBy == .albums, selectedAlbumId == id {
            clearAlbumFilter()
            return
        }
        groupBy = .albums
        selectedAlbumId = id
        selectedSidebarKey = "album:\(id)"
        scheduleReloadVisiblePaths()
    }

    func clearAlbumFilter(reload: Bool = true) {
        guard groupBy == .albums || selectedAlbumId != nil else { return }
        groupBy = .none
        selectedAlbumId = nil
        if selectedSidebarKey?.hasPrefix("album:") == true {
            selectedSidebarKey = nil
        }
        guard reload else { return }
        scheduleReloadVisiblePaths()
    }

    /// Filter section row tapped (DisclosureGroup children do not always update List selection on macOS).
    func selectSidebarFilter(_ key: String?) {
        if let key, selectedSidebarKey == key {
            selectedSidebarKey = nil
        } else {
            selectedSidebarKey = key
        }
    }

    /// Keep album filter in sync with sidebar list selection (`album:…` vs everything else).
    func applySidebarKey(_ key: String?) {
        if let key, key.hasPrefix("album:") {
            let id = String(key.dropFirst("album:".count))
            guard selectedAlbumId != id || groupBy != .albums else { return }
            groupBy = .albums
            selectedAlbumId = id
            scheduleReloadVisiblePaths()
            return
        }
        clearAlbumFilter(reload: false)
        scheduleReloadVisiblePaths()
    }

    func removeLegacySource(path: String) {
        project.sources.removeAll { $0 == path }
        projects.update(project)
        Task {
            try? await index?.removePaths(withPathPrefix: path)
            await reloadVisiblePaths()
        }
    }

    var isMediaTypeFilterActive: Bool {
        let all = Set(detectedMediaExtensions.map(\.ext))
        return !all.isEmpty && selectedMediaExtensions != all
    }

    var hasDateRangeFilter: Bool {
        metadataFilter.takenAfter != nil || metadataFilter.takenBefore != nil
    }

    var isViewFiltered: Bool {
        !filterBannerDescriptions.isEmpty
    }

    var hasNarrowedGrid: Bool {
        if groupBy == .albums, selectedAlbumId != nil { return true }
        if let key = selectedSidebarKey, !key.isEmpty { return true }
        if isMediaTypeFilterActive { return true }
        if hasDateRangeFilter { return true }
        return false
    }

    var viewFilterSummary: String {
        filterBannerDescriptions.joined(separator: " · ")
    }

    /// Shown in the bottom filter banner (category chips & delete bin have their own affordances).
    var filterBannerDescriptions: [String] {
        gridFilterDescriptionParts(includeCategoryChips: false, includeDeleteBin: false)
    }

    var activeFilterDescriptions: [String] {
        gridFilterDescriptionParts(includeCategoryChips: true, includeDeleteBin: true)
    }

    private func gridFilterDescriptionParts(includeCategoryChips: Bool, includeDeleteBin: Bool) -> [String] {
        var parts: [String] = []

        if groupBy == .albums, let id = selectedAlbumId,
           let album = project.albums.first(where: { $0.id == id }) {
            parts.append("Album: \(album.name)")
        } else if let key = selectedSidebarKey {
            switch key {
            case "bin":
                if includeDeleteBin {
                    parts.append("Delete bin")
                }
            case let key where key.hasPrefix("album:"):
                let id = String(key.dropFirst("album:".count))
                if let album = project.albums.first(where: { $0.id == id }) {
                    parts.append("Album: \(album.name)")
                }
            case let key where key.hasPrefix("person:"):
                let id = String(key.dropFirst("person:".count))
                let name = project.personGroups.first(where: { $0.id == id })?.displayName
                let label = (name?.isEmpty == false) ? name! : "Person"
                parts.append("Person: \(label)")
            case "browse:screenshots":
                parts.append("Screenshots")
            case let key where key.hasPrefix("date:"):
                let year = String(key.dropFirst("date:".count))
                parts.append("Year: \(year)")
            case let key where key.hasPrefix("semantic:"):
                if includeCategoryChips {
                    parts.append("Category: \(String(key.dropFirst("semantic:".count)))")
                }
            case let key where key.hasPrefix("camera:"):
                parts.append("Camera: \(String(key.dropFirst("camera:".count)))")
            case let key where key.hasPrefix("place:"):
                parts.append("Place: \(String(key.dropFirst("place:".count)))")
            case let key where key.hasPrefix("source:"):
                let prefix = String(key.dropFirst("source:".count))
                let short = (prefix as NSString).lastPathComponent
                parts.append("Source: \(short)")
            default:
                break
            }
        }

        if isMediaTypeFilterActive {
            let labels = selectedMediaExtensions.sorted().map { $0.uppercased() }
            parts.append("Types: \(labels.joined(separator: ", "))")
        }

        if let summary = dateRangeFilterSummary {
            parts.append(summary)
        }

        return parts
    }

    private var dateRangeFilterSummary: String? {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        switch (metadataFilter.takenAfter, metadataFilter.takenBefore) {
        case (let from?, let to?):
            return "Dates: \(formatter.string(from: from)) – \(formatter.string(from: to))"
        case (let from?, nil):
            return "From \(formatter.string(from: from))"
        case (nil, let to?):
            return "Through \(formatter.string(from: to))"
        case (nil, nil):
            return nil
        }
    }

    func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    func endOfDay(_ date: Date) -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }

    func applyMetadataFilter(_ filter: MetadataFilter) {
        metadataFilter = filter
        scheduleReloadVisiblePaths()
    }

    func resetAllViewFilters() {
        groupBy = .none
        selectedAlbumId = nil
        selectedSidebarKey = nil
        metadataFilter = MetadataFilter()
        appliedVisiblePathsQueryFingerprint = nil
        if !detectedMediaExtensions.isEmpty {
            selectedMediaExtensions = Set(detectedMediaExtensions.map(\.ext))
        }
        scheduleReloadVisiblePaths()
    }

    func setNameFilter(excludedNames: String) {
        project.filter.excludedNameFragments = splitList(excludedNames)
        projects.update(project)
        startIfNeeded()
    }

    func toggleMediaType(_ ext: String) {
        let normalized = ImageFileRules.normalizedExtension(ext)
        if selectedMediaExtensions.contains(normalized) {
            selectedMediaExtensions.remove(normalized)
        } else {
            selectedMediaExtensions.insert(normalized)
        }
        scheduleReloadVisiblePaths()
    }

    func selectAllMediaTypes() {
        selectedMediaExtensions = Set(detectedMediaExtensions.map(\.ext))
        scheduleReloadVisiblePaths()
    }

    func scheduleReloadVisiblePaths() {
        visiblePathsReloadToken += 1
        let token = visiblePathsReloadToken
        Task {
            try? await Task.sleep(for: .milliseconds(48))
            guard token == visiblePathsReloadToken else { return }
            await reloadVisiblePaths()
        }
    }

    func reloadVisiblePaths() async {
        guard let store = index else { return }
        let fingerprint = visiblePathsQueryFingerprint()
        if fingerprint == appliedVisiblePathsQueryFingerprint, !visiblePaths.isEmpty {
            return
        }
        do {
            var paths = try await visiblePathQuery(store: store)
            paths = filterPathsBySelectedMediaTypes(paths)
            visiblePaths = paths
            appliedVisiblePathsQueryFingerprint = fingerprint
        } catch {
            activity.errorMessage = error.localizedDescription
        }
    }

    private func visiblePathsQueryFingerprint() -> String {
        let media = selectedMediaExtensions.sorted().joined(separator: ",")
        let filter = metadataFilter
        let after = filter.takenAfter?.timeIntervalSince1970.description ?? ""
        let before = filter.takenBefore?.timeIntervalSince1970.description ?? ""
        let person = filter.personQuery
        return [
            groupBy.rawValue,
            selectedAlbumId ?? "",
            selectedSidebarKey ?? "",
            photoSort.rawValue,
            media,
            after,
            before,
            person,
            project.filter.excludedNameFragments.joined(separator: "|"),
            project.filter.excludedExtensions.joined(separator: "|"),
        ].joined(separator: "\u{1e}")
    }

    private func syncDetectedMediaTypes(_ counts: [(ext: String, count: Int)]) {
        let newDetected = Set(counts.map(\.ext))
        let previousDetected = Set(detectedMediaExtensions.map(\.ext))
        let hadAllSelected = previousDetected.isEmpty
            || selectedMediaExtensions == previousDetected

        detectedMediaExtensions = counts

        if hadAllSelected {
            selectedMediaExtensions = newDetected
        } else {
            selectedMediaExtensions.formIntersection(newDetected)
            selectedMediaExtensions.formUnion(newDetected.subtracting(previousDetected))
        }
    }

    private func filterPathsBySelectedMediaTypes(_ paths: [String]) -> [String] {
        guard isMediaTypeFilterActive else { return paths }
        guard !selectedMediaExtensions.isEmpty else { return [] }
        return paths.filter { path in
            let ext = (path as NSString).pathExtension.lowercased()
            return selectedMediaExtensions.contains(ext)
        }
    }

    private func visiblePathQuery(store: PhotoIndexStore) async throws -> [String] {
        var extra: Set<String>?
        switch groupBy {
        case .none:
            extra = nil
        case .screenshots:
            extra = Set(try await store.pathsForSmartRules(SmartAlbumRules(conditions: [
                SmartAlbumRule(type: .screenshot, value: "1"),
            ])))
        case .albums:
            if let albumId = selectedAlbumId,
               let album = project.albums.first(where: { $0.id == albumId }) {
                switch album.kind {
                case .manual, .favorites:
                    extra = Set(album.memberPaths)
                case .smart:
                    let rules = album.rules ?? SmartAlbumRules()
                    extra = Set(try await store.pathsForSmartRules(rules))
                }
            } else {
                extra = Set()
            }
        default:
            extra = nil
        }

        if let key = selectedSidebarKey {
            extra = try await sidebarFilter(key: key, store: store, current: extra)
        }

        if !metadataFilter.personQuery.isEmpty {
            extra = try await filterByPersonName(
                query: metadataFilter.personQuery,
                store: store,
                current: extra
            )
        }

        return try await store.fetchPaths(
            limit: 5000,
            offset: 0,
            metadata: metadataFilter,
            projectFilter: project.filter,
            extraPaths: extra,
            sort: photoSort
        )
    }

    func setPhotoSort(_ sort: LibraryPhotoSort) {
        guard photoSort != sort else { return }
        photoSort = sort
        scheduleReloadVisiblePaths()
    }

    private func sidebarFilter(key: String, store: PhotoIndexStore, current: Set<String>?) async throws -> Set<String> {
        if key == "browse:screenshots" {
            return Set(try await store.pathsForSmartRules(SmartAlbumRules(conditions: [
                SmartAlbumRule(type: .screenshot, value: "1"),
            ])))
        }
        if key.hasPrefix("date:") {
            let yearString = String(key.dropFirst("date:".count))
            guard let year = Int(yearString) else {
                if let current { return current }
                return Set(try await store.allPaths())
            }
            let paths = Set(try await store.pathsForYear(year))
            if let current { return current.intersection(paths) }
            return paths
        }
        if key.hasPrefix("semantic:") {
            let name = String(key.dropFirst("semantic:".count))
            return Set(try await store.pathsForSmartRules(SmartAlbumRules(conditions: [
                SmartAlbumRule(type: .semanticCategory, value: name),
            ])))
        }
        if key.hasPrefix("camera:") {
            let model = String(key.dropFirst("camera:".count))
            return Set(try await store.pathsForSmartRules(SmartAlbumRules(conditions: [
                SmartAlbumRule(type: .cameraModelContains, value: model),
            ])))
        }
        if key.hasPrefix("place:") {
            let place = String(key.dropFirst("place:".count))
            if place == "No location" {
                let all = try await store.fetchPaths(limit: 100_000, offset: 0, metadata: MetadataFilter(), projectFilter: project.filter)
                let located = try await store.pathsForSmartRules(SmartAlbumRules(conditions: [.init(type: .hasGPS, value: "1")]))
                return Set(all).subtracting(located)
            }
            return Set(try await store.pathsForSmartRules(SmartAlbumRules(conditions: [
                SmartAlbumRule(type: .placeContains, value: place),
            ])))
        }
        if key.hasPrefix("person:") {
            let personId = String(key.dropFirst("person:".count))
            return Set(try await store.pathsForSmartRules(SmartAlbumRules(conditions: [
                SmartAlbumRule(type: .personGroupId, value: personId),
            ])))
        }
        if key.hasPrefix("source:") {
            let prefix = String(key.dropFirst("source:".count))
            return Set(try await store.pathsForSmartRules(SmartAlbumRules(conditions: [
                SmartAlbumRule(type: .sourcePathPrefix, value: prefix),
            ])))
        }
        if key == "bin" {
            let bin = Set(project.deleteBinPaths)
            if let current { return current.intersection(bin) }
            return bin
        }
        if let current { return current }
        return Set(try await store.allPaths())
    }

    private func runAnalysisIfNeeded(generation: Int) async {
        guard categoryDetectionOn || analyzeFacesOn else {
            activity.errorMessage = "Turn on Categories and/or Faces, then click Run."
            return
        }
        guard let store = index else { return }
        let paths = (try? await store.allPaths()) ?? []
        guard !paths.isEmpty else { return }

        activity.isMetadataing = true
        activity.isAnalyzing = categoryDetectionOn
        activity.isFaceProcessing = false
        activity.metadataTotal = paths.count
        activity.analyzeTotal = paths.count
        activity.facesProcessed = 0
        activity.faceTotal = paths.count

        analysisTask?.cancel()
        analysisTask = Task {
            await analysis.process(
                paths: paths,
                semanticOn: categoryDetectionOn,
                smartTitlesOn: categoryDetectionOn,
                facesOn: analyzeFacesOn,
                index: store,
                placeService: placeService,
                onMetadata: { @MainActor [weak self] done, total in
                    guard let self, generation == self.generation else { return }
                    self.activity.metadataDone = done
                    self.activity.metadataTotal = total
                },
                onAnalysis: { @MainActor [weak self] done, total in
                    guard let self, generation == self.generation else { return }
                    self.activity.analyzed = done
                    self.activity.analyzeTotal = total
                },
                onGeocode: { @MainActor [weak self] done, total in
                    guard let self, generation == self.generation else { return }
                    self.activity.geocoded = done
                    self.activity.geocodeTotal = total
                    self.activity.isGeocoding = done < total
                },
                onFaces: { @MainActor [weak self] done, total in
                    guard let self, generation == self.generation else { return }
                    self.activity.facesProcessed = done
                    self.activity.faceTotal = total
                },
                onFacePhaseStarted: { @MainActor [weak self] in
                    guard let self, generation == self.generation else { return }
                    self.activity.isMetadataing = false
                    self.activity.isAnalyzing = false
                    self.activity.isGeocoding = false
                    self.activity.isFaceProcessing = true
                    self.activity.facesProcessed = 0
                },
                personGroups: { @MainActor [weak self] in
                    self?.project.personGroups ?? []
                },
                onPersonGroups: { @MainActor [weak self] groups in
                    guard let self, generation == self.generation else { return }
                    self.project.personGroups = groups
                    self.projects.update(self.project)
                },
                onSmartTitle: { @MainActor [weak self] path, title in
                    guard let self, generation == self.generation else { return }
                    var annotation = self.annotation(for: path)
                    annotation.suggestedTitle = title
                    self.updateAnnotation(annotation)
                }
            )
            guard generation == self.generation else { return }
            if !Task.isCancelled {
                activity.isMetadataing = false
                activity.isAnalyzing = false
                activity.isFaceProcessing = false
                activity.isGeocoding = false
                await recordAnalysisCheckpoint()
                await reloadVisiblePaths()
                await refreshSidebarBuckets()
                analysisStaleBannerSuppressed = false
                await refreshAnalysisStaleHint()
            }
        }
    }

    func dismissAnalysisStaleBanner() {
        analysisStaleBannerSuppressed = true
    }

    func sourceFingerprint() -> String {
        let bookmarkIDs = project.sourceBookmarks.map(\.id).sorted()
        let legacy = project.sources
            .filter { path in !project.sourceBookmarks.contains(where: { $0.displayPath == path }) }
            .sorted()
        return (bookmarkIDs + legacy).joined(separator: "\u{1f}")
    }

    func refreshAnalysisStaleHint() async {
        guard let store = index else {
            analysisStaleHint = nil
            return
        }
        let indexedCount = (try? await store.count()) ?? 0
        guard indexedCount > 0 else {
            analysisStaleHint = nil
            return
        }

        guard let checkpoint = project.analysisCheckpoint else {
            guard categoryDetectionOn || analyzeFacesOn else {
                analysisStaleHint = nil
                return
            }
            analysisStaleHint = AnalysisStaleHint(
                newPhotoCount: indexedCount,
                sourcesChanged: false,
                neverAnalyzed: true
            )
            return
        }

        let fingerprint = sourceFingerprint()
        let sourcesChanged = fingerprint != checkpoint.sourceFingerprint
        let newPhotos = max(0, indexedCount - checkpoint.indexedPathCount)
        if sourcesChanged || newPhotos > 0 {
            analysisStaleHint = AnalysisStaleHint(
                newPhotoCount: newPhotos,
                sourcesChanged: sourcesChanged,
                neverAnalyzed: false
            )
        } else {
            analysisStaleHint = nil
        }
    }

    func recordAnalysisCheckpoint() async {
        guard let store = index else { return }
        let count = (try? await store.count()) ?? 0
        project.analysisCheckpoint = AnalysisCheckpoint(
            completedAt: Date(),
            indexedPathCount: count,
            sourceFingerprint: sourceFingerprint()
        )
        projects.update(project)
    }

    func thumbnail(for path: String) async -> NSImage? {
        await thumbnails.thumbnail(for: URL(fileURLWithPath: path))
    }

    func fullImage(for path: String) async -> NSImage? {
        await thumbnails.fullImage(for: URL(fileURLWithPath: path))
    }

    /// Semantic / analysis categories for one photo (fullscreen viewer).
    func analysisCategories(for path: String) async -> [String] {
        guard let store = index, let record = try? await store.record(for: path) else { return [] }
        var categories: [String] = []
        if let semantic = record.semanticCategory?.trimmingCharacters(in: .whitespacesAndNewlines),
           !semantic.isEmpty
        {
            categories.append(semantic)
        }
        if record.isScreenshot, !categories.contains("Screenshots") {
            categories.append("Screenshots")
        }
        return categories
    }

    @discardableResult
    func createManualAlbum(name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let album = Album(id: UUID().uuidString, name: trimmed, kind: .manual)
        project.albums.append(album)
        projects.update(project)
        return album.id
    }

    func addPathsToAlbum(albumId: String, paths: [String]) {
        if albumId == AlbumConstants.favoritesAlbumId {
            _ = ensureFavoritesAlbum()
        }
        guard let index = project.albums.firstIndex(where: { $0.id == albumId }) else { return }
        guard project.albums[index].kind == .manual || project.albums[index].isFavorites else { return }
        let unique = paths.filter { path in
            !project.albums[index].memberPaths.contains(path)
        }
        guard !unique.isEmpty else { return }
        project.albums[index].memberPaths.append(contentsOf: unique)
        projects.update(project)
        if isSelectingPhotos {
            selectedPaths.subtract(unique)
        }
    }

    func createSmartAlbum(name: String, rules: SmartAlbumRules) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var album = Album(id: UUID().uuidString, name: trimmed, kind: .smart, rules: rules)
        album.lastEvaluatedAt = Date()
        project.albums.append(album)
        projects.update(project)
        groupBy = .albums
        selectedAlbumId = album.id
        selectedSidebarKey = "album:\(album.id)"
        scheduleReloadVisiblePaths()
    }

    func addToAlbum(albumId: String, path: String) {
        guard let index = project.albums.firstIndex(where: { $0.id == albumId }) else { return }
        guard project.albums[index].kind == .manual || project.albums[index].isFavorites else { return }
        if !project.albums[index].memberPaths.contains(path) {
            project.albums[index].memberPaths.append(path)
            projects.update(project)
        }
    }

    func isFavorite(path: String) -> Bool {
        guard let album = favoritesAlbum else { return false }
        return album.memberPaths.contains(path)
    }

    @discardableResult
    func toggleFavorite(path: String) -> Bool {
        let albumId = ensureFavoritesAlbum()
        guard let index = project.albums.firstIndex(where: { $0.id == albumId }) else { return false }
        if let memberIndex = project.albums[index].memberPaths.firstIndex(of: path) {
            project.albums[index].memberPaths.remove(at: memberIndex)
            projects.update(project)
            return false
        }
        project.albums[index].memberPaths.append(path)
        projects.update(project)
        return true
    }

    var favoritesAlbum: Album? {
        project.albums.first { $0.isFavorites }
    }

    var userCreatedAlbums: [Album] {
        project.albums.filter { !$0.isFavorites }
    }

    func selectFavoritesAlbum() {
        let id = ensureFavoritesAlbum()
        selectAlbum(id: id)
    }

    @discardableResult
    private func ensureFavoritesAlbum() -> String {
        normalizeFavoritesAlbum()
        if let album = favoritesAlbum { return album.id }
        let album = Album(
            id: AlbumConstants.favoritesAlbumId,
            name: AlbumConstants.favoritesAlbumName,
            kind: .favorites
        )
        project.albums.insert(album, at: 0)
        projects.update(project)
        return album.id
    }

    func exportSelectedAlbum() {
        guard let albumId = selectedAlbumId,
              let album = project.albums.first(where: { $0.id == albumId })
        else {
            activity.errorMessage = "Select an album to export."
            return
        }

        Task {
            guard let store = index else { return }
            let paths: [String]
            switch album.kind {
            case .manual, .favorites:
                paths = album.memberPaths
            case .smart:
                paths = (try? await store.pathsForSmartRules(album.rules ?? SmartAlbumRules())) ?? []
            }

            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Export"
            panel.message = "Choose a parent folder for the exported album."
            guard panel.runModal() == .OK, let parent = panel.url else { return }

            activity.isExporting = true
            activity.exportCopied = 0
            activity.exportTotal = paths.count
            do {
                let copied = try await AlbumExportService.export(
                    albumName: album.name,
                    photoPaths: paths,
                    destinationParent: parent,
                    onProgress: { @MainActor done, total in
                        self.activity.exportCopied = done
                        self.activity.exportTotal = total
                    }
                )
                activity.isExporting = false
                activity.errorMessage = nil
                _ = copied
            } catch {
                activity.isExporting = false
                activity.errorMessage = error.localizedDescription
            }
        }
    }

    func renamePerson(id: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = project.personGroups.firstIndex(where: { $0.id == id }) else { return }
        project.personGroups[index].displayName = trimmed.isEmpty ? nil : trimmed
        projects.update(project)
    }

    /// Removes a clustered person and clears their face tags from the index (does not delete photos).
    func removePersonGroup(id: String) {
        guard let groupIndex = project.personGroups.firstIndex(where: { $0.id == id }) else { return }
        let group = project.personGroups[groupIndex]
        project.personGroups.remove(at: groupIndex)
        projects.update(project)
        peopleMergeSelection.remove(id)
        if selectedSidebarKey == "person:\(id)" {
            selectedSidebarKey = nil
        }

        Task {
            if let store = index {
                for path in group.memberPhotoPaths {
                    if let record = try? await store.record(for: path) {
                        let ids = record.personGroupIds.filter { $0 != id }
                        try? await store.updatePersonGroups(path: path, groupIds: ids)
                    }
                }
            }
            if let crop = group.faceCropPath {
                try? FileManager.default.removeItem(atPath: crop)
            }
            await reloadVisiblePaths()
        }
    }

    private func filterByPersonName(
        query: String,
        store: PhotoIndexStore,
        current: Set<String>?
    ) async throws -> Set<String> {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else {
            if let current { return current }
            return Set(try await store.allPaths())
        }

        let matching = project.personGroups.filter { group in
            (group.displayName ?? "").lowercased().contains(needle)
        }
        guard !matching.isEmpty else { return [] }

        var paths = Set<String>()
        for group in matching {
            paths.formUnion(group.memberPhotoPaths)
            let indexed = try await store.pathsForSmartRules(SmartAlbumRules(conditions: [
                SmartAlbumRule(type: .personGroupId, value: group.id),
            ]))
            paths.formUnion(indexed)
        }
        if let current { return current.intersection(paths) }
        return paths
    }

    func selectPerson(id: String) {
        selectedSidebarKey = "person:\(id)"
        groupBy = .none
        selectedAlbumId = nil
        scheduleReloadVisiblePaths()
    }

    func clearPersonFilter() {
        guard selectedSidebarKey?.hasPrefix("person:") == true else { return }
        selectedSidebarKey = nil
        scheduleReloadVisiblePaths()
    }

    func toggleCombiningPeople() {
        isCombiningPeople.toggle()
        peopleMergeSelection.removeAll()
    }

    func togglePersonForMerge(id: String) {
        if peopleMergeSelection.contains(id) {
            peopleMergeSelection.remove(id)
        } else {
            peopleMergeSelection.insert(id)
        }
    }

    func cancelCombiningPeople() {
        isCombiningPeople = false
        peopleMergeSelection.removeAll()
    }

    func mergeSelectedPeople() {
        guard peopleMergeSelection.count >= 2 else { return }
        let ids = Array(peopleMergeSelection)
        Task { await mergeMultiplePersonGroups(ids: ids) }
    }

    private func primaryPersonId(among ids: [String]) -> String? {
        let groups = ids.compactMap { id in project.personGroups.first(where: { $0.id == id }) }
        guard !groups.isEmpty else { return nil }
        return groups.max { lhs, rhs in
            mergePrimaryScore(lhs) < mergePrimaryScore(rhs)
        }?.id
    }

    private func mergePrimaryScore(_ group: PersonGroup) -> Int {
        let named = (group.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? 100_000 : 0
        return named + group.memberPhotoPaths.count
    }

    private func mergeMultiplePersonGroups(ids: [String]) async {
        guard ids.count >= 2, let primaryId = primaryPersonId(among: ids) else { return }
        let removedIds = ids.filter { $0 != primaryId }
        for secondaryId in removedIds {
            await mergePersonGroups(primaryId: primaryId, secondaryId: secondaryId, finishCombineUI: false)
        }
        cancelCombiningPeople()
        if let key = selectedSidebarKey, key.hasPrefix("person:") {
            let personId = String(key.dropFirst("person:".count))
            if removedIds.contains(personId) {
                selectedSidebarKey = "person:\(primaryId)"
            }
        }
        await reloadVisiblePaths()
    }

    func mergePersonGroups(primaryId: String, secondaryId: String, finishCombineUI: Bool = true) async {
        guard primaryId != secondaryId,
              let primaryIndex = project.personGroups.firstIndex(where: { $0.id == primaryId }),
              let secondaryIndex = project.personGroups.firstIndex(where: { $0.id == secondaryId })
        else { return }

        var primary = project.personGroups[primaryIndex]
        let secondary = project.personGroups[secondaryIndex]

        for path in secondary.memberPhotoPaths where !primary.memberPhotoPaths.contains(path) {
            primary.memberPhotoPaths.append(path)
        }
        if primary.faceCropPath == nil { primary.faceCropPath = secondary.faceCropPath }
        if primary.thumbnailPath == nil { primary.thumbnailPath = secondary.thumbnailPath }
        if (primary.displayName ?? "").isEmpty, let name = secondary.displayName, !name.isEmpty {
            primary.displayName = name
        }

        project.personGroups[primaryIndex] = primary
        project.personGroups.remove(at: secondaryIndex)

        if let store = index {
            let touched = Set(primary.memberPhotoPaths + secondary.memberPhotoPaths)
            for path in touched {
                if let record = try? await store.record(for: path) {
                    var ids = record.personGroupIds.filter { $0 != secondaryId }
                    if !ids.contains(primaryId) { ids.append(primaryId) }
                    try? await store.updatePersonGroups(path: path, groupIds: ids)
                }
            }
        }

        if let secondaryCrop = secondary.faceCropPath, secondaryCrop != primary.faceCropPath {
            try? FileManager.default.removeItem(atPath: secondaryCrop)
        }

        projects.update(project)

        guard finishCombineUI else { return }
        cancelCombiningPeople()
        if selectedSidebarKey == "person:\(secondaryId)" {
            selectedSidebarKey = "person:\(primaryId)"
        }
        await reloadVisiblePaths()
    }

    func faceChipImage(for person: PersonGroup) async -> NSImage? {
        guard let path = person.faceCropPath, FileManager.default.fileExists(atPath: path) else { return nil }
        return await Task.detached(priority: .utility) {
            NSImage(contentsOf: URL(fileURLWithPath: path))
        }.value
    }

    func annotation(for path: String) -> PhotoAnnotation {
        project.annotations.first(where: { $0.path == path })
            ?? PhotoAnnotation(path: path)
    }

    func updateAnnotation(_ annotation: PhotoAnnotation) {
        if let index = project.annotations.firstIndex(where: { $0.path == annotation.path }) {
            project.annotations[index] = annotation
        } else {
            project.annotations.append(annotation)
        }
        projects.update(project)
    }

    private static let categoryChipMinimumCount = 3
    private static let categoryChipLimit = 16

    func loadDetectedCategories() async {
        guard let store = index else { return }
        let semantic = (try? await store.groupBySemantic()) ?? []
        let pinnedAsAlbum = Set(
            project.albums.compactMap { album -> String? in
                guard album.kind == .smart, let rules = album.rules else { return nil }
                return rules.conditions.first(where: { $0.type == .semanticCategory })?.value
            }
        )
        let items = semantic
            .filter { $0.count >= Self.categoryChipMinimumCount && !pinnedAsAlbum.contains($0.name) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .prefix(Self.categoryChipLimit)
            .map { item in
                (
                    item.name,
                    item.count,
                    SmartAlbumRule(type: .semanticCategory, value: item.name)
                )
            }
        detectedCategories = Array(items)
    }

    /// Filter grid by an auto-detected category (chip row).
    func selectSemanticCategory(_ name: String) {
        selectSidebarFilter("semantic:\(name)")
        applySidebarKey(selectedSidebarKey)
    }

    /// Pin a detected category as a smart album in the sidebar.
    func pinCategoryAsAlbum(_ item: (title: String, count: Int, rule: SmartAlbumRule)) {
        createSmartAlbum(name: item.title, rules: SmartAlbumRules(conditions: [item.rule]))
        detectedCategories.removeAll { $0.title == item.title }
    }

    func dismissDetectedCategory(_ title: String) {
        detectedCategories.removeAll { $0.title == title }
    }

    private func splitList(_ value: String) -> [String] {
        value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    // MARK: - Grid selection & delete bin

    func setSelectingPhotos(_ enabled: Bool) {
        isSelectingPhotos = enabled
        if !enabled {
            selectedPaths.removeAll()
        }
    }

    func toggleGridSelection(path: String) {
        if selectedPaths.contains(path) {
            selectedPaths.remove(path)
        } else {
            selectedPaths.insert(path)
        }
        syncSelectionModeFromSelection()
    }

    private func syncSelectionModeFromSelection() {
        isSelectingPhotos = !selectedPaths.isEmpty
    }

    func toggleFavoriteSelectedPhotos() {
        guard !selectedPaths.isEmpty else { return }
        let allFavorited = selectedPaths.allSatisfy { isFavorite(path: $0) }
        for path in selectedPaths {
            let favorited = isFavorite(path: path)
            if allFavorited, favorited {
                _ = toggleFavorite(path: path)
            } else if !allFavorited, !favorited {
                _ = toggleFavorite(path: path)
            }
        }
    }

    /// Drag-to-select: always adds (does not toggle off while sweeping).
    func selectGridPhoto(path: String) {
        selectedPaths.insert(path)
        syncSelectionModeFromSelection()
    }

    func selectAllVisiblePhotos() {
        selectedPaths = Set(visiblePaths)
        syncSelectionModeFromSelection()
    }

    func clearGridSelection() {
        selectedPaths.removeAll()
        syncSelectionModeFromSelection()
    }

    func addToDeleteBin(paths: [String]) {
        guard !paths.isEmpty else { return }
        var bin = Set(project.deleteBinPaths)
        for path in paths {
            bin.insert(path)
        }
        project.deleteBinPaths = Array(bin).sorted()
        projects.update(project)
        selectedPaths.subtract(paths)
        syncSelectionModeFromSelection()
    }

    func addSelectedToDeleteBin() {
        addToDeleteBin(paths: Array(selectedPaths))
    }

    func removeFromDeleteBin(paths: [String]) {
        guard !paths.isEmpty else { return }
        let drop = Set(paths)
        project.deleteBinPaths.removeAll { drop.contains($0) }
        projects.update(project)
        selectedPaths.subtract(drop)
        scheduleReloadVisiblePaths()
    }

    func emptyDeleteBin() {
        project.deleteBinPaths.removeAll()
        projects.update(project)
        selectedPaths.removeAll()
        scheduleReloadVisiblePaths()
    }

    func showDeleteBinInSidebar() {
        selectedSidebarKey = "bin"
        groupBy = .none
        selectedAlbumId = nil
        scheduleReloadVisiblePaths()
    }

    /// Moves delete-bin files to the system Trash and updates the index. Returns paths that failed.
    func deleteBinFromSource() async -> [String] {
        let paths = project.deleteBinPaths
        guard !paths.isEmpty else { return [] }

        _ = resolvedSources()
        let failed = Set(SourceFileDeletionService.moveToTrash(paths: paths))
        let succeeded = paths.filter { !failed.contains($0) }

        if let store = index, !succeeded.isEmpty {
            try? await store.removePaths(succeeded)
        }
        for path in succeeded {
            purgePathFromProject(path)
        }

        project.deleteBinPaths.removeAll { succeeded.contains($0) }
        projects.update(project)
        selectedPaths.removeAll()
        await reloadVisiblePaths()

        if failed.isEmpty {
            activity.errorMessage = nil
        } else if succeeded.isEmpty {
            activity.errorMessage = "Could not delete \(failed.count) file(s). Open or reconnect source folders and try again."
        } else {
            activity.errorMessage = "Deleted \(succeeded.count) file(s). \(failed.count) could not be removed."
        }
        return Array(failed)
    }

    private func purgePathFromProject(_ path: String) {
        project.deleteBinPaths.removeAll { $0 == path }
        project.annotations.removeAll { $0.path == path }
        for index in project.albums.indices {
            project.albums[index].memberPaths.removeAll { $0 == path }
        }
        for index in project.personGroups.indices {
            project.personGroups[index].memberPhotoPaths.removeAll { $0 == path }
        }
    }

    /// Unit-test seam: attach a populated index and refresh grid + sidebar buckets.
    func attachPhotoIndexForTesting(_ store: PhotoIndexStore) async {
        index = store
        if let counts = try? await store.mediaExtensionCounts() {
            syncDetectedMediaTypes(counts)
        }
        await refreshSidebarBuckets()
        await reloadVisiblePaths()
        await refreshAnalysisStaleHint()
        await refreshIndexedDateRange()
    }
}