import AppKit
import XCTest
@testable import MLXCore

final class MarkdownPresentationTests: XCTestCase {
    func testOrderedListTextSharesOneColumnAcrossDigitCounts() throws {
        let rendered = MarkdownText.attributedString(for: "9. Ninth item\n10. Tenth item\n11. Eleventh item")
        let ninth = try paragraph("Ninth", in: rendered)
        let tenth = try paragraph("Tenth", in: rendered)
        XCTAssertEqual(ninth.headIndent, tenth.headIndent, accuracy: 0.01)
        XCTAssertGreaterThan(ninth.firstLineHeadIndent, tenth.firstLineHeadIndent)
    }

    func testTablesUseRowDividersWithoutABoxAroundTheText() throws {
        let rendered = MarkdownText.attributedString(for: "| Name | Value |\n| --- | --- |\n| Alpha | One |")
        for value in ["Name", "Value", "Alpha", "One"] {
            let block = try XCTUnwrap(try paragraph(value, in: rendered).textBlocks.first)
            XCTAssertEqual(block.width(for: .border, edge: .minX), 0)
            XCTAssertEqual(block.width(for: .border, edge: .maxX), 0)
            XCTAssertGreaterThanOrEqual(block.width(for: .padding, edge: .minY), 8)
        }
    }

    func testTableCellsFollowChangedTranscriptTextSize() throws {
        let defaults = UserDefaults.standard
        let key = InterfacePrefKey.textSize
        let previous = defaults.object(forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        let source = "| Presentation font probe |\n| --- |\n| Cached cell font probe |"
        for size in [ChatTextSize.small, .xlarge] {
            defaults.set(size.rawValue, forKey: key)
            let rendered = MarkdownText.attributedString(for: source)
            let range = (rendered.string as NSString).range(of: "Cached cell font probe")
            let font = try XCTUnwrap(rendered.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
            XCTAssertEqual(font.pointSize, size.proseSize, accuracy: 0.01)
        }
    }

    private func paragraph(_ text: String, in rendered: NSAttributedString) throws -> NSParagraphStyle {
        let range = (rendered.string as NSString).range(of: text)
        XCTAssertNotEqual(range.location, NSNotFound)
        return try XCTUnwrap(rendered.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)
    }
}
