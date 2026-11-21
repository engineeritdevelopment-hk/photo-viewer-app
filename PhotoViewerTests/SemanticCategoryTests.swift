import XCTest
@testable import Photo_Viewer

final class SemanticCategoryTests: XCTestCase {
    func testFoodMatchesVisionSnippet() {
        XCTAssertEqual(
            SemanticFolders.matchCategory(in: "Image: food, dish, restaurant"),
            "Food"
        )
    }

    func testFoodMatchesFilenameAndOCR() {
        XCTAssertEqual(SemanticFolders.matchCategory(in: "dinner at sushi restaurant"), "Food")
        XCTAssertEqual(SemanticFolders.matchCategory(in: "birthday_cake.JPG"), "Food")
    }

    func testVisionStyleSnippetClassifiesAsFood() {
        XCTAssertEqual(
            SemanticFolders.matchCategory(in: "Image: food, meal, plate"),
            "Food"
        )
    }

    func testWeddingSceneBeatsGenericPeople() {
        XCTAssertEqual(
            SemanticFolders.matchCategory(in: "Image: people, celebration, wedding"),
            "Events"
        )
    }

    func testPortraitWithoutAnEventIsPeople() {
        XCTAssertEqual(
            SemanticFolders.matchCategory(in: "Image: people, adult, clothing"),
            "People"
        )
    }

    func testPlantSceneIsNature() {
        XCTAssertEqual(
            SemanticFolders.matchCategory(in: "Image: plant, flower"),
            "Nature"
        )
    }
}