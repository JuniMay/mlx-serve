import AppKit
import SwiftUI
import XCTest
@testable import MLXCore

@MainActor
final class ModelPickerScrollViewTests: XCTestCase {
    func testThreeLongModelRowsFitWithoutClipping() async throws {
        let contentHeight = try await fittedHeight(modelRows(count: 3))
        let viewportHeight = try await constrainedViewportHeight(rowCount: 3)
        XCTAssertGreaterThan(contentHeight, 100)
        XCTAssertLessThan(contentHeight, 300)
        XCTAssertGreaterThanOrEqual(viewportHeight, contentHeight - 1)
    }

    func testLongListHasABoundedUsableViewport() async throws {
        let contentHeight = try await fittedHeight(modelRows(count: 30))
        let viewportHeight = try await constrainedViewportHeight(rowCount: 30)
        XCTAssertGreaterThan(contentHeight, 300)
        XCTAssertGreaterThanOrEqual(viewportHeight, 200)
        XCTAssertLessThanOrEqual(viewportHeight, 300)
    }

    private func constrainedViewportHeight(rowCount: Int) async throws -> CGFloat {
        let probe = ModelPickerViewportProbe()
        let page = VStack(alignment: .leading, spacing: 12) {
            Label("Select model", systemImage: "chevron.left").frame(height: 24)
            ModelPickerScrollView { modelRows(count: rowCount) }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { probe.height = $0 }
            Divider()
            Button("Manage Models…") {}.frame(height: 24)
        }
        .padding(16)
        .frame(width: 340)
        let hosting = NSHostingView(rootView: page)
        // The model page first receives the compact thinking page's proposal.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 135),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.contentView = nil }
        for _ in 0..<12 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertGreaterThan(hosting.fittingSize.height, 135)
        return probe.height
    }

    private func fittedHeight<Content: View>(_ content: Content) async throws -> CGFloat {
        let hosting = NSHostingView(rootView: content.frame(width: 308))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 308, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.contentView = nil }
        for _ in 0..<12 {
            hosting.setFrameSize(hosting.fittingSize)
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        return hosting.fittingSize.height
    }

    private func modelRows(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("On This Mac").font(.caption)
            ForEach(0..<count, id: \.self) { index in
                Button {} label: {
                    HStack(spacing: 12) {
                        Text(verbatim: "Qwen-3.5-27B-Instruct-Long-Model-Name-IQ4_XS-\(index).gguf")
                            .font(.body)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "checkmark").opacity(index == 0 ? 1 : 0)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

private final class ModelPickerViewportProbe {
    var height: CGFloat = 0
}
