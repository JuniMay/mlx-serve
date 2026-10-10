import Foundation

/// The workspace that can accept a model's inputs and display its outputs.
enum ModelInteractionRoute: Equatable {
    case chat
    case media(MediaModality)
    case decision

    static func resolve(_ model: LocalModel) -> ModelInteractionRoute? {
        guard model.defect == nil, !model.isDownloading, model.kind == .base else { return nil }
        // Kokoro configures spoken replies; the generation workspace requires voice cloning.
        guard model.modelType != "kokoro" else { return nil }
        if let modality = MediaModality(modelType: model.modelType) { return .media(modality) }
        if isDecisionModelType(model.modelType) { return .decision }
        return model.isChatPickable ? .chat : nil
    }

    var title: String {
        switch self {
        case .chat: return "Chat"
        case .media(let modality): return modality.paneName
        case .decision: return "Decisions"
        }
    }

    var symbol: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .media(let modality): return modality.experiment.icon
        case .decision: return "list.bullet.rectangle"
        }
    }
}
