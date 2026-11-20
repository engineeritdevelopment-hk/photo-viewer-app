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

    func testScanningOneFolderDoesNotRestorePhotosFromAnother() async throws {
        let removed = tempRoot.appendingPathComponent("Camera/old.jpg")
        try FileManager.default.createDirectory(
            at: removed.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let keptFolder = tempRoot.appendingPathComponent("Other", isDirectory: true)
        try FileManager.default.createDirectory(at: keptFolder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: keptFolder.appendingPathComponent("keep.jpg").path, contents: Data(count: 2))

        let store = try PhotoIndexStore(databaseAt: tempRoot.appendingPathComponent("index.sqlite"))
        try await store.upsertCatalogRow(path: removed.path, sourceId: "gone", modTime: Date(), fileSize: 1)
        try await store.removePaths(withPathPrefix: removed.deletingLastPathComponent().path)

        let stream = await PhotoCatalogScanner().scan(
            sources: [("other", keptFolder)],
            filter: PhotoFilter(),
            index: store
        )
        for await _ in stream {}

        let paths = try await store.allPaths()
        XCTAssertEqual(paths, [keptFolder.appendingPathComponent("keep.jpg").path])
    }

    func testCancelledScanStopsBeforeWritingTheRestOfTheFolder() async throws {
        let folder = tempRoot.appendingPathComponent("Camera", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 0 ..< 40 {
            FileManager.default.createFile(
                atPath: folder.appendingPathComponent("img-\(index).jpg").path,
                contents: Data([0xFF, 0xD8])
            )
        }

        let store = try PhotoIndexStore(databaseAt: tempRoot.appendingPathComponent("cancel.sqlite"))
        let hold = Task { await store.holdUntilCancelledForTesting() }
        try await Task.sleep(for: .milliseconds(50))

        let scanner = PhotoCatalogScanner()
        let stream = await scanner.scan(sources: [("src", folder)], filter: PhotoFilter(), index: store, batchSize: 1)
        let consumer = Task {
            for await _ in stream {}
        }

        try await Task.sleep(for: .milliseconds(50))
        let stop = Task { await scanner.cancelAndWait() }
        try await Task.sleep(for: .milliseconds(50))
        hold.cancel()
        await hold.value
        await stop.value
        consumer.cancel()

        let stoppedAt = try await store.allPaths().count
        XCTAssertLessThan(stoppedAt, 40)
        try await Task.sleep(for: .milliseconds(200))
        let later = try await store.allPaths().count
        XCTAssertEqual(later, stoppedAt)
    }
}