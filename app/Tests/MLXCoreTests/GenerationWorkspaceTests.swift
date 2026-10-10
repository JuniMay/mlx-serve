import AppKit
import SwiftUI
import XCTest
@testable import MLXCore

@MainActor
final class GenerationWorkspaceTests: XCTestCase {
    func testOutputStaysAboveTheInputAndUsesTheAvailableWidth() async throws {
        for width: CGFloat in [420, 900] {
            let probe = GenerationWorkspaceProbe()
            let hosting = NSHostingView(rootView: GenerationWorkspaceFixture(probe: probe))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 700),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            defer { window.contentView = nil }
            try await settle(hosting) { !probe.prompt.isEmpty && !probe.result.isEmpty }

            XCTAssertLessThanOrEqual(probe.result.maxY, probe.prompt.minY,
                                     "The result canvas belongs above the input dock.")
            XCTAssertGreaterThan(probe.result.width, width - 80,
                                 "Closed options must leave the canvas the full column.")
            XCTAssertGreaterThan(probe.result.height, 250)
            XCTAssertLessThanOrEqual(hosting.fittingSize.width, width)
            XCTAssertEqual(probe.parameterAppearances, 0,
                           "Technical parameters start behind the inspector control.")
            XCTAssertEqual(probe.modelAppearances, 0,
                           "The model's full configuration starts behind its popover.")
        }
    }

    func testCanvasAndDockShareEdgesAtNarrowAndWideSizes() async throws {
        for width: CGFloat in [420, 900, 1400] {
            let probe = GenerationWorkspaceProbe()
            let hosting = NSHostingView(rootView: GenerationWorkspaceFixture(probe: probe))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 700),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            defer { window.contentView = nil }
            try await settle(hosting) { !probe.prompt.isEmpty && !probe.result.isEmpty }

            XCTAssertEqual(probe.result.minX, probe.prompt.minX - AppLayout.contentInset, accuracy: 1,
                           "The result and floating dock share their leading edge.")
            XCTAssertEqual(probe.result.maxX, probe.prompt.maxX + AppLayout.contentInset, accuracy: 1,
                           "The result and floating dock share their trailing edge.")
        }
    }

    func testLongInputKeepsRoomForTheResultAndShrinksAgain() async throws {
        let probe = GenerationWorkspaceProbe()
        let hosting = NSHostingView(rootView: GenerationWorkspaceFixture(probe: probe))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.contentView = nil }
        try await settle(hosting) { !probe.result.isEmpty }
        let originalHeight = probe.result.height

        probe.inputHeight = 500
        try await settle(hosting) { probe.prompt.height >= 500 }
        XCTAssertGreaterThan(probe.result.height, 250)
        XCTAssertLessThan(originalHeight - probe.result.height, 220)

        probe.inputHeight = 70
        try await settle(hosting) { abs(probe.result.height - originalHeight) < 1 }
        XCTAssertEqual(probe.result.height, originalHeight, accuracy: 1)
    }

    private func settle<V: View>(_ hosting: NSHostingView<V>, until ready: () -> Bool) async throws {
        for _ in 0..<100 {
            hosting.layoutSubtreeIfNeeded()
            if ready() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The generation workspace layout did not settle.")
    }
}

@MainActor
private final class GenerationWorkspaceProbe: ObservableObject {
    @Published var inputHeight: CGFloat = 70
    var prompt = CGRect.zero
    var result = CGRect.zero
    var parameterAppearances = 0
    var modelAppearances = 0
}

private struct GenerationWorkspaceFixture: View {
    @ObservedObject var probe: GenerationWorkspaceProbe

    var body: some View {
        GenerationWorkspace(title: "Image", modelName: "Example model", prompt: {
            TextField("Describe an image", text: .constant("A copper kettle"))
                .frame(height: probe.inputHeight)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("workspace")) }
                    action: { probe.prompt = $0 }
        }, model: {
            Text("Full model configuration").onAppear { probe.modelAppearances += 1 }
        }, attachments: {
            EmptyView()
        }, parameters: {
            Text("Sampler steps").onAppear { probe.parameterAppearances += 1 }
        }, actions: {
            Button("Generate") {}
        }, result: {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("workspace")) }
                    action: { probe.result = $0 }
        })
        .coordinateSpace(name: "workspace")
    }
}

@MainActor
final class VideoPromptInputTests: XCTestCase {
    func testEmptyPromptKeepsItsActionsVisibleForEveryBackendFormat() async throws {
        for width: CGFloat in [500, 830] {
            for format: VideoPromptFormat in [.ltx, .h3Base, .h3Reference] {
                let probe = VideoPromptInputProbe()
                let hosting = NSHostingView(rootView: VideoPromptInputFixture(probe: probe, format: format))
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 650),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = hosting
                defer { window.contentView = nil }
                try await settle(hosting)

                XCTAssertFalse(probe.actions.isEmpty)
                XCTAssertGreaterThanOrEqual(probe.actions.minX, 0)
                XCTAssertLessThanOrEqual(probe.actions.maxX, width - AppLayout.pageInset,
                                         "The empty \(format) prompt must keep its actions inside the dock at width \(width).")
                let emptyActions = probe.actions

                probe.text = "A fox walks through a forest."
                try await settle(hosting)
                XCTAssertEqual(probe.actions.midX, emptyActions.midX, accuracy: 1,
                               "Typing must not move the prompt actions across the dock.")
            }
        }
    }

    private func settle<V: View>(_ hosting: NSHostingView<V>) async throws {
        for _ in 0..<12 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
private final class VideoPromptInputProbe: ObservableObject {
    @Published var text = ""
    var actions = CGRect.zero
}

private struct VideoPromptInputFixture: View {
    @ObservedObject var probe: VideoPromptInputProbe
    let format: VideoPromptFormat

    var body: some View {
        GenerationWorkspace(title: "Video", modelName: "Video model", prompt: {
            VideoPromptInput(isEmpty: probe.text.isEmpty, format: format, editor: {
                TextEditor(text: $probe.text, selection: .constant(nil))
                    .font(.app(.body))
                    .frame(height: 110)
                    .scrollContentBackground(.hidden)
            }, actions: {
                Menu {
                    Button("Enhance…") {}
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(.top, 6)
                .accessibilityLabel("Prompt actions")
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("video-prompt")) }
                    action: { probe.actions = $0 }
            })
        }, model: { EmptyView() }, attachments: { EmptyView() },
           parameters: { EmptyView() }, actions: { Button("Generate") {} },
           result: { Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity) })
        .coordinateSpace(name: "video-prompt")
    }
}
