import XCTest
@testable import MLXCore

/// The transcript's reading size is ONE number, and the typeface is the system
/// font.
final class TranscriptTypographyTests: XCTestCase {

    private func source(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    // The default text size is 14 points.
    func testTheTranscriptReadsAtFourteenPointsByDefault() {
        XCTAssertEqual(ChatTextSize.medium.proseSize, 14)
        XCTAssertEqual(ChatMetrics.transcriptFontSize, ChatTextSize.medium.proseSize)
    }

    /// Headings scale FROM the body size. As three literals (18/16/14) raising
    /// the body to 16 would have left an h3 smaller than the paragraph under
    /// it and an h2 identical to it — the hierarchy silently flattening
    /// rather than breaking.
    func testHeadingsStayAboveTheBodySize() {
        let base = ChatMetrics.transcriptFontSize
        let chat = try? source("Sources/MLXServe/Views/ChatView.swift")
        XCTAssertEqual(chat?.contains("level == 1 ? base + 5 : level == 2 ? base + 3 : base + 1"), true,
                       "heading sizes must derive from the body size, not be restated")
        for bump in [5, 3, 1] {
            XCTAssertGreaterThan(base + CGFloat(bump), base)
        }
    }

    /// Code is monospaced, and monospaced glyphs run wide — matching the prose
    /// size makes a fenced block look bigger than the sentence introducing it.
    func testCodeIsSmallerThanProse() {
        XCTAssertLessThan(ChatMetrics.transcriptCodeFontSize, ChatMetrics.transcriptFontSize)
    }

    /// Every transcript size reads the constants. A literal beside them is how
    /// four of five call sites get changed.
    func testNoTranscriptFontSizeIsHardCoded() throws {
        let chat = try source("Sources/MLXServe/Views/ChatView.swift")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces).hasPrefix("//") ? "" : String($0) }
            .joined(separator: "\n")
        // The renderer's own font construction only — other views legitimately
        // use small sizes for badges and captions.
        guard let start = chat.range(of: "private static func buildAttributedString") else {
            return XCTFail("the markdown renderer moved — update this audit")
        }
        let renderer = String(chat[start.upperBound...])
        for literal in ["systemFont(ofSize: 13", "monospacedSystemFont(ofSize: 12"] {
            XCTAssertFalse(renderer.contains(literal), """
                The transcript renderer still hard-codes `\(literal)`. Sizes come \
                from ChatMetrics.transcriptFontSize / .transcriptCodeFontSize.
                """)
        }
    }

    /// The markdown render cache is keyed on the text-size setting: identical
    /// bytes rendered at Small and then Extra Large must come back at two
    /// sizes, not as a stale cache hit built at the old size.
    func testTheRenderedTranscriptFollowsTheTextSizeSetting() {
        let original = UserDefaults.standard.object(forKey: InterfacePrefKey.textSize)
        defer {
            if let original { UserDefaults.standard.set(original, forKey: InterfacePrefKey.textSize) }
            else { UserDefaults.standard.removeObject(forKey: InterfacePrefKey.textSize) }
        }
        UserDefaults.standard.set(ChatTextSize.small.rawValue, forKey: InterfacePrefKey.textSize)
        let small = MarkdownText.attributedString(for: "same bytes, two sizes")
        UserDefaults.standard.set(ChatTextSize.xlarge.rawValue, forKey: InterfacePrefKey.textSize)
        let large = MarkdownText.attributedString(for: "same bytes, two sizes")
        XCTAssertEqual((small.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize,
                       ChatTextSize.small.proseSize)
        XCTAssertEqual((large.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize,
                       ChatTextSize.xlarge.proseSize)
    }

    /// Every indent is measured from a MARGIN, never as an absolute wrap point.
    ///
    /// A positive `tailIndent` is a distance from the LEADING edge, so it stops
    /// a line at a fixed x whatever the column does. That is what the reading
    /// measure used to be, and it is why prose ended mid-column while the table
    /// beside it ran the full width. Negative (or zero) is measured from the
    /// trailing edge, so the text tracks the column instead of a constant.
    func testIndentsAreMeasuredFromTheMarginsNotAnAbsoluteWrapPoint() {
        let rendered = MarkdownText.attributedString(for: "flowing prose\n\n```\nwide code\n```")
        let text = rendered.string as NSString
        let proseStyle = rendered.attribute(.paragraphStyle, at: text.range(of: "flowing").location,
                                            effectiveRange: nil) as? NSParagraphStyle
        let codeStyle = rendered.attribute(.paragraphStyle, at: text.range(of: "wide code").location,
                                           effectiveRange: nil) as? NSParagraphStyle
        XCTAssertLessThanOrEqual(proseStyle?.tailIndent ?? 1, 0, "prose must track the column")
        XCTAssertLessThanOrEqual(codeStyle?.tailIndent ?? 1, 0, "code must track the column")
        XCTAssertEqual(proseStyle?.lineHeightMultiple, ChatMetrics.proseLineHeightMultiple)
    }

    /// A bullet's hanging indent is measured off the bullet glyph, so wrapped
    /// lines align under the text rather than under the dot.
    func testABulletHangsUnderItsOwnText() {
        let rendered = MarkdownText.attributedString(for: "- an item")
        let style = rendered.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertGreaterThan(style?.headIndent ?? 0, 0, "the bullet's own hang is missing")
        let markerWidth = ("• " as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: ChatMetrics.transcriptFontSize)
        ]).width.rounded(.up)
        XCTAssertEqual((style?.firstLineHeadIndent ?? 0) + markerWidth,
                       style?.headIndent ?? 0, "wrapped lines start after the marker column")
    }

    // MARK: - Adaptive geometry and reading density

    private func withLayoutPreferences(column: ChatColumnWidth, compact: Bool = false, _ body: () -> Void) {
        let defaults = UserDefaults.standard
        let previous = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var values = previous
        values[InterfacePrefKey.chatColumn] = column.rawValue
        values[InterfacePrefKey.compactMode] = compact
        defaults.setVolatileDomain(values, forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(previous, forName: UserDefaults.argumentDomain) }
        body()
    }

    func testReadingWidthFollowsTheWindowAcrossSavedColumnPreferences() {
        for column in ChatColumnWidth.allCases {
            withLayoutPreferences(column: column) {
                XCTAssertEqual(ChatMetrics.proseWidth(panelWidth: 1800), 1440)
                XCTAssertEqual(ChatMetrics.proseWidth(panelWidth: 1000), 800)
                XCTAssertEqual(ChatMetrics.proseWidth(panelWidth: 900), 720)
                XCTAssertEqual(ChatMetrics.proseWidth(panelWidth: 600), 480)
            }
        }
    }

    func testNarrowPanelsPreserveTheMinimumGutter() {
        XCTAssertEqual(ChatMetrics.proseWidth(panelWidth: 100), 100 - 2 * ChatMetrics.gutter)
        XCTAssertEqual(ChatMetrics.proseWidth(panelWidth: 20), 0)
    }

    func testAnUnmeasuredPanelFallsBackRatherThanCollapsing() {
        XCTAssertEqual(ChatMetrics.proseWidth(panelWidth: 0), ChatMetrics.contentFallbackWidth)
    }

    func testSavedDensityPreferencesKeepReadableLineSpacing() {
        var normalSpacing: CGFloat = 0
        withLayoutPreferences(column: .wide) {
            normalSpacing = ChatMetrics.userLineSpacing
        }
        withLayoutPreferences(column: .narrow, compact: true) {
            XCTAssertEqual(ChatMetrics.userLineSpacing, normalSpacing)
            XCTAssertGreaterThan(ChatMetrics.userLineSpacing, 0)
            XCTAssertEqual(ChatMetrics.proseLineHeightMultiple, 1.4)
        }
    }

    func testUserTurnsKeepASmallerMaximumWidthThanWideReplies() {
        for column in ChatColumnWidth.allCases {
            withLayoutPreferences(column: column) {
                XCTAssertLessThan(ChatMetrics.userBubbleMaxWidth, ChatMetrics.proseWidth(panelWidth: 2000))
            }
        }
    }

    /// SF Pro is the macOS system font, so the app gets it by asking for the
    /// system font. Naming it explicitly would be the same typeface with none
    /// of the optical sizing or weight mapping — and would break the moment
    /// Apple ships a new system face.
    func testTheAppNeverNamesAFontFamilyByString() throws {
        for path in ["Sources/MLXServe/Views/ChatView.swift",
                     "Sources/MLXServe/Views/ChatMetrics.swift",
                     "Sources/MLXServe/Views/NewTaskSheet.swift",
                     "Sources/MLXServe/Views/TasksView.swift",
                     "Sources/MLXServe/Views/AgentsWindow.swift"] {
            // Comments explain why NOT to name a font, so scanning them finds
            // the ban in the prose that states it.
            let text = try source(path)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces).hasPrefix("//") ? "" : String($0) }
                .joined(separator: "\n")
            XCTAssertFalse(text.contains(".custom("), """
                \(path) names a font family by string. The system font IS SF Pro; \
                a named copy loses optical sizing and weight mapping.
                """)
            XCTAssertFalse(text.contains("NSFont(name:"), "\(path) constructs a font by name")
        }
    }
}
