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
            guard let model = localModels.first(where: { $0.path == row.tag }) else { return }
            selectMediaModel(modality: modality, name: model.name, path: model.path)
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
        showCreate(modality.experiment)
    }
}
