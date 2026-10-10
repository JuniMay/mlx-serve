import Foundation

/// Which single row of the sidebar is lit.
enum SidebarSelection {

    static func isConversationSelected(sessionId: UUID,
                                       activeChatId: UUID?,
                                       workspace: ChatWorkspace) -> Bool {
        workspace.isConversation && sessionId == activeChatId
    }
}

enum SidebarItem: Hashable {
    case models, agents, tasks
    case create(GenExperiment)
    case chat(UUID)
    case terminal(UUID)

    var chatID: UUID? {
        if case .chat(let id) = self { return id }
        return nil
    }
}

/// Destinations are exclusive; only conversations participate in bulk actions.
enum SidebarListSelection {
    struct Outcome {
        var items: Set<SidebarItem>
        var chats: Set<UUID>
        var activeChat: UUID?
        var destination: SidebarItem?
    }

    static func resolve(proposed: Set<SidebarItem>, previous: Set<SidebarItem>,
                        orderedChats: [UUID], activeChat: UUID?) -> Outcome {
        let added = proposed.subtracting(previous)
        let addedChats = Set(added.compactMap(\.chatID))
        if addedChats.isEmpty,
           let destination = added.first(where: { $0.chatID == nil }) {
            return Outcome(items: [destination], chats: [], destination: destination)
        }
        let chats = Set(proposed.compactMap(\.chatID))
        if !chats.isEmpty {
            let addedInOrder = orderedChats.filter(addedChats.contains)
            let extendsUpward = activeChat.flatMap { orderedChats.firstIndex(of: $0) }
                .map { origin in
                    addedInOrder.allSatisfy { orderedChats.firstIndex(of: $0)! < origin }
                } ?? false
            let endpoint = extendsUpward ? addedInOrder.first : addedInOrder.last
            let active = endpoint
                ?? activeChat.flatMap { chats.contains($0) ? $0 : nil }
                ?? orderedChats.first(where: chats.contains)
            return Outcome(items: Set(chats.map(SidebarItem.chat)), chats: chats,
                           activeChat: active)
        }
        let destination = proposed.first
        return Outcome(items: destination.map { [$0] } ?? [], chats: [],
                       destination: destination)
    }
}
