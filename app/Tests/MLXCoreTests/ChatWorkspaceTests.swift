import XCTest
@testable import MLXCore

/// The Model Browser moved from its own `Window` into the chat window's detail
/// column. These pin the three things that make that safe: the gate can't cover
/// the browser, every entry point goes through one chokepoint, and the retired
/// window id is gone from every surface that used to open it.
final class ChatWorkspaceTests: XCTestCase {

    private func source(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // MLXCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // app
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - The gate must not cover its own cure

    /// `ChatModelGateSheet` blocks the whole window and its only door closes it.
    /// With the browser inside that window, presenting the gate over the models
    /// pane locks the user out of the exact screen that resolves the gate.
    func testTheModelGateStandsDownWhileTheModelsPaneIsShowing() {
        XCTAssertFalse(
            ChatWorkspace.gateShouldPresent(gateIsBlocking: true, cancelled: false,
                                            workspace: .models(.recommended), welcomePresented: false),
            "the gate must not cover the browser it is asking the user to use")
        XCTAssertFalse(
            ChatWorkspace.gateShouldPresent(gateIsBlocking: true, cancelled: false,
                                            workspace: .models(.discover), welcomePresented: false),
            "…on any section")
    }

    /// And it is deferred, not dismissed: back in a conversation with still no
    /// model, it presents again.
    func testTheGateReturnsInConversationMode() {
        XCTAssertTrue(
            ChatWorkspace.gateShouldPresent(gateIsBlocking: true, cancelled: false,
                                            workspace: .conversation, welcomePresented: false))
        XCTAssertFalse(
            ChatWorkspace.gateShouldPresent(gateIsBlocking: false, cancelled: false,
                                            workspace: .conversation, welcomePresented: false))
        XCTAssertFalse(
            ChatWorkspace.gateShouldPresent(gateIsBlocking: true, cancelled: true,
                                            workspace: .conversation, welcomePresented: false),
            "Cancel still wins — it is the sheet's one door")
    }

    func testEntryLandsOnTheRecommendedSection() {
        XCTAssertEqual(ChatWorkspace.defaultEntry, .models(.recommended))
        XCTAssertTrue(ChatWorkspace.defaultEntry.isModels)
        XCTAssertEqual(ChatWorkspace.conversation.section, nil)
    }

    // MARK: - One chokepoint in

    /// Five surfaces used to call `openAndFocus("modelBrowser")` on their own.
    /// They all go through `AppState.showModels(...)` now — which both opens the
    /// chat window and sets the mode. A surface that set the mode itself would
    /// switch a window nobody is looking at.
    func testOnlyAppStateSwitchesIntoTheModelsPane() throws {
        let appState = try source("Sources/MLXServe/AppState.swift")
        XCTAssertTrue(appState.contains("func showModels("),
                      "AppState owns the one way into the models pane")

        for path in ["Sources/MLXServe/Views/ChatView.swift",
                     "Sources/MLXServe/Views/ChatModelPill.swift",
                     "Sources/MLXServe/Views/WelcomeView.swift",
                     "Sources/MLXServe/MLXServeApp.swift"] {
            let text = try source(path)
            XCTAssertFalse(text.contains("chatWorkspace = .models"), """
                \(path) sets the workspace directly — go through \
                AppState.showModels(), which also brings the window forward.
                """)
        }
    }

    /// The tray's Chat button lands on the TRANSCRIPT, not merely on the
    /// window: with the window parked on Models/Tasks/Create, a Chat that only
    /// focuses leaves the user staring at the pane they left (live report
    /// 2026-08-09). Same door shape as showModels() — mode AND window.
    func testTheTrayChatButtonSwitchesBackToTheConversation() throws {
        let appState = try source("Sources/MLXServe/AppState.swift")
        XCTAssertTrue(appState.contains("func showChat("),
                      "AppState owns the one door into the conversation")
        let app = try source("Sources/MLXServe/MLXServeApp.swift")
        XCTAssertTrue(app.contains("openChat: { appState.showChat() }"),
                      "the tray's Chat button must switch the mode, not just focus the window")
    }

    // MARK: - The retired window

    /// A scene id left behind after its `Window` is deleted is a control that
    /// opens nothing: `openWindow(id:)` on an unknown id is a no-op with no
    /// error anywhere.
    func testTheModelBrowserWindowIsGoneFromEverySurface() throws {
        for path in ["Sources/MLXServe/MLXServeApp.swift",
                     "Sources/MLXServe/Views/ChatModelPill.swift",
                     "Sources/MLXServe/Services/AppActivation.swift"] {
            let text = try source(path)
            // The OPENING spellings only: a chip may still be identified as
            // "tasks" (its own id), it just must not open a window with it.
            for opener in ["window(\"tasks\")", "openAndFocus(\"tasks\")", "id: \"tasks\")"] {
                XCTAssertFalse(text.contains(opener), """
                    \(path) still opens the retired "tasks" window (\(opener)) — \
                    Tasks is a mode of the chat window now.
                    """)
            }
            XCTAssertFalse(text.contains("\"modelBrowser\""), """
                \(path) still references the retired "modelBrowser" window id — \
                the browser is a mode of the chat window now.
                """)
            XCTAssertFalse(text.contains("\"sandboxTerminal\""), """
                \(path) still references the retired "sandboxTerminal" window id — \
                terminals are rows of the chat window now.
                """)
        }
    }

    /// Moving a view into another window means moving its ENVIRONMENT with it,
    /// and SwiftUI reports a missing `@EnvironmentObject` as a runtime trap —
    /// no compile error, nothing at all until the view first renders. Live
    /// crash 2026-08-08: the browser's window injected four objects, the chat
    /// window three of them, and opening the models pane killed the app inside
    /// `ModelBrowserPane.downloads.getter`.
    ///
    /// The map is explicit so a NEW `@EnvironmentObject` in the browser fails
    /// here — with the name of the type to inject — rather than at runtime.
    func testTheChatWindowInjectsEveryObjectItsHostedPanesRead() throws {
        let expectedInjection: [String: String] = [
            "AppState": ".environmentObject(appState)",
            "ServerManager": ".environmentObject(appState.server)",
            "DownloadManager": ".environmentObject(appState.downloads)",
            "HFSearchService": ".environmentObject(hfSearch)",
            "ImageGenService": ".environmentObject(appState.imageGen)",
            "VideoGenService": ".environmentObject(appState.videoGen)",
            "AudioGenService": ".environmentObject(appState.audioGen)",
            "MusicGenService": ".environmentObject(appState.musicGen)",
            "Model3DGenService": ".environmentObject(appState.model3dGen)",
            "TaskScheduler": ".environmentObject(appState.taskScheduler)",
            "AgentStore": ".environmentObject(appState.agents)",
            "TerminalSessionStore": ".environmentObject(appState.terminals)",
        ]

        // Every view the chat window hosts as a MODE — the browser, the four
        // media generators, and Tasks (whose two panes are columns of the
        // window's own split). All were windows of their own, with their own
        // environments; the chat window inherited that obligation.
        let hosted = ["Sources/MLXServe/Views/ModelBrowserView.swift",
                      "Sources/MLXServe/Views/ImageGenView.swift",
                      "Sources/MLXServe/Views/VideoGenView.swift",
                      "Sources/MLXServe/Views/AudioGenView.swift",
                      "Sources/MLXServe/Views/Model3DGenView.swift",
                      "Sources/MLXServe/Views/TasksView.swift",
                      // Agents is a mode now too, and its panes read a store
                      // the chat scene did not inject — the same first-render
                      // trap the Tasks columns hit, invisible to this audit for
                      // exactly as long as the file was missing from this list.
                      "Sources/MLXServe/Views/AgentsWindow.swift",
                      "Sources/MLXServe/Views/TerminalPane.swift"]
        let pattern = try NSRegularExpression(pattern: #"@EnvironmentObject\s+var\s+\w+\s*:\s*(\w+)"#)
        var types = Set<String>()
        for path in hosted {
            let text = try source(path)
            let range = NSRange(text.startIndex..., in: text)
            for match in pattern.matches(in: text, range: range) {
                if let r = Range(match.range(at: 1), in: text) {
                    types.insert(String(text[r]))
                }
            }
        }
        XCTAssertFalse(types.isEmpty, "the regex stopped matching — fix the audit, not the app")

        let app = try source("Sources/MLXServe/MLXServeApp.swift")
        guard let chatScene = app.range(of: #"Window("MLX-Serve", id: "chat")"#),
              let nextScene = app.range(of: "Window(", range: chatScene.upperBound..<app.endIndex) else {
            return XCTFail("the chat Window scene moved — update this audit")
        }
        let scene = String(app[chatScene.lowerBound..<nextScene.lowerBound])

        for type in types.sorted() {
            guard let injection = expectedInjection[type] else {
                XCTFail("""
                    A pane hosted by the chat window declares @EnvironmentObject \
                    of type \(type), which this audit doesn't know how to inject. \
                    Add it to `expectedInjection` AND to the chat Window scene — \
                    a missing one is a crash at first render, not a build error.
                    """)
                continue
            }
            XCTAssertTrue(scene.contains(injection), """
                The chat window must inject \(type) (`\(injection)`) — a pane it \
                hosts reads it, and SwiftUI traps at render time when it is \
                absent.
                """)
        }
    }

    /// A column of a split view must be a view TYPE, never a computed property
    /// read off a synthetic instance.
    ///
    /// Live crash 2026-08-08: the Tasks columns were `TasksView().taskList` and
    /// `TasksView().taskDetail`. That builds a view VALUE and immediately
    /// evaluates a property which touches `@EnvironmentObject` — but SwiftUI
    /// fills that storage when it INSTALLS a view in the hierarchy, and this
    /// instance never was one, so the first click on Tasks trapped in
    /// `TasksView.$appState.getter`. The `.environmentObject(…)` chained at the
    /// call site cannot help: it decorates the view the property already
    /// returned, long after the property read the empty box.
    ///
    /// The previous audit could not see it — it checks that the WINDOW injects
    /// what its panes read, which was true the whole time. What was wrong is
    /// where the reading happened.
    func testSplitViewColumnsAreViewTypesNotPropertiesOfSyntheticInstances() throws {
        // Comments describe this bug, so scanning them finds it in the prose
        // that warns about it.
        let chat = try source("Sources/MLXServe/Views/ChatView.swift")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces).hasPrefix("//") ? "" : String($0) }
            .joined(separator: "\n")

        // `Foo(…).bar` where `bar` is NOT a call. A view MODIFIER is always
        // `.foo(…)`, so requiring the absence of `(` separates the legitimate
        // shape from the crashing one without an allowlist to keep up to date.
        let pattern = try NSRegularExpression(
            pattern: #"\b([A-Z]\w*(?:View|Pane))\s*\([^)]*\)\s*\.\s*([a-z]\w*)\s*(?![\(\w])"#)
        let range = NSRange(chat.startIndex..., in: chat)
        let offenders: [String] = pattern.matches(in: chat, range: range).compactMap { match in
            Range(match.range, in: chat).map { String(chat[$0]) }
        }
        XCTAssertTrue(offenders.isEmpty, """
            A split-view column reads a property off a freshly constructed view: \
            \(offenders). SwiftUI never installed that instance, so any \
            @EnvironmentObject it touches traps at first render. Give the column \
            its own View type (`TaskListPane` / `TaskDetailPane`) instead.
            """)
    }

    /// Both Tasks columns are real view types, each declaring the environment it
    /// reads — which is what makes the window's injection reach them.
    func testTasksColumnsAreTheirOwnPaneTypes() throws {
        let chat = try source("Sources/MLXServe/Views/ChatView.swift")
        XCTAssertTrue(chat.contains("TaskListPane()"), "the content column must be TaskListPane")
        XCTAssertTrue(chat.contains("TaskDetailPane()"), "the detail column must be TaskDetailPane")
        XCTAssertFalse(chat.contains("TasksView()"), """
            TasksView() is back as a synthetic instance — that is the 2026-08-08 \
            crash shape.
            """)

        let tasks = try source("Sources/MLXServe/Views/TasksView.swift")
        for pane in ["struct TaskListPane: View", "struct TaskDetailPane: View"] {
            XCTAssertTrue(tasks.contains(pane), "missing \(pane)")
        }
    }

    /// A HOSTED pane must not demand a window-sized minimum: the gen views kept
    /// their 820-880pt window-era floors after becoming pages of the chat
    /// window, so at a small window the whole split overflowed the detail
    /// column and clipped BOTH edges (live screenshot 2026-08-09) — the right
    /// answer is the preview side resizing. The controls column keeps its
    /// form-protecting floor; what must never come back is a root frame sized
    /// for a window this view no longer is.
    func testGenPanesDoNotDemandWindowSizedMinimums() throws {
        for pane in ["ImageGenView", "VideoGenView", "AudioGenView",
                     "MusicGenView", "Model3DGenView"] {
            let text = try source("Sources/MLXServe/Views/\(pane).swift")
            for floor in ["minWidth: 7", "minWidth: 8", "minWidth: 9",
                          "minHeight: 6", "minHeight: 7"] {
                XCTAssertFalse(text.contains(floor), """
                    \(pane) demands a window-sized minimum (\(floor)…) — it is \
                    a page of the chat window now; let the preview side shrink.
                    """)
            }
        }
    }

    /// The browser's sub-items live across the top of the CONTENT area, because
    /// the sidebar is the conversation list. `allCases`, never a hand-written
    /// array — that is where a section quietly goes missing.
    func testTheBrowserCarriesItsOwnSectionBar() throws {
        let browser = try source("Sources/MLXServe/Views/ModelBrowserView.swift")
        XCTAssertTrue(browser.contains("ForEach(ModelBrowserSection.allCases)"),
                      "the section bar must iterate the whole catalogue")
        XCTAssertFalse(browser.contains("NavigationSplitView {"), """
            The pane renders inside the chat window's own NavigationSplitView — \
            a nested split view is what the section bar replaced.
            """)
    }

    /// Create mode lost its sidebar page list when the Chats/Models/Create
    /// switcher went — it is reached from the chat's discovery chips and the
    /// tray now. What must still hold is that every generator in the shared
    /// catalogue has a page to land on: `showCreate(.video)` with no video case
    /// would switch the window to a blank column.
    func testEveryGeneratorStillHasAPage() throws {
        let chat = try source("Sources/MLXServe/Views/ChatView.swift")
        for view in ["ImageGenView()", "VideoGenView()", "AudioGenView()", "Model3DGenView()"] {
            XCTAssertTrue(chat.contains(view), "create mode must host \(view)")
        }
        XCTAssertEqual(GenExperiment.allCases.count, 4,
                       "a fifth generator needs a case in ChatDetailView.createPane")
    }
}
