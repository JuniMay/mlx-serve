import AppKit
import SwiftUI
import XCTest
@testable import MLXCore

@MainActor
final class ModelBrowserSectionControlTests: XCTestCase {
    func testNativeSegmentTrackingUpdatesSectionAndReflectsExternalSelection() async throws {
        let selection = SectionSelection()
        let hosting = NSHostingView(rootView: SectionControlFixture(selection: selection))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 80),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.contentView = nil }
        try await settle(hosting)

        let controls = descendants(of: hosting).compactMap { $0 as? NSSegmentedControl }
        XCTAssertEqual(controls.count, 1, "One native control must own selection and press/drag tracking.")
        let control = try XCTUnwrap(controls.first)
        XCTAssertEqual(control.segmentCount, ModelBrowserSection.allCases.count)
        XCTAssertEqual(control.trackingMode, .selectOne)
        XCTAssertEqual(control.selectedSegment, 0)

        for (index, section) in ModelBrowserSection.allCases.enumerated() {
            let sent = await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    control.selectedSegment = index
                    continuation.resume(returning: control.sendAction(control.action, to: control.target))
                }
            }
            XCTAssertTrue(sent)
            try await settle(hosting)
            XCTAssertEqual(selection.section, section)
        }

        selection.section = .myModels
        hosting.rootView = SectionControlFixture(selection: selection, revision: 1)
        try await settle(hosting)
        XCTAssertEqual(control.selectedSegment, 2)
        XCTAssertEqual((0..<control.segmentCount).filter { control.isSelected(forSegment: $0) }, [2])
        XCTAssertTrue((control.label(forSegment: 2) ?? "").contains("4"))
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func settle<V: View>(_ hosting: NSHostingView<V>) async throws {
        for _ in 0..<5 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
private final class SectionSelection {
    var section: ModelBrowserSection = .recommended
}

private struct SectionControlFixture: View {
    let selection: SectionSelection
    // A changed root value tells SwiftUI to reread this test's non-observable reference.
    var revision = 0

    var body: some View {
        ModelBrowserSectionBar(section: Binding(get: { selection.section }, set: { selection.section = $0 }),
                               badges: .live(localModelCount: 4, activeDownloadCount: 0, mediaReadyCount: 1),
                               isDownloading: false)
            .frame(width: 800, height: 80)
    }
}
