import AppKit
import XCTest
@testable import MLXCore

final class MarkdownBlockBoundaryTests: XCTestCase {
    func testUnrelatedNumberedListDoesNotShiftBulletList() throws {
        let baseline = try paragraph("First", in: "- First")
        for source in [
            "- First\n\nAnother paragraph.\n\n123456789. Other",
            "123456789. Other\n\nAnother paragraph.\n\n- First",
        ] {
            let actual = try paragraph("First", in: source)
            XCTAssertEqual(actual.headIndent, baseline.headIndent, accuracy: 0.01)
            XCTAssertEqual(actual.firstLineHeadIndent, baseline.firstLineHeadIndent, accuracy: 0.01)
        }
    }

    func testOneListStillSharesMarkerWidthAcrossDigitCounts() throws {
        let source = "9. Ninth\n10. Tenth\n  - Nested\n11. Eleventh"
        let first = try paragraph("Ninth", in: source)
        for item in ["Tenth", "Eleventh"] {
            XCTAssertEqual(try paragraph(item, in: source).headIndent, first.headIndent, accuracy: 0.01)
        }
    }

    func testWhitespaceBetweenDisplayEquationsDoesNotCreateProseViews() {
        let blocks = MarkdownText.latexBlocks(in: " \n$$a$$\n\t\n$$b$$\n ")
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks.compactMap { block in
            if case .display(_, let raw) = block { return raw }
            return nil
        }, ["$$a$$", "$$b$$"])
        XCTAssertTrue(blocks.allSatisfy { block in
            if case .display = block { return true }
            return false
        })
    }

    func testDisplayBoundariesPreserveNonblankProseAndInlineMathExactly() {
        let before = "Before $x$\n\n"
        let after = "\n\nAfter $y$  "
        let blocks = MarkdownText.latexBlocks(in: before + "$$z$$" + after)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks.compactMap { block in
            if case .prose(let source) = block { return source }
            return nil
        }, [before, after])
    }

    func testIncompleteStreamingFormulaStaysLiteral() {
        let source = "Before\n\n$$unfinished"
        let blocks = MarkdownText.latexBlocks(in: source)
        XCTAssertEqual(blocks.count, 1)
        guard let first = blocks.first, case .prose(let actual) = first else {
            return XCTFail("An incomplete formula must stay selectable prose")
        }
        XCTAssertEqual(actual, source)
    }

    private func paragraph(_ text: String, in source: String) throws -> NSParagraphStyle {
        let rendered = MarkdownText.attributedString(for: source)
        let stringRange = try XCTUnwrap(rendered.string.range(of: text))
        let range = NSRange(stringRange, in: rendered.string)
        return try XCTUnwrap(rendered.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)
    }
}
