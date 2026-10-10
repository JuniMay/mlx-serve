import SwiftUI
import AppKit

/// Music keeps style and lyrics beside the result, with model-specific sources and options.
struct MusicInteractionControls: View {
    @EnvironmentObject var service: MusicGenService
    @EnvironmentObject var server: ServerManager
    @EnvironmentObject var downloads: DownloadManager
    @EnvironmentObject var appState: AppState

    @Binding var prompt: String
    @State private var lyrics: String = ""
    @State private var model: MusicModelPreset = .acestepXLTurbo8bit
    /// Selected network model's routing id (`<model>@<peer>`); nil = local.
    @State private var lanModel: String? = nil
    @State private var durationSeconds: Double = 60
    @State private var vocalLanguage: String = "en"
    @State private var bpm: Int? = nil
    @State private var keyscale: String = ""
    @State private var timesignature: String = ""
    @State private var seed: Int = -1
    @State private var steps: Int? = nil
    @State private var instrumental: Bool = false
    @StateObject private var library = MusicPromptLibrary()
    @State private var showSaveStyle = false
    @State private var showSaveLyrics = false
    @State private var saveTitle = ""
    @State private var rewriteKind: MusicPromptRewriter.Kind? = nil

    @State private var showRAMWarning: Bool = false
    @State private var ramWarningMessage: String = ""
    @State private var pendingRequest: MusicGenRequest? = nil
    @State private var pendingSubmission: MediaInteractionSubmission? = nil
    // The app-wide singleton, not a per-view instance: this view unmounts on
    // navigation (see the tab-persistence note on AudioGenView), and a
    // private player left playing when that happens is a leaked NSSound with
    // no reachable Stop button — see .onDisappear below.
    @ObservedObject private var clipPlayer = AudioClipPlayer.shared
    // Kept across preset switches like the video pane's first frame; the
    // SERVICE gates the field on `supportsReferenceAudio`.
    @State private var refAudioURL: URL? = nil
    @State private var refError: String? = nil
    @State private var isRefDropTargeted: Bool = false
    @State private var refBusy: Bool = false
    // Source-audio tasks (ACE-Step only). The SERVICE gates every field on
    // `supportsSourceAudio` + the task, so a clip left behind by a model
    // switch never reaches a server that refuses it.
    @State private var task: MusicTask = .text2music
    @State private var srcAudioURL: URL? = nil
    /// The clip's length, read from its header once when it arrives — the file
    /// runs to ~100 MB, so this is never re-read while the pane redraws.
    @State private var srcSeconds: Double? = nil
    @State private var srcError: String? = nil
    @State private var isSrcDropTargeted: Bool = false
    @State private var srcBusy: Bool = false
    @State private var coverStrength: Double = 1.0
    @State private var coverNoiseStrength: Double = 0.0
    @State private var trackClasses: [String] = []
    /// Keep the model resident after generating (default off → unload).
    @State private var keepResident: Bool = false
    /// Suppresses persistence while saved parameters are restored.
    @State private var hydrating: Bool = false
    @State private var didHydrate: Bool = false

