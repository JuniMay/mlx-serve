import Foundation

/// A model change that preserves the workspace's current inputs.
struct MediaModelSelectionRequest: Identifiable, Equatable {
    let id = UUID()
    let modality: MediaModality
    let modelID: String
}

protocol MediaModelSelectionSettings {
    static var selectionModality: MediaModality { get }
    var modelId: String { get set }
}

extension MediaModelSelectionRequest {
    func applying<Settings: MediaModelSelectionSettings>(to settings: Settings) -> Settings? {
        guard modality == Settings.selectionModality else { return nil }
        var selection = settings
        selection.modelId = modelID
        return selection
    }
}

extension ImageGenSettings: MediaModelSelectionSettings {
    static let selectionModality = MediaModality.image
}

extension AudioGenSettings: MediaModelSelectionSettings {
    static let selectionModality = MediaModality.voice
}

extension MusicGenSettings: MediaModelSelectionSettings {
    static let selectionModality = MediaModality.music
}

extension SoundGenSettings: MediaModelSelectionSettings {
    static let selectionModality = MediaModality.sound
}

extension VideoGenSettings: MediaModelSelectionSettings {
    static let selectionModality = MediaModality.video
}

extension Model3DGenSettings: MediaModelSelectionSettings {
    static let selectionModality = MediaModality.mesh
}
