import SwiftUI
import AppKit

/// Semantic styles for interface text; transcript sizes remain a user preference.
enum AppType {
    enum Role {
        case pageTitle
        case sectionTitle
        case rowTitle
        case explainer
        case value
        case annotation

        var step: Font.TextStyle {
            switch self {
            case .pageTitle: return .largeTitle
            case .sectionTitle: return .title3
            case .rowTitle: return .body
            case .explainer, .value: return .callout
            case .annotation: return .footnote
            }
        }
    }

    private static func appKitStyle(for style: Font.TextStyle) -> NSFont.TextStyle {
        switch style {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .body: return .body
        case .callout: return .callout
        case .subheadline: return .subheadline
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        @unknown default: return .body
        }
    }

    static func pointSize(for style: Font.TextStyle) -> CGFloat {
        NSFont.preferredFont(forTextStyle: appKitStyle(for: style)).pointSize
    }

    static func system(_ style: Font.TextStyle, weight: NSFont.Weight? = nil) -> NSFont {
        let preferred = NSFont.preferredFont(forTextStyle: appKitStyle(for: style))
        guard let weight else { return preferred }
        return NSFont.systemFont(ofSize: preferred.pointSize, weight: weight)
    }

    static func monospaced(_ style: Font.TextStyle, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: pointSize(for: style), weight: weight)
    }
}

extension Font {
    static func app(_ role: AppType.Role, weight: Font.Weight? = nil, design: Font.Design? = nil) -> Font {
        .app(role.step, weight: weight, design: design)
    }

    static func app(_ style: Font.TextStyle, weight: Font.Weight? = nil, design: Font.Design? = nil) -> Font {
        .system(style, design: design, weight: weight)
    }
}
