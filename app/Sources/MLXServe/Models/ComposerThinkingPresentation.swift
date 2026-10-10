enum ComposerThinkingPresentation {
    static func summary(isOn: Bool, effort: ReasoningEffort,
                        isExternalBridge: Bool, lockedBy: String?) -> String {
        guard isOn else { return "Off" }
        guard !isExternalBridge, lockedBy == nil else { return "Thinking" }
        return effort.label
    }
}
