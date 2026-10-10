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
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}

private struct TranscriptDisclosureButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isHovered || configuration.isPressed ? Color.primary : Color.secondary)
    }
}

struct TranscriptDetailPanel<Header: View, Content: View>: View {
    let isExpanded: Bool
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, AppLayout.contentInset)
                .padding(.vertical, AppLayout.rowSpacing)
            if isExpanded {
                Divider().padding(.horizontal, AppLayout.contentInset)
                content
            }
        }
        .background {
            if isExpanded {
                RoundedRectangle(cornerRadius: AppLayout.surfaceRadius, style: .continuous)
                    .fill(.quaternary.opacity(0.5))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppLayout.surfaceRadius, style: .continuous))
        .transaction { $0.animation = nil }
    }
}

extension View {
    func transcriptDetailText(monospaced: Bool = false) -> some View {
        font(.system(size: ChatMetrics.transcriptFontSize, design: monospaced ? .monospaced : .default))
            .lineSpacing(ChatMetrics.userLineSpacing)
    }
}
