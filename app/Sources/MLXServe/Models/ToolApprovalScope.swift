import Foundation

struct ToolApprovalScope: Equatable, Sendable {
    let sessionID: UUID
    let turnID: UUID

    func isCurrent(sessionID: UUID, turnID: UUID?, plainChat: Bool) -> Bool {
        !plainChat && self.sessionID == sessionID && self.turnID == turnID
    }
}
