import XCTest
@testable import MLXCore

@MainActor
final class MediaInteractionHistoryTests: XCTestCase {
    private var messages: [UUID: [ChatMessage]] = [:]
    private var saves = 0
    private var cancellations: [MediaModality] = []

    private func tracker() -> MediaInteractionHistory {
        MediaInteractionHistory(append: { [unowned self] id, batch in
            messages[id, default: []].append(contentsOf: batch)
        }, save: { [unowned self] in
            saves += 1
        }, cancel: { [unowned self] modality in
            cancellations.append(modality)
        })
    }

    @discardableResult
    private func prepare(_ history: MediaInteractionHistory, _ modality: MediaModality,
                         sessionId: UUID, prompt: String) -> Bool {
        history.reserve(modality, sessionId: sessionId, prompt: prompt)?.begin(prompt) ?? false
    }

    func testVideoOutputRemainsInItsOriginatingSessionAfterSwitchingModels() throws {
        let history = tracker()
        let videoSession = UUID()
        let nextSession = UUID()
        XCTAssertTrue(prepare(history, .video, sessionId: videoSession, prompt: "A cloud passes"))
        history.receive(.running(step: 0, total: 30, message: "Loading"), for: .video)
        XCTAssertTrue(prepare(history, .image, sessionId: nextSession, prompt: "A blue sky"))
        history.receive(.running(step: 12, total: 30, message: "Rendering"), for: .video)

        XCTAssertEqual(history.progress(for: videoSession).first?.step, 12)
        XCTAssertFalse(history.progress(for: nextSession).contains { $0.modality == .video })
        history.receive(.completed(path: "/tmp/video.mp4"), for: .video)

        let transcript = try XCTUnwrap(messages[videoSession])
        XCTAssertEqual(transcript.map(\.role), [.user, .assistant])
        XCTAssertEqual(transcript.first?.content, "A cloud passes")
        XCTAssertEqual(transcript.last?.media?.first?.path, "/tmp/video.mp4")
        XCTAssertEqual(transcript.last?.media?.first?.prompt, "A cloud passes")
        XCTAssertNil(messages[nextSession])
        XCTAssertTrue(history.progress(for: videoSession).isEmpty)
        XCTAssertEqual(saves, 2)
    }

    func testPreparationWaitsForGenerationAndProgressDoesNotDuplicateThePrompt() {
        let history = tracker()
        let session = UUID()
        prepare(history, .video, sessionId: session, prompt: "Wait for confirmation")
        XCTAssertTrue(messages.isEmpty)
        XCTAssertEqual(saves, 0)
        history.receive(.running(step: 0, total: 20, message: "Loading"), for: .video)
        history.receive(.running(step: 1, total: 20, message: "Rendering"), for: .video)
        XCTAssertEqual(messages[session]?.count, 1)
        XCTAssertEqual(saves, 1)
        XCTAssertFalse(prepare(history, .video, sessionId: UUID(), prompt: "Another request"))
    }

    func testEveryGenerationTypePersistsAReferencedOutput() throws {
        let history = tracker()
        for modality in MediaModality.allCases {
            let session = UUID()
            prepare(history, modality, sessionId: session, prompt: "Input")
            history.receive(.running(step: 0, total: 1, message: "Starting"), for: modality)
            history.receive(.completed(path: "/tmp/output-\(modality)"), for: modality)
            let transcript = try XCTUnwrap(messages[session])
            let stored = try JSONEncoder().encode(transcript)
            let loaded = try JSONDecoder().decode([ChatMessage].self, from: stored)
            XCTAssertEqual(loaded.last?.media?.first?.path, "/tmp/output-\(modality)")
            XCTAssertEqual(loaded.first?.role, .user)
            XCTAssertEqual(loaded.last?.role, .assistant)
        }
    }

