import AppKit
import SwiftUI
import XCTest
@testable import MLXCore

@MainActor
final class GrowingTextEditorTests: XCTestCase {
    func testEscapeUsesTheCancelCallbacksConsumptionResult() async throws {
        let probe = EditorProbe()
        let hosting = NSHostingView(rootView: EditorFixture(probe: probe))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.contentView = nil }
        let editor = try await textView(in: hosting)

        for consumed in [false, true] {
            probe.consumeCancel = consumed
            let before = probe.cancelCalls
            XCTAssertEqual(editor.delegate?.textView?(editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))), consumed)
            XCTAssertEqual(probe.cancelCalls, before + 1)
        }
    }

    func testArrowsReportCaretEdgesAndLeaveSelectionsToTheCallback() async throws {
        let probe = EditorProbe()
        probe.text = "A 🦊"
        let hosting = NSHostingView(rootView: EditorFixture(probe: probe))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.contentView = nil }
        let editor = try await textView(in: hosting)
        let keys = [("up", #selector(NSResponder.moveUp(_:))),
                    ("down", #selector(NSResponder.moveDown(_:)))]
        let positions = [(NSRange(location: 0, length: 0), true, false),
                         (NSRange(location: 4, length: 0), false, true),
                         (NSRange(location: 1, length: 0), false, false),
                         (NSRange(location: 0, length: 4), false, false)]
        for (range, start, end) in positions {
            editor.setSelectedRange(range)
            for (name, selector) in keys {
                for consumed in [false, true] {
                    probe.consumeArrow = consumed
                    XCTAssertEqual(editor.delegate?.textView?(editor, doCommandBy: selector), consumed)
                    XCTAssertEqual(probe.lastArrow, EditorArrow(direction: name, atStart: start, atEnd: end))
                }
            }
        }

        probe.text = ""
        try await settle(hosting)
        for (name, selector) in keys {
            _ = editor.delegate?.textView?(editor, doCommandBy: selector)
            XCTAssertEqual(probe.lastArrow, EditorArrow(direction: name, atStart: true, atEnd: true))
        }
    }

    func testAnUnchangedFocusRequestDoesNotTakeFocusBack() async throws {
        let probe = EditorProbe()
        let hosting = NSHostingView(rootView: EditorFixture(probe: probe))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.contentView = nil }
        let editor = try await textView(in: hosting)
        probe.keepFocusRequested = true
        try await settle(hosting)
        XCTAssertTrue(window.firstResponder === editor)

        let other = EditorFocusSink()
        hosting.addSubview(other)
        XCTAssertTrue(window.makeFirstResponder(other))
        probe.text = "An unrelated view update"
        try await settle(hosting)
        XCTAssertTrue(window.firstResponder === other,
                      "An unchanged focus binding must leave another control focused.")
    }

    func testReplacingTheDraftClearsAnOutOfBoundsSelection() async throws {
        for replacement in ["Hi", ""] {
            let probe = EditorProbe()
            probe.text = "A fox in the meadow"
            probe.selection = TextSelection(range: try XCTUnwrap(probe.text.range(of: "meadow")))
            let hosting = NSHostingView(rootView: EditorFixture(probe: probe))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            defer { window.contentView = nil }
            let editor = try await textView(in: hosting)
            probe.text = replacement
            try await settle(hosting)
            XCTAssertEqual(editor.string, replacement)
            XCTAssertEqual(editor.selectedRange(), NSRange(location: replacement.utf16.count, length: 0))
            XCTAssertNil(probe.selection)
        }
    }

    func testMediaReturnInsertsANewlineAndChatReturnSubmits() async throws {
        for newline in [true, false] {
            let probe = EditorProbe()
            probe.text = "A line"
            probe.returnInsertsNewline = newline
            let hosting = NSHostingView(rootView: EditorFixture(probe: probe))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            defer { window.contentView = nil }
            let editor = try await textView(in: hosting)
            XCTAssertEqual(editor.delegate?.textView?(editor, doCommandBy: #selector(NSResponder.insertNewline(_:))), true)
            try await settle(hosting)
            XCTAssertEqual(editor.string, newline ? "A line\n" : "A line")
            XCTAssertEqual(probe.submissions, newline ? 0 : 1)
        }
    }

    func testWrappingRecomputesWhenTheWorkspaceWidthChanges() async throws {
        let probe = EditorProbe()
        probe.text = String(repeating: "A coastal cabin in sunlight. ", count: 8)
        let hosting = NSHostingView(rootView: EditorFixture(probe: probe))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 360),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.contentView = nil }
        _ = try await textView(in: hosting)
        let wideHeight = probe.height
        window.setContentSize(NSSize(width: 260, height: 360))
        try await settle(hosting)
        XCTAssertGreaterThan(probe.height, wideHeight + 15,
                             "Opening an inspector must reflow the draft without another keystroke.")
        window.setContentSize(NSSize(width: 780, height: 360))
        try await settle(hosting)
        XCTAssertEqual(probe.height, wideHeight, accuracy: 1)
    }

    func testMediaSelectionSurvivesExternalMarkerInsertion() async throws {
        let probe = EditorProbe()
        probe.text = "A 🦊 in a meadow"
        let fox = try XCTUnwrap(probe.text.range(of: "🦊"))
        probe.selection = TextSelection(range: fox)
        let hosting = NSHostingView(rootView: EditorFixture(probe: probe))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.contentView = nil }
        let editor = try await textView(in: hosting)
        XCTAssertEqual(editor.selectedRange(), NSRange(fox, in: probe.text))

        probe.text = "A <Picture 1> in a meadow"
        let caret = try XCTUnwrap(probe.text.range(of: "<Picture 1>")).upperBound
        probe.selection = TextSelection(insertionPoint: caret)
        try await settle(hosting)
        XCTAssertEqual(editor.selectedRange(), NSRange(caret..<caret, in: probe.text),
                       "The caret must follow an inserted reference marker.")
    }

    func testNativeSelectionUpdatesTheMediaBinding() async throws {
        let probe = EditorProbe()
        probe.text = "A 🦊 in a meadow"
        let hosting = NSHostingView(rootView: EditorFixture(probe: probe))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.contentView = nil }
        let editor = try await textView(in: hosting)
        let fox = try XCTUnwrap(probe.text.range(of: "🦊"))
        editor.setSelectedRange(NSRange(fox, in: probe.text))
        try await settle(hosting)
        guard case .selection(let range) = probe.selection?.indices else {
            return XCTFail("Native selection must be available to reference insertion.")
        }
        XCTAssertEqual(String(probe.text[range]), "🦊")
    }

    func testSharedEditorUsesNativeGeometryAndBoundsLongDrafts() async throws {
        let probe = EditorProbe()
        let hosting = NSHostingView(rootView: EditorFixture(probe: probe))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.contentView = nil }
        let editor = try await textView(in: hosting)
        XCTAssertEqual(editor.textContainerInset.width, ComposerTextMetrics.containerInsetWidth)
        XCTAssertEqual(editor.textContainerInset.height, ComposerTextMetrics.containerInsetHeight)
        XCTAssertEqual(editor.textContainer?.lineFragmentPadding, ComposerTextMetrics.lineFragmentPadding)
        XCTAssertEqual(editor.font, NSFont.preferredFont(forTextStyle: .body))
        let shortHeight = probe.height
        probe.text = Array(repeating: "A line in a long prompt", count: 40).joined(separator: "\n")
        try await settle(hosting)
        XCTAssertGreaterThan(probe.height, shortHeight)
        XCTAssertLessThan(probe.height, 160)
        XCTAssertEqual(editor.enclosingScrollView?.hasVerticalScroller, true)
        probe.text = "Short"
        try await settle(hosting)
        XCTAssertEqual(probe.height, shortHeight, accuracy: 1)
    }

    private func textView<V: View>(in hosting: NSHostingView<V>) async throws -> NSTextView {
        try await settle(hosting)
        return try XCTUnwrap(findTextView(hosting))
    }

    private func findTextView(_ view: NSView) -> NSTextView? {
        if let text = view as? NSTextView { return text }
        return view.subviews.lazy.compactMap(findTextView).first
    }

    private func settle<V: View>(_ hosting: NSHostingView<V>) async throws {
        for _ in 0..<12 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
private final class EditorProbe: ObservableObject {
    @Published var text = ""
    @Published var selection: TextSelection?
    @Published var focused = false
    @Published var keepFocusRequested = false
    @Published var height: CGFloat = 36
    var returnInsertsNewline = false
    var submissions = 0
    var consumeCancel = false
    var cancelCalls = 0
    var consumeArrow = false
    var lastArrow: EditorArrow?
}

private struct EditorFixture: View {
    @ObservedObject var probe: EditorProbe

    var body: some View {
        GrowingTextEditor(text: $probe.text,
                          isFocused: probe.keepFocusRequested ? .constant(true) : $probe.focused,
                          measuredHeight: $probe.height, selection: $probe.selection,
                          maxLines: 6, isIdle: true, returnInsertsNewline: probe.returnInsertsNewline,
                          onSend: { probe.submissions += 1 },
                          onCancel: {
                              probe.cancelCalls += 1
                              return probe.consumeCancel
                          },
                          onArrow: { direction, start, end in
                              let name: String
                              switch direction {
                              case .up: name = "up"
                              case .down: name = "down"
                              }
                              probe.lastArrow = EditorArrow(direction: name, atStart: start, atEnd: end)
                              return probe.consumeArrow
                          })
            .composerTextField(height: probe.height, placeholder: probe.text.isEmpty ? "Prompt" : nil)
    }
}

private final class EditorFocusSink: NSView {
    override var acceptsFirstResponder: Bool { true }
}

private struct EditorArrow: Equatable {
    let direction: String
    let atStart: Bool
    let atEnd: Bool
}
