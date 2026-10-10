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
}

struct ComposerControlsRow<Leading: View, Model: View, Actions: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var model: Model
    @ViewBuilder var actions: Actions

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    leading
                    Spacer(minLength: 8)
                    model
                    actions
                }
                VStack(alignment: .leading, spacing: 8) {
                    model
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) {
                            leading
                            Spacer(minLength: 8)
                            actions
                        }
                        VStack(alignment: .leading, spacing: 8) {
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
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .controlSize(.regular)
        .accessibilityLabel(L10n.text(label))
        .help(L10n.text(label))
    }
}

extension View {
    func composerTextField(height: CGFloat, placeholder: String?) -> some View {
        frame(height: max(ChatMetrics.composerMinHeight, height))
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
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: AppLayout.surfaceRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppLayout.surfaceRadius, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
    }

    func composerCapsule() -> some View {
        controlSize(.regular)
            .glassEffect(.regular, in: .capsule)
    }
}
