import AppKit
import SwiftUI
import XCTest
@testable import MLXCore

@MainActor
final class TranscriptDetailTypographyTests: XCTestCase {
    func testLongThinkingUsesOneReadOnlyNativeScrollView() {
        let source = String(repeating: "A complete thought remains selectable.\n", count: 4_000)
        let message = ChatMessage(role: .assistant, content: "", reasoningContent: source)
        let hosting = NSHostingView(rootView: MessageBubble(message: message).reasoningText(source)
            .frame(width: 600, height: 240))
        hosting.layoutSubtreeIfNeeded()

        let scrolls: [NSScrollView] = descendants(of: hosting)
        XCTAssertEqual(scrolls.count, 1, "Thinking should use native viewport layout instead of measuring the whole SwiftUI Text.")
        guard let scroll = scrolls.first, let text = scroll.documentView as? NSTextView else {
            return XCTFail("The reasoning reader must expose a native selectable text view.")
        }
        XCTAssertEqual(text.string, source)
        XCTAssertFalse(text.isEditable)
        XCTAssertTrue(text.isSelectable)
        XCTAssertTrue(scroll.hasVerticalScroller)
        XCTAssertFalse(scroll.hasHorizontalScroller)
        XCTAssertTrue(scroll.autohidesScrollers)
        XCTAssertEqual(scroll.scrollerStyle, NSScroller.preferredScrollerStyle)
        XCTAssertNotNil(text.textLayoutManager)
        XCTAssertLessThanOrEqual(scroll.frame.height, 240)
    }

    private func descendants<T: NSView>(of view: NSView) -> [T] {
        view.subviews.flatMap { child in
            (child as? T).map { [$0] } ?? []
        } + view.subviews.flatMap { descendants(of: $0) as [T] }
    }

    func testThinkingTextMatchesConversationSizeAndSpacing() {
        let key = InterfacePrefKey.textSize
        let original = UserDefaults.standard.object(forKey: key)
        defer {
            if let original { UserDefaults.standard.set(original, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        let samples: [(String, CGFloat)] = [
            ("Thinking should read like the conversation.\nA second line tests the line spacing.", 600),
            ("A longer thought wraps across the same narrow reading column as the conversation.\n\nA new paragraph follows. 思考内容也使用相同字号。", 230),
        ]
        for size in ChatTextSize.allCases {
            UserDefaults.standard.set(size.rawValue, forKey: key)
            for (text, width) in samples {
                for streaming in [false, true] {
                    var message = ChatMessage(role: .assistant, content: "", reasoningContent: text)
                    message.isStreaming = streaming
                    let hosting = NSHostingView(rootView: MessageBubble(message: message).reasoningText(text)
                        .frame(width: width))
                    hosting.layoutSubtreeIfNeeded()
                    let views: [NSTextView] = descendants(of: hosting)
                    guard let view = views.first, let storage = view.textStorage else {
                        return XCTFail("The native reasoning text is missing.")
                    }
                    let font = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
                    let paragraph = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
                    XCTAssertEqual(font?.pointSize, size.proseSize)
                    XCTAssertEqual(paragraph?.lineSpacing, ChatMetrics.userLineSpacing)
                    XCTAssertEqual(view.string, text)
                }
            }
        }
    }

}
