import XCTest
@testable import MLXCore

@MainActor
final class InteractionSelectionTests: XCTestCase {
    private var preferences: InteractionTestPreferences?

    override func setUpWithError() throws {
        let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] ?? ""
        guard home.hasPrefix("/tmp/") || home.hasPrefix("/private/tmp/") else {
            throw XCTSkip("Requires CFFIXED_USER_HOME in a temporary directory.")
        }
        preferences = InteractionTestPreferences()
    }

    override func tearDownWithError() throws {
        preferences?.restore()
        preferences = nil
    }

    func testSelectingVideoKeepsTheInteractionAndSession() {
        let app = AppState(startServices: false)
        let session = ChatSession(title: "Keep this interaction")
        app.chatSessions = [session]
        app.activeChatId = session.id
        app.chatWorkspace = .conversation
        let chatPath = app.selectedModelPath
        let preset = VideoModelPreset.minimaxH3

        app.selectMediaModel(modality: .video, name: preset.repo, presetID: preset.id)

        XCTAssertEqual(app.chatWorkspace, .conversation)
        XCTAssertEqual(app.activeChatId, session.id)
        XCTAssertEqual(app.chatSessions.count, 1)
        XCTAssertEqual(app.activeSession?.title, "Keep this interaction")
        XCTAssertEqual(app.selectedModelPath, chatPath)
        XCTAssertEqual(app.mediaModelSelection?.modelID, preset.id)
        XCTAssertEqual(app.interactionMedia, .video)
        XCTAssertEqual(app.server.status, .stopped)
    }

    func testSelectingChatAfterVideoKeepsTheSameInteraction() {
        let app = AppState(startServices: false)
        let session = ChatSession(title: "Keep this interaction")
        app.chatSessions = [session]
        app.activeChatId = session.id
        let preset = VideoModelPreset.minimaxH3
        app.selectMediaModel(modality: .video, name: preset.repo, presetID: preset.id)

        app.applyChatModelPick("/models/qwen3")

        XCTAssertEqual(app.chatWorkspace, .conversation)
        XCTAssertEqual(app.activeChatId, session.id)
        XCTAssertEqual(app.selectedModelPath, "/models/qwen3")
        XCTAssertNil(app.interactionMedia)
        XCTAssertEqual(app.server.status, .stopped)
    }

    func testReturningFromNetworkToSameLocalModelPersistsTheLocalChoice() {
        let app = AppState(startServices: false)
        let preset = ImageModelPreset.flux2Klein9BBase_Q4
        var settings = ImageGenSettings()
        settings.modelId = preset.id
        settings.seed = 73
        settings.save()
        app.selectMediaModel(modality: .image, name: preset.repo,
                             presetID: "lan:" + preset.id + "@studio")

        app.selectMediaModel(modality: .image, name: preset.repo, presetID: preset.id)

        XCTAssertEqual(ImageGenSettings.load().modelId, preset.id)
        XCTAssertEqual(ImageGenSettings.load().seed, 73)
        XCTAssertEqual(app.mediaModelSelection?.modelID, preset.id)
        XCTAssertEqual(app.chatWorkspace, .conversation)
    }

    func testMediaPickerIdentityNamesTheChosenModelAndLeavesChatAvailable() {
        let app = AppState(startServices: false)
        let preset = VideoModelPreset.minimaxH3
        let video = LocalModel(id: "video", name: preset.repo, path: "/models/" + preset.repo,
                               sizeFormatted: "80 GB", modelType: "minimax_h3", source: .mlxServe, kind: .base)
        let chat = LocalModel(id: "chat", name: "qwen/qwen3", path: "/models/qwen/qwen3",
                              sizeFormatted: "8 GB", modelType: "qwen3", source: .mlxServe, kind: .base)
        app.localModels = [video, chat]

        app.selectMediaModel(modality: .video, name: video.name, path: video.path)

        XCTAssertEqual(app.interactionModelTag, video.path)
        XCTAssertEqual(app.interactionModelName, ModelDisplayName.pretty(video.name))
        XCTAssertEqual(app.interactionModelRows.first(where: { $0.tag == chat.path })?.interaction, .chat)

        app.applyChatModelPick(chat.path)
        XCTAssertEqual(app.interactionModelTag, chat.path)
        XCTAssertNil(app.interactionMedia)
    }

    func testUsingTheAlreadyLoadedChatModelLeavesMediaControls() async {
        let app = AppState(startServices: false)
        app.selectedModelPath = "/models/qwen3"
        app.server.lanChatModelId = "qwen3@studio"
        app.server.status = .running
        let preset = VideoModelPreset.minimaxH3
        app.selectMediaModel(modality: .video, name: preset.repo, presetID: preset.id)

        let ready = await app.useModelAndAwaitReady(atPath: "/models/qwen3")

        XCTAssertTrue(ready)
        XCTAssertNil(app.interactionMedia)
        XCTAssertEqual(app.interactionModelTag, "/models/qwen3")
        app.server.status = .stopped
    }
    func testStartingAnAgentChatSelectsChatWithoutChangingTheGenericNewSession() async {
        let app = AppState(startServices: false)
        let path = "/models/qwen3"
        app.selectedModelPath = path
        let local = Agent(name: "Local", systemPrompt: "Help", modelPath: path)
        let network = Agent(name: "Network", systemPrompt: "Help", modelPath: "qwen3@studio")
        app.agents.add(local)
        app.agents.add(network)
        var remote = ModelInfo(name: "qwen3@studio", quantBits: 4, layers: 1, hiddenSize: 1,
                               vocabSize: 1, contextLength: 4096, modelMaxTokens: 4096)
        remote.lanPeer = "studio"
        remote.capabilities = ["chat"]
        app.server.allModels = [remote]
        for agentID in [nil, local.id, network.id] as [UUID?] {
            app.selectMediaModel(modality: .video, name: VideoModelPreset.minimaxH3.id,
                                 presetID: VideoModelPreset.minimaxH3.id)
            let id = app.startChat(withAgent: agentID)
            XCTAssertNil(app.interactionMedia, "An explicit agent chat must expose chat controls immediately.")
            XCTAssertEqual(app.activeChatId, id)
            XCTAssertEqual(app.activeSession?.agentId, agentID)
            await Task.yield()
            XCTAssertNil(app.interactionMedia)
            XCTAssertEqual(app.server.status, .stopped)
        }
        XCTAssertEqual(app.server.lanChatModelId, "qwen3@studio")

        app.selectMediaModel(modality: .video, name: VideoModelPreset.minimaxH3.id,
                             presetID: VideoModelPreset.minimaxH3.id)
        _ = app.newChatSession()
        XCTAssertEqual(app.interactionMedia, .video)
    }

}

/// Restores the test runner's preferences, which cfprefsd shares across processes.
struct InteractionTestPreferences {
    private let keys = [
        "selectedModelPath", "lanChatModelId", "useAppleModel", "audioGenTab",
        "imageGenSettings", "audioGenSettings", "musicGenSettings",
        "soundGenSettings", "videoGenSettings", "model3dGenSettings",
        "serverOptions", "pendingDrafterMigration", "prefixCacheMemAutoMigrated"
    ]
    private var saved: [String: Any] = [:]

    init() {
        for key in keys {
            saved[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func restore() {
        for key in keys {
            if let value = saved[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}
