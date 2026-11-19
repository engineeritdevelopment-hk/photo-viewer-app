import XCTest
@testable import Photo_Viewer

final class ReleaseAssetPickerTests: XCTestCase {
  func testPrefersPhotoViewerZip() throws {
    let assets = [
      GitHubReleaseAsset(
        name: "checksums.txt",
        browser_download_url: URL(string: "https://example.com/a.txt")!
      ),
      GitHubReleaseAsset(
        name: "Photo-Viewer-1.0.1-mac.zip",
        browser_download_url: URL(string: "https://example.com/app.zip")!
      ),
    ]
    let url = ReleaseAssetPicker.preferredZipURL(from: assets)
    XCTAssertEqual(url?.absoluteString, "https://example.com/app.zip")
  }
}