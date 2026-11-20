import XCTest
@testable import Photo_Viewer

@MainActor
final class SourceFolderBrowseTests: XCTestCase {
    private var tempRoot: URL!
    private var projects: ProjectsViewModel!
    private var dbURL: URL!
    private var savedFolderView: Any?

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = try TempDirectory.create()
        ApplicationPaths.useIsolatedSupportRoot(tempRoot)
        projects = ProjectsViewModel()
        let created = projects.create(name: "Folders")!
        projects.projects = [created]
        dbURL = tempRoot.appendingPathComponent("folders.sqlite")
        savedFolderView = UserDefaults.standard.object(forKey: AppPreferences.sourceFolderViewKey)
        UserDefaults.standard.removeObject(forKey: AppPreferences.sourceFolderViewKey)
    }

    override func tearDownWithError() throws {
        if let savedFolderView {
            UserDefaults.standard.set(savedFolderView, forKey: AppPreferences.sourceFolderViewKey)
        } else {
            UserDefaults.standard.removeObject(forKey: AppPreferences.sourceFolderViewKey)
        }
        ApplicationPaths.resetSupportRootOverride()
        TempDirectory.remove(tempRoot)
        tempRoot = nil
        projects = nil
        dbURL = nil
        try super.tearDownWithError()
    }

    private func awaitPaths(_ model: LibraryViewModel, until match: @escaping ([String]) -> Bool) async {
        for _ in 0 ..< 50 {
            if match(model.visiblePaths) { return }
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    func testMultipleFoldersCanBeBrowsedOneAtATimeOrIncludingNested() async throws {
        let store = try PhotoIndexStore(databaseAt: dbURL)
        try await IndexedPhotoFixture.populateMixedLibrary(on: store)
        try await store.upsertCatalogRow(
            path: "/Volumes/DiskA/2024/trip/nested.jpg",
            sourceId: "src-a",
            modTime: IndexedPhotoFixture.date(2024, 4, 1),
            fileSize: 10
        )

        let counts = try await store.directPhotoCountsByFolder()
        XCTAssertTrue(
            SourceFolderIndex.sourceHasMultipleFolders(folderCounts: counts, sourcePath: IndexedPhotoFixture.diskAPrefix)
        )
        XCTAssertFalse(
            SourceFolderIndex.sourceHasMultipleFolders(folderCounts: counts, sourcePath: IndexedPhotoFixture.diskBPrefix)
        )

        var project = projects.projects[0]
        project.sources = [IndexedPhotoFixture.diskAPrefix, IndexedPhotoFixture.diskBPrefix]
        projects.update(project)
        let model = LibraryViewModel(project: projects.projects[0], projects: projects)
        await model.attachPhotoIndexForTesting(store)

        XCTAssertTrue(model.canBrowseSourceByFolder)
        XCTAssertEqual(
            model.sourceFolders(under: IndexedPhotoFixture.diskAPrefix).map(\.relativePath),
            ["2020", "2024", "2024/trip"]
        )

        model.setSourceFolderView(.byFolder)
        model.selectSidebarFilter("folder:/Volumes/DiskA/2024")
        model.applySidebarKey(model.selectedSidebarKey)
        await awaitPaths(model) { $0 == [IndexedPhotoFixture.pathScreenshot] }
        XCTAssertEqual(model.visiblePaths, [IndexedPhotoFixture.pathScreenshot])
        XCTAssertTrue(model.viewFilterSummary.contains("Folder: 2024"))

        model.selectSidebarFilter("folder:/Volumes/DiskA/2024/trip")
        model.applySidebarKey(model.selectedSidebarKey)
        await awaitPaths(model) { $0 == ["/Volumes/DiskA/2024/trip/nested.jpg"] }
        XCTAssertEqual(model.visiblePaths, ["/Volumes/DiskA/2024/trip/nested.jpg"])

        model.setSourceFolderView(.allNested)
        model.selectSidebarFilter("source:\(IndexedPhotoFixture.diskAPrefix)")
        model.applySidebarKey(model.selectedSidebarKey)
        await awaitPaths(model) { paths in
            paths.contains(IndexedPhotoFixture.path2020)
                && paths.contains(IndexedPhotoFixture.pathScreenshot)
                && paths.contains("/Volumes/DiskA/2024/trip/nested.jpg")
                && !paths.contains(IndexedPhotoFixture.pathBeach)
        }
        XCTAssertTrue(model.visiblePaths.contains("/Volumes/DiskA/2024/trip/nested.jpg"))
        XCTAssertTrue(model.viewFilterSummary.contains("Source: DiskA"))
    }
}
