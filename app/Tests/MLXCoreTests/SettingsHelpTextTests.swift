import XCTest
@testable import MLXCore

final class SettingsHelpTextTests: XCTestCase {
    func testMissingSummaryKeepsCompleteExplainerAsCaption() {
        let explainer = "  Keep this full explanation.\nIncluding its second line.  "
        let help = SettingsHelpText(explainer: explainer)
        XCTAssertEqual(help.caption, explainer)
        XCTAssertNil(help.details)
        XCTAssertEqual(help.searchText, [explainer])
    }

    func testEmptyOrWhitespaceSummaryFallsBackWithoutDisclosure() {
        let explainer = "Keep the complete explanation."
        for summary in ["", " \t\n "] {
            let help = SettingsHelpText(explainer: explainer, summary: summary)
            XCTAssertEqual(help.caption, explainer)
            XCTAssertNil(help.details)
            XCTAssertEqual(help.searchText, [explainer])
        }
    }

    func testDistinctSummaryIsTrimmedButDetailsArePreservedExactly() {
        let explainer = "  Full explanation.\n\nKeep `--cache-dir` and all formatting.\n"
        let help = SettingsHelpText(explainer: explainer, summary: " \n Short caption. \t")
        XCTAssertEqual(help.caption, "Short caption.")
        XCTAssertEqual(help.details, explainer)
        XCTAssertEqual(help.searchText, ["Short caption.", explainer])
    }

    func testSameSummaryDoesNotDuplicateTheExplainer() {
        let explainer = "Use the same text once."
        let help = SettingsHelpText(explainer: explainer, summary: explainer)
        XCTAssertEqual(help.caption, explainer)
        XCTAssertNil(help.details)
        XCTAssertEqual(help.searchText, [explainer])
    }

    func testSurroundingWhitespaceDoesNotCreateRedundantDisclosure() {
        let explainer = " \nUse the same text once.\t"
        let help = SettingsHelpText(explainer: explainer, summary: "Use the same text once. ")
        XCTAssertEqual(help.caption, explainer)
        XCTAssertNil(help.details)
        XCTAssertEqual(help.searchText, [explainer])
    }

    func testSearchFindsCollapsedDetailsAndSummaryOnlySynonyms() {
        let help = SettingsHelpText(
            explainer: "Expose Prometheus metrics at /metrics for monitoring.",
            summary: "Track server performance.")
        XCTAssertTrue(SettingsSearch.matches(query: "Prometheus metrics", in: help.searchText))
        XCTAssertTrue(SettingsSearch.matches(query: "performance", in: help.searchText))
        XCTAssertTrue(SettingsSearch.matches(query: "performance Prometheus", in: help.searchText))
        XCTAssertFalse(SettingsSearch.matches(query: "Telegram", in: help.searchText))
    }

    func testFallbackCaptionRemainsSearchable() {
        let help = SettingsHelpText(explainer: "Keep KV snapshots across requests.")
        XCTAssertTrue(SettingsSearch.matches(query: "KV snapshots", in: help.searchText))
    }
}
