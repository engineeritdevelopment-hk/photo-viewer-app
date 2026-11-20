import CoreGraphics
import XCTest
@testable import Photo_Viewer

final class PhotoGridDragSelectionTests: XCTestCase {
    func testStrokeHitsCellsAlongPath() {
        let frames = [
            "/a.jpg": CGRect(x: 0, y: 0, width: 80, height: 80),
            "/b.jpg": CGRect(x: 100, y: 0, width: 80, height: 80),
            "/c.jpg": CGRect(x: 200, y: 0, width: 80, height: 80),
        ]
        let hits = PhotoGridDragSelection.paths(
            alongStrokeFrom: CGPoint(x: 40, y: 40),
            to: CGPoint(x: 240, y: 40),
            cellFrames: frames,
            step: 20
        )
        XCTAssertTrue(hits.contains("/a.jpg"))
        XCTAssertTrue(hits.contains("/b.jpg"))
        XCTAssertTrue(hits.contains("/c.jpg"))
    }

    func testStrokeMissesCellsOffThePath() {
        let frames = [
            "/a.jpg": CGRect(x: 0, y: 0, width: 40, height: 40),
            "/b.jpg": CGRect(x: 0, y: 200, width: 40, height: 40),
        ]
        let hits = PhotoGridDragSelection.paths(
            alongStrokeFrom: CGPoint(x: 10, y: 10),
            to: CGPoint(x: 30, y: 10),
            cellFrames: frames
        )
        XCTAssertEqual(hits, ["/a.jpg"])
    }
}