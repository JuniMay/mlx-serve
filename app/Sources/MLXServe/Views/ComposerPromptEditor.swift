import SwiftUI

/// Media prompts use the chat editor while retaining their own submission rules.
struct ComposerPromptEditor: View {
    @Binding var text: String
    let placeholder: String
    var selection: Binding<TextSelection?>? = nil
    var focused: Binding<Bool>? = nil
    var maxLines = 8
    var isRunning = false
    var canSubmit = true
    var onSubmit: () -> Void
    var onCancel: () -> Void

    @State private var measuredHeight = ChatMetrics.composerMinHeight
    @State private var isFocused = false

    var body: some View {
        GrowingTextEditor(text: $text, isFocused: focused ?? $isFocused,
                          measuredHeight: $measuredHeight, selection: selection,
                          maxLines: maxLines, isIdle: !isRunning && canSubmit,
                          returnInsertsNewline: true,
                          onSend: onSubmit, onCancel: {
                              guard isRunning else { return false }
                              onCancel()
                              return true
                          })
            .composerTextField(height: measuredHeight, placeholder: text.isEmpty ? placeholder : nil)
    }
}
