import SwiftUI

/// Model Browser: five sections (`ModelBrowserSection`), switched by the bar
/// across the top of the content area.
struct ModelBrowserPane: View {
    /// Which section is showing. The pane's own bar drives it: the sidebar is
    /// the conversation list (plus the Models row that gets you here), so the
    /// sub-items live across the top of the content area.
    @Binding var section: ModelBrowserSection

    @EnvironmentObject var searchService: HFSearchService
    @EnvironmentObject var downloads: DownloadManager
    @EnvironmentObject var appState: AppState

    @State private var localFilter = ""

    private var downloadSummary: ModelDownloadSummary {
        ModelDownloadSummary(states: Array(downloads.downloads.values))
    }

    private var downloadItems: [(repoId: String, state: DownloadManager.DownloadState)] {
        downloads.downloads
            .filter { $0.value.status != .idle }
            .sorted { $0.key < $1.key }
            .map { (repoId: $0.key, state: $0.value) }
    }

    /// Counts beside the section names, from the ONE shared builder so they
    /// cannot drift from what the panes list.
    private var badges: ModelBrowserBadgeCounts {
        func readyCount<P: MediaModelPreset>(_ presets: [P]) -> Int {
            presets.filter { downloads.bundleReady($0.bundle) }.count
        }
        let media = readyCount(ImageModelPreset.all)
            + readyCount(AudioModelPreset.allIncludingVoiceOnly)
            + readyCount(VideoModelPreset.all)
            + readyCount(MusicModelPreset.all)
            + readyCount(SoundModelPreset.all)
        return .live(localModelCount: appState.localModels.count,
                     activeDownloadCount: downloadSummary.pending,
                     mediaReadyCount: media)
    }

