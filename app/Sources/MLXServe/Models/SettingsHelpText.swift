import Foundation

struct SettingsHelpText {
    let caption: String
    let details: String?

    init(explainer: String, summary: String? = nil) {
        let trimmedSummary = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedSummary.isEmpty,
           trimmedSummary != explainer.trimmingCharacters(in: .whitespacesAndNewlines) {
            caption = trimmedSummary
            details = explainer
        } else {
            caption = explainer
            details = nil
        }
    }

    // Collapsing the details must not remove their vocabulary from search.
    var searchText: [String] {
        if let details { return [caption, details] }
        return [caption]
    }
}
