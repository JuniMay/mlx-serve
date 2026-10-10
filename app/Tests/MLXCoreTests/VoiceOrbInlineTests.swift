import XCTest
@testable import MLXCore

/// Source audit for the in-window voice UI.
///
/// Voice mode is an INLINE talking orb just above the composer, not a sheet:
/// the sheet covered the transcript (the one thing a chat window is for) and
/// duplicated toggles the composer row already carries. The entry point is a
/// toggle in the composer row, between the context gauge and Send.
///
/// Source audits rather than behavior tests because there is no seam: a
/// re-added `.sheet` or a chevron-only disclosure still compiles and renders —
/// only what a click does differs.
final class VoiceOrbInlineTests: XCTestCase {

    private func viewSource(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // MLXCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // app
            .appendingPathComponent("Sources/MLXServe/Views/\(file)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testVoiceIsAnInlineOrbNotASheet() throws {
        let chat = try viewSource("ChatView.swift")
        XCTAssertFalse(chat.contains(".sheet(isPresented: $showVoiceMode)"),
                       "voice mode must not present as a sheet — it renders inline above the composer")
        XCTAssertTrue(chat.contains("VoiceOrbView("),
                      "the inline orb must be mounted in the chat column")
        let orb = try viewSource("VoiceModeView.swift")
        XCTAssertTrue(orb.contains("orbSize: CGFloat = 128"),
                      "the talking orb is 128×128 by design")
    }

    /// Voice is ONE instance bound to ONE chat (`boundSessionId`): the orb and
    /// the toggle's on-tint must render only in the bound session's tab. A
    /// bare `controller.isActive` gate lights up EVERY tab (the live report:
    /// enabling voice in agent 1's chat showed it enabled in agent 2's and in
    /// new chats too).
    func testOrbAndToggleAreScopedToTheBoundSession() throws {
        let orbFile = try viewSource("VoiceModeView.swift")
        XCTAssertTrue(orbFile.contains("voiceOwnedHere("),
                      "orb + toggle must render from the per-session ownership decision, not bare isActive")
        let chat = try viewSource("ChatView.swift")
        XCTAssertTrue(chat.contains("VoiceOrbView(controller: appState.voice, sessionId: sessionId)"),
                      "the chat column must tell the orb WHICH session it renders for")
        XCTAssertTrue(chat.contains("VoiceComposerToggle(controller: appState.voice,\n                            sessionId: sessionId,")
                      || chat.contains("VoiceComposerToggle(controller: appState.voice, sessionId: sessionId,"),
                      "the composer toggle must carry its session too")
    }

}
