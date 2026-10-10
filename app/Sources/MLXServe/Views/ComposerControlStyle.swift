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

extension View {
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
