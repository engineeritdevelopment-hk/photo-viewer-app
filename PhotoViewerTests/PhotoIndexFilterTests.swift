import XCTest
@testable import Photo_Viewer

final class PhotoIndexFilterTests: XCTestCase {
    private var tempRoot: URL!
    private var dbURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = try TempDirectory.create()
        dbURL = tempRoot.appendingPathComponent("catalog.sqlite")
    }

    override func tearDownWithError() throws {
        TempDirectory.remove(tempRoot)
        tempRoot = nil
        dbURL = nil
        try super.tearDownWithError()
    }

    func testPathsForYear() async throws {
        let store = try PhotoIndexStore(databaseAt: dbURL)
        try await IndexedPhotoFixture.populateMixedLibrary(on: store)

        let year2020 = try await store.pathsForYear(2020)
        XCTAssertEqual(Set(year2020), [IndexedPhotoFixture.path2020])

        let year2024 = try await store.pathsForYear(2024)
        XCTAssertEqual(Set(year2024), [IndexedPhotoFixture.pathScreenshot, IndexedPhotoFixture.pathBeach])
    }

    func testIndexedDateBounds() async throws {
        let store = try PhotoIndexStore(databaseAt: dbURL)
        try await IndexedPhotoFixture.populateMixedLibrary(on: store)

        let bounds = try await store.indexedDateBounds()
        XCTAssertNotNil(bounds)
        XCTAssertEqual(bounds?.earliest, IndexedPhotoFixture.date(2020, 6, 15))
        XCTAssertEqual(bounds?.latest, IndexedPhotoFixture.date(2024, 8, 1))
    }

    func testFetchPathsDateRange() async throws {
        let store = try PhotoIndexStore(databaseAt: dbURL)
        try await IndexedPhotoFixture.populateMixedLibrary(on: store)

        var filter = MetadataFilter()
        filter.takenAfter = IndexedPhotoFixture.date(2024, 1, 1)
        filter.takenBefore = IndexedPhotoFixture.endOfDay(IndexedPhotoFixture.date(2024, 12, 31))

        let paths = try await store.fetchPaths(
            limit: 500,
            offset: 0,
            metadata: filter,
            projectFilter: PhotoFilter()
        )
        XCTAssertEqual(Set(paths), [IndexedPhotoFixture.pathScreenshot, IndexedPhotoFixture.pathBeach])
    }

    func testSourcePathPrefixAndScreenshotRules() async throws {
        let store = try PhotoIndexStore(databaseAt: dbURL)
        try await IndexedPhotoFixture.populateMixedLibrary(on: store)

        let diskA = try await store.pathsForSmartRules(SmartAlbumRules(conditions: [
            .init(type: .sourcePathPrefix, value: IndexedPhotoFixture.diskAPrefix),
        ]))
        XCTAssertEqual(Set(diskA), [IndexedPhotoFixture.path2020, IndexedPhotoFixture.pathScreenshot])

        let shots = try await store.pathsForSmartRules(SmartAlbumRules(conditions: [
            .init(type: .screenshot, value: "1"),
        ]))
        XCTAssertEqual(shots, [IndexedPhotoFixture.pathScreenshot])
    }

    func testPlaceAndCameraGrouping() async throws {
        let store = try PhotoIndexStore(databaseAt: dbURL)
        try await IndexedPhotoFixture.populateMixedLibrary(on: store)

        let places = try await store.groupByPlace()
        XCTAssertTrue(places.contains { $0.name == "Paris, France" && $0.count == 1 })

        let paris = try await store.pathsForSmartRules(SmartAlbumRules(conditions: [
            .init(type: .placeContains, value: "Paris"),
        ]))
        XCTAssertEqual(paris, [IndexedPhotoFixture.path2020])

        let sony = try await store.pathsForSmartRules(SmartAlbumRules(conditions: [
            .init(type: .cameraModelContains, value: "ILCE-7M3"),
        ]))
        XCTAssertEqual(sony, [IndexedPhotoFixture.pathBeach])
    }

    func testGroupByYearBuckets() async throws {
        let store = try PhotoIndexStore(databaseAt: dbURL)
        try await IndexedPhotoFixture.populateMixedLibrary(on: store)

        let years = try await store.groupByYear()
        let map = Dictionary(uniqueKeysWithValues: years.map { ($0.year, $0.count) })
        XCTAssertEqual(map["2020"], 1)
        XCTAssertEqual(map["2022"], 1)
        XCTAssertEqual(map["2024"], 2)
    }
}