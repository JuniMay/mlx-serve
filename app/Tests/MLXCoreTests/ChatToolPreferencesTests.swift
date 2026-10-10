import XCTest
@testable import MLXCore

final class ChatToolPreferencesTests: XCTestCase {
    func testNewPreferencesInheritGlobalDefaultsLive() {
        var session = ChatSession()
        session.toolPreferences = ChatToolPreferences()
        let first = ChatToolDefaults(toolsEnabled: true, mcpEnabled: false, disabledTools: ["shell"])
        let second = ChatToolDefaults(toolsEnabled: false, mcpEnabled: true, disabledTools: ["browse"])
        XCTAssertEqual(session.effectiveToolPreferences(defaults: first), first)
        XCTAssertEqual(session.effectiveToolPreferences(defaults: second), second)
        XCTAssertFalse(session.isPlainChat)
    }

    func testLegacyFlagsDoNotAcquireGlobalCapabilities() {
        let global = ChatToolDefaults(toolsEnabled: true, mcpEnabled: true, disabledTools: [])
        for tools in [false, true] {
            for mcp in [false, true] {
                var session = ChatSession()
                session.mode = tools ? .agent : .chat
                session.useMCP = mcp
                session.disabledTools = ["shell", "future_tool"]
                XCTAssertEqual(session.effectiveToolPreferences(defaults: global),
                               ChatToolDefaults(toolsEnabled: tools, mcpEnabled: mcp,
                                                disabledTools: ["shell", "future_tool"]))
            }
        }
    }

    func testPlainChatRoundTripDoesNotDiscardLegacyChoices() throws {
        var session = ChatSession()
        session.mode = .agent
        session.useMCP = false
        session.disabledTools = ["shell"]
        session.toolPreferences = ChatToolPreferences(followsDefaults: false, plainChat: true)
        let stored = try JSONEncoder().encode(session)
        var restored = try JSONDecoder().decode(ChatSession.self, from: stored)
        XCTAssertTrue(restored.isPlainChat)
        restored.toolPreferences?.plainChat = false
        let global = ChatToolDefaults(toolsEnabled: false, mcpEnabled: true)
        XCTAssertEqual(restored.effectiveToolPreferences(defaults: global),
                       ChatToolDefaults(toolsEnabled: true, mcpEnabled: false, disabledTools: ["shell"]))
    }

