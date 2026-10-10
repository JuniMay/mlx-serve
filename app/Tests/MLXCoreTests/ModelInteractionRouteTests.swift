import XCTest
@testable import MLXCore

final class ModelInteractionRouteTests: XCTestCase {
    private func model(_ type: String, kind: ModelKind = .base) -> LocalModel {
        LocalModel(id: type, name: type, path: "/models/\(type)", sizeFormatted: "1 GB",
                   modelType: type, source: .mlxServe, kind: kind)
    }

    func testModelsRouteToTheirOwnInputAndOutputCapabilities() {
        XCTAssertEqual(ModelInteractionRoute.resolve(model("gemma4")), .chat)
        let media: [(String, MediaModality)] = [("flux2-klein-4b", .image), ("AudioVideo", .video),
            ("qwen3_tts", .voice), ("acestep", .music), ("stable_audio3", .sound), ("hunyuan3d", .mesh)]
        for (type, modality) in media {
            XCTAssertEqual(ModelInteractionRoute.resolve(model(type)), .media(modality))
        }
        XCTAssertEqual(ModelInteractionRoute.resolve(model("laya")), .decision)
    }

    func testDependenciesAndUnavailableCheckpointsDoNotBecomeInteractions() {
        for type in ["bert", "embedding_gemma2", "unknown"] {
            XCTAssertNil(ModelInteractionRoute.resolve(model(type)))
        }
        XCTAssertNil(ModelInteractionRoute.resolve(model("gemma4", kind: .drafter)))
        var downloading = model("flux2-klein-4b")
        downloading.isDownloading = true
        XCTAssertNil(ModelInteractionRoute.resolve(downloading))
    }

    func testMediaOnlySetupDoesNotRequireDownloadingAChatModel() {
        XCTAssertFalse(ChatWorkspace.gateShouldPresent(
            gateIsBlocking: true, cancelled: false, workspace: .conversation,
            welcomePresented: false, otherInteractionAvailable: true))
        XCTAssertTrue(ChatWorkspace.gateShouldPresent(
            gateIsBlocking: true, cancelled: false, workspace: .conversation,
            welcomePresented: false, otherInteractionAvailable: false))
    }
}
