import XCTest
@testable import MLXCore

/// Existing capability and command reachability guards.
final class ComposerModeControlTests: XCTestCase {

    private func chatViewSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // MLXCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // app
            .appendingPathComponent("Sources/MLXServe/Views/ChatView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The body of a `private var <name>: some View { … }`, up to the next
    /// member declaration.
    private func declaration(_ name: String, in source: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: "private var \(name): some View {"),
                                  "ChatView must still declare \(name)")
        let rest = source[start.upperBound...]
        let end = rest.range(of: "\n    private ") ?? rest.range(of: "\n    @ViewBuilder")
        return String(rest[..<(end?.lowerBound ?? rest.endIndex)])
    }



    /// "Enable/Disable All Tools" were bulk rows above the per-tool switches they
    /// duplicated — the same set is one click per row away, and the pair read as
    /// a second on/off for the loop the wrench already toggles.
    func testToolMenuHasNoBulkAllRows() throws {
        let source = try chatViewSource()
        for banned in ["Enable All Tools", "Disable All Tools"] {
            XCTAssertFalse(source.contains(banned), "\(banned) was removed as redundant")
        }
        XCTAssertFalse(source.contains("setAllTools"), "the bulk helper goes with its rows")
    }

    /// The sandbox shield is gone from the composer row (2026-07-29) — it was a
    /// status glyph that only ever opened Settings, sitting in the row reserved
    /// for controls that configure the turn being written.
    func testSandboxShieldIsNotInTheComposerRow() throws {
        let source = try chatViewSource()
        XCTAssertFalse(source.contains("sandboxShield"),
                       "the sandbox shield was removed from the chat composer")
    }

    // MARK: - Agent lock









    /// "Edit Agent…" on a locked disc must land on THAT agent, not on whoever
    /// sorts first — the whole reason the row exists is that the user just read
    /// the agent's name on the card.
    func testEditAgentDeepLinksToTheAgentThatLockedTheControl() throws {
        let source = try chatViewSource()
        let start = try XCTUnwrap(source.range(of: "private func lockedModeMenu("),
                                  "the locked discs must still offer a way into the agent")
        let rest = source[start.upperBound...]
        let body = String(rest[..<(rest.range(of: "\n    private ")?.lowerBound ?? rest.endIndex)])
        XCTAssertTrue(body.contains("openAgentSettings("), """
            Edit Agent… must route through `AppState.openAgentSettings` — a bare \
            openWindow(id: "agents") opens the window on the first agent in the list.
            """)
    }

    // MARK: - The agent is chosen when the chat is, and fixed after

    /// The picker moved OUT of the composer row: it configured the whole
    /// conversation, not the message being written, and it sat next to four
    /// controls the agent then overrode.
    func testTheComposerRowNoLongerHoldsTheAgentPicker() throws {
        let source = try chatViewSource()
        XCTAssertFalse(source.contains("agentChip"),
                       "the agent picker lives next to New Chat now, not in the composer")
    }

    /// Switching mid-thread left half a conversation running under someone
    /// else's prompt, tools and model, with nothing but the transcript to show
    /// where the seam was. A session's agent is now decided when the session is
    /// created and never after — structurally, by there being no setter.
    func testASessionsAgentCannotBeChangedAfterItIsCreated() throws {
        let agentsSource = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/MLXServe/Services/AppStateAgents.swift"), encoding: .utf8)
        XCTAssertFalse(agentsSource.contains("func setAgent("), """
            `setAgent(_:forSession:)` is gone on purpose — a session's agent is \
            fixed at creation. Starting a chat AS an agent goes through \
            `startChat(withAgent:)`.
            """)
        XCTAssertTrue(agentsSource.contains("func startChat(withAgent"),
                      "the sidebar needs one call that creates the session AND applies the agent")
    }

    /// It has to actually apply the agent — its model, workspace and voice all
    /// live outside the turn, and a session that only carries the ID would run
    /// the persona against whatever model happened to be loaded.
    func testStartingAChatAsAnAgentAppliesThatAgentsSelection() throws {
        let agentsSource = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/MLXServe/Services/AppStateAgents.swift"), encoding: .utf8)
        let start = try XCTUnwrap(agentsSource.range(of: "func startChat(withAgent"))
        let rest = agentsSource[start.upperBound...]
        let body = String(rest[..<(rest.range(of: "\n    }")?.upperBound ?? rest.endIndex)])
        XCTAssertTrue(body.contains("newChatSession("), "it must create the session")
        XCTAssertTrue(body.contains("applyAgentSelection("),
                      "model / workspace / voice all live outside the turn")
    }

    /// Starting a chat AS an agent must remain reachable, wherever the control
    /// lives.
    ///
    /// It has moved three times — composer chip → the sidebar's Agents row →
    /// beside New Chat → into the agent's own editor, once Agents became a pane
    /// where everything about an agent lives together. Every move has been one
    /// edit away from deleting the capability instead of relocating it: taking
    /// the menu off the Agents row once left `startChat(withAgent:)` with no
    /// caller anywhere in the UI, and the test passed, because it was pinned to
    /// a control's coordinates. A session's agent is fixed once the session
    /// exists (there is no `setAgent`), so this is the only moment it can be
    /// decided — pin that it is reachable AT ALL, from anywhere.
    func testStartingAChatAsAnAgentStaysReachable() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let views = try FileManager.default
            .contentsOfDirectory(at: root.appendingPathComponent("Sources/MLXServe/Views"),
                                 includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        let callers = try views.filter {
            try String(contentsOf: $0, encoding: .utf8).contains("startChat(withAgent:")
        }
        XCTAssertFalse(callers.isEmpty, """
            Nothing in the UI calls startChat(withAgent:) any more. A session's \
            agent can only be chosen when the session is created, so with no \
            caller the capability is gone, not moved.
            """)
    }

    // MARK: - Content passing under floating chrome

    /// Transcript text ran straight into the floating model-picker cluster.
    /// The fix is the platform's own scroll-edge effect (`scrollEdgeEffectStyle`,
    /// macOS 26+) on the scrolling surfaces — NOT a hand-drawn band, which is how
    /// this went wrong the first time: a custom strip pulled in via
    /// `ignoresSafeArea` looked native and swallowed every click in the toolbar
    /// band's layer.
    func testScrollingSurfacesUseTheNativeScrollEdgeEffect() throws {
        let source = try chatViewSource()
        let sidebar = try XCTUnwrap(source.range(of: "struct ChatSidebar: View {"))
        let sidebarBody = String(source[sidebar.upperBound...]
            .prefix(while: { _ in true }))
            .components(separatedBy: "\n// MARK:").first ?? ""
        XCTAssertTrue(sidebarBody.contains(".scrollEdgeEffectStyle("),
                      "the session list needs the native edge effect under its chrome")

        let occurrences = source.components(separatedBy: ".scrollEdgeEffectStyle(").count - 1
        XCTAssertGreaterThanOrEqual(occurrences, 2,
                                    "both the sidebar and the transcript scroll under floating chrome")
    }


}
