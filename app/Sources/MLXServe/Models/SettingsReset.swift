import Foundation

/// One field a section's "Reset" restores.
///
/// The `name` is the `ServerOptions` stored-property label; `apply` is what
/// actually runs. They're checked against each other by
/// `SettingsSectionResetTests` — the name feeds a reflection guard proving the
/// section→fields map covers every field exactly once, and a second test proves
/// the closure really resets the field its name claims.
struct SettingsFieldReset {
    let name: String
    let apply: (inout ServerOptions, ServerOptions) -> Void
}

/// Each active option belongs to one reset scope. Dormant connection data is preserved.
enum SettingsReset {

    /// Fields restored when `category`'s Reset button is pressed. Empty for
    /// sections with nothing of their own to reset.
    static func fields(for category: SettingsCategory) -> [SettingsFieldReset] {
        switch category {
        case .general, .modelFolders, .about, .appearance, .providers, .tools:
            return []

        case .server:
            return [
                f("host") { $0.host = $1.host },
                f("port") { $0.port = $1.port },
                f("ctxSize") { $0.ctxSize = $1.ctxSize },
                f("noVision") { $0.noVision = $1.noVision },
                f("logLevel") { $0.logLevel = $1.logLevel },
                f("logToFile") { $0.logToFile = $1.logToFile },
                // No UI row of its own (CLI-only), but it IS a server flag —
                // some section has to own it or it can never be restored.
                f("requestTimeout") { $0.requestTimeout = $1.requestTimeout },
                f("enableMetrics") { $0.enableMetrics = $1.enableMetrics },
                f("apiKey") { $0.apiKey = $1.apiKey },
                f("toolAutocorrect") { $0.toolAutocorrect = $1.toolAutocorrect },
            ]

        case .lanSharing:
            return [
                f("lanShareEnabled") { $0.lanShareEnabled = $1.lanShareEnabled },
                f("lanShareAll") { $0.lanShareAll = $1.lanShareAll },
                f("lanSharedModels") { $0.lanSharedModels = $1.lanSharedModels },
                f("lanDiscoverEnabled") { $0.lanDiscoverEnabled = $1.lanDiscoverEnabled },
                f("lanName") { $0.lanName = $1.lanName },
            ]

        case .specDecode:
            return [
                f("enablePLD") { $0.enablePLD = $1.enablePLD },
                f("pldDraftLen") { $0.pldDraftLen = $1.pldDraftLen },
                f("pldKeyLen") { $0.pldKeyLen = $1.pldKeyLen },
                f("enableMTP") { $0.enableMTP = $1.enableMTP },
                f("mtpDepth") { $0.mtpDepth = $1.mtpDepth },
                f("enableDSpark") { $0.enableDSpark = $1.enableDSpark },
                f("llamaMtpDrafts") { $0.llamaMtpDrafts = $1.llamaMtpDrafts },
            ]

        case .memory:
            return [
                f("skipMemPreflight") { $0.skipMemPreflight = $1.skipMemPreflight },
                f("osReserveGiB") { $0.osReserveGiB = $1.osReserveGiB },
                f("maxResidentMemGB") { $0.maxResidentMemGB = $1.maxResidentMemGB },
                f("maxResidentModels") { $0.maxResidentModels = $1.maxResidentModels },
                f("idleEvictSecs") { $0.idleEvictSecs = $1.idleEvictSecs },
                f("pleGpu") { $0.pleGpu = $1.pleGpu },
            ]

        case .cache:
            return [
                f("kvQuant") { $0.kvQuant = $1.kvQuant },
                f("hotPrefixCacheEnabled") { $0.hotPrefixCacheEnabled = $1.hotPrefixCacheEnabled },
                f("prefixCacheEntries") { $0.prefixCacheEntries = $1.prefixCacheEntries },
                f("prefixCacheMem") { $0.prefixCacheMem = $1.prefixCacheMem },
                f("enablePrefixCacheDisk") { $0.enablePrefixCacheDisk = $1.enablePrefixCacheDisk },
                f("prefixCacheDisk") { $0.prefixCacheDisk = $1.prefixCacheDisk },
                f("tokenizeCacheEntries") { $0.tokenizeCacheEntries = $1.tokenizeCacheEntries },
                f("llamaKvQuant") { $0.llamaKvQuant = $1.llamaKvQuant },
                f("llamaCacheEntries") { $0.llamaCacheEntries = $1.llamaCacheEntries },
            ]

        case .performance:
            return [
                f("maxConcurrent") { $0.maxConcurrent = $1.maxConcurrent },
                f("decodeAttnQuantChoice") { $0.decodeAttnQuantChoice = $1.decodeAttnQuantChoice },
                f("anePrefill") { $0.anePrefill = $1.anePrefill },
                f("aneImage") { $0.aneImage = $1.aneImage },
                f("aneVideo") { $0.aneVideo = $1.aneVideo },
                f("aneAudio") { $0.aneAudio = $1.aneAudio },
            ]

        case .engines:
            return [
                f("mlxGguf") { $0.mlxGguf = $1.mlxGguf },
                f("llamaUbatch") { $0.llamaUbatch = $1.llamaUbatch },
                f("ssdStreaming") { $0.ssdStreaming = $1.ssdStreaming },
            ]

        case .requestDefaults:
            return [
                f("defaultMaxTokens") { $0.defaultMaxTokens = $1.defaultMaxTokens },
                f("defaultTemperature") { $0.defaultTemperature = $1.defaultTemperature },
                f("defaultTopP") { $0.defaultTopP = $1.defaultTopP },
                f("defaultTopK") { $0.defaultTopK = $1.defaultTopK },
                f("defaultRepeatPenalty") { $0.defaultRepeatPenalty = $1.defaultRepeatPenalty },
                f("defaultPresencePenalty") { $0.defaultPresencePenalty = $1.defaultPresencePenalty },
                f("defaultReasoningBudget") { $0.defaultReasoningBudget = $1.defaultReasoningBudget },
                // The next three have no row on this screen (thinking lives on
                // the chat toolbar, the per-request spec-decode overrides
                // duplicate the Speculative Decoding toggles) — but they're
                // per-request semantics, so this is their home.
                f("defaultEnableThinking") { $0.defaultEnableThinking = $1.defaultEnableThinking },
                f("perRequestEnablePLD") { $0.perRequestEnablePLD = $1.perRequestEnablePLD },
                f("perRequestEnableDrafter") { $0.perRequestEnableDrafter = $1.perRequestEnableDrafter },
            ]

        case .voice:
            return [
                f("voiceClonePath") { $0.voiceClonePath = $1.voiceClonePath },
                f("voiceCloneEnabled") { $0.voiceCloneEnabled = $1.voiceCloneEnabled },
                f("voiceCloneLabel") { $0.voiceCloneLabel = $1.voiceCloneLabel },
                f("voiceEngine") { $0.voiceEngine = $1.voiceEngine },
                f("kokoroVoice") { $0.kokoroVoice = $1.kokoroVoice },
                f("wakePhrase") { $0.wakePhrase = $1.wakePhrase },
            ]

        case .sandbox:
            return [
                f("sandbox") { $0.sandbox = $1.sandbox },
                // Legacy persisted field, kept in its original reset scope.
                f("toolsOnlyWhenAsked") { $0.toolsOnlyWhenAsked = $1.toolsOnlyWhenAsked },
            ]

        }
    }

