import XCTest
@testable import MLXCore

@MainActor
final class PlainChatTurnConfigTests: XCTestCase {
    private func index() -> DocumentIndex {
        DocumentIndex(folderURL: URL(fileURLWithPath: "/unused"), embedderProvider: { nil })
    }

    func testPlainChatSuppressesAnAttachedDocumentIndexAndAllTools() {
        var resolved = ResolvedAgentSettings(
            tools: Set(AgentToolKind.allCases), toolsEnabled: true,
            mcpEnabled: true, thinkingEnabled: true)
        resolved.plainChat = true
        let config = ChatTurnEngine.TurnConfig.from(resolved, documentIndex: index())

        XCTAssertFalse(config.agentMode)
        XCTAssertFalse(config.mcpMode)
        XCTAssertNil(config.documentIndex)
        XCTAssertTrue(config.advertisedTools.isEmpty)
        XCTAssertTrue(config.dispatchTools.isEmpty)
        XCTAssertTrue(config.enableThinking)
    }

    func testNormalConversationKeepsExplicitlyAttachedDocuments() {
        let documentIndex = index()
        let config = ChatTurnEngine.TurnConfig.from(ResolvedAgentSettings(), documentIndex: documentIndex)
        XCTAssertTrue(config.documentIndex === documentIndex)
    }

    func testRevokingAllToolsAlsoDisablesMCPAndDocumentSearch() {
        let resolved = ResolvedAgentSettings(
            tools: Set(AgentToolKind.allCases), toolsEnabled: true, mcpEnabled: true)
        let original = ChatTurnEngine.TurnConfig.from(resolved, documentIndex: index())
        let revoked = original.revokingAllTools(true)

        XCTAssertFalse(revoked.agentMode)
        XCTAssertFalse(revoked.mcpMode)
        XCTAssertNil(revoked.documentIndex)
        XCTAssertTrue(revoked.dispatchTools.isEmpty)
        XCTAssertTrue(original.revokingAllTools(false).mcpMode)
    }

    func testRevokingMCPKeepsBuiltInToolsAndAttachedDocuments() {
        let documentIndex = index()
        let original = ChatTurnEngine.TurnConfig.from(
            ResolvedAgentSettings(tools: [.shell, .searchDocuments], toolsEnabled: true, mcpEnabled: true),
            documentIndex: documentIndex)
        let revoked = original.revokingMCP(true)
        XCTAssertFalse(revoked.mcpMode)
        XCTAssertTrue(revoked.agentMode)
        XCTAssertEqual(revoked.dispatchTools, original.dispatchTools)
        XCTAssertTrue(revoked.documentIndex === documentIndex)
        XCTAssertTrue(original.revokingMCP(false).mcpMode)
    }

    func testMCPRevocationIsScopedAndEndsWithTheTurn() {
        var ledger = TurnLedger()
        let first = UUID(), other = UUID()
        let token = ledger.begin(session: first)
        _ = ledger.begin(session: other)
        ledger.revokeMCP(session: first)
        XCTAssertTrue(ledger.mcpRevoked(session: first))
        XCTAssertFalse(ledger.toolsRevoked(session: first))
        XCTAssertFalse(ledger.mcpRevoked(session: other))
        ledger.end(session: first, token: token)
        _ = ledger.begin(session: first)
        XCTAssertFalse(ledger.mcpRevoked(session: first))
    }

    func testAllToolRevocationIsScopedAndEndsWithTheTurn() {
        var ledger = TurnLedger()
        let first = UUID(), other = UUID()
        let token = ledger.begin(session: first)
        _ = ledger.begin(session: other)
        ledger.revokeAllTools(session: first)
        XCTAssertTrue(ledger.allToolsRevoked(session: first))
        XCTAssertTrue(ledger.toolsRevoked(session: first))
        XCTAssertFalse(ledger.allToolsRevoked(session: other))
        ledger.end(session: first, token: token)
        _ = ledger.begin(session: first)
        XCTAssertFalse(ledger.allToolsRevoked(session: first))
    }

    func testStoppedOrSupersededTurnsCannotResumeAnApprovedCall() {
        var ledger = TurnLedger()
        let session = UUID()
        let stopped = ledger.begin(session: session)
        XCTAssertTrue(ledger.owns(session: session, token: stopped))
        ledger.endAll(session: session)
        XCTAssertFalse(ledger.owns(session: session, token: stopped))
        let superseded = ledger.begin(session: session)
        let current = ledger.begin(session: session)
        XCTAssertFalse(ledger.owns(session: session, token: superseded))
        XCTAssertTrue(ledger.owns(session: session, token: current))
    }
}
