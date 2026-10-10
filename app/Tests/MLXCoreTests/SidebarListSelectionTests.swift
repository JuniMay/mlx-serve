import XCTest
@testable import MLXCore

final class SidebarListSelectionTests: XCTestCase {
    private let first = UUID()
    private let second = UUID()

    func testSelectingADestinationReplacesTheConversationSelection() {
        let result = SidebarListSelection.resolve(
            proposed: [.chat(first), .models], previous: [.chat(first)],
            orderedChats: [first, second], activeChat: first)
        XCTAssertEqual(result.items, [.models])
        XCTAssertEqual(result.destination, .models)
        XCTAssertTrue(result.chats.isEmpty)
    }

    func testSelectingAChatLeavesThePreviousDestination() {
        let result = SidebarListSelection.resolve(
            proposed: [.models, .chat(second)], previous: [.models],
            orderedChats: [first, second], activeChat: first)
        XCTAssertEqual(result.items, [.chat(second)])
        XCTAssertEqual(result.chats, [second])
        XCTAssertEqual(result.activeChat, second)
        XCTAssertNil(result.destination)
    }

    func testCommandSelectionRetainsAllChatsAndActivatesTheAddedChat() {
        let result = SidebarListSelection.resolve(
            proposed: [.chat(first), .chat(second)], previous: [.chat(first)],
            orderedChats: [first, second], activeChat: first)
        XCTAssertEqual(result.chats, [first, second])
        XCTAssertEqual(result.activeChat, second)
    }

    func testDeselectingTheActiveChatActivatesASurvivingChat() {
        let result = SidebarListSelection.resolve(
            proposed: [.chat(first)], previous: [.chat(first), .chat(second)],
            orderedChats: [first, second], activeChat: second)
        XCTAssertEqual(result.activeChat, first)
    }

    func testClearingSelectionDoesNotInventANavigationRequest() {
        let result = SidebarListSelection.resolve(
            proposed: [], previous: [.chat(first)],
            orderedChats: [first, second], activeChat: first)
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertNil(result.activeChat)
        XCTAssertNil(result.destination)
    }

    func testTerminalSelectionCannotJoinAChatDeletionSelection() {
        let terminal = UUID()
        let result = SidebarListSelection.resolve(
            proposed: [.chat(first), .terminal(terminal)], previous: [.chat(first)],
            orderedChats: [first, second], activeChat: first)
        XCTAssertEqual(result.items, [.terminal(terminal)])
        XCTAssertTrue(result.chats.isEmpty)
        XCTAssertEqual(result.destination, .terminal(terminal))
    }

    func testShiftSelectionIgnoresDestinationsCrossedBetweenChatRows() {
        let result = SidebarListSelection.resolve(
            proposed: [.models, .chat(first), .chat(second)], previous: [.chat(second)],
            orderedChats: [first, second], activeChat: second)
        XCTAssertEqual(result.items, [.chat(first), .chat(second)])
        XCTAssertEqual(result.activeChat, first)
    }

    func testExtendingARangeUpwardActivatesItsFirstRow() {
        let third = UUID(), fourth = UUID()
        let result = SidebarListSelection.resolve(
            proposed: [.chat(first), .chat(second), .chat(third), .chat(fourth)],
            previous: [.chat(fourth)],
            orderedChats: [first, second, third, fourth], activeChat: fourth)
        XCTAssertEqual(result.activeChat, first)
        XCTAssertEqual(result.chats, [first, second, third, fourth])
    }

    func testExtendingARangeDownwardActivatesItsLastRow() {
        let third = UUID(), fourth = UUID()
        let result = SidebarListSelection.resolve(
            proposed: [.chat(first), .chat(second), .chat(third), .chat(fourth)],
            previous: [.chat(first)],
            orderedChats: [first, second, third, fourth], activeChat: first)
        XCTAssertEqual(result.activeChat, fourth)
    }
}
