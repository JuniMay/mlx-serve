import AppKit
import SwiftUI
import XCTest
@testable import MLXCore

@MainActor
final class SettingsSectionResolutionTests: XCTestCase {
    func testEmptySectionsDisappearAndQueryChangesPreserveContentState() async throws {
        let probe = SectionResolutionProbe()
        let hosting = NSHostingView(rootView: SectionResolutionFixture(probe: probe))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.contentView = nil }

        func settle(query: String, rows: Set<String>, sections: Int) async throws {
            probe.query = query
            for _ in 0..<100 {
                hosting.layoutSubtreeIfNeeded()
                if Set(probe.tokens.keys) == rows && probe.sections == sections { return }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTFail("Query \(query): expected \(rows) in \(sections) sections, got \(probe.tokens.keys) in \(probe.sections)")
        }

        try await settle(query: "", rows: ["Alpha", "Beta"], sections: 2)
        let initialTokens = probe.tokens
        try await settle(query: "Alpha", rows: ["Alpha"], sections: 1)
        XCTAssertEqual(probe.tokens["Alpha"], initialTokens["Alpha"])
        try await settle(query: "no match", rows: [], sections: 0)
        try await settle(query: "Beta", rows: ["Beta"], sections: 1)
        XCTAssertEqual(probe.tokens["Beta"], initialTokens["Beta"])
        try await settle(query: "", rows: ["Alpha", "Beta"], sections: 2)
        XCTAssertEqual(probe.tokens, initialTokens)
    }
}

@MainActor
private final class SectionResolutionProbe: ObservableObject {
    @Published var query = ""
    var tokens: [String: UUID] = [:]
    var sections = -1
}

private struct SectionResolutionFixture: View {
    @ObservedObject var probe: SectionResolutionProbe

    var body: some View {
        Form {
            ForEach(sections: SettingsFormSections { content }) { section in
                Section {
                    section.content
                } header: {
                    section.header
                } footer: {
                    section.footer
                }
                .preference(key: ResolvedSectionIDsKey.self, value: [section.id])
            }
        }
        .formStyle(.grouped)
        .environment(\.settingsSearchQuery, probe.query)
        .onPreferenceChange(ResolvedTokensKey.self) { probe.tokens = $0 }
        .onPreferenceChange(ResolvedSectionIDsKey.self) { probe.sections = $0.count }
    }

    @ViewBuilder private var content: some View {
        Section("Alpha section") { StatefulSearchContent(title: "Alpha") }
        Section("Beta section") { StatefulSearchContent(title: "Beta") }
    }
}

private struct StatefulSearchContent: View {
    let title: String
    @State private var token = UUID()

    var body: some View {
        SearchableRow(searchText: [title]) {
            Text(title).preference(key: ResolvedTokensKey.self, value: [title: token])
        }
    }
}

private struct ResolvedTokensKey: PreferenceKey {
    static let defaultValue: [String: UUID] = [:]
    static func reduce(value: inout [String: UUID], nextValue: () -> [String: UUID]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct ResolvedSectionIDsKey: PreferenceKey {
    static let defaultValue: Set<SectionConfiguration.ID> = []
    static func reduce(value: inout Set<SectionConfiguration.ID>, nextValue: () -> Set<SectionConfiguration.ID>) {
        value.formUnion(nextValue())
    }
}
