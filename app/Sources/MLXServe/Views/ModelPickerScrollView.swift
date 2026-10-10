import SwiftUI

struct ModelPickerScrollView<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var contentHeight: CGFloat = 72

    var body: some View {
        ScrollView {
            content
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        // A popover may still propose the previous page's compact height.
        .frame(height: min(max(contentHeight, 72), 300))
    }
}