    var body: some View {
        VStack(spacing: 0) {
            ModelBrowserSectionBar(section: $section, badges: badges,
                                   isDownloading: downloadSummary.running > 0)
            // Empty states must fill the remainder so navigation stays at the top.
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // The floor the browser's table needs, asserted from INSIDE the chat
        // window's detail column: below it the action cell clips off the right
        // edge (`ModelBrowserMetrics`). On the pane rather than the window, so
        // it only applies while the browser is up — a chat transcript is happy
        // much narrower.
        .frame(minWidth: ModelBrowserMetrics.minDetailWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            if searchService.models.isEmpty {
                await searchService.search()
            }
        }
        // Once per visit, not per section: the rescan sizes every model folder
        // on the main thread, and in-app changes already refresh on their own.
        .onAppear { appState.refreshModels() }
        // Live-refresh on-disk sizes while a disk-state pane is showing and a
        // download is in flight, so completion + growing size show up without
        // the user navigating away and back. The task id flips when the section
        // changes or the active-download set changes, which cancels +
        // re-evaluates the guard — so it self-terminates once everything
        // finishes.
        .task(id: "\(section.rawValue)-\(downloadSummary.running)") {
            guard ModelBrowserSection.shouldLivePoll(section: section,
                                                     hasActiveDownloads: downloadSummary.running > 0) else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { break }
                appState.refreshModels()
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch section {
        case .recommended: RecommendedPane()
        case .discover:     DiscoverPane()
        case .myModels:     MyModelsPane(filter: $localFilter)
        case .downloads:    DownloadsPane(items: downloadItems) { section = .myModels }
        case .media:        MediaPane()
        }
    }
}

// MARK: - Section bar

/// The browser's five sections, across the top of the content area.
private struct ModelBrowserSectionBar: View {
    @Binding var section: ModelBrowserSection
    let badges: ModelBrowserBadgeCounts
    let isDownloading: Bool
    @Environment(\.layoutDirection) private var layoutDirection
    @FocusState private var focusedSection: ModelBrowserSection?

    var body: some View {
        GlassEffectContainer {
            ViewThatFits(in: .horizontal) {
                sectionTabs
                    .fixedSize(horizontal: true, vertical: false)
                sectionMenu
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var sectionTabs: some View {
        HStack(spacing: 2) {
            ForEach(ModelBrowserSection.allCases) { item in
                sectionButton(item)
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
        .onKeyPress(.leftArrow) { moveSelection(movingRight: false) }
        .onKeyPress(.rightArrow) { moveSelection(movingRight: true) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Models section")
    }

    private func sectionButton(_ item: ModelBrowserSection) -> some View {
        Button {
            section = item
            focusedSection = item
        } label: {
            HStack(spacing: 6) {
                Text(verbatim: title(for: item))
                    .font(.app(.body))
                if item == .downloads, isDownloading {
                    downloadActivity
                }
            }
            .foregroundStyle(section == item ? Color.accentColor : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(.capsule)
            .background {
                if section == item {
                    Capsule().fill(Color.accentColor.opacity(0.18))
                        .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1))
                }
            }
        }
        .buttonStyle(.borderless)
        .buttonBorderShape(.capsule)
        .focused($focusedSection, equals: item)
        .accessibilityAddTraits(section == item ? .isSelected : [])
    }

    private var sectionMenu: some View {
        Menu {
            Picker("Models section", selection: $section) {
                ForEach(ModelBrowserSection.allCases) { item in
                    Text(verbatim: title(for: item)).tag(item)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(verbatim: title(for: section))
                    .font(.app(.body))
                if isDownloading { downloadActivity }
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("Models section")
        .accessibilityValue(Text(verbatim: title(for: section)))
    }

    private var downloadActivity: some View {
        ProgressView()
            .controlSize(.mini)
            .accessibilityLabel("Models are downloading")
    }

    private func title(for item: ModelBrowserSection) -> String {
        let title = L10n.text(item.title)
        return badges.badge(for: item).map { "\(title) (\($0))" } ?? title
    }

    private func moveSelection(movingRight: Bool) -> KeyPress.Result {
        let destination = ModelBrowserSectionNavigation.destination(
            from: focusedSection ?? section, movingRight: movingRight,
            rightToLeft: layoutDirection == .rightToLeft)
        section = destination
        focusedSection = destination
        return .handled
    }
}

// MARK: - Recommended

/// Every curated Gemma 4 / Qwen 3.5-3.6 checkpoint, grouped by family and
/// explained in plain English. This is the friendly front door for someone
/// who has never picked a local model before — Discover's HuggingFace search
/// (with its 1M+ repos, quant/pull-count columns, and RAM-fitness dots)
/// assumes you already know roughly what you're looking for.
private struct RecommendedPane: View {
    private var memory: SystemMemoryInfo { SystemMemoryInfo.current() }
    private var starter: RecommendedModelPick {
        RecommendedModelPick.starterPick(physicalMemoryBytes: memory.totalBytes)
    }

    var body: some View {
        VStack(spacing: 0) {
            RecommendedSystemSummary(memory: memory, recommended: starter)
            Divider()
            RecommendedModelList(memory: memory, recommendedId: starter.id)
        }
        .navigationTitle("Recommended")
    }
}

private struct RecommendedSystemSummary: View {
    let memory: SystemMemoryInfo
    let recommended: RecommendedModelPick
    @State private var showsRatingInfo = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label(L10n.format("%@ memory · about %@ usable for models", memory.totalLabel, memory.usableLabel),
                      systemImage: "memorychip")
                    .font(.app(.body))
                Text(verbatim: L10n.format("Recommended for your Mac: %@", recommended.name))
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("About ratings", systemImage: "info.circle") {
                showsRatingInfo = true
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("About model ratings and memory estimates")
            .popover(isPresented: $showsRatingInfo) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("About these estimates").font(.app(.headline))
                    Text("Intelligence is the Artificial Analysis Intelligence Index, rescaled to 100 from a reference of 60. It describes the original weights; entries without a published score are marked as our estimate.")
                    Text("Speed is our relative Apple Silicon estimate on a 0–100 scale, informed by benchmarks. It is not tokens per second. Scores that include a built-in draft head say so.")
                    Text("Download size and memory needed are approximate. Maximum context is the model’s published limit; the usable context depends on your Mac and settings.")
                    Link("Artificial Analysis · index reference: July 30, 2026",
                         destination: URL(string: "https://artificialanalysis.ai/models/open-source")!)
                }
                .font(.app(.body))
                .padding(16)
                .frame(width: 350, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct RecommendedModelList: View {
    let memory: SystemMemoryInfo
    let recommendedId: String

    private struct Family: Identifiable {
        let id: String
        let title: String
        let picks: [RecommendedModelPick]
    }

    private var families: [Family] {
        [
            Family(id: "gemma", title: "Gemma 4",
                   picks: RecommendedModelPick.gemmaCatalog),
            Family(id: "qwen", title: "Qwen",
                   picks: RecommendedModelPick.qwenCatalog),
            Family(id: "largest", title: "Largest models",
                   picks: RecommendedModelPick.largestCatalog),
        ]
    }

    var body: some View {
        List {
            ForEach(families) { family in
                Section(L10n.text(family.title)) {
                    ForEach(family.picks) { pick in
                        RecommendedModelRow(
                            pick: pick,
                            memory: memory,
                            isRecommended: pick.id == recommendedId
                        )
                    }
                }
            }
        }
        .listStyle(.inset)
    }
}

private struct RecommendedModelRatings: View {
    let pick: RecommendedModelPick
    var inline = false

    private var description: String {
        CapabilityTip.lines(for: pick).map(L10n.text).joined(separator: "\n")
    }

    var body: some View {
        Group {
            if inline {
                HStack(spacing: 16) { ratings }
            } else {
                VStack(alignment: .leading, spacing: 3) { ratings }
            }
        }
        .font(.app(.caption))
        .foregroundStyle(.secondary)
        .help(description)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(description)
    }

    @ViewBuilder
    private var ratings: some View {
        Text(verbatim: L10n.format("Intelligence: %lld/100", Int64(pick.intelligence))
             + (pick.intelligenceIsEstimated ? " " + L10n.text("est.") : ""))
        Text(verbatim: L10n.format("Speed: %lld/100 est.", Int64(pick.speed)))
    }
}

private struct RecommendedModelRow: View {
    let pick: RecommendedModelPick
    let memory: SystemMemoryInfo
    let isRecommended: Bool

    @EnvironmentObject var downloads: DownloadManager
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var server: ServerManager
    @State private var confirmDelete = false
    @State private var card: ModelCardRequest?

    /// How this pick's memory requirement fits the Mac's usable budget.
    private var fit: MemoryFit { memory.fit(neededGB: pick.approxRAMNeededGB) }

    /// For a GGUF pick, the specific quant file on disk (the repo ships many);
    /// nil until the folder resolves. Drives ready/use so a *different* quant of
    /// the same repo doesn't read as this pick being downloaded.
    private var ggufFilePath: String? {
        guard let f = pick.ggufFilename, let dir = downloads.existingModelDir(for: pick.repoId) else { return nil }
        return (dir as NSString).appendingPathComponent(f)
    }
    private var isReady: Bool {
        if pick.ggufFilename != nil {
            guard let p = ggufFilePath else { return false }
            return FileManager.default.fileExists(atPath: p)
        }
        return downloads.isReady(pick.repoId)
    }
    private var state: DownloadManager.DownloadState? { downloads.downloads[pick.repoId] }

    /// The on-disk model this row's repo resolves to, once downloaded —
    /// mirrors `ModelBrowserRow.usableModel`.
    private var usableModel: LocalModel? {
        // A GGUF quant's LocalModel.path is the FILE, not the repo dir — resolve
        // against the specific quant so "Use" loads exactly this pick.
        let path = pick.ggufFilename != nil ? ggufFilePath : downloads.existingModelDir(for: pick.repoId)
        return ModelBrowserUse.pickableModel(atPath: path, in: appState.localModels)
    }

    /// The other half of the catalogue — see `ModelBrowserUse.mediaModel`.
    private var usableMedia: (model: LocalModel, modality: MediaModality)? {
        let path = pick.ggufFilename != nil ? ggufFilePath : downloads.existingModelDir(for: pick.repoId)
        return ModelBrowserUse.mediaModel(atPath: path, in: appState.localModels)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    modelIdentity
                    RecommendedModelRatings(pick: pick)
                        .fixedSize(horizontal: true, vertical: false)
                    actions
                }
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .top, spacing: 12) {
                        modelIdentity
                        actions
                    }
                    RecommendedModelRatings(pick: pick, inline: true)
                }
            }
            modelFacts
        }
        .padding(.vertical, 6)
        .sheet(item: $card) { ModelDetailSheet(request: $0) }
    }

    private var modelIdentity: some View {
        Button { card = ModelCardRequest(repoId: pick.repoId, title: pick.name) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: pick.name)
                    .font(.app(.body).weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if isRecommended {
                        Label("Recommended", systemImage: "checkmark")
                            .foregroundStyle(.tint)
                    }
                    Text(L10n.text(pick.tagline))
                        .foregroundStyle(.secondary)
                }
                .font(.app(.caption))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(L10n.text(pick.blurb))
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHint("Open model details")
    }

    private var actions: some View {
        actionControl
            .buttonStyle(.bordered)
            .frame(width: 120, alignment: .trailing)
    }

    private var modelFacts: some View {
        (Text(verbatim: L10n.format("Download: %@%@ · RAM: ~%@ · ",
                                   SystemMemoryInfo.preciseGB(pick.sizeGB),
                                   pick.quantLabel.map { " · \($0)" } ?? "",
                                   SystemMemoryInfo.preciseGB(pick.approxRAMNeededGB)))
            .foregroundColor(.secondary)
         + Text(L10n.text(fit.label)).foregroundColor(fitColor)
         + Text(verbatim: L10n.format(" · Max context: %@ tokens", pick.contextTokens.formatted()))
            .foregroundColor(.secondary))
        .font(.app(.caption))
        .fixedSize(horizontal: false, vertical: true)
        .help(L10n.format("Needs about %@ — your Mac can use about %@ for a model.",
                          SystemMemoryInfo.preciseGB(pick.approxRAMNeededGB), memory.usableLabel))
    }

    private var fitColor: Color {
        switch fit {
        case .comfortable: return .green
        case .tight:       return .orange
        case .exceeds:     return .red
        }
    }

    @ViewBuilder
    private var actionControl: some View {
        if isReady {
            HStack(spacing: 6) {
                if let usable = usableModel {
                    let use = ModelUseState.resolve(
                        selected: appState.selectedModelPath == usable.path,
                        serverStatus: server.status
                    )
                    if use == .idle {
                        UseModelButton(path: usable.path, name: usable.name)
                    } else {
                        ModelUseBadge(state: use)
                    }
                } else if let media = usableMedia {
                    UseMediaModelButton(modality: media.modality, name: media.model.name, path: media.model.path)
                } else {
                    Text("✓ On disk")
                        .font(.app(.caption).weight(.medium))
                        .foregroundStyle(.green)
                }
                Button {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red.opacity(0.7))
                        .frame(minWidth: 22, minHeight: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel("Delete model")
                .help("Delete model")
                .alert("Delete Model", isPresented: $confirmDelete) {
                    Button(role: .cancel) {} label: { Text("Cancel")
                        .font(.app(.body)) }
                    Button(role: .destructive) {
                        downloads.deleteModel(repoId: pick.repoId)
                        appState.refreshModels()
                    } label: { Text("Delete")
                        .font(.app(.body)) }
                    .keyboardShortcut(.defaultAction)
                } message: {
                    Text(L10n.format("Delete %@? This will remove all downloaded files.", pick.name)).font(.app(.body))
                }
            }
        } else if let state, state.status == .downloading {
            HStack(spacing: 6) {
                VStack(alignment: .trailing, spacing: 1) {
                    ProgressView(value: state.progress)
                        .frame(width: 70)
                    Text("\(state.percentFormatted) \(state.speedFormatted)")
                        .font(.app(.caption2).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Button {
                    downloads.cancel(pick.repoId)
                    appState.refreshModels()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 22, minHeight: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel("Cancel download")
                .help("Cancel download")
            }
        } else if let state, state.status == .failed {
            VStack(alignment: .trailing, spacing: 2) {
                Button { startDownload() } label: { Text(L10n.text(downloads.hasPartialDownload(pick.repoId) ? "Resume" : "Retry"))
                    .font(.app(.body)) }
                    .controlSize(.small)
                if let error = state.error {
                    Text(error)
                        .font(.app(.caption2))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
        } else {
            Button { startDownload() } label: { Text(L10n.text(downloads.hasPartialDownload(pick.repoId) ? "Resume" : "Download"))
                .font(.app(.body)) }
                .controlSize(.small).font(.app(.body))
        }
    }

    private func startDownload() {
        if let f = pick.ggufFilename {
            // GGUF/ds4 pick: fetch the specific quant (the download path also
            // auto-pulls the ds4 MTP draft head).
            downloads.startGguf(
                repoId: pick.repoId,
                quant: GgufQuant(filename: f, label: DownloadManager.quantLabel(forFilename: f))
            ) { appState.refreshModels() }
        } else {
            downloads.start(repoId: pick.repoId) { appState.refreshModels() }
        }
    }
}

// MARK: - Discover

/// HuggingFace search. On-disk models stay in the list, marked `✓ On disk` with
/// a Use action — never filtered out.
private struct DiscoverPane: View {
    @EnvironmentObject var searchService: HFSearchService
    @EnvironmentObject var downloads: DownloadManager

    /// Measured pane width → column tier. 0 until the first layout pass,
    /// which `ModelBrowserMetrics.tier` treats as roomy.
    @State private var paneWidth: CGFloat = 0

    private var tier: ModelBrowserMetrics.Tier {
        ModelBrowserMetrics.tier(forDetailWidth: paneWidth)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search models...", text: $searchService.searchQuery)
                        .textFieldStyle(.plain)
                        .onSubmit { Task { await searchService.search() } }.font(.app(.body))
                }
                .padding(8)
                .background(.quaternary.opacity(0.5))
                .cornerRadius(8)

                // Weight-format filter: MLX (safetensors), GGUF (llama.cpp /
                // ds4), or Both. Re-runs the search on change.
                Picker("Format", selection: $searchService.format) {
                    ForEach(ModelFormat.allCases) { f in
                        Text(L10n.text(f.label)).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .onChange(of: searchService.format) { _, _ in
                    Task { await searchService.search() }
                }

                Button {
                    Task { await searchService.search() }
                } label: { Text("Search")
                    .font(.app(.body)) }
                .controlSize(.regular)
            }
            .padding(12)

            Divider()

            ColumnHeaderRow(searchService: searchService, tier: tier)
                .padding(.horizontal, ModelBrowserMetrics.rowPaddingH)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.3))

            Divider()

            let onDiskCount = searchService.models.filter { downloads.isReady($0.id) }.count

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(searchService.models) { model in
                        ModelBrowserRow(
                            model: model,
                            fitness: searchService.ramFitness(for: model),
                            tier: tier
                        )
                        Divider().padding(.horizontal, 12)
                    }

                    if searchService.isLoading {
                        ProgressView()
                            .padding(20)
                    } else if let error = searchService.error {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.app(.caption))
                            .padding(20)
                    } else if searchService.models.isEmpty {
                        Text(L10n.text("No models found"))
                            .foregroundStyle(.secondary)
                            .padding(40).font(.app(.body))
                    }

                    if searchService.hasMore && !searchService.models.isEmpty && !searchService.isLoading {
                        Button {
                            Task { await searchService.loadMore() }
                        } label: { Text("Load More")
                            .font(.app(.body)) }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .padding(16)
                    }
                }
            }

            Divider()

            HStack {
                Text(L10n.format("Showing %lld models", Int64(searchService.models.count)))
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                if onDiskCount > 0 {
                    Text(L10n.format("· %lld on disk", Int64(onDiskCount)))
                        .font(.app(.caption))
                        .foregroundStyle(.green)
                }
                Spacer()
                Text(L10n.format("System RAM: %@", MemoryInfo.format(Int64(searchService.systemRAM))))
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        // Track the pane's width for the column-tier decision — same
        // pattern as ChatView's toolbar pill density.
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { paneWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, w in paneWidth = w }
            }
        )
        .navigationTitle("Discover")
    }
}

// MARK: - My Models

/// Everything on this Mac the tray picker can offer, grouped by where it came
/// from. The old "Downloaded" tab listed only `source == .mlxServe`, so it was a
/// strict subset of what you could actually load.
private struct MyModelsPane: View {
    @Binding var filter: String
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var downloads: DownloadManager

    @State private var freeDiskSpace: String = ""
    @State private var sweepItems: [(model: LocalModel, check: UpdateCheck)] = []
    @State private var showSweepAlert = false

    private var groups: [LocalModelGroup] {
        ModelBrowserUse.groupedBySource(appState.localModels, filter: filter)
    }

    private var total: Int { groups.reduce(0) { $0 + $1.models.count } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter your models...", text: $filter)
                    .textFieldStyle(.plain).font(.app(.body))
                if !filter.isEmpty {
                    Button { filter = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary).font(.app(.body))
                }
            }
            .padding(8)
            .background(.quaternary.opacity(0.5))
            .cornerRadius(8)
            .padding(12)

            Divider()

            HStack(spacing: 8) {
                Text("Model")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Size on Disk")
                    .frame(width: 90, alignment: .trailing)
                Text("")
                    .frame(width: 120)
            }
            .font(.app(.callout).weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.3))

            Divider()

            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.models) { model in
                                LocalModelRow(model: model)
                                Divider().padding(.horizontal, 12)
                            }
                        } header: {
                            Text(L10n.text(group.title))
                                .font(.app(.caption).weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(.bar)
                        }
                    }

                    if groups.isEmpty {
                        Text(L10n.text(filter.isEmpty ? "No models on this Mac yet" : "No models match “\(filter)”"))
                            .foregroundStyle(.secondary)
                            .padding(40).font(.app(.body))
                    }
                }
            }

            Divider()

            HStack {
                Text(L10n.format(total == 1 ? "%lld model on disk" : "%lld models on disk", Int64(total)))
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                if let (done, count) = downloads.updateSweep {
                    ProgressView().controlSize(.mini)
                    Text(L10n.format("Checking %lld/%lld\u{2026}", Int64(done), Int64(count)))
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                } else {
                    Button("Check for Updates") {
                        Task {
                            await downloads.checkAllForUpdates(models: appState.localModels)
                            sweepItems = PackUpdateCheck.available(downloads.updateChecks, models: appState.localModels)
                            showSweepAlert = true
                        }
                    }
                    .buttonStyle(.link)
                    .font(.app(.caption))
                    .help("Compare every model with its Hugging Face repo")
                    if !downloads.updateChecks.isEmpty {
                        Text(verbatim: PackUpdateCheck.summary(downloads.updateChecks.values.map(\.result)))
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if !freeDiskSpace.isEmpty {
                    Text(L10n.format("%@ available", freeDiskSpace))
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .alert(sweepItems.isEmpty ? "No Updates" : "Updates Available", isPresented: $showSweepAlert) {
                if sweepItems.isEmpty {
                    Button("OK", role: .cancel) {}
                } else {
                    Button("Update All") {
                        for item in sweepItems {
                            downloads.applyUpdate(item.check, for: item.model) { appState.refreshModels() }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("Cancel", role: .cancel) {}
                }
            } message: {
                Text(verbatim: sweepItems.isEmpty
                     ? PackUpdateCheck.summary(downloads.updateChecks.values.map(\.result))
                     : PackUpdateCheck.sweepMessage(sweepItems))
            }
        }
        .navigationTitle("My Models")
        .onAppear {
            updateDiskSpace()
        }
        .onChange(of: appState.localModels.count) { _, _ in
            updateDiskSpace()
        }
        .onChange(of: downloads.modelsDir) { _, _ in
            updateDiskSpace()
        }
    }

    private func updateDiskSpace() {
        freeDiskSpace = ModelBrowserMetrics.freeSpaceLabel(
            availableBytes: VolumeCapacity.available(atPath: downloads.modelsDir)
        )
    }
}

// MARK: - Downloads

/// The transfer queue. Promoted out of the old Downloaded tab so an in-flight
/// download is reachable (and badged) from anywhere in the browser.
private struct DownloadsPane: View {
    let items: [(repoId: String, state: DownloadManager.DownloadState)]
    let showModels: () -> Void
    @EnvironmentObject var downloads: DownloadManager

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                ContentUnavailableView {
                    Label("No Downloads", systemImage: "arrow.down.circle")
                } description: {
                    Text("Downloads you start from Recommended, Discover, or Media appear here.")
                }
            } else {
                List {
                    rows(status: .downloading, title: "Downloading")
                    rows(status: .failed, title: "Needs Attention")
                    rows(status: .completed, title: "Completed")
                }
                .listStyle(.inset)
                if items.contains(where: { $0.state.status == .completed }) {
                    HStack {
                        Spacer()
                        Button("Clear Completed") {
                            for item in items where item.state.status == .completed {
                                downloads.dismissDownload(repoId: item.repoId)
                            }
                        }
                        .help("Remove completed downloads from this list. Model files stay on disk.")
                    }
                    .padding(12)
                }
            }
        }
        .navigationTitle("Downloads")
    }

    @ViewBuilder
    private func rows(status: DownloadManager.DownloadState.Status, title: String) -> some View {
        let matching = items.filter { $0.state.status == status }
        if !matching.isEmpty {
            Section(L10n.text(title)) {
                ForEach(matching, id: \.repoId) { item in
                    ActiveDownloadRow(repoId: item.repoId, state: item.state, showModels: showModels)
                }
            }
        }
    }
}

// MARK: - Media pane

/// Every media-generation model (image/audio/video/music), grouped by
/// modality. Its own sidebar destination — there's one catalog per modality
/// and none of them are large enough to need Discover-style search, so one
/// scrollable page beats splitting each modality into its own sidebar row.
private struct MediaPane: View {
    private var physicalMemory: UInt64 { ProcessInfo.processInfo.physicalMemory }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ModelGroupSection(
                    title: "Image",
                    subtitle: "Text-to-image generation and image editing.",
                    systemImage: "photo",
                    tint: .pink
                ) {
                    ForEach(ImageModelPreset.all) { MediaModelRow(preset: $0, modality: .image, physicalMemoryBytes: physicalMemory) }
                }
                ModelGroupSection(
                    title: "Audio",
                    subtitle: "Text-to-speech, with optional voice cloning.",
                    systemImage: "waveform",
                    tint: .green
                ) {
                    // The browser lists the FULL catalog — Kokoro is voice-mode
                    // only (out of `.all`, which the media panes offer) but is
                    // still a model the user can fetch from here.
                    ForEach(AudioModelPreset.allIncludingVoiceOnly) { MediaModelRow(preset: $0, modality: .voice, physicalMemoryBytes: physicalMemory) }
                }
                ModelGroupSection(
                    title: "Video",
                    subtitle: "Text/image-to-video, with optional audio.",
                    systemImage: "film",
                    tint: .indigo
                ) {
                    ForEach(VideoModelPreset.all) { MediaModelRow(preset: $0, modality: .video, physicalMemoryBytes: physicalMemory) }
                }
                ModelGroupSection(
                    title: "Music",
                    subtitle: "Text-to-music, with optional lyrics.",
                    systemImage: "music.note",
                    tint: .orange
                ) {
                    ForEach(MusicModelPreset.all) { MediaModelRow(preset: $0, modality: .music, physicalMemoryBytes: physicalMemory) }
                }
                ModelGroupSection(
                    title: "Sound Effects",
                    subtitle: "Text-to-audio: effects and ambiences.",
                    systemImage: "speaker.wave.3",
                    tint: .teal
                ) {
                    ForEach(SoundModelPreset.all) { MediaModelRow(preset: $0, modality: .sound, physicalMemoryBytes: physicalMemory) }
                }
            }
            .padding(16)
        }
        .navigationTitle("Media")
    }
}

