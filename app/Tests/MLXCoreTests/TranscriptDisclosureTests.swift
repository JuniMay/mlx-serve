import AppKit
import SwiftUI
import XCTest
@testable import MLXCore

@MainActor
final class TranscriptDisclosureTests: XCTestCase {
    func testDisclosureKeepsHeaderInPlaceAndBoundsExpandedContent() async throws {
        let probe = DisclosureProbe()
        let hosting = NSHostingView(rootView: DisclosureFixture(probe: probe))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.contentView = nil }
        try await settle(hosting)

        XCTAssertEqual(probe.detailHeight, 0)
        let headerFrame = probe.headerFrame
        probe.expanded.toggle()
        try await settle(hosting)
        XCTAssertTrue(probe.expanded)
        XCTAssertGreaterThan(probe.detailHeight, 0)
        XCTAssertLessThanOrEqual(probe.detailHeight, 240)
        XCTAssertEqual(probe.headerFrame.minX, headerFrame.minX, accuracy: 1)
        XCTAssertEqual(probe.headerFrame.minY, headerFrame.minY, accuracy: 1)

        probe.expanded.toggle()
        try await settle(hosting)
        XCTAssertFalse(probe.expanded)
        XCTAssertEqual(probe.detailHeight, 0)
    }

    private func settle<V: View>(_ hosting: NSHostingView<V>) async throws {
        for _ in 0..<10 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
private final class DisclosureProbe: ObservableObject {
    @Published var expanded = false
    var detailHeight: CGFloat = 0
    var headerFrame = CGRect.zero
    var readerActions = 0
    var stopActions = 0
}

private struct DisclosureFixture: View {
    @ObservedObject var probe: DisclosureProbe

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TranscriptDetailPanel(isExpanded: probe.expanded) {
                HStack {
                    TranscriptDisclosureButton(isExpanded: probe.expanded) {
                        probe.expanded.toggle()
                    } label: { Text("Thinking") }
                    .accessibilityIdentifier("disclosure")
                    Button("Enlarge") { probe.readerActions += 1 }.accessibilityIdentifier("enlarge")
                    Button("Stop") { probe.stopActions += 1 }.accessibilityIdentifier("stop")
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { probe.headerFrame = $0 }
            } content: {
                TranscriptDetailViewport {
                    Text(String(repeating: "Detail\n", count: 100)).transcriptDetailText()
                        .padding(AppLayout.contentInset)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { probe.detailHeight = $0 }
                .onDisappear { probe.detailHeight = 0 }
            }
            Spacer(minLength: 0)
        }
    }
}
