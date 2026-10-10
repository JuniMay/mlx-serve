import XCTest
@testable import MLXCore

final class ToolApprovalScopeTests: XCTestCase {
    private let sessionID = UUID()
    private let turnID = UUID()

    func testApprovalBelongsToItsLiveConversationAndTurn() {
        let scope = ToolApprovalScope(sessionID: sessionID, turnID: turnID)
        XCTAssertTrue(scope.isCurrent(sessionID: sessionID, turnID: turnID, plainChat: false))
    }

    func testChangingConversationCannotTransferApproval() {
        let scope = ToolApprovalScope(sessionID: sessionID, turnID: turnID)
        XCTAssertFalse(scope.isCurrent(sessionID: UUID(), turnID: turnID, plainChat: false))
    }

    func testSupersededTurnCannotApproveItsSuccessor() {
        let scope = ToolApprovalScope(sessionID: sessionID, turnID: turnID)
        XCTAssertFalse(scope.isCurrent(sessionID: sessionID, turnID: UUID(), plainChat: false))
    }

    func testStoppedOrFinishedTurnCannotBeApproved() {
        let scope = ToolApprovalScope(sessionID: sessionID, turnID: turnID)
        XCTAssertFalse(scope.isCurrent(sessionID: sessionID, turnID: nil, plainChat: false))
    }

    func testPlainChatRevokesAnOtherwiseCurrentApproval() {
        let scope = ToolApprovalScope(sessionID: sessionID, turnID: turnID)
        XCTAssertFalse(scope.isCurrent(sessionID: sessionID, turnID: turnID, plainChat: true))
    }
}
