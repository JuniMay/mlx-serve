import Foundation

/// Sidebar destinations in the same order as the Settings form.
enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case general
    case modelFolders
    case server
    case lanSharing
    case providers
    case memory
    case cache
    case performance
    case specDecode
    case engines
    case requestDefaults
    case appearance
    case voice
    case tools
    case sandbox
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .modelFolders: return "Model Folders"
        case .server: return "Server"
        case .lanSharing: return "LAN Sharing"
        case .providers: return "Providers"
        case .memory: return "Memory"
        case .cache: return "Cache"
        case .performance: return "Performance"
        case .specDecode: return "Speculative Decoding"
        case .engines: return "Engines"
        case .requestDefaults: return "Generation Defaults"
        case .appearance: return "Appearance"
        case .voice: return "Voice"
        case .tools: return "Tools & MCP"
        case .sandbox: return "Agent Sandbox"
        case .about: return "About MLX-Serve"
        }
    }

    var sidebarLabel: String { title }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .modelFolders: return "folder"
        case .server: return "server.rack"
        case .lanSharing: return "antenna.radiowaves.left.and.right"
        case .providers: return "cloud"
        case .memory: return "memorychip"
        case .cache: return "internaldrive"
        case .performance: return "speedometer"
        case .specDecode: return "hare"
        case .engines: return "engine.combustion"
        case .requestDefaults: return "slider.horizontal.3"
        case .appearance: return "paintbrush"
        case .voice: return "waveform"
        case .tools: return "wrench.and.screwdriver"
        case .sandbox: return "shield.lefthalf.filled"
        case .about: return "info.circle"
        }
    }

    /// Categories remain stable; their rows describe the engines they configure.
    static func visible(engine: ServerEngine?, selfUpdate: Bool) -> [SettingsCategory] { allCases }
}

/// One category while browsing, or all categories while searching.
///
/// INVARIANT — a selection and search text never coexist. Typing in the filter
/// forces this back to `.all` (`afterQueryEdit`), and picking a category clears
/// the field. Without that, you could select "Server" while a stale query still
/// narrowed its rows and be shown an empty pane with nothing explaining why.
enum SettingsSelection: Hashable {
    case all
    case category(SettingsCategory)

    static let initial: SettingsSelection = .category(.general)

    /// Should the section for `category` render?
    func shows(_ category: SettingsCategory) -> Bool {
        switch self {
        case .all:               return true
        case .category(let c):   return c == category
        }
    }

    /// Search spans every category. Clearing search returns to General unless
    /// choosing a category was what cleared the field.
    static func afterQueryEdit(query: String, current: SettingsSelection) -> SettingsSelection {
        guard SettingsSearch.tokens(query).isEmpty else { return .all }
        return current == .all ? .initial : current
    }

    /// Ordinary reopening keeps the current pane; recovery actions name their destination.
    static func afterOpen(requested: SettingsCategory?, current: SettingsSelection,
                          visible: [SettingsCategory]) -> SettingsSelection {
        reconciled(requested.map(SettingsSelection.category) ?? current, visible: visible)
    }

    /// Restore a visible destination when a requested category is unavailable.
    static func reconciled(_ selection: SettingsSelection, visible: [SettingsCategory]) -> SettingsSelection {
        switch selection {
        case .all:
            return .all
        case .category(let c):
            return visible.contains(c) ? selection : .initial
        }
    }
}
