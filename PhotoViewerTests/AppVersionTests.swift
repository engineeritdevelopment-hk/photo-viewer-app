import XCTest
@testable import Photo_Viewer

final class AppVersionTests: XCTestCase {
  func testParseStripsLeadingV() {
    XCTAssertEqual(AppVersion.parse("v1.2.3")?.components, [1, 2, 3])
  }

  func testComparePatchLevels() {
    let a = AppVersion(components: [1, 0, 0])
    let b = AppVersion(components: [1, 0, 1])
    XCTAssertTrue(a < b)
    XCTAssertFalse(b < a)
  }

  func testCompareUnequalComponentCounts() {
    let a = AppVersion(components: [1, 0])
    let b = AppVersion(components: [1, 0, 0, 1])
    XCTAssertTrue(a < b)
  }

  func testEqualVersions() {
    let a = AppVersion.parse("1.0.0")
    let b = AppVersion.parse("1.0")
    XCTAssertEqual(a, b)
  }
}