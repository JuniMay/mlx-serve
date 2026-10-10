import Foundation

enum InteractionTurnActions {
    static func canReplayChat(messages: [ChatMessage], activeMedia: MediaModality?) -> Bool {
        guard activeMedia == nil, messages.contains(where: { $0.role == .user }) else { return false }
        guard let reply = messages.last(where: { $0.role == .assistant }) else { return true }
        return reply.media?.isEmpty != false
            || !reply.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
