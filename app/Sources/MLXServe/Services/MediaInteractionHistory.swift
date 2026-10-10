import Combine
import Foundation

enum MediaComposerActivity: Equatable {
    case idle, preparingHere, generatingHere, busyElsewhere

    var canCancel: Bool { self == .preparingHere || self == .generatingHere }
}

@MainActor
final class MediaInteractionSubmission {
    private let beginRequest: (String) -> Bool
    private let discardRequest: () -> Void

    fileprivate init(begin: @escaping (String) -> Bool, discard: @escaping () -> Void) {
        beginRequest = begin
        discardRequest = discard
    }

    func begin(_ actualPrompt: String) -> Bool { beginRequest(actualPrompt) }
    func discard() { discardRequest() }
}

struct MediaInteractionProgress: Equatable, Identifiable {
    var modality: MediaModality
    var sessionId: UUID
    var step: Int
    var total: Int
    var message: String
    var startedAt: Date
    var isPreparing = false

    var id: MediaModality { modality }

    var title: String {
        if isPreparing { return "Preparing generation" }
        switch modality {
        case .image: return "Generating image"
        case .voice: return "Synthesizing speech"
        case .music: return "Composing music"
        case .sound: return "Making a sound effect"
        case .video: return "Rendering video"
        case .mesh: return "Generating 3D model"
        }
    }

    var icon: String {
        switch modality {
        case .image: "photo"
        case .voice: "waveform"
        case .music: "music.note"
        case .sound: "speaker.wave.3"
        case .video: "film"
        case .mesh: "cube"
        }
    }

    var fraction: Double? {
        guard total > 0 else { return nil }
        return min(1, max(0, Double(step) / Double(total)))
    }

    var detailText: String {
        guard total > 0 else { return message }
        return L10n.format("%@ — step %lld of %lld", message, Int64(step), Int64(total))
    }
}

@MainActor
final class MediaInteractionHistory: ObservableObject {
    enum Event: Equatable {
        case idle
        case running(step: Int, total: Int, message: String)
        case completed(path: String)
        case failed(String)
        case cancelled
    }

    private struct Run {
        let id = UUID()
        var sessionId: UUID
        var prompt: String
        var accepted = false
        let preparedAt = Date()
        var progress: MediaInteractionProgress?
    }

    @Published private var runs: [MediaModality: Run] = [:]
    private let append: (UUID, [ChatMessage]) -> Void
    private let save: () -> Void
    private let cancelGeneration: (MediaModality) -> Void
    private var subscriptions = Set<AnyCancellable>()

    init(append: @escaping (UUID, [ChatMessage]) -> Void,
         save: @escaping () -> Void,
         cancel: @escaping (MediaModality) -> Void = { _ in }) {
        self.append = append
        self.save = save
        self.cancelGeneration = cancel
    }

    convenience init(appState: AppState) {
        self.init(append: { [weak appState] sessionId, messages in
            for message in messages { appState?.appendMessage(to: sessionId, message: message) }
        }, save: { [weak appState] in
            appState?.saveChatHistory()
        }, cancel: { [weak appState] modality in
            guard let appState else { return }
            switch modality {
            case .image: appState.imageGen.cancel()
            case .voice: appState.audioGen.cancel()
            case .music: appState.musicGen.cancel()
            case .sound: appState.soundGen.cancel()
            case .video: appState.videoGen.cancel()
            case .mesh: appState.model3dGen.cancel()
            }
        })

        objectWillChange.sink { [weak appState] in
            appState?.objectWillChange.send()
        }.store(in: &subscriptions)

        observe(appState.imageGen.$phase, modality: .image) { phase in
            switch phase {
            case .idle: .idle
            case .running(let step, let total, let message): .running(step: step, total: total, message: message)
            case .completed(let path): .completed(path: path)
            case .failed(let message): .failed(message)
            }
        }
        observe(appState.audioGen.$phase, modality: .voice) { phase in
            switch phase {
            case .idle: .idle
            case .running(let step, let total, let message): .running(step: step, total: total, message: message)
            case .completed(let path): .completed(path: path)
            case .failed(let message): .failed(message)
            }
        }
        observe(appState.musicGen.$phase, modality: .music) { phase in
            switch phase {
            case .idle: .idle
            case .running(let step, let total, let message): .running(step: step, total: total, message: message)
            case .completed(let path): .completed(path: path)
            case .failed(let message): .failed(message)
            }
        }
        observe(appState.soundGen.$phase, modality: .sound) { phase in
            switch phase {
            case .idle: .idle
            case .running(let step, let total, let message): .running(step: step, total: total, message: message)
            case .completed(let path): .completed(path: path)
            case .failed(let message): .failed(message)
            }
        }
        observe(appState.videoGen.$phase, modality: .video) { phase in
            switch phase {
            case .idle: .idle
            case .running(let step, let total, let message): .running(step: step, total: total, message: message)
            case .completed(let path): .completed(path: path)
            case .failed(let message): .failed(message)
            case .cancelled: .cancelled
            }
        }
        observe(appState.model3dGen.$phase, modality: .mesh) { phase in
            switch phase {
            case .idle: .idle
            case .running(let step, let total, let message): .running(step: step, total: total, message: message)
            case .completed(let path): .completed(path: path)
            case .failed(let message): .failed(message)
            }
        }
    }

