import XCTest
@testable import MLXCore

/// Pins the chat column's alignment contract. These numbers live in separate
/// views (transcript, context monitor, composer, bubbles) and drifted when
/// inlined — 16/12/12 gutters left the input pill and token bar 4pt left of
/// the message bubbles, with chip rows carrying +4 compensation paddings.
/// `ChatMetrics` is the single source of truth; this test keeps the
/// relationships from regressing.
final class ChatMetricsTests: XCTestCase {
    func testRetiredLayoutPreferencesDoNotChangeConversationGeometry() {
        let defaults = UserDefaults.standard
        let previous = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var overrides = previous
        overrides[InterfacePrefKey.compactMode] = true
        overrides[InterfacePrefKey.chatColumn] = ChatColumnWidth.narrow.rawValue
        defaults.setVolatileDomain(overrides, forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(previous, forName: UserDefaults.argumentDomain) }

        XCTAssertFalse(ChatMetrics.compactMode)
        XCTAssertEqual(ChatMetrics.transcriptSpacing, 10)
        XCTAssertEqual(ChatMetrics.proseWidth(panelWidth: 1600), 1280)
    }

    func testTranscriptSurfacesShareTheirCornerGeometry() {
        XCTAssertEqual(ChatMetrics.bubbleCornerRadius, CodeBlockLayout.cornerRadius)
        XCTAssertEqual(ChatMetrics.composerCornerRadius, ChatMetrics.bubbleCornerRadius)
    }

    func testReadingColumnReservesItsOuterGuttersAtNarrowWidths() {
        let defaults = UserDefaults.standard
        let key = InterfacePrefKey.chatColumn
        let previous = defaults.object(forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        for width in ChatColumnWidth.allCases {
            defaults.set(width.rawValue, forKey: key)
            XCTAssertLessThanOrEqual(ChatMetrics.proseWidth(panelWidth: 300), 300 - 2 * ChatMetrics.gutter)
        }
    }

    func testChatColumnGutter() {
        XCTAssertEqual(ChatMetrics.gutter, 16)
    }

    func testStatsCaptionAlignsWithBubbleTextColumn() {
        // The "N+M tokens" caption under a reply indents by the bubble's inner
        // padding so it lines up with the text, not the bubble edge.
        XCTAssertEqual(ChatMetrics.statsIndent, ChatMetrics.bubblePaddingH)
    }

    func testComposerControlsMatchPillRestHeight() {
        // Attach / mic / send frames equal the input pill's single-line height,
        // so a bottom-aligned HStack lines everything up with no nudge paddings.
        XCTAssertEqual(ChatMetrics.composerControlSize, ChatMetrics.composerMinHeight)
    }

    func testModeIconsShareTheComposerControlGeometry() {
        // Think / Tools / MCP moved out of the window toolbar and into the
        // composer row as bare glyphs, so they draw from the SAME circle
        // geometry as the paperclip and Send rather than the retired
        // `togglePill*` capsule metrics. One row, one baseline: the disc and
        // its frame must be the composer's, and the glyph must fit the disc.
        XCTAssertEqual(ChatMetrics.composerIconSize, 30)
        XCTAssertLessThan(ChatMetrics.composerIconSize, ChatMetrics.composerControlSize + 1)
    }
}
