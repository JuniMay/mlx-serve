import XCTest
@testable import MLXCore

/// Composer height limits and Return-key behavior.
final class ComposerInputTests: XCTestCase {

    // MARK: - ComposerLayout.resolve (auto-grow then scroll)

    func testSingleLineFloorsAtMinHeight() {
        // One short line of content must not collapse below the 1-line floor.
        let r = ComposerLayout.resolve(contentHeight: 5, lineHeight: 20,
                                       minLines: 1, maxLines: 15, verticalInset: 16)
        XCTAssertEqual(r.height, 20 * 1 + 16, accuracy: 0.01)
        XCTAssertFalse(r.scrolls)
    }

    func testGrowsWithContentBelowTheCap() {
        // 10 lines of content sits between the min and max — height tracks it,
        // no scrolling yet.
        let r = ComposerLayout.resolve(contentHeight: 200, lineHeight: 20,
                                       minLines: 1, maxLines: 15, verticalInset: 16)
        XCTAssertEqual(r.height, 200 + 16, accuracy: 0.01)
        XCTAssertFalse(r.scrolls)
    }

    func testClampsAtMaxAndScrolls() {
        // A big paste (30 lines) clamps at the 15-line cap and turns scrolling on
        // — the bug being fixed: TextField(axis:.vertical) never scrolled.
        let r = ComposerLayout.resolve(contentHeight: 600, lineHeight: 20,
                                       minLines: 1, maxLines: 15, verticalInset: 16)
        XCTAssertEqual(r.height, 20 * 15 + 16, accuracy: 0.01)
        XCTAssertTrue(r.scrolls)
    }

    func testExactlyAtCapDoesNotScroll() {
        let r = ComposerLayout.resolve(contentHeight: 20 * 15, lineHeight: 20,
                                       minLines: 1, maxLines: 15, verticalInset: 16)
        XCTAssertEqual(r.height, 20 * 15 + 16, accuracy: 0.01)
        XCTAssertFalse(r.scrolls)
    }

    // MARK: - ComposerKey.onReturn (send vs newline vs swallow)

    func testShiftReturnAlwaysInsertsNewline() {
        XCTAssertEqual(ComposerKey.onReturn(shift: true, isIdle: true), .newline)
        XCTAssertEqual(ComposerKey.onReturn(shift: true, isIdle: false), .newline)
    }

    func testBareReturnSendsWhenIdle() {
        XCTAssertEqual(ComposerKey.onReturn(shift: false, isIdle: true), .send)
    }

    func testBareReturnSwallowedWhileGenerating() {
        // While a turn is generating a bare Return must NOT insert a stray
        // newline and must NOT start a second send — it is swallowed, unless
        // the field can steer (`SteeringNotesTests`).
        XCTAssertEqual(ComposerKey.onReturn(shift: false, isIdle: false), .ignore)
    }
}
