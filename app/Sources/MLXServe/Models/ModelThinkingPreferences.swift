import Foundation

struct ModelThinkingPreference: Codable, Equatable, Sendable {
    var enabled: Bool
    var effort: ReasoningEffort
}

struct ModelThinkingPreferences: Codable, Equatable, Sendable {
    var values: [String: ModelThinkingPreference] = [:]

    static func modelID(selectedPath: String, lanID: String?, apple: Bool) -> String {
        ChatModelSelection.tag(localPath: selectedPath, lanChatModelId: lanID, apple: apple)
    }

    func preference(for modelID: String, fallback: ModelThinkingPreference) -> ModelThinkingPreference {
        values[modelID] ?? fallback
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: "modelThinkingPreferences") else { return Self() }
        return (try? JSONDecoder().decode(Self.self, from: data)) ?? Self()
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: "modelThinkingPreferences")
    }
}
