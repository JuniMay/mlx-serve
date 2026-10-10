import AppKit
import SwiftUI
import XCTest
@testable import MLXCore

@MainActor
final class WorkspaceSplitViewTests: XCTestCase {
    func testSidebarSurvivesNavigationBetweenInteractionAndManagementPages() async throws {
        let probe = WorkspaceSplitProbe()
        let hosting = NSHostingView(rootView: WorkspaceSplitFixture(probe: probe))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.contentView = nil }
        try await settle(hosting)
        XCTAssertEqual(probe.sidebarCreations, 1)

        for workspace: ChatWorkspace in [.models(.myModels), .agents, .tasks, .conversation] {
            probe.workspace = workspace
            try await settle(hosting)
            XCTAssertEqual(probe.sidebarCreations, 1, "Navigation to \(workspace) replaced the sidebar.")
        }
    }

    private func settle<V: View>(_ hosting: NSHostingView<V>) async throws {
        for _ in 0..<10 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
private final class WorkspaceSplitProbe: ObservableObject {
    @Published var workspace = ChatWorkspace.conversation
    var sidebarCreations = 0
}

private struct WorkspaceSplitFixture: View {
    @ObservedObject var probe: WorkspaceSplitProbe

    var body: some View {
        WorkspaceSplitView(hasSecondaryList: probe.workspace.isThreeColumn) {
            SidebarLifetimeProbe(probe: probe)
        } secondary: {
            Text("Items")
        } detail: {
            Text(String(describing: probe.workspace))
        }
    }
}

private struct SidebarLifetimeProbe: NSViewRepresentable {
    let probe: WorkspaceSplitProbe

    func makeNSView(context: Context) -> NSView {
        probe.sidebarCreations += 1
        return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
