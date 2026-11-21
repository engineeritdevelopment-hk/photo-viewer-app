import XCTest
@testable import Photo_Viewer

final class ObjectLabelTests: XCTestCase {
    func testLabelsStayUniqueAndSorted() {
        let encoded = ObjectLabels.encode(["dog", "Dog", "Hot dog", "  bicycle "])
        XCTAssertEqual(encoded, "|bicycle|dog|Hot dog|")
        XCTAssertEqual(ObjectLabels.decode(encoded), ["bicycle", "dog", "Hot dog"])
    }

    func testEmptyLabelsEncodeAsNil() {
        XCTAssertNil(ObjectLabels.encode(["  ", ""]))
        XCTAssertEqual(ObjectLabels.decode(nil), [])
        XCTAssertEqual(ObjectLabels.decode("|"), [])
    }

    func testPaddingIndexesAndUnderscoresAreDropped() {
        let encoded = ObjectLabels.encode(["hot_dog", "601", "Hot dog", "  12 "])
        XCTAssertEqual(encoded, "|hot dog|")
        XCTAssertEqual(ObjectLabels.decode(encoded), ["hot dog"])
    }
}
