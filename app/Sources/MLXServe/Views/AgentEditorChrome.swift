import SwiftUI

/// The Agents editor's geometry — one source of truth for numbers that must
/// agree across independently-written sections.
enum AgentEditorMetrics {
    /// Column edge → content.
    static let contentPadding = AppLayout.pageInset

    /// The reading measure (cf. `ChatMetrics.contentMaxWidth`).
    static let contentMaxWidth: CGFloat = 760

    /// Between one section and the next.
    static let sectionSpacing = AppLayout.sectionSpacing
    /// Label → the thing it names. Strictly less than `sectionSpacing`.
    static let labelSpacing = AppLayout.labelSpacing

    /// Additional inset inside the system group box.
    static let cardPadding = AppLayout.labelSpacing
    /// Between rows inside one card.
    static let cardSpacing = AppLayout.rowSpacing

    static let wellRadius = AppLayout.textEditorRadius
    static let wellPadding = AppLayout.labelSpacing

    /// The prompt editor's floor — the one field you write paragraphs in.
    static let promptMinHeight: CGFloat = 132

    static let avatarSize: CGFloat = 36
}

// MARK: - Surfaces

extension View {
    /// Text entry uses the system text background in either appearance.
    func agentWell() -> some View {
        background(RoundedRectangle(cornerRadius: AgentEditorMetrics.wellRadius,
                                    style: .continuous)
            .fill(Color(.textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: AgentEditorMetrics.wellRadius,
                                      style: .continuous)
                .strokeBorder(Color(.separatorColor), lineWidth: 0.5))
    }
}

// MARK: - Structure

/// A section: its title, then whatever it titles.
struct AgentSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentEditorMetrics.labelSpacing) {
            Text(L10n.text(title))
                .font(.app(.headline))
                .foregroundStyle(.primary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A card — the surface a group of related controls sits on.
struct AgentCard<Content: View>: View {
    var spacing: CGFloat = AgentEditorMetrics.cardSpacing
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat = AgentEditorMetrics.cardSpacing,
         @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: spacing) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AgentEditorMetrics.cardPadding)
        }
    }
}

/// A labelled field with the system text-field treatment.
struct AgentLabeledField<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgentEditorMetrics.labelSpacing) {
            Text(L10n.text(label))
                .font(.app(.headline))
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(Text(L10n.text(label)))
        }
    }
}

/// One row inside a card: what it is on the left, what it's set to on the
/// right, and the sentence explaining it underneath.
struct AgentEditorRow<Trailing: View>: View {
    let title: String
    var caption: String?
    /// Baseline for a row whose trailing side is a line of text or one control;
    /// `.center` when it is a STACK (a slider over its end labels), where
    /// baseline-aligning the title to the slider's first text lifts it clear
    /// off the row.
    var alignment: VerticalAlignment = .firstTextBaseline
    @ViewBuilder let trailing: () -> Trailing

    init(_ title: String, caption: String? = nil,
         alignment: VerticalAlignment = .firstTextBaseline,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.caption = caption
        self.alignment = alignment
        self.trailing = trailing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppLayout.labelSpacing) {
            HStack(alignment: alignment, spacing: AppLayout.rowSpacing) {
                Text(L10n.text(title))
                    .font(.app(.body))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                trailing()
            }
            if let caption {
                Text(L10n.text(caption))
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Controls

/// A secondary action on the adjacent field, such as "Write it for me".
struct AgentPillButton: View {
    let title: String
    let systemImage: String
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppLayout.labelSpacing) {
                if isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                }
                Text(L10n.text(title))
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