    func testOldJSONDoesNotOptIntoGlobalDefaults() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","title":"Old chat",
         "messages":[],"createdAt":0,"updatedAt":0,"mode":"chat","useMCP":false,
         "disabledTools":["shell"]}
        """
        let session = try JSONDecoder().decode(ChatSession.self, from: Data(json.utf8))
        XCTAssertNil(session.toolPreferences)
        XCTAssertFalse(session.isPlainChat)
        XCTAssertEqual(session.effectiveToolPreferences(defaults: .init(toolsEnabled: true, mcpEnabled: true)),
                       .init(toolsEnabled: false, mcpEnabled: false, disabledTools: ["shell"]))
    }

    func testInheritanceAndUnknownDisabledNamesSurviveRoundTrip() throws {
        var session = ChatSession()
        session.toolPreferences = .init(plainChat: true)
        let restored = try JSONDecoder().decode(ChatSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(restored.toolPreferences, session.toolPreferences)
        let defaults = ChatToolDefaults(toolsEnabled: true, mcpEnabled: true,
                                        disabledTools: ["shell", "future_tool"])
        XCTAssertEqual(try JSONDecoder().decode(ChatToolDefaults.self, from: JSONEncoder().encode(defaults)), defaults)
    }

    func testUpgradeDefaultsOnlyMigrateExistingMCPChoice() {
        XCTAssertEqual(ChatToolDefaults.restored(from: nil, legacyMCPEnabled: false), .init())
        XCTAssertEqual(ChatToolDefaults.restored(from: nil, legacyMCPEnabled: true),
                       .init(toolsEnabled: false, mcpEnabled: true))
    }

    func testDamagedNewDefaultsDoNotReviveALegacyMCPGrant() {
        XCTAssertEqual(ChatToolDefaults.restored(from: Data("broken".utf8), legacyMCPEnabled: true), .init())
    }

    func testPersistedDefaultsOutrankLegacyMCPValue() throws {
        let defaults = ChatToolDefaults(toolsEnabled: true, mcpEnabled: false, disabledTools: ["shell"])
        XCTAssertEqual(ChatToolDefaults.restored(from: try JSONEncoder().encode(defaults),
                                                legacyMCPEnabled: true), defaults)
    }

    func testMissingPreferenceFieldsDecodeConservatively() throws {
        XCTAssertEqual(try JSONDecoder().decode(ChatToolDefaults.self, from: Data("{}".utf8)), .init())
        XCTAssertEqual(try JSONDecoder().decode(ChatToolPreferences.self, from: Data("{}".utf8)), .init())
    }

    func testGlobalDisabledToolsSubtractFromAgentCapabilities() {
        var agent = Agent(name: "Researcher", brief: "", systemPrompt: "Research carefully.")
        agent.capabilities.tools = true
        agent.capabilities.web = true
        let defaults = AppDefaultsSnapshot(disabledTools: [.shell, .browse])
        let result = AgentResolution.resolve(agent: agent, defaults: defaults)
        XCTAssertFalse(result.tools.contains(.shell))
        XCTAssertFalse(result.tools.contains(.browse))
        XCTAssertTrue(result.tools.contains(.webSearch))
        XCTAssertTrue(result.toolsEnabled)
    }

    func testPlainChatOverridesAgentToolsButPreservesPersonaAndThinking() {
        var agent = Agent(name: "Coder", brief: "", systemPrompt: "Keep this persona.")
        agent.capabilities.tools = true
        agent.capabilities.mcp = true
        agent.enableThinking = true
        agent.autoApproveTools = false
        agent.modelPath = "/models/pinned"
        let result = AgentResolution.resolve(agent: agent,
            defaults: AppDefaultsSnapshot(toolsEnabled: true, mcpEnabled: true, plainChat: true))
        XCTAssertTrue(result.plainChat)
        XCTAssertTrue(result.tools.isEmpty)
        XCTAssertFalse(result.toolsEnabled)
        XCTAssertFalse(result.mcpEnabled)
        XCTAssertFalse(result.autoApprove)
        XCTAssertTrue(result.thinkingEnabled)
        XCTAssertEqual(result.agentId, agent.id)
        XCTAssertEqual(result.systemPromptPrefix, "Keep this persona.\n\n")
        XCTAssertEqual(result.modelPath, "/models/pinned")
    }

    func testPlainChatAlsoSuppressesAppleAndDocumentSearchTools() {
        let result = AgentResolution.resolve(agent: nil,
            defaults: AppDefaultsSnapshot(toolsEnabled: true, mcpEnabled: true,
                                          appleModel: true, plainChat: true))
        XCTAssertTrue(result.plainChat)
        XCTAssertTrue(result.tools.isEmpty)
        XCTAssertFalse(result.toolsEnabled)
        XCTAssertFalse(result.mcpEnabled)
        XCTAssertFalse(result.thinkingEnabled)
    }

    func testPlainChatOffPreservesAgentCapabilityOwnership() {
        var agent = Agent(name: "Coder", brief: "", systemPrompt: "")
        agent.capabilities.tools = true
        agent.capabilities.mcp = true
        let result = AgentResolution.resolve(agent: agent, defaults: .init())
        XCTAssertFalse(result.plainChat)
        XCTAssertTrue(result.toolsEnabled)
        XCTAssertTrue(result.mcpEnabled)
        XCTAssertFalse(result.autoApprove)
    }
}
