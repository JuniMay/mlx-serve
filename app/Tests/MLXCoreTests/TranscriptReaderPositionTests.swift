import AppKit
import SwiftUI
import XCTest
@testable import MLXCore

@MainActor
final class TranscriptReaderPositionTests: XCTestCase {
    func testEnlargeAndReduceKeepTheHeaderAndInnerReadingPosition() async throws {
        try await checkReaderPosition(initiallyPinned: false)
    }

    func testEnlargeAndReduceKeepTheHeaderWhenTheConversationWasFollowingTheEnd() async throws {
        try await checkReaderPosition(initiallyPinned: true)
    }

    func testOpenAndCloseKeepTheHeaderWhileBrowsingHistory() async throws {
        try await checkDisclosurePosition(initiallyPinned: false)
    }

    func testOpenAndCloseKeepTheHeaderWhenTheConversationWasFollowingTheEnd() async throws {
        try await checkDisclosurePosition(initiallyPinned: true)
    }

    private func checkDisclosurePosition(initiallyPinned: Bool) async throws {
        let probe = ReaderPositionProbe(initiallyPinned: initiallyPinned, expanded: false)
        let hosting = NSHostingView(rootView: ReaderPositionFixture(probe: probe))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 1_000),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.contentView = nil }
        try await settle(hosting)
        probe.moveOuter?(160)
        try await settle(hosting)
        let headerTop = probe.headerTop
        let offset = probe.outerOffset
        XCTAssertEqual(offset, 160, accuracy: 1)

        probe.toggle?()
        try await settle(hosting)
        XCTAssertEqual(probe.headerTop, headerTop, accuracy: 1)
        XCTAssertEqual(probe.outerOffset, offset, accuracy: 1)
        XCTAssertEqual(scrollViews(in: hosting).filter { $0.documentView is NSTextView }.count, 1)

        probe.toggle?()
        try await settle(hosting)
        XCTAssertEqual(probe.headerTop, headerTop, accuracy: 1)
        XCTAssertEqual(probe.outerOffset, offset, accuracy: 1)
        XCTAssertTrue(scrollViews(in: hosting).filter { $0.documentView is NSTextView }.isEmpty)
    }

    private func checkReaderPosition(initiallyPinned: Bool) async throws {
        let probe = ReaderPositionProbe(initiallyPinned: initiallyPinned)
        let hosting = NSHostingView(rootView: ReaderPositionFixture(probe: probe))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 1_000),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.contentView = nil }
        try await settle(hosting)
        let reader = try XCTUnwrap(scrollViews(in: hosting).first { $0.documentView is NSTextView })
        reader.contentView.scroll(to: NSPoint(x: 0, y: 100))
        reader.reflectScrolledClipView(reader.contentView)
        try await settle(hosting)

        let headerTop = probe.headerTop
        let offset = probe.outerOffset
        let innerOffset = reader.contentView.bounds.origin.y
        let initialHeight = reader.frame.height
        XCTAssertEqual(offset, 0, accuracy: 1)
        XCTAssertGreaterThan(innerOffset, 0)
        probe.resize?(true)
        try await settle(hosting)

        XCTAssertGreaterThan(reader.frame.height, initialHeight)
        XCTAssertEqual(probe.headerTop, headerTop, accuracy: 1)
        XCTAssertEqual(probe.outerOffset, offset, accuracy: 1)
        XCTAssertEqual(reader.contentView.bounds.origin.y, innerOffset, accuracy: 1)

        probe.resize?(false)
        try await settle(hosting)
        XCTAssertEqual(reader.frame.height, initialHeight, accuracy: 1)
        XCTAssertEqual(probe.headerTop, headerTop, accuracy: 1)
        XCTAssertEqual(probe.outerOffset, offset, accuracy: 1)
        XCTAssertEqual(reader.contentView.bounds.origin.y, innerOffset, accuracy: 1)
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap { scrollViews(in: $0) }
    }

    private func settle<V: View>(_ view: NSHostingView<V>) async throws {
        for _ in 0..<20 {
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
private final class ReaderPositionProbe: ObservableObject {
    let scroll = ChatScrollModel()
    let initiallyPinned: Bool
    let startsExpanded: Bool
    @Published var expanded: Bool
    @Published var enlarged = false
    var resize: ((Bool) -> Void)?
    var toggle: (() -> Void)?
    var moveOuter: ((CGFloat) -> Void)?
    var headerTop: CGFloat = 0
    var outerOffset: CGFloat = 0

    init(initiallyPinned: Bool, expanded: Bool = true) {
        self.initiallyPinned = initiallyPinned
        self.startsExpanded = expanded
        self.expanded = expanded
        guard !initiallyPinned else { return }
        _ = scroll.apply(.driverChanged(.user))
        _ = scroll.apply(.geometryChanged(distanceFromBottom: 10_000))
        _ = scroll.apply(.driverChanged(.idle))
    }
}

private struct ReaderPositionFixture: View {
    @ObservedObject var probe: ReaderPositionProbe
    @ObservedObject private var scroll: ChatScrollModel
    @State private var position = ScrollPosition(idType: Never.self, edge: .top)
    private let reasoning = String(repeating: "A complete thought.\n", count: 4_000)

    init(probe: ReaderPositionProbe) {
        self.probe = probe
        scroll = probe.scroll
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.clear.frame(height: 200)
                TranscriptDetailPanel(isExpanded: probe.expanded) {
                    HStack {
                        Text("Thinking")
                        Spacer()
                        TranscriptDetailActions(textToCopy: reasoning,
                            isEnlarged: Binding(get: { probe.enlarged }, set: { probe.resize?($0) }))
                    }
                } content: {
                    TranscriptDetailText(text: reasoning, maximumHeight: probe.enlarged ? 640 : 240)
                }
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: {
                    probe.headerTop = $0
                }
                Color.clear.frame(height: probe.initiallyPinned && probe.startsExpanded ? 200 : 2_000)
            }
        }
        .defaultScrollAnchor(.top, for: .initialOffset)
        .defaultScrollAnchor(scroll.isPinnedToBottom ? .bottom : nil, for: .sizeChanges)
        .scrollPosition($position)
        .onScrollGeometryChange(for: CGFloat.self) {
            ChatScrollState.distanceFromBottom($0)
        } action: { _, distance in
            apply(.geometryChanged(distanceFromBottom: distance))
        }
        .onScrollGeometryChange(for: CGPoint.self) {
            CGPoint(x: $0.contentOffset.y, y: $0.contentSize.height)
        } action: { _, geometry in
            probe.outerOffset = geometry.x
            apply(.contentGeometry(offsetY: geometry.x, contentHeight: geometry.y))
        }
        .onAppear {
            probe.resize = { enlarged in
                apply(.readerWillResize)
                probe.enlarged = enlarged
            }
            probe.moveOuter = { position.scrollTo(y: $0) }
            probe.toggle = {
                apply(.readerWillResize)
                probe.expanded.toggle()
            }
        }
    }

    private func apply(_ event: ChatScrollEvent) {
        guard case .toOffset(let offset) = probe.scroll.apply(event) else { return }
        DispatchQueue.main.async { position.scrollTo(y: offset) }
    }
}
