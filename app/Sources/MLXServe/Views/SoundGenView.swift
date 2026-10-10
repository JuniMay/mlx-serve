import SwiftUI
import AppKit

/// Sound generation parameters and actions for the interaction composer.
struct SoundInteractionControls: View {
    @EnvironmentObject var service: SoundGenService
    @EnvironmentObject var server: ServerManager
    @EnvironmentObject var downloads: DownloadManager
    @EnvironmentObject var appState: AppState
    @ObservedObject private var clipPlayer = AudioClipPlayer.shared

    @State private var model: SoundModelPreset = .stableAudio3SmallSFX
    @State private var lanModel: String? = nil
    @Binding var prompt: String
    @State private var durationSeconds: Double = 10
    @State private var steps: Int? = nil
    @State private var seed: Int = -1
    @State private var keepResident: Bool = false
    @State private var showRAMWarning = false
    @State private var pendingRequest: SoundGenRequest? = nil
    @State private var pendingSubmission: MediaInteractionSubmission? = nil
    @State private var hydrating = false
    @State private var didHydrate = false

    var body: some View {
        MediaInteractionControls(
            placeholder: "Describe a sound…", notice: generationBlockReason,
            isRunning: service.isRunning, canSubmit: generationBlockReason == nil,
            submit: generate,
            attachments: { EmptyView() }, parameters: {
                modelDownload
                Toggle("Keep model loaded after generating", isOn: $keepResident)
                    .help("Keep the model in memory for the next sound.")
                durationSection
                parameterControls
                AudioHistoryShelf(title: "History", paths: service.recent,
                                  playingPath: clipPlayer.playingPath,
                                  onPlay: { clipPlayer.play($0) }, onStop: { clipPlayer.stop() })
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: MediaStorage.soundRoot)])
                } label: {
                    Label("Open output folder in Finder", systemImage: "folder").font(.app(.caption))
                }
                .buttonStyle(.borderless)
            }, promptActions: { promptActions })
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
            if server.status == .running { Task { await server.refreshModels() } }
        }
        .onDisappear { clipPlayer.stop() }
        .onChange(of: appState.mediaModelSelection) { _, request in
            guard let request, let selection = request.applying(to: snapshot) else { return }
            model = selection.resolvedModel(models: server.allModels)
            lanModel = LanPick.lanId(selection.modelId)
        }
        .onChange(of: snapshot) { _, s in if !hydrating { s.save() } }
        .onChange(of: service.phase) { _, phase in
            if case .running = phase { clipPlayer.stop() }
            if case .completed(let path) = phase { clipPlayer.play(path) }
        }
        .alert("Model exceeds your Mac's RAM", isPresented: $showRAMWarning) {
            Button(role: .cancel) { discardPendingSubmission() } label: { Text("Cancel").font(.app(.body)) }
            Button(role: .destructive) {
                guard let req = pendingRequest, let submission = pendingSubmission else { return }
                pendingRequest = nil
                pendingSubmission = nil
                startGeneration(req, submission: submission)
            } label: {
                Text("Generate Anyway").font(.app(.body))
            }
        } message: {
            Text(L10n.format("This model needs about %d GB of RAM, but your Mac has %d GB total. It may run very slowly or fail. Continue?",
                             model.approxRAMGB, RAMChecker.totalGB)).font(.app(.body))
        }
    }

    // MARK: - Sections

    private var modelDownload: some View {
        Group {
            if lanModel == nil && !downloads.bundleReady(model.bundle) {
                BundleDownloadBar(bundle: model.bundle)
            }
        }
    }

    private var promptActions: some View {
        Menu {
            Section("Templates") {
                ForEach(SoundPrompt.examples, id: \.self) { example in
                    Button { prompt = example } label: { Text(verbatim: example) }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Sound actions")
        .help("Sound actions")
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("Duration").font(.app(.headline).weight(.semibold))
                Text(String(format: "%.1f sec", durationSeconds)).font(.app(.caption)).foregroundStyle(.secondary)
                Spacer()
            }
            Slider(value: $durationSeconds, in: model.durationRange, step: 0.5)
                .accessibilityLabel("Duration")
        }
    }

    private var parameterControls: some View {
        VStack(alignment: .leading, spacing: AppLayout.rowSpacing) {
            FlowLayout(spacing: 14, rowSpacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Steps").font(.app(.caption))
                    NumberField(range: model.stepsRange,
                                value: Binding(get: { steps ?? model.defaultSteps }, set: { steps = $0 }),
                                width: 52,
                                help: "Sampler steps, \(model.stepsRange.lowerBound)–\(model.stepsRange.upperBound). The model is distilled for \(model.defaultSteps).")
                }
                SeedField(label: "Seed", placeholder: "Random", range: -1...Int(UInt32.max), value: $seed)
            }
            Text("Same seed + prompt + length reproduces the sound.")
                .font(.app(.caption2)).foregroundStyle(.secondary)
        }
    }

    private var generationBlockReason: String? {
        guard !service.isRunning else { return nil }
        if lanModel == nil && !downloads.bundleReady(model.bundle) {
            return "Download the selected model to generate sound."
        }
        return prompt.isBlank ? "Describe the sound you want to make." : nil
    }

    // MARK: - State

    private var request: SoundGenRequest {
        SoundGenRequest(model: model, prompt: prompt, durationSeconds: durationSeconds,
                        steps: steps, seed: seed, keepResident: keepResident, lanModelId: lanModel)
    }

    private func generate(_ submission: MediaInteractionSubmission) {
        guard !service.isRunning, generationBlockReason == nil else {
            submission.discard()
            return
        }
        let req = request
        if RAMChecker.totalGB < model.approxRAMGB {
            pendingRequest = req
            pendingSubmission = submission
            showRAMWarning = true
            return
        }
        startGeneration(req, submission: submission)
    }

    private func startGeneration(_ req: SoundGenRequest, submission: MediaInteractionSubmission) {
        guard submission.begin(req.prompt) else { return }
        service.generate(req, server: server)
    }

    private func discardPendingSubmission() {
        pendingSubmission?.discard()
        pendingSubmission = nil
        pendingRequest = nil
    }

    private var snapshot: SoundGenSettings {
        var s = SoundGenSettings()
        s.modelId = LanPick.persisted(lanModel: lanModel, presetId: model.id)
        s.prompt = prompt
        s.durationSeconds = durationSeconds
        s.steps = steps
        s.seed = seed
        s.keepResident = keepResident
        return s
    }

    private func hydrate() {
        let s = SoundGenSettings.load()
        model = s.resolvedModel(models: server.allModels)
        lanModel = LanPick.lanId(s.modelId)
        durationSeconds = min(max(s.durationSeconds, model.durationRange.lowerBound), model.durationRange.upperBound)
        steps = s.steps
        seed = s.seed
        keepResident = s.keepResident
    }
}

/// Starter descriptions, from Stability's own demo prompts for this model.
enum SoundPrompt {
    static let examples = [
        "Futuristic laser blast, sharp energy pulse, stereo movement, arcade style",
        "Dog barking next to a waterfall",
        "Sparkling fantasy energy swirl, mystical shimmer, rising magical burst",
        "Running footsteps on pavement, fast pace, urban street environment, energetic motion sound",
        "Chugging train coming into station with horn",
    ]
}
