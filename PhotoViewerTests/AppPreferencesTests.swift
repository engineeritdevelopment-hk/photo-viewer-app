import XCTest
@testable import Photo_Viewer

final class AppPreferencesTests: XCTestCase {
    func testLastOpenedProjectIdRoundTrip() {
        let prior = AppPreferences.lastOpenedProjectId
        defer { AppPreferences.lastOpenedProjectId = prior }

        AppPreferences.lastOpenedProjectId = "project-42"
        XCTAssertEqual(AppPreferences.lastOpenedProjectId, "project-42")
        AppPreferences.lastOpenedProjectId = nil
        XCTAssertNil(AppPreferences.lastOpenedProjectId)
    }
}