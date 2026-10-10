import Foundation

/// The ONE place an agent's overrides meet the app's defaults.
///
/// The rule this file exists to enforce: **a turn site never reads a global
/// setting directly — it reads `ResolvedAgentSettings`.** Same class as the LAN
/// rule (chat routes through `server.chatModelId`, never `modelInfo?.name` at a
/// new surface): a per-surface read is exactly how one surface ends up silently
/// ignoring the agent.
///
/// Pure and `nonisolated` so it's testable with no app instance.
struct AppDefaultsSnapshot: Sendable, Equatable {
    /// The surface's own toggles (chat tab's Tools/MCP/Think, the tray's, a
    /// task's) — what the turn would have used before agents existed.
    var toolsEnabled: Bool = false
    var mcpEnabled: Bool = false
    var thinkingEnabled: Bool = false
    var autoApprove: Bool = false
    /// Full access is the historical default: the whole tool literal is
    /// advertised whenever the loop runs.
    var tools: Set<AgentToolKind> = Set(AgentToolKind.allCases)
    /// Tools this SURFACE has switched off (the chat tab's Tools menu, stored on
    /// the session). Subtractive: it rides here rather than being applied at each
    /// turn site so an agent can't be handed a capability its own settings
    /// forbid, and so no surface can forget to apply it — same reason the whole
    /// resolution is one chokepoint. Empty = today's behaviour, unchanged.
    var disabledTools: Set<AgentToolKind> = []
    var workingDirectory: String?
    /// nil = whatever model is selected right now.
    var modelPath: String?
    var temperature: Double = 0.8
    var maxTokens: Int = 4096
    /// The app's global voice (engine + value).
    var voice: AgentVoice?
    var wakePhrase: String = WakeWord.defaultPhrase
    /// The surface's `reasoning_effort` pick (the brain disc's right-click
    /// menu). Pass-through — agents own their thinking BUDGET instead
    /// (`reasoningBudget`, which outranks effort server-side).
    var reasoningEffort: ReasoningEffort = .low
    /// The turn is answered by Apple's on-device model, which has no thinking
    /// mode and a window the full tool set cannot fit.
    var appleModel: Bool = false
    var plainChat: Bool = false
}

/// Every field decided — no optionals left except the ones that are genuinely
/// "unset" downstream too (a nil working directory, a nil model = current).
struct ResolvedAgentSettings: Sendable, Equatable {
    var agentId: UUID?
    /// The persona, ready to be prepended to the STABLE system-prompt prefix
    /// (never the volatile tail — that re-prefills every turn). Carries its own
    /// trailing blank line, and is "" when there's no agent.
    var systemPromptPrefix: String = ""
    var tools: Set<AgentToolKind> = []
    var toolsEnabled: Bool = false
    var mcpEnabled: Bool = false
    var thinkingEnabled: Bool = false
    var autoApprove: Bool = false
    var workingDirectory: String?
    var modelPath: String?
    var temperature: Double = 0.8
    var maxTokens: Int = 4096
    /// The agent's RAW sampling overrides, nil when it didn't set them.
    ///
    /// Kept alongside the decided values above because the two chat paths have
    /// DIFFERENT defaults (the tool loop's temperature is not plain chat's), so a
    /// decided number handed to `TurnConfig` would silently change one of them for
    /// every user who never makes an agent. nil = "this path's own default".
    var temperatureOverride: Double?
    var maxTokensOverride: Int?
    /// The remaining sampling knobs, raw for the same reason. These have no
    /// decided twin — their app defaults live in `ServerOptions` and are laid
    /// under them by `TurnConfig.requestDefaults(from:)` at request time.
    var topPOverride: Double?
    var topKOverride: Int?
    var repeatPenaltyOverride: Double?
    var presencePenaltyOverride: Double?
    var reasoningBudgetOverride: Int?
    var voice: AgentVoice?
    /// The AGENT's own voice, nil when it didn't pick one.
    ///
    /// Same reason the sampling overrides are kept raw: the synthesizer re-reads
    /// the user's voice settings once per utterance, so publishing the
    /// global-fallback value would PIN the turn's voice and stop a mid-answer
    /// Settings change from applying. nil = follow Settings, live.
    var voiceOverride: AgentVoice?
    var wakePhrase: String = WakeWord.defaultPhrase
    var reasoningEffort: ReasoningEffort = .low
    var plainChat: Bool = false
}

enum AgentResolution {

