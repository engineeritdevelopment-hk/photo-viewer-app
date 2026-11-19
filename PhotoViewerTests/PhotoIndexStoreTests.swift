import XCTest
@testable import Photo_Viewer

final class PhotoIndexStoreTests: XCTestCase {
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

    func testUpsertAndRemoveSource() async throws {
        let store = try PhotoIndexStore(databaseAt: dbURL)
        let mod = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.upsertCatalogRow(path: "/Volumes/Disk/a.jpg", sourceId: "src-a", modTime: mod, fileSize: 1024)
        try await store.upsertCatalogRow(path: "/Volumes/Disk/b.jpg", sourceId: "src-b", modTime: mod, fileSize: 2048)

        var paths = try await store.allPaths()
        XCTAssertEqual(Set(paths), ["/Volumes/Disk/a.jpg", "/Volumes/Disk/b.jpg"])

        try await store.removeSource("src-a")
        paths = try await store.allPaths()
        XCTAssertEqual(paths, ["/Volumes/Disk/b.jpg"])
    }

    func testRemovePathsWithPrefix() async throws {
        let store = try PhotoIndexStore(databaseAt: dbURL)
        let mod = Date()
        try await store.upsertCatalogRow(path: "/Volumes/Seagate/roll/1.jpg", sourceId: "s", modTime: mod, fileSize: 1)
        try await store.upsertCatalogRow(path: "/Volumes/Seagate/roll/nested/2.jpg", sourceId: "s", modTime: mod, fileSize: 1)
        try await store.upsertCatalogRow(path: "/Volumes/Other/x.jpg", sourceId: "s", modTime: mod, fileSize: 1)

        try await store.removePaths(withPathPrefix: "/Volumes/Seagate/roll")
        let paths = try await store.allPaths()
        XCTAssertEqual(paths, ["/Volumes/Other/x.jpg"])
    }

    func testSequentialReopenSameDatabaseFile() async throws {
        do {
            let store = try PhotoIndexStore(databaseAt: dbURL)
            try await store.upsertCatalogRow(path: "/tmp/p.jpg", sourceId: "s", modTime: Date(), fileSize: 1)
        }
        let reopened = try PhotoIndexStore(databaseAt: dbURL)
        let paths = try await reopened.allPaths()
        XCTAssertEqual(paths, ["/tmp/p.jpg"])
    }

    func testConcurrentWritesOnSingleConnection() async throws {
        let store = try PhotoIndexStore(databaseAt: dbURL)
        await withTaskGroup(of: Void.self) { group in
            for index in 0 ..< 80 {
                group.addTask {
                    try? await store.upsertCatalogRow(
                        path: "/data/photo-\(index).jpg",
                        sourceId: "source-1",
                        modTime: Date(),
                        fileSize: Int64(index)
                    )
                }
            }
        }
        let paths = try await store.allPaths()
        XCTAssertEqual(paths.count, 80)
    }
}