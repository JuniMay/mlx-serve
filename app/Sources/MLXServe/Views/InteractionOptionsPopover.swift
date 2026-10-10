import AppKit
import SwiftUI

/// Model-specific controls stay beside the shared input.
struct InteractionOptionsPopover<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppLayout.sectionSpacing) {
                content
            }
            .frame(width: 420 - 2 * AppLayout.contentInset
                   - NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy), alignment: .leading)
            .padding(AppLayout.contentInset)
        }
        .frame(width: 420)
        .frame(maxHeight: 520)
        .scrollBounceBehavior(.basedOnSize)
    }
}
