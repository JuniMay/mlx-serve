import XCTest
@testable import MLXCore

@MainActor
final class FolderSearchToolsGateTests: XCTestCase {
    private func index() -> DocumentIndex {
        DocumentIndex(folderURL: URL(fileURLWithPath: "/unused"), embedderProvider: { nil })
    }

    func testToolsOffSuppressesFolderSearchWithAndWithoutMCP() {
        for mcp in [false, true] {
            let resolved = ResolvedAgentSettings(
                tools: [.shell, .searchDocuments], toolsEnabled: false, mcpEnabled: mcp)
            let config = ChatTurnEngine.TurnConfig.from(resolved, documentIndex: index())
            XCTAssertNil(config.documentIndex)
            XCTAssertTrue(config.advertisedTools.isEmpty)
            XCTAssertTrue(config.dispatchTools.isEmpty)
            XCTAssertEqual(config.mcpMode, mcp)
        }
    }

    func testFolderAttachmentCannotGrantSearchAnAgentForbids() {
        let resolved = ResolvedAgentSettings(tools: [.shell], toolsEnabled: true)
        let config = ChatTurnEngine.TurnConfig.from(resolved, documentIndex: index())
        XCTAssertNil(config.documentIndex)
        XCTAssertEqual(config.dispatchTools, [.shell])
    }

    func testToolsOnKeepsFolderSearchAndItsIndex() {
        let documentIndex = index()
        let resolved = ResolvedAgentSettings(tools: [.searchDocuments], toolsEnabled: true)
        let config = ChatTurnEngine.TurnConfig.from(resolved, documentIndex: documentIndex)
        XCTAssertTrue(config.documentIndex === documentIndex)
        XCTAssertTrue(config.dispatchTools.contains(.searchDocuments))
    }

    func testIndividualDisablesKeepFolderSearchAvailableUnderTheToolsSwitch() {
        let toolsAgent = Agent(name: "Reader", systemPrompt: "",
                               capabilities: AgentCapabilities(tools: true, mcp: false, web: false))
        for agent in [nil, toolsAgent] as [Agent?] {
            let resolved = AgentResolution.resolve(agent: agent, defaults: AppDefaultsSnapshot(
                toolsEnabled: true, disabledTools: Set(AgentToolKind.chatToggleable)))
            XCTAssertTrue(resolved.toolsEnabled)
            XCTAssertEqual(resolved.tools, [.searchDocuments])
            let documentIndex = index()
            let config = ChatTurnEngine.TurnConfig.from(resolved, documentIndex: documentIndex)
            XCTAssertTrue(config.agentMode)
            XCTAssertEqual(config.advertisedTools, [.searchDocuments])
            XCTAssertEqual(config.dispatchTools, [.searchDocuments])
            XCTAssertTrue(config.documentIndex === documentIndex)
        }
    }

    func testFolderSearchWithoutAnAttachmentDoesNotStartAToolLoop() {
        let resolved = ResolvedAgentSettings(tools: [.searchDocuments], toolsEnabled: true)
        let config = ChatTurnEngine.TurnConfig.from(resolved)
        XCTAssertFalse(config.agentMode)
        XCTAssertNil(config.documentIndex)
        XCTAssertTrue(config.advertisedTools.isEmpty)
        XCTAssertTrue(config.dispatchTools.isEmpty)
    }

    func testToolsSwitchAndFolderCannotGrantAnAgentAnyToolAccess() {
        let agent = Agent(name: "Writer", systemPrompt: "",
                          capabilities: AgentCapabilities(tools: false, mcp: false, web: false))
        let resolved = AgentResolution.resolve(agent: agent, defaults: AppDefaultsSnapshot(toolsEnabled: true))
        let config = ChatTurnEngine.TurnConfig.from(
            ChatToolPreferences(toolsEnabled: true).applying(to: resolved), documentIndex: index())
        XCTAssertFalse(config.agentMode)
        XCTAssertNil(config.documentIndex)
        XCTAssertTrue(config.dispatchTools.isEmpty)
    }

    func testConversationToolsOverrideRemovesFolderSearchButKeepsMCP() {
        let resolved = ResolvedAgentSettings(
            tools: [.shell, .searchDocuments], toolsEnabled: true, mcpEnabled: true)
        let restricted = ChatToolPreferences(toolsEnabled: false).applying(to: resolved)
        XCTAssertFalse(restricted.toolsEnabled)
        XCTAssertTrue(restricted.tools.isEmpty)
        XCTAssertTrue(restricted.mcpEnabled)
    }

    func testRevokingToolsDropsFolderAccessWithoutRevokingMCP() {
        let original = ChatTurnEngine.TurnConfig.from(
            ResolvedAgentSettings(tools: [.shell, .searchDocuments], toolsEnabled: true, mcpEnabled: true),
            documentIndex: index())
        let revoked = original.revokingTools(true)
        XCTAssertNil(revoked.documentIndex)
        XCTAssertTrue(revoked.dispatchTools.isEmpty)
        XCTAssertTrue(revoked.mcpMode)
        XCTAssertNotNil(original.documentIndex)
    }

    func testRevocationRejectsADocumentCallReturnedBeforeApproval() async throws {
        guard let user = getpwuid(getuid()), NSHomeDirectory() != String(cString: user.pointee.pw_dir) else {
            throw XCTSkip("Use CFFIXED_USER_HOME to isolate AgentMemory initialization")
        }
        let documentIndex = index()
        documentIndex.finishForTesting(chunks: [
            DocumentRetrieval.Chunk(text: "private project budget", source: "budget.txt", vector: [])
        ], files: 1)
        let config = ChatTurnEngine.TurnConfig.from(
            ResolvedAgentSettings(tools: [.searchDocuments], toolsEnabled: true),
            documentIndex: documentIndex).revokingTools(true)
        var workingDirectory: String?
        let call = APIClient.ToolCall(id: "folder-search", name: "searchDocuments",
                                     arguments: ["query": "budget"], rawArguments: "{}")
        let result = await AgentEngine.executeToolCall(
            call, workingDirectory: &workingDirectory, repetition: AgentEngine.RepetitionTracker(),
            iteration: 0, agentMemory: AgentMemory(), documentIndex: config.documentIndex,
            allowedTools: config.dispatchTools)
        XCTAssertTrue(result.output.contains("was not run"), result.output)
        XCTAssertFalse(result.output.contains("private project budget"), result.output)
    }
}