    var body: some View {
        readyView
        .onChange(of: showRAMWarning) { _, showing in
            if !showing { discardPendingSubmission() }
        }
        .onDisappear { discardPendingSubmission() }
        .onAppear {
            if !didHydrate {
                hydrating = true
                hydrate()
                didHydrate = true
                DispatchQueue.main.async { hydrating = false }
            }
            // Freshen the network-model list so LAN entries are current in
            // the picker (discovery lands seconds after the server boots).
            if server.status == .running { Task { await server.refreshModels() } }
        }
        .onDisappear { stopPlayback() }
        .onChange(of: appState.mediaModelSelection) { _, request in
            guard let request, let selection = request.applying(to: stickySnapshot) else { return }
            model = selection.resolvedModel(models: server.allModels)
            lanModel = LanPick.lanId(selection.modelId)
        }
        .onChange(of: model) { _, m in
            guard !hydrating else { return }
            durationSeconds = min(max(durationSeconds, m.durationRange.lowerBound), m.durationRange.upperBound)
        }
        // Persist settings and draft inputs together across workspace changes.
        .onChange(of: stickySnapshot) { _, _ in guard !hydrating else { return }; persist() }
        .onChange(of: service.phase) { _, phase in
            // A new generation stops whatever is still playing.
            if case .running = phase { stopPlayback() }
            if case .completed(let path) = phase { play(path) }
        }
        .alert("Save style prompt", isPresented: $showSaveStyle) {
            TextField("Name", text: $saveTitle)
            Button { library.saveStyle(title: saveTitle, body: prompt) } label: { Text("Save")
                .font(.app(.body)) }
                .keyboardShortcut(.defaultAction)
            Button(role: .cancel) {} label: { Text("Cancel")
                .font(.app(.body)) }
        } message: {
            Text("Give this style a name to reuse it from the Templates menu.").font(.app(.body))
        }
        .alert("Save lyrics", isPresented: $showSaveLyrics) {
            TextField("Name", text: $saveTitle)
            Button { library.saveLyrics(title: saveTitle, body: lyrics) } label: { Text("Save")
                .font(.app(.body)) }
                .keyboardShortcut(.defaultAction)
            Button(role: .cancel) {} label: { Text("Cancel")
                .font(.app(.body)) }
        } message: {
            Text("Give these lyrics a name to reuse them from the Templates menu.").font(.app(.body))
        }
        .sheet(item: $rewriteKind) { kind in
            PromptRewriteSheet(
                title: kind == .style ? "Rewrite style prompt" : "Rewrite lyrics",
                request: { _ in MusicPromptRewriter.request(
                    kind, text: kind == .style ? prompt : lyrics, family: model.family,
                    other: kind == .style ? lyrics : prompt,
                    instrumental: instrumental, language: vocalLanguage) },
                onApply: { if kind == .style { prompt = $0 } else { lyrics = $0 } })
            .environmentObject(appState)
        }
    }

    private func play(_ path: String) { clipPlayer.play(path) }
    private func stopPlayback() { clipPlayer.stop() }

    private var readyView: some View {
        MediaInteractionControls(
            placeholder: "Describe the genre, mood and instruments…", notice: generationBlockReason,
            hasAttachments: model.supportsSourceAudio || model.supportsReferenceAudio,
            attachmentCount: (sourceTask && srcAudioURL != nil ? 1 : 0)
                + (model.supportsReferenceAudio && refAudioURL != nil ? 1 : 0),
            isRunning: service.isRunning, canSubmit: generationBlockReason == nil,
            submit: tryGenerate,
            attachments: {
                if model.supportsSourceAudio { modeSection }
                if sourceTask { sourceSection }
                if model.supportsReferenceAudio { referenceSection }
            }, parameters: {
                modelDownload
                lyricsSection
                keepResidentToggle
                if sourceTask { sourceControls } else { durationSection }
                advancedBody
                AudioHistoryShelf(
                    title: "History", paths: service.recent,
                    playingPath: clipPlayer.playingPath,
                    onPlay: { play($0) }, onStop: { stopPlayback() })
                outputFolderLink
            }, promptActions: { promptActions })
        .alert("Model exceeds your Mac's RAM", isPresented: $showRAMWarning) {
            Button(role: .cancel) { discardPendingSubmission() } label: { Text("Cancel")
                .font(.app(.body)) }
            Button(role: .destructive) {
                guard let req = pendingRequest, let submission = pendingSubmission else { return }
                pendingRequest = nil
                pendingSubmission = nil
                startGeneration(req, submission: submission)
            } label: { Text("Generate Anyway")
                .font(.app(.body)) }
        } message: {
            Text(L10n.text(ramWarningMessage)).font(.app(.body))
        }
    }

    // MARK: - Sections

