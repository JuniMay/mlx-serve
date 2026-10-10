import XCTest

@testable import MLXCore

/// Every creation menu exposes the same media workspaces.
final class GenExperimentTests: XCTestCase {

    /// Tray tiles keep short titles in a stable order.
    func testSectionHasExactlyTheMediaToolsInOrder() {
        XCTAssertEqual(GenExperiment.allCases.map(\.title),
                       ["Image", "Video", "Audio", "3D"])
    }

    func testCreationMenuPreservesEveryMediaWorkspace() {
        let items = GenExperiment.allCases
        XCTAssertEqual(items, [.image, .video, .audio, .model3d])
        XCTAssertEqual(items.map(\.menuTitle),
                       ["Image Generation", "Video Generation", "Audio & Music", "3D Model"])
        XCTAssertEqual(Set(items.map(\.id)).count, items.count)
        XCTAssertTrue(items.allSatisfy { !$0.icon.isEmpty })
    }

    /// Tooltips explain the short tile titles.
    func testHelpTextPresentPerTool() {
        for e in GenExperiment.allCases {
            XCTAssertFalse(e.help.isEmpty, "\(e.title) needs a tooltip")
        }
    }

    /// Each workspace has a distinct icon.
    func testIconsAreUnique() {
        let icons = GenExperiment.allCases.map(\.icon)
        XCTAssertEqual(Set(icons).count, icons.count, "Each experiment needs a distinct icon")
    }
}