/// One family/modality group's header (icon, name, what it's for) over its
/// list of rows — shared by the Recommended pane (grouped by model family)
/// and the Media pane (grouped by modality).
private struct ModelGroupSection<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.text(title)).font(.app(.subheadline).weight(.semibold))
                    Text(L10n.text(subtitle)).font(.app(.caption2)).foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(spacing: 0) {
                content
            }
            .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// One row for any media preset (image/audio/video/music) — generic over
/// `MediaModelPreset` so the four modalities share this instead of four
/// near-duplicate views. Download/progress/retry mirrors `BundleDownloadBar`.
///
/// The terminal state used to be on-disk + Delete and nothing else, on the
/// reasoning that each gen pane keeps its own sticky model selection. But that
/// left "throw it away" as the only verb the browser offered for a model it
/// had just finished downloading (#228). `Use` opens the owning pane; the pane
/// still keeps its own selection, so this is navigation, not a second loader.
/// The modality is passed in rather than derived — the Media pane already
/// groups by it, so the call site knows it exactly.
private struct MediaModelRow<Preset: MediaModelPreset>: View {
    let preset: Preset
    let modality: MediaModality
    let physicalMemoryBytes: UInt64
    @EnvironmentObject var downloads: DownloadManager
    @EnvironmentObject var appState: AppState
    @State private var confirmDelete = false
    @State private var card: ModelCardRequest?

