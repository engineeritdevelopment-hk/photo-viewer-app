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
    /// Draws the filtered person's face while moving between photos.
    var highlightsFilteredFace = false
    var selectedAlbumId: String?
    var metadataFilter = MetadataFilter()
    /// File extensions in the index (`ext`, count), sorted.
    var detectedMediaExtensions: [(ext: String, count: Int)] = []
    /// Included types for the grid; when equal to all detected, no media-type filter is applied.
    var selectedMediaExtensions: Set<String> = []
    var photoSort: LibraryPhotoSort = .dateNewest
    var categoryDetectionOn = false
    var objectDetectionOn = false
    var analyzeFacesOn = false

    var allAnalysisOptionsOn: Bool {
        categoryDetectionOn && objectDetectionOn && analyzeFacesOn
    }

    func setAllAnalysisOptions(_ on: Bool) {
        guard !isAnalysisRunning else { return }
        categoryDetectionOn = on
        objectDetectionOn = on
        analyzeFacesOn = on
    }
    var isSelectingPhotos = false
    var selectedPaths: Set<String> = []
    var isCombiningPeople = false
    var peopleMergeSelection: Set<String> = []

    /// Auto-detected semantic categories for the chip row (not created as albums until pinned).
    var detectedCategories: [(title: String, count: Int, rule: SmartAlbumRule)] = []
    /// Photos that contain the face the user framed. Nil when that search is off.
    var faceMatchPaths: [String]?
    private var faceMatchToken = 0
    /// Bumps when a looked-up person's photo list changes so the grid reloads.
    private var lookedUpMemberToken = 0
    private var faceSearchGeneration = 0
    private var faceSearchTask: Task<Void, Never>?
    var analysisStaleHint: AnalysisStaleHint?
    private var analysisStaleBannerSuppressed = false
    var sidebarYears: [(year: String, count: Int)] = []
    var sidebarPlaces: [(name: String, count: Int)] = []
    var sidebarCameras: [(name: String, count: Int)] = []
    var sidebarObjects: [(name: String, count: Int)] = []
    /// Free-text object search. Matches any detected name that contains this text.
    var objectSearchText = ""
    var sidebarScreenshotCount = 0
    /// Child folders under sources that contain photos. Empty until the index is loaded.
    var sourceFolders: [SourceFolderNode] = []
    /// A source contains photos in more than one directory, so folder browsing is useful.
    var canBrowseSourceByFolder = false
    var sourceFolderView: SourceFolderView = AppPreferences.sourceFolderView
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
    private var openingIndexTask: Task<Void, Never>?
    /// Bumped on appear and on close so a transient disappear does not cancel a visible library.
    private var sessionToken = 0
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
        sessionToken += 1
        let token = sessionToken
        Task(priority: .userInitiated) {
            await Task.yield()
            guard token == sessionToken else { return }
            startIfNeeded()
            await Task.yield()
            guard token == sessionToken else { return }
            normalizeFavoritesAlbum()
        }
    }

    /// Open the SQLite index off the main thread as soon as the user picks this project.
    func prepareForOpening() {
        guard index == nil, openingIndexTask == nil else { return }
        let projectId = project.id
        openingIndexTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.installIndexIfNeeded(projectId: projectId)
            self.openingIndexTask = nil
        }
    }

    /// Ensures the Favorites album uses `AlbumKind.favorites` (legacy projects used `.manual`).
    func normalizeFavoritesAlbum() {
        guard let index = project.albums.firstIndex(where: {
            $0.id == AlbumConstants.favoritesAlbumId
                || ($0.name == AlbumConstants.favoritesAlbumName && $0.kind == .manual)
        }) else { return }
        var album = project.albums[index]
        let hasDuplicateManualFavorites = project.albums.contains { other in
            other.id != album.id
                && other.name == AlbumConstants.favoritesAlbumName
                && other.kind == .manual
        }
        let alreadyNormalized = album.id == AlbumConstants.favoritesAlbumId
            && album.name == AlbumConstants.favoritesAlbumName
            && album.kind == .favorites
            && !hasDuplicateManualFavorites
        guard !alreadyNormalized else { return }
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
        sessionToken += 1
        let token = sessionToken
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard token == sessionToken else { return }
            self.haltLibraryWork()
        }
    }

    private func haltLibraryWork() {
        generation += 1
        let priorCatalog = catalogTask
        let priorAnalysis = analysisTask
        let priorIndexOpen = openingIndexTask
        catalogTask = nil
        analysisTask = nil
        openingIndexTask = nil
        priorCatalog?.cancel()
        priorAnalysis?.cancel()
        priorIndexOpen?.cancel()
        Task {
            await priorCatalog?.value
            await priorAnalysis?.value
            securityScope.releaseAll()
        }
    }

    private func installIndexIfNeeded(projectId: String) async {
        guard index == nil else { return }
        do {
            let store = try await Task.detached(priority: .userInitiated) {
                try PhotoIndexStore(projectId: projectId)
            }.value
            index = store
            _ = resolvedSources()
            await reloadVisiblePaths()
            await refreshSidebarBuckets()
        } catch {
            activity.errorMessage = error.localizedDescription
        }
    }

    private func ensureIndexReady() async throws {
        if index != nil { return }
        if let openingIndexTask {
            await openingIndexTask.value
            if index != nil { return }
        }
        try await installIndexIfNeededThrowing(projectId: project.id)
        guard index != nil else {
            throw PhotoIndexError.openFailed("Could not open photo index.")
        }
    }

    private func installIndexIfNeededThrowing(projectId: String) async throws {
        guard index == nil else { return }
        let store = try await Task.detached(priority: .userInitiated) {
            try PhotoIndexStore(projectId: projectId)
        }.value
        index = store
    }

    func startIfNeeded() {
        generation += 1
        let current = generation
        analysisTask?.cancel()

        let priorCatalog = catalogTask
        priorCatalog?.cancel()

        catalogTask = Task(priority: .userInitiated) {
            if let priorCatalog {
                await priorCatalog.value
            }
            await catalog.cancelAndWait()
            guard !Task.isCancelled, current == generation else { return }

            do {
                try await ensureIndexReady()
            } catch {
                activity.errorMessage = error.localizedDescription
                return
            }

            await reloadVisiblePaths()
            await Task.yield()
            await refreshSidebarBuckets()

            let sources = resolvedSources()
            guard !sources.isEmpty else { return }

            guard let store = index else { return }

            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, current == generation else { return }

            activity.isCataloging = true
            activity.catalogScanned = 0
            activity.catalogTotal = nil
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
        sidebarObjects = (try? await store.groupByObject()) ?? []
        if let counts = try? await store.sidebarCounts() {
            sidebarScreenshotCount = counts.screenshots
        }
        let folderCounts = (try? await store.directPhotoCountsByFolder()) ?? []
        let roots = sourceRootPaths
        sourceFolders = SourceFolderIndex.nodes(folderCounts: folderCounts, sourcePaths: roots)
        canBrowseSourceByFolder = SourceFolderIndex.canBrowseByFolder(
            folderCounts: folderCounts,
            sourcePaths: roots
        )
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
        activity.isMetadataing
            || activity.isAnalyzing
            || activity.isFaceProcessing
            || activity.isSearchingFaces
            || activity.isGeocoding
    }

    private(set) var interfaceBusyCount = 0

    var isInterfaceBusy: Bool { interfaceBusyCount > 0 }

    /// Shows the working spinner, lets it draw, then runs the work.
    func withInterfaceWork<T>(_ operation: () async -> T) async -> T {
        interfaceBusyCount += 1
        await Task.yield()
        defer { interfaceBusyCount -= 1 }
        return await operation()
    }

    var canStartAnalysis: Bool {
        (categoryDetectionOn || objectDetectionOn || analyzeFacesOn)
            && !isAnalysisRunning
            && !activity.isCataloging
            && index != nil
    }

    var lookedUpPeople: [PersonGroup] {
        project.personGroups
            .filter(\.isLookedUp)
            .sorted { lhs, rhs in
                if lhs.memberPhotoPaths.count != rhs.memberPhotoPaths.count {
                    return lhs.memberPhotoPaths.count > rhs.memberPhotoPaths.count
                }
                return lhs.id < rhs.id
            }
    }

    /// Adds the framed face under Filter and selects it, then scans the library.
    @discardableResult
    func pinLookedUpFace(image: CGImage, sourcePath: String) -> String {
        let id = UUID().uuidString
        let crop = FaceThumbnailWriter.save(cgImage: image, groupId: id)
        var members: [String] = []
        if !sourcePath.isEmpty { members.append(sourcePath) }
        project.personGroups.append(
            PersonGroup(
                id: id,
                displayName: nil,
                memberPhotoPaths: members,
                thumbnailPath: sourcePath.isEmpty ? nil : sourcePath,
                faceCropPath: crop,
                isLookedUp: true
            )
        )
        projects.update(project)
        groupBy = .none
        selectedAlbumId = nil
        faceMatchPaths = nil
        selectedSidebarKey = "person:\(id)"
        appliedVisiblePathsQueryFingerprint = nil
        scheduleReloadVisiblePaths()
        return id
    }

    func beginFaceSearch(embedding: FaceEmbedding, face: CGImage, sourcePath: String) {
        faceSearchTask?.cancel()
        faceSearchGeneration += 1
        let generation = faceSearchGeneration
        let personId = pinLookedUpFace(image: face, sourcePath: sourcePath)
        activity.isSearchingFaces = true
        activity.faceSearchDone = 0
        activity.faceSearchTotal = 0
        activity.errorMessage = nil
        faceSearchTask = Task {
            await runFaceSearch(
                embedding: embedding,
                generation: generation,
                personId: personId,
                sourcePath: sourcePath
            )
        }
    }

    func cancelFaceSearch() {
        faceSearchTask?.cancel()
        faceSearchTask = nil
        faceSearchGeneration += 1
        faceMatchPaths = nil
        activity.isSearchingFaces = false
        activity.faceSearchDone = 0
        activity.faceSearchTotal = 0
    }

    private func runFaceSearch(
        embedding: FaceEmbedding,
        generation: Int,
        personId: String,
        sourcePath: String
    ) async {
        let paths = (try? await index?.allPaths()) ?? []
        activity.faceSearchTotal = paths.count
        var matches: [String] = sourcePath.isEmpty ? [] : [sourcePath]
        for (offset, path) in paths.enumerated() {
            if Task.isCancelled || generation != faceSearchGeneration {
                await finishLookedUpSearch(personId: personId, matches: matches, generation: generation)
                return
            }
            if path != sourcePath {
                let matched = await Task.detached(priority: .utility) {
                    autoreleasepool { () -> Bool in
                        for face in FaceAlignment.alignedFaces(from: URL(fileURLWithPath: path)) {
                            guard let candidate = AdaFaceEmbedder.embedding(forAlignedFace: face.image) else { continue }
                            if candidate.cosineSimilarity(to: embedding) >= FaceEmbedding.samePersonCosine {
                                return true
                            }
                        }
                        return false
                    }
                }.value
                if matched { matches.append(path) }
            }
            activity.faceSearchDone = offset + 1
            if matches.count % 25 == 0 {
                publishLookedUpMatches(personId: personId, matches: matches, persist: false)
            }
        }
        await finishLookedUpSearch(personId: personId, matches: matches, generation: generation)
    }

    private func publishLookedUpMatches(personId: String, matches: [String], persist: Bool) {
        guard let index = project.personGroups.firstIndex(where: { $0.id == personId }) else { return }
        project.personGroups[index].memberPhotoPaths = uniquePaths(matches)
        lookedUpMemberToken += 1
        if persist { projects.update(project) }
        if selectedSidebarKey == "person:\(personId)" {
            appliedVisiblePathsQueryFingerprint = nil
            scheduleReloadVisiblePaths()
        }
    }

    private func finishLookedUpSearch(personId: String, matches: [String], generation: Int) async {
        guard project.personGroups.contains(where: { $0.id == personId }) else { return }
        let paths = uniquePaths(matches)
        if let index = project.personGroups.firstIndex(where: { $0.id == personId }) {
            project.personGroups[index].memberPhotoPaths = paths
        }
        projects.update(project)
        await tagLookedUpPerson(personId, paths: paths)
        guard generation == faceSearchGeneration else { return }
        activity.isSearchingFaces = false
        lookedUpMemberToken += 1
        if selectedSidebarKey == "person:\(personId)" {
            appliedVisiblePathsQueryFingerprint = nil
            await reloadVisiblePaths()
        }
    }

    private func uniquePaths(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }

    private func tagLookedUpPerson(_ personId: String, paths: [String]) async {
        guard let store = index else { return }
        for path in paths {
            guard let record = try? await store.record(for: path) else { continue }
            var ids = record.personGroupIds
            if !ids.contains(personId) { ids.append(personId) }
            try? await store.updatePersonGroups(path: path, groupIds: ids)
        }
    }

    /// Keeps framed-face people when a later Faces run rebuilds clusters.
    private func mergingLookedUpPeople(into groups: [PersonGroup]) -> [PersonGroup] {
        let lookedUp = project.personGroups.filter(\.isLookedUp)
        guard !lookedUp.isEmpty else { return groups }
        var merged = groups
        for person in lookedUp {
            if let index = merged.firstIndex(where: { $0.id == person.id }) {
                merged[index].isLookedUp = true
                if merged[index].faceCropPath == nil { merged[index].faceCropPath = person.faceCropPath }
                if (merged[index].displayName ?? "").isEmpty { merged[index].displayName = person.displayName }
            } else {
                merged.append(person)
            }
        }
        return merged
    }

    func startAnalysis() {
        guard canStartAnalysis else { return }
        Task { await runAnalysisIfNeeded(generation: generation) }
    }

    /// Removes categories, suggested titles, and people. Photos, albums, and notes stay.
    func clearAnalysisData() {
        guard !isAnalysisRunning else { return }
        let crops = project.personGroups.compactMap(\.faceCropPath)
        project.personGroups = []
        project.annotations = project.annotations.compactMap { annotation in
            var kept = annotation
            kept.suggestedTitle = nil
            let hasNote = !kept.place.isEmpty || !kept.items.isEmpty || !kept.faces.isEmpty
            return hasNote ? kept : nil
        }
        project.analysisCheckpoint = nil
        projects.update(project)
        peopleMergeSelection.removeAll()
        isCombiningPeople = false
        detectedCategories = []
        objectSearchText = ""
        analysisStaleHint = nil
        if let key = selectedSidebarKey,
           key.hasPrefix("person:") || key.hasPrefix("semantic:") || key.hasPrefix("object:") {
            selectedSidebarKey = nil
        }

        Task {
            if let index {
                try? await index.clearAnalysis()
            }
            for crop in crops {
                try? FileManager.default.removeItem(atPath: crop)
            }
            await reloadVisiblePaths()
            await refreshSidebarBuckets()
            await loadDetectedCategories()
            await refreshAnalysisStaleHint()
        }
    }

    func stopAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        cancelFaceSearch()
        Task { await analysis.setPaused(false) }
        activity.isMetadataing = false
        activity.isAnalyzing = false
        activity.isFaceProcessing = false
        activity.isGeocoding = false
    }

    var sourceRootPaths: [String] {
        var paths = project.sourceBookmarks.map(\.displayPath)
        for path in project.sources where !paths.contains(path) {
            paths.append(path)
        }
        return paths.map(SourceFolderIndex.normalize)
    }

    func sourceFolders(under sourcePath: String) -> [SourceFolderNode] {
        let root = SourceFolderIndex.normalize(sourcePath)
        return sourceFolders.filter { $0.sourcePath == root }
    }

    /// Folder browsing is active only when this library actually has multiple folders.
    var usesFolderBrowsing: Bool {
        sourceFolderView == .byFolder && canBrowseSourceByFolder
    }

    func setSourceFolderView(_ view: SourceFolderView) {
        guard sourceFolderView != view else { return }
        sourceFolderView = view
        AppPreferences.sourceFolderView = view
        scheduleReloadVisiblePaths()
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
            registerSource(displayPath: url.path, bookmarkData: data, sourceID: sourceID)
            projects.update(project)
            _ = try? securityScope.beginAccess(sourceID: sourceID, bookmarkData: data)
            activity.errorMessage = nil
            analysisStaleBannerSuppressed = false
            Task {
                do {
                    try await ensureIndexReady()
                } catch {
                    activity.errorMessage = error.localizedDescription
                }
                await refreshAnalysisStaleHint()
                startIfNeeded()
            }
        } catch {
            activity.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Records a chosen source folder. Used by the open panel and by tests.
    func registerSource(displayPath: String, bookmarkData: Data, sourceID: String = UUID().uuidString) {
        let bookmark = SourceBookmark(id: sourceID, displayPath: displayPath, bookmarkData: bookmarkData)
        project.sourceBookmarks.append(bookmark)
        if !project.sources.contains(displayPath) {
            project.sources.append(displayPath)
        }
    }

    func removeSource(id: String) {
        securityScope.release(sourceID: id)
        let removedPath = project.sourceBookmarks.first(where: { $0.id == id })?.displayPath
        project.sourceBookmarks.removeAll { $0.id == id }
        if let removedPath {
            project.sources.removeAll { $0 == removedPath }
            forgetPhotos(under: removedPath)
        } else {
            projects.update(project)
        }
        Task {
            await dropIndexedSource(id: id, path: removedPath)
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
        forgetPhotos(under: path)
        Task {
            await dropIndexedSource(id: path, path: path)
        }
    }

    /// Drops a removed folder from albums, the delete bin, and the current selection.
    private func forgetPhotos(under prefix: String) {
        func isUnder(_ path: String) -> Bool {
            path == prefix || path.hasPrefix(prefix.hasSuffix("/") ? prefix : prefix + "/")
        }
        project.deleteBinPaths.removeAll(where: isUnder)
        project.annotations.removeAll { isUnder($0.path) }
        for index in project.albums.indices {
            project.albums[index].memberPaths.removeAll(where: isUnder)
        }
        for index in project.personGroups.indices {
            project.personGroups[index].memberPhotoPaths.removeAll(where: isUnder)
            if project.personGroups[index].thumbnailPath.map(isUnder) == true {
                project.personGroups[index].thumbnailPath = nil
            }
        }
        selectedPaths = selectedPaths.filter { !isUnder($0) }
        if selectedSidebarKey == "source:\(prefix)" {
            selectedSidebarKey = nil
        }
        projects.update(project)
        syncSelectionModeFromSelection()
    }

    /// Stops an in-flight catalog so it cannot write the folder back, then deletes its index rows.
    private func dropIndexedSource(id: String, path: String?) async {
        generation += 1
        let priorCatalog = catalogTask
        catalogTask = nil
        priorCatalog?.cancel()
        await catalog.cancelAndWait()
        await priorCatalog?.value

        if let store = index {
            try? await store.removeSource(id)
            if let path {
                try? await store.removePaths(withPathPrefix: path)
            }
        }
        analysisStaleBannerSuppressed = false
        appliedVisiblePathsQueryFingerprint = nil
        await reloadVisiblePaths()
        await refreshSidebarBuckets()
        await refreshAnalysisStaleHint()
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

    var filteredPersonId: String? {
        guard let key = selectedSidebarKey, key.hasPrefix("person:") else { return nil }
        let id = String(key.dropFirst("person:".count))
        return id.isEmpty ? nil : id
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

    /// Shown in the bottom filter banner. The delete bin has its own bar.
    var filterBannerDescriptions: [String] {
        gridFilterDescriptionParts(includeCategoryChips: true, includeDeleteBin: false)
    }

    var activeFilterDescriptions: [String] {
        gridFilterDescriptionParts(includeCategoryChips: true, includeDeleteBin: true)
    }

    var filteredSidebarObjects: [(name: String, count: Int)] {
        let query = objectSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Array(sidebarObjects.prefix(40)) }
        return sidebarObjects.filter { $0.name.localizedStandardContains(query) }
    }

    private func gridFilterDescriptionParts(includeCategoryChips: Bool, includeDeleteBin: Bool) -> [String] {
        var parts: [String] = []
        let objectQuery = objectSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !objectQuery.isEmpty, selectedSidebarKey?.hasPrefix("object:") != true {
            parts.append("Objects matching “\(objectQuery)”")
        }
        if let matches = faceMatchPaths {
            let noun = matches.count == 1 ? "photo" : "photos"
            parts.append("Face search: \(matches.count) \(noun)")
        }

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
            case let key where key.hasPrefix("object:"):
                parts.append("Object: \(String(key.dropFirst("object:".count)))")
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
                if usesFolderBrowsing {
                    parts.append("Folder: \(short)")
                } else {
                    parts.append("Source: \(short)")
                }
            case let key where key.hasPrefix("folder:"):
                let folder = String(key.dropFirst("folder:".count))
                let relative = sourceFolders.first { $0.path == folder }?.relativePath
                    ?? (folder as NSString).lastPathComponent
                if usesFolderBrowsing {
                    parts.append("Folder: \(relative)")
                } else {
                    parts.append("Folder: \(relative), with subfolders")
                }
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
        cancelFaceSearch()
        highlightsFilteredFace = false
        objectSearchText = ""
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
            paths = await filterPathsBySelectedMediaTypes(paths)
            if let matches = faceMatchPaths {
                let allowed = Set(matches)
                paths = paths.filter { allowed.contains($0) }
            }
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
            objectSearchText,
            photoSort.rawValue,
            media,
            after,
            before,
            person,
            project.filter.excludedNameFragments.joined(separator: "|"),
            project.filter.excludedExtensions.joined(separator: "|"),
            project.deleteBinPaths.joined(separator: "|"),
            usesFolderBrowsing ? "folders" : "all",
            faceMatchPaths == nil ? "" : "face:\(faceMatchToken)",
            "lookedUp:\(lookedUpMemberToken)",
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

    private func filterPathsBySelectedMediaTypes(_ paths: [String]) async -> [String] {
        guard isMediaTypeFilterActive else { return paths }
        guard !selectedMediaExtensions.isEmpty else { return [] }
        let allowed = selectedMediaExtensions
        guard paths.count > 512 else {
            return paths.filter { path in
                let ext = (path as NSString).pathExtension.lowercased()
                return allowed.contains(ext)
            }
        }
        return await Task.detached {
            paths.filter { path in
                let ext = (path as NSString).pathExtension.lowercased()
                return allowed.contains(ext)
            }
        }.value
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

        let objectQuery = objectSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !objectQuery.isEmpty, selectedSidebarKey?.hasPrefix("object:") != true {
            let matches = Set(try await store.pathsMatchingObject(query: objectQuery, exact: false))
            extra = extra.map { $0.intersection(matches) } ?? matches
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
        if key.hasPrefix("object:") {
            let name = String(key.dropFirst("object:".count))
            return Set(try await store.pathsMatchingObject(query: name, exact: true))
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
            let indexed = Set(try await store.pathsForSmartRules(SmartAlbumRules(conditions: [
                SmartAlbumRule(type: .personGroupId, value: personId),
            ])))
            let members = Set(project.personGroups.first { $0.id == personId }?.memberPhotoPaths ?? [])
            return indexed.union(members)
        }
        if key.hasPrefix("source:") {
            let prefix = String(key.dropFirst("source:".count))
            if usesFolderBrowsing {
                return Set(try await store.paths(inFolder: prefix, includeNested: false))
            }
            return Set(try await store.pathsForSmartRules(SmartAlbumRules(conditions: [
                SmartAlbumRule(type: .sourcePathPrefix, value: prefix),
            ])))
        }
        if key.hasPrefix("folder:") {
            let folder = String(key.dropFirst("folder:".count))
            return Set(try await store.paths(inFolder: folder, includeNested: !usesFolderBrowsing))
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
        guard categoryDetectionOn || objectDetectionOn || analyzeFacesOn else {
            activity.errorMessage = "Turn on Categories, Objects, and/or Faces, then click Run."
            return
        }
        guard let store = index else { return }
        let paths = (try? await store.allPaths()) ?? []
        guard !paths.isEmpty else { return }

        activity.isMetadataing = true
        activity.isAnalyzing = categoryDetectionOn || objectDetectionOn
        activity.analysisTitle = objectDetectionOn && !categoryDetectionOn ? "Finding objects…" : "Analyzing…"
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
                objectsOn: objectDetectionOn,
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
                    self.project.personGroups = self.mergingLookedUpPeople(into: groups)
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
            guard categoryDetectionOn || objectDetectionOn || analyzeFacesOn else {
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
        for name in record.objectLabels where !categories.contains(name) {
            categories.append(name)
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
        var seen = Set(project.albums[index].memberPaths)
        let unique = paths.filter { path in
            guard seen.insert(path).inserted else { return false }
            return true
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

    /// Photos that would be copied for this album, without asking for a destination folder.
    func exportPhotoPaths(for album: Album) async -> [String] {
        switch album.kind {
        case .manual, .favorites:
            return album.memberPaths
        case .smart:
            guard let store = index else { return [] }
            return (try? await store.pathsForSmartRules(album.rules ?? SmartAlbumRules())) ?? []
        }
    }

    @discardableResult
    func exportSelectedAlbum() -> Bool {
        guard let albumId = selectedAlbumId,
              let album = project.albums.first(where: { $0.id == albumId })
        else {
            return false
        }

        Task {
            let paths = await exportPhotoPaths(for: album)

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
        return true
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

    /// Faces of the person currently chosen in People or the left filter.
    func highlightedFaces(on path: String) async -> [FaceAlignment.AlignedFace] {
        guard highlightsFilteredFace, let personId = filteredPersonId,
              let person = project.personGroups.first(where: { $0.id == personId })
        else { return [] }
        let cached = personEmbeddingCache[person.id]
        let referencePaths = referenceImagePaths(for: person)
        let result = await Task.detached(priority: .userInitiated) {
            let faces = FaceAlignment.alignedFaces(from: URL(fileURLWithPath: path))
            let personEmbedding = cached ?? FacePhotoWork.embedding(forImagePaths: referencePaths)
            guard !faces.isEmpty else { return (faces: [FaceAlignment.AlignedFace](), embedding: personEmbedding) }
            var embeddings: [UUID: FaceEmbedding] = [:]
            for face in faces {
                embeddings[face.id] = AdaFaceEmbedder.embedding(forAlignedFace: face.image)
            }
            let matches = FaceNameMatcher.matchingFaceIDs(
                faceIDs: faces.map(\.id),
                faceEmbeddings: embeddings,
                personEmbedding: personEmbedding
            )
            return (faces: faces.filter { matches.contains($0.id) }, embedding: personEmbedding)
        }.value
        if let embedding = result.embedding {
            personEmbeddingCache[person.id] = embedding
        }
        return result.faces
    }

    /// Names to draw on faces in one photo. Includes people from the top row and the left filter.
    func faceLabels(for faces: [FaceAlignment.AlignedFace], path: String) async -> [UUID: String] {
        let people = await namedPeople(on: path)
        guard !faces.isEmpty, !people.isEmpty else { return [:] }
        let described = people.map { person in
            (
                name: person.name,
                embedding: personEmbeddingCache[person.group.id],
                paths: referenceImagePaths(for: person.group)
            )
        }
        let faceImages = faces.map { (id: $0.id, image: $0.image) }
        return await Task.detached(priority: .userInitiated) {
            var faceEmbeddings: [UUID: FaceEmbedding] = [:]
            for face in faceImages {
                faceEmbeddings[face.id] = AdaFaceEmbedder.embedding(forAlignedFace: face.image)
            }
            let named = described.map { person in
                (
                    name: person.name,
                    embedding: person.embedding ?? FacePhotoWork.embedding(forImagePaths: person.paths)
                )
            }
            return FaceNameMatcher.labels(
                faceIDs: faceImages.map(\.id),
                faceEmbeddings: faceEmbeddings,
                people: named
            )
        }.value
    }

    private func namedPeople(on path: String) async -> [(name: String, group: PersonGroup)] {
        var ids = Set(project.personGroups.filter { $0.memberPhotoPaths.contains(path) }.map(\.id))
        if let record = try? await index?.record(for: path) {
            ids.formUnion(record.personGroupIds)
        }
        return project.personGroups.compactMap { group in
            guard ids.contains(group.id) else { return nil }
            let name = group.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { return nil }
            return (name, group)
        }
    }

    private var personEmbeddingCache: [String: FaceEmbedding] = [:]

    private func referenceImagePaths(for person: PersonGroup) -> [String] {
        [person.faceCropPath, person.thumbnailPath, person.memberPhotoPaths.first].compactMap { $0 }
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