import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Preferences in the dedicated Settings window. Bindings flow
/// through `appState.serverOptions`; AppState's `didSet` auto-saves to
/// UserDefaults.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var server: ServerManager

    /// Live filter text. Pushed down the tree via `\.settingsSearchQuery`;
    /// every row decides for itself whether to stay on screen (see
    /// `SearchableRow`), and every section collapses when nothing inside it
    /// survived. The matching rule is pure and tested — `SettingsSearch`.
    @State private var searchQuery = ""

    @State private var selection: SettingsSelection = .initial

    /// Rows still visible under the current filter, summed up the tree from
    /// `SettingsVisibleRowCountKey`. Drives the "no matches" placeholder.
    @State private var visibleRows = SettingsVisibleRows()

    /// What the sections below the containers edit — see `SettingsFormState`.
    @StateObject private var formState = SettingsFormState()

    private var filtering: Bool { !SettingsSearch.tokens(searchQuery).isEmpty }

    private var windowTitle: String {
        switch selection {
        case .category(let category): L10n.text(category.sidebarLabel)
        case .all: L10n.text("Search Settings")
        }
    }

    /// Categories the form actually renders for the active engine — the sidebar
    /// must never offer a section that isn't there.
    private var categories: [SettingsCategory] {
        SettingsCategory.visible(engine: server.modelInfo?.engine,
                                 selfUpdate: BuildFeatures.current.selfUpdate)
    }

    var body: some View {
        shell
        .navigationTitle(windowTitle)
        .searchable(text: $searchQuery, placement: .sidebar, prompt: "Search Settings")
        .onChange(of: searchQuery) { _, query in
            selection = SettingsSelection.afterQueryEdit(query: query, current: selection)
        }
        .onChange(of: categories) { _, visible in
            selection = SettingsSelection.reconciled(selection, visible: visible)
        }
        .onAppear(perform: applyOpenRequest)
        .onChange(of: appState.pendingSettingsOpenTick) { _, _ in
            applyOpenRequest()
        }
    }

    private func applyOpenRequest() {
        let requested = appState.settingsCategoryRequest
        selection = SettingsSelection.afterOpen(requested: requested, current: selection, visible: categories)
        if requested != nil { searchQuery = "" }
    }

    private var shell: some View {
        NavigationSplitView {
            categoryList
        } detail: {
            form
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var categoryList: some View {
        SettingsSidebar(categories: categories, selection: $selection) {
            // Picking a category clears the search: the two are alternative
            // ways to narrow, and letting them stack strands the user on an
            // empty pane with a stale query they can't see.
            searchQuery = ""
        }
    }

    private var form: some View {
        VStack(spacing: 0) {
            if server.needsRestartFor(appState.serverOptions) {
                RestartBanner()
            }
            Form {
                SettingsFormSections { sections }
            }
            .formStyle(.grouped)
            ResetDefaultsFooter()
                .environment(\.settingsSelection, selection == .category(.general) ? .all : selection)
        }
        .environment(\.settingsSearchQuery, searchQuery)
        .environment(\.settingsSelection, selection)
        .environment(\.settingsVisibleRows, visibleRows)
        .environmentObject(formState)
        .onPreferenceChange(SettingsVisibleRowCountKey.self) { visibleRows = $0 }
    }

    /// Search and category browsing share the same sections and bindings.
    @ViewBuilder
    private var sections: some View {
        SettingsSection(
            category: .general,
            subtitle: "Choose how the app and server start."
        ) {
            GeneralSectionContent()
        }
        SettingsSection(
            category: .modelFolders,
            subtitle: "Download and discovery folders. Every listed folder is served; restart after changes."
        ) {
            ModelFoldersSectionContent()
        }
        SettingsSection(
            category: .server,
            subtitle: "Connection and server settings. Restart to apply changes."
        ) {
            ServerSectionContent()
        }
        SettingsSection(
            category: .lanSharing,
            subtitle: "Share and discover models on your local network. Restart to apply."
        ) {
            LanSharingSectionContent()
        }
        SettingsSection(
            category: .providers,
            subtitle: "OpenAI-compatible chat services. Changes apply when saved."
        ) {
            ProvidersSectionContent()
        }
        // Keep destinations stable while showing each engine's applicable controls.
        EngineAwareSections()
        SettingsSection(
            category: .requestDefaults,
            subtitle: "Defaults for all clients. Apply to the next request without a restart."
        ) {
            GlobalGenerationDefaultsView()
            ModelThinkingSettings()
        }

        SettingsSection(
            category: .appearance,
            subtitle: "Colors, text size, and terminal appearance. Changes apply immediately."
        ) {
            AppearanceSectionContent()
        }

        SettingsSection(
            category: .voice,
            subtitle: "Voice engine and hands-free controls. Changes apply to the next sentence."
        ) {
            WakePhraseSectionContent()
            VoiceCloneSectionContent()
        }

        SettingsSection(
            category: .tools,
            subtitle: "Choose available tools and connected services. Conversations can override these defaults."
        ) {
            ChatToolsSectionContent()
        }

        SettingsSection(
            category: .sandbox,
            subtitle: BuildFeatures.current.hostShell
                ? "Run agent shell commands in an isolated Linux environment. Off by default."
                : "Agent shell commands run in the bundled Linux environment."
        ) {
            SandboxSectionContent()
        }

        SettingsSection(category: .about, subtitle: "App and embedded engine versions.") {
            AboutSectionContent()
        }

        if filtering && visibleRows.total == 0 {
            NoSearchResults(query: searchQuery) { searchQuery = "" }
        }

    }
}

// MARK: - Sidebar

/// Search spans all categories; normal browsing shows one category at a time.
private struct SettingsSidebar: View {
    let categories: [SettingsCategory]
    @Binding var selection: SettingsSelection
    /// Run when the user picks a row — clears the search field (a category and a
    /// query never coexist).
    let onPick: () -> Void

    var body: some View {
        List(selection: Binding(
            get: { selection },
            set: { newValue in
                selection = newValue
                onPick()
            }
        )) {
            ForEach(categories) { category in
                Label(L10n.text(category.sidebarLabel), systemImage: category.icon)
                    .tag(SettingsSelection.category(category))
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
    }
}

// MARK: - Search plumbing

/// The active filter text, pushed down to every row. A section whose *header*
/// matches re-publishes a blank query to its children so the whole section
/// shows (searching "Cache" should reveal its limits, not just the rows
/// whose own text happens to contain the word).
private struct SettingsSearchQueryKey: EnvironmentKey {
    static let defaultValue: String = ""
}

extension EnvironmentValues {
    var settingsSearchQuery: String {
        get { self[SettingsSearchQueryKey.self] }
        set { self[SettingsSearchQueryKey.self] = newValue }
    }
}

private struct SettingsSearchSectionKey: EnvironmentKey {
    static let defaultValue: SettingsCategory? = nil
}

private struct SettingsVisibleRowsKey: EnvironmentKey {
    static let defaultValue = SettingsVisibleRows()
}

extension EnvironmentValues {
    fileprivate var settingsSearchSection: SettingsCategory? {
        get { self[SettingsSearchSectionKey.self] }
        set { self[SettingsSearchSectionKey.self] = newValue }
    }

    fileprivate var settingsVisibleRows: SettingsVisibleRows {
        get { self[SettingsVisibleRowsKey.self] }
        set { self[SettingsVisibleRowsKey.self] = newValue }
    }
}

/// The sidebar's category filter, pushed down so each `SettingsSection` — and
/// `EngineAwareSections`, which builds its own — can decide whether it renders.
private struct SettingsSelectionKey: EnvironmentKey {
    static let defaultValue: SettingsSelection = .all
}

extension EnvironmentValues {
    var settingsSelection: SettingsSelection {
        get { self[SettingsSelectionKey.self] }
        set { self[SettingsSelectionKey.self] = newValue }
    }
}

/// Number of rows that survived the filter, summed up the view tree. Sections
/// read it to decide whether to collapse; the root reads it to decide whether
/// to show the "no matches" placeholder.
private struct SettingsVisibleRowCountKey: PreferenceKey {
    static let defaultValue = SettingsVisibleRows()
    static func reduce(value: inout SettingsVisibleRows, nextValue: () -> SettingsVisibleRows) {
        value.merge(nextValue())
    }
}

/// Wraps one row so the filter can hide it, and reports it as visible when it
/// survives. `searchText` is conventionally `[label, description]` — the same
/// text the row renders, so what you read is what you can search for.
struct SearchableRow<Content: View>: View {
    let searchText: [String]
    @ViewBuilder var content: Content

    @Environment(\.settingsSearchQuery) private var query
    @Environment(\.settingsSearchSection) private var section

    var body: some View {
        if SettingsSearch.matches(query: query, in: searchText) {
            content.preference(key: SettingsVisibleRowCountKey.self, value: .row(in: section))
        }
    }
}

/// Shown when the filter matches nothing at all.
private struct NoSearchResults: View {
    let query: String
    let clear: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.app(.title2))
                .foregroundStyle(.secondary)
            Text(L10n.format("No settings match \"%@\"", query))
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
            Button(action: clear, label: { Text(L10n.text("Clear filter"))
                .font(.app(.body)) })
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - Reset to Defaults footer

/// Restores the selected section; General also offers the existing global reset.
private struct ResetDefaultsFooter: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.settingsSelection) private var selection
    @State private var showConfirm = false
    @State private var resetError: String?

    private var label: String { SettingsReset.buttonLabel(selection) }

    private var helpText: String { SettingsReset.confirmMessage(selection) }

    /// Nothing to reset in this section → no button.
    private var hidden: Bool {
        if case .category(let c) = selection { return !SettingsReset.isResettable(c) }
        return false
    }

    var body: some View {
        if !hidden {
            SearchableRow(searchText: [label, helpText]) {
                VStack(alignment: .trailing, spacing: 6) {
                    if selection == .all {
                        Text("Keeps startup, appearance, folders, providers, and your workspace.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button(role: .destructive) {
                        showConfirm = true
                    } label: {
                        Label(L10n.text(label), systemImage: "arrow.uturn.backward.circle").font(.app(.body))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(helpText)
                    if let resetError { Text(verbatim: resetError).font(.app(.caption)).foregroundStyle(.red) }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 20)
                .confirmationDialog(
                    SettingsReset.confirmTitle(selection),
                    isPresented: $showConfirm,
                    titleVisibility: .visible
                ) {
                    Button(role: .destructive) {
                        do {
                            if selection == .all || selection == .category(.requestDefaults) {
                                try GenerationDefaultsFile.save(.init())
                            }
                            appState.serverOptions = SettingsReset.apply(selection, to: appState.serverOptions)
                            resetError = nil
                        } catch { resetError = "Could not reset generation defaults: \(error.localizedDescription)" }
                    } label: { Text("Reset")
                        .font(.app(.body)) }
                    Button(role: .cancel) { } label: { Text("Cancel")
                        .font(.app(.body)) }
                    .keyboardShortcut(.defaultAction)
                } message: {
                    Text(L10n.text(helpText))
                }
            }
        }
    }
}

// MARK: - Restart banner

private struct RestartBanner: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var server: ServerManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.app(.title2))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("Some changes require a server restart"))
                    .font(.app(.subheadline).weight(.semibold))
                Text(L10n.text("Click Restart Now to apply, or Discard to revert the unsaved server-launch fields."))
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                let opts = appState.serverOptions
                let model = appState.selectedModelPath
                server.stop()
                if !model.isEmpty {
                    server.start(modelPath: model, options: opts)
                }
            } label: { Text("Restart Now")
                .font(.app(.body)) }
            .buttonStyle(.borderedProminent)
            .disabled(appState.selectedModelPath.isEmpty)

            Button {
                if let last = server.lastLaunchedOptions {
                    // Revert every server-launch field to the last-launched
                    // snapshot; per-request defaults are preserved. Start
                    // from `last` (which has all server fields right) and
                    // patch the per-request fields back from `current` so
                    // the user's mid-session sampler tweaks survive.
                    let current = appState.serverOptions
                    var reverted = last
                    reverted.defaultMaxTokens       = current.defaultMaxTokens
                    reverted.defaultTemperature     = current.defaultTemperature
                    reverted.defaultTopP            = current.defaultTopP
                    reverted.defaultTopK            = current.defaultTopK
                    reverted.defaultRepeatPenalty   = current.defaultRepeatPenalty
                    reverted.defaultPresencePenalty = current.defaultPresencePenalty
                    reverted.defaultReasoningBudget = current.defaultReasoningBudget
                    reverted.defaultEnableThinking  = current.defaultEnableThinking
                    reverted.perRequestEnablePLD    = current.perRequestEnablePLD
                    reverted.perRequestEnableDrafter = current.perRequestEnableDrafter
                    appState.serverOptions = reverted
                }
            } label: { Text("Discard")
                .font(.app(.body)) }
            .buttonStyle(.bordered)
            .disabled(server.lastLaunchedOptions == nil)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.orange.opacity(0.10))
        .overlay(Divider(), alignment: .bottom)
    }
}

