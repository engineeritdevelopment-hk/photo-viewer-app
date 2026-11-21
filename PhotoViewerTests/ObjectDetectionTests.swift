import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Photo_Viewer

final class ObjectDetectionTests: XCTestCase {
    private var tempRoot: URL!
    private var dbURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = try TempDirectory.create()
        dbURL = tempRoot.appendingPathComponent("objects.sqlite")
    }

    override func tearDownWithError() throws {
        TempDirectory.remove(tempRoot)
        tempRoot = nil
        dbURL = nil
        try super.tearDownWithError()
    }

    func testBundledDetectorListsOpenImagesClasses() throws {
        XCTAssertTrue(ObjectDetector.isAvailable())
        let url = try XCTUnwrap(Bundle.main.url(forResource: "ObjectClasses", withExtension: "json"))
        let names = try JSONDecoder().decode([String].self, from: Data(contentsOf: url))
        XCTAssertEqual(names.count, 601)
        XCTAssertEqual(names.first, "Accordion")
        XCTAssertEqual(names.last, "Zucchini")
        XCTAssertFalse(names.contains { $0.allSatisfy(\.isNumber) })
        XCTAssertEqual(Set(names).count, names.count)
    }

    func testDetectorFindsTheBusAndIgnoresABlankPhoto() throws {
        let bus = try copyFixture("bus", extension: "jpg")
        let blank = tempRoot.appendingPathComponent("blank.jpg")
        try writeSolidJPEG(to: blank, red: 0.12, green: 0.35, blue: 0.62)

        let names = Set(ObjectDetector.labels(at: bus))
        XCTAssertTrue(names.contains("Bus"), "Detected \(names.sorted())")
        XCTAssertTrue(names.contains("Man"))
        XCTAssertTrue(names.isSubset(of: classNames()))
        XCTAssertFalse(names.contains { $0.allSatisfy(\.isNumber) })

        XCTAssertEqual(ObjectDetector.labels(at: blank), [])
    }

    func testAnalysisPassStoresDetectedNames() async throws {
        let bus = try copyFixture("bus", extension: "jpg")
        let store = try PhotoIndexStore(databaseAt: dbURL)
        try await store.upsertCatalogRow(path: bus.path, sourceId: "src", modTime: Date(), fileSize: 1)

        let pipeline = AnalysisPipeline()
        await pipeline.process(
            paths: [bus.path],
            semanticOn: false,
            smartTitlesOn: false,
            objectsOn: true,
            facesOn: false,
            index: store,
            placeService: PlaceLabelService(),
            onMetadata: { _, _ in },
            onAnalysis: { _, _ in },
            onGeocode: { _, _ in },
            onFaces: { _, _ in },
            onFacePhaseStarted: {},
            personGroups: { [] },
            onPersonGroups: { _ in },
            onSmartTitle: { _, _ in }
        )

        let record = try await store.record(for: bus.path)
        XCTAssertTrue(record?.objectLabels.contains("Bus") == true)
    }

    func testIndexSearchKeepsDogDistinctFromHotDog() async throws {
        let store = try PhotoIndexStore(databaseAt: dbURL)
        let mod = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.upsertCatalogRow(path: "/photos/street.jpg", sourceId: "s", modTime: mod, fileSize: 1)
        try await store.upsertCatalogRow(path: "/photos/lunch.jpg", sourceId: "s", modTime: mod, fileSize: 1)
        try await store.upsertCatalogRow(path: "/photos/plain.jpg", sourceId: "s", modTime: mod, fileSize: 1)
        try await store.updateObjectLabels(path: "/photos/street.jpg", names: ["Bus", "Dog"])
        try await store.updateObjectLabels(path: "/photos/lunch.jpg", names: ["Hot dog", "bus"])
        try await store.updateObjectLabels(path: "/photos/plain.jpg", names: [])

        let dog = try await store.pathsMatchingObject(query: "Dog", exact: true)
        XCTAssertEqual(dog, ["/photos/street.jpg"])
        let either = try await store.pathsMatchingObject(query: "dog", exact: false)
        XCTAssertEqual(Set(either), ["/photos/street.jpg", "/photos/lunch.jpg"])
        let blankQuery = try await store.pathsMatchingObject(query: "  ", exact: false)
        XCTAssertEqual(blankQuery, [])

        let groups = try await store.groupByObject()
        XCTAssertEqual(groups.first?.name, "Bus")
        XCTAssertEqual(groups.first?.count, 2)
        XCTAssertEqual(groups.map(\.name), ["Bus", "Dog", "Hot dog"])

        let replaced = try await store.record(for: "/photos/street.jpg")
        XCTAssertEqual(replaced?.objectLabels, ["Bus", "Dog"])
        try await store.updateObjectLabels(path: "/photos/street.jpg", names: ["Jeans"])
        let jeans = try await store.record(for: "/photos/street.jpg")
        XCTAssertEqual(jeans?.objectLabels, ["Jeans"])

        try await store.clearAnalysis()
        let cleared = try await store.record(for: "/photos/lunch.jpg")
        XCTAssertEqual(cleared?.objectLabels, [])
        let remaining = try await store.groupByObject()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testStoredLabelsSurviveReopeningTheIndex() async throws {
        let path = "/photos/street.jpg"
        do {
            let store = try PhotoIndexStore(databaseAt: dbURL)
            try await store.upsertCatalogRow(path: path, sourceId: "s", modTime: Date(), fileSize: 1)
            try await store.updateObjectLabels(path: path, names: ["Wine glass"])
        }
        let reopened = try PhotoIndexStore(databaseAt: dbURL)
        let record = try await reopened.record(for: path)
        XCTAssertEqual(record?.objectLabels, ["Wine glass"])
    }

    private func classNames() -> Set<String> {
        guard let url = Bundle.main.url(forResource: "ObjectClasses", withExtension: "json"),
              let names = try? JSONDecoder().decode([String].self, from: Data(contentsOf: url)) else {
            return []
        }
        return Set(names)
    }

    private func copyFixture(_ name: String, extension ext: String) throws -> URL {
        let bundled = try XCTUnwrap(
            Bundle(for: ObjectDetectionTests.self).url(forResource: name, withExtension: ext),
            "Missing \(name).\(ext) in the test bundle"
        )
        let destination = tempRoot.appendingPathComponent("\(name).\(ext)")
        try Data(contentsOf: bundled).write(to: destination)
        return destination
    }

    private func writeSolidJPEG(to url: URL, red: CGFloat, green: CGFloat, blue: CGFloat) throws {
        let context = CGContext(
            data: nil,
            width: 64,
            height: 64,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
        context?.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let filled = try XCTUnwrap(context?.makeImage())
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            XCTFail("Could not create JPEG")
            return
        }
        CGImageDestinationAddImage(destination, filled, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}

@MainActor
final class ObjectSearchTests: XCTestCase {
    private var tempRoot: URL!
    private var projects: ProjectsViewModel!
    private var dbURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = try TempDirectory.create()
        ApplicationPaths.useIsolatedSupportRoot(tempRoot)
        projects = ProjectsViewModel()
        let created = projects.create(name: "Object Search")!
        projects.projects = [created]
        dbURL = tempRoot.appendingPathComponent("search.sqlite")
    }

    override func tearDownWithError() throws {
        ApplicationPaths.resetSupportRootOverride()
        TempDirectory.remove(tempRoot)
        tempRoot = nil
        projects = nil
        dbURL = nil
        try super.tearDownWithError()
    }

    func testObjectsToggleIsEnoughToRun() async throws {
        let (model, _) = try await makeModel()
        XCTAssertFalse(model.canStartAnalysis)
        model.objectDetectionOn = true
        XCTAssertTrue(model.canStartAnalysis)
        model.activity.isAnalyzing = true
        XCTAssertFalse(model.canStartAnalysis)
    }

    func testObjectFilterAndTypedSearchNarrowTheGrid() async throws {
        let (model, _) = try await makeModel()
        XCTAssertEqual(model.sidebarObjects.map(\.name), ["Bus", "Dog", "Hot dog", "Jeans", "Man"])
        XCTAssertEqual(model.sidebarObjects.first?.count, 2)

        model.selectSidebarFilter("object:Dog")
        model.applySidebarKey("object:Dog")
        await awaitGridSettle(model)
        XCTAssertEqual(model.visiblePaths, [IndexedPhotoFixture.pathScreenshot])
        XCTAssertEqual(model.viewFilterSummary, "Object: Dog")

        model.selectSidebarFilter(nil)
        model.objectSearchText = "dog"
        model.scheduleReloadVisiblePaths()
        await awaitGridSettle(model)
        XCTAssertEqual(
            Set(model.visiblePaths),
            [IndexedPhotoFixture.pathScreenshot, IndexedPhotoFixture.pathBeach]
        )
        XCTAssertEqual(model.viewFilterSummary, "Objects matching “dog”")

        model.objectSearchText = "bus"
        model.selectSidebarFilter("date:2020")
        model.applySidebarKey("date:2020")
        await awaitGridSettle(model)
        XCTAssertEqual(model.visiblePaths, [IndexedPhotoFixture.path2020])
        XCTAssertTrue(model.viewFilterSummary.contains("Year: 2020"))
        XCTAssertTrue(model.viewFilterSummary.contains("Objects matching “bus”"))

        model.objectSearchText = "zzz"
        XCTAssertTrue(model.filteredSidebarObjects.isEmpty)
        model.objectSearchText = "hot"
        XCTAssertEqual(model.filteredSidebarObjects.map(\.name), ["Hot dog"])

        model.resetAllViewFilters()
        await awaitGridSettle(model)
        XCTAssertEqual(model.objectSearchText, "")
        XCTAssertNil(model.selectedSidebarKey)
        XCTAssertEqual(model.visiblePaths.count, 4)
    }

    func testSidebarShowsFortyObjectsUntilASearch() {
        let model = LibraryViewModel(project: projects.projects[0], projects: projects)
        model.sidebarObjects = (0..<45).map { index in
            (name: String(format: "Item %02d", index), count: 45 - index)
        }
        XCTAssertEqual(model.filteredSidebarObjects.count, 40)
        XCTAssertEqual(model.filteredSidebarObjects.first?.name, "Item 00")
        model.objectSearchText = "Item 44"
        XCTAssertEqual(model.filteredSidebarObjects.map(\.name), ["Item 44"])
    }

    func testPhotoCategoriesIncludeObjectNamesOnce() async throws {
        let (model, store) = try await makeModel()
        try await store.updateAnalysis(
            path: IndexedPhotoFixture.path2020,
            sceneLabels: [],
            ocrSnippet: nil,
            semanticCategory: "Bus",
            source: .onDeviceAI
        )
        let categories = await model.analysisCategories(for: IndexedPhotoFixture.path2020)
        XCTAssertEqual(categories.filter { $0 == "Bus" }.count, 1)
        XCTAssertTrue(categories.contains("Man"))
    }

    func testClearAnalysisDropsObjectNamesAndTheObjectFilter() async throws {
        let (model, store) = try await makeModel()
        model.objectDetectionOn = true
        model.objectSearchText = "bus"
        model.selectedSidebarKey = "object:Bus"
        model.clearAnalysisData()
        XCTAssertEqual(model.objectSearchText, "")
        XCTAssertNil(model.selectedSidebarKey)

        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(25))
            if model.sidebarObjects.isEmpty { break }
        }
        XCTAssertTrue(model.sidebarObjects.isEmpty)
        let record = try await store.record(for: IndexedPhotoFixture.path2020)
        XCTAssertEqual(record?.objectLabels, [])
        XCTAssertEqual(record?.semanticCategory, nil)
    }

    private func makeModel() async throws -> (LibraryViewModel, PhotoIndexStore) {
        let store = try PhotoIndexStore(databaseAt: dbURL)
        try await IndexedPhotoFixture.populateMixedLibrary(on: store)
        try await store.updateObjectLabels(path: IndexedPhotoFixture.path2020, names: ["Bus", "Man"])
        try await store.updateObjectLabels(path: IndexedPhotoFixture.pathBeach, names: ["Hot dog", "Jeans", "Bus"])
        try await store.updateObjectLabels(path: IndexedPhotoFixture.pathScreenshot, names: ["Dog"])
        let model = LibraryViewModel(project: projects.projects[0], projects: projects)
        await model.attachPhotoIndexForTesting(store)
        return (model, store)
    }

    private func awaitGridSettle(_ model: LibraryViewModel) async {
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(25))
            if !model.activity.isCataloging { break }
        }
        try? await Task.sleep(for: .milliseconds(50))
    }
}