    private var bundle: MediaBundle { preset.bundle }
    private var isReady: Bool { downloads.bundleReady(bundle) }
    private var active: (repo: String, index: Int, count: Int, state: DownloadManager.DownloadState)? {
        downloads.activeBundleComponent(bundle)
    }

    /// Soft signal only — shows a warning, never blocks downloading or using
    /// it (same "warn, don't gate" policy as the Recommended pane).
    private var meetsRequirements: Bool {
        preset.meetsSystemRequirements(physicalMemoryBytes: physicalMemoryBytes)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { card = ModelCardRequest(repoId: bundle.primaryRepo, title: preset.name) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text(preset.name))
                    .font(.app(.callout).weight(.medium))

                Text(L10n.text(preset.description))
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if bundle.components.count > 1 {
                    Text(L10n.format("Includes %lld models (e.g. a text encoder)", Int64(bundle.components.count)))
                        .font(.app(.caption2))
                        .foregroundStyle(.tertiary)
                }

                if !meetsRequirements {
                    Label(
                        "Needs about \(preset.approxRAMGB) GB of RAM — your Mac has \(MemoryInfo.format(Int64(physicalMemoryBytes)))",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.app(.caption2).weight(.medium))
                    .foregroundStyle(.orange)
                }

                if let active, active.state.status == .failed, let error = active.state.error {
                    Text(error)
                        .font(.app(.caption2))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                Text(L10n.text(bundle.approxSizeLabel))
                    .font(.app(.caption2))
                    .foregroundStyle(.tertiary)
                actionControl
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .sheet(item: $card) { ModelDetailSheet(request: $0) }
    }

    @ViewBuilder
    private var actionControl: some View {
        if isReady {
            HStack(spacing: 6) {
                UseMediaModelButton(modality: modality, name: preset.name, presetID: preset.id)
                Button {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red.opacity(0.7))
                        .frame(minWidth: 22, minHeight: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel("Delete model")
                .help("Delete model")
                .alert("Delete Model", isPresented: $confirmDelete) {
                    Button(role: .cancel) {} label: { Text("Cancel")
                        .font(.app(.body)) }
                    Button(role: .destructive) {
                        downloads.deleteModel(repoId: bundle.primaryRepo)
                        appState.refreshModels()
                    } label: { Text("Delete")
                        .font(.app(.body)) }
                    .keyboardShortcut(.defaultAction)
                } message: {
                    Text(L10n.format("Delete %@? This will remove the downloaded files.", preset.name)).font(.app(.body))
                }
            }
        } else if let active, active.state.status == .downloading {
            HStack(spacing: 6) {
                VStack(alignment: .trailing, spacing: 1) {
                    ProgressView(value: active.state.progress)
                        .frame(width: 70)
                    Text("\(active.state.percentFormatted) \(active.state.speedFormatted)")
                        .font(.app(.caption2).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Button {
                    downloads.cancelBundle(bundle)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 22, minHeight: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel("Cancel download")
                .help("Cancel download")
            }
        } else if active?.state.status == .failed {
            Button { startDownload() } label: { Text("Retry")
                .font(.app(.body)) }
                .controlSize(.small)
        } else {
            Button { startDownload() } label: { Text("Download")
                .font(.app(.body)) }
                .controlSize(.small)
        }
    }

    private func startDownload() {
        downloads.startBundle(bundle) { appState.refreshModels() }
    }
}

// MARK: - Use button

/// The "Use" control for any Model Browser row (Discover / My Models /
/// Recommended): selects the model, makes the server actually load it
/// (starting it if stopped, hot-switching/restarting if already running),
/// and once it's ready opens the Chat window — a click ends in a
/// ready-to-chat server, not just a selection the user then has to start
/// themselves. Shared so the three rows can't drift onto three slightly
/// different "Use" behaviors.
private struct UseModelButton: View {
    let path: String
    let name: String
    @EnvironmentObject var appState: AppState
    @State private var isLoading = false

    var body: some View {
        Button {
            Task {
                isLoading = true
                let ready = await appState.useModelAndAwaitReady(atPath: path)
                isLoading = false
                if ready { appState.showChat() }
            }
        } label: {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 30)
            } else {
                Text("Use").font(.app(.body))
            }
        }
        .controlSize(.small)
        .disabled(isLoading)
        .help("Load \(name) as the server's model, then open chat")
    }
}

/// "Use" for a media checkpoint: open the pane that owns it.
///
/// Model selection and workspace routing share the global chooser's path.
private struct UseMediaModelButton: View {
    let modality: MediaModality
    let name: String
    var path: String = ""
    var presetID: String? = nil
    @EnvironmentObject var appState: AppState

    private var selectedID: String? {
        presetID ?? ModelBrowserUse.mediaPresetID(modality: modality, name: name, path: path,
                                                  models: appState.server.allModels)
    }

    var body: some View {
        Button {
            appState.selectMediaModel(modality: modality, name: name, path: path, presetID: selectedID)
        } label: {
            Text(L10n.text(selectedID == nil ? "Open" : "Use"))
                .font(.app(.body))
        }
        .controlSize(.small)
        .help(selectedID == nil
              ? L10n.format("Open %@ to choose a model", L10n.text(modality.paneName))
              : L10n.format("Use %@ in %@", name, L10n.text(modality.paneName)))
    }
}

private struct UseDecisionModelButton: View {
    let path: String
    let name: String
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            appState.decisionsModelPath = path
            AppActivation.openWindow(id: "decisions", using: openWindow)
        } label: { Text("Use")
            .font(.app(.body)) }
        .controlSize(.small)
        .help("Open \(name) in Decisions")
    }
}

// MARK: - In-use badge

/// Replaces the "Use" button on the model the server is pointed at, so clicking
/// Use produces immediate, visible feedback instead of just greying the button
/// out. Distinguishes "loaded and serving" from "selected, still loading" and
/// "selected, server stopped" — see `ModelUseState`.
private struct ModelUseBadge: View {
    let state: ModelUseState

    private var tint: Color {
        switch state {
        case .inUse:    return .green
        case .loading:  return .orange
        case .selected: return .secondary
        case .idle:     return .clear
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            switch state {
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.5)
                    .frame(width: 8, height: 8)
            case .inUse:
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
            default:
                EmptyView()
            }
            Text(L10n.text(state.label))
                .font(.app(.caption).weight(.medium))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tint.opacity(0.12), in: Capsule())
        .help(L10n.text(state.help))
    }
}

// MARK: - Column Headers

