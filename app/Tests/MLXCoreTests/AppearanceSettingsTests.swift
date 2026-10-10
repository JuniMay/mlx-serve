import XCTest
@testable import MLXCore

/// Guards for Settings ▸ Appearance wiring — the two places a display pref can
/// silently stop applying: a window scene that forgets `.appAppearance()`,
/// and the transcript, whose metrics read UserDefaults with no SwiftUI
/// dependency of their own.
final class AppearanceSettingsTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    /// `.appAppearance()` is applied per scene BY HAND, so a new `Window` can
    /// forget it and ship a window that ignores Settings ▸ Appearance — the
    /// same class as the window-injection rules.
    func testEveryWindowSceneAppliesTheAppAppearance() throws {
        let text = try source("Sources/MLXServe/MLXServeApp.swift")
        let scenes = text.components(separatedBy: "Window(\"").dropFirst()
        XCTAssertGreaterThanOrEqual(scenes.count, 4, "expected the app's window scenes to be found")
        for scene in scenes {
            let name = scene.prefix(while: { $0 != "\"" })
            XCTAssertTrue(scene.contains(".appAppearance()"),
                          "the \(name) window scene does not apply .appAppearance()")
        }
    }

    // Existing transcript rows update when the text size changes.
    func testTheTranscriptObservesTheInterfaceKeysItRendersWith() throws {
        let text = try source("Sources/MLXServe/Views/ChatView.swift")
        XCTAssertTrue(text.contains("@AppStorage(InterfacePrefKey.textSize)"),
                      "ChatDetailView does not observe the text-size key")
    }
}
