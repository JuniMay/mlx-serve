import Foundation

/// The inputs and outputs supported by an interaction model.
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

    static func resolve(_ model: ModelInfo) -> ModelInteractionRoute? {
        guard model.lanPeer != nil else { return nil }
        if model.lanAdvertises("chat") { return .chat }
        let name = LanPick.base(of: model.name)
        guard model.architecture != "kokoro", name != AudioModelPreset.kokoro82M.id else { return nil }
        let capabilities: [(MediaModality, String)] = [(.image, "image"), (.video, "video"),
            (.voice, "speech"), (.music, "music"), (.sound, "sound"), (.mesh, "3d")]
        for (modality, capability) in capabilities where model.lanAdvertises(capability) {
            let known = ModelBrowserUse.mediaPresetID(modality: modality, name: name, path: "") != nil
            let supported = model.architecture != "kokoro"
                && MediaModality(modelType: model.architecture) == modality
                && CustomMediaModels.bundle(arch: model.architecture, repoId: name) != nil
            if known || supported { return .media(modality) }
        }
        return nil
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
