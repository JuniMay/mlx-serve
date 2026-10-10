import AppKit
import SwiftUI
import XCTest
@testable import MLXCore

final class SystemTypeTests: XCTestCase {
    private let styles: [(Font.TextStyle, NSFont.TextStyle)] = [
        (.largeTitle, .largeTitle), (.title, .title1), (.title2, .title2), (.title3, .title3),
        (.headline, .headline), (.body, .body), (.callout, .callout), (.subheadline, .subheadline),
        (.footnote, .footnote), (.caption, .caption1), (.caption2, .caption2),
    ]

    func testSwiftUIFontsKeepTheirSemanticStyles() {
        for (style, _) in styles {
            XCTAssertEqual(Font.app(style), Font.system(style), "\(style) must remain a semantic font")
        }
    }

    func testExplicitWeightAndDesignArePreserved() {
        XCTAssertEqual(Font.app(.body, weight: .semibold, design: .rounded),
                       Font.system(.body, design: .rounded, weight: .semibold))
        XCTAssertEqual(Font.app(.caption, design: .monospaced),
                       Font.system(.caption, design: .monospaced))
    }

    func testAppKitFontsUseThePlatformsPreferredMetricsAndTraits() {
        for (style, nativeStyle) in styles {
            let expected = NSFont.preferredFont(forTextStyle: nativeStyle)
            let actual = AppType.system(style)
            XCTAssertEqual(actual.pointSize, expected.pointSize, accuracy: 0.01)
            XCTAssertEqual(actual.fontDescriptor.symbolicTraits, expected.fontDescriptor.symbolicTraits)
            XCTAssertEqual(AppType.pointSize(for: style), expected.pointSize, accuracy: 0.01)
        }
    }

    func testMonospacedTextKeepsThePreferredSize() {
        let font = AppType.monospaced(.caption)
        XCTAssertEqual(font.pointSize, NSFont.preferredFont(forTextStyle: .caption1).pointSize, accuracy: 0.01)
        XCTAssertEqual(("iiii" as NSString).size(withAttributes: [.font: font]).width,
                       ("WWWW" as NSString).size(withAttributes: [.font: font]).width, accuracy: 0.01)
    }

    func testRolesKeepTheirSemanticHierarchy() {
        let roles: [(AppType.Role, Font.TextStyle)] = [
            (.pageTitle, .largeTitle), (.sectionTitle, .title3), (.rowTitle, .body),
            (.explainer, .callout), (.value, .callout), (.annotation, .footnote),
        ]
        for (role, style) in roles {
            XCTAssertEqual(Font.app(role), Font.system(style))
        }
    }

    func testSavedTranscriptSizeChoicesKeepTheirExistingSizes() {
        let sizes: [(String, CGFloat, CGFloat)] = [
            ("small", 12, 11), ("medium", 14, 13), ("large", 16, 15), ("xlarge", 19, 17),
        ]
        for (rawValue, prose, code) in sizes {
            let choice = ChatTextSize(rawValue: rawValue)
            XCTAssertEqual(choice?.proseSize, prose)
            XCTAssertEqual(choice?.codeSize, code)
        }
    }
}