    /// Fold an agent's overrides into the app defaults. `agent == nil` returns
    /// the defaults verbatim — that's the upgrade guarantee, and it has its own
    /// test.
    /// Apply the surface's per-chat switches to an allowed set.
    ///
    /// Per-tool switches subtract capabilities. Folder search has no individual
    /// switch; TurnConfig requires Tools access and an attached folder.
    private static func applying(_ disabled: Set<AgentToolKind>,
                                 to allowed: Set<AgentToolKind>) -> Set<AgentToolKind> {
        guard !disabled.isEmpty else { return allowed }
        return allowed.subtracting(disabled.subtracting([.searchDocuments]))
    }

    nonisolated static func resolve(agent: Agent?, defaults: AppDefaultsSnapshot) -> ResolvedAgentSettings {
        var settings = resolveUnclamped(agent: agent, defaults: defaults)
        if defaults.appleModel { settings = clampedForApple(settings) }
        if defaults.plainChat {
            settings.plainChat = true
            settings.tools = []
            settings.toolsEnabled = false
            settings.mcpEnabled = false
        }
        return settings
    }

    /// Apple's on-device model, clamped at the ONE place a turn's capabilities
    /// are decided: no thinking (the framework has none), no MCP, and browse +
    /// search only — everything else cannot fit its 4k window beside the
    /// history. The surface's own switches still subtract inside that set.
    nonisolated static func clampedForApple(_ s: ResolvedAgentSettings) -> ResolvedAgentSettings {
        var out = s
        out.tools = s.tools.intersection(AppleFoundationChat.allowedTools)
        out.toolsEnabled = s.toolsEnabled && !out.tools.isEmpty
        out.thinkingEnabled = false
        out.mcpEnabled = false
        return out
    }

    private nonisolated static func resolveUnclamped(agent: Agent?, defaults: AppDefaultsSnapshot) -> ResolvedAgentSettings {
        guard let agent else {
            let tools = applying(defaults.disabledTools, to: defaults.tools)
            return ResolvedAgentSettings(
                agentId: nil,
                systemPromptPrefix: "",
                tools: tools,
                toolsEnabled: defaults.toolsEnabled,
                mcpEnabled: defaults.mcpEnabled,
                thinkingEnabled: defaults.thinkingEnabled,
                autoApprove: defaults.autoApprove,
                workingDirectory: defaults.workingDirectory,
                modelPath: defaults.modelPath,
                temperature: defaults.temperature,
                maxTokens: defaults.maxTokens,
                voice: defaults.voice,
                wakePhrase: defaults.wakePhrase,
                reasoningEffort: defaults.reasoningEffort
            )
        }

        // The persona is the prompt TEXT, verbatim — nothing is bolted on here.
        // Brevity is written into the prompt when a model writes it
        // (`AgentWriter.brevityLine`), so it's visible and editable rather than a
        // hidden setting.
        let persona = agent.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        // Folder search requires the resolved Tools switch and an attached index.
        // Conversation switches can subtract from the agent's capabilities.
        let agentTools = agent.capabilities.resolvedTools()
        let capabilityTools = applying(defaults.disabledTools, to: agentTools)

        return ResolvedAgentSettings(
            agentId: agent.id,
            systemPromptPrefix: persona.isEmpty ? "" : persona + "\n\n",
            tools: capabilityTools.union([.searchDocuments]),
            toolsEnabled: !agentTools.isEmpty,
            mcpEnabled: agent.capabilities.mcp,
            thinkingEnabled: agent.enableThinking ?? defaults.thinkingEnabled,
            autoApprove: agent.autoApproveTools ?? defaults.autoApprove,
            workingDirectory: agent.workingDirectory ?? defaults.workingDirectory,
            modelPath: agent.modelPath ?? defaults.modelPath,
            temperature: agent.temperature ?? defaults.temperature,
            maxTokens: agent.maxTokens ?? defaults.maxTokens,
            temperatureOverride: agent.temperature,
            maxTokensOverride: agent.maxTokens,
            topPOverride: agent.topP,
            topKOverride: agent.topK,
            repeatPenaltyOverride: agent.repeatPenalty,
            presencePenaltyOverride: agent.presencePenalty,
            reasoningBudgetOverride: agent.reasoningBudget,
            voice: agent.resolvedVoice ?? defaults.voice,
            voiceOverride: agent.resolvedVoice,
            wakePhrase: agent.wakePhrase.flatMap(WakeWord.normalizePhrase) ?? defaults.wakePhrase,
            reasoningEffort: defaults.reasoningEffort
        )
    }
}
