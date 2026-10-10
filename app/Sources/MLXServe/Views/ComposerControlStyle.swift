import SwiftUI

/// Shared label geometry keeps native circular buttons the same diameter.
struct ComposerControlSymbol: View {
    let name: String

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .medium))
            .frame(width: 20, height: 20)
    }
}

enum ComposerControlMetrics {
    static let height: CGFloat = 30
    static let horizontalPadding: CGFloat = 12
    static let spacing: CGFloat = 10
}

struct ComposerControlsRow<Leading: View, Model: View, Actions: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var model: Model
    @ViewBuilder var actions: Actions

    var body: some View {
        GlassEffectContainer(spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: ComposerControlMetrics.spacing) {
                    leading
                    Spacer(minLength: ComposerControlMetrics.spacing)
                    model
                    actions
                }
                VStack(alignment: .leading, spacing: ComposerControlMetrics.spacing) {
                    model
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: ComposerControlMetrics.spacing) {
                            leading
                            Spacer(minLength: ComposerControlMetrics.spacing)
                            actions
                        }
                        VStack(alignment: .leading, spacing: ComposerControlMetrics.spacing) {
                            leading
                            HStack {
                                Spacer(minLength: 0)
                                actions
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ComposerActionButton: View {
    let isRunning: Bool
    let label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ComposerControlSymbol(name: isRunning ? "stop.fill" : "arrow.up")
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.regular)
        .accessibilityLabel(L10n.text(label))
        .help(L10n.text(label))
    }
}

extension View {
    func composerTextField(height: CGFloat, placeholder: String?, expanded: Bool = false) -> some View {
        frame(height: expanded ? nil : max(ChatMetrics.composerMinHeight, height))
            .frame(minHeight: ChatMetrics.composerMinHeight, maxHeight: expanded ? .infinity : nil)
            .padding(.horizontal, ComposerTextMetrics.fieldHorizontalPadding)
            .overlay(alignment: .topLeading) {
                if let placeholder {
                    Text(L10n.text(placeholder))
                        .font(.app(.body))
                        .foregroundStyle(.secondary)
                        .padding(.leading, ComposerTextMetrics.placeholderLeading)
                        .padding(.top, ComposerTextMetrics.placeholderTop)
                        .allowsHitTesting(false)
                }
            }
    }

    func floatingInputSurface() -> some View {
        padding(AppLayout.contentInset)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: AppLayout.surfaceRadius))
    }

    func composerCapsule() -> some View {
        controlSize(.regular)
            .glassEffect(.regular, in: .capsule)
    }
}
