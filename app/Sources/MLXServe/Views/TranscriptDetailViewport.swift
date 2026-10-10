import SwiftUI
import AppKit

enum TranscriptDetailSizing {
    static let inlineMaximumHeight: CGFloat = 240

    static func readerSize(in available: CGSize) -> CGSize {
        CGSize(width: max(1, min(760, available.width - 40)),
               height: max(1, min(640, available.height - 80)))
    }
}

struct TranscriptDetailViewport<Content: View>: View {
    var followsTail = false
    @ViewBuilder var content: Content
    @State private var height = TranscriptDetailSizing.inlineMaximumHeight
    @State private var isAtBottom = true

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) {
                    min(TranscriptDetailSizing.inlineMaximumHeight, ceil($0.size.height))
                } action: { height = $0 }
        }
        .frame(height: height)
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

struct TranscriptReaderButton<Content: View>: View {
    let title: String
    let textToCopy: String
    @ViewBuilder var content: Content
    @State private var isPresented = false
    @State private var readerSize = CGSize(width: 760, height: 640)

    var body: some View {
        Button {
            let available = NSApp.keyWindow?.contentLayoutRect.size ?? CGSize(width: 800, height: 720)
            readerSize = TranscriptDetailSizing.readerSize(in: available)
            isPresented = true
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help("Open in Reader")
        .accessibilityLabel("Open in Reader")
        .accessibilityHint(Text(L10n.text(title)))
        .sheet(isPresented: $isPresented) {
            TranscriptDetailReader(title: title, textToCopy: textToCopy, size: readerSize) {
                content
            }
        }
    }
}

private struct TranscriptDetailReader<Content: View>: View {
    let title: String
    let textToCopy: String
    let size: CGSize
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppLayout.rowSpacing) {
                Text(L10n.text(title)).font(.headline).lineLimit(1)
                Spacer(minLength: AppLayout.compactSpacing)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(textToCopy, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .controlSize(.small)
            .padding(.horizontal, AppLayout.pageInset)
            .padding(.vertical, AppLayout.rowSpacing)
            Divider()
            ScrollView {
                content
                    .transcriptDetailText()
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppLayout.contentInset)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
