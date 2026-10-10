import XCTest
@testable import MLXCore

final class ModelThinkingPreferencesTests: XCTestCase {
    private let off = ModelThinkingPreference(enabled: false, effort: .low)
    private let high = ModelThinkingPreference(enabled: true, effort: .high)

    func testThinkingPreferenceFollowsRequestSelectionWhenAgentHasAnotherModel() {
        var agent = Agent(name: "Reasoner", brief: "", systemPrompt: "")
        agent.modelPath = "/models/agent"
        let resolved = AgentResolution.resolve(agent: agent, defaults: AppDefaultsSnapshot())
        let config = ChatTurnEngine.TurnConfig.from(resolved)
        let selectedPath = "/models/dock"
        let preferences = ModelThinkingPreferences(values: [
            "/models/agent": high, selectedPath: off, "lan:qwen@mac": off
        ])

        for lanID: String? in [nil, "qwen@mac"] {
            let requestSelection = ChatModelSelection.tag(
                localPath: config.modelPath ?? selectedPath, lanChatModelId: lanID)
            let thinkingSelection = ModelThinkingPreferences.modelID(selectedPath: selectedPath,
                lanID: lanID, apple: false)
            XCTAssertEqual(thinkingSelection, requestSelection)
            XCTAssertEqual(preferences.preference(for: thinkingSelection, fallback: high), off)
        }
    }

    func testSavedDefaultsDoNotOverrideAgentThinkingAndBudget() {
        let preferences = ModelThinkingPreferences(values: ["/models/a": off])
        let preference = preferences.preference(for: "/models/a", fallback: high)
        var agent = Agent(name: "Reasoner", brief: "", systemPrompt: "")
        agent.enableThinking = true
        agent.reasoningBudget = 8192
        let resolved = AgentResolution.resolve(agent: agent,
            defaults: AppDefaultsSnapshot(thinkingEnabled: preference.enabled, reasoningEffort: preference.effort))
        XCTAssertTrue(resolved.thinkingEnabled)
        XCTAssertEqual(resolved.reasoningBudgetOverride, 8192)
    }

    func testEachModelRestoresItsOwnPreferenceAcrossConversations() {
        let preferences = ModelThinkingPreferences(values: ["/models/a": high, "lan:b@mac": off])
        XCTAssertEqual(preferences.preference(for: "/models/a", fallback: off), high)
        XCTAssertEqual(preferences.preference(for: "lan:b@mac", fallback: high), off)
        XCTAssertEqual(preferences.preference(for: "/models/unseen", fallback: high), high)
    }

    func testRemovingSavedModelRestoresConversationFallback() {
        var preferences = ModelThinkingPreferences(values: ["/models/a": high])
        XCTAssertEqual(preferences.preference(for: "/models/a", fallback: off), high)
        preferences.values.removeValue(forKey: "/models/a")
        XCTAssertEqual(preferences.preference(for: "/models/a", fallback: off), off)
    }

    func testSavedValuesSurviveRelaunchAndCanBeResetTogether() throws {
        let suite = "ModelThinkingPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ModelThinkingPreferences(values: ["/models/a": high, "lan:b@mac": off])
        preferences.save(to: defaults)
        let restored = ModelThinkingPreferences.load(from: defaults)
        XCTAssertEqual(restored, preferences)
        XCTAssertEqual(restored.preference(for: "/models/a", fallback: off), high)
        ModelThinkingPreferences().save(to: defaults)
        XCTAssertTrue(ModelThinkingPreferences.load(from: defaults).values.isEmpty)
    }

    func testDamagedStoreFallsBackWithoutOverwritingConversationChoice() throws {
        let suite = "ModelThinkingPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("invalid".utf8), forKey: "modelThinkingPreferences")
        XCTAssertEqual(ModelThinkingPreferences.load(from: defaults)
            .preference(for: "/models/a", fallback: high), high)
    }
}
