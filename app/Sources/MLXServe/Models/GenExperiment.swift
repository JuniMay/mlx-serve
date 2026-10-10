import Foundation

/// Media workspaces shared by the tray, session menu, and Tools menu.
enum GenExperiment: String, CaseIterable, Identifiable {
    case image, video, audio, model3d

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .image: "photo.on.rectangle.angled"
        case .video: "film.stack"
        case .audio: "waveform"
        case .model3d: "cube.transparent"
        }
    }

    var title: String {
        switch self {
        case .image: "Image"
        case .video: "Video"
        case .audio: "Audio"
        case .model3d: "3D"
        }
    }

    var menuTitle: String {
        switch self {
        case .image: "Image Generation"
        case .video: "Video Generation"
        case .audio: "Audio & Music"
        case .model3d: "3D Model"
        }
    }

    var help: String {
        switch self {
        case .image: "Image Generation (FLUX.2 / Krea-2)"
        case .video: "Video Generation (LTX-Video 2.3)"
        case .audio: "Audio Generation — voice cloning & music"
        case .model3d: "3D Generation — photo to mesh (Hunyuan3D 2.1)"
        }
    }
}
