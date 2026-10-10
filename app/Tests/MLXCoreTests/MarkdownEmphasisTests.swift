import AppKit
import XCTest
@testable import MLXCore

final class MarkdownEmphasisTests: XCTestCase {
    func testReportedStrongTextRemovesMarkersAndUsesBold() throws {
        for text in [
            "4. Metatheoretic distinctions",
            "Boolean canonicity by reduction fails in B.",
            "DERIVED HERE.",
        ] {
            let rendered = MarkdownText.attributedString(for: "**\(text)**")
            XCTAssertEqual(rendered.string, text)
            let font = try font(at: text, in: rendered)
            XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.bold),
                          "\(rendered.string): \(font.fontName), traits \(font.fontDescriptor.symbolicTraits.rawValue)")
        }
    }

    func testInlineEmphasisCombinesBoldAndItalicWithoutChangingPlainText() throws {
        let rendered = MarkdownText.attributedString(for: "Plain *italic* **bold** ***both***")
        XCTAssertEqual(rendered.string, "Plain italic bold both")
        let plain = try font(at: "Plain", in: rendered).fontDescriptor.symbolicTraits
        XCTAssertFalse(plain.contains(.bold))
        XCTAssertFalse(plain.contains(.italic))
        XCTAssertTrue(try font(at: "italic", in: rendered).fontDescriptor.symbolicTraits.contains(.italic))
        XCTAssertTrue(try font(at: "bold", in: rendered).fontDescriptor.symbolicTraits.contains(.bold))
        let both = try font(at: "both", in: rendered).fontDescriptor.symbolicTraits
        XCTAssertTrue(both.contains(.bold))
        XCTAssertTrue(both.contains(.italic))
    }

    func testHeadingKeepsInlineItalicAlongsideItsHeadingWeight() throws {
        let rendered = MarkdownText.attributedString(for: "## A *careful* heading")
        let italic = try font(at: "careful", in: rendered)
        XCTAssertTrue(italic.fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertTrue(italic.fontDescriptor.symbolicTraits.contains(.italic))
        XCTAssertEqual(italic.pointSize, ChatMetrics.transcriptFontSize + 3)
        let plain = try font(at: "heading", in: rendered)
        XCTAssertTrue(plain.fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertFalse(plain.fontDescriptor.symbolicTraits.contains(.italic))
    }

    func testEscapedMarkersAndCodeKeepTheirLiteralStars() throws {
        let rendered = MarkdownText.attributedString(for: #"\*\*literal\*\* and `**code**`"#)
        XCTAssertEqual(rendered.string, "**literal** and **code**")
        XCTAssertFalse(try font(at: "literal", in: rendered).fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertEqual(try font(at: "code", in: rendered).fontName,
                       NSFont.monospacedSystemFont(ofSize: ChatMetrics.transcriptCodeFontSize, weight: .regular).fontName)
    }

    func testEmphasisKeepsRequestedReadingSize() throws {
        let rendered = MarkdownText.renderInline("Plain *italic* **bold** ***both***", theme: .light, fontSize: 23)
        for word in ["Plain", "italic", "bold", "both"] {
            XCTAssertEqual(try font(at: word, in: rendered).pointSize, 23)
        }
    }

    private func font(at text: String, in rendered: NSAttributedString) throws -> NSFont {
        let stringRange = try XCTUnwrap(rendered.string.range(of: text))
        let range = NSRange(stringRange, in: rendered.string)
        return try XCTUnwrap(rendered.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
    }
}