    private var promptActions: some View {
        Menu {
            Button("Enhance…") { rewriteKind = .style }.disabled(prompt.isBlank)
            styleExamplesMenu
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Style actions")
        .help("Style actions")
    }

    private var lyricsSection: some View {
        VStack(alignment: .leading, spacing: AppLayout.labelSpacing) {
            HStack(spacing: AppLayout.rowSpacing) {
                Text("Lyrics").font(.app(.body).weight(.medium))
                Toggle("Instrumental", isOn: $instrumental)
                    .controlSize(.small)
                    .help(L10n.text(model.family == .minimaxMusic3
                          ? "Lyrics are not used. This model has no dedicated instrumental switch, so it is requested in text and may still add wordless vocals."
                          : "Generate music with no singing. The lyrics below are not used."))
                Spacer()
                Menu {
                    Button("Enhance…") { rewriteKind = .lyrics }
                        .disabled(lyrics.isBlank || instrumental)
                    lyricsExamplesMenu
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Lyrics actions")
                .help("Lyrics actions")
            }
            if instrumental {
                if model.family == .minimaxMusic3 {
                    Text("This model may still add wordless vocals.")
                        .font(.app(.caption)).foregroundStyle(.secondary)
                }
            } else {
                TextField("Add lyrics…", text: $lyrics, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(6...12)
                    .accessibilityLabel("Lyrics")
                    .help(model.requiresLyrics
                          ? L10n.format("This model sings your lyrics. Put section tags on their own lines: %@", MusicOptions.sectionTagHint)
                          : L10n.format("Leave empty or choose Instrumental for no vocals. Put section tags on their own lines: %@", MusicOptions.sectionTagHint))

            }
        }
    }

    /// The task actually in force: the mode control only exists on models
    /// with source-audio tasks, so elsewhere the sticky value is inert.
    private var sourceTask: Bool { model.supportsSourceAudio && task.needsSource }

    /// What the track is made from. Cover keeps the source's melody and
    /// structure under a new caption; Vocal to BGM arranges around a vocal
    /// stem. Both take their length from the clip, so Duration disappears.
    private var modeSection: some View {
        VStack(alignment: .leading, spacing: AppLayout.labelSpacing) {
            Picker("Mode", selection: $task) {
                // Name a missing tokenizer before the user selects Cover.
                ForEach(MusicTask.allCases, id: \.self) { t in
                    Text(L10n.text(CoverWeightsFetch.modeLabel(t, decision: t == .cover ? coverWeights : .ready))).tag(t)
                }
            }
            .labelsHidden().pickerStyle(.menu)
            Text(L10n.text(
                 task == .cover
                 ? "Re-sings an existing track in the style you describe: melody and structure stay, the caption and lyrics decide the rest."
                 : (task == .complete
                    ? "Builds an arrangement around a vocal stem (or any part): pick the instruments to add, or leave them all off to let the model decide."
                    : "A new track from the style prompt and lyrics.")
))
                .font(.app(.caption2)).foregroundStyle(.secondary)
            coverWeightsNotice
        }
    }

    /// Whether Cover can run against the pack on THIS Mac. Purely local — the
    /// pack dir resolves across every served root, so an LM Studio or custom
    /// folder answers too, and no generation has to be set up to find out.
    private var coverWeights: CoverWeightsFetch.Decision {
        CoverWeightsFetch.decide(
            task: .cover,
            modelSupportsSourceAudio: model.supportsSourceAudio,
            isRemote: lanModel != nil,
            packDir: lanModel == nil ? ServerManager.resolveModelDir(repo: model.repo) : nil,
            fetching: downloads.isFetchingPackFile(repoId: model.repo))
    }

    /// Says what is missing, by name, and offers the ONE file — never the 5 GB
    /// pack again. The engine stats for the tokenizer on every cover request
    /// (`acestep.Engine.fsqAvailable`), so a resident model picks the file up
    /// as soon as it lands: no reload, no app restart, nothing to warn about.
    @ViewBuilder
    private var coverWeightsNotice: some View {
        if task == .cover, let text = CoverWeightsFetch.notice(coverWeights) {
            VStack(alignment: .leading, spacing: AppLayout.labelSpacing) {
                Text(text).font(.app(.caption2)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                switch coverWeights {
                case .fetch:
                    Button {
                        downloads.startPackFile(repoId: model.repo,
                                                fileName: CoverWeightsFetch.fileName) {
                            appState.refreshModels()
                        }
                    } label: {
                        Label("Download \(CoverWeightsFetch.fileName) (\(CoverWeightsFetch.approxMB) MB)",
                              systemImage: "arrow.down.circle")
                            .font(.app(.caption))
                    }
                    .buttonStyle(.bordered)
                case .downloading:
                    HStack(spacing: 8) {
                        ProgressView(value: downloads.downloads[model.repo]?.progress ?? 0)
                            .progressViewStyle(.linear)
                        Text(downloads.downloads[model.repo]?.percentFormatted ?? "")
                            .font(.app(.caption2).monospacedDigit()).foregroundStyle(.secondary)
                        // Cancels ONLY this single-file fetch — a full pack
                        // download for the same repo is never touched.
                        Button { downloads.cancelPackFile(repoId: model.repo) } label: { Text("Cancel")
                            .font(.app(.body)) }
                            .buttonStyle(.borderless).font(.app(.caption))
                    }
                default:
                    EmptyView()
                }
            }
            .padding(8)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    /// The source clip for Cover / Vocal to BGM: full length (up to 10 minutes),
    /// because the track is made exactly as long as it. Same pick / drop /
    /// preview / clear shape as the reference well below.
    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: AppLayout.labelSpacing) {
            HStack {
                Text(L10n.text(task == .cover ? "Source track" : "Source stem")).font(.app(.subheadline).weight(.semibold))
                Spacer()
            }
            if let url = srcAudioURL {
                MediaDropWellFilled(isTargeted: isSrcDropTargeted) {
                    VStack(alignment: .leading, spacing: AppLayout.labelSpacing) {
                        HStack(spacing: 8) {
                            Image(systemName: "waveform.circle.fill").foregroundStyle(.blue)
                            Text(url.lastPathComponent)
                                .font(.app(.caption)).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            if clipPlayer.playingPath == url.path {
                                Button { clipPlayer.stop() } label: { Image(systemName: "stop.circle.fill") }
                                    .buttonStyle(.borderless).help("Stop preview")
                            } else {
                                Button { clipPlayer.play(url.path) } label: { Image(systemName: "play.circle") }
                                    .buttonStyle(.borderless).help("Preview source")
                            }
                            Button { clearSource() } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.borderless).foregroundStyle(.secondary).help("Clear source")
                        }
                        // A header we cannot read leaves the pane with nothing
                        // to say about length, which is the one thing a source
                        // task decides for you.
                        Text(srcSeconds.map { "The new track will be \(SourceTrackLength.spoken(seconds: $0)) long." }
                             ?? "The new track will be exactly as long as this clip.")
                            .font(.app(.caption2)).foregroundStyle(.secondary)
                    }
                }
            } else if srcBusy {
                MediaDropWellFilled(isTargeted: isSrcDropTargeted) { converting }
            } else {
                MediaDropWell(title: "Choose file…",
                              systemImage: "waveform.badge.plus",
                              caption: "10 seconds to 10 minutes. The new track will have the same length.",
                              isTargeted: isSrcDropTargeted,
                              action: chooseSourceFile)
            }
            if let err = srcError {
                Text(err).font(.app(.caption2)).foregroundStyle(.orange)
            }
        }
        .mediaDrop(.audio, isTargeted: $isSrcDropTargeted) { urls in
            if let url = urls.first { acceptSource(url) }
        }
    }

    private var sourceControls: some View {
        VStack(alignment: .leading, spacing: AppLayout.rowSpacing) {
            if task == .cover {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Cover strength").font(.app(.rowTitle))
                        Spacer()
                        Text(String(format: "%.2f", coverStrength)).font(.app(.caption).monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Slider(value: $coverStrength, in: 0...1, step: 0.05)
                    Text("How many of the steps follow the source. 1 keeps it all the way; lower lets the caption take over for the last steps.")
                        .font(.app(.caption2)).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Noise strength").font(.app(.rowTitle))
                        Spacer()
                        Text(String(format: "%.2f", coverNoiseStrength)).font(.app(.caption).monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Slider(value: $coverNoiseStrength, in: 0...1, step: 0.05)
                    Text("0 starts from pure noise (the default). Higher starts closer to the original audio, so more of it comes through.")
                        .font(.app(.caption2)).foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            }
            if task == .complete {
                Text("Add").font(.app(.caption)).padding(.top, 6)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 4) {
                    ForEach(MusicTask.trackClasses, id: \.self) { name in
                        Toggle(L10n.text(name.replacingOccurrences(of: "_", with: " ")),
                               isOn: Binding(get: { trackClasses.contains(name) },
                                             set: { on in
                                                 if on { if !trackClasses.contains(name) { trackClasses.append(name) } }
                                                 else { trackClasses.removeAll { $0 == name } }
                                             }))
                            .font(.app(.caption))
                    }
                }
            }
        }
    }

    private func chooseSourceFile() {
        srcError = nil
        let panel = OpenPanel.make()
        panel.allowedContentTypes = [.audio, .wav, .mp3, .mpeg4Audio, .aiff]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard AppActivation.runModal(panel) == .OK, let url = panel.url else { return }
        acceptSource(url)
    }

    private func acceptSource(_ url: URL) {
        guard !srcBusy else { return }
        srcError = nil
        srcBusy = true
        transcode(url, maxSeconds: 600) { result in
            srcBusy = false
            switch result {
            case .success(let wav):
                srcAudioURL = wav
                srcSeconds = SourceTrackLength.seconds(ofWavAt: wav)
            case .failure(let err): srcError = err.localizedDescription
            }
        }
    }

    /// Decode + resample + write off the main thread: a 10-minute clip took
    /// seconds, and the drop animation sat frozen for all of them.
    private func transcode(_ url: URL, maxSeconds: Double, done: @escaping @MainActor (Result<URL, Error>) -> Void) {
        Task.detached(priority: .userInitiated) {
            let result = Result { try AudioReference.referenceWav(fromFile: url, maxSeconds: maxSeconds) }
            await done(result)
        }
    }

    private func clearSource() {
        if let url = srcAudioURL { try? FileManager.default.removeItem(at: url) }
        srcAudioURL = nil
        srcSeconds = nil
    }

    /// ACE-Step's timbre slot (#259): a clip whose style the track follows.
    /// Same pick / drop / preview / clear shape as the Audio pane's voice
    /// reference, minus recording — a mic clip is no style reference.
    private var referenceSection: some View {
        VStack(alignment: .leading, spacing: AppLayout.labelSpacing) {
            HStack {
                Text("Reference audio (optional)").font(.app(.headline).weight(.semibold))
                Spacer()
            }
            if let url = refAudioURL {
                MediaDropWellFilled(isTargeted: isRefDropTargeted) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.circle.fill").foregroundStyle(.blue)
                        Text(url.lastPathComponent)
                            .font(.app(.caption)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if clipPlayer.playingPath == url.path {
                            Button { clipPlayer.stop() } label: { Image(systemName: "stop.circle.fill") }
                                .buttonStyle(.borderless).help("Stop preview")
                        } else {
                            Button { clipPlayer.play(url.path) } label: { Image(systemName: "play.circle") }
                                .buttonStyle(.borderless).help("Preview reference")
                        }
                        Button { clearReference() } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary).help("Clear reference")
                    }
                }
            } else if refBusy {
                MediaDropWellFilled(isTargeted: isRefDropTargeted) { converting }
            } else {
                MediaDropWell(title: "Choose file…",
                              systemImage: "music.note",
                              caption: "A light touch: the model takes the overall feel and timbre from up to 30 seconds of the clip, it does not recreate the song.",
                              isTargeted: isRefDropTargeted,
                              action: chooseReferenceFile)
            }
            if let err = refError {
                Text(err).font(.app(.caption2)).foregroundStyle(.orange)
            }
        }
        .mediaDrop(.audio, isTargeted: $isRefDropTargeted) { urls in
            if let url = urls.first { acceptReference(url) }
        }
    }

    private var converting: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Converting…").font(.app(.caption)).foregroundStyle(.secondary)
        }
    }