    func testCancellationTargetsTheOriginalRunAndSurfacesInItsTranscript() {
        let history = tracker()
        let session = UUID()
        prepare(history, .video, sessionId: session, prompt: "Video")
        history.receive(.running(step: 1, total: 20, message: "Rendering"), for: .video)
        history.cancel(sessionId: UUID())
        XCTAssertTrue(cancellations.isEmpty)
        history.cancel(sessionId: session)
        XCTAssertEqual(cancellations, [.video])
        XCTAssertTrue(history.progress(for: session).isEmpty)
        XCTAssertEqual(messages[session]?.last?.content, "Generation stopped.")
        history.receive(.cancelled, for: .video)
        XCTAssertEqual(messages[session]?.count, 2)
    }

    func testFailureKeepsThePromptAndCannotBeReplacedByALateCompletion() {
        let history = tracker()
        let session = UUID()
        prepare(history, .image, sessionId: session, prompt: "A lake")
        history.receive(.running(step: 1, total: 8, message: "Generating"), for: .image)
        history.receive(.failed("Out of memory"), for: .image)
        history.receive(.completed(path: "/tmp/stale.png"), for: .image)
        XCTAssertEqual(messages[session]?.count, 2)
        XCTAssertEqual(messages[session]?.last?.errorNotice?.message, "Out of memory")
        XCTAssertNil(messages[session]?.last?.media)
        XCTAssertTrue(history.progress(for: session).isEmpty)
    }

    func testUnownedServiceEventsDoNotCreateConversationMessages() {
        let history = tracker()
        history.receive(.running(step: 0, total: 20, message: "Loading"), for: .video)
        history.receive(.completed(path: "/tmp/existing.mp4"), for: .video)
        XCTAssertTrue(messages.isEmpty)
        XCTAssertEqual(saves, 0)
    }

    func testPendingGenerationReservesItsModalityForTheOriginalSession() throws {
        let history = tracker()
        let first = UUID()
        let second = UUID()
        let submission = try XCTUnwrap(history.reserve(.video, sessionId: first, prompt: "First video"))
        XCTAssertNil(history.reserve(.video, sessionId: second, prompt: "Second video"))
        XCTAssertEqual(history.progress(for: first).count, 1)
        XCTAssertTrue(history.progress(for: second).isEmpty)
        XCTAssertTrue(messages.isEmpty)
        XCTAssertTrue(submission.begin("First video"))
        history.receive(.running(step: 0, total: 20, message: "Loading"), for: .video)
        history.receive(.completed(path: "/tmp/first.mp4"), for: .video)
        XCTAssertEqual(messages[first]?.last?.media?.first?.prompt, "First video")
        XCTAssertNil(messages[second])
    }

    func testActualRequestPromptIncludesFinalizedDictation() throws {
        let history = tracker()
        let session = UUID()
        let submission = try XCTUnwrap(history.reserve(.voice, sessionId: session, prompt: "Please read"))
        XCTAssertTrue(submission.begin("Please read the final words"))
        XCTAssertFalse(submission.begin("Cannot start the same request twice"))
        history.receive(.running(step: 0, total: 0, message: "Synthesizing"), for: .voice)
        history.receive(.completed(path: "/tmp/voice.wav"), for: .voice)
        XCTAssertEqual(messages[session]?.first?.content, "Please read the final words")
        XCTAssertEqual(messages[session]?.last?.media?.first?.prompt, "Please read the final words")
    }

    func testDiscardedConfirmationInvalidatesLateCallbacksWithoutCancellingAnotherRequest() throws {
        let history = tracker()
        let first = UUID()
        let second = UUID()
        let abandoned = try XCTUnwrap(history.reserve(.video, sessionId: first, prompt: "Abandoned"))
        abandoned.discard()
        let current = try XCTUnwrap(history.reserve(.video, sessionId: second, prompt: "Current"))
        XCTAssertFalse(abandoned.begin("Abandoned"))
        abandoned.discard()
        XCTAssertTrue(current.begin("Current"))
        history.receive(.running(step: 0, total: 20, message: "Loading"), for: .video)
        current.discard()
        XCTAssertEqual(history.progress(for: second).count, 1)
        XCTAssertEqual(messages[second]?.first?.content, "Current")
        XCTAssertNil(messages[first])
        XCTAssertTrue(cancellations.isEmpty)
    }

