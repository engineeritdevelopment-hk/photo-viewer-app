import XCTest
@testable import Photo_Viewer

@MainActor
final class MissingLibraryUseCaseTests: XCTestCase {
    private var tempRoot: URL!
    private var projects: ProjectsViewModel!
    private var dbURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = try TempDirectory.create()
        ApplicationPaths.useIsolatedSupportRoot(tempRoot)
        projects = ProjectsViewModel()
        let created = projects.create(name: "Gaps")!
        projects.projects = [created]
        dbURL = tempRoot.appendingPathComponent("gaps.sqlite")
    }

    override func tearDownWithError() throws {
        ApplicationPaths.resetSupportRootOverride()
        TempDirectory.remove(tempRoot)
        tempRoot = nil
        projects = nil
        dbURL = nil
        try super.tearDownWithError()
    }

    private func indexedModel() async throws -> (LibraryViewModel, PhotoIndexStore) {
        let store = try PhotoIndexStore(databaseAt: dbURL)
        try await IndexedPhotoFixture.populateMixedLibrary(on: store)
        let model = LibraryViewModel(project: projects.projects[0], projects: projects)
        await model.attachPhotoIndexForTesting(store)
        return (model, store)
    }

    private func awaitPaths(_ model: LibraryViewModel, until match: @escaping ([String]) -> Bool) async {
        for _ in 0 ..< 50 {
            if match(model.visiblePaths) { return }
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    func testMediaTypeToggleAndSelectAll() async throws {
        let (model, _) = try await indexedModel()
        model.toggleMediaType("png")
        await awaitPaths(model) { paths in
            !paths.contains(IndexedPhotoFixture.pathScreenshot) && paths.count == 3
        }
        XCTAssertFalse(model.visiblePaths.contains(IndexedPhotoFixture.pathScreenshot))

        model.selectAllMediaTypes()
        await awaitPaths(model) { $0.count == 4 }
        XCTAssertEqual(model.visiblePaths.count, 4)
    }

    func testFilenameExclusionReloadsTheGrid() async throws {
        let (model, _) = try await indexedModel()
        model.setNameFilter(excludedNames: "screen")
        await awaitPaths(model) { paths in
            !paths.contains(IndexedPhotoFixture.pathScreenshot) && !paths.isEmpty
        }
        XCTAssertFalse(model.visiblePaths.contains(IndexedPhotoFixture.pathScreenshot))
        XCTAssertTrue(model.visiblePaths.contains(IndexedPhotoFixture.pathBeach))
    }

    func testPlaceCameraAndNoLocationNarrowTheGrid() async throws {
        let (model, _) = try await indexedModel()

        model.selectSidebarFilter("place:Honolulu")
        model.applySidebarKey(model.selectedSidebarKey)
        await awaitPaths(model) { $0 == [IndexedPhotoFixture.pathBeach] }
        XCTAssertEqual(model.visiblePaths, [IndexedPhotoFixture.pathBeach])

        model.selectSidebarFilter("camera:ILCE-7M3")
        model.applySidebarKey(model.selectedSidebarKey)
        await awaitPaths(model) { $0 == [IndexedPhotoFixture.pathBeach] }
        XCTAssertEqual(model.visiblePaths, [IndexedPhotoFixture.pathBeach])

        model.selectSidebarFilter("place:No location")
        model.applySidebarKey(model.selectedSidebarKey)
        await awaitPaths(model) { Set($0) == [IndexedPhotoFixture.pathScreenshot, IndexedPhotoFixture.pathOther] }
        XCTAssertEqual(
            Set(model.visiblePaths),
            [IndexedPhotoFixture.pathScreenshot, IndexedPhotoFixture.pathOther]
        )
    }

    func testSmartAlbumSelectionShowsMatchingPhotos() async throws {
        let (model, _) = try await indexedModel()
        model.createSmartAlbum(
            name: "Shots",
            rules: SmartAlbumRules(conditions: [SmartAlbumRule(type: .screenshot, value: "1")])
        )
        await awaitPaths(model) { $0 == [IndexedPhotoFixture.pathScreenshot] }
        XCTAssertEqual(model.visiblePaths, [IndexedPhotoFixture.pathScreenshot])
        let paths = await model.exportPhotoPaths(for: model.project.albums.first { $0.kind == .smart }!)
        XCTAssertEqual(paths, [IndexedPhotoFixture.pathScreenshot])
    }

    func testSemanticCategoryPinDismissAndFilter() async throws {
        let (model, store) = try await indexedModel()
        for path in [IndexedPhotoFixture.pathBeach, IndexedPhotoFixture.path2020, IndexedPhotoFixture.pathOther] {
            try await store.updateAnalysis(
                path: path,
                sceneLabels: ["food"],
                ocrSnippet: nil,
                semanticCategory: "Food",
                source: .metadata
            )
        }
        await model.loadDetectedCategories()
        XCTAssertTrue(model.detectedCategories.contains { $0.title == "Food" })

        model.selectSemanticCategory("Food")
        await awaitPaths(model) {
            Set($0) == [IndexedPhotoFixture.pathBeach, IndexedPhotoFixture.path2020, IndexedPhotoFixture.pathOther]
        }
        XCTAssertEqual(model.visiblePaths.count, 3)
        XCTAssertTrue(model.isViewFiltered)
        XCTAssertEqual(model.viewFilterSummary, "Category: Food")

        let food = model.detectedCategories.first { $0.title == "Food" }!
        model.pinCategoryAsAlbum(food)
        XCTAssertFalse(model.detectedCategories.contains { $0.title == "Food" })
        XCTAssertTrue(model.project.albums.contains { $0.name == "Food" && $0.kind == .smart })

        model.detectedCategories.append(("Noise", 3, SmartAlbumRule(type: .semanticCategory, value: "Noise")))
        model.dismissDetectedCategory("Noise")
        XCTAssertFalse(model.detectedCategories.contains { $0.title == "Noise" })
    }

    func testPersonFilterClearAndRemove() async throws {
        let (model, store) = try await indexedModel()
        try await store.updatePersonGroups(path: IndexedPhotoFixture.pathBeach, groupIds: ["p1"])
        var project = model.project
        let crop = tempRoot.appendingPathComponent("face.jpg")
        try Data("face".utf8).write(to: crop)
        project.personGroups = [
            PersonGroup(
                id: "p1",
                displayName: "Ada",
                memberPhotoPaths: [IndexedPhotoFixture.pathBeach],
                faceCropPath: crop.path
            ),
        ]
        projects.update(project)
        model.project = projects.projects[0]

        model.selectPerson(id: "p1")
        await awaitPaths(model) { $0 == [IndexedPhotoFixture.pathBeach] }
        XCTAssertEqual(model.visiblePaths, [IndexedPhotoFixture.pathBeach])

        model.clearPersonFilter()
        await awaitPaths(model) { $0.count == 4 }
        XCTAssertEqual(model.visiblePaths.count, 4)

        model.selectPerson(id: "p1")
        model.removePersonGroup(id: "p1")
        for _ in 0 ..< 40 {
            if model.project.personGroups.isEmpty, !FileManager.default.fileExists(atPath: crop.path) { break }
            try? await Task.sleep(for: .milliseconds(40))
        }
        XCTAssertTrue(model.project.personGroups.isEmpty)
        XCTAssertNil(model.selectedSidebarKey)
        XCTAssertFalse(FileManager.default.fileExists(atPath: crop.path))
        let record = try await store.record(for: IndexedPhotoFixture.pathBeach)
        XCTAssertTrue(record?.personGroupIds.isEmpty == true)
    }

    func testClearAnalysisDataKeepsPhotosAndNotes() async throws {
        let (model, store) = try await indexedModel()
        try await store.updateAnalysis(
            path: IndexedPhotoFixture.pathBeach,
            sceneLabels: ["portrait"],
            ocrSnippet: "hello",
            semanticCategory: "People",
            source: .metadata
        )
        try await store.updatePersonGroups(path: IndexedPhotoFixture.pathBeach, groupIds: ["p1"])
        let crop = tempRoot.appendingPathComponent("face.jpg")
        try Data("face".utf8).write(to: crop)
        var project = model.project
        project.personGroups = [
            PersonGroup(
                id: "p1",
                displayName: "Ada",
                memberPhotoPaths: [IndexedPhotoFixture.pathBeach],
                faceCropPath: crop.path
            ),
        ]
        project.analysisCheckpoint = AnalysisCheckpoint(
            completedAt: Date(),
            indexedPathCount: 4,
            sourceFingerprint: "src"
        )
        projects.update(project)
        model.project = projects.projects[0]
        model.updateAnnotation(PhotoAnnotation(path: IndexedPhotoFixture.pathBeach, place: "Hall", suggestedTitle: "Title"))
        model.selectSemanticCategory("People")

        model.clearAnalysisData()
        for _ in 0 ..< 40 {
            let record = try await store.record(for: IndexedPhotoFixture.pathBeach)
            if model.project.personGroups.isEmpty,
               record?.semanticCategory == nil,
               record?.personGroupIds.isEmpty == true {
                break
            }
            try? await Task.sleep(for: .milliseconds(40))
        }

        let record = try await store.record(for: IndexedPhotoFixture.pathBeach)
        let photoCount = try await store.count()
        XCTAssertNil(record?.semanticCategory)
        XCTAssertNil(record?.ocrSnippet)
        XCTAssertTrue(record?.sceneLabels.isEmpty == true)
        XCTAssertTrue(record?.personGroupIds.isEmpty == true)
        XCTAssertEqual(photoCount, 4)
        XCTAssertTrue(model.project.personGroups.isEmpty)
        XCTAssertNil(model.project.analysisCheckpoint)
        XCTAssertFalse(FileManager.default.fileExists(atPath: crop.path))
        XCTAssertEqual(model.annotation(for: IndexedPhotoFixture.pathBeach).place, "Hall")
        XCTAssertNil(model.annotation(for: IndexedPhotoFixture.pathBeach).suggestedTitle)
        XCTAssertNil(model.selectedSidebarKey)
        XCTAssertTrue(model.detectedCategories.isEmpty)
    }

    func testDeleteBinViewAndEmptyWithoutDeletingFiles() async throws {
        let (model, _) = try await indexedModel()
        model.addToDeleteBin(paths: [IndexedPhotoFixture.pathBeach])
        model.showDeleteBinInSidebar()
        await awaitPaths(model) { $0 == [IndexedPhotoFixture.pathBeach] }
        XCTAssertEqual(model.visiblePaths, [IndexedPhotoFixture.pathBeach])
        XCTAssertTrue(model.isViewingDeleteBin)

        model.emptyDeleteBin()
        await awaitPaths(model) { $0.isEmpty }
        XCTAssertTrue(model.visiblePaths.isEmpty)
        XCTAssertEqual(model.deleteBinCount, 0)
    }

    func testFavoriteSelectionStarsThenClears() async throws {
        let (model, _) = try await indexedModel()
        model.visiblePaths = [IndexedPhotoFixture.pathBeach, IndexedPhotoFixture.path2020]
        model.selectAllVisiblePhotos()
        model.toggleFavoriteSelectedPhotos()
        XCTAssertTrue(model.isFavorite(path: IndexedPhotoFixture.pathBeach))
        XCTAssertTrue(model.isFavorite(path: IndexedPhotoFixture.path2020))

        model.toggleFavoriteSelectedPhotos()
        XCTAssertFalse(model.isFavorite(path: IndexedPhotoFixture.pathBeach))
        XCTAssertFalse(model.isFavorite(path: IndexedPhotoFixture.path2020))
    }

    func testLegacyFolderRemovalDropsIndexedPhotos() async throws {
        let (model, store) = try await indexedModel()
        let folder = IndexedPhotoFixture.diskAPrefix
        model.project.sources = [folder]
        projects.update(model.project)

        model.removeLegacySource(path: folder)
        for _ in 0 ..< 40 {
            if !model.visiblePaths.contains(IndexedPhotoFixture.path2020) { break }
            try? await Task.sleep(for: .milliseconds(40))
        }
        XCTAssertFalse(model.project.sources.contains(folder))
        XCTAssertFalse(model.visiblePaths.contains(IndexedPhotoFixture.path2020))
        XCTAssertFalse(model.visiblePaths.contains(IndexedPhotoFixture.pathScreenshot))
        XCTAssertTrue(model.visiblePaths.contains(IndexedPhotoFixture.pathBeach))
        let remaining = try await store.allPaths()
        XCTAssertFalse(remaining.contains(IndexedPhotoFixture.path2020))
    }

    func testExportRequiresASelectedAlbum() {
        let model = LibraryViewModel(project: projects.projects[0], projects: projects)
        XCTAssertFalse(model.exportSelectedAlbum())
        XCTAssertNil(model.activity.errorMessage)
    }
}
