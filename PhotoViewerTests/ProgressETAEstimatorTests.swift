import XCTest
@testable import Photo_Viewer

final class ProgressETAEstimatorTests: XCTestCase {
    func testFormatSecondsMinutesHours() {
        XCTAssertEqual(ProgressETAEstimator.format(remaining: 45), "~45s remaining")
        XCTAssertEqual(ProgressETAEstimator.format(remaining: 120), "~2 min remaining")
        XCTAssertEqual(ProgressETAEstimator.format(remaining: 3720), "~1h 2m remaining")
    }

    func testUpdateReturnsNilAtStart() {
        var estimator = ProgressETAEstimator()
        XCTAssertNil(estimator.update(done: 0, total: 100))
        XCTAssertNil(estimator.update(done: 1, total: 100))
    }

    func testUpdateResetsWhenComplete() {
        var estimator = ProgressETAEstimator()
        _ = estimator.update(done: 50, total: 100)
        XCTAssertNil(estimator.update(done: 100, total: 100))
        XCTAssertNil(estimator.update(done: 0, total: 100))
    }
}