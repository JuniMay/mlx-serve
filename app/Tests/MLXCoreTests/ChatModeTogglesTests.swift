import XCTest
@testable import MLXCore

final class ChatModeTogglesTests: XCTestCase {

    func testNormalSessionReflectsItsResolvedState() {
        let t = ChatModeToggles.resolve(
            inAppThinking: false, inAppAgent: true, inAppMCP: false)
        XCTAssertEqual(t, ChatModeToggles(thinking: false, agent: true, mcp: false))
    }

    private let chef = AgentModeLock(name: "Chef", thinking: nil, tools: true, mcp: false)

    func testAgentDecidesToolsAndMcpAndTheDiscsSayWhoDid() {
        let t = ChatModeToggles.resolve(
            inAppThinking: false, inAppAgent: false, inAppMCP: true,   // the chat's own → overridden
            agentLock: chef)
        XCTAssertTrue(t.agent, "the agent's capabilities decide the tool loop")
        XCTAssertFalse(t.mcp, "the agent's capabilities decide MCP")
        XCTAssertEqual(t.toolsLockedBy, "Chef")
        XCTAssertEqual(t.mcpLockedBy, "Chef")
    }

    /// Thinking is the one an agent may leave unset (`enableThinking: nil`), and
    /// `AgentResolution` falls back to the surface's own value there. Locking it
    /// anyway would take away a control nobody is deciding for you.
    func testThinkingStaysTheChatsOwnWhenTheAgentDidNotDecideIt() {
        let t = ChatModeToggles.resolve(
            inAppThinking: true, inAppAgent: false, inAppMCP: false,
            agentLock: chef)
        XCTAssertTrue(t.thinking, "the chat's own thinking stands")
        XCTAssertNil(t.thinkingLockedBy, "nothing is deciding it, so it must not read as locked")
    }

    func testThinkingIsLockedWhenTheAgentDecidedIt() {
        let strict = AgentModeLock(name: "Coder", thinking: false, tools: true, mcp: false)
        let t = ChatModeToggles.resolve(
            inAppThinking: true, inAppAgent: false, inAppMCP: false,   // chat says on → overridden
            agentLock: strict)
        XCTAssertFalse(t.thinking)
        XCTAssertEqual(t.thinkingLockedBy, "Coder")
    }

    func testNoAgentLeavesEveryControlUnlocked() {
        let t = ChatModeToggles.resolve(
            inAppThinking: true, inAppAgent: true, inAppMCP: true,
            agentLock: nil)
        XCTAssertEqual(t, ChatModeToggles(thinking: true, agent: true, mcp: true))
        XCTAssertFalse(t.isLocked)
    }

    func testIsLockedIsTrueWhenAnyControlIsLocked() {
        XCTAssertTrue(ChatModeToggles(thinking: false, agent: true, mcp: false,
                                      toolsLockedBy: "Chef").isLocked)
        XCTAssertFalse(ChatModeToggles(thinking: false, agent: true, mcp: false).isLocked)
    }

    /// Apple's on-device model has no thinking mode and no room for MCP's tool
    /// definitions, so both discs read locked with it named as the owner —
    /// the same shape an agent's lock takes.
    func testAppleIntelligenceLocksThinkingAndMCP() {
        let t = ChatModeToggles.resolve(
                                        inAppThinking: true, inAppAgent: true, inAppMCP: true,
                                        apple: true)
        XCTAssertFalse(t.thinking)
        XCTAssertFalse(t.mcp)
        XCTAssertEqual(t.thinkingLockedBy, AppleFoundationChat.displayName)
        XCTAssertEqual(t.mcpLockedBy, AppleFoundationChat.displayName)
        // The tool LOOP still switches; only the tool SET is clamped.
        XCTAssertTrue(t.agent)
        XCTAssertNil(t.toolsLockedBy)
    }
}