    func testDeletingSessionInvalidatesPendingDownloadCallback() throws {
        let history = tracker()
        let session = UUID()
        let submission = try XCTUnwrap(history.reserve(.video, sessionId: session, prompt: "A clip"))
        history.cancel(sessionId: session)
        XCTAssertFalse(submission.begin("A clip"))
        XCTAssertTrue(history.progress(for: session).isEmpty)
        XCTAssertTrue(messages.isEmpty)
        XCTAssertTrue(cancellations.isEmpty)
    }

    func testComposerCanOnlyCancelItsOwnGeneration() throws {
        let history = tracker()
        let owner = UUID()
        let other = UUID()
        XCTAssertEqual(history.composerState(modality: .video, sessionId: owner, serviceIsRunning: false), .idle)
        let submission = try XCTUnwrap(history.reserve(.video, sessionId: owner, prompt: "A clip"))
        XCTAssertEqual(history.composerState(modality: .video, sessionId: owner, serviceIsRunning: false), .preparingHere)
        XCTAssertTrue(history.composerState(modality: .video, sessionId: owner, serviceIsRunning: false).canCancel)
        XCTAssertEqual(history.composerState(modality: .video, sessionId: other, serviceIsRunning: false), .busyElsewhere)
        XCTAssertFalse(history.composerState(modality: .video, sessionId: other, serviceIsRunning: false).canCancel)
        XCTAssertTrue(submission.begin("A clip"))
        history.receive(.running(step: 0, total: 20, message: "Loading"), for: .video)
        XCTAssertEqual(history.composerState(modality: .video, sessionId: owner, serviceIsRunning: true), .generatingHere)
        XCTAssertFalse(history.composerState(modality: .video, sessionId: other, serviceIsRunning: true).canCancel)
        history.cancel(sessionId: owner)
        XCTAssertEqual(history.composerState(modality: .video, sessionId: owner, serviceIsRunning: true), .busyElsewhere)
        XCTAssertFalse(history.composerState(modality: .video, sessionId: owner, serviceIsRunning: true).canCancel)
        XCTAssertEqual(history.composerState(modality: .video, sessionId: owner, serviceIsRunning: false), .idle)
    }

    func testServiceEventsCannotConsumeAReservationBeforeItsStartCallback() throws {
        let history = tracker()
        let session = UUID()
        let submission = try XCTUnwrap(history.reserve(.image, sessionId: session, prompt: "Current"))
        history.receive(.running(step: 3, total: 8, message: "Unrelated"), for: .image)
        history.receive(.completed(path: "/tmp/unrelated.png"), for: .image)
        XCTAssertTrue(messages.isEmpty)
        XCTAssertTrue(submission.begin("Current"))
        history.receive(.running(step: 0, total: 8, message: "Current"), for: .image)
        XCTAssertEqual(messages[session]?.first?.content, "Current")
    }

    func testStoppingOneMediaRowLeavesAnotherGenerationRunning() {
        let history = tracker()
        let session = UUID()
        prepare(history, .image, sessionId: session, prompt: "A still image")
        prepare(history, .video, sessionId: session, prompt: "A moving scene")
        history.receive(.running(step: 3, total: 8, message: "Generating"), for: .image)
        history.receive(.running(step: 2, total: 20, message: "Rendering"), for: .video)
        history.cancel(modality: .video, sessionId: UUID())
        XCTAssertTrue(cancellations.isEmpty)
        history.cancel(modality: .video, sessionId: session)
        XCTAssertEqual(cancellations, [.video])
        XCTAssertEqual(history.progress(for: session).map(\.modality), [.image])
        XCTAssertEqual(history.progress(for: session).first?.step, 3)
        XCTAssertEqual(messages[session]?.count, 3)
        history.receive(.completed(path: "/tmp/still.png"), for: .image)
        XCTAssertEqual(messages[session]?.last?.media?.first?.path, "/tmp/still.png")
    }
}
