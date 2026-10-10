import XCTest
@testable import MLXCore

final class ChatDeletionRequestTests: XCTestCase {
    private let sessionId = UUID()

    private func user(_ text: String = "question") -> ChatMessage {
        ChatMessage(role: .user, content: text)
    }

    private func reply(_ text: String = "answer") -> ChatMessage {
        ChatMessage(role: .assistant, content: text)
    }

    private func toolRound() -> [ChatMessage] {
        var call = reply("Checking")
        call.toolCalls = [MLXCore.SerializedToolCall(id: "call_1", name: "shell", arguments: "{}")]
        var result = ChatMessage(role: .system, content: "done")
        result.toolCallId = "call_1"
        return [call, result]
    }

    private func request(_ messages: [ChatMessage], at index: Int) -> ChatDeletionRequest? {
        ChatDeletionRequest.make(sessionId: sessionId, messageId: messages[index].id,
                                 messages: messages, turnInFlight: false)
    }

    func testUserMessageRequestKeepsTheReply() throws {
        let messages = [user(), reply()]
        let deletion = try XCTUnwrap(request(messages, at: 0))
        XCTAssertEqual(deletion.sessionId, sessionId)
        XCTAssertEqual(deletion.messageId, messages[0].id)
        XCTAssertEqual(deletion.scope, .message)
        XCTAssertEqual(deletion.messageIds, [messages[0].id])
    }

    func testMessageRangeIncludesFollowingHiddenResultsOnly() throws {
        let messages = [user(), toolRound()[1], reply(), user("next")]
        let deletion = try XCTUnwrap(request(messages, at: 0))
        XCTAssertEqual(ChatDeletionRequest.messageRange(at: 0, in: messages), 0..<2)
        XCTAssertEqual(ChatDeletionRequest.messageRange(at: 2, in: messages), 2..<3)
        XCTAssertEqual(deletion.messageIds, messages[..<2].map(\.id))
        XCTAssertNotEqual(deletion.explanation, request([messages[0], messages[2]], at: 0)?.explanation)
    }

    func testReplyRequestIncludesItsToolStepsButKeepsPreviousBoundary() throws {
        let messages = [user(), reply("earlier answer")] + toolRound() + [reply()]
        let deletion = try XCTUnwrap(request(messages, at: messages.count - 1))
        XCTAssertEqual(deletion.scope, .turn)
        XCTAssertEqual(deletion.messageIds, messages[2...].map(\.id))
    }

    func testInterruptedTurnRequestIncludesTheHiddenResult() throws {
        let messages = [user()] + toolRound()
        let deletion = try XCTUnwrap(request(messages, at: messages.count - 1))
        XCTAssertEqual(deletion.scope, .turn)
        XCTAssertEqual(deletion.messageIds, messages[1...].map(\.id))
    }

    func testToolCallInsideATurnIsNotADeletionBoundary() {
        let messages = [user()] + toolRound() + [reply()]
        XCTAssertNil(request(messages, at: 1))
    }

    func testCancelResolvesToNoDeletion() throws {
        let messages = [user(), reply()]
        let deletion = try XCTUnwrap(request(messages, at: 1))
        XCTAssertNil(deletion.resolve(confirmed: false, in: sessionId,
                                      messages: messages, turnInFlight: false))
    }

    func testConfirmResolvesTheCapturedTarget() throws {
        let messages = [user(), reply()]
        let deletion = try XCTUnwrap(request(messages, at: 1))
        XCTAssertEqual(deletion.resolve(confirmed: true, in: sessionId,
                                       messages: messages, turnInFlight: false), deletion)
    }

    func testChangingChatsCancelsEvenWhenTheSameMessageIsPresent() throws {
        let messages = [user(), reply()]
        let deletion = try XCTUnwrap(request(messages, at: 1))
        XCTAssertNil(deletion.resolve(confirmed: true, in: UUID(),
                                      messages: messages, turnInFlight: false))
    }

    func testMissingTargetDoesNotDeleteItsReplacement() throws {
        let question = user()
        let deletion = try XCTUnwrap(request([question, reply()], at: 1))
        XCTAssertNil(deletion.resolve(confirmed: true, in: sessionId,
                                      messages: [question, reply()], turnInFlight: false))
        XCTAssertNil(ChatDeletionRequest.make(sessionId: sessionId, messageId: UUID(),
                                             messages: [question], turnInFlight: false))
    }

    func testChangedTurnScopeRequiresANewConfirmation() throws {
        let messages = [user()] + toolRound() + [reply()]
        let deletion = try XCTUnwrap(request(messages, at: messages.count - 1))
        var changed = messages
        changed.insert(ChatMessage(role: .assistant, content: "", reasoningContent: "more"), at: 1)
        XCTAssertNil(deletion.resolve(confirmed: true, in: sessionId,
                                      messages: changed, turnInFlight: false))
        changed = messages
        changed.remove(at: 2)
        XCTAssertNil(deletion.resolve(confirmed: true, in: sessionId,
                                      messages: changed, turnInFlight: false))
    }

    func testLaterMessagesDoNotChangeACompletedReplyScope() throws {
        let messages = [user(), reply()]
        let deletion = try XCTUnwrap(request(messages, at: 1))
        XCTAssertEqual(deletion.resolve(confirmed: true, in: sessionId,
                                       messages: messages + [user("next"), reply("next answer")],
                                       turnInFlight: false), deletion)
    }

    func testActiveTurnCannotBeRequestedOrConfirmed() throws {
        let messages = [user(), reply()]
        let deletion = try XCTUnwrap(request(messages, at: 1))
        XCTAssertNil(ChatDeletionRequest.make(sessionId: sessionId, messageId: messages[1].id,
                                             messages: messages, turnInFlight: true))
        XCTAssertNil(deletion.resolve(confirmed: true, in: sessionId,
                                      messages: messages, turnInFlight: true))
    }

    func testStreamingTargetCannotBeRequestedEvenWithoutAnActiveTurn() {
        var streaming = reply()
        streaming.isStreaming = true
        XCTAssertNil(request([user(), streaming], at: 1))
    }
}
