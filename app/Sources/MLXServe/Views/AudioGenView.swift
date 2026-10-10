import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum AudioInteractionKind: String, CaseIterable {
    case voice = "Voice"
    case music = "Music"
    case sound = "Sound Effects"
}

/// The style prompt a track was made from, read back out of the `<track>.txt`
/// sidecar the gen services write beside every WAV.
///
/// A history row carries a path and nothing else, so without this a track sent
/// to chat arrives captioned "Generated audio" — true, and useless in a
/// transcript you keep. Best-effort by design: an older track, a hand-copied
/// file or a missing sidecar just falls back to that.
enum AudioSidecar {
    static func prompt(forTrack path: String) -> String {
        let txt = (path as NSString).deletingPathExtension + ".txt"
        guard let body = try? String(contentsOfFile: txt, encoding: .utf8) else { return "" }
        guard let range = body.range(of: "# Style prompt\n") else { return "" }
        let rest = body[range.upperBound...]
        // The sidecar's sections are separated by a blank line.
        let end = rest.range(of: "\n\n")?.lowerBound ?? rest.endIndex
        return String(rest[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Vertical list of past generations, shared by the Voice and Music tabs.
/// Every file the service ever wrote stays listed (newest first, uncapped);
/// clicking a row plays it through the owning tab's player, replacing
/// whatever was playing.
struct AudioHistoryShelf: View {
    let title: String
    let paths: [String]
    let playingPath: String?
    let onPlay: (String) -> Void
    let onStop: () -> Void

    var body: some View {
        Group {
            if !paths.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text(title)).font(.app(.caption).weight(.semibold)).foregroundStyle(.secondary)
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(paths, id: \.self) { path in
                                row(path)
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                }
            }
        }
    }

    private func row(_ path: String) -> some View {
        let playing = playingPath == path
        return HStack(spacing: 8) {
            // The same glyph throughout — what says it is playing is that it
            // MOVES, and a row that stopped has to look like the ones that
            // never started.
            Image(systemName: "waveform")
                .foregroundStyle(playing ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing,
                              options: .repeat(.continuous), isActive: playing)
                .frame(width: 16)
            Text(URL(fileURLWithPath: path).lastPathComponent)
                .font(.app(.caption))
                .lineLimit(1).truncationMode(.middle)
                .help(path)
            Spacer()
            Button {
                playing ? onStop() : onPlay(path)
            } label: {
                Image(systemName: playing ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.borderless)
            .help(playing ? "Stop" : "Play")
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            } label: { Image(systemName: "folder") }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Reveal in Finder")
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(playing ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { playing ? onStop() : onPlay(path) }
    }
}

/// Which of the Voice pane's inputs the chosen model actually takes.
enum VoiceGenInputs {
    /// A model that speaks in its own built-in voices takes no `ref_audio`
    /// (a named 400 server-side), so the whole section goes away rather than
    /// asking for a clip nothing would read.
    static func showsReference(_ model: AudioModelPreset) -> Bool {
        model.supportsCloning
    }
}

/// Speech uses a text input, an optional reference voice, and an output player.
struct VoiceInteractionControls: View {
    @EnvironmentObject var service: AudioGenService
    @EnvironmentObject var server: ServerManager
    @EnvironmentObject var downloads: DownloadManager
    @EnvironmentObject var appState: AppState

    @StateObject private var recorder = AudioRecorder()

    @Binding var text: String

    init(prompt: Binding<String>) {
        _text = prompt
    }
    @State private var model: AudioModelPreset = .qwen3TTS06B8bit
    /// Selected network model's routing id (`<model>@<peer>`); nil = local.
    @State private var lanModel: String? = nil
    @State private var refAudioURL: URL? = nil
    @State private var refText: String = ""
    @State private var speed: Double = 1.0
    @State private var temperature: Double = 0.7

    @State private var refError: String? = nil
    /// True while a drag carrying a file hovers the reference-voice section —
    /// drives its dashed-border highlight (see `MediaDropTarget`).
    @State private var isDropTargeted: Bool = false
    /// Dictation into the text editor: the voice-mode recognizer emits one
    /// finalized utterance per silence gap; each is appended via `Dictation`.
    /// Created lazily on first use — never at launch (audio-graph TCC rule).
    @State private var dictation: (any SpeechRecognizing)? = nil
    @State private var dictating: Bool = false
    @State private var dictationPartial: String = ""
    @State private var dictationError: String? = nil
    @State private var showRAMWarning: Bool = false
    @State private var ramWarningMessage: String = ""
    @State private var pendingRequest: AudioGenRequest? = nil
    @State private var pendingSubmission: MediaInteractionSubmission? = nil
    // The app-wide singleton, not a per-view instance — see the matching note
    // in MusicGenView: a private player left playing when this view unmounts
    // on tab navigation is a leaked NSSound nothing can stop.
    @ObservedObject private var clipPlayer = AudioClipPlayer.shared
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
        .onDisappear {
            stopDictation()
            stopPlayback()
        }
        .onChange(of: appState.mediaModelSelection) { _, request in
            guard let request, let selection = request.applying(to: stickySnapshot) else { return }
            model = selection.resolvedModel(models: server.allModels)
            lanModel = LanPick.lanId(selection.modelId)
        }
        .onChange(of: stickySnapshot) { _, _ in guard !hydrating else { return }; persist() }
        .onChange(of: service.phase) { _, phase in
            // A new generation stops whatever is still playing.
            if case .running = phase { stopPlayback() }
            if case .completed(let path) = phase { play(path) }
        }
    }

    private func play(_ path: String) {
        clipPlayer.play(path)
    }

    private func stopPlayback() {
        clipPlayer.stop()
    }

    private var readyView: some View {
        MediaInteractionControls(
            placeholder: "Enter the words you want to hear…", notice: dictationError ?? generationBlockReason,
            hasAttachments: VoiceGenInputs.showsReference(model),
            attachmentCount: VoiceGenInputs.showsReference(model) && refAudioURL != nil ? 1 : 0,
            isRunning: service.isRunning, canSubmit: generationBlockReason == nil,
            submit: tryGenerate,
            attachments: {
                if VoiceGenInputs.showsReference(model) { referenceSection }
                if recorder.isRecording {
                    HStack {
                        Label("Recording reference voice…", systemImage: "microphone.fill")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Stop", systemImage: "stop.fill") { stopRecording() }
                            .buttonStyle(.bordered)
                    }
                }
            }, parameters: {
                modelDownload
                keepResidentToggle
                parameterControls
                AudioHistoryShelf(
                    title: "History", paths: service.recent,
                    playingPath: clipPlayer.playingPath,
                    onPlay: { play($0) }, onStop: { stopPlayback() })
                outputFolderLink
            }, promptActions: { dictationButton })
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

    // MARK: - Dictation

    /// Start, state and stop in ONE control: a running mic is the loudest thing
    /// in the pane, and the way to end it is the thing you are already looking
    /// at. The partial transcript is not shown — every finished utterance lands
    /// in the editor below, which is where you would read it anyway.
    private var dictationButton: some View {
        Button { toggleDictation() } label: {
            HStack(spacing: 5) {
                Image(systemName: dictating ? "microphone.fill" : "microphone")
                Text(L10n.text(dictating ? "Listening…" : "Speak it"))
                if dictating { Image(systemName: "stop.fill") }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(dictating ? Color.orange : Color.accentColor)
        .help(L10n.text(dictating ? "Stop dictation" : "Dictate the text instead of typing it"))
    }

    private func toggleDictation() {
        dictating ? stopDictation() : startDictation()
    }

    private func startDictation() {
        dictationError = nil
        Task {
            let rec = dictation ?? makeSpeechRecognizer()
            dictation = rec
            guard await rec.requestAuthorization() else {
                dictationError = "Microphone or speech-recognition access is off. Enable both in System Settings ▸ Privacy & Security."
                return
            }
            rec.onPartialTranscript = { dictationPartial = $0 }
            rec.onFinalTranscript = {
                text = Dictation.appending($0, to: text)
                dictationPartial = ""
            }
            rec.onError = { msg in
                dictationError = msg
                stopDictation()
            }
            do {
                try rec.start()
                dictating = true
            } catch {
                dictationError = error.localizedDescription
            }
        }
    }

    private func stopDictation() {
        // Words spoken but not yet finalized by the silence gap land too —
        // stopping mid-sentence must not eat them.
        if !dictationPartial.isEmpty { text = Dictation.appending(dictationPartial, to: text) }
        dictationPartial = ""
        dictation?.stop()
        dictating = false
    }

    private var modelDownload: some View {
        Group {
            if lanModel == nil && !downloads.bundleReady(model.bundle) {
                BundleDownloadBar(bundle: model.bundle)
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

    private var referenceSection: some View {
        VStack(alignment: .leading, spacing: AppLayout.labelSpacing) {
            Text("Reference voice").font(.app(.headline).weight(.semibold))

            if let url = refAudioURL {
                MediaDropWellFilled(isTargeted: isDropTargeted) {
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
                                Button { playReference(url) } label: { Image(systemName: "play.circle") }
                                    .buttonStyle(.borderless).help("Preview reference")
                            }
                            Button { clearReference() } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.borderless).foregroundStyle(.secondary).help("Clear reference")
                        }
                        // In the well with the clip it describes, not under it.
                        Text("Transcript of reference (optional)").font(.app(.rowTitle))
                            .padding(.top, 6)
                        TextField("", text: $refText,
                                  prompt: Text("Optional — the reference audio alone clones the voice"))
                            .textFieldStyle(.roundedBorder)
                            .font(.app(.caption))
                    }
                }
            } else if recorder.isRecording {
                MediaDropWellFilled(isTargeted: isDropTargeted) {
                    HStack(spacing: 10) {
                        Image(systemName: "microphone.fill")
                            .font(.app(.caption))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.orange))
                        ProgressView(value: Double(recorder.level)).frame(width: 120)
                        Text(String(format: "%.1fs", recorder.duration))
                            .font(.app(.caption).monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        Button { stopRecording() } label: {
                            Label("Stop", systemImage: "stop.fill").font(.app(.body))
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else {
                // Two ways in, one clip slot — the same well the picture panes
                // use, split down the middle.
                MediaDropWellPair(
                    isTargeted: isDropTargeted,
                    leading: MediaDropWellOption(
                        title: "Choose audio file…",
                        systemImage: "waveform.badge.plus",
                        caption: "or drag one here",
                        action: chooseReferenceFile),
                    trailing: MediaDropWellOption(
                        title: "Record audio…",
                        systemImage: "microphone.badge.plus",
                        caption: L10n.format("~%llds recommended", Int64(model.recommendedRefSeconds)),
                        action: startRecording))
            }

            if refAudioURL == nil {
                // The well already says how to add a clip and how long it wants
                // one; what is left to say is what happens without it.
                Text("Without a reference, the model's default voice is used.")
                    .font(.app(.caption2)).foregroundStyle(.secondary)
            }

            if let err = refError {
                Text(err).font(.app(.caption2)).foregroundStyle(.orange)
            }
        }
        // One clip slot, so a drop replaces what's there. Routed through
        // `acceptReference` so a dropped file is transcoded exactly like a
        // picked one — see `MediaDropTarget`.
        .mediaDrop(.audio, isTargeted: $isDropTargeted) { urls in
            if let url = urls.first { acceptReference(url) }
        }
    }

    private var parameterControls: some View {
        VStack(alignment: .leading, spacing: AppLayout.sectionSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Speed (\(String(format: "%.2fx", speed)))").font(.app(.caption))
                Slider(value: $speed, in: 0.5...2.0, step: 0.05)
                    .accessibilityLabel("Speed")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Temperature (\(String(format: "%.2f", temperature)))").font(.app(.caption))
                Slider(value: $temperature, in: 0.1...1.5, step: 0.05)
                    .accessibilityLabel("Temperature")
                Text("Higher = more expressive and varied.").font(.app(.caption2)).foregroundStyle(.secondary)
            }
        }
    }

    private var generationBlockReason: String? {
        guard !service.isRunning else { return nil }
        if lanModel == nil && !downloads.bundleReady(model.bundle) {
            return "Download the selected model to generate speech."
        }
        return text.isBlank ? "Enter the words you want to hear." : nil
    }

    private var outputFolderLink: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting(
                [URL(fileURLWithPath: MediaStorage.audiosRoot)])
        } label: {
            Label("Open output folder in Finder", systemImage: "folder")
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Reference actions

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

    /// The one way a FILE becomes the reference clip, whether it was picked or
    /// dropped: a dropped file gets the same 24 kHz mono transcode, and a
    /// transcode failure the same visible reason rather than a file that
    /// silently doesn't attach.
    private func acceptReference(_ url: URL) {
        refError = nil
        do {
            refAudioURL = try AudioReference.normalizedReferenceWav(fromFile: url)
        } catch {
            refError = error.localizedDescription
        }
    }

    private func startRecording() {
        refError = nil
        stopDictation() // one mic user at a time
        Task {
            guard await AudioRecorder.requestPermission() else {
                refError = "Microphone access denied. Enable it in System Settings ▸ Privacy ▸ Microphone."
                return
            }
            do { try recorder.start() }
            catch { refError = error.localizedDescription }
        }
    }

    private func stopRecording() {
        guard let data = recorder.stop() else {
            refError = "Nothing was recorded."
            return
        }
        do {
            refAudioURL = try AudioReference.normalizedReferenceWav(fromRecordedPCM: data)
        } catch {
            refError = error.localizedDescription
        }
    }

    private func clearReference() {
        if let url = refAudioURL { try? FileManager.default.removeItem(at: url) }
        refAudioURL = nil
        refText = ""
    }

    private func playReference(_ url: URL) {
        clipPlayer.play(url.path)
    }

    // MARK: - Sticky settings

    private func hydrate() {
        let s = AudioGenSettings.load()
        model = s.resolvedModel(models: server.allModels)
        lanModel = LanPick.lanId(s.modelId)
        speed = s.speed
        temperature = s.temperature
        keepResident = s.keepResident
        refText = s.refText
        // The clip is a temp transcode; only restore it while it still exists.
        refAudioURL = s.refAudioPath.flatMap { FileManager.default.fileExists(atPath: $0) ? URL(fileURLWithPath: $0) : nil }
    }

    /// Every sticky field (knobs AND the typed draft) as one `Equatable`
    /// blob, so a single `onChange` persists all of it.
    private var stickySnapshot: AudioGenSettings {
        var s = AudioGenSettings()
        s.modelId = LanPick.persisted(lanModel: lanModel, presetId: model.id)
        s.speed = speed
        s.temperature = temperature
        s.keepResident = keepResident
        s.text = text
        s.refText = refText
        s.refAudioPath = refAudioURL?.path
        return s
    }

    private func persist() { stickySnapshot.save() }

    // MARK: - Generate

    private func discardPendingSubmission() {
        pendingSubmission?.discard()
        pendingSubmission = nil
        pendingRequest = nil
    }

    private func tryGenerate(_ submission: MediaInteractionSubmission) {
        stopDictation() // the open mic would pick up the played result
        guard !service.isRunning, generationBlockReason == nil else {
            submission.discard()
            return
        }
        // A clip the pane is no longer showing must not still shape the
        // request: the same predicate decides both.
        let clones = VoiceGenInputs.showsReference(model)
        let req = AudioGenRequest(
            model: model,
            text: text,
            refAudioPath: clones ? refAudioURL?.path : nil,
            refText: clones ? refText : "",
            speed: speed,
            temperature: temperature,
            keepResident: keepResident,
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

    private func startGeneration(_ req: AudioGenRequest, submission: MediaInteractionSubmission) {
        guard submission.begin(req.text) else { return }
        service.generate(req, server: server)
    }

}
