import XCTest
@testable import MLXCore

final class ModelBrowserSectionNavigationTests: XCTestCase {
    func testArrowKeysSelectAdjacentSections() {
        XCTAssertEqual(ModelBrowserSectionNavigation.destination(from: .discover, movingRight: true), .myModels)
        XCTAssertEqual(ModelBrowserSectionNavigation.destination(from: .myModels, movingRight: false), .discover)
    }

    func testArrowKeysWrapAtBothEnds() {
        XCTAssertEqual(ModelBrowserSectionNavigation.destination(from: .media, movingRight: true), .recommended)
        XCTAssertEqual(ModelBrowserSectionNavigation.destination(from: .recommended, movingRight: false), .media)
    }

    func testArrowKeysFollowRightToLeftVisualOrder() {
        XCTAssertEqual(ModelBrowserSectionNavigation.destination(from: .discover, movingRight: true,
                                                                  rightToLeft: true), .recommended)
        XCTAssertEqual(ModelBrowserSectionNavigation.destination(from: .discover, movingRight: false,
                                                                  rightToLeft: true), .myModels)
        XCTAssertEqual(ModelBrowserSectionNavigation.destination(from: .recommended, movingRight: true,
                                                                  rightToLeft: true), .media)
        XCTAssertEqual(ModelBrowserSectionNavigation.destination(from: .media, movingRight: false,
                                                                  rightToLeft: true), .recommended)
    }
}
