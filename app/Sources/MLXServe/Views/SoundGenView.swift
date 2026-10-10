import SwiftUI
import AppKit

/// Sound Effects tab (Stable Audio 3): a description in, a short WAV out.
/// Built from the shared Create-pane pieces; everything shown is sticky
/// through `SoundGenSettings` (the pane unmounts on navigation).
struct SoundGenView: View {
    @EnvironmentObject var service: SoundGenService
    @EnvironmentObject var server: ServerManager
    @EnvironmentObject var downloads: DownloadManager
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var clipPlayer = AudioClipPlayer.shared

    @State private var model: SoundModelPreset = .stableAudio3SmallSFX
    @State private var lanModel: String? = nil
    @State private var prompt: String = ""
    @State private var durationSeconds: Double = 10
    @State private var steps: Int? = nil
    @State private var seed: Int = -1
    @State private var keepResident: Bool = false
    @State private var showRAMWarning = false
    @State private var hydrating = false
    @State private var didHydrate = false

    var body: some View {
        GenerationWorkspace(
            title: "Sound Effects", modelName: lanModel ?? model.name,
            notice: generationBlockReason,
            prompt: {
                promptSection
            }, model: {
                modelSection
            }, attachments: {
                EmptyView()
            }, parameters: {
                Toggle("Keep model loaded after generating", isOn: $keepResident)
                    .help("Keep the model in memory for the next sound.")
                durationSection
                parameterControls
            }, actions: {
                actionRow
            }, result: {
                previewArea
                AudioHistoryShelf(title: "History", paths: service.recent,
                                  playingPath: clipPlayer.playingPath,
                                  onPlay: { clipPlayer.play($0) }, onStop: { clipPlayer.stop() })
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: MediaStorage.soundRoot)])
                } label: {
                    Label("Open output folder in Finder", systemImage: "folder").font(.app(.caption))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .labelStyle(.iconOnly)
                .accessibilityLabel("Open output folder in Finder")
                .help("Open output folder in Finder")
                .frame(maxWidth: .infinity, alignment: .trailing)
            })
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
            Button(role: .cancel) {} label: { Text("Cancel").font(.app(.body)) }
            Button(role: .destructive) { service.generate(request, server: server) } label: {
                Text("Generate Anyway").font(.app(.body))
            }
        } message: {
            Text(L10n.format("This model needs about %d GB of RAM, but your Mac has %d GB total. It may run very slowly or fail. Continue?",
                             model.approxRAMGB, RAMChecker.totalGB)).font(.app(.body))
        }
    }

    // MARK: - Sections

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            MediaModelChooser.pane(
                all: SoundModelPreset.all,
                onThisMac: CustomMediaModels.soundPresets(from: server.allModels),
                capability: "sound",
                selected: $model, lanModel: $lanModel,
                capabilityOf: { _ in "Sound effects" },
                resolveCustom: { [models = server.allModels] in CustomMediaModels.soundPreset(for: $0, from: models) },
                bundleOf: { $0.bundle },
                downloads: downloads,
                onDownloadFinished: { appState.refreshModels() },
                persist: { snapshot.save() })
            if lanModel == nil && !downloads.bundleReady(model.bundle) {
                BundleDownloadBar(bundle: model.bundle, showsStartButton: false)
            }
        }
    }

    private var promptSection: some View {
        HStack(alignment: .top, spacing: AppLayout.compactSpacing) {
            TextEditor(text: $prompt)
                .accessibilityLabel("Describe the sound")
                .font(.app(.body))
                .frame(height: AppLayout.generationPromptHeight)
                .scrollContentBackground(.hidden)
                .help("Describe what makes the sound, its material and its surroundings, such as a heavy wooden door creaking open in a stone hall.")
                .overlay(alignment: .topLeading) {
                    if prompt.isEmpty {
                        Text("Describe a sound…")
                            .font(.app(.body))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
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
            .padding(.top, 6)
            .accessibilityLabel("Sound actions")
            .help("Sound actions")
        }
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

    private var actionRow: some View {
        HStack {
            if service.isRunning {
                Button(role: .destructive) { service.cancel() } label: {
                    Label("Cancel", systemImage: "stop.circle")
                }
                .buttonStyle(.bordered)
            } else {
                Button { generate() } label: {
                    Label("Generate", systemImage: "speaker.wave.3")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(generationBlockReason != nil)
            }
        }
        .controlSize(.large)
    }

    private var previewArea: some View {
        Group {
            switch service.phase {
            case .idle:
                VStack(spacing: AppLayout.rowSpacing) {
                    Image(systemName: "speaker.wave.3").font(.app(.title2))
                    Text("Describe the sound you want to create.").font(.app(.body))
                }
                .foregroundStyle(.secondary)
            case .running(let step, let total, let message):
                VStack(spacing: AppLayout.rowSpacing) {
                    if total == 0 {
                        ProgressView().frame(maxWidth: 240)
                    } else {
                        ProgressView(value: Double(step), total: max(1, Double(total))).progressViewStyle(.linear).frame(maxWidth: 240)
                    }
                    Text(message).font(.app(.footnote)).foregroundStyle(.secondary)
                }
            case .completed(let path):
                let playing = clipPlayer.playingPath == path
                VStack(spacing: AppLayout.rowSpacing) {
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.app(.largeTitle)).foregroundStyle(.tint)
                        .symbolEffect(.variableColor.iterative, options: .repeat(.continuous), isActive: playing)
                    Button { playing ? clipPlayer.stop() : clipPlayer.play(path) } label: {
                        Label(playing ? "Stop" : "Play", systemImage: playing ? "stop.fill" : "play.fill").font(.app(.body))
                    }
                    .buttonStyle(.bordered)
                    HStack(spacing: AppLayout.compactSpacing) {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.app(.caption)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless).help("Reveal in Finder")
                        .accessibilityLabel("Reveal in Finder")
                    }
                }
                .padding(AppLayout.contentInset)
            case .failed(let msg):
                ContentUnavailableView {
                    Label("Failed", systemImage: "exclamationmark.triangle").font(.app(.body))
                } description: {
                    Text(msg)
                } actions: {
                    Button { AppActivation.openWindow(id: "serverLog", using: openWindow) } label: {
                        Text("Show log").font(.app(.body))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - State

    private var request: SoundGenRequest {
        SoundGenRequest(model: model, prompt: prompt, durationSeconds: durationSeconds,
                        steps: steps, seed: seed, keepResident: keepResident, lanModelId: lanModel)
    }

    private func generate() {
        if RAMChecker.totalGB < model.approxRAMGB {
            showRAMWarning = true
            return
        }
        service.generate(request, server: server)
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
        prompt = s.prompt
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
