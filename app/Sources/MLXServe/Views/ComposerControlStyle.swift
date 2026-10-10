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
    func composerCapsule() -> some View {
        controlSize(.regular)
            .glassEffect(.regular, in: .capsule)
    }
}
