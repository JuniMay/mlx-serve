import XCTest
@testable import MLXCore

/// Unit tests for the Settings sidebar — the category list, what's selectable
/// under which engine, and how selection and the search field interact.
///
/// SwiftUI can't be exercised directly, so (exactly as with `SettingsSearch`)
/// every *decision* lives in a pure model and the views only ask it questions.
///
/// The load-bearing invariant: **search text and a category selection never
/// coexist.** Typing forces the selection back to All; picking a category clears
/// the search. Otherwise a user lands on "Server" with a stale query still
/// narrowing it and sees an empty pane with no visible explanation.
final class SettingsCategoryTests: XCTestCase {

    func testCategoriesGroupCachesAndHardwareWithoutRetiredDestinations() {
        let expected = ["general", "modelFolders", "server", "lanSharing", "providers", "memory", "cache",
                        "performance", "specDecode", "engines", "requestDefaults", "appearance", "voice",
                        "tools", "sandbox", "about"]
        for engine: ServerEngine? in [nil, .mlx, .mlxGguf, .llama, .dsv4] {
            for selfUpdate in [false, true] {
                XCTAssertEqual(SettingsCategory.visible(engine: engine, selfUpdate: selfUpdate).map(\.rawValue), expected)
            }
        }
    }

    func testAppearanceAndSpeculationUseUserFacingCategoryNames() throws {
        let appearance = try XCTUnwrap(SettingsCategory(rawValue: "appearance"))
        XCTAssertEqual(appearance.title, "Appearance")
        XCTAssertEqual(SettingsCategory.specDecode.title, "Speculative Decoding")
    }

    // MARK: - Selection ↔ search interaction (the invariant)

    func testTypingASearchForcesSelectionBackToAll() {
        XCTAssertEqual(SettingsSelection.afterQueryEdit(query: "prefix cache", current: .category(.server)), .all)
        XCTAssertEqual(SettingsSelection.afterQueryEdit(query: "kv", current: .category(.voice)), .all)
    }

    /// Clearing the field must NOT yank the user back to All — otherwise picking
    /// a category (which clears the search) would immediately undo itself.
    func testClearingTheSearchLeavesTheSelectionAlone() {
        XCTAssertEqual(SettingsSelection.afterQueryEdit(query: "", current: .category(.server)), .category(.server))
        XCTAssertEqual(SettingsSelection.afterQueryEdit(query: "   ", current: .category(.server)), .category(.server))
    }

    func testClearingGlobalSearchReturnsToGeneral() {
        let selection = SettingsSelection.afterQueryEdit(query: "", current: .all)
        guard case .category(let category) = selection else {
            return XCTFail("Clearing search must return to a category, not the complete settings form")
        }
        XCTAssertEqual(category.rawValue, "general")
    }

    func testOrdinaryWindowReopenPreservesTheCategoryAndSearch() {
        let visible = SettingsCategory.visible(engine: .mlx, selfUpdate: true)
        XCTAssertEqual(SettingsSelection.afterOpen(requested: nil, current: .category(.voice), visible: visible),
                       .category(.voice))
        XCTAssertEqual(SettingsSelection.afterOpen(requested: nil, current: .all, visible: visible), .all)
    }

    func testContextRecoveryOpensServerEvenDuringGlobalSearch() {
        let visible = SettingsCategory.visible(engine: .mlx, selfUpdate: true)
        XCTAssertEqual(SettingsSelection.afterOpen(requested: .server, current: .all, visible: visible),
                       .category(.server))
        XCTAssertEqual(SettingsSelection.afterOpen(requested: .server, current: .category(.general), visible: visible),
                       .category(.server))
    }

    func testUnavailableDeepLinkFallsBackToGeneral() {
        let visible: [SettingsCategory] = [.general, .server]
        XCTAssertEqual(SettingsSelection.afterOpen(requested: .specDecode, current: .category(.server), visible: visible),
                       .category(.general))
        XCTAssertEqual(SettingsSelection.afterOpen(requested: .about, current: .category(.server), visible: visible),
                       .category(.general))
    }

    // MARK: - What a selection shows

    func testAllShowsEverySection() {
        for c in SettingsCategory.allCases {
            XCTAssertTrue(SettingsSelection.all.shows(c))
        }
    }

    func testACategoryShowsOnlyItself() {
        let sel = SettingsSelection.category(.server)
        XCTAssertTrue(sel.shows(.server))
        XCTAssertFalse(sel.shows(.voice))
        XCTAssertFalse(sel.shows(.performance))
    }

    // MARK: - Reconciliation

    // An unavailable destination must fall back to a visible category.
    func testSelectionFallsBackToGeneralWhenItsCategoryDisappears() {
        let visible: [SettingsCategory] = [.general, .server]
        let fallback = SettingsSelection.reconciled(.category(.specDecode), visible: visible)
        if case .category(let category) = fallback {
            XCTAssertEqual(category.rawValue, "general")
        } else {
            XCTFail("A retired category must fall back to General")
        }
        XCTAssertEqual(SettingsSelection.reconciled(.category(.server), visible: visible), .category(.server),
                       "a still-visible category survives an engine switch")
        XCTAssertEqual(SettingsSelection.reconciled(.all, visible: visible), .all)
    }

    // MARK: - Titles

    /// The sidebar label and the section header come from ONE source, so they
    /// can't drift. The header keeps its long, explicit form; the sidebar gets a
    /// short one that fits the column.
    func testEveryCategoryHasATitleAndASidebarLabel() {
        for c in SettingsCategory.allCases {
            XCTAssertFalse(c.title.isEmpty)
            XCTAssertFalse(c.sidebarLabel.isEmpty)
            XCTAssertFalse(c.icon.isEmpty)
        }
        XCTAssertEqual(SettingsCategory.specDecode.title, "Speculative Decoding")
        XCTAssertEqual(SettingsCategory.specDecode.sidebarLabel, "Speculative Decoding")
    }

    // MARK: - Source audit (class guard)

    /// CLASS GUARD: every settings section must declare a `category:`, never a
    /// raw `title:` string. A section without a category has no sidebar entry —
    /// it would be silently unreachable whenever anything but "All Settings" is
    /// selected, and its title could drift from the sidebar's.
    func testEverySettingsSectionDeclaresACategory() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/MLXServe/Views/SettingsView.swift")
        let body = try String(contentsOf: source, encoding: .utf8)

        // Declarations wrap: `SettingsSection(` on one line, `category:` on the
        // next — so look at the call, not a single line.
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        var offenders: [String] = []
        for (i, l) in lines.enumerated() {
            if l.hasPrefix("//") || l.contains("struct ") { continue }
            guard l.contains("SettingsSection(") else { continue }
            let declaration = lines[i...min(i + 2, lines.count - 1)].joined(separator: " ")
            if !declaration.contains("category:") {
                offenders.append(declaration)
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            Every SettingsSection must be declared with `category:` so it has a \
            sidebar entry (and one source of truth for its title). Offenders:
            \(offenders.joined(separator: "\n"))
            """)
    }
}
