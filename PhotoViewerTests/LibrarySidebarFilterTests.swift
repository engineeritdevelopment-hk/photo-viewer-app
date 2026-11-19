import XCTest
@testable import Photo_Viewer

@MainActor
final class LibrarySidebarFilterTests: XCTestCase {
    private var tempRoot: URL!
    private var projects: ProjectsViewModel!
    private var dbURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = try TempDirectory.create()
        ApplicationPaths.useIsolatedSupportRoot(tempRoot)
        projects = ProjectsViewModel()
        let created = projects.create(name: "Filter Tests")!
        projects.projects = [created]
        dbURL = tempRoot.appendingPathComponent("filter-catalog.sqlite")
    }

    override func tearDownWithError() throws {
        ApplicationPaths.resetSupportRootOverride()
        TempDirectory.remove(tempRoot)
        tempRoot = nil
        projects = nil
        dbURL = nil
        try super.tearDownWithError()
    }

    private func makeModelWithIndex() async throws -> (LibraryViewModel, PhotoIndexStore) {
        let store = try PhotoIndexStore(databaseAt: dbURL)
        try await IndexedPhotoFixture.populateMixedLibrary(on: store)
        let model = LibraryViewModel(project: projects.projects[0], projects: projects)
        await model.attachPhotoIndexForTesting(store)
        return (model, store)
    }

    private func awaitGridSettle(_ model: LibraryViewModel) async {
        try? await Task.sleep(for: .milliseconds(64))
        for _ in 0 ..< 40 {
            try? await Task.sleep(for: .milliseconds(32))
            if !model.activity.isCataloging { break }
        }
    }

    func testSelectSidebarFilterTogglesOff() throws {
        let model = LibraryViewModel(project: projects.projects[0], projects: projects)
        model.selectSidebarFilter("date:2024")
        XCTAssertEqual(model.selectedSidebarKey, "date:2024")
        model.selectSidebarFilter("date:2024")
        XCTAssertNil(model.selectedSidebarKey)
        model.selectSidebarFilter(nil)
        XCTAssertNil(model.selectedSidebarKey)
    }

    func testActiveFilterDescriptionsForSidebarKeys() {
        let model = LibraryViewModel(project: projects.projects[0], projects: projects)
        model.selectedSidebarKey = "date:2023"
        XCTAssertTrue(model.viewFilterSummary.contains("Year: 2023"))
        model.selectedSidebarKey = "place:Paris"
        XCTAssertTrue(model.viewFilterSummary.contains("Place: Paris"))
        model.selectedSidebarKey = "source:\(IndexedPhotoFixture.diskAPrefix)"
        XCTAssertTrue(model.viewFilterSummary.contains("Source:"))
        model.selectedSidebarKey = "browse:screenshots"
        XCTAssertTrue(model.viewFilterSummary.contains("Screenshots"))
    }

    func testApplySidebarKeyYearFiltersGrid() async throws {
        let (model, _) = try await makeModelWithIndex()
        XCTAssertEqual(model.visiblePaths.count, 4)

        model.selectSidebarFilter("date:2020")
        model.applySidebarKey(model.selectedSidebarKey)
        await awaitGridSettle(model)

        XCTAssertEqual(Set(model.visiblePaths), [IndexedPhotoFixture.path2020])
        XCTAssertTrue(model.isViewFiltered)
    }

    func testApplySidebarKeySourcePrefix() async throws {
        let (model, _) = try await makeModelWithIndex()
        let key = "source:\(IndexedPhotoFixture.diskBPrefix)"
        model.selectSidebarFilter(key)
        model.applySidebarKey(key)
        await awaitGridSettle(model)

        XCTAssertEqual(Set(model.visiblePaths), [IndexedPhotoFixture.pathBeach])
    }

    func testApplySidebarKeyScreenshots() async throws {
        let (model, _) = try await makeModelWithIndex()
        model.selectSidebarFilter("browse:screenshots")
        model.applySidebarKey("browse:screenshots")
        await awaitGridSettle(model)

        XCTAssertEqual(model.visiblePaths, [IndexedPhotoFixture.pathScreenshot])
    }

    func testApplySidebarKeyClearsAlbumMode() async throws {
        var project = projects.projects[0]
        project.albums = [
            Album(id: "a1", name: "Vacation", kind: .manual, memberPaths: [IndexedPhotoFixture.pathBeach]),
        ]
        projects.update(project)

        let store = try PhotoIndexStore(databaseAt: dbURL)
        try await IndexedPhotoFixture.populateMixedLibrary(on: store)
        let model = LibraryViewModel(project: projects.projects[0], projects: projects)
        await model.attachPhotoIndexForTesting(store)
        model.selectedSidebarKey = "album:a1"
        model.applySidebarKey("album:a1")
        await awaitGridSettle(model)
        XCTAssertEqual(Set(model.visiblePaths), [IndexedPhotoFixture.pathBeach])

        model.selectSidebarFilter("date:2020")
        model.applySidebarKey("date:2020")
        await awaitGridSettle(model)

        XCTAssertEqual(model.groupBy, .none)
        XCTAssertNil(model.selectedAlbumId)
        XCTAssertEqual(Set(model.visiblePaths), [IndexedPhotoFixture.path2020])
    }

    func testDateRangeMetadataNarrowsGrid() async throws {
        let (model, _) = try await makeModelWithIndex()
        var filter = MetadataFilter()
        filter.takenAfter = model.startOfDay(IndexedPhotoFixture.date(2024, 7, 1))
        filter.takenBefore = model.endOfDay(IndexedPhotoFixture.date(2024, 12, 31))
        model.applyMetadataFilter(filter)
        await awaitGridSettle(model)

        XCTAssertEqual(Set(model.visiblePaths), [IndexedPhotoFixture.pathBeach])
        XCTAssertTrue(model.viewFilterSummary.contains("Dates:"))
    }

    func testResetAllViewFiltersClearsSidebarAndDates() async throws {
        let (model, _) = try await makeModelWithIndex()
        model.selectSidebarFilter("place:Honolulu")
        model.applyMetadataFilter(MetadataFilter(
            takenAfter: IndexedPhotoFixture.date(2020, 1, 1),
            takenBefore: IndexedPhotoFixture.date(2020, 12, 31)
        ))
        await awaitGridSettle(model)
        XCTAssertTrue(model.isViewFiltered)

        model.resetAllViewFilters()
        await awaitGridSettle(model)

        XCTAssertNil(model.selectedSidebarKey)
        XCTAssertFalse(model.hasDateRangeFilter)
        XCTAssertFalse(model.isViewFiltered)
        XCTAssertEqual(model.visiblePaths.count, 4)
    }

    func testRefreshSidebarBucketsAfterIndexAttach() async throws {
        let (model, _) = try await makeModelWithIndex()
        XCTAssertFalse(model.sidebarYears.isEmpty)
        XCTAssertTrue(model.sidebarPlaces.contains { $0.name == "Paris, France" })
        XCTAssertTrue(model.sidebarCameras.contains { $0.name.contains("ILCE-7M3") })
        XCTAssertEqual(model.sidebarScreenshotCount, 1)
    }

    func testAnalysisStaleAfterNewPhotosIndexed() async throws {
        let store = try PhotoIndexStore(databaseAt: dbURL)
        try await IndexedPhotoFixture.populateMixedLibrary(on: store)
        var project = projects.projects[0]
        project.analysisCheckpoint = AnalysisCheckpoint(
            completedAt: Date(),
            indexedPathCount: 1,
            sourceFingerprint: "src-a"
        )
        projects.update(project)

        let model = LibraryViewModel(project: projects.projects[0], projects: projects)
        model.categoryDetectionOn = true
        await model.attachPhotoIndexForTesting(store)

        XCTAssertEqual(model.analysisStaleHint?.newPhotoCount, 3)
        XCTAssertFalse(model.analysisStaleHint?.neverAnalyzed ?? true)
        XCTAssertTrue(model.shouldShowAnalysisStaleBanner)
    }

    func testAnalysisStaleWhenSourcesFingerprintChanges() async throws {
        let (model, _) = try await makeModelWithIndex()
        var project = model.project
        project.analysisCheckpoint = AnalysisCheckpoint(
            completedAt: Date(),
            indexedPathCount: 4,
            sourceFingerprint: "old-source-set"
        )
        projects.update(project)
        model.project = projects.projects[0]

        await model.refreshAnalysisStaleHint()

        XCTAssertTrue(model.analysisStaleHint?.sourcesChanged == true)
        XCTAssertTrue(model.shouldShowAnalysisStaleBanner)
    }

    func testAnalysisStaleWhenSourcesChangeWithoutTogglesOn() async throws {
        let (model, _) = try await makeModelWithIndex()
        model.categoryDetectionOn = false
        model.analyzeFacesOn = false
        var project = model.project
        project.analysisCheckpoint = AnalysisCheckpoint(
            completedAt: Date(),
            indexedPathCount: 4,
            sourceFingerprint: "old-source-set"
        )
        projects.update(project)
        model.project = projects.projects[0]

        await model.refreshAnalysisStaleHint()

        XCTAssertTrue(model.analysisStaleHint?.sourcesChanged == true)
        XCTAssertTrue(model.shouldShowAnalysisStaleBanner)
    }

    func testAnalysisCheckpointClearsStaleBanner() async throws {
        let (model, _) = try await makeModelWithIndex()
        model.categoryDetectionOn = true
        model.project.analysisCheckpoint = AnalysisCheckpoint(
            completedAt: Date.distantPast,
            indexedPathCount: 1,
            sourceFingerprint: model.sourceFingerprint()
        )
        await model.refreshAnalysisStaleHint()
        XCTAssertNotNil(model.analysisStaleHint)

        await model.recordAnalysisCheckpoint()
        await model.refreshAnalysisStaleHint()
        XCTAssertNil(model.analysisStaleHint)
    }
}