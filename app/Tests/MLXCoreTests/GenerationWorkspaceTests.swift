import AppKit
import SwiftUI
import XCTest
@testable import MLXCore

@MainActor
final class InteractionComposerLifetimeTests: XCTestCase {
    private var preferences: InteractionTestPreferences?

    override func setUpWithError() throws {
        let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] ?? ""
        guard home.hasPrefix("/tmp/") || home.hasPrefix("/private/tmp/") else {
            throw XCTSkip("Requires CFFIXED_USER_HOME in a temporary directory.")
        }
        preferences = InteractionTestPreferences()
    }

    override func tearDownWithError() throws {
        preferences?.restore()
        preferences = nil
    }

    func testEveryModelCapabilityKeepsTheSameEditorDraftAndSession() async throws {
        let app = AppState(startServices: false)
        let session = ChatSession(title: "One interaction")
        app.chatSessions = [session]
        app.activeChatId = session.id
        let hosting = host(app, session: session.id)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.contentView = nil }
        try await settle(hosting)
        let original = try XCTUnwrap(editors(in: hosting).first)
        original.string = "Keep this draft 🦊"
        original.didChangeText()
        try await settle(hosting)
        let width = original.bounds.width

        let picks: [(MediaModality, String)] = [
            (.video, VideoModelPreset.minimaxH3.id),
            (.image, ImageModelPreset.flux2Klein4B_Q4.id),
            (.voice, AudioModelPreset.all[0].id),
            (.music, MusicModelPreset.all[0].id),
            (.sound, SoundModelPreset.all[0].id),
            (.mesh, Model3DModelPreset.all[0].id)
        ]
        for (modality, preset) in picks {
            app.selectMediaModel(modality: modality, name: preset, presetID: preset)
            try await settle(hosting)
            let current = try XCTUnwrap(editors(in: hosting).first)
            XCTAssertTrue(current === original, "Selecting \(modality) must keep the editor mounted.")
            XCTAssertEqual(editors(in: hosting).count, 1, "Parameters stay behind their control.")
            XCTAssertEqual(current.string, "Keep this draft 🦊")
            XCTAssertEqual(current.bounds.width, width, accuracy: 1)
            XCTAssertEqual(app.chatWorkspace, .conversation)
            XCTAssertEqual(app.activeChatId, session.id)
            XCTAssertTrue(app.activeSession?.messages.isEmpty == true)

            app.applyChatModelPick("/models/chat")
            try await settle(hosting)
            XCTAssertTrue(editors(in: hosting).first === original)
            XCTAssertEqual(original.string, "Keep this draft 🦊")
            XCTAssertNil(app.interactionMedia)
        }
        XCTAssertEqual(app.server.status, .stopped)
    }

    func testLongDraftReflowsWithoutChangingItsEditorOrLosingOutputSpace() async throws {
        let app = AppState(startServices: false)
        let session = ChatSession(title: "Layout")
        app.chatSessions = [session]
        app.activeChatId = session.id
        let hosting = host(app, session: session.id)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.contentView = nil }
        try await settle(hosting)
        let editor = try XCTUnwrap(editors(in: hosting).first)
        editor.string = String(repeating: "The same input handles text, image, sound, and video. ", count: 60)
        editor.didChangeText()
        try await settle(hosting)
        let wide = editor.bounds.width
        window.setContentSize(NSSize(width: 620, height: 700))
        try await settle(hosting)
        XCTAssertTrue(editors(in: hosting).first === editor)
        XCTAssertLessThan(editor.bounds.width, wide)
        let scroll = try XCTUnwrap(editor.enclosingScrollView)
        XCTAssertLessThan(scroll.bounds.height, 350, "A long draft must leave room for the transcript.")
        XCTAssertLessThanOrEqual(hosting.fittingSize.width, 620)
        XCTAssertTrue(scroll.hasVerticalScroller)
    }

    func testPreparingGenerationKeepsTheEditorAndEscapeIsScopedToItsSession() async throws {
        let app = AppState(startServices: false)
        let session = ChatSession(title: "Preparing video")
        app.chatSessions = [session]
        app.activeChatId = session.id
        let hosting = host(app, session: session.id)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.contentView = nil }
        try await settle(hosting)
        let editor = try XCTUnwrap(editors(in: hosting).first)
        editor.string = "Keep writing during preparation"
        editor.didChangeText()
        app.selectMediaModel(modality: .video, name: VideoModelPreset.minimaxH3.id,
                             presetID: VideoModelPreset.minimaxH3.id)
        let pending = try XCTUnwrap(app.prepareMediaInteraction(.video, sessionId: session.id,
                                                              prompt: "A cloud passes"))
        defer { pending.discard() }
        try await settle(hosting)
        app.applyChatModelPick("/models/chat")
        try await settle(hosting)

        XCTAssertTrue(editors(in: hosting).first === editor)
        XCTAssertEqual(editor.string, "Keep writing during preparation")
        XCTAssertTrue(app.activeSession?.messages.isEmpty == true)
        XCTAssertEqual(app.mediaInteractions.progress(for: session.id).first?.isPreparing, true)
        app.selectMediaModel(modality: .video, name: VideoModelPreset.minimaxH3.id,
                             presetID: VideoModelPreset.minimaxH3.id)
        try await settle(hosting)
        let cancel = #selector(NSResponder.cancelOperation(_:))
        XCTAssertEqual(editor.delegate?.textView?(editor, doCommandBy: cancel), true)
        XCTAssertTrue(app.mediaInteractions.progress(for: session.id).isEmpty)

        let otherSession = UUID()
        let other = try XCTUnwrap(app.prepareMediaInteraction(.video, sessionId: otherSession,
                                                            prompt: "Another session"))
        defer { other.discard() }
        try await settle(hosting)
        XCTAssertEqual(editor.delegate?.textView?(editor, doCommandBy: cancel), false)
        XCTAssertFalse(app.mediaInteractions.progress(for: otherSession).isEmpty)
        XCTAssertEqual(editor.string, "Keep writing during preparation")
        XCTAssertEqual(app.server.status, .stopped)
    }

    func testModelParametersStayInsideTheOptionsPopover() async throws {
        let app = AppState(startServices: false)
        let picks: [(MediaModality, String)] = [
            (.video, VideoModelPreset.minimaxH3.id),
            (.image, ImageModelPreset.flux2Klein4B_Q4.id),
            (.voice, AudioModelPreset.all[0].id),
            (.music, MusicModelPreset.all[0].id),
            (.sound, SoundModelPreset.all[0].id),
            (.mesh, Model3DModelPreset.all[0].id)
        ]
        for (modality, preset) in picks {
            app.selectMediaModel(modality: modality, name: preset, presetID: preset)
            let hosting = NSHostingView(rootView: InteractionOptionsHarness(modality: modality)
                .environmentObject(app).environmentObject(app.server).environmentObject(app.downloads)
                .environmentObject(app.videoGen).environmentObject(app.imageGen)
                .environmentObject(app.audioGen).environmentObject(app.musicGen)
                .environmentObject(app.soundGen).environmentObject(app.model3dGen))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            try await settle(hosting)
            let controls = nativeControls(in: hosting)
            XCTAssertFalse(controls.isEmpty, "\(modality)")
            for control in controls where !control.isHiddenOrHasHiddenAncestor {
                let rect = control.convert(control.bounds, to: hosting)
                XCTAssertGreaterThanOrEqual(rect.minX, -1, "\(modality): \(type(of: control)) starts outside the popover")
                XCTAssertLessThanOrEqual(rect.maxX, 421, "\(modality): \(type(of: control)) extends outside the popover")
            }
            window.contentView = nil
        }
    }

    private func nativeControls(in view: NSView) -> [NSControl] {
        (view as? NSControl).map { [$0] } ?? view.subviews.flatMap { nativeControls(in: $0) }
    }

    private func host(_ app: AppState, session: UUID) -> NSHostingView<some View> {
        NSHostingView(rootView: ChatDetailView(sessionId: session)
            .environmentObject(app).environmentObject(app.server)
            .environmentObject(app.downloads).environmentObject(app.toolExecutor)
            .environmentObject(app.mcpManager).environmentObject(app.chatEngine))
    }

    private func editors(in view: NSView) -> [NSTextView] {
        if let editor = view as? NSTextView, editor.isEditable { return [editor] }
        return view.subviews.flatMap { editors(in: $0) }
    }

    private func settle<V: View>(_ hosting: NSHostingView<V>) async throws {
        for _ in 0..<30 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private struct InteractionOptionsHarness: View {
    let modality: MediaModality
    @State private var prompt = "A cloud passes"
    @State private var selection: TextSelection?
    @State private var focused = false

    var body: some View {
        controls
            .backgroundPreferenceValue(MediaInteractionPreferenceKey.self) { configuration in
                if let configuration {
                    InteractionOptionsPopover {
                        configuration.accessories
                        configuration.parameters
                    }
                }
            }
            .frame(width: 420, height: 520)
    }
    @ViewBuilder private var controls: some View {
        switch modality {
        case .video: VideoInteractionControls(prompt: $prompt, promptSelection: $selection, promptFocused: $focused)
        case .image: ImageInteractionControls(prompt: $prompt, promptSelection: $selection, promptFocused: $focused)
        case .voice: VoiceInteractionControls(prompt: $prompt)
        case .music: MusicInteractionControls(prompt: $prompt)
        case .sound: SoundInteractionControls(prompt: $prompt)
        case .mesh: Model3DInteractionControls()
        }
    }

}
