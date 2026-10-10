import SwiftUI

/// Model capabilities supply controls to the permanent interaction composer.
struct MediaInteractionConfiguration {
    let placeholder: String
    let notice: String?
    let hasAttachments: Bool
    let attachmentCount: Int
    let isRunning: Bool
    let canSubmit: Bool
    let submit: (MediaInteractionSubmission) -> Void
    let attachments: AnyView
    let parameters: AnyView
    let accessories: AnyView
}

struct MediaInteractionPreferenceKey: PreferenceKey {
    static var defaultValue: MediaInteractionConfiguration? { nil }

    static func reduce(value: inout MediaInteractionConfiguration?,
                       nextValue: () -> MediaInteractionConfiguration?) {
        if let next = nextValue() { value = next }
    }
}

struct MediaInteractionControls<Attachments: View, Parameters: View, PromptActions: View>: View {
    let placeholder: String
    var notice: String? = nil
    var hasAttachments = false
    var attachmentCount = 0
    let isRunning: Bool
    let canSubmit: Bool
    let submit: (MediaInteractionSubmission) -> Void
    @ViewBuilder var attachments: Attachments
    @ViewBuilder var parameters: Parameters
    @ViewBuilder var promptActions: PromptActions

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .preference(key: MediaInteractionPreferenceKey.self, value:
                MediaInteractionConfiguration(
                    placeholder: placeholder, notice: notice,
                    hasAttachments: hasAttachments, attachmentCount: attachmentCount,
                    isRunning: isRunning, canSubmit: canSubmit,
                    submit: submit,
                    attachments: AnyView(attachments), parameters: AnyView(parameters),
                    accessories: AnyView(promptActions)))
    }
}
