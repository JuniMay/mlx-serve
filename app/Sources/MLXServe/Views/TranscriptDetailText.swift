import AppKit
import SwiftUI

/// TextKit 2 lays out the visible reasoning while retaining the complete selectable text.
struct TranscriptDetailText: NSViewRepresentable {
    let text: String
    var maximumHeight = TranscriptDetailSizing.inlineMaximumHeight
    var followsTail = false
    var monospaced = false

    final class Coordinator {
        var maximumHeight: CGFloat
        init(maximumHeight: CGFloat) { self.maximumHeight = maximumHeight }
    }

    func makeCoordinator() -> Coordinator { Coordinator(maximumHeight: maximumHeight) }

    private var font: NSFont {
        monospaced ? .monospacedSystemFont(ofSize: ChatMetrics.transcriptFontSize, weight: .regular)
                   : .systemFont(ofSize: ChatMetrics.transcriptFontSize)
    }

    private var attributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = ChatMetrics.userLineSpacing
        return [.font: font, .paragraphStyle: paragraph, .foregroundColor: NSColor.labelColor]
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = NSScroller.preferredScrollerStyle

        let view = NSTextView(usingTextLayoutManager: true)
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.drawsBackground = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainerInset = NSSize(width: AppLayout.contentInset, height: AppLayout.contentInset)
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.lineFragmentPadding = 0
        scroll.documentView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        let changed = view.string != text
        let atBottom = scroll.contentView.bounds.maxY >= view.bounds.maxY - 8
        let firstContent = view.string.isEmpty
        let origin = scroll.contentView.bounds.origin
        let selection = view.selectedRange()
        let styleChanged = view.font != font
        if context.coordinator.maximumHeight != maximumHeight {
            context.coordinator.maximumHeight = maximumHeight
            // TextKit may adjust the clip origin as its viewport grows; retain the reader's place.
            DispatchQueue.main.async { [weak scroll] in
                guard let scroll else { return }
                scroll.layoutSubtreeIfNeeded()
                scroll.contentView.scroll(to: origin)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }

        if changed {
            if !view.string.isEmpty, text.hasPrefix(view.string) {
                let suffix = (text as NSString).substring(from: (view.string as NSString).length)
                view.textStorage?.append(NSAttributedString(string: suffix, attributes: attributes))
            } else {
                view.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes))
            }
        }
        if styleChanged {
            view.textStorage?.addAttributes(attributes, range: NSRange(location: 0, length: (text as NSString).length))
            view.font = font
        }
        if changed {
            if selection.location + selection.length <= (text as NSString).length {
                view.setSelectedRange(selection)
            }
            if followsTail && (firstContent || atBottom) {
                view.scrollRangeToVisible(NSRange(location: (text as NSString).length, length: 0))
            } else {
                scroll.contentView.scroll(to: origin)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        let width = max(1, proposal.width ?? 600)
        let inset = AppLayout.contentInset * 2
        // Long documents need a viewport, not a full-document measurement before opening.
        let end = text.index(text.startIndex, offsetBy: 4_096, limitedBy: text.endIndex) ?? text.endIndex
        let prefix = String(text[..<end])
        let height: CGFloat
        if end != text.endIndex {
            height = maximumHeight
        } else {
            let bounds = NSAttributedString(string: prefix, attributes: attributes).boundingRect(
                with: CGSize(width: max(1, width - inset), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading])
            height = min(maximumHeight, max(font.ascender - font.descender, ceil(bounds.height)) + inset)
        }
        return CGSize(width: width, height: height)
    }
}
