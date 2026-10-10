import SwiftUI
import AppKit

enum TranscriptDetailSizing {
    static let inlineMaximumHeight: CGFloat = 240

    static func maximumHeight(enlarged: Bool, windowHeight: CGFloat) -> CGFloat {
        enlarged ? max(inlineMaximumHeight, min(640, windowHeight - 160)) : inlineMaximumHeight
    }

    @MainActor static func maximumHeight(enlarged: Bool) -> CGFloat {
        maximumHeight(enlarged: enlarged, windowHeight: NSApp.keyWindow?.contentLayoutRect.height ?? 800)
    }
}

struct TranscriptDetailViewport<Content: View>: View {
    var followsTail = false
    var maximumHeight = TranscriptDetailSizing.inlineMaximumHeight
    @ViewBuilder var content: Content
    @State private var contentHeight = TranscriptDetailSizing.inlineMaximumHeight
    @State private var isAtBottom = true

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) {
                    ceil($0.size.height)
                } action: { contentHeight = $0 }
        }
        .frame(height: min(maximumHeight, contentHeight))
        .scrollIndicators(.automatic)
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(followsTail ? .bottom : .top, for: .initialOffset)
        .defaultScrollAnchor(followsTail && isAtBottom ? .bottom : nil, for: .sizeChanges)
        .onScrollGeometryChange(for: CGPoint.self) {
            CGPoint(x: $0.contentOffset.y,
                    y: max(0, $0.contentSize.height - $0.containerSize.height))
        } action: { old, new in
            // Content growth alone must not unpin a reader already following the tail.
            if old.x != new.x { isAtBottom = new.x >= new.y - 8 }
        }
    }
}

struct TranscriptDetailActions: View {
    let textToCopy: String
    @Binding var isEnlarged: Bool

    var body: some View {
        HStack(spacing: AppLayout.rowSpacing) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(textToCopy, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy")
            .accessibilityLabel("Copy")

            Button { isEnlarged.toggle() } label: {
                Image(systemName: isEnlarged ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            .help(isEnlarged ? "Reduce details" : "Enlarge details")
            .accessibilityLabel(isEnlarged ? "Reduce details" : "Enlarge details")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .foregroundStyle(.secondary)
    }
}
