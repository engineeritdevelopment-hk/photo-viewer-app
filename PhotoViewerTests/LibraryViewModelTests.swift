import XCTest
@testable import Photo_Viewer

@MainActor
final class LibraryViewModelTests: XCTestCase {
    private var tempRoot: URL!
    private var projects: ProjectsViewModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = try TempDirectory.create()
        ApplicationPaths.useIsolatedSupportRoot(tempRoot)
        projects = ProjectsViewModel()
        let created = projects.create(name: "Test Library")!
        projects.projects = [created]
    }

    override func tearDownWithError() throws {
        ApplicationPaths.resetSupportRootOverride()
        TempDirectory.remove(tempRoot)
        tempRoot = nil
        projects = nil
        try super.tearDownWithError()
    }

    func testToggleFavoriteCreatesFavoritesAlbum() {
        let project = projects.projects[0]
        let model = LibraryViewModel(project: project, projects: projects)

        XCTAssertFalse(model.isFavorite(path: "/any/photo.jpg"))
        XCTAssertTrue(model.toggleFavorite(path: "/any/photo.jpg"))
        XCTAssertTrue(model.isFavorite(path: "/any/photo.jpg"))
        XCTAssertFalse(model.toggleFavorite(path: "/any/photo.jpg"))

        let favorites = model.project.albums.first { $0.id == AlbumConstants.favoritesAlbumId }
        XCTAssertNotNil(favorites)
        XCTAssertEqual(favorites?.kind, .favorites)
        XCTAssertEqual(favorites?.memberPaths, [])
    }

    func testActiveFilterDescriptionsIncludeAlbumAndPerson() {
        var project = projects.projects[0]
        project.albums = [Album(id: "a1", name: "Trips", kind: .manual)]
        project.personGroups = [PersonGroup(id: "p1", displayName: "Sam", memberPhotoPaths: [])]
        projects.update(project)

        let model = LibraryViewModel(project: project, projects: projects)
        model.groupBy = .albums
        model.selectedAlbumId = "a1"
        model.selectedSidebarKey = "album:a1"
        XCTAssertTrue(model.viewFilterSummary.contains("Album: Trips"))

        model.resetAllViewFilters()
        XCTAssertFalse(model.isViewFiltered)

        model.selectedSidebarKey = "person:p1"
        XCTAssertTrue(model.viewFilterSummary.contains("Person: Sam"))
    }

    func testDeleteAlbumClearsSelection() async {
        let project = projects.projects[0]
        var mutable = project
        let album = Album(id: "album-1", name: "Trips", kind: .manual, memberPaths: ["/a.jpg"])
        mutable.albums = [album]
        projects.update(mutable)

        let model = LibraryViewModel(project: projects.projects[0], projects: projects)
        model.groupBy = .albums
        model.selectedAlbumId = "album-1"

        model.deleteAlbum(id: "album-1")
        XCTAssertNil(model.selectedAlbumId)
        XCTAssertEqual(model.groupBy, .none)
        XCTAssertTrue(model.project.albums.isEmpty)
    }

    func testRenamePersonPersists() {
        let project = projects.projects[0]
        var mutable = project
        mutable.personGroups = [
            PersonGroup(id: "p1", displayName: nil, memberPhotoPaths: ["/a.jpg"]),
        ]
        projects.update(mutable)
        let model = LibraryViewModel(project: projects.projects[0], projects: projects)
        model.renamePerson(id: "p1", name: "Sam")
        XCTAssertEqual(model.project.personGroups[0].displayName, "Sam")
    }

    func testMergeMultiplePersonGroups() async {
        let project = projects.projects[0]
        var mutable = project
        mutable.personGroups = [
            PersonGroup(id: "p1", displayName: "Alex", memberPhotoPaths: ["/a.jpg"]),
            PersonGroup(id: "p2", displayName: nil, memberPhotoPaths: ["/b.jpg"]),
            PersonGroup(id: "p3", displayName: nil, memberPhotoPaths: ["/c.jpg", "/d.jpg"]),
        ]
        projects.update(mutable)
        let model = LibraryViewModel(project: projects.projects[0], projects: projects)
        model.peopleMergeSelection = ["p1", "p2", "p3"]
        model.mergeSelectedPeople()
        for _ in 0 ..< 40 {
            try? await Task.sleep(for: .milliseconds(50))
            if model.project.personGroups.count == 1 { break }
        }
        XCTAssertEqual(model.project.personGroups.count, 1)
        XCTAssertEqual(Set(model.project.personGroups[0].memberPhotoPaths), ["/a.jpg", "/b.jpg", "/c.jpg", "/d.jpg"])
        XCTAssertEqual(model.project.personGroups[0].id, "p1")
        XCTAssertEqual(model.project.personGroups[0].displayName, "Alex")
    }

    func testMergePersonGroups() async {
        let project = projects.projects[0]
        var mutable = project
        mutable.personGroups = [
            PersonGroup(id: "p1", displayName: "Alex", memberPhotoPaths: ["/a.jpg"], thumbnailPath: "/a.jpg"),
            PersonGroup(id: "p2", displayName: nil, memberPhotoPaths: ["/b.jpg", "/c.jpg"], thumbnailPath: "/b.jpg"),
        ]
        projects.update(mutable)
        let model = LibraryViewModel(project: projects.projects[0], projects: projects)

        await model.mergePersonGroups(primaryId: "p1", secondaryId: "p2")

        XCTAssertEqual(model.project.personGroups.count, 1)
        let merged = model.project.personGroups[0]
        XCTAssertEqual(merged.id, "p1")
        XCTAssertEqual(Set(merged.memberPhotoPaths), ["/a.jpg", "/b.jpg", "/c.jpg"])
    }

    func testDeleteBinStagingAndRemoval() {
        let project = projects.projects[0]
        let model = LibraryViewModel(project: project, projects: projects)

        model.addToDeleteBin(paths: ["/a.jpg", "/b.jpg"])
        XCTAssertEqual(model.deleteBinCount, 2)
        XCTAssertTrue(model.project.deleteBinPaths.contains("/a.jpg"))

        model.removeFromDeleteBin(paths: ["/a.jpg"])
        XCTAssertEqual(model.deleteBinCount, 1)

        model.emptyDeleteBin()
        XCTAssertEqual(model.deleteBinCount, 0)
    }

    func testPhotoFilterExcludesByExtensionAndName() {
        var filter = PhotoFilter()
        filter.excludedExtensions = ["png"]
        filter.excludedNameFragments = ["screenshot"]

        XCTAssertTrue(filter.allows(path: "/tmp/photo.jpg"))
        XCTAssertFalse(filter.allows(path: "/tmp/shot.PNG"))
        XCTAssertFalse(filter.allows(path: "/tmp/my_screenshot.jpg"))
    }
}