// MARK: - Engine-aware section composer

/// Categories stay stable while engine-specific controls follow the active model.
private struct EngineAwareSections: View {
    @EnvironmentObject var server: ServerManager

    var body: some View {
        let engine = server.modelInfo?.engine
        let showMLX = engine?.isMlxPath ?? true
        let showLlama = engine == nil || engine == .llama
        let showDSpark = engine == nil || showMLX || engine == .dsv4

        SettingsSection(category: .memory, subtitle: "Model residency and available memory. Restart to apply.") {
            MemorySectionContent(showMLX: showMLX)
        }
        SettingsSection(category: .cache, subtitle: "Reuse processed prompts and manage cache memory and disk space. Restart to apply.") {
            CacheSectionContent(showMLX: showMLX, showLlama: showLlama)
        }
        SettingsSection(category: .performance, subtitle: "Generation throughput and hardware acceleration. Restart to apply.") {
            if showMLX { PerformanceSectionContent() }
            SettingsSubheader("Neural Engine acceleration")
            NeuralEngineSectionContent()
        }
        SettingsSection(category: .specDecode, subtitle: "Draft several tokens and verify them together on compatible models. Restart to apply.") {
            SpecDecodeSectionContent(showMLX: showMLX, showLlama: showLlama, showDSpark: showDSpark)
        }
        SettingsSection(category: .engines, subtitle: "GGUF engine settings. Restart to apply.") {
            EnginesSectionContent()
        }
    }
}

// MARK: - Section frame

struct SettingsFormSections<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ForEach(sections: content) { section in
            if !section.content.isEmpty {
                Section {
                    section.content
                } header: {
                    section.header
                } footer: {
                    section.footer
                }
            }
        }
    }
}

private struct SettingsSection<Content: View>: View {
    /// Identity. The sidebar row and this header both read their text from it,
    /// so a section can never exist without a way to reach it (and its two
    /// labels can't drift). Pinned by `testEverySettingsSectionDeclaresACategory`.
    let category: SettingsCategory
    let subtitle: String
    @ViewBuilder var content: Content

    @Environment(\.settingsSearchQuery) private var query
    @Environment(\.settingsSelection) private var selection

    private var title: String { category.title }

    /// Both filter decisions (what query the rows see, whether to hide the
    /// chrome) live in the pure, tested `SettingsSearch.SectionFilter`.
    private var filter: SettingsSearch.SectionFilter {
        SettingsSearch.section(query: query, title: title)
    }

    @ViewBuilder
    var body: some View {
        // Sidebar filter. Unlike the search filter below — which must keep a
        // collapsed section's rows in the tree so they can publish their count
        // and bring the section back — this one drops the subtree outright. It
        // can: a category is only ever selected while the search field is EMPTY
        // (SettingsSelection's invariant), so no row count depends on it.
        if selection.shows(category) {
            sectionBody
        }
    }

    @ViewBuilder
    private var sectionBody: some View {
        // Keep filtered rows mounted so a later query can publish a nonzero
        // count and restore the section header.
        Section {
            content
                .environment(\.settingsSearchQuery, filter.childQuery)
                .environment(\.settingsSearchSection, category)
        } header: {
            SettingsSectionHeader(category: category, subtitle: subtitle)
        }
    }
}

struct SettingsSectionHeader: View {
    let category: SettingsCategory
    let subtitle: String
    @Environment(\.settingsSelection) private var selection
    @Environment(\.settingsSearchQuery) private var query
    @Environment(\.settingsVisibleRows) private var visibleRows

    var body: some View {
        let filter = SettingsSearch.section(query: query, title: category.title)
        if !filter.collapsed(visibleRows: visibleRows.count(in: category)) {
            VStack(alignment: .leading, spacing: 4) {
                if selection == .all {
                    Text(L10n.text(category.title)).font(.headline)
                }
                Text(L10n.text(subtitle))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - One row helper

private struct SettingsRow<Control: View>: View {
    let title: String
    let explainer: String
    var summary: String? = nil
    var note: String? = nil
    /// True when this field has been changed since the running server was
    /// last launched — i.e. the user has edited it but not yet hit "Restart
    /// Now". Drives the orange restart icon. False (or always-false for
    /// per-request fields) hides the icon. We deliberately don't show it on
    /// every server-launch row by default — that's noisy when nothing has
    /// actually been changed yet.
    var isDirty: Bool = false
    /// The setting's memory/disk cost; orange and bold while it is switched on.
    var cost: String? = nil
    var costActive: Bool = false
    var leadingControl: Bool = false
    @ViewBuilder var control: Control

    var body: some View {
        let help = SettingsHelpText(explainer: explainer, summary: summary)
        SearchableRow(searchText: [title] + help.searchText + [note, cost].compactMap { $0 }) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                if leadingControl {
                    control.accessibilityLabel(Text(L10n.text(title)))
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(L10n.text(title))
                            .font(.body)
                        if let details = help.details {
                            SettingsHelpButton(title: title, details: details)
                        }
                        if isDirty {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .help("Restart the server to apply this change")
                                .accessibilityLabel("Restart required")
                        }
                    }
                    if !help.caption.isEmpty {
                        Text(L10n.text(help.caption))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let note {
                        Text(L10n.text(note))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let cost {
                        Text(L10n.text(cost))
                            .font(.caption)
                            .fontWeight(costActive ? .semibold : .regular)
                            .foregroundStyle(costActive ? Color.orange : Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !leadingControl {
                    control
                        .frame(width: 280, alignment: .trailing)
                        .accessibilityLabel(Text(L10n.text(title)))
                }
            }
        }
    }
}

private struct SettingsHelpButton: View {
    let title: String
    let details: String
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.borderless)
        .help("More information")
        .accessibilityLabel(L10n.format("About %@", L10n.text(title)))
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text(title)).font(.headline)
                Text(L10n.text(details))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(20)
            .frame(width: 380)
        }
    }
}

/// Shared dirty-bit helper. Compares a single `ServerOptions` keypath against
/// the snapshot the server was last launched with. Returns false until the
/// server has been launched at least once (no baseline to compare against).
fileprivate struct ServerLaunchDirty {
    let current: ServerOptions
    let last: ServerOptions?

    func dirty<V: Equatable>(_ keyPath: KeyPath<ServerOptions, V>) -> Bool {
        guard let last else { return false }
        return current[keyPath: keyPath] != last[keyPath: keyPath]
    }
}

// MARK: - Model folders section

/// One row showing the user-configured extra discovery root. The path is
/// rendered verbatim (raw, not standardized) so the user sees exactly what
/// they picked; discovery silently skips it when it doesn't resolve to an
/// existing directory. Picking a folder triggers an immediate refresh so the
/// menu-bar picker updates without a server restart.
private struct ModelFoldersSectionContent: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var downloads: DownloadManager

    private static let explainer = "Accepts both flat layout (<name>/config.json) and 2-level layout (<author>/<name>/config.json)."
    private static let defaultExplainer = "Where new downloads are saved. Everything already downloaded keeps working — the old folder stays in the scan list. Restart the server to apply."

    /// Re-read after a pick so the row repaints without an @Published mirror of
    /// a value that lives in UserDefaults.
    @State private var downloadFolderTick = 0

    var body: some View {
        if BuildFeatures.current.customModelFolders { defaultFolderRow }
        customFolderRow
    }

    // MARK: - Default (download destination)

    @ViewBuilder
    private var defaultFolderRow: some View {
        let roots = ModelRoots()
        let configured = roots.configuredDownloadRoot
        let unavailable = roots.downloadRootIsUnavailable
        SearchableRow(searchText: ["Default folder", "download", Self.defaultExplainer]) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L10n.text("Default folder"))
                        .font(.app(.body))
                    Spacer(minLength: 12)
                    HStack(spacing: 8) {
                        Text(configured ?? roots.downloadRoot)
                            .font(.app(.caption).monospaced())
                            // An unreachable folder is shown in the warning
                            // colour rather than swapped for the fallback: the
                            // path the user chose is the thing they need to see
                            // to understand where their downloads went instead.
                            .foregroundStyle(unavailable ? AnyShapeStyle(.orange) : AnyShapeStyle(configured == nil ? .secondary : .primary))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 220, alignment: .trailing)
                        Button { chooseDownloadFolder() } label: { Text("Choose…")
                            .font(.app(.body)) }
                            .buttonStyle(.bordered)
                        Button {
                            SecurityScopedBookmark.clear(name: DownloadManager.downloadFolderBookmarkName)
                            ModelRoots().configuredDownloadRoot = nil
                            applyFolderChange()
                        } label: { Text("Reset")
                            .font(.app(.body)) }
                        .buttonStyle(.bordered)
                        .disabled(configured == nil)
                    }
                }
                Text(unavailable
                     ? L10n.format("That folder isn't reachable right now, so downloads are going to %@ instead.", ModelRoots.builtInRoot)
                     : L10n.text(Self.defaultExplainer))
                    .font(.app(.caption2))
                    .foregroundStyle(unavailable ? .orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .id(downloadFolderTick)
        }
    }

    private func chooseDownloadFolder() {
        let panel = OpenPanel.make()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "New model downloads will be saved here."
        if let existing = ModelRoots().configuredDownloadRoot {
            panel.directoryURL = URL(fileURLWithPath: (existing as NSString).expandingTildeInPath)
        }
        guard AppActivation.runModal(panel) == .OK, let url = panel.url else { return }
        // Store the bookmark while the panel's grant is still live — the same
        // rule the agent-workspace picker follows.
        SecurityScopedBookmark.store(url, name: DownloadManager.downloadFolderBookmarkName)
        SecurityScopedBookmark.startAccessOnce(name: DownloadManager.downloadFolderBookmarkName)
        ModelRoots().configuredDownloadRoot = url.path
        applyFolderChange()
    }

    /// One place for "the library's folders changed": the downloader re-reads
    /// its destination, the app rescans, and the server needs a restart to pick
    /// up the new `--model-dir` set (the banner at the top of Settings says so).
    private func applyFolderChange() {
        downloads.refreshRoots()
        appState.refreshModels()
        downloadFolderTick += 1
    }

    // MARK: - Custom (extra scan folder)

    private var customFolderRow: some View {
        let pathText: String = {
            let raw = downloads.customRoot?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return raw.isEmpty ? "(none)" : raw
        }()
        let hasPath = !(downloads.customRoot?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        return SearchableRow(searchText: ["Custom folder", Self.explainer]) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L10n.text("Custom folder"))
                        .font(.app(.body))
                    Spacer(minLength: 12)
                    HStack(spacing: 8) {
                        Text(L10n.text(pathText))
                            .font(.app(.caption).monospaced())
                            .foregroundStyle(hasPath ? .primary : .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 220, alignment: .trailing)
                        Button { choose() } label: { Text("Choose…")
                            .font(.app(.body)) }
                            .buttonStyle(.bordered)
                        Button {
                            downloads.customRoot = nil
                            appState.refreshModels()
                        } label: { Text("Clear")
                            .font(.app(.body)) }
                        .buttonStyle(.bordered)
                        .disabled(!hasPath)
                    }
                }
                Text(L10n.text(Self.explainer))
                    .font(.app(.caption2))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func choose() {
        let panel = OpenPanel.make()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if let existing = downloads.customRoot,
           !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            panel.directoryURL = URL(fileURLWithPath: (existing as NSString).expandingTildeInPath)
        }
        if AppActivation.runModal(panel) == .OK, let url = panel.url {
            downloads.customRoot = url.path
            appState.refreshModels()
        }
    }
}

