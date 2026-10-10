import SwiftUI

/// Model selection and reasoning settings for the next message.
struct ChatModelPill: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var server: ServerManager
    @Environment(\.openWindow) private var openWindow

    /// False when embedded in the toolbar's floating cluster, which draws ONE
    /// capsule around the model picker, voice and settings together — a second
    /// capsule inside it reads as a button inside a button.
    var showsBackground: Bool = true
    /// Composer placement: sized and weighted like the rest of that row (which
    /// is where the picker lives now — it configures the message you are about
    /// to send, not the window), and it carries the download affordances a
    /// toolbar pill had no room for.
    var compact: Bool = false
    var reasoningLabel: String? = nil
    var reasoningLocked: Bool = false
    var thinkingHint: String? = nil
    var thinkingHeader: AnyView? = nil
    var thinkingControls: AnyView? = nil
    var contextControl: AnyView? = nil
    var startControl: ChatServerStartControl = .hidden
    var onStart: (() -> Void)? = nil

    @State private var isPresented = false
    @State private var showingModels = false
    @FocusState private var focusedModel: String?
    @FocusState private var focusedNavigation: NavigationFocus?
    @State private var typedPrefix = ""
    @State private var lastTyped = Date.distantPast

    private enum NavigationFocus: Hashable { case model, back, manage }

    @EnvironmentObject private var downloads: DownloadManager

    /// Hard cap on the name's width. The pill's size is what keeps it safe in
    /// the toolbar, so this is a contract, not a nicety.
    private static let maxNameWidth: CGFloat = 210
    /// Tighter cap in the composer row, which has its own budget — see the
    /// toolbar-eviction note above; the same discipline applies here.
    private static let compactNameWidth: CGFloat = 150

    /// What the PILL shows: the model name without its org.
    static func headerName(_ full: String) -> String {
        guard let slash = full.lastIndex(of: "/") else { return full }
        let tail = full[full.index(after: slash)...]
        return tail.isEmpty ? full : String(tail)
    }

    private var pickableModels: [LocalModel] { appState.localModels.filter(\.isChatPickable) }
    private var isMedia: Bool { appState.interactionMedia != nil }
    private var hasThinkingControls: Bool { !isMedia && thinkingControls != nil }

    /// The name and the in-flight state, decided in ONE pure place shared with
    /// the tray's rules (`ChatModelSelection.pillState`) — a per-surface copy is
    /// how one picker starts naming a model the other doesn't.
    private var pill: ChatModelPillState {
        if let name = appState.interactionModelName {
            return ChatModelPillState(name: name, isLoading: false)
        }
        return ChatModelSelection.pillState(lanChatModelId: server.lanChatModelId,
                                     apple: appState.useAppleModel,
                                     residentName: server.chatModelInfo?.name,
                                     loadingPath: appState.loadingModelPath,
                                     selectedPath: appState.selectedModelPath,
                                     models: pickableModels)
    }

    /// Green once the server is up AND a chat model is actually resident —
    /// "running with nothing loaded" is not ready to answer, and a green dot
    /// there is a lie the first message exposes.
    private var statusColor: Color {
        // The on-device model answers with the server down — the dot reports
        // whether the chat can answer, not whether a process is up.
        if appState.useAppleModel { return .green }
        guard server.status == .running else { return .secondary.opacity(0.5) }
        if server.lanChatModelId != nil { return .green }
        return server.chatModelInfo == nil ? .orange : .green
    }

    private var selection: String {
        appState.interactionModelTag
    }

    private var modelRows: [ModelPaletteRow] {
        appState.interactionModelRows
    }

    /// A live transfer THIS CHAT is waiting on, if any. The pill is where the
    /// user is already looking when they wonder why nothing answers, so a
    /// download in flight belongs here rather than only in the browser two
    /// clicks away — but it has to be the download that explains the silence.
    /// Excluding media bundles was half of that (a 30 GB video pack grew a
    /// hairline under the chat model's name); the other half is that a CHAT
    /// model fetched in the background drew a bar under a different model that
    /// was already answering perfectly well. It is keyed to the pill's own
    /// model now, the way every other download surface keys its row.
    ///
    /// `hasChatModelOnDisk` is the exception, and the reason the hairline
    /// exists: with nothing pickable on this Mac the composer cannot answer at
    /// all, so whatever chat model is arriving IS what it is waiting for.
    static func chatDownload(in downloads: [String: DownloadManager.DownloadState],
                             mediaRepos: Set<String>,
                             selectedModelPath: String,
                             hasChatModelOnDisk: Bool) -> DownloadManager.DownloadState? {
        downloads
            .filter { repoId, state in
                guard state.status == .downloading, !mediaRepos.contains(repoId) else { return false }
                return hasChatModelOnDisk ? isTransfer(of: repoId, for: selectedModelPath) : true
            }
            .min { $0.key < $1.key }?  // stable pick when two are running
            .value
    }

    /// Whether `repoId` is the model at `path`. A download has no `LocalModel`
    /// until its files land, so the join is the layout the downloader writes:
    /// `<root>/<org>/<name>`, i.e. the path's last two components ARE the repo
    /// id. A GGUF selection points at the file inside that folder, so its repo
    /// is one level further up.
    static func isTransfer(of repoId: String, for path: String) -> Bool {
        guard !repoId.isEmpty, !path.isEmpty else { return false }
        var dir = path as NSString
        while dir.hasSuffix("/") { dir = dir.deletingLastPathComponent as NSString }
        if dir.pathExtension.lowercased() == "gguf" { dir = dir.deletingLastPathComponent as NSString }
        let org = (dir.deletingLastPathComponent as NSString).lastPathComponent
        let name = dir.lastPathComponent
        return repoId == "\(org)/\(name)" || repoId == name
    }

    private var activeDownload: DownloadManager.DownloadState? {
        guard !isMedia, server.lanChatModelId == nil else { return nil }
        return Self.chatDownload(in: downloads.downloads,
                                 mediaRepos: downloads.mediaBundleRepos,
                                 selectedModelPath: appState.selectedModelPath,
                                 hasChatModelOnDisk: !pickableModels.isEmpty)
    }

    private var needsDownload: Bool {
        modelRows.isEmpty && activeDownload == nil
    }

    @ViewBuilder
    var body: some View {
        if compact {
            HStack(spacing: 0) {
                if !isMedia, let contextControl {
                    contextControl
                    Divider().frame(height: 16)
                }
                modelButton
                if !isMedia, startControl != .hidden, let onStart {
                    Divider().frame(height: 16)
                    Button(action: onStart) {
                        HStack(spacing: 5) {
                            if startControl == .starting {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "play.fill")
                                    .font(.app(.caption2, weight: .semibold))
                            }
                            Text(L10n.text(startControl.title))
                                .font(.app(.callout, weight: .medium))
                        }
                        .padding(.horizontal, ComposerControlMetrics.horizontalPadding)
                        .frame(minHeight: ComposerControlMetrics.height)
                        .contentShape(Rectangle())
                    }
                    .disabled(!startControl.isEnabled)
                    .accessibilityLabel(L10n.text(startControl.title))
                    .help(startControl == .starting
                          ? "Loading the model — this can take a while for a large one."
                          : "The server isn't running, so nothing can answer. Click to start it.")
                }
            }
            .buttonStyle(.borderless)
            .composerCapsule()
            .accessibilityElement(children: .contain)
        } else {
            modelButton
                .buttonStyle(.plain)
        }
    }

    private var modelButton: some View {
        let pill = self.pill
        return Button {
            showingModels = !hasThinkingControls || selection.isEmpty
            typedPrefix = ""
            isPresented.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(ModelDisplayName.pretty(pill.name))
                        .font(.app(.body))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: compact ? Self.compactNameWidth : Self.maxNameWidth,
                               alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !isMedia, let reasoningLabel {
                        Text(L10n.text(reasoningLabel))
                            .font(.app(.body))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    if !isMedia, reasoningLocked {
                        Image(systemName: "lock.fill")
                            .font(.app(.caption2))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    if pill.isLoading {
                        // A switch in flight. The dot would say GREEN here —
                        // the server is running and a model is resident, just
                        // not this one — so the spinner replaces it rather than
                        // sitting beside it.
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.6)
                            .frame(width: 8, height: 8)
                    } else if needsDownload {
                        // Nothing on disk: the one thing to do is get one, so
                        // say it with the symbol rather than a dot that only
                        // reports.
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.app(.subheadline))
                            .foregroundStyle(Color.accentColor)
                    } else if !isMedia, startControl == .hidden {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                    }
                    Image(systemName: "chevron.down")
                        .font(.app(.caption2, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                if let active = activeDownload {
                    // Deliberately wordless: a hairline that fills. The figures
                    // live in the browser; here it only has to say "something is
                    // arriving, that's why it can't answer yet".
                    ProgressView(value: max(0, min(1, active.progress)))
                        .progressViewStyle(.linear)
                        .tint(.green)
                        .frame(height: 3)
                        .frame(maxWidth: compact ? Self.compactNameWidth : Self.maxNameWidth)
                }
            }
            .padding(.horizontal, compact ? ComposerControlMetrics.horizontalPadding : showsBackground ? 12 : 4)
            .padding(.vertical, compact ? 0 : 4)
            .frame(minHeight: compact ? ComposerControlMetrics.height : nil)
            .background(!compact && showsBackground ? Color.secondary.opacity(0.12) : Color.clear)
            .clipShape(Capsule())
            .contentShape(Rectangle())
        }
        .fixedSize()
        .accessibilityLabel(hasThinkingControls ? "Model and thinking" : "Model")
        .accessibilityValue([ModelDisplayName.pretty(pill.name), isMedia ? nil : reasoningLabel.map(L10n.text)]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(isMedia ? "" : thinkingHint ?? "")
        .help(pill.isLoading
              ? L10n.format("Loading %@…", ModelDisplayName.pretty(pill.name))
              : L10n.text(hasThinkingControls ? "Choose a model and configure thinking." : "Choose a model."))
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 12) {
                if showingModels {
                    modelPicker
                } else {
                    thinkingPage
                }
            }
            .padding(14)
            .frame(width: 320)
            .onExitCommand { isPresented = false }
        }
    }

    private var thinkingPage: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let thinkingHeader { thinkingHeader }
            Button { showingModels = true } label: {
                HStack(spacing: 5) {
                    Text(verbatim: ModelDisplayName.pretty(pill.name))
                        .font(.app(.body))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .focused($focusedNavigation, equals: .model)
            .accessibilityLabel("Select model")
            .accessibilityValue(ModelDisplayName.pretty(pill.name))
            .onKeyPress(.rightArrow) {
                showingModels = true
                return .handled
            }
            if let thinkingControls {
                thinkingControls
                    .padding(.top, 4)
            }
        }
        .onAppear {
            focusedModel = nil
            DispatchQueue.main.async {
                guard isPresented, !showingModels else { return }
                focusedNavigation = .model
            }
        }
    }

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if hasThinkingControls {
                    Button { showingModels = false } label: {
                        Label("Back", systemImage: "chevron.left")
                            .labelStyle(.iconOnly)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .focused($focusedNavigation, equals: .back)
                    .help("Back")
                }
                Text("Select model")
                    .font(.app(.callout))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            ScrollViewReader { proxy in
                ModelPickerScrollView {
                    VStack(alignment: .leading, spacing: 12) { menuContent }
                }
                .onKeyPress(.upArrow) { moveFocus(-1) }
                .onKeyPress(.downArrow) { moveFocus(1) }
                .onKeyPress(characters: .alphanumerics, phases: .down, action: typeAhead)
                .onChange(of: focusedModel) { _, tag in
                    if let tag { proxy.scrollTo(tag, anchor: .center) }
                }
                .onAppear {
                    typedPrefix = ""
                    let tag = navigationRows.first { $0.tag == selection }?.tag
                        ?? navigationRows.first?.tag
                    DispatchQueue.main.async {
                        guard isPresented, showingModels else { return }
                        if let tag {
                            focusedNavigation = nil
                            focusedModel = tag
                            proxy.scrollTo(tag, anchor: .center)
                        } else {
                            focusedModel = nil
                            focusedNavigation = hasThinkingControls ? .back : .manage
                        }
                    }
                }
            }
            Divider()
            Button {
                isPresented = false
                appState.showModels()
            } label: {
                Label("Manage Models…", systemImage: "square.stack.3d.up")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .focused($focusedNavigation, equals: .manage)
        }
        .onKeyPress(.leftArrow) {
            guard hasThinkingControls else { return .ignored }
            showingModels = false
            return .handled
        }
    }

    private var navigationRows: [(tag: String, title: String)] {
        modelRows.map { (tag: $0.tag, title: $0.title) }
    }

    private func moveFocus(_ delta: Int) -> KeyPress.Result {
        let rows = navigationRows
        let index = rows.firstIndex { $0.tag == focusedModel }
        if let next = ModelPalette.move(index, by: delta, count: rows.count) { focusedModel = rows[next].tag }
        typedPrefix = ""
        return .handled
    }

    private func typeAhead(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.intersection([.command, .control, .option]).isEmpty else { return .ignored }
        let now = Date()
        typedPrefix = now.timeIntervalSince(lastTyped) > 1 ? press.characters : typedPrefix + press.characters
        lastTyped = now
        let prefix = typedPrefix.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if let match = navigationRows.first(where: {
            $0.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).hasPrefix(prefix)
        }) { focusedModel = match.tag }
        return .handled
    }

    @ViewBuilder
    private var menuContent: some View {
        if modelRows.isEmpty {
            Text("No models available").font(.app(.body))
        } else {
            ForEach(modelSections, id: \.self) { section in
                VStack(alignment: .leading, spacing: 2) {
                    modelSectionTitle(section)
                    ForEach(modelRows.filter { $0.section == section }) { model in
                        row(model)
                    }
                }
            }
        }
    }

    private var modelSections: [String] {
        var seen = Set<String>()
        return modelRows.compactMap { seen.insert($0.section).inserted ? $0.section : nil }
    }

    private func modelSectionTitle(_ title: String) -> some View {
        Text(L10n.text(title))
            .font(.app(.caption))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    private func row(_ model: ModelPaletteRow) -> some View {
        Button { pick(model) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: model.title)
                        .font(.app(.body))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: model.detail)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .opacity(selection == model.tag ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(model.title)
        .focused($focusedModel, equals: model.tag)
        .id(model.tag)
        .onKeyPress(.return) {
            pick(model)
            return .handled
        }
        .accessibilityAddTraits(selection == model.tag ? .isSelected : [])
    }

    private func pick(_ model: ModelPaletteRow) {
        isPresented = false
        appState.selectInteractionModel(model, using: openWindow)
    }
}
