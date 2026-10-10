import AppKit
import SwiftUI
import XCTest
@testable import MLXCore

final class ModelCatalogTableTests: XCTestCase {
    @MainActor
    func testProductionHeaderKeepsItsLeadingEdgeWhenTheParentMoves() async throws {
        func fixture(sidebarWidth: CGFloat) -> some View {
            HStack(spacing: 0) {
                Color.clear.frame(width: sidebarWidth)
                ModelCatalogTable {
                    LocalModelColumnHeader()
                } content: { measurement in
                    HStack(spacing: 8) {
                        Text("Fixture model").frame(maxWidth: .infinity, alignment: .leading)
                        Text("8 GB").frame(width: 90, alignment: .trailing)
                        Text("Use").frame(width: ModelBrowserMetrics.localActionWidth)
                    }
                    .padding(.vertical, 8)
                    .modifier(measurement)
                }
                .frame(width: 960)
                Spacer(minLength: 0)
            }
            .frame(width: 1280, height: 280)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        }
        let hosting = NSHostingView(rootView: fixture(sidebarWidth: 220))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 280),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.contentView = nil }
        for sidebarWidth: CGFloat in [220, 300] {
            hosting.rootView = fixture(sidebarWidth: sidebarWidth)
            try await settle(hosting)
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / 1280
            func leftmostText(from top: CGFloat, to bottom: CGFloat) throws -> CGFloat {
                var left: Int?
                for y in Int(top * scale)..<Int(bottom * scale) {
                    for x in Int((sidebarWidth + 5) * scale)..<Int((sidebarWidth + 680) * scale) {
                        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                        if max(color.redComponent, color.greenComponent, color.blueComponent) < 0.65 {
                            left = min(left ?? x, x)
                        }
                    }
                }
                return CGFloat(try XCTUnwrap(left)) / scale
            }
            let headingLeft = try leftmostText(from: 2, to: 24)
            let rowLeft = try leftmostText(from: 32, to: 80)
            XCTAssertEqual(headingLeft, rowLeft, accuracy: 2,
                           "The production heading and row text must align beside the sidebar.")
        }
    }

    @MainActor
    func testColumnHeadingsMatchNativeListRowsWithPreferredScrollerStyle() async throws {
        let defaults = UserDefaults.standard
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain) }
        let requestedStyle = ProcessInfo.processInfo.environment["MODEL_CATALOG_SCROLLER_STYLE"]
        if let requestedStyle {
            var overrides = arguments
            overrides["AppleShowScrollBars"] = requestedStyle == "overlay" ? "WhenScrolling" : "Always"
            defaults.setVolatileDomain(overrides, forName: UserDefaults.argumentDomain)
        }
        let style = NSScroller.preferredScrollerStyle
        if let requestedStyle {
            XCTAssertEqual(style, requestedStyle == "overlay" ? .overlay : .legacy)
        }
        for width in [ModelBrowserMetrics.minDetailWidth, CGFloat(960)] {
            for direction in [LayoutDirection.leftToRight, .rightToLeft] {
                for grouped in [false, true] {
                    let frames = ColumnFrames()
                    let hosting = NSHostingView(rootView:
                        HStack(spacing: 0) {
                            Color.clear.frame(width: 220)
                            TableFixture(frames: frames, grouped: grouped)
                                .environment(\.layoutDirection, direction)
                                .frame(width: width, height: 280)
                        }
                        .frame(width: width + 220, height: 280))
                    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width + 220, height: 280),
                                          styleMask: [.borderless], backing: .buffered, defer: false)
                    window.contentView = hosting
                    defer { window.contentView = nil }
                    try await settle(hosting)
                    let scroll = try XCTUnwrap(scrollView(in: hosting))
                    scroll.hasVerticalScroller = true
                    scroll.autohidesScrollers = false
                    scroll.tile()
                    try await settle(hosting)
                    XCTAssertEqual(scroll.scrollerStyle, style)
                    XCTAssertGreaterThan(try XCTUnwrap(scroll.documentView).bounds.height,
                                         scroll.contentView.bounds.height)
                    let context = "width=\(width), scroller=\(style.rawValue), grouped=\(grouped), direction=\(direction)"
                    for column in ["name", "size", "actions"] {
                        let header = try XCTUnwrap(frames.values["header.\(column)"], context)
                        let row = try XCTUnwrap(frames.values["row.\(column)"], context)
                        XCTAssertEqual(header.minX, row.minX, accuracy: 0.5, "\(column) leading: \(context)")
                        XCTAssertEqual(header.maxX, row.maxX, accuracy: 0.5, "\(column) trailing: \(context)")
                    }
                    let name = try XCTUnwrap(frames.values["row.name"])
                    let actions = try XCTUnwrap(frames.values["row.actions"])
                    XCTAssertEqual(frames.availableWidth, name.union(actions).width, accuracy: 0.5,
                                   "Column tiers must use the native list's available width: \(context)")
                }
            }
        }
    }

    @MainActor
    private func settle(_ hosting: NSView) async throws {
        for _ in 0..<20 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @MainActor
    private func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.scrollView(in: $0) }.first
    }
}

@MainActor
private final class ColumnFrames {
    var values: [String: CGRect] = [:]
    var availableWidth: CGFloat = 0
}

private struct TableFixture: View {
    let frames: ColumnFrames
    let grouped: Bool

    var body: some View {
        ModelCatalogTable(onColumnWidthChange: { frames.availableWidth = $0 }) {
            columns(prefix: "header")
        } content: { measurement in
            if grouped {
                Section("On this Mac") { rows(measurement: measurement) }
            } else {
                rows(measurement: measurement)
            }
        }
    }

    private func rows(measurement: ModelCatalogColumnMeasurement) -> some View {
        ForEach(0..<30) { index in
            columns(prefix: index == 0 ? "row" : nil)
                .padding(.vertical, 8)
                .modifier(measurement.when(index == 0))
        }
    }

    private func columns(prefix: String?) -> some View {
        HStack(spacing: ModelBrowserMetrics.columnSpacing) {
            Text("Model")
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    if let prefix { frames.values["\(prefix).name"] = $0 }
                }
            Text("Size")
                .frame(width: 90, alignment: .trailing)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    if let prefix { frames.values["\(prefix).size"] = $0 }
                }
            Text("Actions")
                .frame(width: ModelBrowserMetrics.localActionWidth)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    if let prefix { frames.values["\(prefix).actions"] = $0 }
                }
        }
    }
}
