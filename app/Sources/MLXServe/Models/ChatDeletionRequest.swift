import Foundation

/// Confirmation names a stable transcript segment, not the view's current row.
struct ChatDeletionRequest: Equatable {
    enum Scope: Equatable { case message, turn }

    let sessionId: UUID
    let messageId: UUID
    let scope: Scope
    let messageIds: [UUID]

    var title: String { scope == .message ? "Delete Message?" : "Delete Turn?" }
    var actionLabel: String { scope == .message ? "Delete Message" : "Delete Turn" }
    var explanation: String {
        switch scope {
        case .message:
            if messageIds.count > 1 {
                return "This deletes your message, its associated tool results, and their attachments from this chat. Replies will remain. This can't be undone."
            }
            return "This deletes your message and its attachments from this chat. Replies will remain. This can't be undone."
        case .turn:
            return "This deletes the selected response or interrupted turn, including its preceding thinking and tool steps and their attachments. Your messages and earlier responses will remain. Completed tool actions are not undone. This can't be undone."
        }
    }

    static func make(sessionId: UUID, messageId: UUID, messages: [ChatMessage],
                     turnInFlight: Bool) -> Self? {
        guard !turnInFlight,
              let index = messages.firstIndex(where: { $0.id == messageId }),
              !messages[index].isStreaming else { return nil }
        let scope: Scope
        let range: Range<Int>
        if messages[index].role == .user {
            scope = .message
            range = messageRange(at: index, in: messages)
        } else {
            guard ChatTurn.footerDeletes(messages[index], isLast: index == messages.count - 1),
                  let turn = ChatTurn.deletionRange(endingAt: messageId, in: messages)
            else { return nil }
            scope = .turn
            range = turn
        }
        guard !messages[range].contains(where: \.isStreaming) else { return nil }
        return Self(sessionId: sessionId, messageId: messageId, scope: scope,
                    messageIds: messages[range].map(\.id))
    }

    func resolve(confirmed: Bool, in currentSessionId: UUID, messages: [ChatMessage],
                 turnInFlight: Bool) -> Self? {
        guard confirmed, currentSessionId == sessionId,
              Self.make(sessionId: sessionId, messageId: messageId, messages: messages,
                        turnInFlight: turnInFlight) == self else { return nil }
        return self
    }

    static func messageRange(at index: Int, in messages: [ChatMessage]) -> Range<Int> {
        var end = index + 1
        while end < messages.count, messages[end].toolCallId != nil { end += 1 }
        return index..<end
    }
}
