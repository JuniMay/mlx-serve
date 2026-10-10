import Foundation

struct ChatToolDefaults: Codable, Equatable, Sendable {
    var toolsEnabled: Bool = false
    var mcpEnabled: Bool = false
    var disabledTools: [String] = []

    init(toolsEnabled: Bool = false, mcpEnabled: Bool = false, disabledTools: [String] = []) {
        self.toolsEnabled = toolsEnabled
        self.mcpEnabled = mcpEnabled
        self.disabledTools = disabledTools
    }

    private enum CodingKeys: String, CodingKey { case toolsEnabled, mcpEnabled, disabledTools }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        toolsEnabled = try values.decodeIfPresent(Bool.self, forKey: .toolsEnabled) ?? false
        mcpEnabled = try values.decodeIfPresent(Bool.self, forKey: .mcpEnabled) ?? false
        disabledTools = try values.decodeIfPresent([String].self, forKey: .disabledTools) ?? []
    }

    static func restored(from data: Data?, legacyMCPEnabled: Bool) -> Self {
        guard let data else { return Self(mcpEnabled: legacyMCPEnabled) }
        return (try? JSONDecoder().decode(Self.self, from: data)) ?? Self()
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        restored(from: defaults.data(forKey: "chatToolDefaults"),
                 legacyMCPEnabled: defaults.bool(forKey: "mcpMode"))
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: "chatToolDefaults")
        }
    }
}

struct ChatToolPreferences: Codable, Equatable, Sendable {
    var followsDefaults: Bool = true
    var plainChat: Bool = false
    var toolsEnabled: Bool?
    var mcpEnabled: Bool?

    init(followsDefaults: Bool = true, plainChat: Bool = false,
         toolsEnabled: Bool? = nil, mcpEnabled: Bool? = nil) {
        self.followsDefaults = followsDefaults
        self.plainChat = plainChat
        self.toolsEnabled = toolsEnabled
        self.mcpEnabled = mcpEnabled
    }

    private enum CodingKeys: String, CodingKey { case followsDefaults, plainChat, toolsEnabled, mcpEnabled }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        followsDefaults = try values.decodeIfPresent(Bool.self, forKey: .followsDefaults) ?? true
        plainChat = try values.decodeIfPresent(Bool.self, forKey: .plainChat) ?? false
        toolsEnabled = try values.decodeIfPresent(Bool.self, forKey: .toolsEnabled)
        mcpEnabled = try values.decodeIfPresent(Bool.self, forKey: .mcpEnabled)
    }

    /// Conversation switches can remove access that an agent owns, never grant it.
    func applying(to resolved: ResolvedAgentSettings) -> ResolvedAgentSettings {
        var result = resolved
        if toolsEnabled == false {
            result.toolsEnabled = false
            result.tools = []
        }
        if mcpEnabled == false { result.mcpEnabled = false }
        return result
    }
}

extension ChatSession {
    var isPlainChat: Bool { toolPreferences?.plainChat ?? false }

    /// Legacy conversations keep their saved choices until they explicitly opt in.
    func effectiveToolPreferences(defaults: ChatToolDefaults) -> ChatToolDefaults {
        var result = toolPreferences?.followsDefaults == true ? defaults
            : ChatToolDefaults(toolsEnabled: mode == .agent, mcpEnabled: useMCP,
                               disabledTools: disabledTools)
        if let tools = toolPreferences?.toolsEnabled { result.toolsEnabled = tools }
        if let mcp = toolPreferences?.mcpEnabled { result.mcpEnabled = mcp }
        return result
    }
}