/// Column widths and visibility come from `ModelBrowserMetrics` — the ONE
/// source of truth shared with `ModelBrowserRow`, so header/row alignment
/// can't drift and narrow panes drop the same columns in both.
private struct ColumnHeaderRow: View {
    @ObservedObject var searchService: HFSearchService
    let tier: ModelBrowserMetrics.Tier

    var body: some View {
        HStack(spacing: ModelBrowserMetrics.columnSpacing) {
            Text("Model")
                .frame(maxWidth: .infinity, alignment: .leading)
            SortableHeader("Quant", field: nil, searchService: searchService)
                .frame(width: ModelBrowserMetrics.quantWidth, alignment: .leading)
            SortableHeader("Size", field: nil, searchService: searchService)
                .frame(width: ModelBrowserMetrics.sizeWidth, alignment: .trailing)
            // HuggingFace pull count. Called "Pulls", NOT "Downloads": the
            // sidebar has a Downloads destination meaning "transferring right
            // now", and having both words in one window is what made users read
            // the old "Downloaded" toggle as a filter on this column. 64 wide
            // fits "Pulls" + the sort chevron.
            if tier.showsPulls {
                SortableHeader("Pulls", field: .downloads, searchService: searchService)
                    .frame(width: ModelBrowserMetrics.pullsWidth, alignment: .trailing)
                    .help("How many times this repo has been pulled from HuggingFace")
            }
            if tier.showsLikes {
                SortableHeader("Likes", field: .likes, searchService: searchService)
                    .frame(width: ModelBrowserMetrics.likesWidth, alignment: .trailing)
            }
            SortableHeader("RAM Est.", field: .estimatedSize, searchService: searchService)
                .frame(width: ModelBrowserMetrics.ramWidth, alignment: .trailing)
            if tier.showsUpdated {
                SortableHeader("Updated", field: .lastModified, searchService: searchService)
                    .frame(width: ModelBrowserMetrics.updatedWidth, alignment: .trailing)
            }
            Text("")
                .frame(width: ModelBrowserMetrics.actionWidth)
        }
        .font(.app(.callout).weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

private struct SortableHeader: View {
    let title: String
    let field: HFSortField?
    @ObservedObject var searchService: HFSearchService

    init(_ title: String, field: HFSortField?, searchService: HFSearchService) {
        self.title = title
        self.field = field
        self.searchService = searchService
    }

    private var isActive: Bool {
        guard let field else { return false }
        return searchService.sortField == field
    }

    var body: some View {
        if let field {
            Button {
                searchService.sort(by: field)
            } label: {
                HStack(spacing: 2) {
                    Text(L10n.text(title))
                    if isActive {
                        Image(systemName: searchService.sortDescending ? "chevron.down" : "chevron.up")
                            .font(.app(.caption2))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isActive ? .primary : .secondary)
        } else {
            Text(L10n.text(title)).font(.app(.body))
        }
    }
}

// MARK: - Model Row

private struct ModelBrowserRow: View {
    let model: HFModel
    let fitness: RAMFitness
    let tier: ModelBrowserMetrics.Tier
    @EnvironmentObject var downloads: DownloadManager
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var server: ServerManager

    private var isReady: Bool { downloads.isReady(model.id) }
    private var state: DownloadManager.DownloadState? { downloads.downloads[model.id] }
    private var disabled: Bool { !model.isCompatible }
    @State private var card: ModelCardRequest?

    var body: some View {
        HStack(spacing: ModelBrowserMetrics.columnSpacing) {
            // Model name — takes all remaining space; click opens the card.
            Button { card = ModelCardRequest(repoId: model.id, title: model.modelName) } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.text(model.modelName))
                    .font(.app(.callout).weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(L10n.text(model.author))
                        .font(.app(.caption))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    if let reason = model.incompatibleReason {
                        Text(L10n.text(reason))
                            .font(.app(.caption2))
                            .foregroundStyle(.red.opacity(0.8))
                            .lineLimit(1)
                    }
                }
            }
            .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Quantization badge
            Group {
                if let quant = model.quantization {
                    Text(L10n.text(quant))
                        .font(.app(.caption2).weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .cornerRadius(4)
                } else {
                    Text("\u{2014}").font(.app(.body))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: ModelBrowserMetrics.quantWidth, alignment: .leading)

            // Size (parsed from model name)
            Text(L10n.text(model.modelSize))
                .font(.app(.callout).monospacedDigit())
                .frame(width: ModelBrowserMetrics.sizeWidth, alignment: .trailing)

            // HF pull count
            if tier.showsPulls {
                Text(formatCount(model.downloads ?? 0))
                    .font(.app(.callout).monospacedDigit())
                    .frame(width: ModelBrowserMetrics.pullsWidth, alignment: .trailing)
            }

            // Likes
            if tier.showsLikes {
                Text(formatCount(model.likes ?? 0))
                    .font(.app(.callout).monospacedDigit())
                    .frame(width: ModelBrowserMetrics.likesWidth, alignment: .trailing)
            }

            // RAM estimate with color indicator — 120 so GGUF range strings
            // like "21.2–55.4 GB" stay on one line. `.lineLimit(1)` is the
            // belt-and-suspenders guard against any future format that
            // exceeds the budget — we'd rather truncate than wrap.
            HStack(spacing: 4) {
                Circle()
                    .fill(fitnessColor)
                    .frame(width: 8, height: 8)
                Text(L10n.text(model.ramEstimate))
                    .font(.app(.callout).monospacedDigit())
                    .lineLimit(1)
            }
            .frame(width: ModelBrowserMetrics.ramWidth, alignment: .trailing)

            // Last updated
            if tier.showsUpdated {
                Text(formatRelativeDate(model.lastModifiedDate))
                    .font(.app(.callout))
                    .foregroundStyle(.secondary)
                    .frame(width: ModelBrowserMetrics.updatedWidth, alignment: .trailing)
            }

            actionCell
                .frame(width: ModelBrowserMetrics.actionWidth, alignment: .center)
        }
        .padding(.horizontal, ModelBrowserMetrics.rowPaddingH)
        .padding(.vertical, 6)
        .opacity(disabled ? 0.4 : 1.0)
        .sheet(item: $card) { ModelDetailSheet(request: $0) }
    }

    private var fitnessColor: Color {
        switch fitness {
        case .fits: return .green
        case .tight: return .yellow
        case .wontFit: return .red
        case .unknown: return .gray
        }
    }

    @State private var confirmDelete = false

    /// Resolved by the pure state machine so the branch ladder is unit-tested
    /// (`ModelBrowserSectionTests`). The key change: a ready model resolves to
    /// `.onDisk` and stays in the list, where it used to be filtered out of the
    /// search results entirely — vanishing at the exact moment it finished.
    private var action: ModelRowAction {
        ModelRowAction.resolve(
            isCompatible: model.isCompatible,
            isReady: isReady,
            status: state?.status,
            hasPartial: downloads.hasPartialDownload(model.id),
            progress: state?.progress ?? 0
        )
    }

    /// The on-disk model this row's repo resolves to, when it's loadable as the
    /// server's chat model. nil for drafters, encoders, and media checkpoints —
    /// they're on disk and deletable, but "Use" would load something that can't
    /// serve a completion.
    private var usableModel: LocalModel? {
        ModelBrowserUse.pickableModel(
            atPath: downloads.existingModelDir(for: model.id),
            in: appState.localModels
        )
    }

    /// The other half of the catalogue — see `ModelBrowserUse.mediaModel`.
    private var usableMedia: (model: LocalModel, modality: MediaModality)? {
        ModelBrowserUse.mediaModel(
            atPath: downloads.existingModelDir(for: model.id),
            in: appState.localModels
        )
    }

    /// A verified community media pack downloads as its FAMILY bundle — the
    /// same allowlists + ready markers the catalog packs use — never the flat
    /// chat-default pull, which would miss subdirs and grab repo junk. nil for
    /// everything that isn't a served media repo.
    private var mediaBundle: MediaBundle? {
        guard model.mediaStructureVerified == true,
              let arch = model.mediaFamilyModelType else { return nil }
        return CustomMediaModels.bundle(arch: arch, repoId: model.id)
    }

    /// Start (or resume) this row's download. The media arm also asks the
    /// running server to rescan afterward — boot-time discovery can't see a
    /// model downloaded mid-session, and the media panes' "On This Mac" rows
    /// read `/v1/models`.
    private func startDownload() {
        if let b = mediaBundle {
            downloads.startBundle(b) {
                appState.refreshModels()
                server.rescanModels()
            }
        } else {
            downloads.start(repoId: model.id) { appState.refreshModels() }
        }
    }

    @ViewBuilder
    private var actionCell: some View {
        // Same shelf shape as GGUF, in directories instead of files: some MLX
        // repos publish every quant as a subfolder (`LiquidAI/LFM2.5-2.6B-MLX`).
        // Checked first — such a repo carries no `gguf` tag, so the two can't
        // both match.
        if model.isMlxVariantRepo, action != .unsupported {
            if case .downloading(let progress) = action {
                downloadingCell(progress: progress)
            } else {
                MlxVariantMenu(repoId: model.id, variants: model.mlxVariants, state: state)
            }
        }
        // A GGUF repo is a FOLDER OF QUANTS, not a model, so it never reaches a
        // terminal "on disk" state: owning Q4_K_M says nothing about whether you
        // also want Q8_0. Its cell stays a menu that marks what you have and
        // keeps offering what you don't — the old `.onDisk` collapse to
        // "✓ On disk" + trash left no way back to the quant picker.
        else if model.isGgufRepo, action != .unsupported {
            if case .downloading(let progress) = action {
                downloadingCell(progress: progress)
            } else {
                GgufQuantMenu(repoId: model.id, state: state)
            }
        } else {
            switch action {
            case .unsupported:
                Image(systemName: "nosign")
                    .foregroundStyle(.secondary)
                    .font(.app(.caption))

            case .onDisk:
                HStack(spacing: 6) {
                    if let usable = usableModel {
                        let use = ModelUseState.resolve(
                            selected: appState.selectedModelPath == usable.path,
                            serverStatus: server.status
                        )
                        if use == .idle {
                            UseModelButton(path: usable.path, name: usable.name)
                        } else {
                            ModelUseBadge(state: use)
                        }
                    } else if let media = usableMedia {
                        UseMediaModelButton(modality: media.modality, name: media.model.name, path: media.model.path)
                    } else {
                        Text("✓ On disk")
                            .font(.app(.caption).weight(.medium))
                            .foregroundStyle(.green)
                    }
                    deleteButton
                }

            case .downloading(let progress):
                downloadingCell(progress: progress)

            case .failed(let resumable):
                Button {
                    startDownload()
                } label: { Text(L10n.text(resumable ? "Resume" : "Retry"))
                    .font(.app(.body)) }
                .font(.app(.callout))
                .controlSize(.small)

            case .notDownloaded(let resumable):
                Button {
                    startDownload()
                } label: { Text(L10n.text(resumable ? "Resume" : "Download"))
                    .font(.app(.body)) }
                .font(.app(.callout))
                .controlSize(.small)
            }
        }
    }

    private func downloadingCell(progress: Double) -> some View {
        HStack(spacing: 4) {
            VStack(spacing: 1) {
                ProgressView(value: progress)
                    .frame(width: 50)
                Text(state?.percentFormatted ?? "")
                    .font(.app(.caption2).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button {
                // A bundle download's task is keyed by the BUNDLE id — a
                // per-repo cancel would only wipe state, not stop the loop.
                if let b = mediaBundle { downloads.cancelBundle(b) } else { downloads.cancel(model.id) }
                appState.refreshModels()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 22, minHeight: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .accessibilityLabel("Cancel download")
            .help("Cancel download")
        }
    }

    private var deleteButton: some View {
        Button {
            confirmDelete = true
        } label: {
            Image(systemName: "trash")
                .foregroundStyle(.red.opacity(0.7))
                .frame(minWidth: 22, minHeight: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .font(.app(.callout))
        .accessibilityLabel("Delete model")
        .help("Delete model")
        .alert("Delete Model", isPresented: $confirmDelete) {
            Button(role: .cancel) {} label: { Text("Cancel")
                .font(.app(.body)) }
            Button(role: .destructive) {
                downloads.deleteModel(repoId: model.id)
                appState.refreshModels()
            } label: { Text("Delete")
                .font(.app(.body)) }
            .keyboardShortcut(.defaultAction)
        } message: {
            Text(L10n.format("Delete %@? This will remove all downloaded files.", model.modelName)).font(.app(.body))
        }
    }
}

/// The action cell for a GGUF repo: one menu covering every quant, in every
/// state.
private struct GgufQuantMenu: View {
    let repoId: String
    let state: DownloadManager.DownloadState?
    @EnvironmentObject var downloads: DownloadManager
    @EnvironmentObject var appState: AppState
    @State private var remote: [String] = []
    @State private var loaded = false
    @State private var pendingDelete: GgufQuant?

    private var menu: GgufQuantMenuModel.Menu {
        GgufQuantMenuModel.build(
            remote: remote,
            // Recursive paths so a sharded quant's nested shards are seen and an
            // incomplete split reads as available (resume), not on-disk.
            onDisk: downloads.downloadedGgufPaths(repoId: repoId)
        )
    }

    /// Where a quant lives on disk — the path the server loads and the tray
    /// picker selects, so "Use" here and picking it in the tray are the same act.
    /// `quant.filename` is the repo-relative PRIMARY shard, so this resolves to
    /// the `-00001` shard for a sharded quant (libllama auto-loads the rest).
    private func path(of quant: GgufQuant) -> String? {
        guard let dir = downloads.existingModelDir(for: repoId) else { return nil }
        return (dir as NSString).appendingPathComponent(quant.filename)
    }

    var body: some View {
        let m = menu
        Menu {
            if !m.onDisk.isEmpty {
                Section("On this Mac") {
                    ForEach(m.onDisk) { quant in
                        Button {
                            guard let p = path(of: quant) else { return }
                            Task { _ = await appState.useModelAndAwaitReady(atPath: p) }
                        } label: {
                            let selected = path(of: quant) == appState.selectedModelPath
                            Label(
                                L10n.format(selected ? "%@ — in use" : "%@ — use",
                                            L10n.text(quant.label)),
                                systemImage: selected ? "checkmark.circle.fill" : "checkmark"
                            )
                        }
                    }
                }
            }

            Section(L10n.text(m.onDisk.isEmpty ? "Choose a quant" : "Download another")) {
                if !loaded {
                    Text("Loading quants…")
                } else if m.available.isEmpty {
                    Text(L10n.text(m.onDisk.isEmpty ? "No GGUF files found" : "Every quant is downloaded"))
                } else {
                    ForEach(m.available) { quant in
                        Button {
                            // Pass the whole quant — a sharded one pulls every
                            // shard into `<model>/<quant>/`.
                            downloads.startGguf(repoId: repoId, quant: quant) {
                                appState.refreshModels()
                            }
                        } label: { Text(L10n.text(quant.label))
                            .font(.app(.body)) }
                    }
                }
            }

            if !m.onDisk.isEmpty {
                // Deletes remove ONE quant. Its siblings are separate models the
                // user didn't ask to delete.
                Menu("Delete") {
                    ForEach(m.onDisk) { quant in
                        Button(role: .destructive) { pendingDelete = quant } label: { Text(L10n.text(quant.label))
                            .font(.app(.body)) }
                    }
                }
            }
        } label: {
            Text(L10n.text(
                GgufQuantMenuModel.buttonLabel(
                onDisk: m.onDisk,
                failed: state?.status == .failed,
                hasPartial: downloads.hasPartialDownload(repoId)
            )
)).font(.app(.body))
        }
        .menuStyle(.button)
        .controlSize(.small)
        .fixedSize()
        .task {
            guard !loaded else { return }
            remote = await downloads.listGgufFiles(repoId: repoId)
            loaded = true
        }
        .alert("Delete Quant", isPresented: .init(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { quant in
            Button(role: .cancel) { pendingDelete = nil } label: { Text("Cancel")
                .font(.app(.body)) }
            Button(role: .destructive) {
                if let p = path(of: quant) { downloads.removeGgufQuant(at: p) }
                pendingDelete = nil
                appState.refreshModels()
            } label: { Text("Delete")
                .font(.app(.body)) }
            .keyboardShortcut(.defaultAction)
        } message: { quant in
            Text(L10n.format("Delete the %@ quant? Other quants of this model stay on disk.", quant.label)).font(.app(.body))
        }
    }
}

/// The action cell for a multi-variant MLX repo — the directory-shaped twin of
/// `GgufQuantMenu`.
private struct MlxVariantMenu: View {
    let repoId: String
    let variants: [MlxVariant]
    let state: DownloadManager.DownloadState?
    @EnvironmentObject var downloads: DownloadManager
    @EnvironmentObject var appState: AppState
    @State private var pendingDelete: MlxVariant?

    /// Each variant is its own ordinary model dir — see `MlxVariantScan.localRepoId`.
    private func localId(_ v: MlxVariant) -> String {
        MlxVariantScan.localRepoId(repoId: repoId, folder: v.folder)
    }
    private func path(of v: MlxVariant) -> String? { downloads.existingModelDir(for: localId(v)) }

    private var menu: MlxVariantMenuModel.Menu {
        MlxVariantMenuModel.build(
            remote: variants,
            onDisk: Set(variants.filter { downloads.isReady(localId($0)) }.map(\.folder))
        )
    }

    private func title(_ v: MlxVariant) -> String {
        v.sizeLabel.isEmpty ? v.label : "\(v.label) · \(v.sizeLabel)"
    }

    var body: some View {
        let m = menu
        Menu {
            if !m.onDisk.isEmpty {
                Section("On this Mac") {
                    ForEach(m.onDisk) { v in
                        Button {
                            guard let p = path(of: v) else { return }
                            Task { _ = await appState.useModelAndAwaitReady(atPath: p) }
                        } label: {
                            let selected = path(of: v) == appState.selectedModelPath
                            Label(
                                L10n.format(selected ? "%@ — in use" : "%@ — use",
                                            L10n.text(v.label)),
                                systemImage: selected ? "checkmark.circle.fill" : "checkmark"
                            )
                        }
                    }
                }
            }

            Section(L10n.text(m.onDisk.isEmpty ? "Choose a quantization" : "Download another")) {
                if m.available.isEmpty {
                    Text("Every quantization is downloaded")
                } else {
                    ForEach(m.available) { v in
                        Button {
                            downloads.startMlxVariant(repoId: repoId, variant: v) {
                                appState.refreshModels()
                            }
                        } label: { Text(L10n.text(title(v)))
                            .font(.app(.body)) }
                    }
                }
            }

            if !m.onDisk.isEmpty {
                // Deletes remove ONE variant. Its siblings are separate models
                // the user didn't ask to delete.
                Menu("Delete") {
                    ForEach(m.onDisk) { v in
                        Button(role: .destructive) { pendingDelete = v } label: { Text(L10n.text(v.label))
                            .font(.app(.body)) }
                    }
                }
            }
        } label: {
            Text(L10n.text(
                MlxVariantMenuModel.buttonLabel(
                onDisk: m.onDisk,
                failed: state?.status == .failed,
                hasPartial: variants.contains { downloads.hasPartialDownload(localId($0)) }
            )
)).font(.app(.body))
        }
        .menuStyle(.button)
        .controlSize(.small)
        .fixedSize()
        .alert("Delete Quantization", isPresented: .init(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { v in
            Button(role: .cancel) { pendingDelete = nil } label: { Text("Cancel")
                .font(.app(.body)) }
            Button(role: .destructive) {
                downloads.deleteModel(repoId: localId(v))
                pendingDelete = nil
                appState.refreshModels()
            } label: { Text("Delete")
                .font(.app(.body)) }
            .keyboardShortcut(.defaultAction)
        } message: { v in
            Text(L10n.format("Delete the %@ build? Other quantizations of this model stay on disk.", v.label)).font(.app(.body))
        }
    }
}

// MARK: - Local Model Row

private struct LocalModelRow: View {
    let model: LocalModel
    @EnvironmentObject var downloads: DownloadManager
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var server: ServerManager
    @State private var confirmDelete = false
    /// Per-row, per-session: clicking the lock arms the trash for THIS row
    /// only, and a refresh re-locks it. The friction is worth one click; the
    /// old dead badge was not worth anything.
    @State private var unlocked = false
    @State private var card: ModelCardRequest?
    @State private var settings: ModelSettingsRequest?
    @State private var hasOverrides = false
    @State private var badge = SocketBadge(stone: nil, skull: false)
    @State private var confirmReplace: UpdateCheck?

    private var settingsRequest: ModelSettingsRequest {
        ModelSettingsRequest(path: model.path, title: ModelDisplayName.pretty(model.displayLabel))
    }

    /// nil for a bare folder that maps to no Hugging Face repo.
    private var cardRequest: ModelCardRequest? {
        ModelCard.repoId(localName: model.name).map {
            ModelCardRequest(repoId: $0, title: ModelDisplayName.pretty(model.displayLabel))
        }
    }

    private var useState: ModelUseState {
        ModelUseState.resolve(
            selected: appState.selectedModelPath == model.path,
            serverStatus: server.status
        )
    }

    /// Open Finder with the model selected. `path` is the directory for a
    /// safetensors checkpoint and the FILE for one GGUF quant, and
    /// `activateFileViewerSelecting` selects either — which is the behaviour
    /// you want: a quant row reveals its own file, not its repo folder.
    private func refreshOverrides() {
        let o = ModelSettingsFile.load().override(for: model.path)
        hasOverrides = o?.hasSettings ?? false
        guard model.isChatPickable, model.quantFile == nil else { return }
        badge = DrafterGems.badge(o ?? ModelOverride(), modelDir: model.path, hasMtpHead: model.hasMtpHead,
                                  options: appState.serverOptions)
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: model.path)])
    }

    /// The manual check's verdict, else the daily check's pending update.
    private var updateCheck: UpdateCheck? {
        if let check = downloads.updateChecks[model.id] { return check }
        guard let update = downloads.packUpdates[model.name] else { return nil }
        let drafter = downloads.packListings[model.name]?.keys.contains { $0.hasPrefix(DrafterGems.packFolder + "/") } ?? false
        let off = ModelSettingsFile.load().override(for: model.path)?.drafter == "off"
        return UpdateCheck(result: .update(update), repo: model.name, dir: model.path, selection: .chat(drafter: drafter && !off))
    }

    private func applyUpdate(_ check: UpdateCheck) {
        downloads.applyUpdate(check, for: model) { appState.refreshModels() }
    }

    private func performDelete() {
        downloads.deleteModel(model, unlocked: unlocked)
        appState.refreshModels()
    }

    var body: some View {
        HStack(spacing: 8) {
            Button { card = cardRequest } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    // The READABLE name. `displayLabel` (the repo id, plus a
                    // quant suffix so two quants of one GGUF repo are two
                    // distinguishable rows) survives as the subtext below —
                    Text(L10n.text(ModelDisplayName.pretty(model.displayLabel)))
                        .font(.app(.callout).weight(.medium))
                        .lineLimit(1)
                    // Drafter checkpoints are real, supported models — they
                    // just aren't loadable as a target on their own. Show a
                    // distinct badge instead of the red "unsupported" warning
                    // that the generic check would otherwise render.
                    // A folder that cannot load says so on the row itself. The
                    // alternative — hiding it — is how two junk folders sat in
                    // this library unnoticed while the server registered both.
                    if let defect = model.defect {
                        Text(L10n.text(defect.label))
                            .font(.app(.caption2).weight(.medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                            .help(L10n.text(defect.explanation))
                    }
                    if model.kind == .drafter {
                        Text("Drafter")
                            .font(.app(.caption2).weight(.medium))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.purple.opacity(0.15), in: Capsule())
                            .help("Speculative-decoding drafter — pairs with a Gemma 4 base model in Settings, not loadable on its own.")
                    }
                    if let stone = badge.stone {
                        HStack(spacing: 3) {
                            GemIcon(name: "gem-\(stone.rawValue).png")
                            Text(stone.badge)
                                .font(.app(.caption2).weight(.semibold))
                                .foregroundStyle(.green)
                            if badge.skull { GemIcon(name: "gem-skull.png") }
                        }
                        .padding(.leading, 2).padding(.trailing, 5).padding(.vertical, 1)
                        .background(Color.green.opacity(0.15), in: Capsule())
                        .help(badge.skull ? "\(stone.label), lossy acceptance (Typical / TokenV3)" : stone.label)
                    }
                }
                // The id itself, under the readable name.
                Text(L10n.text(model.displayLabel))
                    .font(.app(.caption2))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                // Metadata caption: params · quant · architecture · engine, so
                // the row actually tells the user what the model is — previously
                // it was just a name and a delete button.
                HStack(spacing: 6) {
                    // For a broken folder the architecture summary is noise —
                    // what it IS matters less than why it cannot load.
                    Text(L10n.text(model.defect?.explanation ?? model.metadataSummary))
                        .font(.app(.caption2))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    // Capability icons mirror the search rows.
                    if model.hasVision {
                        Image(systemName: "eye")
                            .font(.app(.caption2))
                            .foregroundStyle(.secondary)
                            .help("Vision (image input)")
                    }
                    if model.hasToolCalling {
                        Image(systemName: "wrench")
                            .font(.app(.caption2))
                            .foregroundStyle(.secondary)
                            .help("Tool calling")
                    }
                    // Only flag genuinely unsupported architectures. Drafters
                    // declare `gemma4_assistant` (not in supportedModelTypes)
                    // intentionally — the badge above already explains them.
                    if case .localCopy = downloads.updateChecks[model.id]?.result {
                        Text("Local copy")
                            .font(.app(.caption2).weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                            .help("Not on Hugging Face under this name, so there is nothing to update from.")
                    }
                    if model.kind != .drafter, !model.isSupportedArchitecture {
                        Text("Unsupported")
                            .font(.app(.caption2).weight(.medium))
                            .foregroundStyle(.red.opacity(0.8))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.red.opacity(0.12), in: Capsule())
                    }
                }
            }
            .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(cardRequest == nil)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(L10n.text(model.sizeFormatted))
                .font(.app(.callout).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)

            // Use + Delete. "Use" is the missing terminal action the browser
            // never had — before this, the only thing you could do with a model
            // you'd downloaded was throw it away. Once picked, the button is
            // replaced by an In-use badge rather than merely greyed out, so the
            // click produces visible feedback.
            HStack(spacing: 6) {
                if model.isChatPickable {
                    if useState == .idle {
                        UseModelButton(path: model.path, name: model.name)
                    } else {
                        ModelUseBadge(state: useState)
                    }
                } else if isDecisionModelType(model.modelType) {
                    UseDecisionModelButton(path: model.path, name: model.name)
                } else if let modality = MediaModality(modelType: model.modelType) {
                    // A media checkpoint is a real, loadable, servable model —
                    // it just is not a CHAT model, and until now that meant the
                    // only verb the browser offered for it was Delete. This
                    // does NOT go through `useModelAndAwaitReady`: that starts
                    // the server on the path as its primary chat model, which
                    // for a diffusion checkpoint means the text loader. It
                    // opens the pane that owns the model instead, and lets the
                    // pane load it the way it always has.
                    UseMediaModelButton(modality: modality, name: model.name, path: model.path)
                }
                if let check = updateCheck, case .update(let update) = check.result {
                    Button {
                        if update.replaces > 0 { confirmReplace = check } else { applyUpdate(check) }
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .foregroundStyle(.tint)
                            .frame(minWidth: 22, minHeight: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .font(.app(.callout))
                    .disabled(downloads.downloads[check.repo]?.status == .downloading)
                    .accessibilityLabel("Update model")
                    .help("Update from \(check.repo): \(update.files) file\(update.files == 1 ? "" : "s"), \(ByteCountFormatter.string(fromByteCount: update.bytes, countStyle: .file))")
                }
                if model.isChatPickable {
                    Button { settings = settingsRequest } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(hasOverrides ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            .frame(minWidth: 22, minHeight: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .font(.app(.callout))
                    .accessibilityLabel("Model settings")
                    .help(hasOverrides ? "Model settings (this model has its own context / KV settings)" : "Model settings")
                }
                if model.isDownloading {
                    // The trash's slot: deleting files under a live transfer
                    // breaks it, so the row offers the transfer's own Cancel.
                    if let live = ModelRowActions.transfer(for: model, in: downloads.downloads) {
                        ProgressView(value: max(0, min(1, live.state.progress)))
                            .progressViewStyle(.linear)
                            .frame(width: 60)
                            .help(live.state.statusText)
                        Text(verbatim: live.state.percentFormatted)
                            .font(.app(.caption).monospacedDigit())
                            .foregroundStyle(.secondary)
                        Button { downloads.cancel(live.repoId) } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 22, minHeight: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .font(.app(.callout))
                        .accessibilityLabel("Cancel download")
                        .help("Cancel download")
                    } else {
                        ProgressView().controlSize(.small)
                    }
                } else if ModelRowActions.showsLock(model, unlocked: unlocked) {
                    // Locked, not read-only. This slot used to hold an `Image`
                    // of an external-drive/cloud glyph nobody could read, which
                    // did nothing when clicked. It is a Button now, and clicking
                    // it is how you get the trash. (The old symbol name is
                    // deliberately not spelled here — a source scan in
                    // `ModelRowActionsTests` asserts it is gone from this file.)
                    Button { unlocked = true } label: {
                        Image(systemName: "lock")
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 22, minHeight: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .font(.app(.callout))
                    .accessibilityLabel("Unlock deletion")
                    .help(ModelRowActions.lockHelp(model))
                } else {
                    Button {
                        confirmDelete = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red.opacity(0.7))
                            .frame(minWidth: 22, minHeight: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .font(.app(.callout))
                    .accessibilityLabel(L10n.text(model.defect != nil
                                        ? "Delete this broken folder"
                                        : (model.quantFile != nil ? "Delete this quant" : "Delete model")))
                    .help(model.defect != nil
                          ? "Delete this broken folder"
                          : (model.quantFile != nil ? "Delete this quant" : "Delete model"))
                }

                // Reveal in Finder — rightmost, on EVERY row. Six other panes
                // already had this control; the one pane that is entirely about
                // files on disk did not, so a model you did not recognise could
                // not be located from the app that listed it.
                Button(action: revealInFinder) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 22, minHeight: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .font(.app(.callout))
                .accessibilityLabel("Reveal in Finder")
                .help(ModelRowActions.revealHelp(model))
            }
            .frame(width: 172, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        // The alert lives on the ROW so both the trash and the context menu
        // raise the same confirmation — two delete paths with two dialogs is
        // two chances to word the consequence differently.
        .alert(model.quantFile != nil ? "Delete Quant" : "Delete Model", isPresented: $confirmDelete) {
            Button(role: .cancel) {} label: { Text("Cancel")
                .font(.app(.body)) }
            Button(role: .destructive) { performDelete() } label: { Text("Delete")
                .font(.app(.body)) }
                .keyboardShortcut(.defaultAction)
        } message: {
            Text(ModelRowActions.deleteMessage(model)).font(.app(.body))
        }
        .alert("Replace Files?", isPresented: Binding(get: { confirmReplace != nil }, set: { if !$0 { confirmReplace = nil } }), presenting: confirmReplace) { check in
            Button("Cancel", role: .cancel) {}
            Button("Replace", role: .destructive) { applyUpdate(check) }
                .keyboardShortcut(.defaultAction)
        } message: { check in
            if case .update(let u) = check.result {
                Text(L10n.format(u.replaces == 1 ? "%lld file differs from Hugging Face and will be replaced." : "%lld files differ from Hugging Face and will be replaced.", Int64(u.replaces)))
            }
        }
        .sheet(item: $card) { ModelDetailSheet(request: $0) }
        .sheet(item: $settings, onDismiss: refreshOverrides) { ModelSettingsSheet(request: $0).environmentObject(appState).environmentObject(server).environmentObject(downloads) }
        .onAppear(perform: refreshOverrides)
        .contextMenu {
            if model.isChatPickable, useState == .idle {
                Button {
                    appState.selectedModelPath = model.path
                } label: { Text("Use This Model")
                    .font(.app(.body)) }
            }
            if cardRequest != nil {
                Button { card = cardRequest } label: { Text("Model Details\u{2026}")
                    .font(.app(.body)) }
            }
            if model.isChatPickable {
                Button { settings = settingsRequest } label: { Text("Model Settings\u{2026}")
                    .font(.app(.body)) }
            }
            Button(action: revealInFinder, label: { Text("Show in Finder")
                .font(.app(.body)) })
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.path, forType: .string)
            } label: { Text("Copy Path")
                .font(.app(.body)) }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.displayLabel, forType: .string)
            } label: { Text("Copy Model ID")
                .font(.app(.body)) }
            Divider()
            if let live = ModelRowActions.transfer(for: model, in: downloads.downloads) {
                Button { downloads.cancel(live.repoId) } label: { Text("Cancel Download")
                    .font(.app(.body)) }
            } else if ModelRowActions.showsTrash(model, unlocked: unlocked) {
                Button(role: .destructive) { confirmDelete = true } label: { Text("Delete\u{2026}")
                    .font(.app(.body)) }
            } else if !model.isDownloading {
                // Same two-step as the lock button: the menu never deletes
                // another app's model on one click.
                Button { unlocked = true } label: { Text("Unlock to Delete")
                    .font(.app(.body)) }
            }
        }
    }
}

// MARK: - Active Download Row

private struct GemIcon: View {
    let name: String

    var body: some View {
        if let image = BundledAsset.image(name) {
            Image(nsImage: image).resizable().frame(width: 16, height: 16)
        }
    }
}

private struct ActiveDownloadRow: View {
    let repoId: String
    let state: DownloadManager.DownloadState
    let showModels: () -> Void
    @EnvironmentObject var downloads: DownloadManager
    @EnvironmentObject var appState: AppState

    private var modelName: String {
        repoId.components(separatedBy: "/").last ?? repoId
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: modelName)
                    .font(.app(.callout).weight(.medium))
                    .textSelection(.enabled)
                Text(verbatim: repoId)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if state.status == .downloading, !state.statusText.isEmpty {
                    Text(verbatim: state.statusText)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .help(state.statusText)
                } else if state.status == .failed {
                    Text(verbatim: state.error ?? L10n.text("Download failed"))
                        .font(.app(.caption))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if state.status == .downloading {
                VStack(alignment: .trailing, spacing: 5) {
                    ProgressView(value: state.progress)
                        .frame(width: 120)
                        .accessibilityLabel(L10n.format("Download %@", modelName))
                    Text("\(state.percentFormatted) \(state.speedFormatted)")
                        .font(.app(.caption).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button("Cancel") {
                        downloads.cancel(repoId)
                        appState.refreshModels()
                    }
                    .controlSize(.small)
                    .accessibilityLabel(L10n.format("Cancel download of %@", modelName))
                }
            } else {
                VStack(alignment: .trailing, spacing: 6) {
                    if state.status == .completed {
                        Label("Downloaded", systemImage: "checkmark.circle")
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                        Button("Show in My Models", action: showModels)
                    } else if downloads.canRetry(repoId: repoId) {
                        Button("Retry") {
                            downloads.retry(repoId: repoId) {
                                appState.refreshModels()
                                appState.server.rescanModels()
                            }
                        }
                        .help("Retry this download, keeping files already downloaded.")
                    } else {
                        Text("Retry from the model catalog.")
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                    Button("Dismiss") { downloads.dismissDownload(repoId: repoId) }
                        .help("Remove this entry from the list. Downloaded files stay on disk.")
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
    }
}