    private func chooseReferenceFile() {
        refError = nil
        let panel = OpenPanel.make()
        panel.allowedContentTypes = [.audio, .wav, .mp3, .mpeg4Audio, .aiff]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard AppActivation.runModal(panel) == .OK, let url = panel.url else { return }
        acceptReference(url)
    }

    /// Picked or dropped, a file becomes the reference the same way: a 48 kHz
    /// stereo transcode, or a visible reason instead of a clip that silently
    /// doesn't attach.
    private func acceptReference(_ url: URL) {
        guard !refBusy else { return }
        refError = nil
        refBusy = true
        transcode(url, maxSeconds: 30) { result in
            refBusy = false
            switch result {
            case .success(let wav): refAudioURL = wav
            case .failure(let err): refError = err.localizedDescription
            }
        }
    }

    private func clearReference() {
        if let url = refAudioURL { try? FileManager.default.removeItem(at: url) }
        refAudioURL = nil
    }

    private var modelDownload: some View {
        Group {
            if lanModel == nil && !downloads.bundleReady(model.bundle) {
                if model.isLocalOnly { convertHint } else { BundleDownloadBar(bundle: model.bundle) }
            }
        }
    }

    private var keepResidentToggle: some View {
        Toggle(isOn: $keepResident) {
            Text("Keep model loaded after generating")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.app(.body))
        .help("On: the model stays resident so the next generation is instant. Off (default): it's unloaded to free GPU memory.")
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            // The box belongs NEXT to the label it edits. Right-justifying it
            // against the pane margin puts a number and its name at opposite
            // ends of a wide row with nothing between them to tie the two.
            HStack(spacing: 6) {
                Text("Duration").font(.app(.headline).weight(.semibold))
                // Typed entry beside the slider: the slider steps by 5 and
                // landing on 95 s by dragging is not a thing anyone should do.
                NumberField(range: durationRangeInt,
                            value: Binding(get: { Int(durationSeconds) },
                                           set: { durationSeconds = Double($0) }),
                            width: 52,
                            help: "Seconds. \(durationRangeInt.lowerBound)–\(durationRangeInt.upperBound) for this model.")
                Text("sec · \(formattedDuration)").font(.app(.caption2)).foregroundStyle(.secondary)
                Spacer()
            }
            Slider(value: $durationSeconds, in: model.durationRange, step: 5)
                .accessibilityLabel("Duration")
            if model.family == .minimaxMusic3 {
                Text("An upper bound — the model may end the song earlier.")
                    .font(.app(.caption2)).foregroundStyle(.secondary)
            }
        }
    }

    /// Label over control, pinned to the cell's leading edge.
    private func advancedCell<C: View>(_ label: String, @ViewBuilder control: () -> C) -> some View {
        // No `maxWidth: .infinity`: that stretched every cell across its whole
        // grid column, which reads as an arbitrary gap between two controls.
        // The cell hugs its content and the grid sets it at the leading edge.
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.text(label)).font(.app(.caption))
            control()
        }
    }

    /// The model's server-valid duration bounds as integers, for the typed box.
    private var durationRangeInt: ClosedRange<Int> {
        Int(model.durationRange.lowerBound)...Int(model.durationRange.upperBound)
    }

    /// The shared seed component (dice + forgiving paste). The pane's old bare
    /// TextField parsed with `Int(...)`, so a pasted "Seed: 3,847,592" fell
    /// through to -1 and rolled a RANDOM seed — the user believed they had
    /// reproduced a track and had not.
    private var seedControl: some View {
        SeedField(label: "Seed", placeholder: "Random",
                  range: -1...Int(UInt32.max), value: $seed)
    }

    private var formattedDuration: String {
        let s = Int(durationSeconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private var advancedBody: some View {
        VStack(alignment: .leading, spacing: AppLayout.rowSpacing) {
            // Refinement passes. Music 3 only: ACE-Step Turbo is distillation-
            // fixed at 8 and the server ignores the field, so a control there
            // would visibly do nothing.
            if model.supportsSteps {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Quality passes").font(.app(.caption))
                        NumberField(range: model.stepsRange,
                                    value: Binding(get: { steps ?? model.fixedSteps },
                                                   set: { steps = $0 }),
                                    width: 52,
                                    help: "Flow-matching steps, \(model.stepsRange.lowerBound)–\(model.stepsRange.upperBound). Default \(model.fixedSteps).")
                        Spacer()
                    }
                    Slider(value: Binding(get: { Double(steps ?? model.fixedSteps) },
                                          set: { steps = Int($0.rounded()) }),
                           in: Double(model.stepsRange.lowerBound)...Double(model.stepsRange.upperBound),
                           step: 1)
                    Text("More passes means more detail and a slower render.")
                        .font(.app(.caption2)).foregroundStyle(.secondary)
                }
            }
            // Dropdowns only — every choice is a value the server accepts,
            // "Auto" leaves the decision to the model (field omitted). The
            // whole musical-metadata knob set is ACE-Step's; Music 3 has no
            // equivalent (the server names each field a 400), so the controls
            // disappear with it — and `requestBody` gates the FIELDS too.
            // Tempo and key are supported by BOTH engines — conditioning fields
            // on ACE-Step, caption text on Music 3 — so they sit OUTSIDE the
            // acestep-only block. Hiding them on Music 3 read as "this model
            // cannot do tempo", which its own model card contradicts.
            // Controls wrap within the inspector's available width.
            FlowLayout(spacing: 14, rowSpacing: 10) {
                if model.supportsTempoAndKey {
                    advancedCell("Tempo (BPM)") {
                        // Typed, because the server takes 30–300 and the ten
                        // anchors in the menu could not express 92. The menu stays
                        // as a shortcut for people who think in genres, not numbers.
                        HStack(spacing: 4) {
                            OptionalNumberField(range: MusicOptions.bpmRange, value: $bpm,
                                                placeholder: "Auto", width: 64,
                                                help: "\(MusicOptions.bpmRange.lowerBound)–\(MusicOptions.bpmRange.upperBound), or leave empty to let the model decide.")
                            Menu {
                                Button { bpm = nil } label: { Text("Auto")
                                    .font(.app(.body)) }
                                ForEach(MusicOptions.bpms, id: \.bpm) { opt in
                                    Button { bpm = opt.bpm } label: { Text(L10n.text(opt.label))
                                        .font(.app(.body)) }
                                }
                            } label: {
                                Label("Common tempos", systemImage: "metronome")
                                    .labelStyle(.iconOnly)
                            }
                            .modifier(PaneChipMenu())
                            .help("Common tempos")
                        }
                    }
                    advancedCell("Key") {
                        Picker("Key", selection: $keyscale) {
                            Text("Auto").font(.app(.body)).tag("")
                            ForEach(MusicOptions.keyscales, id: \.self) { key in
                                Text(MusicOptions.keyLabel(key)).font(.app(.body)).tag(key)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).fixedSize()
                    }
                }
                if model.supportsMusicalMeta {
                    advancedCell("Vocal language") {
                        Picker("Vocal language", selection: $vocalLanguage) {
                            ForEach(MusicOptions.languages, id: \.code) { opt in
                                Text(L10n.text(opt.label)).font(.app(.body)).tag(opt.code)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).fixedSize()
                    }
                    advancedCell("Time signature") {
                        Picker("Time signature", selection: $timesignature) {
                            Text("Auto").font(.app(.body)).tag("")
                            ForEach(MusicOptions.timeSignatures, id: \.value) { opt in
                                Text(L10n.text(opt.label)).font(.app(.body)).tag(opt.value)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).fixedSize()
                    }
                }
                seedControl
            }
            if model.supportsTempoAndKey && model.family == .minimaxMusic3 {
                Text("Tempo and key are written into the style prompt for this model — it has no separate fields for them.")
                    .font(.app(.caption2)).foregroundStyle(.secondary)
            }
            Text("Same seed + prompt reproduces the track.")
                .font(.app(.caption2)).foregroundStyle(.secondary)
        }
    }

    private var generationBlockReason: String? {
        guard !service.isRunning else { return nil }
        if lanModel == nil && !downloads.bundleReady(model.bundle) {
            return model.isLocalOnly
                ? "Install the selected model to generate music."
                : "Download the selected model to generate music."
        }
        if prompt.isBlank { return "Describe the music you want to make." }
        if !MusicGenRequest.lyricsSatisfied(model: model, lyrics: lyrics, instrumental: instrumental) {
            return "Add lyrics or choose Instrumental."
        }
        return sourceTask && srcAudioURL == nil ? "Attach source audio with the plus button." : nil
    }

    private var convertHint: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Weights not found", systemImage: "wrench.and.screwdriver")
                .font(.app(.caption).weight(.semibold)).foregroundStyle(.secondary)
            Text("\(model.name) has no download yet — convert the weights on-device with the matching script in the repo (see its README). They install to ~/.mlx-serve/models/local/.")
                .font(.app(.caption2)).foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
    }

    private var outputFolderLink: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting(
                [URL(fileURLWithPath: MediaStorage.musicRoot)])
        } label: {
            Label("Open output folder in Finder", systemImage: "folder")
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Sticky settings

    private func hydrate() {
        let s = MusicGenSettings.load()
        model = s.resolvedModel(models: server.allModels)
        lanModel = LanPick.lanId(s.modelId)
        durationSeconds = Double(s.durationSeconds)
        vocalLanguage = s.vocalLanguage
        keepResident = s.keepResident
        bpm = s.bpm
        keyscale = s.keyscale
        timesignature = s.timesignature
        seed = s.seed
        steps = s.steps
        instrumental = s.instrumental
        lyrics = s.lyrics
        refAudioURL = s.refAudioPath.flatMap { FileManager.default.fileExists(atPath: $0) ? URL(fileURLWithPath: $0) : nil }
        task = s.task
        srcAudioURL = s.srcAudioPath.flatMap { FileManager.default.fileExists(atPath: $0) ? URL(fileURLWithPath: $0) : nil }
        srcSeconds = srcAudioURL.flatMap { SourceTrackLength.seconds(ofWavAt: $0) }
        coverStrength = s.coverStrength
        coverNoiseStrength = s.coverNoiseStrength
        trackClasses = s.trackClasses
    }

    /// Every sticky field, as the blob it would persist to — `Equatable`, so
    /// one `onChange` covers all of them.
    private var stickySnapshot: MusicGenSettings {
        var s = MusicGenSettings()
        s.modelId = LanPick.persisted(lanModel: lanModel, presetId: model.id)
        s.durationSeconds = Int(durationSeconds)
        s.vocalLanguage = vocalLanguage
        s.keepResident = keepResident
        s.bpm = bpm
        s.keyscale = keyscale
        s.timesignature = timesignature
        s.seed = seed
        s.steps = steps
        s.instrumental = instrumental
        s.prompt = prompt
        s.lyrics = lyrics
        s.refAudioPath = refAudioURL?.path
        s.task = task
        s.srcAudioPath = srcAudioURL?.path
        s.coverStrength = coverStrength
        s.coverNoiseStrength = coverNoiseStrength
        s.trackClasses = trackClasses
        return s
    }

    private func persist() { stickySnapshot.save() }

    // MARK: - Examples

    /// Style-prompt Templates menu: Save current + your saved styles (with a
    /// Delete submenu) + the built-in genre starters.
    private var styleExamplesMenu: some View {
        Menu {
            Button {
                saveTitle = MusicPromptStore.autoTitle(from: prompt)
                showSaveStyle = true
            } label: { Text("Save current…")
                .font(.app(.body)) }
            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !library.savedStyles.isEmpty {
                Section("Saved") {
                    ForEach(library.savedStyles) { p in
                        Button { prompt = p.body } label: { Text(L10n.text(p.title))
                            .font(.app(.body)) }
                    }
                }
                Menu("Delete saved…") {
                    ForEach(library.savedStyles) { p in
                        Button(role: .destructive) { library.deleteStyle(title: p.title) } label: {
                            Label(L10n.text(p.title), systemImage: "trash")
                        }
                    }
                }
            }
            // Named after the engine, because the two sets are not
            // interchangeable: ACE-Step reads a one-line genre description and
            // Music 3 a structured caption.
            Section("Example templates for \(model.family == .minimaxMusic3 ? "MiniMax Music 3" : "ACE-Step")") {
                ForEach(MusicPrompt.builtinStyles(for: model.family)) { p in
                    Button { prompt = p.body } label: { Text(L10n.text(p.title))
                        .font(.app(.body)) }
                }
            }
        } label: {
            Text("Templates")
        }
        .modifier(PaneChipMenu())
    }

    /// Lyrics Templates menu: Save current + your saved lyrics (with a Delete
    /// submenu) + built-in ORIGINAL lyric templates to start from.
    private var lyricsExamplesMenu: some View {
        Menu {
            Button {
                saveTitle = MusicPromptStore.autoTitle(from: lyrics)
                showSaveLyrics = true
            } label: { Text("Save current…")
                .font(.app(.body)) }
            .disabled(lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !library.savedLyrics.isEmpty {
                Section("Saved") {
                    ForEach(library.savedLyrics) { p in
                        Button { lyrics = p.body } label: { Text(L10n.text(p.title))
                            .font(.app(.body)) }
                    }
                }
                Menu("Delete saved…") {
                    ForEach(library.savedLyrics) { p in
                        Button(role: .destructive) { library.deleteLyrics(title: p.title) } label: {
                            Label(L10n.text(p.title), systemImage: "trash")
                        }
                    }
                }
            }
            Section("Example templates") {
                ForEach(MusicPrompt.builtinLyrics) { p in
                    Button { lyrics = p.body } label: { Text(L10n.text(p.title))
                        .font(.app(.body)) }
                }
            }
        } label: {
            Text("Templates")
        }
        .modifier(PaneChipMenu())
    }

    // MARK: - Generate

    private func discardPendingSubmission() {
        pendingSubmission?.discard()
        pendingSubmission = nil
        pendingRequest = nil
    }

    private func tryGenerate(_ submission: MediaInteractionSubmission) {
        guard !service.isRunning, generationBlockReason == nil else {
            submission.discard()
            return
        }
        let req = MusicGenRequest(
            model: model,
            prompt: prompt,
            lyrics: lyrics,
            instrumental: instrumental,
            vocalLanguage: vocalLanguage,
            bpm: bpm,
            keyscale: keyscale,
            timesignature: timesignature,
            durationSeconds: Int(durationSeconds),
            seed: seed,
            steps: steps,
            keepResident: keepResident,
            refAudioPath: refAudioURL?.path,
            task: task,
            srcAudioPath: srcAudioURL?.path,
            coverStrength: coverStrength,
            coverNoiseStrength: coverNoiseStrength,
            trackClasses: trackClasses,
            lanModelId: lanModel
        )
        persist()
        let total = RAMChecker.totalGB
        let needed = model.approxRAMGB
        if total < needed {
            ramWarningMessage = "This model needs about \(needed) GB of RAM, but your Mac has \(total) GB total. It may run very slowly or fail. Continue?"
            pendingRequest = req
            pendingSubmission = submission
            showRAMWarning = true
            return
        }
        startGeneration(req, submission: submission)
    }

    private func startGeneration(_ req: MusicGenRequest, submission: MediaInteractionSubmission) {
        guard submission.begin(req.prompt) else { return }
        service.generate(req, server: server, downloads: downloads)
    }
}
