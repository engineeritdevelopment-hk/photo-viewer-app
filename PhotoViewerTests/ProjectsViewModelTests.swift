import XCTest
@testable import Photo_Viewer

@MainActor
final class ProjectsViewModelTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = try TempDirectory.create()
        ApplicationPaths.useIsolatedSupportRoot(tempRoot)
    }

    override func tearDownWithError() throws {
        ApplicationPaths.resetSupportRootOverride()
        TempDirectory.remove(tempRoot)
        tempRoot = nil
        try super.tearDownWithError()
    }

    func testCreateRenameDeleteProject() throws {
        let vm = ProjectsViewModel()
        vm.load()

        let created = vm.create(name: "Travel")
        XCTAssertNotNil(created)
        XCTAssertEqual(vm.projects.count, 1)

        vm.rename(projectId: created!.id, to: "Family Trips")
        XCTAssertEqual(vm.projects.first?.name, "Family Trips")

        vm.delete(projectIds: [created!.id])
        XCTAssertTrue(vm.projects.isEmpty)
        let reloaded = try ProjectStore.load()
        XCTAssertTrue(reloaded.isEmpty)
    }

    func testDeleteRemovesProjectIndexFile() {
        let vm = ProjectsViewModel()
        let project = vm.create(name: "Index Test")!
        let indexURL = ApplicationPaths.indexDatabase(projectId: project.id)
        FileManager.default.createFile(atPath: indexURL.path, contents: Data())
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexURL.path))

        vm.delete(projectIds: [project.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: indexURL.path))
    }

    func testProjectStoreRoundTrip() throws {
        let vm = ProjectsViewModel()
        _ = vm.create(name: "Persisted")
        _ = vm.create(name: "Second")

        let reloaded = ProjectsViewModel()
        reloaded.load()
        XCTAssertEqual(reloaded.projects.map(\.name).sorted(), ["Persisted", "Second"])
    }
}