// MARK: - Server section

// MARK: - LAN sharing section

private struct LanSharingSectionContent: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var server: ServerManager

    private var meta: [String: ServerOptionField] { ServerOptions.serverFlagFields }
    private var dirty: ServerLaunchDirty {
        ServerLaunchDirty(current: appState.serverOptions, last: server.liveLaunchedOptions)
    }

    var body: some View {
        if let m = meta["lanShareEnabled"] {
            SettingsRow(title: m.title, explainer: m.explainer, summary: m.summary, isDirty: dirty.dirty(\.lanShareEnabled)) {
                Toggle("", isOn: $appState.serverOptions.lanShareEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch).font(.app(.body))
            }
        }
        if appState.serverOptions.lanShareEnabled {
            if let m = meta["lanShareAll"] {
                SettingsRow(title: m.title, explainer: m.explainer, summary: m.summary, isDirty: dirty.dirty(\.lanShareAll)) {
                    Toggle("", isOn: $appState.serverOptions.lanShareAll)
                        .labelsHidden()
                        .toggleStyle(.switch).font(.app(.body))
                }
            }
            if !appState.serverOptions.lanShareAll {
                sharedModelList
            }
            if let m = meta["lanName"] {
                SettingsRow(title: m.title, explainer: m.explainer, summary: m.summary, isDirty: dirty.dirty(\.lanName)) {
                    TextField(
                        "",
                        text: $appState.serverOptions.lanName,
                        prompt: Text(Host.current().localizedName ?? L10n.text("this Mac"))
                    )
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 200).font(.app(.body))
                }
            }
        }
        if let m = meta["lanDiscoverEnabled"] {
            SettingsRow(title: m.title, explainer: m.explainer, summary: m.summary, isDirty: dirty.dirty(\.lanDiscoverEnabled)) {
                Toggle("", isOn: $appState.serverOptions.lanDiscoverEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch).font(.app(.body))
            }
        }
        // The privacy disclosure — sharing means running other people's
        // prompts, and using a network model means the host reads yours.
        SearchableRow(searchText: ["Privacy", Self.privacyNote]) {
            Text(L10n.text(Self.privacyNote))
                .font(.app(.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    private static let privacyNote = "Privacy: prompts sent to a model you share are processed on — and visible to — this Mac. Prompts you send to a network model are visible to the Mac hosting it. Traffic stays on your local network, and everything here is off unless you turn it on."

    /// One checkbox per local model name. Names are deduped — a GGUF and an
    /// MLX build of the same repo share a name and are shared together (the
    /// server matches share entries against registry ids basename-tolerantly).
    private var sharedModelList: some View {
        let names = Array(Set(appState.localModels.map(\.name))).sorted()
        return VStack(alignment: .leading, spacing: 4) {
            if names.isEmpty {
                Text(L10n.text("No local models yet — download one first."))
                    .font(.app(.caption))
                    .foregroundStyle(.tertiary)
            }
            ForEach(names, id: \.self) { name in
                Toggle(name, isOn: Binding(
                    get: { appState.serverOptions.lanSharedModels.contains(name) },
                    set: { on in
                        var list = appState.serverOptions.lanSharedModels
                        list.removeAll { $0 == name }
                        if on { list.append(name) }
                        appState.serverOptions.lanSharedModels = list.sorted()
                    }
                ))
                .toggleStyle(.checkbox)
                .font(.app(.caption))
            }
        }
        .padding(.leading, 8)
        .padding(.vertical, 2)
    }
}

// MARK: - Providers section

/// Rows of `~/.mlx-serve/providers.json`. Every edit saves the file and asks
/// the running server to reload; the health dot is the server's own probe
/// (`GET /v1/providers`), never a guess made here.
private struct ProvidersSectionContent: View {
    @EnvironmentObject var server: ServerManager
    @EnvironmentObject var formState: SettingsFormState
    @State private var status: [ProviderStatus] = []
    @State private var saveError: String?

    var body: some View {
        // One searchable row: a section whose content publishes no row count
        // never collapses under the filter.
        SearchableRow(searchText: ["Providers", "OpenAI-compatible chat endpoints", "cloud API", "providers.json", "API key"]
                      + formState.providerEntries.map(\.name)) {
            providersBody
        }
    }

    private var providersBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if formState.providerEntries.isEmpty {
                Text(L10n.text("No providers yet."))
                    .font(.app(.caption))
                    .foregroundStyle(.tertiary)
            }
            ForEach($formState.providerEntries) { $entry in
                ProviderRow(entry: $entry,
                            serverPort: server.port,
                            status: status.first { $0.name == entry.name },
                            duplicate: ProvidersFile.duplicateNames(formState.providerEntries).contains(entry.name),
                            onDelete: { [id = entry.id] in
                                formState.removeProvider(id: id)
                                save()
                            },
                            onCommit: save)
            }
            HStack {
                Button { formState.providerEntries.append(ProviderEntry()) } label: { Label("Add Provider", systemImage: "plus") }
                Spacer()
                // Fields also save on Enter, but an edit followed by a click
                // elsewhere never submits — this is the button that always writes.
                Button { save() } label: { Text("Save")
                    .font(.app(.body)) }
                .keyboardShortcut("s", modifiers: .command)
                .help("Write providers.json and ask the server to re-probe now")
            }
            if let saveError {
                Text(L10n.text(saveError)).font(.app(.caption)).foregroundStyle(.red)
            }
            Text(L10n.text("Keys are stored in plain text in ~/.mlx-serve/providers.json. Prefer an environment variable name for a shared machine. Provider models are never shared over the LAN."))
                .font(.app(.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task { await refreshStatus() }
        .onChange(of: server.status) { _, s in
            if s == .running { Task { await refreshStatus() } }
        }
    }

    private func save() {
        do {
            try ProvidersFile.save(formState.providerEntries)
            saveError = nil
        } catch {
            saveError = "Could not save providers.json: \(error.localizedDescription)"
            return
        }
        Task {
            await server.reloadProviders()
            // The probe runs on the server's own thread right after reload.
            try? await Task.sleep(for: .seconds(2))
            await refreshStatus()
        }
    }

    private func refreshStatus() async {
        guard server.status == .running else { return }
        status = await server.providerStatus()
    }
}

private struct ProviderRow: View {
    @Binding var entry: ProviderEntry
    @EnvironmentObject var formState: SettingsFormState
    let serverPort: UInt16
    let status: ProviderStatus?
    let duplicate: Bool
    let onDelete: () -> Void
    let onCommit: () -> Void
    @State private var picking = false

    /// The model-id field's own text, held on the store: the entry keeps the
    /// parsed ids, so a rebuilt row would otherwise show the parsed list back.
    private var modelsText: Binding<String> {
        Binding(
            get: { formState.providerModelText[entry.id] ?? entry.models.joined(separator: ", ") },
            set: { formState.providerModelText[entry.id] = $0 }
        )
    }

    private var problem: String? {
        if duplicate { return "Another provider already uses this name" }
        return entry.problem(serverPort: serverPort)
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("Name").frame(width: 100, alignment: .leading)
                        TextField("Name", text: $entry.name, prompt: Text("Provider name")).onSubmit(onCommit)
                    }
                    GridRow {
                        Text("Endpoint")
                        TextField("Endpoint", text: $entry.url, prompt: Text("https://api.example.com/v1")).onSubmit(onCommit)
                    }
                    GridRow {
                        Text("API key")
                        SecureField("API key", text: $entry.apiKey, prompt: Text("Optional")).onSubmit(onCommit)
                    }
                    GridRow {
                        Text("Environment")
                        TextField("Environment variable", text: $entry.apiKeyEnv, prompt: Text("API key variable name")).onSubmit(onCommit)
                    }
                    GridRow {
                        Text("Models")
                        HStack(spacing: 8) {
                            TextField("Models", text: modelsText, prompt: Text("All models, or comma-separated IDs"))
                                .onChange(of: formState.providerModelText[entry.id]) { _, text in
                                    entry.models = ProviderEntry.parseModelList(text ?? "")
                                }
                                .onSubmit(onCommit)
                            Button("Choose…") { picking = true }
                                .disabled(entry.problem() != nil)
                                .help("Choose which models this provider exposes")
                        }
                    }
                }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                if let problem {
                    Text(L10n.text(problem)).font(.caption).foregroundStyle(.orange)
                } else if let status {
                    Text(L10n.text(statusLine(status))).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(8)
        } label: {
            HStack(spacing: 8) {
                Toggle("Enabled", isOn: $entry.enabled)
                    .toggleStyle(.switch)
                    .onChange(of: entry.enabled) { _, _ in onCommit() }
                Spacer(minLength: 12)
                healthDot
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove provider")
                    .help("Remove this provider")
            }
        }
        .sheet(isPresented: $picking) {
            ProviderModelPickerSheet(entry: entry) { chosen in
                formState.providerModelText[entry.id] = chosen.joined(separator: ", ")
                entry.models = chosen
                onCommit()
            }
        }
    }

    private var healthDot: some View {
        Circle()
            .fill(status.map { $0.up ? Color.green : ($0.probed ? Color.red : Color.gray) } ?? Color.gray)
            .frame(width: 8, height: 8)
            .help(status.map(statusLine) ?? "Not reported by the server yet")
    }

    private func statusLine(_ s: ProviderStatus) -> String {
        if !s.probed { return "Checking…" }
        return s.up ? "Up — \(s.models) model\(s.models == 1 ? "" : "s")" : "Unreachable"
    }
}

/// Fetches `<url>/models` with the row's key and lets the user tick the ids
/// to expose. Done writes the list back as the comma-separated field.
private struct ProviderModelPickerSheet: View {
    let entry: ProviderEntry
    let onDone: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var ids: [String] = []
    @State private var chosen: Set<String> = []
    @State private var filter = ""
    @State private var error: String?
    @State private var loading = true

    private var shown: [String] {
        filter.isEmpty ? ids : ids.filter { $0.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.format("Models at %@", entry.name)).font(.app(.headline))
            TextField("Filter", text: $filter).textFieldStyle(.roundedBorder)
            if loading {
                ProgressView().frame(maxWidth: .infinity)
            } else if let error {
                Text(error).foregroundStyle(.red).font(.app(.caption))
            } else {
                List(shown, id: \.self) { id in
                    Toggle(id, isOn: Binding(
                        get: { chosen.contains(id) },
                        set: { on in if on { chosen.insert(id) } else { chosen.remove(id) } }
                    ))
                }
                .listStyle(.plain)
            }
            HStack {
                Text("\(chosen.count) of \(ids.count) selected").font(.app(.caption)).foregroundStyle(.secondary)
                Button { chosen = [] } label: { Text("Clear")
                    .font(.app(.body)) }.disabled(chosen.isEmpty)
                Spacer()
                Button { dismiss() } label: { Text("Cancel")
                    .font(.app(.body)) }.keyboardShortcut(.cancelAction)
                Button {
                    onDone(ids.filter { chosen.contains($0) })
                    dismiss()
                } label: { Text("Done")
                    .font(.app(.body)) }
                .keyboardShortcut(.defaultAction)
                .disabled(loading)
            }
        }
        .padding()
        .frame(width: 460, height: 520)
        .task { await load() }
    }

    private func load() async {
        chosen = Set(entry.models)
        var key = entry.apiKey
        if !entry.apiKeyEnv.isEmpty {
            // `LoginShellEnv.values(of:)` spawns the user's login shell — blocking,
            // and documented as off-main only. This runs from `.task`, which
            // inherits the main actor, so it has to hop off before asking.
            let name = entry.apiKeyEnv
            let shell = await Task.detached(priority: .userInitiated) { LoginShellEnv.values(of: [name]) }.value
            if let v = shell[name], !v.isEmpty { key = v }
        }
        var lastError = "No model list at \(entry.url)"
        for url in ProviderEntry.modelsURLs(for: entry.url) {
            var req = URLRequest(url: url, timeoutInterval: 15)
            if !key.isEmpty { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if code == 200, let list = ProviderEntry.modelIds(fromModelsBody: data) {
                    ids = list.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                    loading = false
                    return
                }
                lastError = "HTTP \(code) from \(url.absoluteString)"
            } catch {
                lastError = error.localizedDescription
            }
        }
        self.error = lastError
        loading = false
    }
}

