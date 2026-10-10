import XCTest
@testable import MLXCore

/// The tray keeps status labels compact and emphasizes the primary server action.
final class TrayChromeTests: XCTestCase {

    // MARK: - Status chip

    /// The header chip is a GLANCE. `ServerStatus.label` interpolates the whole
    /// error message ("Error: MISSING WEIGHT: model.embed_tokens.weight …"),
    /// which in a 340pt panel either truncates to nothing useful or blows the
    /// header's height — the full text belongs in the tooltip and the error row
    /// under the server controls, both of which already show it.
    func testStatusChipNeverRendersTheRawErrorMessage() {
        let raw = "MISSING WEIGHT: model.embed_tokens.weight — checkpoint is incomplete"
        let chip = TrayStatusChipModel(status: .error(raw))

        XCTAssertEqual(chip.label, "Error")
        XCTAssertEqual(chip.tone, .error)
        XCTAssertFalse(chip.label.contains(raw))
    }

    func testStatusChipLabelsAndTones() {
        XCTAssertEqual(TrayStatusChipModel(status: .running).label, "Running")
        XCTAssertEqual(TrayStatusChipModel(status: .running).tone, .running)
        XCTAssertEqual(TrayStatusChipModel(status: .starting).label, "Loading")
        XCTAssertEqual(TrayStatusChipModel(status: .starting).tone, .starting)
        XCTAssertEqual(TrayStatusChipModel(status: .stopped).label, "Stopped")
        XCTAssertEqual(TrayStatusChipModel(status: .stopped).tone, .stopped)
    }

    // MARK: - Server control emphasis

    /// Only ONE filled control per panel, and it goes to the action the user is
    /// most likely to want. With the server up that action is "open Chat", not
    /// "Stop Server" — a full-width red fill was the loudest thing on screen for
    /// the state the app spends all its time in. Start/Loading stay prominent:
    /// there, starting the server IS the thing to do next.
    func testOnlyTheStartAndLoadingStatesAreProminent() {
        XCTAssertTrue(ServerControlButtonPresentation(status: .stopped).isProminent)
        XCTAssertTrue(ServerControlButtonPresentation(status: .starting).isProminent)
        XCTAssertTrue(ServerControlButtonPresentation(status: .error("x")).isProminent)
        XCTAssertFalse(ServerControlButtonPresentation(status: .running).isProminent)
    }

    /// The titles/tints the older tests pin must survive the emphasis change —
    /// stop is still red, it just isn't filled.
    func testRunningKeepsItsRedStopPresentation() {
        let running = ServerControlButtonPresentation(status: .running)
        XCTAssertEqual(running.title, "Stop Server")
        XCTAssertEqual(running.tint, .red)
    }

}
