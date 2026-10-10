import Foundation

/// The content displayed in the main window.
enum ChatWorkspace: Equatable {
    /// The transcript for `AppState.activeChatId`.
    case conversation
    /// The model browser, on one of its sections.
    case models(ModelBrowserSection)
    /// A media workspace from the shared generation catalog.
    case create(GenExperiment)
    /// Scheduled and on-demand agent tasks.
    case tasks
    /// The agent list and editor.
    case agents
    /// App settings presented within the main window.
    case settings
    /// A terminal session listed beside conversations.
    case terminal(UUID)

    var isModels: Bool {
        if case .models = self { return true }
        return false
    }

    var isAgents: Bool { self == .agents }

    /// Whether the main pane includes a secondary item list beside its detail.
    var isThreeColumn: Bool { self == .tasks || isAgents }

    /// The terminal being shown, or nil outside terminal mode.
    var terminalId: UUID? {
        if case .terminal(let id) = self { return id }
        return nil
    }

    /// The transcript — the only mode the chat gate may cover.
    var isConversation: Bool { self == .conversation }

    /// The section being browsed, or nil in conversation mode.
    var section: ModelBrowserSection? {
        if case .models(let section) = self { return section }
        return nil
    }

    /// The starting section for a browse-models request.
    static let defaultEntry: ChatWorkspace = .models(.recommended)

    /// Chat setup yields to other sheets and to available non-chat workspaces.
    static func gateShouldPresent(gateIsBlocking: Bool,
                                  cancelled: Bool,
                                  workspace: ChatWorkspace,
                                  welcomePresented: Bool,
                                  palettePresented: Bool = false,
                                  otherInteractionAvailable: Bool = false) -> Bool {
        gateIsBlocking && !cancelled && !otherInteractionAvailable && workspace.isConversation
            && !welcomePresented && !palettePresented
    }
}