private struct GeneralSectionContent: View {
    @EnvironmentObject var appState: AppState

    /// Chat models only — the `isChatPickable` filter every other model picker uses.
    private var pickable: [LocalModel] {
        appState.localModels.filter(\.isChatPickable)
    }

    /// The tray picker's labels: a `.menu` Picker keys its checkmark by title, so
    /// duplicate labels get an engine suffix.
    private func startupModelLabel(_ model: LocalModel, dupNames: Set<String>) -> String {
        let label = model.displayLabel
        guard dupNames.contains(label) else { return label }
        return "\(label) · \(model.engine.shortLabel)"
    }

    /// Under "Last model used" the dropdown shows the rule's answer, read from the
    /// same `StartupModelChoice.resolved` as the launch gate. The setter only runs
    /// in `.pinned` mode; the control is disabled otherwise.
    private var startupModelDisplay: Binding<String> {
        Binding(
            get: {
                guard appState.startupModelMode == .lastUsed else {
                    return appState.startupModelPinnedPath
                }
                return StartupModelChoice.resolved(mode: .lastUsed,
                                                   pinnedPath: nil,
                                                   lastUsed: StartupModelChoice.lastUsed(),
                                                   installedPaths: pickable.map(\.path)) ?? ""
            },
            set: { appState.startupModelPinnedPath = $0 }
        )
    }

