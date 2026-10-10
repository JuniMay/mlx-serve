import XCTest
@testable import MLXCore

final class ChatWindowPresentationTests: XCTestCase {
    func testDetailTitleNamesTheConversationBeforeItsAgent() {
        XCTAssertEqual(ChatWindowPresentation.conversationTitle(
            title: "Fix the login bug", agentName: "Coder"), "Fix the login bug")
        XCTAssertEqual(ChatWindowPresentation.conversationTitle(
            title: "New agent", agentName: "Coder"), "Coder")
        XCTAssertEqual(ChatWindowPresentation.conversationTitle(
            title: "New Chat", agentName: nil), "New Chat")
        XCTAssertEqual(ChatWindowPresentation.conversationTitle(
            title: nil, agentName: nil), "New Chat")
    }

    func testBranchUsesTheLastCompleteBoundaryAfterToolWork() {
        let question = ChatMessage(role: .user, content: "List the files")
        let answer = ChatMessage(role: .assistant, content: "Two files")
        var tool = ChatMessage(role: .assistant, content: "Checking one more file")
        tool.toolCalls = [MLXCore.SerializedToolCall(id: "call", name: "readFile", arguments: "{}")]
        var result = ChatMessage(role: .system, content: "file data")
        result.toolCallId = "call"
        let messages = [question, answer, tool, result]
        XCTAssertEqual(ChatWindowPresentation.branchMessageID(
            messages: messages, turnInFlight: false), answer.id)
        guard let cut = ChatWindowPresentation.branchMessageID(messages: messages, turnInFlight: false) else {
            return XCTFail("A completed answer must be available for branching")
        }
        XCTAssertEqual(ChatFork.prefix(messages, through: cut).map(\.id), [question.id, answer.id])
    }

    func testBranchDeclinesRunningTurnsAndIncompleteMessages() {
        let question = ChatMessage(role: .user, content: "Hello")
        var streaming = ChatMessage(role: .assistant, content: "Partial")
        streaming.isStreaming = true
        XCTAssertNil(ChatWindowPresentation.branchMessageID(
            messages: [question, streaming], turnInFlight: true))
        XCTAssertEqual(ChatWindowPresentation.branchMessageID(
            messages: [question, streaming], turnInFlight: false), question.id)
        XCTAssertNil(ChatWindowPresentation.branchMessageID(messages: [], turnInFlight: false))
        XCTAssertNil(ChatWindowPresentation.branchMessageID(
            messages: [ChatMessage(role: .system, content: "Instructions")], turnInFlight: false))
    }
}
