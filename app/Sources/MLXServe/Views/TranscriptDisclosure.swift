import SwiftUI

struct TranscriptDisclosureButton<Label: View>: View {
    let isExpanded: Bool
    let action: () -> Void
    @ViewBuilder var label: Label
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppLayout.labelSpacing) {
                label
                Image(systemName: "chevron.right")
                    .font(.system(size: ChatMetrics.transcriptFontSize - 3, weight: .medium))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .font(.system(size: ChatMetrics.transcriptFontSize))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(TranscriptDisclosureButtonStyle(isHovered: isHovered))
        .onHover { isHovered = $0 }
    }
}

private struct TranscriptDisclosureButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isHovered || configuration.isPressed ? Color.primary : Color.secondary)
    }
}

struct TranscriptDetailSurface<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(AppLayout.contentInset)
            .background(.quaternary.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: AppLayout.surfaceRadius, style: .continuous))
    }
}

extension View {
    func transcriptDetailText(monospaced: Bool = false) -> some View {
        font(.system(size: ChatMetrics.transcriptFontSize, design: monospaced ? .monospaced : .default))
            .lineSpacing(ChatMetrics.userLineSpacing)
    }
}
