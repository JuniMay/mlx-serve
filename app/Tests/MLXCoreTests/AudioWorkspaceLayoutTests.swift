import AppKit
import SwiftUI
import XCTest
@testable import MLXCore

@MainActor
final class AudioWorkspaceLayoutTests: XCTestCase {
    func testAudioWorkspaceKeepsItsStandardResultInset() async throws {
        let probe = AudioWorkspaceLayoutProbe()
        let hosting = NSHostingView(rootView: AudioWorkspaceLayoutFixture(probe: probe))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 740),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.contentView = nil }
        for _ in 0..<40 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(probe.workspace.isEmpty)
        XCTAssertFalse(probe.result.isEmpty)
        XCTAssertEqual(probe.result.minY - probe.workspace.minY, AppLayout.pageInset, accuracy: 1,
                       "The output canvas keeps the shared workspace inset.")
    }
}

@MainActor
private final class AudioWorkspaceLayoutProbe: ObservableObject {
    var workspace = CGRect.zero
    var result = CGRect.zero
}

private struct AudioWorkspaceLayoutFixture: View {
    @ObservedObject var probe: AudioWorkspaceLayoutProbe

    var body: some View {
        NavigationSplitView {
            Text("Library")
        } detail: {
            AudioGenView.workspace(selection: .constant(.music)) {
                GenerationWorkspace(title: "Music", modelName: "Example", prompt: {
                    TextField("Style", text: .constant("Piano"))
                }, model: {
                    Text("Model")
                }, attachments: {
                    EmptyView()
                }, parameters: {
                    Text("Duration")
                }, actions: {
                    Button("Generate") {}
                }, result: {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) }
                            action: { probe.result = $0 }
                })
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) }
                    action: { probe.workspace = $0 }
            }
            .navigationTitle("Music")
        }
    }
}