    private func observe<P: Publisher>(_ publisher: P, modality: MediaModality,
                                       event: @escaping (P.Output) -> Event) where P.Failure == Never {
        // A service can already hold an output from an earlier, unowned request.
        publisher.dropFirst().sink { [weak self] phase in
            self?.receive(event(phase), for: modality)
        }.store(in: &subscriptions)
    }

    func reserve(_ modality: MediaModality, sessionId: UUID, prompt: String) -> MediaInteractionSubmission? {
        guard runs[modality] == nil else { return nil }
        let run = Run(sessionId: sessionId, prompt: prompt)
        runs[modality] = run
        return MediaInteractionSubmission(begin: { [weak self] actualPrompt in
            self?.begin(modality, token: run.id, prompt: actualPrompt) ?? false
        }, discard: { [weak self] in
            self?.discard(modality, token: run.id)
        })
    }

    func composerState(modality: MediaModality, sessionId: UUID,
                       serviceIsRunning: Bool) -> MediaComposerActivity {
        guard let run = runs[modality] else { return serviceIsRunning ? .busyElsewhere : .idle }
        guard run.sessionId == sessionId else { return .busyElsewhere }
        return run.progress == nil ? .preparingHere : .generatingHere
    }

    private func begin(_ modality: MediaModality, token: UUID, prompt: String) -> Bool {
        guard var run = runs[modality], run.id == token, !run.accepted else { return false }
        run.prompt = prompt
        run.accepted = true
        runs[modality] = run
        return true
    }

    private func discard(_ modality: MediaModality, token: UUID) {
        guard let run = runs[modality], run.id == token, run.progress == nil else { return }
        runs.removeValue(forKey: modality)
    }

    func receive(_ event: Event, for modality: MediaModality) {
        guard var run = runs[modality], run.accepted else { return }
        switch event {
        case .running(let step, let total, let message):
            if run.progress == nil {
                append(run.sessionId, [ChatMessage(role: .user, content: run.prompt)])
                save()
            }
            run.progress = MediaInteractionProgress(
                modality: modality, sessionId: run.sessionId, step: step, total: total,
                message: message, startedAt: run.progress?.startedAt ?? Date())
            runs[modality] = run
        case .completed(let path):
            guard run.progress != nil else { return }
            var response = ChatMessage(role: .assistant, content: "")
            response.media = [ChatMediaRef(kind: attachmentKind(for: modality), path: path, prompt: run.prompt)]
            finish(modality, run: run, message: response)
        case .failed(let detail):
            var response = ChatMessage(role: .assistant, content: "")
            response.errorNotice = ChatErrorNotice(kind: .generic, message: detail,
                                                  neededTokens: nil, contextLength: nil)
            finish(modality, run: run, message: response)
        case .idle, .cancelled:
            if run.progress != nil {
                finish(modality, run: run, message: ChatMessage(role: .assistant, content: "Generation stopped."))
            } else {
                runs.removeValue(forKey: modality)
            }
        }
    }

    func progress(for sessionId: UUID) -> [MediaInteractionProgress] {
        MediaModality.allCases.compactMap { modality in
            guard let run = runs[modality], run.sessionId == sessionId else { return nil }
            return run.progress ?? MediaInteractionProgress(
                modality: modality, sessionId: sessionId, step: 0, total: 0,
                message: "Waiting for model preparation…", startedAt: run.preparedAt,
                isPreparing: true)
        }
    }

    func cancel(sessionId: UUID) {
        let owned = MediaModality.allCases.filter { runs[$0]?.sessionId == sessionId }
        for modality in owned {
            cancel(modality: modality, sessionId: sessionId)
        }
    }

    func cancel(modality: MediaModality, sessionId: UUID) {
        guard let run = runs[modality], run.sessionId == sessionId else { return }
        if run.progress != nil {
            finish(modality, run: run, message: ChatMessage(role: .assistant, content: "Generation stopped."))
            cancelGeneration(modality)
        } else {
            runs.removeValue(forKey: modality)
        }
    }

    private func finish(_ modality: MediaModality, run: Run, message: ChatMessage) {
        runs.removeValue(forKey: modality)
        append(run.sessionId, [message])
        save()
    }

    private func attachmentKind(for modality: MediaModality) -> ChatMediaRef.Kind {
        switch modality {
        case .image: .image
        case .voice, .music, .sound: .audio
        case .video: .video
        case .mesh: .model3D
        }
    }
}

extension AppState {
    func prepareMediaInteraction(_ modality: MediaModality, sessionId: UUID,
                                 prompt: String) -> MediaInteractionSubmission? {
        mediaInteractions.reserve(modality, sessionId: sessionId, prompt: prompt)
    }
}
