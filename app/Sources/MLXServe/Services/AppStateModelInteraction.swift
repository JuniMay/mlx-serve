import Foundation
import SwiftUI

extension AppState {
    @MainActor
    func selectInteractionModel(_ row: ModelPaletteRow, using openWindow: OpenWindowAction) {
        switch row.interaction {
        case .chat:
            applyChatModelPick(row.tag)
            showConversation()
        case .media(let modality):
            if let remote = LanPick.lanId(row.tag) {
                selectMediaModel(modality: modality, name: remote, presetID: row.tag)
            } else if let model = localModels.first(where: { $0.path == row.tag }) {
                selectMediaModel(modality: modality, name: model.name, path: model.path)
            }
        case .decision:
            decisionsModelPath = row.tag
            AppActivation.openWindow(id: "decisions", using: openWindow)
        }
    }

    /// Selects a media model without changing drafts or loading a chat engine.
    @MainActor
    func selectMediaModel(modality: MediaModality, name: String, path: String = "",
                          presetID: String? = nil) {
        let selectedID = presetID ?? ModelBrowserUse.mediaPresetID(
            modality: modality, name: name, path: path, models: server.allModels)
        if let id = selectedID {
            switch modality {
            case .image:
                var settings = ImageGenSettings.load(); settings.modelId = id; settings.save()
            case .voice:
                var settings = AudioGenSettings.load(); settings.modelId = id; settings.save()
            case .music:
                var settings = MusicGenSettings.load(); settings.modelId = id; settings.save()
            case .sound:
                var settings = SoundGenSettings.load(); settings.modelId = id; settings.save()
            case .video:
                var settings = VideoGenSettings.load(); settings.modelId = id; settings.save()
            case .mesh:
                var settings = Model3DGenSettings.load(); settings.modelId = id; settings.save()
            }
            mediaModelSelection = MediaModelSelectionRequest(modality: modality, modelID: id)
        }
        if let tab = modality.audioTab { UserDefaults.standard.set(tab.rawValue, forKey: "audioGenTab") }
        interactionMedia = modality
        showConversation()
    }

    func savedMediaModelID(for modality: MediaModality) -> String {
        switch modality {
        case .image: return ImageGenSettings.load().modelId
        case .voice: return AudioGenSettings.load().modelId
        case .music: return MusicGenSettings.load().modelId
        case .sound: return SoundGenSettings.load().modelId
        case .video: return VideoGenSettings.load().modelId
        case .mesh: return Model3DGenSettings.load().modelId
        }
    }

    var interactionModelRows: [ModelPaletteRow] {
        ModelPalette.rows(appleAvailable: AppleFoundationChat.availability.isAvailable,
                          local: localModels, lan: server.allModels.filter { $0.lanPeer != nil },
                          mediaModels: server.allModels)
    }

    var interactionModelTag: String {
        guard let modality = interactionMedia else {
            return ChatModelSelection.tag(localPath: selectedModelPath,
                                          lanChatModelId: server.lanChatModelId, apple: useAppleModel)
        }
        let modelID = savedMediaModelID(for: modality)
        if LanPick.lanId(modelID) != nil { return modelID }
        return localModels.first {
            ModelInteractionRoute.resolve($0) == .media(modality)
                && ModelBrowserUse.mediaPresetID(modality: modality, name: $0.name, path: $0.path,
                                                models: server.allModels) == modelID
        }?.path ?? modelID
    }

    var interactionModelName: String? {
        guard let modality = interactionMedia else { return nil }
        if let row = interactionModelRows.first(where: { $0.tag == interactionModelTag }) { return row.title }
        let modelID = savedMediaModelID(for: modality)
        if let remote = LanPick.lanId(modelID) { return ModelDisplayName.pretty(remote) }
        return ModelDisplayName.pretty(modelID)
    }
}
