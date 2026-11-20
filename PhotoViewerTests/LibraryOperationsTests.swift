import XCTest
@testable import Photo_Viewer

@MainActor
final class LibraryOperationsTests: XCTestCase {
    private var tempRoot: URL!
    private var projects: ProjectsViewModel!
    private var dbURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = try TempDirectory.create()
        ApplicationPaths.useIsolatedSupportRoot(tempRoot)
        projects = ProjectsViewModel()
        let created = projects.create(name: "Operations")!
        projects.projects = [created]
        dbURL = tempRoot.appendingPathComponent("operations.sqlite")
    }

    override func tearDownWithError() throws {
        ApplicationPaths.resetSupportRootOverride()
        TempDirectory.remove(tempRoot)
        tempRoot = nil
        projects = nil
        dbURL = nil
        try super.tearDownWithError()
    }

    private func makeModel() -> LibraryViewModel {
        LibraryViewModel(project: projects.projects[0], projects: projects)
    }

    private func makeIndexedModel() async throws -> LibraryViewModel {
        let store = try PhotoIndexStore(databaseAt: dbURL)
        try await IndexedPhotoFixture.populateMixedLibrary(on: store)
        let model = makeModel()
        await model.attachPhotoIndexForTesting(store)
        return model
    }

    private func awaitPaths(_ model: LibraryViewModel, _ expected: [String]) async {
        for _ in 0 ..< 50 {
            if model.visiblePaths == expected { return }
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    // MARK: Edit

    func testEditAnnotationAndProjectName() {
        let model = makeModel()
        var note = model.annotation(for: "/photos/a.jpg")
        note.place = "Kyoto"
        note.items = ["temple"]
        model.updateAnnotation(note)

        let stored = model.annotation(for: "/photos/a.jpg")
        XCTAssertEqual(stored.place, "Kyoto")
        XCTAssertEqual(stored.items, ["temple"])

        note.place = "Osaka"
        model.updateAnnotation(note)
        XCTAssertEqual(model.project.annotations.filter { $0.path == "/photos/a.jpg" }.count, 1)
        XCTAssertEqual(model.annotation(for: "/photos/a.jpg").place, "Osaka")

        projects.rename(projectId: model.project.id, to: "Edited")
        XCTAssertEqual(projects.projects.first?.name, "Edited")
    }

    func testCreateAlbumRejectsBlankName() {
        let model = makeModel()
        XCTAssertNil(model.createManualAlbum(name: "   "))
        XCTAssertTrue(model.project.albums.isEmpty)
    }

    // MARK: Add

    func testAddAlbumAndPhotos() {
        let model = makeModel()
        let albumId = model.createManualAlbum(name: "Trips")
        XCTAssertNotNil(albumId)
        model.addPathsToAlbum(albumId: albumId!, paths: ["/a.jpg", "/b.jpg", "/a.jpg"])
        let album = model.project.albums.first { $0.id == albumId }
        XCTAssertEqual(album?.memberPaths, ["/a.jpg", "/b.jpg"])
    }

    func testAddFolderThenRemoveIt() async throws {
        let folder = tempRoot.appendingPathComponent("Camera", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let removedPhoto = folder.appendingPathComponent("kept-in-index.jpg").path
        let otherPhoto = tempRoot.appendingPathComponent("other.jpg").path

        let store = try PhotoIndexStore(databaseAt: dbURL)
        try await store.upsertCatalogRow(path: removedPhoto, sourceId: "src-1", modTime: Date(), fileSize: 10)
        try await store.upsertCatalogRow(path: otherPhoto, sourceId: "other", modTime: Date(), fileSize: 10)

        let model = makeModel()
        await model.attachPhotoIndexForTesting(store)
        model.registerSource(displayPath: folder.path, bookmarkData: Data("bookmark".utf8), sourceID: "src-1")
        projects.update(model.project)
        let albumId = model.createManualAlbum(name: "From folder")!
        model.addToAlbum(albumId: albumId, path: removedPhoto)
        model.addToDeleteBin(paths: [removedPhoto])

        XCTAssertTrue(model.visiblePaths.contains(removedPhoto))

        model.removeSource(id: "src-1")
        for _ in 0 ..< 40 {
            if !model.visiblePaths.contains(removedPhoto), model.project.sourceBookmarks.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(40))
        }

        XCTAssertTrue(model.project.sourceBookmarks.isEmpty)
        XCTAssertFalse(model.project.sources.contains(folder.path))
        XCTAssertFalse(model.visiblePaths.contains(removedPhoto))
        XCTAssertTrue(model.visiblePaths.contains(otherPhoto))
        XCTAssertFalse(model.project.albums[0].memberPaths.contains(removedPhoto))
        XCTAssertFalse(model.project.deleteBinPaths.contains(removedPhoto))
        let remaining = try await store.allPaths()
        XCTAssertEqual(remaining, [otherPhoto])
    }

    func testRemoveLegacyFolderPath() {
        let model = makeModel()
        let folder = tempRoot.appendingPathComponent("Legacy", isDirectory: true).path
        model.project.sources = [folder]
        projects.update(model.project)
        model.removeLegacySource(path: folder)
        XCTAssertFalse(model.project.sources.contains(folder))
    }

    // MARK: Delete

    func testDeleteAlbumAndKeepFavorites() {
        let model = makeModel()
        _ = model.toggleFavorite(path: "/keep.jpg")
        let albumId = model.createManualAlbum(name: "Toss")!
        model.deleteAlbum(id: albumId)
        model.deleteAlbum(id: AlbumConstants.favoritesAlbumId)
        XCTAssertEqual(model.project.albums.map(\.id), [AlbumConstants.favoritesAlbumId])
    }

    func testDeleteBinMovesFilesAndDropsAlbumMembership() async throws {
        let photo = tempRoot.appendingPathComponent("gone.jpg")
        try Data("jpeg".utf8).write(to: photo)
        let model = makeModel()
        let albumId = model.createManualAlbum(name: "Hold")!
        model.addToAlbum(albumId: albumId, path: photo.path)
        model.addToDeleteBin(paths: [photo.path, "/missing.jpg"])

        let failed = await model.deleteBinFromSource()
        XCTAssertEqual(failed, ["/missing.jpg"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: photo.path))
        XCTAssertEqual(model.project.deleteBinPaths, ["/missing.jpg"])
        XCTAssertFalse(model.project.albums[0].memberPaths.contains(photo.path))
    }

    // MARK: Sort

    func testSortNewestOldestAndName() async throws {
        let model = try await makeIndexedModel()
        let newest = [
            IndexedPhotoFixture.pathBeach,
            IndexedPhotoFixture.pathScreenshot,
            IndexedPhotoFixture.pathOther,
            IndexedPhotoFixture.path2020,
        ]
        let oldest = Array(newest.reversed())
        let byName = [
            IndexedPhotoFixture.path2020,
            IndexedPhotoFixture.pathScreenshot,
            IndexedPhotoFixture.pathBeach,
            IndexedPhotoFixture.pathOther,
        ]

        await awaitPaths(model, newest)
        XCTAssertEqual(model.visiblePaths, newest)

        model.setPhotoSort(.dateOldest)
        await awaitPaths(model, oldest)
        XCTAssertEqual(model.visiblePaths, oldest)

        model.setPhotoSort(.fileName)
        await awaitPaths(model, byName)
        XCTAssertEqual(model.visiblePaths, byName)
    }

    // MARK: Fullscreen navigate

    func testFullscreenStepAndPosition() {
        let paths = ["/a.jpg", "/b.jpg", "/c.jpg"]
        XCTAssertEqual(ViewerNavigation.positionLabel(path: "/b.jpg", paths: paths), "2 of 3")
        XCTAssertEqual(ViewerNavigation.steppedPath(from: "/b.jpg", in: paths, by: 1), "/c.jpg")
        XCTAssertEqual(ViewerNavigation.steppedPath(from: "/b.jpg", in: paths, by: -1), "/a.jpg")
        XCTAssertNil(ViewerNavigation.steppedPath(from: "/a.jpg", in: paths, by: -1))
        XCTAssertNil(ViewerNavigation.steppedPath(from: "/c.jpg", in: paths, by: 1))
        XCTAssertNil(ViewerNavigation.steppedPath(from: "/missing.jpg", in: paths, by: 1))
    }

    // MARK: Drag and drop

    func testDragPayloadUsesSelectionOnlyWhenDraggingASelectedPhoto() {
        let model = makeModel()
        model.selectGridPhoto(path: "/a.jpg")
        model.selectGridPhoto(path: "/c.jpg")

        XCTAssertEqual(
            PhotoAlbumDragDrop.payload(for: "/a.jpg", model: model).paths,
            ["/a.jpg", "/c.jpg"]
        )
        XCTAssertEqual(
            PhotoAlbumDragDrop.payload(for: "/b.jpg", model: model).paths,
            ["/b.jpg"]
        )
    }

    func testDropOntoManualAlbumAddsPathsAndSmartAlbumIgnoresThem() {
        let model = makeModel()
        let manual = model.createManualAlbum(name: "Manual")!
        model.createSmartAlbum(name: "Smart", rules: SmartAlbumRules(conditions: [
            SmartAlbumRule(type: .screenshot, value: "1"),
        ]))
        let smart = model.project.albums.first { $0.kind == .smart }!

        let transfer = PhotoPathsTransfer(paths: ["/drop.jpg"])
        model.addPathsToAlbum(albumId: manual, paths: transfer.paths)
        model.addPathsToAlbum(albumId: smart.id, paths: transfer.paths)

        XCTAssertEqual(model.project.albums.first { $0.id == manual }?.memberPaths, ["/drop.jpg"])
        XCTAssertTrue(model.project.albums.first { $0.id == smart.id }?.memberPaths.isEmpty == true)
    }

    // MARK: Navigate and select

    func testNavigateAlbumsAndSelectPhotos() async throws {
        let model = try await makeIndexedModel()
        let albumId = model.createManualAlbum(name: "Picks")!
        model.selectAlbum(id: albumId)
        XCTAssertEqual(model.selectedAlbumId, albumId)
        XCTAssertEqual(model.groupBy, .albums)

        model.selectAlbum(id: albumId)
        XCTAssertNil(model.selectedAlbumId)
        XCTAssertEqual(model.groupBy, .none)

        model.visiblePaths = [IndexedPhotoFixture.pathBeach, IndexedPhotoFixture.path2020]
        model.toggleGridSelection(path: IndexedPhotoFixture.pathBeach)
        model.selectAllVisiblePhotos()
        XCTAssertEqual(model.selectedPaths, Set(model.visiblePaths))
        XCTAssertTrue(model.isSelectingPhotos)

        model.toggleGridSelection(path: IndexedPhotoFixture.pathBeach)
        XCTAssertFalse(model.selectedPaths.contains(IndexedPhotoFixture.pathBeach))
        model.clearGridSelection()
        XCTAssertTrue(model.selectedPaths.isEmpty)
        XCTAssertFalse(model.isSelectingPhotos)
    }

    func testDragSelectAddsWithoutTogglingOff() {
        let model = makeModel()
        model.selectGridPhoto(path: "/a.jpg")
        model.selectGridPhoto(path: "/a.jpg")
        model.selectGridPhoto(path: "/b.jpg")
        XCTAssertEqual(model.selectedPaths, ["/a.jpg", "/b.jpg"])
    }

    // MARK: Export

    func testExportCopiesAlbumAndSkipsMissingFiles() async throws {
        let first = tempRoot.appendingPathComponent("one.jpg")
        let second = tempRoot.appendingPathComponent("two.jpg")
        try Data("one".utf8).write(to: first)
        try Data("two".utf8).write(to: second)
        let destination = tempRoot.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let copied = try await AlbumExportService.export(
            albumName: "Trips",
            photoPaths: [first.path, "/no/such.jpg", second.path],
            destinationParent: destination,
            onProgress: { _, _ in }
        )
        XCTAssertEqual(copied, 2)
        let exported = destination.appendingPathComponent("Trips", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.appendingPathComponent("one.jpg").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.appendingPathComponent("two.jpg").path))

        let again = try await AlbumExportService.export(
            albumName: "Trips",
            photoPaths: [first.path],
            destinationParent: destination,
            onProgress: { _, _ in }
        )
        XCTAssertEqual(again, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.appendingPathComponent("one-2.jpg").path))
    }
}
