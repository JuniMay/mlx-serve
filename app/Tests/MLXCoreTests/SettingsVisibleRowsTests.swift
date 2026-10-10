import XCTest
@testable import MLXCore

final class SettingsVisibleRowsTests: XCTestCase {
    func testMergedCountsKeepSectionsAndFooterSeparate() {
        var rows = SettingsVisibleRows()
        rows.merge(.row(in: .general))
        rows.merge(.row(in: .general))
        rows.merge(.row(in: .memory))
        rows.merge(.row(in: nil))

        XCTAssertEqual(rows.count(in: .general), 2)
        XCTAssertEqual(rows.count(in: .memory), 1)
        XCTAssertEqual(rows.count(in: .tools), 0)
        XCTAssertEqual(rows.total, 4)
    }

    func testFooterMatchDoesNotKeepUnrelatedHeadersVisible() {
        let rows = SettingsVisibleRows.row(in: nil)
        XCTAssertEqual(rows.total, 1)
        for category in SettingsCategory.allCases {
            let filter = SettingsSearch.section(query: "resets", title: category.title)
            XCTAssertTrue(filter.collapsed(visibleRows: rows.count(in: category)), category.rawValue)
        }
    }

    func testQueryChangesReplaceRatherThanRetainOldSectionMatches() {
        let candidates: [(SettingsCategory, [String])] = [
            (.general, ["Start server", "Start automatically"]),
            (.general, ["Quick Launcher", "Global shortcut"]),
            (.memory, ["Model memory cap", "--max-resident-mem"]),
        ]
        func snapshot(_ query: String) -> SettingsVisibleRows {
            var rows = SettingsVisibleRows()
            for (category, text) in candidates {
                let filter = SettingsSearch.section(query: query, title: category.title)
                if SettingsSearch.matches(query: filter.childQuery, in: text) {
                    rows.merge(.row(in: category))
                }
            }
            return rows
        }

        var rows = snapshot("General")
        XCTAssertEqual(rows.count(in: .general), 2)
        XCTAssertEqual(rows.count(in: .memory), 0)
        rows = snapshot("--max-resident-mem")
        XCTAssertEqual(rows.count(in: .general), 0)
        XCTAssertEqual(rows.count(in: .memory), 1)
        rows = snapshot("unmatchablesettingsquery")
        XCTAssertEqual(rows.total, 0)
        rows = snapshot("")
        XCTAssertEqual(rows.total, 3)
    }
}
