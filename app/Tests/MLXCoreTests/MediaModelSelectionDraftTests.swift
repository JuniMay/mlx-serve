import XCTest
@testable import MLXCore

final class MediaModelSelectionDraftTests: XCTestCase {
    func testImageModelChangePreservesPromptSourcesAndAdapters() throws {
        var draft = ImageGenSettings()
        draft.modelId = "previous-image"
        draft.prompt = "A copper kettle"
        draft.negativePrompt = "Blurred lettering"
        draft.sourcePath = "/fixtures/source.png"
        draft.refPaths = ["/fixtures/reference.png"]
        draft.loras = [LoraAdapter(path: "/fixtures/style.safetensors", scale: 0.7)]
        draft.seed = 72
        draft.customWidth = 1536
        try assertModelChange(draft, to: ImageModelPreset.flux2Klein4B_Q4.id)
    }

    func testVoiceModelChangePreservesTextAndCloneReference() throws {
        var draft = AudioGenSettings()
        draft.modelId = "previous-voice"
        draft.text = "Welcome back."
        draft.refAudioPath = "/fixtures/voice.wav"
        draft.refText = "Reference sentence."
        draft.speed = 1.25
        draft.temperature = 0.4
        draft.keepResident = true
        try assertModelChange(draft, to: AudioModelPreset.qwen3TTS06B8bit.id)
    }

    func testMusicModelChangePreservesLyricsAndSourceTask() throws {
        var draft = MusicGenSettings()
        draft.modelId = "previous-music"
        draft.prompt = "Piano and strings"
        draft.lyrics = "[verse]\nRain on the window"
        draft.refAudioPath = "/fixtures/reference.wav"
        draft.srcAudioPath = "/fixtures/source.wav"
        draft.task = .cover
        draft.coverStrength = 0.7
        draft.coverNoiseStrength = 0.2
        draft.seed = 81
        draft.bpm = 92
        draft.keyscale = "C major"
        draft.durationSeconds = 95
        try assertModelChange(draft, to: MusicModelPreset.miniMaxMusic3_8bit.id)
    }

    func testSoundModelChangePreservesDescriptionAndTiming() throws {
        var draft = SoundGenSettings()
        draft.modelId = "previous-sound"
        draft.prompt = "A wooden door creaks"
        draft.durationSeconds = 6.5
        draft.steps = 12
        draft.seed = 42
        try assertModelChange(draft, to: SoundModelPreset.stableAudio3SmallSFX.id)
    }

    func testVideoModelChangePreservesEveryReferenceKind() throws {
        var draft = VideoGenSettings()
        draft.modelId = "previous-video"
        draft.prompt = "A quiet coastal scene"
        draft.firstFramePath = "/fixtures/first.png"
        draft.lastFramePath = "/fixtures/last.png"
        draft.audioPath = "/fixtures/ambience.wav"
        draft.speechText = "The tide is coming in."
        draft.refImagePaths = ["/fixtures/subject.png"]
        draft.refVideoPaths = ["/fixtures/motion.mp4"]
        draft.refAudioPaths = ["/fixtures/voice.wav"]
        draft.loras = [LoraAdapter(path: "/fixtures/film.safetensors", scale: 0.4)]
        draft.seed = 91
        draft.numFrames = 121
        try assertModelChange(draft, to: VideoModelPreset.ltx23Q4.id)
    }

    func testMeshModelChangePreservesPhotoTextureAndPreviewSettings() throws {
        var draft = Model3DGenSettings()
        draft.modelId = "previous-mesh"
        draft.photoPath = "/fixtures/object.png"
        draft.texture = true
        draft.turntable = false
        draft.steps = 40
        draft.guidance = 4.5
        draft.resolution = 256
        try assertModelChange(draft, to: Model3DModelPreset.hunyuan3d21_8bit.id)
    }

    private func assertModelChange<Settings: MediaModelSelectionSettings & Equatable>(
        _ draft: Settings, to modelID: String, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let request = MediaModelSelectionRequest(modality: Settings.selectionModality, modelID: modelID)
        var changed = try XCTUnwrap(request.applying(to: draft), file: file, line: line)
        XCTAssertEqual(changed.modelId, modelID, file: file, line: line)
        changed.modelId = draft.modelId
        XCTAssertEqual(changed, draft, "A model switch must preserve the current draft.", file: file, line: line)

        for other in MediaModality.allCases where other != Settings.selectionModality {
            XCTAssertNil(MediaModelSelectionRequest(modality: other, modelID: "other").applying(to: draft),
                         "Other workspaces must ignore this selection.", file: file, line: line)
        }
    }
}