    private static func f(_ name: String,
                          _ apply: @escaping (inout ServerOptions, ServerOptions) -> Void) -> SettingsFieldReset {
        SettingsFieldReset(name: name, apply: apply)
    }

    /// Does this section have anything of its own to restore? A Reset button on
    /// a section with no fields would be a button that lies.
    static func isResettable(_ category: SettingsCategory) -> Bool {
        !fields(for: category).isEmpty
    }

    /// Restore one section's fields; every other field is left exactly as it is.
    static func apply(_ category: SettingsCategory, to current: ServerOptions) -> ServerOptions {
        let fresh = ServerOptions()
        var out = current
        for field in fields(for: category) {
            field.apply(&out, fresh)
        }
        return out
    }

    /// Restore active settings while preserving dormant connection data.
    static func applyAll(to current: ServerOptions) -> ServerOptions {
        var reset = ServerOptions.resetToDefaults(preserving: current)
        reset.telegram = current.telegram
        return reset
    }

    /// Apply whatever the sidebar has selected.
    static func apply(_ selection: SettingsSelection, to current: ServerOptions) -> ServerOptions {
        switch selection {
        case .all:                 return applyAll(to: current)
        case .category(let c):     return apply(c, to: current)
        }
    }

    // MARK: - Copy (the scope has to be stated BEFORE anything is wiped)

    static func buttonLabel(_ selection: SettingsSelection) -> String {
        switch selection {
        case .all:               return "Reset Server and Agent Settings…"
        case .category(let c):   return "Reset \(c.sidebarLabel)"
        }
    }

    static func confirmTitle(_ selection: SettingsSelection) -> String {
        switch selection {
        case .all:               return "Reset Server and Agent Settings?"
        case .category(let c):   return "Reset \(c.sidebarLabel) to defaults?"
        }
    }

    static func confirmMessage(_ selection: SettingsSelection) -> String {
        switch selection {
        case .all:
            return "This resets server options, Generation Defaults, Voice, and Agent Sandbox settings across every section. Tools & MCP defaults, startup, appearance, model folders, providers, your workspace folder, and per-model rules are kept. Generation defaults apply to the next request; server options apply after a restart."
        case .category(let c):
            let scope = "This resets only the \(c.sidebarLabel) section. Every other section is left untouched."
            if c == .requestDefaults { return scope + " Generation defaults apply to the next request without a restart. Per-model rules are kept." }
            return scope + " The running server keeps its current flags until you hit Restart Now."
        }
    }
}
