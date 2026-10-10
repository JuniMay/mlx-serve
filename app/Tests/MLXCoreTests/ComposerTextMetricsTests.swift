import XCTest
@testable import MLXCore

/// The composer's placeholder stands in for the first character you type, so it
/// has to sit exactly where that character lands.
///
/// It didn't: the placeholder was a literal `9` while the first glyph starts at
/// `5 + 7 + 2 = 14` — the field's own padding, the text container inset, and
/// the line-fragment padding, which is the one nobody remembers because it is
/// not a padding anybody wrote. The caret therefore sat five points right of
/// the placeholder, overlapping its first letter.
final class ComposerTextMetricsTests: XCTestCase {

    /// The arithmetic, stated once. Three insets stand between the field's edge
    /// and the glyph, and every one of them counts.
    func testThePlaceholderStartsWhereTheTextDoes() {
        XCTAssertEqual(ComposerTextMetrics.placeholderLeading,
                       ComposerTextMetrics.fieldHorizontalPadding
                       + ComposerTextMetrics.containerInsetWidth
                       + ComposerTextMetrics.lineFragmentPadding)
        XCTAssertEqual(ComposerTextMetrics.placeholderLeading, 14)
        XCTAssertEqual(ComposerTextMetrics.placeholderTop,
                       ComposerTextMetrics.containerInsetHeight)
    }

    /// The old value, named so a regression to it fails with the reason.
    func testTheOldMisalignedValueIsNotWhatWeUse() {
        XCTAssertNotEqual(ComposerTextMetrics.placeholderLeading, 9,
                          "9 was the field padding plus a guess — it ignored both text insets")
    }

}
