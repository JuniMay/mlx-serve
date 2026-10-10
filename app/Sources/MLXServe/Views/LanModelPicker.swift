import SwiftUI

/// Identity helpers for local and network media models. The persisted `modelId` is a
/// string: a preset id for local models, `"lan:<model>@<peer>"` for network
/// ones — the suffix form the local server proxies to the hosting Mac.
enum LanPick {
    static let prefix = "lan:"

    /// The LAN routing id inside a selection/persisted value, or nil for locals.
    static func lanId(_ value: String) -> String? {
        value.hasPrefix(prefix) ? String(value.dropFirst(prefix.count)) : nil
    }

    /// The checkpoint that determines the controls for a saved model selection.
    static func modelID(_ selection: String) -> String {
        lanId(selection).map { base(of: $0) } ?? selection
    }

    /// The `modelId` to persist for the current pane state.
    static func persisted(lanModel: String?, presetId: String) -> String {
        lanModel.map { prefix + $0 } ?? presetId
    }

    /// The peer name inside a LAN routing id ("model@peer" → "peer").
    static func peer(of id: String) -> String {
        guard let at = id.lastIndex(of: "@") else { return id }
        return String(id[id.index(after: at)...])
    }

    /// `peer(of:)`'s mirror: the model id without the peer suffix.
    static func base(of id: String) -> String {
        guard let at = id.lastIndex(of: "@") else { return id }
        return String(id[..<at])
    }

}
