import AppKit
import SwiftUI
import XCTest
@testable import MLXCore

@MainActor
final class TranscriptDetailViewportTests: XCTestCase {
    func testReaderSizeStaysInsideThePresentingWindow() {
        for available in [CGSize(width: 400, height: 350), CGSize(width: 900, height: 700),
                          CGSize(width: 1800, height: 1200)] {
            let size = TranscriptDetailSizing.readerSize(in: available)
            XCTAssertLessThanOrEqual(size.width, available.width - 40)
            XCTAssertLessThanOrEqual(size.height, available.height - 80)
            XCTAssertLessThanOrEqual(size.width, 760)
            XCTAssertLessThanOrEqual(size.height, 640)
            XCTAssertGreaterThan(size.width, 0)
            XCTAssertGreaterThan(size.height, 0)
        }
    }

    func testLongContentIsBoundedWhileShortContentUsesItsNaturalHeight() async throws {
        let probe = TranscriptViewportProbe()
        let hosting = NSHostingView(rootView: TranscriptViewportFixture(probe: probe))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 800),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.contentView = nil }

        try await settle(hosting) { probe.height > 0 && probe.height < 60 }
        let shortHeight = probe.height

        probe.text = (0..<100).map { "Detail line \($0)" }.joined(separator: "\n")
        try await settle(hosting) { probe.height > shortHeight }
        XCTAssertLessThanOrEqual(probe.height, 240)
        XCTAssertGreaterThan(probe.height, 200)

        probe.text = "A short detail again."
        try await settle(hosting) { abs(probe.height - shortHeight) < 1 }
        XCTAssertEqual(probe.height, shortHeight, accuracy: 1)
    }

    private func settle<V: View>(_ hosting: NSHostingView<V>, until ready: () -> Bool) async throws {
        for _ in 0..<100 {
            hosting.layoutSubtreeIfNeeded()
            if ready() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The transcript detail layout did not settle.")
    }
}

@MainActor
private final class TranscriptViewportProbe: ObservableObject {
    @Published var text = "A short detail."
    var height: CGFloat = 0
}

private struct TranscriptViewportFixture: View {
    @ObservedObject var probe: TranscriptViewportProbe

    var body: some View {
        VStack(spacing: 0) {
            TranscriptDetailViewport {
                Text(verbatim: probe.text)
                    .font(.system(size: 14))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { probe.height = $0 }
            Spacer(minLength: 0)
        }
    }
}