    var body: some View {
        // Same value as the tray's toggle.
        SettingsRow(
            title: "Start server when the app launches",
            explainer: "The server comes up as soon as the app does. Off means you start it from the tray.",
            summary: "Start the server automatically when you open the app."
        ) {
            Toggle("", isOn: $appState.autoStartServer)
                .labelsHidden()
                .toggleStyle(.switch).font(.app(.body))
        }
        SettingsRow(
            title: "Preload the model when the server starts",
            explainer: "Off by default: every start, automatic or from the Start Server button, comes up with no model resident and loads one on demand at your first message, so login stays fast. On pays for the load up front. A large checkpoint can take a while and holds the memory from the moment the server is up.",
            summary: "Uses memory while idle and may slow startup. When off, the model loads on first use."
        ) {
            Toggle("", isOn: $appState.loadModelAtStart)
                .labelsHidden()
                .toggleStyle(.switch).font(.app(.body))
        }
        SettingsRow(
            title: "Which model",
            explainer: "\"Last model used\" follows whatever you were last chatting with, decided when the app starts rather than when you set this — so it keeps up as you switch models. \"Always this model\" pins one regardless.",
            summary: "Preload your last chat model or always use one model."
        ) {
            Picker("", selection: $appState.startupModelMode) {
                ForEach(StartupModelChoice.Mode.allCases) { mode in
                    Text(L10n.text(mode.label)).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(!appState.loadModelAtStart).font(.app(.body))
        }
        SettingsRow(
            title: "Model",
            explainer: "If the pinned model is removed later — or nothing has been loaded yet — the server simply starts with nothing resident, rather than substituting a model you did not choose.",
            summary: "If this model is unavailable, the server starts without a model.",
            note: appState.startupModelMode == .lastUsed ? "Selected at each app launch." : nil
        ) {
            VStack(alignment: .trailing, spacing: 4) {
                Picker("", selection: startupModelDisplay) {
                    let dupNames = LocalModel.duplicateNames(in: pickable)
                    ForEach(pickable) { model in
                        Text(L10n.text(startupModelLabel(model, dupNames: dupNames))).font(.app(.body)).tag(model.path)
                    }
                    // A selection that matches no row renders blank, so empty and
                    // uninstalled selections each get a row of their own.
                    if startupModelDisplay.wrappedValue.isEmpty {
                        Text(L10n.text("None — starts with no model")).font(.app(.body)).tag("")
                    }
                    if !appState.startupModelPinnedPath.isEmpty,
                       !pickable.contains(where: { $0.path == appState.startupModelPinnedPath }) {
                        Text("\((appState.startupModelPinnedPath as NSString).lastPathComponent) — no longer installed").font(.app(.body))
                            .tag(appState.startupModelPinnedPath)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: 180, alignment: .trailing)
                .disabled(!appState.loadModelAtStart || appState.startupModelMode == .lastUsed)


            }
        }

    }
}

private struct ServerSectionContent: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var server: ServerManager

    private var meta: [String: ServerOptionField] { ServerOptions.serverFlagFields }
    private var dirty: ServerLaunchDirty {
        ServerLaunchDirty(current: appState.serverOptions, last: server.liveLaunchedOptions)
    }

    var body: some View {
        if let m = meta["host"] {
            SettingsRow(
                title: m.title,
                explainer: m.explainer, summary: m.summary,
                isDirty: dirty.dirty(\.host)
            ) {
                TextField(
                    "",
                    text: Binding(
                        get: { appState.serverOptions.host },
                        set: { appState.serverOptions.host = $0.trimmingCharacters(in: .whitespaces) }
                    ),
                    prompt: Text("0.0.0.0")
                )
                .textFieldStyle(.roundedBorder)
                .font(.app(.body).monospacedDigit())
                .multilineTextAlignment(.trailing)
                .frame(width: 160)
            }
        }
        PortRow()
        ContextSizeRow()
        if let m = meta["noVision"] {
            SettingsRow(
                title: m.title,
                explainer: m.explainer, summary: m.summary,
                isDirty: dirty.dirty(\.noVision)
            ) {
                Toggle("", isOn: $appState.serverOptions.noVision)
                    .labelsHidden()
                    .toggleStyle(.switch).font(.app(.body))
            }
        }
        if let m = meta["enableMetrics"] {
            SettingsRow(
                title: m.title,
                explainer: m.explainer, summary: m.summary,
                isDirty: dirty.dirty(\.enableMetrics)
            ) {
                Toggle("", isOn: $appState.serverOptions.enableMetrics)
                    .labelsHidden()
                    .toggleStyle(.switch).font(.app(.body))
            }
        }
        if let m = meta["apiKey"] {
            SettingsRow(
                title: m.title,
                explainer: m.explainer, summary: m.summary,
                isDirty: dirty.dirty(\.apiKey)
            ) {
                SecureField(
                    "",
                    text: Binding(
                        get: { appState.serverOptions.apiKey },
                        set: { appState.serverOptions.apiKey = $0.trimmingCharacters(in: .whitespaces) }
                    ),
                    prompt: Text("none")
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 180).font(.app(.body))
            }
        }
        if let m = meta["toolAutocorrect"] {
            SettingsRow(
                title: m.title,
                explainer: m.explainer, summary: m.summary,
                isDirty: dirty.dirty(\.toolAutocorrect)
            ) {
                Toggle("", isOn: $appState.serverOptions.toolAutocorrect)
                    .labelsHidden()
                    .toggleStyle(.switch).font(.app(.body))
            }
        }
        if let m = meta["logLevel"] {
            SettingsRow(
                title: m.title,
                explainer: m.explainer, summary: m.summary,
                isDirty: dirty.dirty(\.logLevel)
            ) {
                Picker("", selection: $appState.serverOptions.logLevel) {
                    ForEach(ServerOptions.LogLevel.allCases) { lvl in
                        Text(L10n.text(lvl.label)).font(.app(.body)).tag(lvl)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: 180, alignment: .trailing).font(.app(.body))
            }
        }
        if let m = meta["logToFile"] {
            SettingsRow(
                title: m.title,
                explainer: m.explainer, summary: m.summary,
                isDirty: dirty.dirty(\.logToFile)
            ) {
                Toggle("", isOn: $appState.serverOptions.logToFile)
                    .labelsHidden()
                    .toggleStyle(.switch).font(.app(.body))
            }
        }
    }
}

/// Port text field with commit-on-valid semantics. The field edits a local
/// string so the user can clear it or type through invalid intermediate
/// states; only values `ServerOptions.parsePort` accepts are committed to
/// storage. Submitting (or an external change like Reset to Defaults /
/// Discard) snaps the display back to the last committed value.
private struct PortRow: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var server: ServerManager
    @EnvironmentObject var formState: SettingsFormState

    /// The field's text lives on the store so what is being typed survives a
    /// query edit; nil means the field has not been shown yet.
    private var text: Binding<String> {
        Binding(get: { formState.portText ?? "" },
                set: { formState.portText = $0 })
    }

    private var isDirty: Bool {
        guard let last = server.liveLaunchedOptions else { return false }
        return appState.serverOptions.port != last.port
    }

    var body: some View {
        if let m = ServerOptions.serverFlagFields["port"] {
            SettingsRow(
                title: m.title,
                explainer: m.explainer, summary: m.summary,
                isDirty: isDirty
            ) {
                TextField("", text: text, prompt: Text("11234"))
                    .textFieldStyle(.roundedBorder)
                    .font(.app(.body).monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                    .onAppear {
                        if formState.portText == nil { formState.portText = "\(appState.serverOptions.port)" }
                    }
                    .onChange(of: formState.portText) { _, newValue in
                        if let p = ServerOptions.parsePort(newValue ?? "") {
                            appState.serverOptions.port = p
                        }
                    }
                    .onChange(of: appState.serverOptions.port) { _, newPort in
                        if ServerOptions.parsePort(formState.portText ?? "") != newPort {
                            formState.portText = "\(newPort)"
                        }
                    }
                    .onSubmit { formState.portText = "\(appState.serverOptions.port)" }
            }
        }
    }
}

private struct ContextSizeRow: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var server: ServerManager

    private var options: [Int] {
        ContextSizeDisplay.options(modelMaxTokens: server.modelInfo?.modelMaxTokens ?? 0,
                                   currentValue: appState.serverOptions.ctxSize)
    }

    private var status: String? {
        var values: [String] = []
        if let maximum = server.modelInfo?.modelMaxTokens, maximum > 0 {
            values.append("Model maximum: \(ContextSizeDisplay.formatTokens(maximum))")
        }
        if let safe = server.memoryInfo?.maxSafeContext, safe > 0 {
            values.append("Memory-safe maximum: \(ContextSizeDisplay.formatTokens(safe))")
        }
        if let current = ContextSizeDisplay.inUseValue(contextLength: server.modelInfo?.contextLength) {
            values.append("In use: \(current)")
        }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    private var warning: String? {
        let chosen = appState.serverOptions.ctxSize
        if let maximum = server.modelInfo?.modelMaxTokens, maximum > 0, chosen > maximum {
            return "The saved context exceeds this model's maximum. Choose a smaller value or Auto."
        }
        if let safe = server.memoryInfo?.maxSafeContext, safe > 0, chosen > safe {
            return "The selected context exceeds the current memory-safe maximum."
        }
        return nil
    }

    var body: some View {
        SettingsRow(
            title: "Context size",
            explainer: ContextSizeDisplay.helpText,
            summary: "Auto fits the context to available memory when the model loads.",
            note: status,
            isDirty: ServerLaunchDirty(current: appState.serverOptions, last: server.liveLaunchedOptions).dirty(\.ctxSize),
            cost: warning,
            costActive: warning != nil
        ) {
            Picker("Context size", selection: $appState.serverOptions.ctxSize) {
                ForEach(options, id: \.self) { value in
                    if value == 0 {
                        Text("Auto").tag(value)
                    } else {
                        Text("\(value.formatted()) tokens").tag(value)
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }
}

// MARK: - Spec-decode section

private struct SpecDecodeSectionContent: View {
    let showMLX: Bool
    let showLlama: Bool
    let showDSpark: Bool
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var server: ServerManager

    private var meta: [String: ServerOptionField] { ServerOptions.serverFlagFields }
    private var dirty: ServerLaunchDirty {
        ServerLaunchDirty(current: appState.serverOptions, last: server.liveLaunchedOptions)
    }

    var body: some View {
        let opts = $appState.serverOptions
        // Drafter and PLD are mutually exclusive at the request level
        // (`drafter > PLD > regular` in src/server.zig). When drafter is on
        // we lock the PLD toggles down so users can't accidentally enable a
        // setting that would never apply.
        let drafterActive = server.chatModelInfo?.drafterLoaded ?? false
        let pldUsable = appState.serverOptions.enablePLD && !drafterActive

        if showMLX {
            SettingsSubheader("Prompt reuse")
            if let m = meta["enablePLD"] {
                let lockNote = drafterActive
                    ? "Locked off while Drafter is on (Drafter takes priority)."
                    : nil
                SettingsRow(
                    title: m.title,
                    explainer: m.explainer,
                    summary: m.summary,
                    note: lockNote,
                    isDirty: dirty.dirty(\.enablePLD)
                ) {
                    Toggle("", isOn: opts.enablePLD)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(drafterActive).font(.app(.body))
                }
            }
            if let m = meta["pldDraftLen"] {
                SettingsRow(
                    title: m.title,
                    explainer: m.explainer, summary: m.summary,
                    isDirty: dirty.dirty(\.pldDraftLen)
                ) {
                    NumberStepper(title: m.title, value: opts.pldDraftLen, range: 1...16)
                    .disabled(!pldUsable)
                }
            }
            if let m = meta["pldKeyLen"] {
                SettingsRow(
                    title: m.title,
                    explainer: m.explainer, summary: m.summary,
                    isDirty: dirty.dirty(\.pldKeyLen)
                ) {
                    NumberStepper(title: m.title, value: opts.pldKeyLen, range: 1...8)
                    .disabled(!pldUsable)
                }
            }
        }
        if showMLX || showLlama {
            SettingsSubheader("Model prediction heads")
        }
        if showMLX {
            if let m = meta["enableMTP"] {
                SettingsRow(
                    title: m.title,
                    explainer: m.explainer, summary: m.summary,
                    isDirty: dirty.dirty(\.enableMTP)
                ) {
                    Toggle("", isOn: opts.enableMTP)
                        .labelsHidden()
                        .toggleStyle(.switch).font(.app(.body))
                }
            }
            if let m = meta["mtpDepth"] {
                SettingsRow(
                    title: m.title,
                    explainer: m.explainer, summary: m.summary,
                    isDirty: dirty.dirty(\.mtpDepth)
                ) {
                    // 0 is the server's "auto" sentinel (the adaptive controller);
                    // 1...6 is the fixed range it accepts — 7+ hits a measured
                    // occupancy cliff in the verify kernel, so it isn't offered.
                    Picker("", selection: opts.mtpDepth) {
                        // Automatic is ONE entry, probe-backed internally with the
                        // per-silicon table as fallback — shipping "Automatic"
                        // beside "Probe" would ask a question nobody can answer
                        // without benchmarking. It DISPLAYS what it resolved to
                        // instead (MLX_SERVE_SPEC_COST_PROBE=0 is the A/B arm).
                        if let specCost = server.specCost {
                            Text(L10n.format("Automatic (measured: %lld tokens)", Int64(specCost.mtpDepthCap))).font(.app(.body)).tag(0)
                        } else {
                            Text(L10n.text("Automatic")).font(.app(.body)).tag(0)
                        }
                        ForEach(1...6, id: \.self) { n in
                            Text("\(n) token\(n == 1 ? "" : "s")").font(.app(.body)).tag(n)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 140, alignment: .trailing)
                    .disabled(!appState.serverOptions.enableMTP).font(.app(.body))
                }
            }
        }
        if showLlama {
            if let m = meta["llamaMtpDrafts"] {
                SettingsRow(title: m.title, explainer: m.explainer, summary: m.summary, isDirty: dirty.dirty(\.llamaMtpDrafts)) {
                    HStack(spacing: 6) {
                        if appState.serverOptions.llamaMtpDrafts == 0 {
                            Text("Off").font(.app(.caption)).foregroundStyle(.secondary)
                        }
                        NumberStepper(title: m.title, value: opts.llamaMtpDrafts, range: 0...8)
                    }
                }
            }
        }
        if showMLX || showDSpark {
            SettingsSubheader("Assistant models")
            let drafterHelp = "Drafters are chosen per model: Model Settings, Speculation."
            SearchableRow(searchText: [drafterHelp]) {
                Text(L10n.text(drafterHelp))
                    .font(.app(.caption2))
                    .foregroundStyle(.secondary)
            }
        }
        if showDSpark {
            if let m = meta["enableDSpark"] {
                SettingsRow(
                    title: m.title,
                    explainer: m.explainer, summary: m.summary,
                    isDirty: dirty.dirty(\.enableDSpark)
                ) {
                    Toggle("", isOn: opts.enableDSpark)
                        .labelsHidden()
                        .toggleStyle(.switch).font(.app(.body))
                }
            }
        }
    }
}

/// Group labels hide while searching so filtered rows do not leave empty headings.
private struct SettingsSubheader: View {
    let text: String
    @Environment(\.settingsSearchQuery) private var query

    init(_ text: String) { self.text = text }

    var body: some View {
        if SettingsSearch.tokens(query).isEmpty {
            Text(L10n.text(text))
                .font(.app(.caption).weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }
}

// MARK: - Performance section

private struct PerformanceSectionContent: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var server: ServerManager

    private var meta: [String: ServerOptionField] { ServerOptions.serverFlagFields }
    private var dirty: ServerLaunchDirty {
        ServerLaunchDirty(current: appState.serverOptions, last: server.liveLaunchedOptions)
    }

    var body: some View {
        let opts = $appState.serverOptions

        if let m = meta["maxConcurrent"] {
            SettingsRow(
                title: m.title,
                explainer: m.explainer, summary: m.summary,
                note: server.batching?.label,
                isDirty: dirty.dirty(\.maxConcurrent)
            ) {
                NumberStepper(title: m.title, value: opts.maxConcurrent, range: 1...8)
            }
        }
        if let m = meta["decodeAttnQuant"] {
            SettingsRow(
                title: m.title,
                explainer: m.explainer, summary: m.summary,
                isDirty: dirty.dirty(\.decodeAttnQuantChoice)
            ) {
                // Tri-state under a binary toggle: untouched (nil) RENDERS as
                // the server default (on); touching it stores an explicit
                // choice — which is exactly what the positive flag form means
                // (it opts dsv4's characterization-gated requant in).
                Toggle("", isOn: Binding(
                    get: { appState.serverOptions.decodeAttnQuantChoice ?? true },
                    set: { appState.serverOptions.decodeAttnQuantChoice = $0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch).font(.app(.body))
            }
        }

    }
}

// MARK: - Memory section

/// Every engine memory knob in one place. The resident-model limits, the OS
/// reserve and the preflight apply to every engine; the KV and prefix-cache rows
/// and the n-gram table are MLX-only and hide when a GGUF/DSV4 model is serving.
private struct MemorySectionContent: View {
    let showMLX: Bool
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var server: ServerManager

    private var meta: [String: ServerOptionField] { ServerOptions.serverFlagFields }
    private var dirty: ServerLaunchDirty {
        ServerLaunchDirty(current: appState.serverOptions, last: server.liveLaunchedOptions)
    }

    var body: some View {
        let opts = $appState.serverOptions

        if let m = meta["maxResidentMemGB"] {
            SettingsRow(
                title: m.title,
                explainer: m.explainer, summary: m.summary,
                isDirty: dirty.dirty(\.maxResidentMemGB)
            ) {
                let gb = appState.serverOptions.maxResidentMemGB
                snappingSlider(
                    presets: ServerOptions.residentMemPresets(
                        physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory),
                    current: gb,
                    set: { appState.serverOptions.maxResidentMemGB = $0 },
                    label: gb == 0 ? "Auto" : "\(gb) GB"
                )
            }
        }
        if let m = meta["maxResidentModels"] {
            SettingsRow(
                title: m.title,
                explainer: m.explainer, summary: m.summary,
                isDirty: dirty.dirty(\.maxResidentModels)
            ) {
                NumberStepper(title: m.title, value: opts.maxResidentModels, range: 1...8)
            }
        }
        if let m = meta["idleEvictSecs"] {
            SettingsRow(
                title: m.title,
                explainer: m.explainer, summary: m.summary,
                isDirty: dirty.dirty(\.idleEvictSecs)
            ) {
                let secs = appState.serverOptions.idleEvictSecs
                snappingSlider(
                    presets: ServerOptions.idleEvictPresets,
                    current: secs,
                    set: { appState.serverOptions.idleEvictSecs = $0 },
                    label: ServerOptions.idleEvictLabel(secs)
                )
            }
        }
        if let m = meta["skipMemPreflight"] {
            SettingsRow(
                title: m.title,
                explainer: m.explainer, summary: m.summary,
                isDirty: dirty.dirty(\.skipMemPreflight)
            ) {
                Toggle("", isOn: opts.skipMemPreflight)
                    .labelsHidden()
                    .toggleStyle(.switch).font(.app(.body))
            }
        }
        if let m = meta["osReserveGiB"] {
            SettingsRow(
                title: m.title,
                explainer: m.explainer, summary: m.summary,
                isDirty: dirty.dirty(\.osReserveGiB)
            ) {
                let auto = ServerOptions.autoOsReserveGiB(physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory)
                Picker("", selection: opts.osReserveGiB) {
                    Text("Auto (\(auto.formatted(.number.precision(.fractionLength(0...1)))) GB)")
                        .font(.app(.body)).tag(Int?.none)
                    ForEach([0, 2, 3, 4, 6, 8], id: \.self) { gib in
                        Text(gib == 0 ? "Off" : "\(gib) GB").font(.app(.body)).tag(Int?.some(gib))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: 220, alignment: .trailing).font(.app(.body))
            }
        }
        if showMLX {
            if let m = meta["pleGpu"] {
                SettingsRow(
                    title: m.title,
                    explainer: m.explainer, summary: m.summary,
                    isDirty: dirty.dirty(\.pleGpu),
                    cost: m.cost,
                    costActive: appState.serverOptions.pleGpu
                ) {
                    Toggle("", isOn: opts.pleGpu)
                        .labelsHidden()
                        .toggleStyle(.switch).font(.app(.body))
                }
            }
        }
    }
}

// MARK: - Neural Engine acceleration

private struct NeuralEngineSectionContent: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var server: ServerManager

    private var meta: [String: ServerOptionField] { ServerOptions.serverFlagFields }
    private var dirty: ServerLaunchDirty {
        ServerLaunchDirty(current: appState.serverOptions, last: server.liveLaunchedOptions)
    }

    var body: some View {
        let opts = $appState.serverOptions

        if let m = meta["anePrefill"] {
            SettingsRow(
                title: "Prompt processing",
                explainer: m.explainer, summary: m.summary,
                note: AnePrefillAdvice.liveCaution,
                isDirty: dirty.dirty(\.anePrefill),
                cost: m.cost,
                costActive: appState.serverOptions.anePrefill
            ) {
                Toggle("", isOn: opts.anePrefill).labelsHidden().toggleStyle(.switch)
            }
        }
        if let m = meta["aneImage"] {
            SettingsRow(title: "Images", explainer: m.explainer, summary: m.summary, isDirty: dirty.dirty(\.aneImage),
                        cost: m.cost, costActive: appState.serverOptions.aneImage) {
                Toggle("", isOn: opts.aneImage).labelsHidden().toggleStyle(.switch).font(.app(.body))
            }
        }
        if let m = meta["aneVideo"] {
            SettingsRow(title: "Video", explainer: m.explainer, summary: m.summary, isDirty: dirty.dirty(\.aneVideo),
                        cost: m.cost, costActive: appState.serverOptions.aneVideo) {
                Toggle("", isOn: opts.aneVideo).labelsHidden().toggleStyle(.switch).font(.app(.body))
            }
        }
        if let m = meta["aneAudio"] {
            SettingsRow(title: "Music", explainer: m.explainer, summary: m.summary, isDirty: dirty.dirty(\.aneAudio),
                        cost: m.cost, costActive: appState.serverOptions.aneAudio) {
                Toggle("", isOn: opts.aneAudio).labelsHidden().toggleStyle(.switch).font(.app(.body))
            }
        }
    }
}

private struct CacheSectionContent: View {
    let showMLX: Bool
    let showLlama: Bool
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var server: ServerManager

    private var meta: [String: ServerOptionField] { ServerOptions.serverFlagFields }
    private var dirty: ServerLaunchDirty {
        ServerLaunchDirty(current: appState.serverOptions, last: server.liveLaunchedOptions)
    }

    var body: some View {
        let opts = $appState.serverOptions
        SettingsSubheader("Request reuse")
        if let m = meta["tokenizeCacheEntries"] {
            SettingsRow(
                title: m.title,
                explainer: m.explainer, summary: m.summary,
                isDirty: dirty.dirty(\.tokenizeCacheEntries)
            ) {
                NumberStepper(title: m.title, value: opts.tokenizeCacheEntries, range: 0...32)
            }
        }
        if showMLX {
            SettingsSubheader("Conversation cache in memory")
            if let m = meta["kvQuant"] {
                SettingsRow(
                    title: m.title,
                    explainer: m.explainer, summary: m.summary,
                    isDirty: dirty.dirty(\.kvQuant)
                ) {
                    Picker("", selection: opts.kvQuant) {
                        ForEach(ServerOptions.KVQuant.allCases) { q in
                            Text(L10n.text(q.label)).font(.app(.body)).tag(q)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(minWidth: 220, alignment: .trailing).font(.app(.body))
                }
            }
            if let m = meta["hotPrefixCacheEnabled"] {
                SettingsRow(
                    title: m.title,
                    explainer: m.explainer, summary: m.summary,
                    isDirty: dirty.dirty(\.hotPrefixCacheEnabled)
                ) {
                    Toggle("", isOn: opts.hotPrefixCacheEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch).font(.app(.body))
                }
            }
            if let m = meta["prefixCacheEntries"], appState.serverOptions.hotPrefixCacheEnabled {
                // Surface the RAM clamp so a 16 GB Mac user who sets, say, 8 sees
                // that the launcher will actually pass 1 (and why).
                let ram = ProcessInfo.processInfo.physicalMemory
                let set = appState.serverOptions.prefixCacheEntries
                let effective = ServerOptions.ramCappedPrefixCacheEntries(set, physicalMemoryBytes: ram)
                let capNote = effective < set
                    ? "  ·  This Mac (\(MemoryInfo.format(Int64(ram)))) launches with \(effective) to keep cache memory bounded."
                    : ""
                SettingsRow(
                    title: m.title,
                    explainer: m.explainer + capNote,
                    summary: effective < set ? nil : m.summary,
                    isDirty: dirty.dirty(\.prefixCacheEntries)
                ) {
                    NumberStepper(title: m.title, value: opts.prefixCacheEntries, range: 1...16)
                }
            }
            if let m = meta["prefixCacheMem"], appState.serverOptions.hotPrefixCacheEnabled {
                SettingsRow(
                    title: m.title,
                    explainer: m.explainer, summary: m.summary,
                    isDirty: dirty.dirty(\.prefixCacheMem)
                ) {
                    TextField("", text: opts.prefixCacheMem, prompt: Text("Auto"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                }
            }
            SettingsSubheader("Conversation cache on disk")
            if let m = meta["enablePrefixCacheDisk"] {
                SettingsRow(
                    title: m.title,
                    explainer: m.explainer, summary: m.summary,
                    isDirty: dirty.dirty(\.enablePrefixCacheDisk)
                ) {
                    Toggle("", isOn: opts.enablePrefixCacheDisk)
                        .labelsHidden()
                        .toggleStyle(.switch).font(.app(.body))
                }
            }
            if let m = meta["prefixCacheDisk"], appState.serverOptions.enablePrefixCacheDisk {
                SettingsRow(
                    title: m.title,
                    explainer: m.explainer, summary: m.summary,
                    isDirty: dirty.dirty(\.prefixCacheDisk)
                ) {
                    TextField("", text: opts.prefixCacheDisk, prompt: Text("10GB"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                }
            }
        }
        if showLlama {
            SettingsSubheader("GGUF conversation cache")
            if let m = meta["llamaKvQuant"] {
                SettingsRow(title: m.title, explainer: m.explainer, summary: m.summary, isDirty: dirty.dirty(\.llamaKvQuant)) {
                    Picker("", selection: opts.llamaKvQuant) {
                        ForEach(ServerOptions.LlamaKVQuant.allCases) { q in
                            Text(L10n.text(q.label)).font(.app(.body)).tag(q)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(minWidth: 260, alignment: .trailing).font(.app(.body))
                }
            }
            if let m = meta["llamaCacheEntries"] {
                SettingsRow(title: m.title, explainer: m.explainer, summary: m.summary, isDirty: dirty.dirty(\.llamaCacheEntries)) {
                    NumberStepper(title: m.title, value: opts.llamaCacheEntries, range: 1...8)
                }
            }
        }
    }
}

// MARK: - GGUF (llama.cpp) performance section

/// Every embedded engine's launch flags, grouped by engine.
private struct EnginesSectionContent: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var server: ServerManager
    @Environment(\.settingsSearchQuery) private var query

    private var meta: [String: ServerOptionField] { ServerOptions.serverFlagFields }
    private var dirty: ServerLaunchDirty {
        ServerLaunchDirty(current: appState.serverOptions, last: server.liveLaunchedOptions)
    }
    /// A search narrows to rows, so the engine boxes step aside while one runs.
    private var grouped: Bool { SettingsSearch.tokens(query).isEmpty }

    var body: some View {
        let opts = $appState.serverOptions
        EngineGroup(name: "mlx-serve-gguf", blurb: "GGUF files on MLX itself. Experimental.", boxed: grouped) {
            if let m = meta["mlxGguf"] {
                SettingsRow(title: m.title, explainer: m.explainer, summary: m.summary, isDirty: dirty.dirty(\.mlxGguf)) {
                    Toggle("", isOn: opts.mlxGguf)
                        .labelsHidden()
                        .toggleStyle(.switch).font(.app(.body))
                }
            }
        }
        EngineGroup(name: "llama.cpp", blurb: "Serves every other .gguf file. Its own kernels and KV layout, so the MLX rows do not apply.", boxed: grouped) {
            if let m = meta["llamaUbatch"] {
                SettingsRow(title: m.title, explainer: m.explainer, summary: m.summary, isDirty: dirty.dirty(\.llamaUbatch)) {
                    Picker("", selection: opts.llamaUbatch) {
                        Text(L10n.text("Default (512)")).font(.app(.body)).tag(0)
                        ForEach([1024, 2048, 4096], id: \.self) { n in
                            Text(verbatim: "\(n)").font(.app(.body)).tag(n)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(minWidth: 140, alignment: .trailing).font(.app(.body))
                }
            }
        }
        EngineGroup(name: "ds4", blurb: "Serves DeepSeek-V4-Flash GGUF files.", boxed: grouped) {
            if let m = meta["ssdStreaming"] {
                SettingsRow(title: m.title, explainer: m.explainer, summary: m.summary, isDirty: dirty.dirty(\.ssdStreaming)) {
                    Toggle("", isOn: opts.ssdStreaming)
                        .labelsHidden()
                        .toggleStyle(.switch).font(.app(.body))
                }
            }
        }
    }
}

/// One engine's rows in a box under its name. Unboxed, the rows sit bare in the
/// section, so a search that filters every row out leaves no empty box behind.
private struct EngineGroup<Content: View>: View {
    let name: String
    let blurb: String
    let boxed: Bool
    @ViewBuilder var content: Content

    var body: some View {
        if boxed {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.app(.headline))
                    Text(L10n.text(blurb)).font(.app(.caption2)).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 18) { content }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: AppLayout.surfaceRadius).fill(Color.secondary.opacity(0.08)))
        } else {
            content
        }
    }
}


// MARK: - Saved model thinking

private struct ModelThinkingSettings: View {
    @EnvironmentObject var appState: AppState

    private var modelIDs: [String] { appState.modelThinkingPreferences.values.keys.sorted() }

    var body: some View {
        SettingsSubheader("Model thinking")
        if modelIDs.isEmpty {
            SearchableRow(searchText: ["Model thinking", "reasoning effort"]) {
                Text("Choose thinking effort in the model menu to save a preference for that model.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        ForEach(modelIDs, id: \.self) { id in
            SettingsRow(
                title: modelName(id),
                explainer: "The model menu remembers this choice for future conversations. Saved agents can apply their own thinking settings. Reset removes this model's saved preference.",
                summary: "Default thinking effort for this model."
            ) {
                HStack(spacing: 8) {
                    Picker("Thinking effort", selection: preference(id)) {
                        Text("Off").tag(Optional<ReasoningEffort>.none)
                        ForEach(ReasoningEffort.allCases) { effort in
                            Text(L10n.text(effort.label)).tag(Optional(effort))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    Button("Reset") { appState.modelThinkingPreferences.values.removeValue(forKey: id) }
                }
            }
        }
    }

    private func modelName(_ id: String) -> String {
        if let model = appState.localModels.first(where: { $0.path == id }) { return model.displayLabel }
        let name = id.hasPrefix("lan:") ? String(id.dropFirst(4)) : (id as NSString).lastPathComponent
        return ModelDisplayName.pretty(name)
    }

    private func preference(_ id: String) -> Binding<ReasoningEffort?> {
        Binding(
            get: {
                guard let value = appState.modelThinkingPreferences.values[id], value.enabled else { return nil }
                return value.effort
            },
            set: { effort in
                let previous = appState.modelThinkingPreferences.values[id]?.effort ?? .low
                appState.modelThinkingPreferences.values[id] = ModelThinkingPreference(
                    enabled: effort != nil, effort: effort ?? previous)
            })
    }
}

// MARK: - Appearance

/// Display preferences apply without restarting the server.
private struct AppearanceSectionContent: View {
    @AppStorage(InterfacePrefKey.appearanceMode) private var appearanceModeRaw = AppAppearanceMode.system.rawValue
    @AppStorage(InterfacePrefKey.accentColor) private var accentColorRaw = AppAccentColor.system.rawValue
    @AppStorage(InterfacePrefKey.textSize) private var textSizeRaw = ChatTextSize.medium.rawValue
    @AppStorage(InterfacePrefKey.terminalTheme) private var terminalThemeId = TerminalTheme.defaultId
    @AppStorage(InterfacePrefKey.terminalBackground) private var terminalBackgroundHex = ""

    var body: some View {
        SettingsRow(title: "Color Mode", explainer: "Follow the system setting, or force light/dark for this app only.") {
            Picker("", selection: $appearanceModeRaw) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Text(L10n.text(mode.label)).tag(mode.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize(horizontal: true, vertical: false).font(.app(.body))
        }
        SettingsRow(title: "Accent Color", explainer: "Tint for buttons, links and the selected message bubble.") {
            Picker("", selection: $accentColorRaw) {
                ForEach(AppAccentColor.allCases) { accent in
                    Text(L10n.text(accent.label)).font(.app(.body)).tag(accent.rawValue)
                }
            }
            .labelsHidden()
            .frame(width: 140, alignment: .trailing).font(.app(.body))
        }
        SettingsRow(title: "Text Size", explainer: "Size of the chat transcript's prose and code.") {
            Picker("", selection: $textSizeRaw) {
                ForEach(ChatTextSize.allCases) { size in
                    Text(L10n.text(size.label)).font(.app(.body)).tag(size.rawValue)
                }
            }
            .labelsHidden()
            .frame(width: 140, alignment: .trailing).font(.app(.body))
        }
        SettingsRow(title: "Terminal Theme",
                    explainer: "Colors for new sandbox terminals. Right-click a terminal in the sidebar to give one session a different theme.") {
            Picker("", selection: $terminalThemeId) {
                ForEach(TerminalTheme.all) { theme in
                    Text(theme.name).font(.app(.body)).tag(theme.id)
                }
            }
            .labelsHidden()
            .frame(width: 160, alignment: .trailing).font(.app(.body))
        }
        SettingsRow(title: "Terminal Background",
                    explainer: "Ground under the default theme. Reset to use the theme's own.") {
            HStack(spacing: 8) {
                ColorPicker("", selection: terminalBackground, supportsOpacity: false)
                    .labelsHidden()
                if !terminalBackgroundHex.isEmpty {
                    Button { terminalBackgroundHex = "" } label: { Text("Reset")
                        .font(.app(.body)) }
                        .controlSize(.small)
                }
            }
        }
    }
}

extension AppearanceSectionContent {
    /// The color well ↔ the stored "#RRGGBB" (empty = the theme's ground).
    fileprivate var terminalBackground: Binding<Color> {
        Binding(
            get: {
                let rgb = TerminalTheme.RGB(hex: terminalBackgroundHex)
                    ?? (TerminalTheme.theme(terminalThemeId) ?? TerminalTheme.theme(TerminalTheme.defaultId)!).background
                return Color(.sRGB, red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
            },
            set: { color in
                guard let c = NSColor(color).usingColorSpace(.sRGB) else { return }
                terminalBackgroundHex = TerminalTheme.RGB(UInt8((c.redComponent * 255).rounded()),
                                                          UInt8((c.greenComponent * 255).rounded()),
                                                          UInt8((c.blueComponent * 255).rounded())).hex
            })
    }
}

// MARK: - Voice (wake phrase) section

private struct WakePhraseSectionContent: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        SettingsRow(
            title: "Wake phrase",
            explainer: "What you say to address the assistant in hands-free voice mode. Required when Require Wake Phrase is on. Matching ignores case and punctuation and accepts common greetings before the name. The assistant uses the phrase's last word as its name.",
            summary: "Required when Require Wake Phrase is on."
        ) {
            TextField("Choose a wake phrase", text: $appState.serverOptions.wakePhrase)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
        }
    }
}

// MARK: - Voice (clone clip) section

/// The global voice-clone clip: pick an audio file or record a few seconds,
/// normalized via `AudioReference` (24 kHz mono WAV — what Qwen3-TTS
/// `ref_audio` expects) and copied to `~/.mlx-serve/voice-clips/` so it
/// survives relaunch. An app-side setting like the sandbox — binds straight
/// through `appState.serverOptions.voiceClonePath`, no restart banner, no CLI
/// flag. Voice mode's `ClonedVoiceSynthesizer` re-reads the path per sentence.
private struct VoiceCloneSectionContent: View {
    @EnvironmentObject var appState: AppState
    /// The recorder is the store's, so a filter edit cannot stop a capture
    /// mid-recording; the store builds it on the first record.
    @EnvironmentObject var formState: SettingsFormState
    @State private var voiceError: String?
    /// Built lazily against the app's server so previews reuse the resident
    /// Kokoro model instead of loading it per click.
    @StateObject private var previewer = VoicePreviewer()
    @EnvironmentObject private var downloads: DownloadManager

    private static let explainer = "A few seconds of clean speech works best. Answers are synthesized locally by the Audio pane's TTS model (downloaded on first use)."
    /// Per-engine blurb. The old single string described Kokoro AND cloning and
    /// was shown under every tab, so picking "System voice" read as advice about
    /// a model you had not chosen.
    private static func engineExplainer(_ e: VoiceEngine) -> String {
        switch e {
        case .system:
            return "The built-in macOS voice. No download and no GPU, but the least natural of the three."
        case .clone:
            return "Copies the voice from the clip below using Qwen3-TTS. Slower and much heavier than Kokoro, and it needs the model downloaded from the Audio tile."
        case .kokoro:
            return "A small, very fast model (about 17x realtime, a tenth of the memory of the cloning model) with 54 built-in voices you can blend. It can't copy your voice."
        }
    }

    var body: some View {
        SearchableRow(searchText: ["Voice engine", "Kokoro", "System voice", "cloned"]) {
            engineBody
        }
        // The clip control only makes sense for the backend that can USE it —
        // Kokoro has no cloning and asking it to clone is a named 400, so the
        // control is hidden rather than left dead (the image-preset rule).
        if appState.serverOptions.voiceEngine == .clone {
            SearchableRow(searchText: ["Voice clone clip", Self.explainer, "Record", "Choose file"]) {
                clipBody
            }
        }
        if appState.serverOptions.voiceEngine == .kokoro {
            SearchableRow(searchText: ["Kokoro voice", "blend", "preview"]
                          + AudioModelPreset.kokoroVoices) {
                kokoroBody
            }
        }
        if appState.serverOptions.voiceEngine == .system {
            SearchableRow(searchText: ["System voice", "Apple voice"]) {
                systemVoiceBody
            }
        }
    }

    /// The app-wide Apple voice; an agent with its own voice still overrides it.
    @ViewBuilder
    private var systemVoiceBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text("System voice")).font(.app(.headline).weight(.semibold))
            HStack(spacing: 8) {
                Picker("", selection: Binding(get: { appState.voice.selectedVoiceId },
                                              set: { appState.voice.selectVoice($0) })) {
                    ForEach(appState.voice.availableVoices) { v in
                        Text(v.displayName).font(.app(.body)).tag(Optional(v.id))
                    }
                }
                .labelsHidden()
                .frame(width: 260, alignment: .leading)
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var engineBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text("Voice engine")).font(.app(.rowTitle).weight(.semibold))
            Picker("", selection: $appState.serverOptions.voiceEngine) {
                ForEach(VoiceEngine.allCases, id: \.self) { e in
                    Text(L10n.text(e.label)).tag(e)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            Text(L10n.text(Self.engineExplainer(appState.serverOptions.voiceEngine)))
                .font(.app(.caption2)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Stop a preview when the engine changes — otherwise a Kokoro sample
        // keeps talking after switching to the system voice.
        .onChange(of: appState.serverOptions.voiceEngine) { _, _ in previewer.stop() }
        .onAppear { previewer.attach(server: appState.server) }
    }

    private var kokoroBundle: MediaBundle { AudioModelPreset.kokoro82M.bundle }
    private var kokoroReady: Bool { downloads.bundleReady(kokoroBundle) }

    @ViewBuilder
    private var kokoroBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text("Kokoro voice")).font(.app(.headline).weight(.semibold))
            // Selecting the engine has to be able to GET the model — the gen
            // panes have had this bar all along; Settings ▸ Voice was the one
            // place that offered a backend with no way to fetch it. Collapses to
            // nothing once the bundle is complete.
            BundleDownloadBar(bundle: kokoroBundle)
            // A bare `.frame(maxWidth:)` centres the popup inside the flexible
            // width; the row needs an explicit leading alignment plus a Spacer
            // to sit against the left edge like every other control here.
            HStack(spacing: 8) {
                Picker("", selection: $appState.serverOptions.kokoroVoice) {
                    // Grouped by language so 54 entries are navigable, and named
                    // rather than shown as raw wire ids.
                    ForEach(KokoroVoiceCatalog.grouped(), id: \.language) { group in
                        Section(L10n.text(group.language)) {
                            ForEach(group.voices, id: \.self) { v in
                                Text(KokoroVoiceCatalog.displayName(for: v)).font(.app(.body)).tag(v)
                            }
                        }
                    }
                }
                .labelsHidden()
                .frame(width: 260, alignment: .leading)

                Button {
                    previewer.preview(appState.serverOptions.kokoroVoice)
                } label: {
                    if previewer.isPreviewing(appState.serverOptions.kokoroVoice) {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Play", systemImage: "play.circle").font(.app(.body))
                    }
                }
                .help(kokoroReady ? "Hear a short sample of this voice"
                                  : "Download the model first")
                .disabled(previewer.active != nil || !kokoroReady)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(L10n.text("Voices blend: type several separated by commas (af_bella,af_sky) to make a new one."))
                .font(.app(.caption2)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let e = previewer.error {
                Text(L10n.text(e)).font(.app(.caption)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Auditioning on SELECTION is the whole point — the user asked to hear
        // the voice they just picked, not to hunt for a play button.
        // Audition on SELECTION — but only once the weights are here, or every
        // pick would fire a request that can only fail.
        .onChange(of: appState.serverOptions.kokoroVoice) { _, newValue in
            if kokoroReady { previewer.preview(newValue) }
        }
        .onDisappear { previewer.stop() }
    }

    @ViewBuilder
    private var clipBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text("Voice clone clip")).font(.app(.headline).weight(.semibold))
            HStack(spacing: 8) {
                if !appState.serverOptions.voiceClonePath.isEmpty {
                    Image(systemName: "waveform").foregroundStyle(.secondary)
                    // Prefer the display label — the stored file is always the
                    // normalized "voice-clone.wav", which says nothing.
                    // "Recorded clip" is copy, not a file name: the row resolves
                    // it, so the stored label stays language-neutral.
                    let label = appState.serverOptions.voiceCloneLabel.isEmpty
                        ? (appState.serverOptions.voiceClonePath as NSString).lastPathComponent
                        : appState.serverOptions.voiceCloneLabel
                    Text(L10n.text(label))
                        .font(.app(.caption)).lineLimit(1).truncationMode(.middle)
                    Button { clearVoice() } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                        .help("Remove the clip — voice mode falls back to the system voice")
                } else {
                    Text(L10n.text("None — voice mode uses the system voice."))
                        .font(.app(.caption)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                Button { chooseVoiceFile() } label: { Label("Choose file…", systemImage: "folder") }
                if let recorder = formState.recorder {
                    VoiceRecordControl(recorder: recorder, onRecord: startRecording, onStop: stopRecording)
                } else {
                    Button { startRecording() } label: { Label("Record", systemImage: "mic") }
                }
            }
            .font(.app(.caption))
            Text(L10n.text(Self.explainer))
                .font(.app(.caption2)).foregroundStyle(.secondary)
            if let voiceError {
                Text(L10n.text(voiceError)).font(.app(.caption)).foregroundStyle(.red)
            }
        }
    }

    private func chooseVoiceFile() {
        voiceError = nil
        do {
            guard let picked = try VoiceCloneMenuModel.pickAndPersistClip() else { return }
            appState.serverOptions.voiceClonePath = picked.path
            appState.serverOptions.voiceCloneLabel = picked.label
            appState.serverOptions.voiceCloneEnabled = true
        } catch {
            voiceError = error.localizedDescription
        }
    }

    private func startRecording() {
        voiceError = nil
        Task {
            guard await AudioRecorder.requestPermission() else {
                voiceError = L10n.text("Microphone access denied. Enable it in System Settings ▸ Privacy ▸ Microphone.")
                return
            }
            do { try formState.audioRecorder().start() }
            catch { voiceError = error.localizedDescription }
        }
    }

    private func stopRecording() {
        guard let data = formState.recorder?.stop() else { voiceError = L10n.text("Nothing was recorded."); return }
        do {
            let normalized = try AudioReference.normalizedReferenceWav(fromRecordedPCM: data)
            appState.serverOptions.voiceClonePath = VoiceCloneClipStore.persist(normalized)
            appState.serverOptions.voiceCloneLabel = "Recorded clip"
            appState.serverOptions.voiceCloneEnabled = true
        } catch {
            voiceError = error.localizedDescription
        }
    }

    private func clearVoice() {
        appState.serverOptions.voiceClonePath = ""
        appState.serverOptions.voiceCloneLabel = ""
    }
}

/// Record / stop for the clip row. The store owns the recorder, so this is
/// what still observes it — the elapsed label has to tick while recording.
private struct VoiceRecordControl: View {
    @ObservedObject var recorder: AudioRecorder
    let onRecord: () -> Void
    let onStop: () -> Void

    var body: some View {
        if recorder.isRecording {
            Button(role: .destructive, action: onStop) {
                Label(L10n.format("Stop (%.1fs)", recorder.duration), systemImage: "stop.circle")
            }
        } else {
            Button(action: onRecord) { Label("Record", systemImage: "mic").font(.app(.callout)) }
        }
    }
}

// MARK: - Agent sandbox section

private struct ChatToolsSectionContent: View {
    @EnvironmentObject var appState: AppState
    @State private var showMCPSettings = false

    var body: some View {
        SettingsRow(
            title: "Tools",
            explainer: "Allow built-in tools in conversations that follow Settings defaults. Conversations can override access. Saved agents also apply their own capability choices. Tool approval rules still apply.",
            summary: "Default access to the built-in tools selected below.",
            leadingControl: true
        ) {
            Toggle("Tools", isOn: $appState.chatToolDefaults.toolsEnabled).labelsHidden().toggleStyle(.switch)
        }
        ForEach(AgentToolGroup.allCases.filter { $0 != .knowledge }, id: \.self) { group in
            ChatToolGroupSettings(group: group)
        }
        SettingsSubheader("Memory & Tasks")
        ForEach(AgentToolGroup.knowledge.tools, id: \.self) { tool in
            ChatToolSettingsSwitch(tool: tool)
        }
        SettingsRow(
            title: "MCP",
            explainer: "Make enabled Model Context Protocol (MCP) servers available to conversations that follow Settings defaults. Saved agents also apply their own MCP choice. Scheduled tasks use their own settings. Access does not change approval rules or server permissions.",
            summary: "Default access to your enabled MCP servers.",
            leadingControl: true
        ) {
            Toggle("MCP", isOn: $appState.chatToolDefaults.mcpEnabled).labelsHidden().toggleStyle(.switch)
        }
        SearchableRow(searchText: ["MCP servers", "Configure", "connected services"]) {
            Button("Configure MCP Servers…") { showMCPSettings = true }
                .frame(maxWidth: .infinity, alignment: .leading)
                .sheet(isPresented: $showMCPSettings) {
                    MCPMarketplaceView().environmentObject(appState.mcpManager)
                }
        }
    }
}

private struct ChatToolGroupSettings: View {
    let group: AgentToolGroup
    @Environment(\.settingsSearchQuery) private var query
    @State private var expanded = false

    var body: some View {
        SearchableRow(searchText: [group.title] + group.tools.map(\.displayName)) {
            DisclosureGroup(isExpanded: Binding(
                get: { expanded || !SettingsSearch.tokens(query).isEmpty },
                set: { expanded = $0 })) {
                ForEach(group.tools, id: \.self) { tool in
                    ChatToolSettingsSwitch(tool: tool)
                }
            } label: {
                Text(L10n.text(group.title))
            }
        }
    }
}

private struct ChatToolSettingsSwitch: View {
    let tool: AgentToolKind
    @EnvironmentObject var appState: AppState

    var body: some View {
        SearchableRow(searchText: [tool.displayName]) {
            HStack(spacing: 12) {
                Toggle(tool.displayName, isOn: Binding(
                    get: { !appState.chatToolDefaults.disabledTools.contains(tool.rawValue) },
                    set: { enabled in
                        var disabled = Set(appState.chatToolDefaults.disabledTools)
                        if enabled { disabled.remove(tool.rawValue) } else { disabled.insert(tool.rawValue) }
                        appState.chatToolDefaults.disabledTools = disabled.sorted()
                    }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel(L10n.text(tool.displayName))
                Label(L10n.text(tool.displayName), systemImage: tool.icon)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
        }
    }
}

/// Toggle + base-image field for the agent execution sandbox. This is an
/// app-side agent-behavior setting (the tool executor reads it), NOT a
/// server-launch flag — so it binds straight through
/// `appState.serverOptions.sandbox` with no restart banner and no CLI flag.
private struct SandboxSectionContent: View {
    @EnvironmentObject var appState: AppState
    @State private var showResetConfirm = false
    @State private var resetting = false
    /// Mirrors the stored default so the row re-renders on change; writes go
    /// through `AppState.setDefaultAgentWorkspace` (retarget + VM remount),
    /// never directly through this binding.
    @AppStorage(ChatSession.defaultWorkspaceDefaultsKey) private var storedWorkspace = ""

    private var currentWorkspace: String {
        storedWorkspace.isEmpty ? ChatSession.builtinDefaultWorkingDirectory : storedWorkspace
    }

    var body: some View {
        SettingsRow(
            title: "Agent workspace folder",
            explainer: "The default working folder for the agent's tools (shell, readFile, writeFile, …) in every chat — and the folder shared into the sandbox VM at /workspace while the sandbox is on. Changing it moves chats still on the previous default, remounts a running sandbox, and restarts any open terminal sessions in the new folder; a chat with its own picked folder (the folder icon on the Agent pill) keeps it.",
            summary: "Default folder for agent tools, shared with the sandbox. Changing it restarts open terminal sessions; custom chat folders are kept."
        ) {
            HStack(spacing: 8) {
                Text((currentWorkspace as NSString).abbreviatingWithTildeInPath)
                    .font(.app(.caption).monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(currentWorkspace)
                Button {
                    if let picked = WorkspacePicker.pickDirectory() {
                        appState.setDefaultAgentWorkspace(picked)
                    }
                } label: { Text("Choose…")
                    .font(.app(.body)) }
            }
        }

        // No host shell in the App Store build → the sandbox can't be turned
        // off (`AgentSandbox.resolveEnabled`), so offering the toggle would be
        // a lie; the base image is likewise locked to the bundled guest.
        if BuildFeatures.current.hostShell {
            SettingsRow(
                title: "Sandbox agent commands",
                explainer: "Runs shell commands in a Linux virtual machine. Shared workspace folders are real Mac folders, so commands can change their files. File tools run on the Mac with workspace checks. Network access is controlled separately. The virtual machine uses additional memory. When off, shell commands run directly on macOS.",
                summary: "Run shell commands in Linux. Changes to shared workspace files affect your Mac."
            ) {
                Toggle("", isOn: $appState.serverOptions.sandbox.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch).font(.app(.body))
            }
        }

        SettingsRow(
            title: "Network + port mapping",
            explainer: "ON = the sandbox has outbound internet (NAT), and any server the agent starts inside it is automatically reachable on this Mac at localhost with the same port — e.g. a dev server on 8080 appears at localhost:8080 (bound to localhost only, never your LAN). OFF = the sandbox gets no network device at all: fully isolated, but installs and downloads inside it will fail. Applies to the next sandbox session.",
            summary: "Allow internet access and forward sandbox ports to this Mac only. When off, network installs fail. Applies to the next sandbox session."
        ) {
            Toggle("", isOn: $appState.serverOptions.sandbox.network)
                .labelsHidden()
                .toggleStyle(.switch).font(.app(.body))
        }

        SettingsRow(
            title: "Reset sandbox",
            explainer: "Deletes ALL sandbox data and returns it to factory state: the downloaded guest image and everything inside it (installed CLIs like pi/hermes, their configs and logins, any files created outside the shared workspace), the cached kernel, the sandbox ssh identity, and the activity transcript. Any running guest and live agent sessions are stopped immediately. Your workspace folder, models, and other app data on this Mac are not touched. The sandbox re-provisions itself on next use.",
            summary: "Permanently delete sandbox apps, logins, and data, and stop active sessions. Your Mac workspace and models are kept."
        ) {
            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                if resetting {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Resetting…").font(.app(.body))
                    }
                } else {
                    Label("Reset Sandbox…", systemImage: "trash").font(.app(.body))
                        .foregroundStyle(.red)
                }
            }
            .disabled(resetting)
            .confirmationDialog(
                "Reset the Agent Sandbox?",
                isPresented: $showResetConfirm,
                titleVisibility: .visible
            ) {
                Button(role: .destructive) {
                    resetting = true
                    AgentSandbox.shared.resetAllData {
                        resetting = false
                    }
                } label: { Text("Delete All Sandbox Data")
                    .font(.app(.body)) }
                Button(role: .cancel) {} label: { Text("Cancel")
                    .font(.app(.body)) }
                .keyboardShortcut(.defaultAction)
            } message: {
                Text("""
                This permanently deletes everything the sandbox has downloaded and every change made inside it — installed agent CLIs (pi, hermes), their configs and logins, and any files outside the shared workspace. Any running guest and live sessions stop immediately.

                Files in your workspace folder on this Mac are kept. This cannot be undone.
                """)
            }
        }
    }
}

// MARK: - About

private struct AboutSectionContent: View {
    @EnvironmentObject var formState: SettingsFormState

    private var engineRows: [EngineVersion] {
        let rows = formState.engineVersions.filter { $0.name != "mlx-serve" }
        return rows.isEmpty
            ? [EngineVersion(name: "llama.cpp", version: UpdateChecker.bundledLlamaTag)]
            : rows
    }

    var body: some View {
        SettingsRow(title: "Version", explainer: "Installed app version.") {
            Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")
                .textSelection(.enabled)
        }
        SettingsSubheader("Bundled Engines")
        ForEach(engineRows) { row in
            SettingsRow(title: EngineVersions.displayLabel(row.name),
                        explainer: EngineVersions.explainer(row.name)) {
                Text(row.version).textSelection(.enabled)
            }
        }
        .task {
            guard formState.engineVersions.isEmpty else { return }
            formState.engineVersions = await EngineVersions.probe(binaryPath: ServerManager.resolveBinaryPath())
        }
        SettingsSubheader("Dependencies")
        SettingsRow(
            title: "SwiftTerm · MCP SDK · Swift Collections · SwaTex",
            explainer: "Terminal sessions, MCP connections, collection utilities, and formula rendering."
        ) {
            Button("Open Notices") {
                if let notice = Bundle.main.url(forResource: "NOTICE", withExtension: nil) {
                    NSWorkspace.shared.open(notice)
                }
            }
            .disabled(Bundle.main.url(forResource: "NOTICE", withExtension: nil) == nil)
            .help("Open the bundled third-party license notices")
        }
    }
}

// MARK: - Shared numeric control

/// A slider that snaps to a discrete preset list — the float value is the index
/// into `presets`, rounding pins to the nearest entry. Shared: a setting whose
/// useful values are a ladder (memory caps, token budgets) reads better as this
/// than as a free-text field, and a value picked off a ladder cannot be a typo
/// the launcher has to defend against.
@ViewBuilder
private func snappingSlider(
    presets: [Int],
    current: Int,
    set: @escaping (Int) -> Void,
    label: String
) -> some View {
    let safePresets = presets.isEmpty ? [0] : presets
    let currentIdx = closestPresetIndex(in: safePresets, to: current)
    HStack(spacing: 8) {
        Slider(
            value: Binding(
                get: { Double(currentIdx) },
                set: { raw in
                    let i = Int(raw.rounded())
                    let clamped = max(0, min(i, safePresets.count - 1))
                    set(safePresets[clamped])
                }
            ),
            in: 0...Double(max(1, safePresets.count - 1)),
            step: 1
        )
        .frame(width: 200)
        Text(L10n.text(label))
            .font(.app(.body).monospacedDigit())
            .frame(minWidth: 70, alignment: .trailing)
    }
}

/// Index of the preset closest to `value`, so a stored value not on the snap
/// grid still positions the slider sensibly.
private func closestPresetIndex(in presets: [Int], to value: Int) -> Int {
    if let exact = presets.firstIndex(of: value) { return exact }
    var best = 0
    for i in 1..<presets.count where abs(presets[i] - value) < abs(presets[best] - value) {
        best = i
    }
    return best
}
