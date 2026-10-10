import AppKit
import SwiftUI
import XCTest
@testable import MLXCore

@MainActor
final class ComposerControlsLayoutTests: XCTestCase {
    func testControlsKeepVisibleGapsAtWideAndWrappedWidths() async throws {
        for width: CGFloat in [900, 400] {
            let row = ComposerControlsRow {
                Probe().frame(width: 160, height: 30)
            } model: {
                Probe().frame(width: 270, height: 30)
            } actions: {
                Probe().frame(width: 72, height: 30)
            }
            let hosting = NSHostingView(rootView: row)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 100),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            defer { window.contentView = nil }
            for _ in 0..<12 {
                hosting.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(10))
            }
            func probes(_ view: NSView) -> [ProbeView] {
                (view as? ProbeView).map { [$0] } ?? view.subviews.flatMap(probes)
            }
            let frames = probes(hosting).filter { !$0.isHiddenOrHasHiddenAncestor }
                .map { $0.convert($0.bounds, to: hosting) }
            XCTAssertEqual(frames.count, 3)
            for a in frames {
                XCTAssertGreaterThanOrEqual(a.minX, -1)
                XCTAssertLessThanOrEqual(a.maxX, width + 1)
                for b in frames where b.minX > a.minX && abs(b.midY - a.midY) < 1 {
                    XCTAssertGreaterThanOrEqual(b.minX - a.maxX, 10,
                        "Separate dock controls need a visible gap at width \(width).")
                }
            }
        }
    }
}

private struct Probe: NSViewRepresentable {
    func makeNSView(context: Context) -> ProbeView { ProbeView() }
    func updateNSView(_ view: ProbeView, context: Context) {}
}

private final class ProbeView: NSView {}
