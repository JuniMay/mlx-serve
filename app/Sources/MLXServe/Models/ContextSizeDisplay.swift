import Foundation

/// Context choices and labels distinguish model limits, memory limits, and the active limit.
enum ContextSizeDisplay {

    /// The context ladder Settings and the per-model sheet both pick from. 0 = Auto.
    static let presets: [Int] = [
        0, 4_096, 6_144, 8_192, 12_288, 16_384, 24_576, 32_768,
        49_152, 65_536, 98_304, 131_072, 196_608, 262_144,
        393_216, 524_288, 786_432, 1_048_576,
    ]

    static func options(modelMaxTokens: Int, currentValue: Int) -> [Int] {
        var values = presets.filter { modelMaxTokens <= 0 || $0 <= modelMaxTokens }
        if currentValue > 0 && !values.contains(currentValue) { values.append(currentValue) }
        return values.sorted()
    }

    /// "Auto" for 0; otherwise a 1024-based K/M abbreviation.
    static func formatTokens(_ n: Int) -> String {
        if n == 0 { return "Auto" }
        if n >= 1_048_576 { return "\(n / 1_048_576)M" }
        if n >= 1024 { return "\(n / 1024)K" }
        return "\(n)"
    }

    /// Shared with the server flag description.
    static let helpText =
        "Maximum prompt and completion tokens. Auto chooses 85% of the memory-safe "
        + "ceiling when the model loads, rounds down to 1,024 tokens, and caps the "
        + "result at the model maximum. That limit stays fixed until the model reloads "
        + "or the server restarts. A positive per-model context setting overrides this "
        + "global choice. Larger contexts use more memory."

    /// The context the RUNNING server settled on, formatted for the pill.
    /// nil until the server has reported a loaded model.
    static func inUseValue(contextLength: Int?) -> String? {
        guard let contextLength, contextLength > 0 else { return nil }
        return formatTokens(contextLength)
    }
}
