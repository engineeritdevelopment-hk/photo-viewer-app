import XCTest
@testable import Photo_Viewer

final class PhotoCatalogScannerTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = try TempDirectory.create()
    }

    override func tearDownWithError() throws {
        TempDirectory.remove(tempRoot)
        tempRoot = nil
        try super.tearDownWithError()
    }

    func testScanIndexesAllowedImagesAndSkipsOthers() async throws {
        FileManager.default.createFile(atPath: tempRoot.appendingPathComponent("keep.jpg").path, contents: Data(count: 4), attributes: nil)
        FileManager.default.createFile(atPath: tempRoot.appendingPathComponent("skip.txt").path, contents: Data(count: 4), attributes: nil)
        FileManager.default.createFile(atPath: tempRoot.appendingPathComponent(".hidden.jpg").path, contents: Data(count: 4), attributes: nil)

        let dbURL = tempRoot.appendingPathComponent("index.sqlite")
        let store = try PhotoIndexStore(databaseAt: dbURL)
        let scanner = PhotoCatalogScanner()
        let stream = await scanner.scan(
            sources: [("src", tempRoot)],
            filter: PhotoFilter(),
            index: store,
            batchSize: 4
        )

        var scanned = 0
        for await progress in stream {
            scanned = progress.scanned
        }

        XCTAssertEqual(scanned, 1)
        let paths = try await store.allPaths()
        XCTAssertEqual(paths.count, 1)
        XCTAssertTrue(paths[0].hasSuffix("keep.jpg"))
    }
}