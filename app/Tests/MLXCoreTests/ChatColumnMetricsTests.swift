import XCTest
import AppKit
import SwiftUI
@testable import MLXCore

/// Reading measure for the chat column.
///
/// The measure used to be a fixed 740pt: on a fullscreen window that left
/// roughly 40-50% dead space on either side, because the panel next to the
/// session sidebar is wider than 740/0.8. It is now proportional — 80% of
/// the detail column's measured width, centered — so the column grows with
/// the window instead of stopping at a hardcoded cap. The transcript, the
/// composer, and the empty-state greeting all share the same measure: a
/// composer narrower or wider than the answer above it is the seam you
/// can't unsee.
final class ChatColumnMetricsTests: XCTestCase {

    /// Pinned so "make it a bit wider" is a decision someone makes on
    /// purpose. Below 0.7 it's back to visible dead space; above 0.9 prose
    /// runs close enough to the window edge to lose the "column" feel.
    func testTheMeasureIsProportionalAndInTheReadableBand() {
        XCTAssertGreaterThanOrEqual(ChatMetrics.contentWidthFraction, 0.7)
        XCTAssertLessThanOrEqual(ChatMetrics.contentWidthFraction, 0.9)
    }

    /// The fallback only covers the single frame before `ChatDetailView`
    /// measures its own width — it should still sit in a sane reading-width
    /// range so that frame doesn't flash something absurd.
    func testTheFallbackIsInTheReadableRange() {
        XCTAssertGreaterThanOrEqual(ChatMetrics.contentFallbackWidth, 640)
        XCTAssertLessThanOrEqual(ChatMetrics.contentFallbackWidth, 820)
    }

    @MainActor
    func testSharedColumnCentersContentWithTheSameEdges() async throws {
        for panelWidth: CGFloat in [320, 900, 1600] {
            let probe = ColumnFrameProbe()
            let width = min(740, panelWidth - 2 * ChatMetrics.gutter)
            let content = VStack {
                Color.clear.frame(height: 20)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { probe.first = $0 }
                    .chatColumn(width: width)
                Text("Composer").frame(maxWidth: .infinity)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { probe.second = $0 }
                    .chatColumn(width: width)
            }
            let hosting = NSHostingView(rootView: content)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 100),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            defer { window.contentView = nil }
            for _ in 0..<10 {
                hosting.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertEqual(probe.first.width, width, accuracy: 1)
            XCTAssertEqual(probe.first.minX, probe.second.minX, accuracy: 1)
            XCTAssertEqual(probe.first.maxX, probe.second.maxX, accuracy: 1)
            XCTAssertEqual(probe.first.midX, panelWidth / 2, accuracy: 1)
        }
    }
}

private final class ColumnFrameProbe {
    var first = CGRect.zero
    var second = CGRect.zero
}
