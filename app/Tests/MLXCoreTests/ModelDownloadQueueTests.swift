import XCTest
@testable import MLXCore

@MainActor
final class ModelDownloadQueueTests: XCTestCase {
    private var root: String!
    private var savedSession: URLSession!

    override func setUpWithError() throws {
        root = (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        savedSession = DownloadSession.shared
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HuggingFaceStubProtocol.self]
        DownloadSession.shared = URLSession(configuration: config)
        HuggingFaceStubProtocol.reset()
    }

    override func tearDownWithError() throws {
        DownloadSession.shared = savedSession
        HuggingFaceStubProtocol.reset()
        try? FileManager.default.removeItem(atPath: root)
    }

    func testRetryKeepsTheSelectedGgufQuant() async throws {
        let repo = "fixture/quants"
        let quant = GgufQuant(filename: "model-Q4.gguf", label: "Q4")
        HuggingFaceStubProtocol.serve(repo: repo, files: [
            (quant.filename, Data(repeating: 7, count: 256)),
            ("model-Q8.gguf", Data(repeating: 8, count: 512)),
            ("config.json", Data("{}".utf8)),
        ])
        let manager = DownloadManager(modelsRoot: root)
        let first = expectation(description: "first quant download")
        manager.startGguf(repoId: repo, quant: quant) { first.fulfill() }
        await fulfillment(of: [first], timeout: 10)
        XCTAssertEqual(manager.downloads[repo]?.status, .completed)
        let dir = DownloadManager.newLayoutDir(rootDir: root, repoId: repo)
        try FileManager.default.removeItem(atPath: (dir as NSString).appendingPathComponent(quant.filename))
        manager.downloads[repo] = .init(status: .failed, error: "Interrupted")
        HuggingFaceStubProtocol.clearRequests()

        let retried = expectation(description: "retried quant")
        XCTAssertTrue(manager.retry(repoId: repo) { retried.fulfill() })
        await fulfillment(of: [retried], timeout: 10)

        XCTAssertEqual(manager.downloads[repo]?.status, .completed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent(quant.filename)))
        XCTAssertFalse(HuggingFaceStubProtocol.requests.contains { $0.path.hasSuffix("model-Q8.gguf") || $0.path.hasSuffix("config.json") })
    }

    func testRetryKeepsTheMlxVariantAndItsDestination() async throws {
        let repo = "fixture/variants"
        let variant = MlxVariant(folder: "4bit", label: "4-bit", sizeBytes: 256)
        HuggingFaceStubProtocol.serve(repo: repo, files: [
            ("4bit/config.json", Data("{}".utf8)),
            ("4bit/model.safetensors", Data(repeating: 4, count: 256)),
            ("8bit/model.safetensors", Data(repeating: 8, count: 512)),
        ])
        let manager = DownloadManager(modelsRoot: root)
        let first = expectation(description: "first variant download")
        manager.startMlxVariant(repoId: repo, variant: variant) { first.fulfill() }
        await fulfillment(of: [first], timeout: 10)
        let dest = MlxVariantScan.localRepoId(repoId: repo, folder: variant.folder)
        let dir = DownloadManager.newLayoutDir(rootDir: root, repoId: dest)
        try FileManager.default.removeItem(atPath: dir)
        manager.downloads[repo] = .init(status: .failed, error: "Interrupted")
        HuggingFaceStubProtocol.clearRequests()

        let retried = expectation(description: "retried variant")
        XCTAssertTrue(manager.retry(repoId: repo) { retried.fulfill() })
        await fulfillment(of: [retried], timeout: 10)

        XCTAssertEqual(manager.downloads[repo]?.status, .completed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent("model.safetensors")))
        XCTAssertFalse(HuggingFaceStubProtocol.requests.contains { $0.path.contains("/8bit/") })
    }

    func testCancellingAComponentStopsItsBundleAndKeepsInstalledComponents() async throws {
        let installed = "fixture/installed"
        let transferring = "fixture/transferring"
        let dir = DownloadManager.newLayoutDir(rootDir: root, repoId: installed)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let weights = (dir as NSString).appendingPathComponent("model.safetensors")
        try Data([1, 2, 3]).write(to: URL(fileURLWithPath: weights))
        try Data("{}".utf8).write(to: URL(fileURLWithPath: (dir as NSString).appendingPathComponent("config.json")))
        let bundle = MediaBundle(id: "fixture-bundle", displayName: "Fixture", components: [
            MediaComponent(repo: installed, selection: .chatDefault, readyMarkers: []),
            MediaComponent(repo: transferring, selection: .chatDefault, readyMarkers: []),
        ], sizeEstimateGB: 1)
        HuggingFaceStubProtocol.serve(repo: transferring, files: [
            ("model.safetensors", Data(repeating: 2, count: 4 << 20)),
        ], throttle: true)
        let manager = DownloadManager(modelsRoot: root)
        XCTAssertTrue(manager.componentReady(bundle.components[0]))
        let finished = expectation(description: "bundle stopped")
        manager.startBundle(bundle) { finished.fulfill() }
        for _ in 0..<100 where manager.downloads[transferring]?.fileIndex != 1 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(manager.downloads[transferring]?.status, .downloading,
                       manager.downloads[transferring]?.error ?? "Transfer did not start")
        XCTAssertEqual(manager.downloads[transferring]?.fileIndex, 1)

        manager.cancel(transferring)
        await fulfillment(of: [finished], timeout: 10)

        XCTAssertFalse(manager.isBundleDownloading(bundle))
        XCTAssertNil(manager.downloads[transferring])
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: weights)), Data([1, 2, 3]))
    }

    func testUnexpectedBundleFailureCompletesWithoutModalUIInTests() async {
        let repo = "fixture/missing"
        let bundle = MediaBundle(id: "missing-bundle", displayName: "Missing", components: [
            MediaComponent(repo: repo, selection: .chatDefault, readyMarkers: []),
        ], sizeEstimateGB: 1)
        let manager = DownloadManager(modelsRoot: root)
        let finished = expectation(description: "failed bundle completes")

        manager.startBundle(bundle) { finished.fulfill() }
        await fulfillment(of: [finished], timeout: 5)

        XCTAssertEqual(manager.downloads[repo]?.status, .failed)
        XCTAssertFalse(manager.downloads[repo]?.error?.isEmpty ?? true)
        XCTAssertFalse(manager.isBundleDownloading(bundle))
    }

    func testRetryingAComponentKeepsItsBundleFileSelection() async throws {
        let repo = "fixture/media"
        let component = MediaComponent(repo: repo, selection: FileSelection(recursive: true), readyMarkers: ["transformer"])
        let bundle = MediaBundle(id: "media-bundle", displayName: "Media", components: [component], sizeEstimateGB: 1)
        HuggingFaceStubProtocol.serve(repo: repo, files: [
            ("transformer/model.safetensors", Data(repeating: 3, count: 256)),
        ])
        let manager = DownloadManager(modelsRoot: root)
        let first = expectation(description: "media download")
        manager.startBundle(bundle) { first.fulfill() }
        await fulfillment(of: [first], timeout: 10)
        let dir = DownloadManager.newLayoutDir(rootDir: root, repoId: repo)
        try FileManager.default.removeItem(atPath: dir)
        manager.downloads[repo] = .init(status: .failed, error: "Interrupted")

        let retried = expectation(description: "retried media")
        XCTAssertTrue(manager.retry(repoId: repo) { retried.fulfill() })
        await fulfillment(of: [retried], timeout: 10)

        XCTAssertEqual(manager.downloads[repo]?.status, .completed)
        XCTAssertTrue(manager.bundleReady(bundle))
    }

    func testStartingTheSameBundleAgainKeepsTheFirstTransferAlive() async throws {
        let repo = "fixture/shared-download"
        let component = MediaComponent(repo: repo, selection: .chatDefault, readyMarkers: [])
        let bundle = MediaBundle(id: "shared-bundle", displayName: "Shared", components: [component], sizeEstimateGB: 1)
        HuggingFaceStubProtocol.serve(repo: repo, files: [
            ("model.safetensors", Data(repeating: 5, count: 4 << 20)),
        ], throttle: true)
        let manager = DownloadManager(modelsRoot: root)
        let first = expectation(description: "original download")
        let second = expectation(description: "second observer")
        var originalStatus: DownloadManager.DownloadState.Status?
        manager.startBundle(bundle) {
            originalStatus = manager.downloads[repo]?.status
            first.fulfill()
        }
        for _ in 0..<100 where manager.downloads[repo]?.fileIndex != 1 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        manager.startBundle(bundle) { second.fulfill() }
        await fulfillment(of: [first], timeout: 10)
        manager.cancelBundle(bundle)
        await fulfillment(of: [second], timeout: 10)

        XCTAssertEqual(originalStatus, .completed)
    }

    func testRetryRechecksAFailedComponentEvenWhenItsReadyMarkersExist() async throws {
        let repo = "fixture/incomplete-media"
        let firstFile = ("transformer/first.safetensors", Data(repeating: 1, count: 256))
        let missingFile = ("transformer/second.safetensors", Data(repeating: 2, count: 256))
        let component = MediaComponent(repo: repo, selection: FileSelection(recursive: true), readyMarkers: ["transformer"])
        let bundle = MediaBundle(id: "incomplete-media", displayName: "Media", components: [component], sizeEstimateGB: 1)
        HuggingFaceStubProtocol.serve(repo: repo, files: [firstFile])
        let manager = DownloadManager(modelsRoot: root)
        let first = expectation(description: "first file downloaded")
        manager.startBundle(bundle) { first.fulfill() }
        await fulfillment(of: [first], timeout: 10)
        XCTAssertTrue(manager.componentReady(component))
        manager.downloads[repo] = .init(status: .failed, error: "Second file interrupted")
        HuggingFaceStubProtocol.serve(repo: repo, files: [firstFile, missingFile])

        let retried = expectation(description: "missing file downloaded")
        XCTAssertTrue(manager.retry(repoId: repo) { retried.fulfill() })
        await fulfillment(of: [retried], timeout: 10)

        XCTAssertEqual(manager.downloads[repo]?.status, .completed)
        let dir = DownloadManager.newLayoutDir(rootDir: root, repoId: repo)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: (dir as NSString).appendingPathComponent(missingFile.0))), missingFile.1)
    }

    func testDismissingAFailureKeepsPartialFiles() throws {
        let repo = "fixture/partial"
        let manager = DownloadManager(modelsRoot: root)
        let dir = DownloadManager.newLayoutDir(rootDir: root, repoId: repo)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let file = URL(fileURLWithPath: (dir as NSString).appendingPathComponent("model.safetensors.partial"))
        try Data([1, 2, 3]).write(to: file)
        manager.downloads[repo] = .init(status: .failed, error: "Offline")

        manager.dismissDownload(repoId: repo)

        XCTAssertNil(manager.downloads[repo])
        XCTAssertEqual(try Data(contentsOf: file), Data([1, 2, 3]))
    }

    func testFailedDownloadsNeedAttentionWithoutIndicatingActivity() {
        let summary = ModelDownloadSummary(states: [.init(status: .failed), .init(status: .completed)])
        XCTAssertEqual(summary.running, 0)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.completed, 1)
        XCTAssertEqual(summary.pending, 1)
    }
}
