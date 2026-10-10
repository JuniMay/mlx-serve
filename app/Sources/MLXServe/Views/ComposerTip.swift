import SwiftUI

/// The native tooltip and accessibility description for a composer control.
struct ComposerTip: Equatable {
    var title: String
    var body: String
    static func attachments(audioSupported: Bool, videoSupported: Bool = false) -> ComposerTip {
        let body: String
        switch (videoSupported, audioSupported) {
        case (true, true): body = "Image, video, PDF or audio — or a folder to ask questions about."
        case (true, false): body = "Image, video or PDF — or a folder to ask questions about."
        case (false, true): body = "Image, PDF or audio — or a folder to ask questions about."
        case (false, false): body = "Image or PDF — or a folder to ask questions about."
        }
        return ComposerTip(title: L10n.text("Attach"), body: L10n.text(body))
    }

    static func thinking(isOn: Bool, lockedBy agent: String? = nil) -> ComposerTip {
        ComposerTip(title: L10n.format("Thinking · %@", state(isOn)),
                    body: agent.map(locked)
                        ?? L10n.text("Open the menu to turn thinking on or off and choose reasoning effort."))
    }

    private static func locked(_ agent: String) -> String {
        L10n.format("Set by the agent %@. Edit the agent to change it.", agent)
    }

    private static func state(_ isOn: Bool) -> String { L10n.text(isOn ? "ON" : "OFF") }
}

extension View {
    func composerTip(_ tip: ComposerTip) -> some View {
        let description = [tip.title, tip.body].joined(separator: "\n")
        return help(description)
            .accessibilityLabel(tip.title)
            .accessibilityHint(tip.body)
    }
}
