import XCTest
@testable import MLXCore

final class InteractionTurnActionsTests: XCTestCase {
    private let textMessages = [ChatMessage(role: .user, content: "Explain this"),
                                ChatMessage(role: .assistant, content: "An explanation")]

    func testSelectedMediaCapabilitiesCannotReplayThePromptAsChat() {
        for modality in MediaModality.allCases {
            XCTAssertFalse(InteractionTurnActions.canReplayChat(
                messages: textMessages, activeMedia: modality), "\(modality)")
        }
    }

    func testDirectMediaOutputCannotBeRegeneratedAsChatAfterSwitchingBack() {
        for kind in [ChatMediaRef.Kind.image, .audio, .video, .model3D] {
            var response = ChatMessage(role: .assistant, content: " \n")
            response.media = [ChatMediaRef(kind: kind, path: "/tmp/output", prompt: "Make this")]
            XCTAssertFalse(InteractionTurnActions.canReplayChat(
                messages: [textMessages[0], response], activeMedia: nil), "\(kind)")
        }
    }

    func testNormalChatRemainsReplayableIncludingRepliesWithToolAttachments() {
        XCTAssertTrue(InteractionTurnActions.canReplayChat(messages: textMessages, activeMedia: nil))
        var response = textMessages[1]
        response.media = [ChatMediaRef(kind: .image, path: "/tmp/tool.png", prompt: "A diagram")]
        XCTAssertTrue(InteractionTurnActions.canReplayChat(
            messages: [textMessages[0], response], activeMedia: nil))
    }

    func testEarlierMediaDoesNotPreventReplayingTheLatestTextReply() {
        var response = ChatMessage(role: .assistant, content: "")
        response.media = [ChatMediaRef(kind: .video, path: "/tmp/video.mp4", prompt: "A cloud")]
        XCTAssertTrue(InteractionTurnActions.canReplayChat(
            messages: [textMessages[0], response] + textMessages, activeMedia: nil))
    }

    func testAConversationWithoutAUserPromptCannotReplay() {
        XCTAssertFalse(InteractionTurnActions.canReplayChat(messages: [], activeMedia: nil))
        XCTAssertFalse(InteractionTurnActions.canReplayChat(messages: [textMessages[1]], activeMedia: nil))
    }
}
