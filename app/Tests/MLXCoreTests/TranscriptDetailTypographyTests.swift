import AppKit
import SwiftUI
import XCTest
@testable import MLXCore

@MainActor
final class TranscriptDetailTypographyTests: XCTestCase {
    func testThinkingAndReaderTextMatchConversationSizeAndSpacing() {
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
                let reference = Text(verbatim: text)
                    .font(.system(size: size.proseSize))
                    .lineSpacing(ChatMetrics.userLineSpacing)
                let expected = measured(reference, width: width)
                for streaming in [false, true] {
                    var message = ChatMessage(role: .assistant, content: "", reasoningContent: text)
                    message.isStreaming = streaming
                    let actual = measured(MessageBubble(message: message).reasoningText(text), width: width)
                    XCTAssertEqual(actual.height, expected.height, accuracy: 1,
                                   "\(size), streaming: \(streaming)")
                }
            }
        }
    }

    private func measured<V: View>(_ view: V, width: CGFloat) -> CGSize {
        NSHostingView(rootView: view.frame(width: width).fixedSize(horizontal: false, vertical: true)).fittingSize
    }
}
