import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import AppKit
import SwaTexRender

/// A tool-call awaiting user approval. The agent loop suspends on
/// `continuation` while the SwiftUI sheet shows the request; the sheet's
/// buttons resume it with the user's choice.
struct ToolApprovalRequest: Identifiable {
    let id = UUID()
    let toolName: String
    let arguments: [String: String]
    /// Raw JSON arguments — used when `arguments` is the post-parse dict but
    /// we want to display the verbatim JSON (handy for nested objects /
    /// arrays the dict-flattening loses).
    let rawArguments: String
    let continuation: CheckedContinuation<ToolApprovalChoice, Never>
    var scope: ToolApprovalScope? = nil
}

enum ToolApprovalChoice {
    case allow
    case deny
}

/// Sheet body. Renders the tool name, a pretty-printed argument block, and
/// three buttons. Allow / Deny resume the continuation with that choice;
/// Always Allow flips a per-session flag (in the parent view) and resumes
/// with `.allow`.
struct ToolApprovalSheet: View {
    let request: ToolApprovalRequest
    let onAllow: () -> Void
    let onDeny: () -> Void
    let onAllowAll: () -> Void

    /// Short, human-readable summary for the most common tools. Falls back to
    /// "Run <tool>" so unknown tools (e.g. MCP server tools) still render.
    private var headline: String {
        switch request.toolName {
        case "shell":      return "Run a shell command"
        case "cwd":        return "Change working directory"
        case "writeFile":  return "Write a file"
        case "editFile":   return "Edit a file"
        case "readFile":   return "Read a file"
        case "searchFiles":return "Search the workspace"
        case "listFiles":  return "List files"
        case "browse":     return "Browse the web"
        case "webSearch":  return "Search the web"
        case "saveMemory": return "Save a memory"
        case "generate_image": return "Generate an image"
        case "generate_speech": return "Generate spoken audio"
        case "generate_music": return "Generate a music track"
        case "generate_sound": return "Generate a sound effect"
        case "generate_video": return "Generate a video"
        default:           return "Run \(request.toolName)"
        }
    }

    /// Sorted arg pairs. Prefer the parsed dict; if it's empty (raw is the
    /// only source of truth for arrays/objects), show the raw JSON inline.
    private var argPairs: [(String, String)] {
        request.arguments.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.app(.title2))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("Allow this tool call?"))
                        .font(.app(.headline))
                    Text(L10n.text(headline))
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.format("Tool: %@", request.toolName))
                    .font(.app(.caption).weight(.semibold))
                    .foregroundStyle(.secondary)
                if argPairs.isEmpty && !request.rawArguments.isEmpty {
                    ScrollView {
                        Text(L10n.text(request.rawArguments))
                            .font(.app(.subheadline, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 200)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else if argPairs.isEmpty {
                    Text("(no arguments)")
                        .font(.app(.caption).italic())
                        .foregroundStyle(.tertiary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(argPairs, id: \.0) { (k, v) in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(L10n.text(k))
                                        .font(.app(.subheadline, design: .monospaced).weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(L10n.text(v))
                                        .font(.app(.subheadline, design: .monospaced))
                                        .textSelection(.enabled)
                                        .lineLimit(8)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                    .frame(maxHeight: 240)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            HStack(spacing: 8) {
                Button(role: .destructive) {
                    onDeny()
                } label: {
                    Text("Deny").font(.app(.body)).frame(minWidth: 70)
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    onAllowAll()
                } label: {
                    Text("Allow all tools this session").font(.app(.body)).frame(minWidth: 180)
                }

                Button {
                    onAllow()
                } label: {
                    Text("Allow").font(.app(.body)).frame(minWidth: 70)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

/// Horizontal strip of pending attachment chips (images, PDFs, audio) shown
/// above the message input. Extracted from `ChatDetailView` so its body stays
/// within the Swift type-checker's complexity budget.
private struct AttachmentPreviewRow: View {
    @Binding var images: [PendingImage]
    @Binding var pdfs: [(name: String, text: String)]
    @Binding var videos: [ChatVideo]
    @Binding var audio: [ChatAudio]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(images.enumerated()), id: \.offset) { idx, pending in
                    imageChip(idx: idx, img: pending.image)
                }
                // Each `detail` is localized by its producer, not by `fileChip`:
                // a format key has to be completed BEFORE the catalog lookup, or
                // the lookup keys on the finished sentence and can never match.
                ForEach(Array(pdfs.enumerated()), id: \.offset) { idx, pdf in
                    fileChip(idx: idx, name: pdf.name, detail: L10n.format("PDF · %lld chars", pdf.text.count),
                             icon: "doc.text.fill", tint: .red) { pdfs.remove(at: idx) }
                }
                ForEach(Array(videos.enumerated()), id: \.offset) { idx, vid in
                    fileChip(idx: idx, name: vid.name, detail: L10n.format("Video · %lld frames", vid.frameCount),
                             icon: "video.fill", tint: .orange) { videos.remove(at: idx) }
                }
                ForEach(Array(audio.enumerated()), id: \.offset) { idx, clip in
                    fileChip(idx: idx, name: clip.name, detail: L10n.format("Audio · %.1fs", clip.durationSeconds),
                             icon: "waveform", tint: .purple) { audio.remove(at: idx) }
                }
            }
        }
        .frame(height: 64)
    }

    @ViewBuilder
    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.app(.body))
                .foregroundStyle(.white)
                .background(Circle().fill(.black.opacity(0.5)))
        }
        .buttonStyle(.plain)
        .offset(x: 4, y: -4)
    }

    @ViewBuilder
    private func imageChip(idx: Int, img: NSImage) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            removeButton { images.remove(at: idx) }
        }
    }

    @ViewBuilder
    private func fileChip(idx: Int, name: String, detail: String, icon: String, tint: Color, remove: @escaping () -> Void) -> some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.app(.title2))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.app(.caption).weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    // Verbatim: every caller hands in text its producer already
                    // localized, so a lookup here would re-key the sentence.
                    Text(detail)
                        .font(.app(.caption2))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: 200, minHeight: 56, maxHeight: 56)
            .background(Color.secondary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            removeButton(remove)
        }
    }
}

/// A chat image decoded off-main once, not per bubble redraw.
private struct AttachmentImageCell: View {
    let image: ChatImage
    @State private var decoded: NSImage?
    @State private var undecodable = false

    var body: some View {
        Group {
            if let decoded {
                // `.fill`: the rounded corners clip the frame,
                // so a letterboxed picture keeps square corners.
                Image(nsImage: decoded)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: ChatImagePreview.displayWidth(for: decoded),
                           height: ChatMetrics.attachmentHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onTapGesture(count: 2) { ChatImagePreview.openInPreview(image) }
                    .help("Double-click to open in Preview")
            } else if !undecodable {
                // Hold the row's height so the transcript does not jump.
                Color.clear
                    .frame(width: ChatMetrics.attachmentHeight,
                           height: ChatMetrics.attachmentHeight)
            }
        }
        .task(id: image.id) {
            let loaded = await MediaImage.load(data: image.data,
                                               id: image.id.uuidString,
                                               maxPixel: 1536)
            guard !Task.isCancelled else { return }
            if let loaded { decoded = loaded } else { undecodable = true }
        }
    }
}

/// Chip for the attached document folder (mini RAG): shows live indexing
/// progress, then the indexed file/chunk totals, with an ✕ to detach. Styled
/// to match the `AttachmentPreviewRow` file chips.
private struct DocumentFolderChip: View {
    @ObservedObject var index: DocumentIndex
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.app(.title2))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.text(index.folderName))
                    .font(.app(.caption).weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(L10n.text(statusText))
                    .font(.app(.caption2))
                    .foregroundStyle(.secondary)
            }
            if case .indexing(let done, let total) = index.state {
                ProgressView(value: total > 0 ? Double(done) / Double(total) : 0)
                    .progressViewStyle(.linear)
                    .frame(width: 70)
            }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.app(.body))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Detach folder")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: 320, minHeight: 44, alignment: .leading)
        .background(Color.secondary.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var iconName: String {
        if case .failed = index.state { return "exclamationmark.triangle.fill" }
        return "folder.fill"
    }

    private var tint: Color {
        if case .failed = index.state { return .orange }
        return .blue
    }

    private var statusText: String {
        switch index.state {
        case .preparing:
            return "Preparing embeddings…"
        case .indexing(let done, let total):
            return total > 0 ? "Indexing \(done)/\(total) files…" : "Scanning folder…"
        case .ready(let files, let chunks):
            return "\(files) files · \(chunks) excerpts — ask away"
        case .failed(let msg):
            return msg
        }
    }
}

/// Audio attachment control; the active recording keeps its timer and level meter.
private struct MicButton: View {
    @ObservedObject var recorder: AudioRecorder
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 4) {
                ComposerControlSymbol(name: recorder.isRecording ? "stop.fill" : "mic.fill")
                if recorder.isRecording {
                    Text(timeString(recorder.duration))
                        .font(.app(.caption2).monospacedDigit().weight(.medium))
                    Circle().fill(Color.red)
                        .frame(width: 5, height: 5)
                        .scaleEffect(0.6 + 0.4 * CGFloat(recorder.level))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(recorder.isRecording ? Color.red : Color.primary)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(.regular)
        .accessibilityLabel(recorder.isRecording ? "Stop recording and attach" : "Record audio")
        .accessibilityValue(recorder.isRecording ? "Recording" : "Not recording")
        .help(recorder.isRecording ? "Stop recording and attach" : "Record audio for the model to hear")
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// What a pasted/dropped file URL should become, by extension + directory flag.
/// A top-level (non-`@MainActor`) type so the routing is unit-testable without
/// the rendered view — it mirrors the attach button's dispatch (see ChatPasteTests).
enum PasteFileKind: String, Equatable {
    case folder, pdf, audio, video, image, unhandled

    static func classify(ext: String, isDirectory: Bool, audioSupported: Bool, videoSupported: Bool = false) -> PasteFileKind {
        if isDirectory { return .folder }
        let e = ext.lowercased()
        if e == "pdf" { return .pdf }
        if let ut = UTType(filenameExtension: e) {
            if ut.conforms(to: .audio) { return audioSupported ? .audio : .unhandled }
            if ut.conforms(to: .movie) { return videoSupported ? .video : .unhandled }
            if ut.conforms(to: .image) { return .image }
        }
        return .unhandled
    }
}

enum ChatWindowPresentation {
    static func conversationTitle(title: String?, agentName: String?) -> String {
        let title = title?.trimmedNonEmpty ?? ChatSessionTitle.plain
        return ChatSessionTitle.subject(title: title, agentName: agentName)
            ?? ChatSessionTitle.display(title: title, agentName: agentName)
    }

    static func branchMessageID(messages: [ChatMessage], turnInFlight: Bool) -> UUID? {
        guard !turnInFlight,
              let message = messages.last(where: { !$0.isStreaming && ChatTurn.isBoundary($0) }),
              ChatFork.isForkable(messages, at: message.id) else { return nil }
        return message.id
    }
}

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var server: ServerManager
    /// The Agents pane's editing state, owned here so it survives while the
    /// user moves between agents. The standalone Agents window owns its own —
    /// two surfaces editing one draft would fight over it.
    @StateObject private var agentsModel = AgentsWorkspaceModel()
    /// Flipped by the gate sheet's Cancel, and by nothing else.
    @State private var gateCancelled = false

    @ToolbarContentBuilder
    private var conversationActions: some ToolbarContent {
        if appState.chatWorkspace.isConversation, let session = appState.activeSession {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { appState.pendingRename = session.id } label: {
                        Label("Rename…", systemImage: "pencil")
                    }
                    Button {
                        guard let current = appState.chatSessions.first(where: { $0.id == session.id }),
                              let messageID = branchMessageID(for: current) else { return }
                        appState.forkSession(current.id, from: messageID)
                    } label: {
                        Label("Branch Chat", systemImage: "arrow.trianglehead.branch")
                    }
                    .disabled(branchMessageID(for: session) == nil)
                } label: {
                    Label("Conversation actions", systemImage: "ellipsis")
                }
                .labelStyle(.iconOnly)
                .menuIndicator(.hidden)
                .help("Conversation actions")
            }
        }
    }

    private func branchMessageID(for session: ChatSession) -> UUID? {
        ChatWindowPresentation.branchMessageID(messages: session.messages,
            turnInFlight: appState.chatEngine.composerState(for: session.id) == .generatingHere)
    }

    /// The starter recommendation this Mac gets — same function the welcome
    /// window and the Model Browser read.
    private var starterPick: RecommendedModelPick {
        RecommendedModelPick.starterPick(physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory)
    }

    /// Blocking whenever nothing on this Mac can serve a chat. The progress
    /// argument is nil here on purpose: this only decides WHETHER to block, and
    /// `appState.localModels` is what flips it back. The sheet itself observes
    /// the download manager for the live figure.
    private var gateIsBlocking: Bool {
        ChatGateState.resolve(localModels: appState.localModels,
                              activeDownload: nil,
                              lanChatModelCount: server.lanModels(capability: "chat").count).isBlocking
    }

    var body: some View {
        WorkspaceSplitView(hasSecondaryList: appState.chatWorkspace.isThreeColumn) {
            ChatSidebar()
        } secondary: {
            if appState.chatWorkspace.isAgents {
                AgentListPane(model: agentsModel)
            } else {
                TaskListPane()
            }
        } detail: {
            workspaceDetail
        }
        .navigationTitle(Text(verbatim: windowTitle))
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbar {
            conversationActions
        }
        .sheet(isPresented: $appState.modelPalettePresented) {
            ModelPaletteSheet()
                .environmentObject(appState)
                .environmentObject(server)
        }
        // Blocking: the setter drops SwiftUI's own dismissals, so nothing but
        // Cancel takes this sheet down. The getter is recomputed every update,
        // so it also clears ITSELF the moment a chat model lands.
        .sheet(isPresented: Binding(
            get: {
                ChatWorkspace.gateShouldPresent(gateIsBlocking: gateIsBlocking,
                                                cancelled: gateCancelled,
                                                workspace: appState.chatWorkspace,
                                                welcomePresented: appState.showWelcome,
                                                palettePresented: appState.modelPalettePresented,
                                                otherInteractionAvailable: ModelPalette.hasNonChatInteraction(
                                                    local: appState.localModels, mediaModels: server.allModels))
            },
            set: { _ in })) {
            ChatModelGateSheet(pick: starterPick, onCancel: cancelGate)
                .environmentObject(appState)
                .environmentObject(appState.downloads)
                .environmentObject(server)
        }
        .onAppear {
            // Menu bar apps need explicit activation for keyboard focus — and
            // the `.regular` flip must come FIRST. (The old comment here claimed
            // ActivationPolicyManager would handle it "when this window becomes
            // key", which is the bug: an inactive accessory app has no key
            // window, so that notification never arrives.)
            DispatchQueue.main.async {
                AppActivation.focus()
            }
            // The gate reads `localModels`; a chat window opened right after a
            // download landed elsewhere must not show a stale one.
            appState.refreshModels()
        }
    }

    @ViewBuilder
    private var workspaceDetail: some View {
        switch appState.chatWorkspace {
        case .agents:
            AgentDetailPane(model: agentsModel)
        case .tasks:
            TaskDetailPane()
        case .models(let section):
            ModelBrowserPane(section: Binding(
                get: { section },
                set: { appState.selectModelSection($0) }))
        case .terminal(let id):
            TerminalPane(sessionId: id)
        case .create(let experiment):
            createPane(experiment)
        case .conversation, .settings:
            if let sessionId = appState.activeChatId,
               appState.chatSessions.contains(where: { $0.id == sessionId }) {
                ChatDetailView(sessionId: sessionId)
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear { _ = appState.newChatSession() }
            }
        }
    }

    private var windowTitle: String {
        switch appState.chatWorkspace {
        case .conversation:
            let session = appState.activeSession
            let title = ChatWindowPresentation.conversationTitle(
                title: session?.title,
                agentName: appState.agents.agent(id: session?.agentId)?.name)
            return ChatSessionTitle.isPlaceholder(title) ? L10n.text(title) : title
        case .models: return L10n.text("Models")
        case .create(let experiment): return L10n.text(experiment.title)
        case .tasks: return L10n.text("Tasks")
        case .agents: return L10n.text("Agents")
        case .settings: return L10n.text("Settings")
        case .terminal(let id):
            return appState.terminals.sessions.session(id)?.displayName ?? L10n.text("Terminal")
        }
    }

    /// Each generation capability keeps its own inputs, results, and parameters.
    @ViewBuilder
    private func createPane(_ experiment: GenExperiment) -> some View {
        switch experiment {
        case .image:   ImageGenView().environmentObject(appState.imageGen)
        case .video:   VideoGenView().environmentObject(appState.videoGen)
        case .audio:   AudioGenView()
                           .environmentObject(appState.audioGen)
                           .environmentObject(appState.musicGen)
                           .environmentObject(appState.soundGen)
        case .model3d: Model3DGenView().environmentObject(appState.model3dGen)
        }
    }

    /// Dismiss setup while keeping model browsing and other workspaces available.
    private func cancelGate() {
        gateCancelled = true
    }
}

/// Drag-to-reorder for one sidebar row: the row is a drag source carrying its
/// id, and a drop target that takes the dragged row into its slot the moment
/// the drag ENTERS it. `onDrag`/`onDrop` rather than `.draggable`, because the
/// live reorder needs `dropEntered`, which only a `DropDelegate` gets.
struct SidebarReorder: ViewModifier {
    let id: UUID
    @Binding var dragging: UUID?
    let move: (UUID, UUID) -> Void

    func body(content: Content) -> some View {
        content
            .onDrag {
                dragging = id
                return NSItemProvider(object: id.uuidString as NSString)
            }
            .onDrop(of: [.text], delegate: Delegate(id: id, dragging: $dragging, move: move))
    }

    private struct Delegate: DropDelegate {
        let id: UUID
        @Binding var dragging: UUID?
        let move: (UUID, UUID) -> Void

        func dropEntered(info: DropInfo) {
            guard let moved = dragging, moved != id else { return }
            move(moved, id)
        }
        func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
        func performDrop(info: DropInfo) -> Bool {
            dragging = nil
            return true
        }
        func dropExited(info: DropInfo) {}
    }
}

/// A group heading (or the Sessions one, nil) as a drop target: the dragged
/// row joins it as the drag enters, the same live idiom as `SidebarReorder`.
struct SidebarGroupDrop: DropDelegate {
    @Binding var dragging: UUID?
    let assign: (UUID) -> Void

    func dropEntered(info: DropInfo) {
        if let id = dragging { assign(id) }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

enum SidebarRowStyle {
    static func fill(selected: Bool, hovering: Bool) -> Color {
        selected ? Color.primary.opacity(0.10) : .clear
    }
}

/// Selection rules for numbered shortcuts; List owns pointer and arrow-key selection.
enum SidebarMultiSelect {
    struct Outcome: Equatable {
        var selection: Set<UUID>
        /// What a subsequent shift-click ranges FROM.
        var anchor: UUID?
        /// The chat the detail column should show, or nil to leave it where it
        /// is — a cmd-click that deselects some OTHER row changes what is
        /// selected without changing where you are.
        var activate: UUID?
    }

    /// - Parameters:
    ///   - ordered: every visible row id in panel order, both sections
    ///     flattened — a shift-range crosses the Agents/Chats boundary.
    ///   - active: the chat currently on screen.
    static func click(_ id: UUID,
                      ordered: [UUID],
                      selection: Set<UUID>,
                      anchor: UUID?,
                      active: UUID?,
                      command: Bool,
                      shift: Bool) -> Outcome {
        // Shift wins when both are held, as it does in every macOS list.
        if shift, let anchor, anchor != id,
           let from = ordered.firstIndex(of: anchor),
           let to = ordered.firstIndex(of: id) {
            let span = from <= to ? from...to : to...from
            // The range REPLACES the selection and the anchor stays put, so
            // shift-clicking around re-ranges from one origin instead of
            // accumulating every range you passed through.
            return Outcome(selection: Set(ordered[span]), anchor: anchor, activate: id)
        }
        guard command else {
            return Outcome(selection: [id], anchor: id, activate: id)
        }
        guard selection.contains(id) else {
            return Outcome(selection: selection.union([id]), anchor: id, activate: id)
        }
        // Cmd-clicking the ONLY selected row is a no-op: this selection is also
        // the panel's "you are here", and emptying it would leave a transcript
        // on screen with nothing in the list pointing at it.
        guard selection.count > 1 else {
            return Outcome(selection: selection, anchor: id, activate: nil)
        }
        var next = selection
        next.remove(id)
        // Deselecting the row you were READING moves to the nearest survivor —
        // otherwise the transcript belongs to a row that is no longer lit.
        let activate = active == id ? nearest(to: id, in: ordered, within: next) : nil
        return Outcome(selection: next, anchor: id, activate: activate)
    }

    /// What the selection becomes when the composer takes the keyboard, or nil
    /// when it already says that.
    ///
    /// Typing is a statement that you are working in ONE conversation. Without
    /// this the multi-selection stayed lit behind the field, and since a
    /// multi-selection outranks focus for ⌘⌫ (`ChatDeleteShortcut.route`) the
    /// chord kept raising a delete dialog mid-message — two rules each reading
    /// a true fact and disagreeing about which one meant "the user is deleting
    /// chats". The chat you are typing IN is the survivor: its transcript is
    /// the one on screen above the field.
    ///
    /// Nil rather than an equal set, so a focus event that changes nothing does
    /// not publish.
    static func focusingComposer(in sessionId: UUID, selection: Set<UUID>) -> Set<UUID>? {
        selection == [sessionId] ? nil : [sessionId]
    }

    private static func nearest(to id: UUID, in ordered: [UUID], within set: Set<UUID>) -> UUID? {
        guard let origin = ordered.firstIndex(of: id) else { return set.first }
        return ordered.enumerated()
            .filter { set.contains($0.element) }
            .min { abs($0.offset - origin) < abs($1.offset - origin) }?
            .element
    }
}

/// Which deletions stop and ask first. Pure, and beside `SidebarMultiSelect`
/// for the same reason — the rule is worth pinning, and there is nothing to
/// see on screen until you have already lost the conversations.
enum SidebarDeleteConfirm {
    /// ⌘⌫ ALWAYS asks: the key names no row, so its target is implicit — every
    /// selected row, or, with nothing selected, whichever chat you happen to be
    /// reading. And any BULK delete asks whichever control started it, because
    /// N conversations go on one action and nothing undoes it. A single
    /// deliberate delete on a named row (the row's ✕, its context menu) still
    /// goes straight through, as it always has.
    static func required(count: Int, keyboard: Bool) -> Bool {
        count > 0 && (keyboard || count > 1)
    }

    /// What ⌘⌫ acts on: the sidebar's selection, or — with nothing selected —
    /// the chat being read. Nil when there is nothing to delete, which is also
    /// what disables the menu item, since a command that does nothing when you
    /// pick it is the dead-control class.
    static func target(selection: Set<UUID>, activeChatId: UUID?,
                       workspace: ChatWorkspace = .conversation) -> Set<UUID>? {
        guard workspace.isConversation else { return nil }
        let ids = selection.isEmpty ? (activeChatId.map { Set([$0]) } ?? []) : selection
        return ids.isEmpty ? nil : ids
    }

    /// The count is the thing to check before agreeing, so it is in the title.
    /// The dialog renders this verbatim, so the format runs here.
    static func title(count: Int) -> String {
        count == 1 ? L10n.text("Delete this chat?")
                   : L10n.format("Delete %lld chats?", Int64(count))
    }
}

/// Where ⌘⌫ goes.
///
/// A menu item's key equivalent is offered the keystroke by
/// `performKeyEquivalent` BEFORE the first responder ever sees it, so a Delete
/// Chat command in the menu bar takes ⌘⌫ away from every text field in the app
/// — including the composer, where it has meant "delete to the start of the
/// line" since long before this app existed. Typing it mid-message raised a
/// delete-chat dialog, and `.disabled(chatDeletionTarget == nil)` cannot help:
/// a chat is open in exactly the state where you are typing into one.
///
/// So the command ROUTES rather than claims. The keyboard's own owner wins
/// while it has focus, and the menu item keeps its slot — which is the half
/// that made the shortcut discoverable in the first place.
enum ChatDeleteShortcut {
    enum Route: Equatable {
        /// Hand it back to the text being edited (see `deleteToBeginningOfLine`
        /// — the menu has already swallowed the event, so returning early
        /// would make ⌘⌫ do nothing at all in the composer).
        case deleteToLineStart
        case deleteChats
    }

    /// - Parameter selectedChats: how many rows the sidebar has picked. Several
    ///   is unambiguous — you were working in the list — and it OUTRANKS focus,
    ///   because focus alone is not a signal this window can be trusted to get
    ///   right: nothing in it takes the keyboard off the composer except
    ///   `KeyboardFocus.resignTextEditor`, and one stuck reading would
    ///   otherwise make ⌘⌫ a line delete forever with a dozen chats selected
    ///   behind it. Belt and braces on a key that deletes conversations.
    static func route(editingText: Bool, selectedChats: Int) -> Route {
        if selectedChats > 1 { return .deleteChats }
        return editingText ? .deleteToLineStart : .deleteChats
    }
}

/// Distinguishes text editing from commands aimed at the conversation list.
enum KeyboardFocus {

    /// Whether the responder holding the keyboard is text being typed into.
    ///
    /// `NSTextView` covers both cases and is the only type that needs naming: a
    /// focused `NSTextField` never becomes first responder itself — the
    /// window's FIELD EDITOR does, and that is an `NSTextView`.
    static func isTextEditor(_ responder: NSResponder?) -> Bool {
        responder is NSTextView
    }

    /// Move the keyboard out of a text field, because nothing else in this
    /// window will. Only when a text editor actually has it — an unconditional
    /// `makeFirstResponder(nil)` would yank focus off whatever else legitimately
    /// holds it.
    static func resignTextEditor(in window: NSWindow?) {
        guard let window, isTextEditor(window.firstResponder) else { return }
        window.makeFirstResponder(nil)
    }
}

// MARK: - Sidebar

/// Every measured row, so the quick-switch can number only the ones in the
/// clear. Published per row and merged on the way up.
struct SidebarRowSpansKey: PreferenceKey {
    static let defaultValue: [UUID: SidebarRowSpan] = [:]
    static func reduce(value: inout [UUID: SidebarRowSpan],
                       nextValue: () -> [UUID: SidebarRowSpan]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// The bottom edge of the frosted destination block, measured in the column's
/// own space — rows above this line are behind glass.
struct SidebarClearBandTopKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The bottom edge of the panel — rows below this line are off the fold.
struct SidebarClearBandBottomKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ChatSidebar: View {
    private enum GroupSheet: Identifiable {
        case create(Set<UUID>)
        case rename(UUID, String)

        var id: String {
            switch self {
            case .create: return "create"
            case .rename(let id, _): return id.uuidString
            }
        }
    }

    /// The one coordinate space the three band measurements share.
    ///
    /// Load-bearing that it is the COLUMN's own space and not `.global`: a
    /// global frame is not re-published when a view merely MOVES, and entering
    /// fullscreen translates the whole column without resizing the pinned
    /// destination block — so the block went on reporting the maxY it had in
    /// the smaller window while the rows slid out from under it, and rows in
    /// plain sight lost their badges. Measured here, the top edge is the
    /// block's own height and the bottom edge is the column's, both of which
    /// change only when there is genuinely a new layout to report.
    static let bandSpace = "chatSidebarBand"

    @EnvironmentObject var appState: AppState
    /// Observed directly — AppState forwards objectWillChange only for the
    /// server and the agent store, so a badge reading `appState.downloads`
    /// never repainted while a transfer started, progressed or finished.
    @EnvironmentObject var downloads: DownloadManager
    /// Sandbox terminals share the Chats section with the conversations.
    @EnvironmentObject var terminals: TerminalSessionStore
    @Environment(\.openWindow) private var openWindow
    /// Mirror of `ChatTurnEngine.activity`, received explicitly for the same
    /// reason `downloads` is: AppState does not forward the engine's changes.
    @State private var activity = SidebarActivity()
    /// The row being dragged to a new slot, nil outside a drag.
    @State private var draggingRowId: UUID?
    /// The rename dialog's text.
    @State private var renameDraft = ""
    /// The group name sheet, nil when closed.
    @State private var groupSheet: GroupSheet?
    /// Where a shift-click ranges FROM. Moved by every plain / cmd click, left
    /// alone by shift itself so dragging a range up and down keeps re-ranging
    /// from the same origin instead of walking away from it.
    @State private var selectionAnchor: UUID?
    /// Scans for installed agent CLIs — the Code Launcher row renders the tray's
    /// shared menu body, which needs it.
    @StateObject private var cliDetector = CLILauncher()
    /// Holding ⌘ numbers the conversation rows. A modifier held down is STATE,
    /// which SwiftUI does not report outside a hovered view — see the monitor.
    @StateObject private var modifiers = ModifierKeyMonitor()
    /// Where the frosted destination block ENDS, and where the panel ends, in
    /// the column's own space — the band a conversation row has to sit inside
    /// to be readable. Measured rather than derived from the inset's height:
    /// the block's contents vary (the Create list, the download badge), so the
    /// one number that cannot go stale is the one the block reports itself.
    @State private var clearBandTop: CGFloat = 0
    @State private var clearBandBottom: CGFloat = 0
    /// Each conversation row's vertical extent, reported only while ⌘ is down.
    @State private var rowSpans: [UUID: SidebarRowSpan] = [:]

    /// The rows a number may land on: those fully clear of the frosted block
    /// and inside the panel. `nil` means "not measured" — before the first
    /// layout after ⌘ goes down — and numbers everything, which is the old
    /// behaviour rather than a sidebar of blank rows for one frame.
    private var numberedRows: Set<UUID>? {
        guard modifiers.commandHeld else { return nil }
        return ChatQuickSwitch.numbering(rowSpans: rowSpans,
                                         clearBandTop: clearBandTop,
                                         clearBandBottom: clearBandBottom)
    }

    var body: some View {
        conversationsSidebar
            .onChange(of: appState.pendingRename) { _, id in
                if let session = appState.chatSessions.first(where: { $0.id == id }) {
                    renameDraft = ChatSessionTitle.isPlaceholder(session.title) ? "" : session.title
                }
            }
    }

    /// ⌘1…⌘9 jumps to the row wearing that number; ⌃⌘1…⌃⌘9 ranges to it from
    /// where you are, selecting everything in between.
    ///
    /// Zero-size hidden buttons, the same idiom as ⌘R regenerate: they need
    /// THIS view's session list, and a key equivalent works wherever focus is,
    /// including while the composer's text view has it.
    ///
    /// **Ranging is ⌃⌘, not the ⇧⌘ every macOS list uses, because macOS took
    /// those digits first**: ⇧⌘3/4/5 are screen capture and ⇧⌘6 grabs the
    /// Touch Bar, all system-level, so they never reach an app — four of the
    /// nine ranged silently and the other five worked, which is worse than a
    /// shortcut that is simply somewhere else. Control is the replacement
    /// rather than Option because it is the one modifier that does not rewrite
    /// the character its key produces (⌥4 is ¢), so key-equivalent matching
    /// stays boring. ⌃ alone would collide with Mission Control's
    /// switch-to-desktop-N; with ⌘ it does not.
    private var quickSwitchShortcuts: some View {
        ForEach(1...ChatQuickSwitch.maxSlots, id: \.self) { slot in
            let key = KeyEquivalent(Character("\(slot)"))
            Group {
                Button { quickSwitch(to: slot, extend: false) } label: { EmptyView() }
                    .keyboardShortcut(key, modifiers: .command)
                Button { quickSwitch(to: slot, extend: true) } label: { EmptyView() }
                    .keyboardShortcut(key, modifiers: [.command, .control])
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
    }

    /// Go to a numbered chat, or range to it. Not `selectRow`: that one reads
    /// the CURRENT event's modifier flags, and the event behind these always
    /// has ⌘ down — every jump would toggle the row into a multi-selection
    /// instead of going to it. The flags are stated explicitly instead, and the
    /// decision itself is `ChatQuickSwitch.outcome`.
    private func quickSwitch(to slot: Int, extend: Bool) {
        let rows = panelRows
        switch ChatQuickSwitch.target(
            slot: slot,
            visible: rows.visible,
            chats: rows.chats,
            numbering: numberedRows,
            selection: appState.sidebarSelection,
            anchor: selectionAnchor,
            active: appState.activeChatId,
            extend: extend) {
        case .chat(let outcome)?: apply(outcome)
        case .terminal(let id)?: showTerminal(id)
        case nil: break
        }
    }

    /// The panel top to bottom: ungrouped Agents rows, the user's groups, then
    /// ungrouped Sessions rows (chats and terminals interleaved), all in the
    /// ONE dragged order. `visible` is what the ⌘ numbers read (collapsed
    /// groups hide theirs); `all` is what a drop reorders, so a drag never
    /// forgets a collapsed row's slot; `chats` is the conversation subset a
    /// shift-range runs over — the split is a heading, not a wall.
    private var panelRows: (agents: [SidebarChatRows.Row],
                            groups: [(group: SidebarGroups.Group, rows: [SidebarChatRows.Row])],
                            sessions: [SidebarChatRows.Row],
                            visible: [UUID], all: [UUID], chats: [UUID]) {
        let agentIds = Set(SidebarSessionGroups.split(appState.visibleChatSessions).agents.map(\.id))
        let rows = SidebarChatRows.merge(chats: appState.visibleChatSessions,
                                         terminals: terminals.sessions.sessions,
                                         order: appState.sidebarOrder)
        let parts = appState.sidebarGroups.partition(rows)
        let agents = parts.ungrouped.filter { agentIds.contains($0.id) }
        let sessions = parts.ungrouped.filter { !agentIds.contains($0.id) }
        let shown = agents + parts.groups.flatMap { $0.group.collapsed ? [] : $0.rows } + sessions
        let all = agents + parts.groups.flatMap(\.rows) + sessions
        let chats = shown.compactMap { row -> UUID? in
            if case .chat(let s) = row { return s.id }
            return nil
        }
        return (agents, parts.groups, sessions, shown.map(\.id), all.map(\.id), chats)
    }

    /// Store the selected rows before publishing the active conversation.
    private func apply(_ outcome: SidebarMultiSelect.Outcome) {
        appState.showConversation()
        selectionAnchor = outcome.anchor
        if appState.sidebarSelection != outcome.selection {
            appState.sidebarSelection = outcome.selection
        }
        if let target = outcome.activate, appState.activeChatId != target {
            appState.activeChatId = target
        }
    }

    private var listSelection: Binding<Set<SidebarItem>> {
        Binding(get: {
            switch appState.chatWorkspace {
            case .models: return [.models]
            case .create(let experiment): return [.create(experiment)]
            case .agents: return [.agents]
            case .tasks: return [.tasks]
            case .terminal(let id): return [.terminal(id)]
            case .settings: return []
            case .conversation: return Set(appState.sidebarSelection.map(SidebarItem.chat))
            }
        }, set: { proposed in
            let outcome = SidebarListSelection.resolve(
                proposed: proposed, previous: listSelection.wrappedValue,
                orderedChats: panelRows.chats, activeChat: appState.activeChatId)
            if let destination = outcome.destination {
                switch destination {
                case .models: appState.showModels()
                case .agents: appState.showAgents()
                case .tasks: appState.showTasks()
                case .create(let experiment): appState.showCreate(experiment)
                case .terminal(let id): showTerminal(id)
                case .chat: break
                }
            } else {
                appState.sidebarSelection = outcome.chats
                if let id = outcome.activeChat {
                    selectionAnchor = id
                    appState.showConversation()
                    appState.activeChatId = id
                }
            }
        })
    }

    private var conversationsSidebar: some View {
        List(selection: listSelection) {
            Section {
                Button {
                    appState.showConversation()
                    appState.newChatSession()
                } label: {
                    Label("New", systemImage: "square.and.pencil")
                        .font(.app(.rowTitle))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                    .selectionDisabled()
            }
            let rows = panelRows
            if !rows.agents.isEmpty {
                Section("Agent Conversations") {
                    ForEach(rows.agents) { panelRow($0, ordered: rows.chats, all: rows.all) }
                }
            }
            ForEach(rows.groups, id: \.group.id) { entry in
                Section(isExpanded: Binding(
                    get: { !entry.group.collapsed },
                    set: { expanded in
                        if expanded == entry.group.collapsed {
                            appState.sidebarGroups.toggleCollapsed(entry.group.id)
                        }
                    })) {
                    ForEach(entry.rows) { panelRow($0, ordered: rows.chats, all: rows.all) }
                } header: {
                    groupHeader(entry.group)
                }
            }
            Section {
                ForEach(rows.sessions) { panelRow($0, ordered: rows.chats, all: rows.all) }
            } header: {
                HStack {
                    Text("Sessions")
                        .font(.system(.caption, weight: .medium))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onDrop(of: [.text], delegate: groupDrop(nil))
                    if BuildFeatures.current.cliLauncher {
                        Menu { terminalCreationItems(group: nil) } label: {
                            Image(systemName: "terminal")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("New Terminal")
                        .accessibilityLabel("New Terminal")
                    }
                }
            }
            Section("Manage") {
                destinationLabel("Models", icon: "square.stack.3d.up", badge: activeDownloadCount)
                    .tag(SidebarItem.models)
                destinationLabel("Agents", icon: "person.2")
                    .tag(SidebarItem.agents)
                destinationLabel("Tasks", icon: "clock.badge.checkmark")
                    .tag(SidebarItem.tasks)
            }
        }
        .listStyle(.sidebar)
        .tint(.gray)
        .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        .onDeleteCommand {
            if appState.chatWorkspace.isConversation {
                requestDeleteChats(appState.sidebarSelection, keyboard: true)
            } else if let id = appState.chatWorkspace.terminalId {
                requestCloseTerminal(id)
            }
        }
        .onReceive(appState.chatEngine.$activity) { activity = $0; clearSeenActivity(in: $0) }
        .onChange(of: appState.sidebarSelection) { _, _ in clearSeenActivity(in: activity) }
        .onChange(of: appState.chatWorkspace) { _, _ in clearSeenActivity(in: activity) }
        .onAppear {
            // The rows READ the selection to decide their highlight, so it has
            // to be primed: `activeChatId` is usually set long before this panel
            // first appears, and an .onChange can't fire for a value that was
            // already there.
            if appState.sidebarSelection.isEmpty, let id = appState.activeChatId {
                appState.sidebarSelection = [id]
                selectionAnchor = id
            }
        }
        // Deletions from anywhere else (the tray, a task run, another window)
        // must not leave ids in the selection that no longer name a chat — a
        // stale one would be counted by the context menu's "Delete N Chats" and
        // handed straight back to `deleteSessions` by ⌫.
        .onChange(of: appState.visibleChatSessions.count) { _, _ in
            let live = Set(appState.visibleChatSessions.map(\.id))
            if !appState.sidebarSelection.isSubset(of: live) {
                appState.sidebarSelection.formIntersection(live)
            }
            if let anchor = selectionAnchor, !live.contains(anchor) { selectionAnchor = nil }
        }
        .onChange(of: appState.sidebarSelection) { _, newSelection in
            // When the sidebar's selection becomes a single id, make that the
            // active chat so the detail column follows the user's intent.
            if newSelection.count == 1, let id = newSelection.first {
                if appState.activeChatId != id { appState.activeChatId = id }
            }
        }
        .onChange(of: appState.activeChatId) { _, newActive in
            // Keep the sidebar selection in sync when other parts of the app
            // change the active chat (open-from-tray, quick launcher, etc.).
            // Only COLLAPSE it when the new active chat isn't already IN it:
            // this ran unconditionally, so a cmd-click that added a second row
            // was overwritten by `[id]` on its way out and the panel could never
            // hold more than one — the multi-select bug. A chat the selection
            // already contains is a move WITHIN the selection, and leaves it be.
            guard let id = newActive else {
                appState.sidebarSelection.removeAll()
                selectionAnchor = nil
                return
            }
            if !appState.sidebarSelection.contains(id) {
                appState.sidebarSelection = [id]
                selectionAnchor = id
            }
        }
        .confirmationDialog(
            SidebarDeleteConfirm.title(count: appState.pendingChatDeletion?.count ?? 1),
            isPresented: Binding(get: { appState.pendingChatDeletion != nil },
                                 set: { if !$0 { appState.pendingChatDeletion = nil } }),
            presenting: appState.pendingChatDeletion
        ) { ids in
            Button(role: .destructive) {
                deleteChats(ids)
                appState.pendingChatDeletion = nil
            } label: { Text("Delete")
                .font(.app(.body)) }
            // Return deletes. The dialog is the second time you have said so
            // (a menu command or a row's Delete raised it), and reaching for
            // the trackpad to confirm a decision already made is the whole
            // reason this asked to be a keyboard app. Escape still cancels —
            // AppKit gives the `.cancel` role that for free.
            .keyboardShortcut(.defaultAction)
            Button(role: .cancel) { appState.pendingChatDeletion = nil } label: { Text("Cancel")
                .font(.app(.body)) }
        } message: { _ in
            Text(L10n.text("This can't be undone.")).font(.app(.body))
        }
        // ⌘1…⌘9. In the sidebar rather than the window's `.commands` because
        // they address THIS view's conversation list; hidden in a background so
        // they cost no layout.
        .background(quickSwitchShortcuts)
        .background(renameDialog)
        .sheet(item: $groupSheet) { sheet in
            switch sheet {
            case .create(let ids):
                SidebarGroupSheet(title: "New Group", action: "Create", name: "") {
                    appState.sidebarGroups.create($0, with: ids)
                }
            case .rename(let id, let name):
                SidebarGroupSheet(title: "Rename Group", action: "Rename", name: name) {
                    appState.sidebarGroups.rename(id, to: $0)
                }
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: SidebarClearBandTopKey.self,
                                value: proxy.frame(in: .named(ChatSidebar.bandSpace)).minY)
                    .preference(key: SidebarClearBandBottomKey.self,
                                value: proxy.frame(in: .named(ChatSidebar.bandSpace)).maxY)
            }
        }
        .coordinateSpace(.named(ChatSidebar.bandSpace))
        .onPreferenceChange(SidebarClearBandTopKey.self) { value in
            applyMeasurement(value, to: $clearBandTop)
        }
        .onPreferenceChange(SidebarClearBandBottomKey.self) { value in
            applyMeasurement(value, to: $clearBandBottom)
        }
        .onPreferenceChange(SidebarRowSpansKey.self) { value in
            guard rowSpans != value else { return }
            // Async for the same reason the transcript's scroll correction is
            // (issue #136): a geometry-driven write that lands inside the
            // layout flush re-enters layout, and under a scroll it does so
            // every frame. One turn later it coalesces instead.
            DispatchQueue.main.async { rowSpans = value }
        }
    }

    /// Store a measured edge, ignoring sub-pixel noise. The equality gate is
    /// load-bearing, not an optimisation: a write per layout would re-enter
    /// layout and never settle.
    private func applyMeasurement(_ value: CGFloat, to binding: Binding<CGFloat>) {
        guard abs(binding.wrappedValue - value) > 0.5 else { return }
        DispatchQueue.main.async { binding.wrappedValue = value }
    }

    // MARK: Selection

    /// Whether a conversation row can be lit at ALL in the current workspace
    /// mode. Asked of the active chat against itself, so the answer is the mode
    /// question alone — the per-row half is now selection membership.
    private var conversationsAreLit: Bool {
        guard let active = appState.activeChatId else { return false }
        return SidebarSelection.isConversationSelected(
            sessionId: active, activeChatId: active, workspace: appState.chatWorkspace)
    }

    /// A finished mark on a selected, lit row has been seen. Deferred one
    /// turn: this runs from the engine's own publisher.
    private func clearSeenActivity(in activity: SidebarActivity) {
        guard conversationsAreLit else { return }
        let seen = activity.unseen.intersection(appState.sidebarSelection)
        guard !seen.isEmpty else { return }
        Task { @MainActor in
            for id in seen { appState.chatEngine.markActivitySeen(id) }
        }
    }

    /// The row's turn mark: green pulsing disc generating, blue spinning
    /// dashed disc running tools; once a turn ended in a chat that was not
    /// open, a grey check, or an orange mark when it ended on an error card.
    /// Three separate views, not one image swapping symbols: a symbol effect
    /// deactivated on a shared view finishes its cycle, so the grey check
    /// would still make one turn.
    @ViewBuilder
    private func activityDot(for dot: SidebarActivity.Dot) -> some View {
        switch dot {
        case .generating:
            Image(systemName: "inset.filled.circle")
                .font(.app(.subheadline))
                .foregroundStyle(.green)
                .symbolEffect(.pulse.byLayer, options: .repeat(.continuous))
                .help("Generating")
        case .tool:
            Image(systemName: "inset.filled.circle.dashed")
                .font(.app(.subheadline))
                .foregroundStyle(.blue)
                .symbolEffect(.rotate.clockwise.byLayer, options: .repeat(.continuous))
                .help("Running a tool")
        case .finished:
            Image(systemName: "checkmark.circle.fill")
                .font(.app(.subheadline))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .help("Finished")
        case .attention:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.app(.subheadline))
                .foregroundStyle(.orange)
                .help("Stopped with an error")
        }
    }

    /// Every control that deletes conversations comes through here, so which
    /// ones ask first is `SidebarDeleteConfirm`'s decision and not a per-button
    /// habit. `keyboard` is what separates ⌘⌫ — which names no row — from a
    /// click on one.
    private func requestDeleteChats(_ ids: Set<UUID>, keyboard: Bool) {
        guard !ids.isEmpty else { return }
        if SidebarDeleteConfirm.required(count: ids.count, keyboard: keyboard) {
            appState.pendingChatDeletion = ids
        } else {
            deleteChats(ids)
        }
    }

    /// Delete a set of conversations and leave the panel's own state consistent
    /// — the ids go out of the selection and the anchor FIRST, so nothing that
    /// reads them (the ⌫ handler, the context menu's count) can name a chat that
    /// is already gone.
    private func deleteChats(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        appState.sidebarSelection.subtract(ids)
        if let anchor = selectionAnchor, ids.contains(anchor) { selectionAnchor = nil }
        appState.deleteSessions(ids)
    }

    @ViewBuilder
    private func panelRow(_ row: SidebarChatRows.Row, ordered: [UUID], all: [UUID]) -> some View {
        switch row {
        case .chat(let session):
            sessionRow(session, ordered: ordered)
                .modifier(reorderable(session.id, visible: all))
        case .terminal(let t):
            terminalRow(t)
                .modifier(reorderable(t.id, visible: all))
        }
    }

    /// A user group's heading: the label folds it, the + adds a chat or
    /// terminal straight into it, a row dropped on it joins it, right-click
    /// renames or deletes it (its rows go back to their sections).
    private func groupHeader(_ group: SidebarGroups.Group) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Label(group.name, systemImage: "folder")
                .lineLimit(1)
            Spacer()
            newSessionMenu(group: group.id)
        }
        .font(.system(.caption, weight: .medium))
        .foregroundStyle(.secondary)
        .textCase(nil)
        .padding(.trailing, 6)
        .onDrop(of: [.text], delegate: groupDrop(group.id))
        .contextMenu {
            Button { groupSheet = .rename(group.id, group.name) } label: { Text("Rename Group…")
                .font(.app(.body)) }
            Button(role: .destructive) { appState.sidebarGroups.delete(group.id) } label: { Text("Delete Group")
                .font(.app(.body)) }
        }
    }

    private func groupDrop(_ group: UUID?) -> SidebarGroupDrop {
        SidebarGroupDrop(dragging: $draggingRowId) { appState.sidebarGroups.assign([$0], to: group) }
    }

    /// "Move to Group" for a row, or for the multi-selection it sits in.
    @ViewBuilder
    private func groupMenu(for ids: Set<UUID>, current: UUID?) -> some View {
        Menu("Move to Group") {
            ForEach(appState.sidebarGroups.groups) { group in
                Button { appState.sidebarGroups.assign(ids, to: group.id) } label: { Text(group.name)
                    .font(.app(.body)) }
                    .disabled(ids.count == 1 && group.id == current)
            }
            if !appState.sidebarGroups.groups.isEmpty { Divider() }
            Button { groupSheet = .create(ids) } label: { Text("New Group…")
                .font(.app(.body)) }
        }
        if current != nil {
            Button { appState.sidebarGroups.assign(ids, to: nil) } label: { Text("Remove from Group")
                .font(.app(.body)) }
        }
        Divider()
    }

    private func newSessionMenu(group: UUID) -> some View {
        Menu {
            Button {
                appState.showConversation()
                appState.sidebarGroups.assign([appState.newChatSession()], to: group)
            } label: {
                Label("New Chat", systemImage: "square.and.pencil")
            }
            if BuildFeatures.current.cliLauncher {
                Divider()
                terminalCreationItems(group: group)
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .controlSize(.small)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("New Chat")
        .help("New chat, or a coding agent in a terminal")
    }

    private func terminalCreationItems(group: UUID?) -> some View {
        CLILauncherMenuItems(
            detector: cliDetector,
            baseURL: appState.server.baseURL,
            servedModelId: appState.server.chatModelId ?? "mlx-serve",
            serverContextLength: appState.server.chatModelInfo?.contextLength,
            models: appState.server.allModels,
            openSandboxAgent: { appState.startTerminal(agentId: $0, group: group) },
            openHostCLI: { appState.startTerminal(hostCLI: $0, group: group) })
    }

    /// One conversation row, shared by both sections. `ordered` is the panel's
    /// flattened visual order, which shift-click ranges over.
    @ViewBuilder
    private func sessionRow(_ session: ChatSession, ordered: [UUID]) -> some View {
        let isSelected = conversationsAreLit && appState.sidebarSelection.contains(session.id)
            let agent = appState.agents.agent(id: session.agentId)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if session.isExternalBridge {
                        Image(systemName: "paperplane.fill")
                            .font(.app(.caption2))
                            .foregroundStyle(.secondary)
                            .help("Archived Telegram conversation")
                    }
                    if let agent {
                        Image(systemName: agent.symbol)
                            .font(.app(.caption2))
                            .foregroundStyle(.secondary)
                    } else if !session.isExternalBridge {
                        // Every row in this column carries a glyph saying what
                        // it is — a terminal, an agent, a plain conversation.
                        Image(systemName: "bubble.left")
                            .font(.app(.subheadline, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    let displayTitle = ChatSessionTitle.display(title: session.title,
                                                                agentName: agent?.name)
                    Text(displayTitle == "New Chat" ? L10n.text(displayTitle) : displayTitle)
                        .font(.app(.rowTitle))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    if let dot = activity.dot(for: session.id, isSelected: isSelected) {
                        activityDot(for: dot)
                    }
                }
                // What this particular conversation is about, displaced from
                // the title line by the agent's name. It is also the only
                // thing telling a second thread with the same agent apart
                // from the first — without it the sidebar draws two identical
                // rows. Absent until the thread has said something, so a new
                // one is a single line exactly like a destination row.
                if let subject = ChatSessionTitle.subject(title: session.title,
                                                          agentName: agent?.name) {
                    Text(L10n.text(subject))
                        .font(.app(.caption2))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.secondary)
                }
            }
            // Room kept for the delete button at ALL times, not only while
            // hovering: reserving it on hover reflows the title under the
            // pointer, right as you are aiming at it.
            .padding(.trailing, 24)
            .padding(.vertical, 2)
            // A row is as tall as what is IN it: one line matches a
            // destination row exactly, and only the rows carrying an agent
            // subtitle grow. The floor lives on the LABEL so the button — the
            // thing that answers clicks — is the full height of the fill.
            // `minHeight` is a floor, never a fixed height.
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())

        .tag(SidebarItem.chat(session.id))
        .background(rowSpanProbe(session.id))
        .overlay(alignment: .trailing) { quickSwitchBadge(for: session.id) }
        .contextMenu {
            // Right-clicking INSIDE a multi-selection acts on all of it, and
            // says how many; right-clicking outside one acts on the row.
            let inSelection = appState.sidebarSelection.count > 1
                && appState.sidebarSelection.contains(session.id)
            Button { beginRename(session.id, current: session.title) } label: { Text("Rename…")
                .font(.app(.body)) }
            groupMenu(for: inSelection ? appState.sidebarSelection : [session.id],
                      current: appState.sidebarGroups.group(of: session.id))
            if inSelection {
                Button(role: .destructive) {
                    requestDeleteChats(appState.sidebarSelection, keyboard: false)
                } label: { Text(L10n.format("Delete %lld Chats", Int64(appState.sidebarSelection.count)))
                    .font(.app(.body)) }
            } else {
                Button(role: .destructive) {
                    requestDeleteChats([session.id], keyboard: false)
                } label: { Text("Delete")
                    .font(.app(.body)) }
            }
        }
    }

    /// One sandbox terminal row: the same chrome as a conversation row, a
    /// terminal glyph tinted by phase, the workspace's folder as the caption.
    @ViewBuilder
    private func terminalRow(_ t: TerminalSessionList.Session) -> some View {
            HStack(spacing: 6) {
                Image(systemName: t.isInOwnWindow ? "macwindow" : "terminal")
                    .font(.app(.subheadline, weight: .medium))
                    .foregroundStyle(terminalTint(t.phase))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text(t.displayName))
                        .font(.app(.rowTitle))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    Text((t.workspace as NSString).lastPathComponent)
                        .font(.app(.caption2))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.trailing, 24)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())

        .tag(SidebarItem.terminal(t.id))
        .background(rowSpanProbe(t.id))
        .overlay(alignment: .trailing) { quickSwitchBadge(for: t.id) }
        .contextMenu {
            Button { beginRename(t.id, current: t.displayName) } label: { Text("Rename…")
                .font(.app(.body)) }
            groupMenu(for: [t.id], current: appState.sidebarGroups.group(of: t.id))
            if t.isInOwnWindow {
                Button { showTerminal(t.id) } label: { Text("Show Window")
                    .font(.app(.body)) }
            } else {
                Button { moveToNewWindow(t.id) } label: { Text("Move Tab to New Window")
                    .font(.app(.body)) }
            }
            Menu("Theme") {
                Toggle("App Default", isOn: Binding(
                    get: { t.themeId == nil },
                    set: { _ in terminals.setTheme(t.id, themeId: nil) }))
                Divider()
                ForEach(TerminalTheme.all) { theme in
                    Toggle(theme.name, isOn: Binding(
                        get: { t.themeId == theme.id },
                        set: { _ in terminals.setTheme(t.id, themeId: theme.id) }))
                }
            }
            Button(role: .destructive) {
                requestCloseTerminal(t.id)
            } label: { Text(L10n.text(t.isActive ? "End Session" : "Close"))
                .font(.app(.body)) }
        }
        // Per row, so only the row asked presents; a live session's ✕ is a
        // small target and a misclick must not kill a TUI.
        .confirmationDialog(
            "End the \(t.displayName) session?",
            isPresented: Binding(get: { appState.pendingTerminalClose == t.id },
                                 set: { if !$0 { appState.pendingTerminalClose = nil } })
        ) {
            Button(role: .destructive) { appState.closeTerminal(t.id) } label: { Text("End Session")
                .font(.app(.body)) }
                .keyboardShortcut(.defaultAction)
            Button(role: .cancel) { appState.pendingTerminalClose = nil } label: { Text("Cancel")
                .font(.app(.body)) }
        } message: {
            Text(L10n.text("The session running inside the sandbox will be terminated. Files it wrote are kept."))
        }
    }

    /// Drag a row onto another to take its slot. Reorders LIVE as the drag
    /// passes over rows (the `dropEntered` idiom), so the list shows where the
    /// row will land; the drop itself only ends the drag.
    private func reorderable(_ id: UUID, visible: [UUID]) -> SidebarReorder {
        SidebarReorder(id: id, dragging: $draggingRowId) { moved, target in
            appState.moveSidebarRow(moved, onto: target, visible: visible)
        }
    }

    /// Where a row sits, so the numbering can skip whatever is under the
    /// frosted block. Attached ONLY while ⌘ is down: a probe on every row is
    /// a preference write per row per scroll frame, and outside this
    /// transient mode nothing reads the answer.
    @ViewBuilder
    private func rowSpanProbe(_ id: UUID) -> some View {
        if modifiers.commandHeld {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .named(ChatSidebar.bandSpace))
                Color.clear.preference(
                    key: SidebarRowSpansKey.self,
                    value: [id: SidebarRowSpan(top: frame.minY, bottom: frame.maxY)])
            }
        }
    }

    /// The ⌘-digit badge for a row, nil when it wears none (⌘ up, or the row
    /// is under the frost). Shared by chat and terminal rows — one panel, one
    /// numbering.
    private func quickSwitchBadge(for id: UUID) -> AnyView? {
        guard modifiers.commandHeld,
              let slot = ChatQuickSwitch.slot(for: id, visible: panelRows.visible,
                                              numbering: numberedRows) else { return nil }
        return AnyView(
            Text("\(slot)")
                .font(.app(.caption2).weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.08))
                )
                .padding(.trailing, ChatMetrics.sidebarRowInset)
                // Decoration: it must never eat the click that selects the
                // row it is drawn on.
                .allowsHitTesting(false)
                .transition(AnyTransition.asymmetric(
                    insertion: .opacity.animation(.easeIn(duration: 0.25).delay(0.2)),
                    removal: .opacity.animation(.easeOut(duration: 0.15))
                 ))
                .animation(.easeInOut(duration: 0.25), value: modifiers.commandHeld))
    }

    private func beginRename(_ id: UUID, current: String) {
        renameDraft = ChatSessionTitle.isPlaceholder(current) ? "" : current
        appState.pendingRename = id
    }

    /// The one rename dialog, for chats and terminals alike.
    private var renameDialog: some View {
        Color.clear.frame(width: 0, height: 0)
            .alert("Rename Session",
                   isPresented: Binding(get: { appState.pendingRename != nil },
                                        set: { if !$0 { appState.pendingRename = nil } }),
                   presenting: appState.pendingRename) { id in
                TextField("Name", text: $renameDraft)
                Button {
                    appState.renameSession(id, to: renameDraft)
                    appState.pendingRename = nil
                } label: { Text("Rename")
                    .font(.app(.body)) }
                .keyboardShortcut(.defaultAction)
                Button(role: .cancel) { appState.pendingRename = nil } label: { Text("Cancel")
                    .font(.app(.body)) }
            } message: { _ in
                Text("Leave it empty to go back to the automatic name.").font(.app(.body))
            }
    }

    /// A terminal shows in the detail column, or — once moved out — in its
    /// own window, which a repeat open only raises.
    private func showTerminal(_ id: UUID) {
        if terminals.sessions.session(id)?.isInOwnWindow == true {
            AppActivation.openWindow(id: "terminalWindow", value: id, using: openWindow)
        } else {
            appState.showTerminal(id)
        }
    }

    private func moveToNewWindow(_ id: UUID) {
        if appState.chatWorkspace == .terminal(id) { appState.showConversation() }
        terminals.setInOwnWindow(id, true)
        AppActivation.openWindow(id: "terminalWindow", value: id, using: openWindow)
    }

    private func terminalTint(_ phase: TerminalSessionList.Session.Phase) -> Color {
        switch phase {
        case .preparing: return .orange
        case .live: return .green
        case .suspended: return .secondary
        case .exited: return .secondary
        case .failed: return .red
        }
    }

    /// Instant for exited/failed rows, confirmed while a session is alive.
    private func requestCloseTerminal(_ id: UUID) {
        if terminals.sessions.closeNeedsConfirmation(id) {
            appState.pendingTerminalClose = id
        } else {
            appState.closeTerminal(id)
        }
    }

    private func destinationLabel(_ title: String, icon: String,
                                  badge: Int = 0) -> some View {
        Label {
            HStack {
                Text(L10n.text(title))
                Spacer()
                if badge > 0 {
                    Text("\(badge)")
                        .font(.app(.caption).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: icon)
        }
        .padding(.vertical, 3)
    }

    private var activeDownloadCount: Int {
        downloads.downloads.values.filter { $0.status == .downloading }.count
    }

}

// MARK: - Chat Detail

struct ChatDetailView: View {
    let sessionId: UUID
    @EnvironmentObject var appState: AppState
    @State private var modelSettings: ModelSettingsRequest?
    /// Observed directly (AppState does not forward download publishes) — the
    /// create banner's "not downloaded" pill and the held-prompt readiness
    /// checks must repaint when the bytes land.
    @EnvironmentObject var downloads: DownloadManager
    @EnvironmentObject var server: ServerManager
    @EnvironmentObject var toolExecutor: ToolExecutor
    @EnvironmentObject var mcpManager: MCPManager
    @EnvironmentObject var chatEngine: ChatTurnEngine
    @Environment(\.openWindow) private var openWindow
    // Settings ▸ Interface, observed HERE because `ChatMetrics` reads these
    // keys straight off UserDefaults with no SwiftUI dependency: without a
    // real observer a size change reaches only rows that happen to re-render,
    // leaving the transcript in two fonts at once. The values feed the `.id`
    // on the row stack, which is what forces the rebuild.
    @AppStorage(InterfacePrefKey.textSize) private var interfaceTextSize = ChatTextSize.medium.rawValue
    @State private var inputText = ""
    /// Where ↑/↓ have walked back to in this chat's own history. Per-tab state
    /// like everything else here — `ChatDetailView` is REUSED across tabs, so a
    /// walk left running would resume in someone else's conversation. Stale
    /// indexes are harmless by construction (`ComposerHistory` treats one that
    /// no longer names an entry as no walk at all), but resetting on the switch
    /// is what makes the first ↑ in a new tab mean what it says.
    @State private var composerWalk = ComposerHistory.Walk.idle
    // The detail view is reused between chats; only thinking needs a local editor binding.
    @State private var enableThinking = false
    @State private var reasoningEffort = ReasoningEffort.low
    @State private var showAttachmentPicker = false
    @State private var showChatMode = false
    @State private var executingPlanMessageId: UUID?
    // Follow-the-newest-line. The decision core is pure (`ChatScrollState`,
    // pinned by ChatScrollTests); the model holds it in a class so per-frame
    // scroll geometry doesn't re-evaluate the whole chat body — only the
    // pinned flag is published. `scrollPosition` is the one handle that moves
    // the transcript, so no view needs a `ScrollViewProxy` passed around.
    @StateObject private var scrollModel = ChatScrollModel()
    @State private var scrollPosition = ScrollPosition(idType: Never.self, edge: .bottom)
    @State private var pasteMonitor: Any?
    @State private var pendingImages: [PendingImage] = []
    @State private var pendingPDFs: [(name: String, text: String)] = []
    @State private var pendingVideos: [ChatVideo] = []
    @State private var pendingAudio: [ChatAudio] = []
    @StateObject private var recorder = AudioRecorder()
    // Tool-approval gate state. `pendingApproval` is set right before each
    // tool call when Agent mode is on; the sheet at the bottom of `body`
    // observes it and resumes `approvalContinuation` with the user's choice.
    @State private var pendingApproval: ToolApprovalRequest?
    @State private var pendingMessageDeletion: ChatDeletionRequest?
    @State private var toolAllowList = SessionToolAllowList()
    // Plain Bool (not @FocusState): the composer is an NSTextView wrapper, so
    // AppKit first-responder is the source of truth and GrowingTextEditor mirrors
    // it back into this flag. The Cmd+V attach monitor reads it; on-appear and
    // post-generation code set it true to (re)focus the field.
    @State private var inputFocused = false
    /// The detail column's measured width — the panel next to the session
    /// sidebar, not the whole window. Drives `contentWidth` below. Zero until
    /// `body`'s root view reports its first `onGeometryChange`.
    @State private var columnWidth: CGFloat = 0

    /// The reading column (Settings ▸ Interface ▸ Chat Column) every capped
    /// site shares: transcript, composer, empty-state greeting.
    private var contentWidth: CGFloat {
        ChatMetrics.proseWidth(panelWidth: columnWidth)
    }
    @State private var composerHeight: CGFloat = 36
    @State private var inputAreaHeight: CGFloat = 120
    // The composer's "create mode" (the chip rewired the composer into a
    // generator) is GONE: a media chip navigates to the Create pane, exactly
    // like the Tools menu. In-chat media generation is the agent tools' job
    // (`generate_image` & co.) — one way to drive a generator from a chat,
    // not two.
    // Issue #227: built once per messages change, not per body pass. Rebuilding
    // inside the ForEach handed SwiftUI a fresh array on every layout pass and
    // the LazyVStack could spin forever.
    @State private var rows: [ChatRow] = []
    @State private var foldStore = FoldStore()
    /// The transcript lays out `rows[firstVisibleRow...]`; see `TranscriptWindow`.
    @State private var firstVisibleRow = 0
    /// Which conversation the cut belongs to. The messages observer cuts on
    /// first appearance (it is the one with `initial: true`); the session
    /// observer cuts on every switch, with its own copy of the rows, so
    /// neither depends on the other having run.
    @State private var windowSession: UUID?
    @State private var isRevealingEarlier = false


    private var session: ChatSession? {
        appState.chatSessions.first { $0.id == sessionId }
    }

    /// Generation state for THIS chat. The engine runs one turn at a time, so a
    /// chat that doesn't own the active turn must show Send (idle), not the Stop
    /// button — and its Send is disabled while another chat is mid-turn.
    // MARK: - "/" skill menu

    /// Highlighted row; Escape hides the menu without clearing what was typed.
    @State private var slashSelection: Int = 0
    @State private var slashDismissed: Bool = false

    /// Skills answering the half-typed command, or none when the menu is
    /// closed. Guarded by `SlashCommands.query` FIRST: the skills folder is
    /// stat-ed on read, and this property is evaluated on every body pass
    /// (including ~10 Hz while a reply streams).
    private var slashMatches: [SkillSummary] {
        guard !slashDismissed, let q = SlashCommands.query(in: inputText) else { return [] }
        return SlashCommands.matches(query: q, in: AgentPrompt.skillManager.summaries)
    }

    /// Up/Down/Return/Tab/Escape while the menu is open. Returns false when
    /// it is closed, so the composer keeps every key it owns today.
    private func handleSlashKey(_ command: ComposerKeyCommand) -> Bool {
        let matches = slashMatches
        guard !matches.isEmpty else { return false }
        switch command {
        case .up:
            slashSelection = (slashSelection - 1 + matches.count) % matches.count
        case .down:
            slashSelection = (slashSelection + 1) % matches.count
        case .accept:
            pickSlashSkill(matches[min(slashSelection, matches.count - 1)])
        case .cancel:
            slashDismissed = true
        }
        return true
    }

    private func pickSlashSkill(_ skill: SkillSummary) {
        inputText = SlashCommands.accept(skill.name, in: inputText)
        slashSelection = 0
        inputFocused = true
    }

    private var composerState: ChatTurnEngine.ComposerState {
        chatEngine.composerState(for: sessionId)
    }

    private var thinkingModelID: String {
        appState.thinkingModelID
    }

    private func syncTogglesFromSession() {
        guard let session else { return }
        let preference = appState.thinkingPreference(for: session)
        enableThinking = preference.enabled
        reasoningEffort = preference.effort
    }

    private var isExternalBridgeSession: Bool { session?.isExternalBridge == true }

    private var toolbarToggles: ChatModeToggles {
        let resolved = resolvedChatSettings
        var toggles = ChatModeToggles.resolve(
            inAppThinking: enableThinking, inAppAgent: resolved.toolsEnabled,
            inAppMCP: resolved.mcpEnabled, agentLock: agentModeLock,
            apple: appState.useAppleModel)
        if session?.isPlainChat == true {
            toggles.agent = false
            toggles.mcp = false
        }
        return toggles
    }

    private var resolvedChatSettings: ResolvedAgentSettings {
        appState.resolvedChatSettings(for: session ?? ChatSession())
    }

    /// What this tab's agent decided about Think / Tools / MCP, nil with no agent.
    private var agentModeLock: AgentModeLock? {
        guard let agent = activeAgent else { return nil }
        let resolved = resolvedChatSettings
        return AgentModeLock(name: agent.name,
                             // The only one an agent may leave to the chat.
                             thinking: agent.enableThinking,
                             tools: resolved.toolsEnabled,
                             mcp: resolved.mcpEnabled)
    }

    // MARK: Mode controls (Think / Tools / MCP)

    private var serverStartControl: ChatServerStartControl {
        ChatServerStartControl.resolve(
            status: server.status,
            hasStartableModel: !appState.useAppleModel
                && (!appState.selectedModelPath.isEmpty || server.lanChatModelId != nil))
    }

    // The per-tab agent PICKER used to sit here, between the paperclip and the
    // mode discs. Starting a chat as an agent lives in the sidebar's Agents
    // destination now:

    /// The agent this tab is talking to (nil = none).
    private var activeAgent: Agent? { appState.agents.agent(id: session?.agentId) }

    /// Files for this message, or a document folder to ask questions about.
    private var attachmentMenu: some View {
        Button {
            showAttachmentPicker.toggle()
        } label: {
            ComposerControlSymbol(name: "plus")
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.regular)
        .composerTip(.attachments(audioSupported: audioSupported, videoSupported: videoSupported))
        .popover(isPresented: $showAttachmentPicker, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add to message")
                    .font(.app(.headline))
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                attachmentPickerRow(
                    title: attachmentMenuLabel,
                    description: "Include files with your next message.",
                    icon: "photo.on.rectangle", action: pickAttachment)
                Divider().padding(.horizontal, 10)
                attachmentPickerRow(
                    title: "Attach Folder for Q&A…",
                    description: "Ask questions about documents in a folder.",
                    icon: "folder.badge.questionmark", action: pickDocumentFolder)
            }
            .padding(8)
            .frame(width: columnWidth > 0 ? min(340, max(1, columnWidth - 32)) : 340)
        }
    }

    private func attachmentPickerRow(title: String, description: String, icon: String,
                                     action: @escaping () -> Void) -> some View {
        Button {
            showAttachmentPicker = false
            DispatchQueue.main.async(execute: action)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.app(.title3))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text(title))
                        .font(.app(.body, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(L10n.text(description))
                        .font(.app(.callout))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .controlSize(.large)
    }

    private var attachmentMenuLabel: String {
        switch (videoSupported, audioSupported) {
        case (true, true): return "Attach Image, Video, PDF, or Audio…"
        case (true, false): return "Attach Image, Video, or PDF…"
        case (false, true): return "Attach Image, PDF, or Audio…"
        case (false, false): return "Attach Image or PDF…"
        }
    }

    /// What a locked disc offers instead of its own controls: who decided it, and
    /// the way to the place where that decision lives. A locked control that does
    /// nothing at all on click is the dead-control class — this is the same shape
    /// as the tool menu's "not in <agent>'s capabilities" rows.
    @ViewBuilder
    private func lockedModeMenu(_ agentName: String) -> some View {
        if agentName == AppleFoundationChat.displayName {
            // Not an agent, and nothing to edit: the on-device model simply
            // does not have these.
            Text(L10n.format("Not available on %@", AppleFoundationChat.displayName))
        } else {
            Text(L10n.format("Set by %@", agentName))
            Button {
                // ON that agent — the window otherwise opens on whoever sorts
                // first, which is the wrong one every time you got here from a
                // card that just named a different name.
                guard let id = activeAgent?.id else { return }
                appState.openAgentSettings(id, using: openWindow)
            } label: { Text("Edit Agent…")
                .font(.app(.body)) }
        }
    }

    private var thinkingBinding: Binding<Bool> {
        Binding(get: { toolbarToggles.thinking }, set: { value in
            updateThinking(enabled: value, effort: reasoningEffort)
        })
    }

    private var reasoningEffortBinding: Binding<ReasoningEffort> {
        Binding(get: { reasoningEffort }, set: { value in
            updateThinking(enabled: enableThinking, effort: value)
        })
    }

    private func updateThinking(enabled: Bool, effort: ReasoningEffort) {
        guard !isExternalBridgeSession, toolbarToggles.thinkingLockedBy == nil,
              !thinkingModelID.isEmpty, !appState.useAppleModel,
              let index = appState.chatSessions.firstIndex(where: { $0.id == sessionId }) else { return }
        enableThinking = enabled
        reasoningEffort = effort
        appState.chatSessions[index].enableThinking = enabled
        appState.chatSessions[index].reasoningEffort = effort
        appState.modelThinkingPreferences.values[thinkingModelID] =
            ModelThinkingPreference(enabled: enabled, effort: effort)
    }

    private var thinkingHeader: some View {
        let label = ComposerThinkingPresentation.summary(
            isOn: toolbarToggles.thinking, effort: reasoningEffort,
            isExternalBridge: isExternalBridgeSession,
            lockedBy: toolbarToggles.thinkingLockedBy)
        return Text(L10n.text(label))
            .font(.app(.title3, weight: .medium))
            .foregroundStyle(toolbarToggles.thinking ? Color.orange : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .overlay(alignment: .trailing) {
                Button {
                    updateThinking(enabled: false, effort: .low)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .disabled(toolbarToggles.thinkingLockedBy != nil)
                .help("Reset thinking to Off and effort to Low")
                .accessibilityLabel("Reset thinking")
            }
    }

    private var thinkingSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let owner = toolbarToggles.thinkingLockedBy {
                lockedModeMenu(owner)
            } else if !isExternalBridgeSession {
                ReasoningEffortSlider(isOn: thinkingBinding, effort: reasoningEffortBinding)
            }
        }
    }

    private var thinkingAccessibilityHint: String {
        if toolbarToggles.thinkingLockedBy == AppleFoundationChat.displayName {
            return L10n.format("Not available on %@", AppleFoundationChat.displayName)
        }
        return ComposerTip.thinking(isOn: toolbarToggles.thinking,
            lockedBy: toolbarToggles.thinkingLockedBy).body
    }

    private var chatModeMenu: some View {
        Button { showChatMode.toggle() } label: {
            HStack(spacing: 6) {
                Label(session?.isPlainChat == true ? "Plain Chat" : "Tools & MCP",
                      systemImage: session?.isPlainChat == true ? "text.bubble" : "slider.horizontal.3")
                Image(systemName: "chevron.down")
                    .font(.app(.caption2, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .font(.app(.body))
            .padding(.horizontal, ComposerControlMetrics.horizontalPadding)
            .frame(minHeight: ComposerControlMetrics.height)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .composerCapsule()
        .popover(isPresented: $showChatMode, arrowEdge: .top) {
            chatModeControls
        }
        .help("Tools and MCP for this conversation")
    }

    private var chatModeControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                chatModeSwitch("Plain Chat", isOn: Binding(
                    get: { session?.isPlainChat == true }, set: setPlainChat))
                Text("Turn off Tools, MCP, and attached-folder search for this conversation.")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            chatModeSwitch("Tools", isOn: toolModeBinding(\.toolsEnabled))
                .disabled(session?.isPlainChat == true || agentForbidsTools)
            chatModeSwitch("MCP", isOn: toolModeBinding(\.mcpEnabled))
                .disabled(session?.isPlainChat == true || appState.useAppleModel
                          || activeAgent?.capabilities.mcp == false)
            Divider()
            Button("Use Settings Defaults") {
                updateToolPreferences(ChatToolPreferences(plainChat: session?.isPlainChat ?? false))
            }
            Button("Tools & MCP Settings…") { appState.showSettings(category: .tools) }
            if let agent = activeAgent {
                Button("Edit Agent…") { appState.openAgentSettings(agent.id, using: openWindow) }
            }
            Divider()
            Button("Workspace…") {
                if let picked = WorkspacePicker.pickDirectory() {
                    workingDirectoryBinding.wrappedValue = picked
                }
            }
            if let directory = session?.workingDirectory, !directory.isEmpty {
                Text(verbatim: directory)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
        .toggleStyle(.switch)
        .buttonStyle(.borderless)
        .padding(16)
        .frame(width: 280)
    }

    private func chatModeSwitch(_ title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: isOn)
                .labelsHidden()
        }
        .frame(maxWidth: .infinity)
    }

    private var agentForbidsTools: Bool {
        activeAgent.map { $0.capabilities.resolvedTools().isEmpty } ?? false
    }

    private func toolModeBinding(_ keyPath: WritableKeyPath<ChatToolPreferences, Bool?>) -> Binding<Bool> {
        Binding(get: {
            keyPath == \ChatToolPreferences.toolsEnabled ? toolbarToggles.agent : toolbarToggles.mcp
        }, set: { enabled in
            var preferences = session?.toolPreferences ?? ChatToolPreferences(followsDefaults: false)
            preferences[keyPath: keyPath] = enabled
            updateToolPreferences(preferences)
        })
    }

    private func setPlainChat(_ enabled: Bool) {
        var preferences = session?.toolPreferences ?? ChatToolPreferences(followsDefaults: false)
        preferences.plainChat = enabled
        updateToolPreferences(preferences)
    }

    private func updateToolPreferences(_ preferences: ChatToolPreferences) {
        guard !isExternalBridgeSession,
              let index = appState.chatSessions.firstIndex(where: { $0.id == sessionId }) else { return }
        let previous = resolvedChatSettings
        appState.chatSessions[index].toolPreferences = preferences
        let current = resolvedChatSettings
        appState.saveChatHistory()
        toolAllowList.rearm(sessionId)
        if preferences.plainChat {
            chatEngine.revokeAllTools(sessionId: sessionId)
        } else {
            if previous.toolsEnabled && !current.toolsEnabled { chatEngine.revokeTools(sessionId: sessionId) }
            if previous.mcpEnabled && !current.mcpEnabled { chatEngine.revokeMCP(sessionId: sessionId) }
        }
        if preferences.plainChat || (previous.toolsEnabled && !current.toolsEnabled)
            || (previous.mcpEnabled && !current.mcpEnabled) {
            appState.voice.revokeToolApprovals(for: sessionId)
            if let request = pendingApproval, request.scope?.sessionID == sessionId {
                request.continuation.resume(returning: .deny)
                pendingApproval = nil
            }
        }
    }

    /// A conversation with nothing in it yet. Rendered instead of an empty
    /// scroll view so the composer sits under a greeting in the middle of the
    /// window rather than pinned to the bottom of a blank page.
    private var isEmptyConversation: Bool {
        (session?.messages.isEmpty ?? true) && composerState != .generatingHere
    }

    /// Which reply Cmd+R / the footer's Regenerate button targets — the
    /// last assistant message, so the button only ever shows on that one.
    private var lastAssistantMessageId: UUID? {
        session?.messages.last { $0.role == .assistant }?.id
    }

    /// The greeting and optional agent description above an empty input. The vertical slack
    /// lives OUTSIDE this view (two sibling Spacers in the body) — a Spacer
    /// nested in here shares space unevenly with the body's own trailing one,
    /// which is what pinned the whole group to the bottom of the window.
    private var emptyState: some View {
        VStack(spacing: 8) {
            // Plain SF Pro, one solid colour. It was `design: .rounded` under a
            // top-to-bottom LinearGradient — a different typeface from the rest
            // of the app, wearing a fade that reads as a rendering artefact at
            // this size rather than as depth.
            // The agent's NAME, not the word "Agent" with the name as its
            // caption — the name is the thing, the category isn't (same
            // inversion the sidebar rows had). Under it, what the agent is
            // FOR, which is what tells you what to ask it.
            Text(ChatGreeting.heading(agentName: activeAgent?.name))
                .font(.app(.largeTitle, weight: .semibold))
                .foregroundStyle(.primary)
            if let subtitle = ChatGreeting.subtitle(agentBrief: activeAgent?.brief,
                                                    serverRunning: canAnswer) {
                Text(L10n.text(subtitle))
                    .font(.app(.callout))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

        }
        // Same column as the transcript and the composer below it, so the
        // greeting sits over the field rather than spanning the window.
        .chatColumn(width: contentWidth)
        .padding(.bottom, 22)
    }

    var body: some View {
        VStack(spacing: 0) {
            if isEmptyConversation {
                // Two SIBLING spacers (this one + the trailing one below the
                // composer) split the slack evenly, so greeting + chips +
                // composer sit as one group in the middle of the window.
                Spacer(minLength: 0)
                emptyState
            } else {
            // Messages
                ScrollView {
                    // Not lazy: a lazy stack ESTIMATES its height from the rows
                    // it has built, and every scroll decision below aims at
                    // that number (story: docs/gotchas/app.md).
                    VStack(spacing: ChatMetrics.transcriptSpacing) {
                        if firstVisibleRow > 0 {
                            showEarlierButton
                        }
                        ForEach(rows[firstVisibleRow...]) { row in
                            switch row {
                            case .message(let m):
                                MessageBubble(
                                    message: m,
                                    sources: sourcesFor(m),
                                    onIncreaseContext: {
                                        let path = appState.selectedModelPath
                                        let has = ModelSettingsFile.load().override(for: path)?.hasSettings ?? false
                                        switch ContextIncreaseTarget.resolve(hasOverride: has) {
                                        case .modelSettings:
                                            modelSettings = ModelSettingsRequest(path: path, title: ModelDisplayName.pretty((path as NSString).lastPathComponent))
                                        case .appSettings:
                                            appState.showSettings(category: .server)
                                        }
                                    },
                                    // Your message goes alone. A reply takes
                                    // the model's turn above it with it, and
                                    // only where the transcript can be cut.
                                    onDelete: deletionAction(for: m),
                                    // Both roles are editable, and they mean
                                    // different things. Editing YOUR message
                                    // is a re-ask: the turns after it answered
                                    // something you no longer said, so they go
                                    // and it resubmits. Editing the MODEL's is
                                    // putting words in its mouth — that turn
                                    // already happened, and the point is to
                                    // steer what comes next (Continue, or the
                                    // following turn), so nothing is dropped
                                    // and nothing re-runs.
                                    onEdit: session?.isExternalBridge == true ? nil : { newText in
                                        if m.role == .user {
                                            editAndResend(messageId: m.id, newText: newText)
                                        } else {
                                            appState.editAssistantMessage(in: sessionId,
                                                                          messageId: m.id,
                                                                          newText: newText)
                                        }
                                    },
                                    onRegenerate: (m.role == .assistant && m.id == lastAssistantMessageId)
                                        ? { regenerateLastResponse() }
                                        : nil,
                                    // Only the last message: a continuation
                                    // streams into the END of the transcript,
                                    // so offering it on an earlier reply would
                                    // append the text to a different bubble.
                                    onContinue: (m.id == session?.messages.last?.id && canContinue)
                                        ? { continueReply() }
                                        : nil,
                                    onSelectRevision: { index in
                                        appState.selectRevision(in: sessionId,
                                                                messageId: m.id,
                                                                index: index)
                                    },
                                    // Branch here. Offered on both roles and at
                                    // any depth — unlike Continue and
                                    // Regenerate, which act on the END of the
                                    // transcript, a fork is a statement about
                                    // this message. A task run or a bridge
                                    // mirror can be branched INTO an ordinary
                                    // chat, so no read-only gate: nothing about
                                    // the source is changed.
                                    onFork: ChatFork.isForkable(session?.messages ?? [], at: m.id)
                                        ? { appState.forkSession(sessionId, from: m.id) }
                                        : nil,
                                    onWillResize: { applyScroll(.rowWillResize) },
                                    onDidResize: { applyScroll(.rowDidResize) },
                                    foldStore: foldStore)
                                .equatable()
                                .id(m.id)
                            case .toolCall(let call, let results, let calls, let owned):
                                ToolCallRow(call: call, results: results, calls: calls,
                                            ownedHandles: owned,
                                            sessionId: sessionId).id(call.id)
                            }
                        }
                        // A property of the transcript's END, not of a row: the
                        // turn stopped on something that carries no footer.
                        if let last = session?.messages.last,
                           ChatTurn.needsEndFooter(session?.messages ?? [],
                                                   turnInFlight: composerState == .generatingHere) {
                            TurnEndFooter(
                                endedAt: last.timestamp,
                                onRegenerate: canRegenerate ? { regenerateLastResponse() } : nil,
                                onDelete: { requestMessageDeletion(last.id) })
                        }
                        // Live media generation, under the tool-call row that
                        // started it. These block chat decode on the one GPU for
                        // anything from seconds to minutes, so the alternative is
                        // a window that looks frozen. Only in the chat whose turn
                        // ASKED for it — with concurrent turns, ownership rides
                        // `mediaProgressSessionId`, not just "is generating".
                        if composerState == .generatingHere,
                           chatEngine.mediaProgressSessionId == sessionId,
                           let progress = chatEngine.mediaProgress {
                            MediaProgressCard(progress: progress)
                                .id("mediaProgress")
                        }
                    }
                    // The reading measure. The window is free to be as wide as
                    // the user wants; the prose is not (`ChatMetrics`).
                    .chatColumn(width: contentWidth)
                    .padding(.vertical, 20)
                }
                .contentMargins(.bottom, inputAreaHeight, for: .scrollContent)
                .sheet(item: $modelSettings) { ModelSettingsSheet(request: $0).environmentObject(appState).environmentObject(server).environmentObject(appState.downloads) }
                // Transcript text used to run straight into the floating model
                // picker. The toolbar band's own full-width background stays
                // hidden (the cluster carries its own material — that's what
                // keeps content from bleeding THROUGH the controls); this is
                // the other half, frosting the content as it passes UNDER them,
                // drawn by the scroll view itself so nothing new can intercept
                // a click.
                .scrollEdgeEffectStyle(.soft, for: .top)
                // A chat opens at its newest line by LAYOUT, with the real
                // heights in hand, not by a jump aimed at an estimate of them.
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                // The transcript is moved from exactly one place — `applyScroll`
                // — and only ever by a decision `ChatScrollState` made.
                .scrollPosition($scrollPosition)
                // While following, the scroll view keeps its own bottom edge
                // glued as the content grows, so a streamed token costs NOTHING:
                .defaultScrollAnchor(scrollModel.isPinnedToBottom ? .bottom : nil,
                                     for: .sizeChanges)
                // The scroll view's OWN geometry says how far the end sits below
                // the fold. This replaces a preference key published by a 1pt
                // anchor view, which raced the layout it was measuring and could
                // not see the viewport at all without a second preference key.
                .onScrollGeometryChange(for: CGFloat.self) {
                    ChatScrollState.distanceFromBottom($0)
                } action: { _, distance in
                    applyScroll(.geometryChanged(distanceFromBottom: distance))
                }
                // The two numbers a fold's correction is made of.
                .onScrollGeometryChange(for: CGPoint.self) {
                    CGPoint(x: $0.contentOffset.y, y: $0.contentSize.height)
                } action: { _, g in
                    applyScroll(.contentGeometry(offsetY: g.x, contentHeight: g.y))
                }
                // Who is moving it. The predecessor was an app-global NSEvent
                // scroll-wheel monitor: it fired for every other window in the
                // app, disengaged on a single upward notch (including the
                // rubber-band settle after flinging TO the bottom, which is why
                // auto-follow so often refused to come back), and was blind to
                // scroller drags, keyboard scrolling and window resizes.
                .onScrollPhaseChange { _, phase in
                    applyScroll(.driverChanged(ChatScrollDriver(phase)))
                }
                .overlay(alignment: .bottom) {
                    // The old affordance was a 4pt accent strip with hit-testing
                    // off: it reported the state and offered no way out of it.
                    Group {
                        if !scrollModel.isPinnedToBottom {
                            jumpToLatestButton
                                .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        }
                    }
                    .padding(.bottom, inputAreaHeight)
                    .animation(.easeInOut(duration: 0.18), value: scrollModel.isPinnedToBottom)
                }
                // A new conversation is a new scroll view, laid out from its
                // initial anchor instead of inheriting an offset measured in
                // the transcript it replaces. A metrics change rebuilds every
                // row anyway (they read `ChatMetrics` at build time).
                .id("transcript-\(sessionId)-\(interfaceTextSize)")
            }   // end else (non-empty conversation)

            if isEmptyConversation {
                inputArea
            }
            // The top spacer's sibling — see the empty-state branch above.
            if isEmptyConversation { Spacer(minLength: 0) }
        }
        .overlay(alignment: .bottom) {
            if !isEmptyConversation { inputArea }
        }
        // Cmd+R — regenerate the last reply. A zero-size hidden button rather
        // than a window-level `.commands` entry: it needs THIS tab's session
        // and toolbar state, and disabling it here (rather than graying out a
        // menu item elsewhere) is what keeps it from firing mid-stream or on
        // an empty chat.
        .background(
            Button(action: regenerateLastResponse) { EmptyView() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!canRegenerate)
                .frame(width: 0, height: 0)
                .opacity(0)
        )
        .onDrop(of: [.image, .pdf, .audio, .movie], isTargeted: nil) { providers in
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                    provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, _ in
                        guard let url = url else { return }
                        let name = url.lastPathComponent
                        if let text = Self.extractPDFText(from: url) {
                            DispatchQueue.main.async {
                                pendingPDFs.append((name: name, text: text))
                            }
                        } else {
                            DispatchQueue.main.async { showPDFError(name) }
                        }
                    }
                } else if audioSupported, provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier) {
                    // Decode inside the closure — the temp URL is only valid here.
                    provider.loadFileRepresentation(forTypeIdentifier: UTType.audio.identifier) { url, _ in
                        guard let url = url else { return }
                        let name = url.lastPathComponent
                        let pcm = AudioPreprocessor.preprocess(url: url)
                        DispatchQueue.main.async {
                            if let pcm, pcm.count >= 4 {
                                pendingAudio.append(ChatAudio(name: name, pcm: pcm))
                            } else {
                                showAudioError(name)
                            }
                        }
                    }
                } else if videoSupported, provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    // The temp URL is only valid inside the closure and frame
                    // extraction is async, so decode from a copy we own.
                    provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                        guard let url = url else { return }
                        let copy = FileManager.default.temporaryDirectory
                            .appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
                        guard (try? FileManager.default.copyItem(at: url, to: copy)) != nil else {
                            DispatchQueue.main.async { showVideoError(url.lastPathComponent) }
                            return
                        }
                        DispatchQueue.main.async {
                            addVideoAttachment(copy, name: url.lastPathComponent, removeAfter: true)
                        }
                    }
                } else if let imageType = provider.registeredTypeIdentifiers.first(where: {
                    UTType($0)?.conforms(to: .image) == true
                }) {
                    // The image's OWN bytes, asked for by the type the provider
                    // actually REGISTERED — a Finder drag of a PNG registers
                    // `public.png`, not `public.image`, so a request for the
                    // umbrella type fails. `loadItem` hands back the file URL
                    // (Finder) or the data, and either way the encoding survives:
                    // `loadObject(ofClass: NSImage.self)` decodes to an NSImage
                    // and throws the bytes away, so a dropped PNG used to be
                    // stored as a re-encoded JPEG.
                    //
                    // The name comes from the URL when there is one and from
                    // `suggestedName` otherwise (`droppedName`); an extension
                    // neither supplies comes from the bytes themselves
                    // (`AttachmentStore.payload`).
                    //
                    // The fallback is for a provider that only offers the decoded
                    // object. It is not what makes a browser drag work: a drag
                    // out of a page registers `public.jpeg` with NO loader block
                    // behind it (measured, Brave), so nothing loads by any route
                    // and the drop does nothing — as it did before this change.
                    let suggested = provider.suggestedName
                    provider.loadItem(forTypeIdentifier: imageType) { item, _ in
                        let url = item as? URL
                        let bytes: Data? = (item as? Data) ?? url.flatMap { try? Data(contentsOf: $0) }
                        if let bytes, let image = NSImage(data: bytes) {
                            let name = AttachmentStore.droppedName(url: url, suggested: suggested)
                            DispatchQueue.main.async {
                                pendingImages.append(PendingImage(image: image, original: bytes, filename: name))
                            }
                            return
                        }
                        provider.loadObject(ofClass: NSImage.self) { image, _ in
                            guard let image = image as? NSImage else { return }
                            DispatchQueue.main.async {
                                pendingImages.append(PendingImage(image: image))
                            }
                        }
                    }
                }
            }
            return true
        }
        // Typed-turn approvals only. Voice turns approve through the
        // controller's own `pendingApproval`, rendered inline next to the orb
        // (and in the tray) — never through this sheet.
        .sheet(item: $pendingApproval) { req in
            ToolApprovalSheet(request: req,
                              onAllow: { resolveApproval(.allow, requestID: req.id) },
                              onDeny: { resolveApproval(.deny, requestID: req.id) },
                              onAllowAll: { resolveApproval(.allow, requestID: req.id, allowAll: true) })
        }
        .alert(L10n.text(pendingMessageDeletion?.title ?? "Delete Message?"),
               isPresented: Binding(get: { pendingMessageDeletion != nil },
                                    set: { if !$0 { pendingMessageDeletion = nil } }),
               presenting: pendingMessageDeletion) { request in
            Button("Cancel", role: .cancel) {
                resolveMessageDeletion(request, confirmed: false)
            }
            .keyboardShortcut(.defaultAction)
            Button(L10n.text(request.actionLabel), role: .destructive) {
                resolveMessageDeletion(request, confirmed: true)
            }
            .disabled(composerState == .generatingHere)
        } message: { request in
            Text(L10n.text(request.explanation))
        }
        .onAppear {
            inputFocused = true
            syncTogglesFromSession()
            restoreAttachedFolderIfNeeded()
            recoverSteeringNoteIfIdle()
            applyScroll(.transcriptShown)
            // Cmd+V into the focused chat input: if the clipboard holds an image,
            // PDF, or folder, attach it (same as the attach button / drag-drop)
            // and swallow the paste; plain text still pastes into the field.
            pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard inputFocused,
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                      event.charactersIgnoringModifiers == "v"
                else { return event }
                return pasteAttachmentsFromClipboard() ? nil : event
            }
        }
        .onDisappear {
            // Generation lives on the app-level engine now — closing the chat
            // window must NOT cancel an in-flight turn (the voice assistant may
            // be driving it with no window open). Only tear down this view's
            // paste monitor.
            if let monitor = pasteMonitor {
                NSEvent.removeMonitor(monitor)
                pasteMonitor = nil
            }
        }
        .onChange(of: thinkingModelID) { _, _ in syncTogglesFromSession() }
        .onChange(of: appState.modelThinkingPreferences) { _, _ in syncTogglesFromSession() }
        .onChange(of: composerState) { _, state in
            if state == .idle {
                // A turn that ended without reaching a step (Stop, an error)
                // leaves its note nowhere to go: back into the composer.
                pauseSteeringNote()
                inputFocused = true
            }
        }
        // The keyboard arriving in the composer collapses the sidebar selection
        // to this chat. Keyed on the focus MIRROR rather than on the click, so
        // it covers every way the field ends up holding the keyboard — and the
        // rule is what keeps ⌘⌫ from raising a delete dialog mid-message with
        // several chats still lit behind the field.
        .onChange(of: inputFocused) { _, focused in
            guard focused,
                  let collapsed = SidebarMultiSelect.focusingComposer(
                      in: sessionId, selection: appState.sidebarSelection)
            else { return }
            appState.sidebarSelection = collapsed
        }
        .onChange(of: session?.messages, initial: true) { _, msgs in
            rows = ChatRowBuilder.rows(from: msgs ?? [])
            if windowSession != sessionId {
                cutTranscriptWindow()
            } else {
                firstVisibleRow = TranscriptWindow.clamp(first: firstVisibleRow, total: rows.count)
            }
        }
        .onChange(of: sessionId) { _, _ in
            pendingMessageDeletion = nil
            // The view is reused across tabs, so reload the toolbar toggles from
            // the newly-visible session. The allow-list is NOT reset here — it's
            // keyed by session id, so each tab keeps its own decision across
            // switches (a session re-arms only when its Agent toggle goes off).
            syncTogglesFromSession()
            restoreAttachedFolderIfNeeded()
            recoverSteeringNoteIfIdle()
            // Scroll state is per-view, and the view is reused across tabs — so
            // without this, leaving one chat scrolled up opened the next one
            // unpinned at whatever offset the previous conversation's content
            // happened to leave behind.
            applyScroll(.transcriptShown)
            // The binding outlives the scroll view too: a point a fold set in
            // the old conversation would be what the new one attaches to,
            // instead of its initial anchor.
            scrollPosition = ScrollPosition(idType: Never.self, edge: .bottom)
            // Rebuilt here as well so the cut does not depend on whether the
            // messages observer ran first (it runs only when the messages
            // differ, which a fork's do not).
            rows = ChatRowBuilder.rows(from: session?.messages ?? [])
            cutTranscriptWindow()
            // A history walk belongs to ONE conversation. Stale indexes are
            // harmless (ComposerHistory reads a mismatched draft as no walk),
            // but the first ↑ in the newly-visible tab has to mean "the last
            // thing I said HERE".
            composerWalk = .idle
            // Unfolding a long turn belongs to the visit, not to the message:
            // nothing about it is written to disk, so carrying it across
            // conversations would remember it until the next launch and no
            // further, which the reader can rely on in neither direction.
            foldStore.clear()
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { columnWidth = $0 }
    }

    private var inputArea: some View {
        VStack(spacing: 4) {
          if session?.isExternalBridge == true {
            // Archived bridge transcripts remain readable and can be branched.
            HStack(spacing: 8) {
                Image(systemName: "paperplane.fill")
                    .foregroundStyle(.secondary)
                Text("Archived conversation — view only.")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
          } else {
            // Pending attachment thumbnails (images + PDFs + videos + audio)
            if !pendingImages.isEmpty || !pendingPDFs.isEmpty || !pendingVideos.isEmpty || !pendingAudio.isEmpty {
                AttachmentPreviewRow(images: $pendingImages, pdfs: $pendingPDFs, videos: $pendingVideos, audio: $pendingAudio)
            }

            // Attached document folder (mini RAG) — indexing progress / ready chip
            if let docIndex = appState.documentIndexes[sessionId] {
                DocumentFolderChip(index: docIndex) {
                    docIndex.cancel()
                    appState.documentIndexes.removeValue(forKey: sessionId)
                    // Detach is a user decision — drop the persisted pick
                    // too, or the folder would re-attach on next launch.
                    if let idx = appState.chatSessions.firstIndex(where: { $0.id == sessionId }) {
                        appState.chatSessions[idx].attachedFolderPath = nil
                    }
                    SecurityScopedBookmark.clear(
                        name: SecurityScopedBookmark.attachedFolderName(sessionId))
                }
            }

            // Voice mode lives INLINE: a talking orb just above the input,
            // not a sheet over the transcript (the sheet hid the
            // conversation and duplicated the composer's own toggles).
            // Renders nothing while voice is off.
            VoiceOrbView(controller: appState.voice, sessionId: sessionId)

            // The note waiting for the agent's next step, where the user
            // is looking during a long run.
            if let note = steeringNote {
                SteeringNoteRow(note: note, onPause: { pauseSteeringNote() })
            }

            // One rounded container, two rows: the input on top with the
            // full width of the column, its controls beneath — inside the
            // same border, so they read as belonging to it.
            VStack(alignment: .leading, spacing: AppLayout.compactSpacing) {
                composerField
                composerControls
            }
            .floatingInputSurface()
            // "/" skill menu — FLOATS over the transcript rather than
            // sitting in the bar: as a sibling it grew the composer and
            // shoved the conversation up on every keystroke. An overlay
            // past the clip, its own bottom guide pinned to the
            // container's top, so it needs no height to position itself.
            // Not an NSPopover — that takes first responder, and the menu
            // has to stay open while you keep typing.
            .overlay(alignment: .topLeading) {
                if !slashMatches.isEmpty {
                    SlashSkillMenu(matches: slashMatches,
                                   selection: min(slashSelection, max(0, slashMatches.count - 1)),
                                   onPick: { pickSlashSkill($0) })
                        .alignmentGuide(.top) { $0[.bottom] + 8 }
                        .shadow(color: .black.opacity(0.28), radius: 14, y: 4)
                }
            }
          }   // end editable conversation
        }
        .chatColumn(width: contentWidth)
        .padding(.vertical, 10)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { inputAreaHeight = $0 }
    }

    /// The input field. No background or border of its own — the composer
    /// container draws those around both rows. NSTextView-backed so a big paste
    /// stays smooth and the mouse wheel scrolls once it grows past the cap.
    /// While this chat answers, the field takes a steering note: Return hands
    /// it to the agent at its next step instead of sending a second turn.
    private var composerPlaceholder: String {
        composerState == .generatingHere ? "Type a note; Return sends it at the next step" : "Ask me anything…"
    }

    private var composerField: some View {
        GrowingTextEditor(text: $inputText,
                          isFocused: $inputFocused,
                          measuredHeight: $composerHeight,
                          isIdle: composerState == .idle,
                          canSteer: true,
                          onSend: { sendMessage() },
                          // Escape stops the reply being written. Handled here
                          // rather than as a hidden `.cancelAction` button so
                          // the edit bubble and the approval sheet keep the key
                          // while they are up (ComposerKey.onEscape).
                          onCancel: {
                              switch ComposerKey.onEscape(isGenerating: composerState == .generatingHere) {
                              case .stop: stopGeneration(); return true
                              case .pass: return false
                              }
                          },
                          onArrow: { direction, caretAtStart, caretAtEnd in
                              recallHistory(direction, caretAtStart: caretAtStart, caretAtEnd: caretAtEnd)
                          },
                          onKeyCommand: { handleSlashKey($0) })
            .composerTextField(height: composerHeight,
                               placeholder: inputText.isEmpty ? composerPlaceholder : nil)
            .disabled(!canAnswer)
            // Escape closes the menu for the text as it stands; the next
            // keystroke is a new query, so it opens again.
            .onChange(of: inputText) { _, _ in
                if slashDismissed { slashDismissed = false }
                slashSelection = 0
            }
    }

    /// Keep mode labels readable when the detail column narrows.
    private var composerControls: some View {
        ComposerControlsRow {
            composerModes
        } model: {
            composerModel
        } actions: {
            composerActions
        }
    }

    private var composerModes: some View {
        HStack(spacing: 6) {
            attachmentMenu
            if audioSupported {
                MicButton(recorder: recorder) { toggleRecording() }
                    .disabled(server.status != .running || composerState == .generatingHere)
            }
            chatModeMenu
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var composerModel: some View {
        HStack(spacing: 6) {
            ChatModelPill(
                compact: true,
                reasoningLabel: ComposerThinkingPresentation.summary(
                    isOn: toolbarToggles.thinking, effort: reasoningEffort,
                    isExternalBridge: isExternalBridgeSession,
                    lockedBy: toolbarToggles.thinkingLockedBy),
                reasoningLocked: toolbarToggles.thinkingLockedBy != nil,
                thinkingHint: thinkingAccessibilityHint,
                thinkingHeader: AnyView(thinkingHeader),
                thinkingControls: AnyView(thinkingSettings),
                contextControl: showsContextPill ? AnyView(
                    ContextPill(stats: contextStats,
                                decodeSpeed: lastDecodeSpeed,
                                isLive: composerState == .generatingHere)) : nil,
                startControl: serverStartControl,
                onStart: { appState.startServer(loadingSelection: true) })
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var composerActions: some View {
        HStack(spacing: 6) {
            voiceToggle
            ComposerActionButton(isRunning: composerState == .generatingHere,
                                 label: composerState == .generatingHere ? "Stop generating" : "Send message") {
                if composerState == .generatingHere {
                    stopGeneration()
                } else {
                    sendMessage()
                }
            }
            .disabled(!canAnswer
                      || (composerState == .idle
                          && inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          && pendingImages.isEmpty && pendingPDFs.isEmpty && pendingVideos.isEmpty && pendingAudio.isEmpty))
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// Composer-row voice toggle — see `VoiceComposerToggle` for why it's an
    /// observing child view rather than a Button reading `appState.voice` here.
    private var voiceToggle: some View {
        VoiceComposerToggle(controller: appState.voice, sessionId: sessionId,
                            disabled: server.status != .running) { startVoiceMode() }
    }

    // MARK: - Document Folder (mini RAG)

    /// Pick a folder of mixed documents to index in-memory for this session.
    private func pickDocumentFolder() {
        let panel = OpenPanel.make()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder of documents to ask questions about (txt, md, pdf, json, yaml, csv …)"
        panel.prompt = "Attach"
        AppActivation.beginPanel(panel) { response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async { attachDocumentFolder(url) }
        }
    }

    /// Index a folder for mini-RAG. Shared by the folder picker and paste/drop so
    /// every entry point behaves identically. Embeds on the local server's GPU;
    /// auto-downloads the default encoder model (35 MB, one-time) when none is
    /// available. Server down → lexical-only retrieval. Must run on the main actor.
    private func attachDocumentFolder(_ url: URL) {
        SecurityScopedBookmark.store(url, name: SecurityScopedBookmark.attachedFolderName(sessionId))
        if let idx = appState.chatSessions.firstIndex(where: { $0.id == sessionId }) {
            appState.chatSessions[idx].attachedFolderPath = url.path
        }
        appState.documentIndexes[sessionId]?.cancel()
        let index = DocumentIndex(folderURL: url,
                                  embedderProvider: ServerEmbedding.autoProvider(port: server.port))
        appState.documentIndexes[sessionId] = index
        index.startIndexing()
    }

    /// Rebuild a persisted attached folder's index after a relaunch. The view is
    /// reused across tabs, so this runs on appear AND on every session change;
    /// a session with a live index (or none attached) is a no-op.
    private func restoreAttachedFolderIfNeeded() {
        guard !isExternalBridgeSession,
              appState.documentIndexes[sessionId] == nil,
              let path = session?.attachedFolderPath else { return }
        // Resolve the bookmark first (starts the sandbox grant). A missing or
        // dead bookmark (DMG build, folder relocated) falls back to the raw
        // path — outside the sandbox it is directly accessible anyway.
        let url = SecurityScopedBookmark.startAccessOnce(
            name: SecurityScopedBookmark.attachedFolderName(sessionId))
            ?? URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let index = DocumentIndex(folderURL: url,
                                  embedderProvider: ServerEmbedding.autoProvider(port: server.port))
        appState.documentIndexes[sessionId] = index
        index.startIndexing()
    }

    // MARK: - Paste-to-attach

    /// Route the current clipboard to the same pending-attachment lists as the
    /// attach button (image / PDF / audio) and the folder picker (mini-RAG).
    /// Returns true when something was attached, so the caller can swallow the
    /// Cmd+V instead of letting it fall through to the text field.
    private func pasteAttachmentsFromClipboard() -> Bool {
        let pb = NSPasteboard.general
        var handled = false
        // Finder copies (folder / PDF / image file / audio file) arrive as real
        // file URLs — read them directly (NOT loadFileRepresentation) so a pasted
        // folder is indexed in place rather than as a sandboxed temp copy.
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            for url in urls where attachFileURL(url) { handled = true }
        }
        if handled { return true }
        // Raw image data (screenshots, copy-image-from-a-browser) — no file URL.
        //
        // Take the pasteboard's PNG when it has one, so a copied PNG is stored
        // byte for byte. What it usually has is TIFF, which is UNCOMPRESSED: a
        // 3000x2000 screenshot is ~24 MB of it, so those bytes are deliberately
        // NOT kept and `AttachmentStore` encodes the image to PNG instead.
        if let image = NSImage(pasteboard: pb) {
            let png = pb.data(forType: .png)
            pendingImages.append(PendingImage(image: image, original: png))
            return true
        }
        return false
    }

    /// Dispatch one file URL to the matching attachment path. Returns false for
    /// unsupported types so the caller leaves the paste alone.
    private func attachFileURL(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }
        switch PasteFileKind.classify(ext: url.pathExtension, isDirectory: isDir.boolValue, audioSupported: audioSupported, videoSupported: videoSupported) {
        case .folder:
            attachDocumentFolder(url)
        case .pdf:
            if let text = Self.extractPDFText(from: url) {
                pendingPDFs.append((name: url.lastPathComponent, text: text))
            } else {
                showPDFError(url.lastPathComponent)
            }
        case .audio:
            addAudioAttachment(url)
        case .video:
            addVideoAttachment(url)
        case .image:
            guard let bytes = try? Data(contentsOf: url),
                  let image = NSImage(data: bytes) else { return false }
            pendingImages.append(PendingImage(image: image, original: bytes,
                                              filename: url.lastPathComponent))
        case .unhandled:
            return false
        }
        return true
    }

    // MARK: - Image Helpers

    private func pickAttachment() {
        let panel = OpenPanel.make()
        // Only offer audio/video on models that can use them.
        var types: [UTType] = [.image, .pdf]
        if videoSupported { types.append(.movie) }
        if audioSupported { types.append(.audio) }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        AppActivation.beginPanel(panel) { response in
            guard response == .OK else { return }
            for url in panel.urls {
                if url.pathExtension.lowercased() == "pdf" {
                    if let text = Self.extractPDFText(from: url) {
                        pendingPDFs.append((name: url.lastPathComponent, text: text))
                    } else {
                        showPDFError(url.lastPathComponent)
                    }
                } else if let utType = UTType(filenameExtension: url.pathExtension), utType.conforms(to: .audio) {
                    addAudioAttachment(url)
                } else if videoSupported, let utType = UTType(filenameExtension: url.pathExtension), utType.conforms(to: .movie) {
                    addVideoAttachment(url)
                } else if let bytes = try? Data(contentsOf: url),
                          let image = NSImage(data: bytes) {
                    pendingImages.append(PendingImage(image: image, original: bytes,
                                                      filename: url.lastPathComponent))
                }
            }
        }
    }

    /// Decode an audio file to 16 kHz mono float32 PCM (off the main thread —
    /// AVFoundation decode can be slow) and add it as a pending attachment.
    private func addAudioAttachment(_ url: URL) {
        let name = url.lastPathComponent
        DispatchQueue.global(qos: .userInitiated).async {
            let pcm = AudioPreprocessor.preprocess(url: url)
            DispatchQueue.main.async {
                if let pcm, pcm.count >= 4 {
                    pendingAudio.append(ChatAudio(name: name, pcm: pcm))
                } else {
                    showAudioError(name)
                }
            }
        }
    }

    private func showAudioError(_ name: String) {
        let alert = NSAlert()
        alert.messageText = L10n.text("Couldn't read audio")
        alert.informativeText = L10n.format("%@ couldn't be decoded. Supported: wav, mp3, m4a, aiff, caf, flac.", name)
        alert.alertStyle = .warning
        alert.runModal()
    }

    /// Extract frames from a video file (off the main thread — AVFoundation
    /// decode can be slow) and add it as a pending attachment.
    private func addVideoAttachment(_ url: URL, name: String? = nil, removeAfter: Bool = false) {
        let name = name ?? url.lastPathComponent
        Task.detached(priority: .userInitiated) {
            let frames = await VideoPreprocessor.extractFrames(url: url)
            if removeAfter { try? FileManager.default.removeItem(at: url) }
            await MainActor.run {
                if let frames, !frames.isEmpty {
                    pendingVideos.append(ChatVideo(name: name, frames: frames))
                } else {
                    showVideoError(name)
                }
            }
        }
    }

    private func showVideoError(_ name: String) {
        let alert = NSAlert()
        alert.messageText = L10n.text("Couldn't read video")
        alert.informativeText = L10n.format("%@ couldn't be decoded.", name)
        alert.alertStyle = .warning
        alert.runModal()
    }

    /// Convert pending audio clips to a ChatAudio array, clearing the list.
    /// Written on SEND like the pictures (`AudioClipFile.stored`).
    private func consumePendingAudio() -> [ChatAudio]? {
        guard !pendingAudio.isEmpty else { return nil }
        let clips = pendingAudio.map { AudioClipFile.stored($0) }
        pendingAudio = []
        return clips
    }

    /// Whether the active model understands audio (Gemma 4 12B unified). Gates
    /// the mic button and audio-file attachment so they only appear where audio
    /// actually does something.
    private var audioSupported: Bool { server.chatModelInfo?.supportsAudio ?? false }

    /// Whether the active model understands video (Qwen3-VL-family checkpoints
    /// declaring `video_token_id`). Gates the video-attach option so it only
    /// appears where the server can actually read it.
    private var videoSupported: Bool { server.chatModelInfo?.supportsVideo ?? false }

    /// Convert pending videos to a ChatVideo array, clearing the list.
    /// Written on SEND like the pictures (`AttachmentStore.storedVideo`).
    private func consumePendingVideos() -> [ChatVideo]? {
        guard !pendingVideos.isEmpty else { return nil }
        let videos = pendingVideos.map { AttachmentStore.storedVideo($0) }
        pendingVideos = []
        return videos
    }

    /// Mic tap handler: start recording (after a permission check), or stop and
    /// turn the captured PCM into a pending audio attachment.
    private func toggleRecording() {
        if recorder.isRecording {
            if let pcm = recorder.stop(), pcm.count >= 4 {
                // The chips print the duration themselves; a name carrying it too read
                // "Recording · 4s · 3.8s" and would land in the filename.
                pendingAudio.append(ChatAudio(name: "Recording", pcm: pcm))
            }
            return
        }
        Task {
            let granted = await AudioRecorder.requestPermission()
            guard granted else { showMicPermissionError(); return }
            do {
                try recorder.start()
            } catch {
                showAudioError("the microphone")
            }
        }
    }

    private func showMicPermissionError() {
        let alert = NSAlert()
        alert.messageText = L10n.text("Microphone access needed")
        alert.informativeText = L10n.text("Enable microphone access for MLX-Serve in System Settings → Privacy & Security → Microphone, then try again.")
        alert.alertStyle = .warning
        alert.runModal()
    }

    /// Returns nil if the PDF is unreadable, encrypted, or contains no extractable text
    /// (e.g. scanned-image-only PDFs without an OCR layer).
    static func extractPDFText(from url: URL) -> String? {
        guard let pdf = PDFDocument(url: url),
              let text = pdf.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }

    private func showPDFError(_ name: String) {
        let alert = NSAlert()
        alert.messageText = L10n.text("Couldn't read PDF")
        alert.informativeText = L10n.format("%@ is empty, encrypted, or contains only scanned images (no extractable text).", name)
        alert.alertStyle = .warning
        alert.runModal()
    }

    /// Build a preamble string that joins all pending PDFs and clears the list.
    /// Returns "" when nothing is pending.
    private func consumePendingPDFsAsText() -> String {
        guard !pendingPDFs.isEmpty else { return "" }
        let combined = pendingPDFs.map { "[PDF: \($0.name)]\n\($0.text)" }.joined(separator: "\n\n")
        pendingPDFs = []
        return combined
    }

    /// Write the pending attachments out and hand back the messages' images,
    /// clearing the pending list.
    ///
    /// Written on SEND, not on attach: the preview row lets an attachment be
    /// removed again, and a file per abandoned pick is how a folder fills up
    /// with things no conversation names.
    ///
    /// A failed write is not fatal to the turn. The `ChatImage` keeps its bytes,
    /// so the model still sees the picture and the transcript still draws it —
    /// only the next launch finds no file, and says so.
    private func consumePendingImages() -> [ChatImage]? {
        guard !pendingImages.isEmpty else { return nil }
        let chatImages = pendingImages.compactMap { pending -> ChatImage? in
            var image = ChatImage(data: Data())
            guard let payload = AttachmentStore.payload(for: pending, id: image.id) else { return nil }
            image.data = payload.data
            image.path = AttachmentStore.write(payload.data, named: payload.name)
            return image
        }
        pendingImages = []
        return chatImages.isEmpty ? nil : chatImages
    }

    // MARK: - Helpers

    /// Route one event through the decision core and carry out whatever it asks
    /// for. The ONLY place in this view that moves the transcript.
    private func applyScroll(_ event: ChatScrollEvent) {
        switch scrollModel.apply(event) {
        case .none:
            break
        case .toBottom(let animated):
            if case .geometryChanged = event {
                // `onScrollGeometryChange` delivers its action INSIDE the
                // window's layout flush, and `scrollPosition` is @State —
                // writing it there re-enters layout while AppKit is mid-flush.
                // Under a streaming re-layout storm (code block re-highlights,
                // then markdown re-measures) that loop is the #136 beachball,
                // and the write that lands at the wrong point in the flush is
                // the uncaught NSException crash (live crash log 2026-08-09:
                // StoredLocationBase.beginUpdate → setNeedsUpdateConstraints →
                // _crashOnException). One runloop turn later is outside the
                // flush, and coalesces the storm to one correction per turn.
                DispatchQueue.main.async { performScroll(animated: animated) }
            } else {
                // Button taps and sends run from event handling, not layout —
                // they stay synchronous so the jump lands with the click.
                performScroll(animated: animated)
            }
        case .toOffset(let y):
            // From a geometry callback, so out of the layout flush (#136).
            DispatchQueue.main.async {
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) { scrollPosition.scrollTo(y: y) }
            }
        }
    }

    private func performScroll(animated: Bool) {
        if animated {
            // A discrete jump the user asked for (their own message, the
            // button) — the movement is the feedback that it landed.
            withAnimation(.easeOut(duration: 0.2)) {
                scrollPosition.scrollTo(edge: .bottom)
            }
        } else {
            // Following the stream is a direct offset set, explicitly
            // unanimated: this used to run a 0.15s `withAnimation` per
            // STREAMED TOKEN, so dozens of animations a second each started
            // over the top of the one still running. That is the stutter,
            // and it got worse the longer the transcript grew.
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                scrollPosition.scrollTo(edge: .bottom)
            }
        }
    }

    /// Above the first laid-out row of a long conversation.
    private var showEarlierButton: some View {
        Button {
            revealEarlierRows()
        } label: {
            Group {
                if isRevealingEarlier {
                    ProgressView().controlSize(.mini)
                } else {
                    Text("Show earlier messages")
                }
            }
            .font(.app(.caption).weight(.medium))
            .foregroundStyle(.secondary)
            .frame(height: 22)
            .padding(.horizontal, 12)
            .background(Color.secondary.opacity(0.15), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }

    /// A delete shortens the transcript at or above the control that asked for
    /// it, so it rides the resize bracket a fold uses.
    private func deleteKeepingPlace(_ change: @escaping () -> Void) {
        applyScroll(.rowWillResize)
        change()
        DispatchQueue.main.async { DispatchQueue.main.async { applyScroll(.rowDidResize) } }
    }

    private func deletionAction(for message: ChatMessage) -> (() -> Void)? {
        guard composerState != .generatingHere, !message.isStreaming,
              message.role == .user || ChatTurn.footerDeletes(
                message, isLast: message.id == session?.messages.last?.id)
        else { return nil }
        return { requestMessageDeletion(message.id) }
    }

    private func requestMessageDeletion(_ id: UUID) {
        pendingMessageDeletion = ChatDeletionRequest.make(
            sessionId: sessionId, messageId: id, messages: session?.messages ?? [],
            turnInFlight: composerState == .generatingHere)
    }

    private func resolveMessageDeletion(_ request: ChatDeletionRequest, confirmed: Bool) {
        pendingMessageDeletion = nil
        guard let deletion = request.resolve(confirmed: confirmed, in: sessionId,
                                              messages: session?.messages ?? [],
                                              turnInFlight: composerState == .generatingHere)
        else { return }
        deleteKeepingPlace {
            switch deletion.scope {
            case .message:
                appState.deleteMessage(in: deletion.sessionId, messageId: deletion.messageId)
            case .turn:
                appState.deleteTurn(in: deletion.sessionId, endingAt: deletion.messageId)
            }
        }
    }

    private func cutTranscriptWindow() {
        windowSession = sessionId
        firstVisibleRow = TranscriptWindow.firstRow(total: rows.count)
    }

    /// The rows appear ABOVE what the reader is looking at, so the transcript
    /// holds their place through it (the same bracket a fold uses), and the
    /// button answers the click before the layout that makes it slow starts.
    private func revealEarlierRows() {
        isRevealingEarlier = true
        applyScroll(.rowWillResize)
        DispatchQueue.main.async {
            firstVisibleRow = 0
            DispatchQueue.main.async {
                DispatchQueue.main.async {
                    applyScroll(.rowDidResize)
                    isRevealingEarlier = false
                }
            }
        }
    }

    /// Shown only while auto-follow is off — its absence is how the transcript
    /// says it is already following.
    private var jumpToLatestButton: some View {
        Button { applyScroll(.jumpTapped) } label: {
            Image(systemName: "arrow.down")
                .font(.app(.callout, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help("Jump to the latest message")
        .padding(.bottom, 12)
    }


    /// Latest context usage from the most recent assistant message with token
    /// data — the prompt size + the reply's length of the last completed turn.
    private var contextUsage: (promptTokens: Int, completionTokens: Int, contextLength: Int)? {
        guard let messages = session?.messages else { return nil }
        if let last = messages.last(where: { $0.promptTokens != nil && $0.promptTokens! > 0 }) {
            let ctxLen = AgentEngine.effectiveContextLength(
                appContextSize: appState.contextSize,
                modelContextLength: server.chatModelInfo?.contextLength,
                apple: appState.useAppleModel
            )
            return (promptTokens: last.promptTokens!, completionTokens: last.completionTokens ?? 0, contextLength: ctxLen)
        }
        return nil
    }

    /// Pages a web search backed this reply with. Only computed for a finished
    /// assistant reply — tool-call summaries and user turns have no provenance
    /// to show, and the walk is bounded by the previous user message so this
    /// stays cheap per row.
    private func sourcesFor(_ message: ChatMessage) -> [WebSource] {
        guard message.role == .assistant, !message.isAgentSummary, !message.isStreaming,
              let messages = session?.messages else { return [] }
        return WebSourceExtractor.sources(forMessageId: message.id, in: messages)
    }

    /// The context-overflow notice from the turn that just ended, if that's how
    /// it ended. Scoped to the LAST message on purpose: an overflow the user has
    /// since worked around (shorter prompt, tools off) must stop colouring the
    /// pill red, or the gauge keeps reporting a failure that no longer applies.
    private var lastOverflowNotice: ChatErrorNotice? {
        guard let notice = session?.messages.last?.errorNotice,
              notice.kind == .contextOverflow else { return nil }
        return notice
    }

    /// Reading behind the composer's context pill.
    private var contextStats: ContextWindowStats {
        let usage = contextUsage
        return ContextWindowStats.make(
            promptTokens: usage?.promptTokens ?? 0,
            completionTokens: usage?.completionTokens ?? 0,
            liveTokens: composerState == .generatingHere ? chatEngine.liveCompletionTokens(for: sessionId) : 0,
            contextLength: usage?.contextLength
                ?? AgentEngine.effectiveContextLength(appContextSize: appState.contextSize,
                                                      modelContextLength: server.chatModelInfo?.contextLength,
                                                      apple: appState.useAppleModel),
            overflow: lastOverflowNotice)
    }

    /// Decode speed of the most recent reply that was actually timed.
    private var lastDecodeSpeed: Double? {
        session?.messages.last { ($0.tokensPerSecond ?? 0) > 0 }?.tokensPerSecond
    }

    /// Hidden until there's something true to report — a pill reading 0.0%
    /// before the first reply is noise, not information.
    private var showsContextPill: Bool {
        contextUsage != nil || composerState == .generatingHere || lastOverflowNotice != nil
    }

    private var workingDirectoryBinding: Binding<String?> {
        Binding(
            get: { appState.chatSessions.first { $0.id == sessionId }?.workingDirectory },
            set: { newValue in
                if let idx = appState.chatSessions.firstIndex(where: { $0.id == sessionId }) {
                    appState.chatSessions[idx].workingDirectory = newValue
                    // Persist the panel's grant: without a security-scoped
                    // bookmark, a folder outside the container is unreachable
                    // after relaunch under the App Sandbox. Resolved at the
                    // agent-turn seam (ChatTurnEngine.runAgentTurn).
                    let slot = SecurityScopedBookmark.workingFolderName(sessionId)
                    if let dir = newValue {
                        appState.agentMemory.recordDirectory(dir)
                        SecurityScopedBookmark.store(URL(fileURLWithPath: dir), name: slot)
                    } else {
                        SecurityScopedBookmark.clear(name: slot)
                    }
                    // No eager remount: /workspace stays the Settings default
                    // (pi/hermes live there). This chat's folder is hot-mounted
                    // at /projects/<slug> the first time a tool runs — no VM
                    // reboot, so live CLI sessions are never torn down. Only a
                    // Settings default change remounts /workspace.
                }
            }
        )
    }

    // MARK: - Voice Mode

    /// Resume the pending tool-approval continuation with the user's choice.
    /// Drives the text-chat approval sheet (the in-window orb and tray panel
    /// resolve their own approvals through the controller).
    private func resolveApproval(_ choice: ToolApprovalChoice, requestID: UUID,
                                 allowAll: Bool = false) {
        guard let request = pendingApproval, request.id == requestID else { return }
        let scope = request.scope
        let origin = scope.flatMap { origin in appState.chatSessions.first { $0.id == origin.sessionID } }
        let current = scope.map {
            $0.isCurrent(sessionID: origin?.id ?? sessionId,
                         turnID: chatEngine.turnToken(sessionId: $0.sessionID),
                         plainChat: origin?.isPlainChat ?? true)
        } ?? false
        let decision: ToolApprovalChoice = current ? choice : .deny
        if allowAll, decision == .allow, let scope { toolAllowList.allowAll(scope.sessionID) }
        pendingApproval = nil
        request.continuation.resume(returning: decision)
    }

    /// Start hands-free voice from the composer toggle. The controller is
    /// app-level; the toggle already ended any voice running elsewhere (the
    /// "move it here" click), so by the time this runs the mic is free. The
    /// orb renders inline in the BOUND session's tab — nothing to "present".
    private func startVoiceMode() {
        guard !appState.voice.isActive else { return }
        // Sync the voice toggles to the chat session being opened — talking should
        // start in the same Think/Tools/MCP mode as the chat you launched it from.
        if let s = session {
            let resolved = appState.resolvedChatSettings(for: s)
            appState.voice.enableThinking = resolved.thinkingEnabled
            appState.voice.agentMode = resolved.toolsEnabled
            appState.voice.mcpMode = resolved.mcpEnabled
            // …and to the same AGENT. Voice routes each turn into its agent's own
            // thread, so without this a tray default of "Chef" would pull the
            // conversation out of the tab you launched voice from.
            appState.defaultAgentId = s.agentId
        }
        appState.sessionForAgent(session?.agentId)
        Task { _ = await appState.voice.begin() }   // on permission failure the orb shows the error
    }

    // MARK: - Send Message

    /// Thin wrapper: build the turn config from the toolbar @State, consume the
    /// input draft + attachments (View-owned UI state), and hand the turn to the
    /// shared `ChatTurnEngine`. The engine routes to plain chat or the agent loop
    /// based on `config.agentMode || config.mcpMode` — there is no separate
    /// agent send path here anymore. Voice turns go straight through the
    /// controller and never touch this method.
    private func sendMessage() {
        // Keyboard actions must respect the archived transcript's read-only state.
        if session?.isExternalBridge == true { return }

        // A busy chat takes the text as a steering note for the agent's next
        // step (`SteeringNotes`); the row above the composer shows it until
        // it fires.
        if composerState == .generatingHere {
            queueSteeringNote()
            return
        }

        // Sending ends any history walk: the composer is about to empty for a
        // different reason, and a live walk would make the next ↑ resume from
        // wherever the last one left off rather than from what was just sent.
        composerWalk = .idle
        proceedSend()
    }

    // MARK: - Steering notes

    private var steeringNote: String? { chatEngine.steering.note(for: sessionId) }

    private func queueSteeringNote() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        chatEngine.setSteeringNote(text, for: sessionId)
        inputText = ""
        composerWalk = .idle
    }

    /// Pausing takes the note back into the composer, ahead of whatever is
    /// typed there, so nothing fires while it is being rewritten; Return
    /// queues it again.
    private func pauseSteeringNote() {
        guard let note = steeringNote else { return }
        chatEngine.clearSteeringNote(for: sessionId)
        inputText = SteeringNotes.joined(note, inputText)
        inputFocused = true
    }

    /// A note whose turn ended while this chat was in another tab: nobody
    /// watched the state flip, so it is recovered on the way in.
    private func recoverSteeringNoteIfIdle() {
        if composerState == .idle { pauseSteeringNote() }
    }

    private func proceedSend() {
        var text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachedImages = consumePendingImages()
        let attachedVideos = consumePendingVideos()
        let attachedAudio = consumePendingAudio()
        let pdfText = consumePendingPDFsAsText()
        guard !text.isEmpty || attachedImages != nil || attachedVideos != nil || attachedAudio != nil || !pdfText.isEmpty,
              composerState != .generatingHere, canAnswer else { return }
        inputText = ""
        if !pdfText.isEmpty {
            text = text.isEmpty ? pdfText : pdfText + "\n\n" + text
        }

        chatEngine.runTurn(sessionId: sessionId, userText: text,
                           images: attachedImages, videos: attachedVideos, audio: attachedAudio,
                           config: buildTurnConfig(),
                           approval: { await requestToolApproval($0) })
        // Your own message always wins: sending from halfway up the history used
        // to leave you exactly there, because auto-follow was off and nothing
        // else scrolled.
        applyScroll(.userSentMessage)
    }

    /// The toolbar toggles are this surface's DEFAULTS; the tab's agent (if
    /// any) overrides what it declared. One builder, so no field is read from
    /// a global here — see ChatTurnEngine.TurnConfig. Shared by send, Cmd+R
    /// regenerate, and edit-and-resend so all three run under identical
    /// settings.
    private func buildTurnConfig() -> ChatTurnEngine.TurnConfig {
        var current = session ?? ChatSession()
        current.enableThinking = enableThinking
        current.reasoningEffort = reasoningEffort
        let resolved = appState.resolvedChatSettings(for: current)
        return ChatTurnEngine.TurnConfig.from(
            resolved, documentIndex: appState.documentIndexes[sessionId])
    }

    /// Whether this chat can answer at all. Apple's on-device model needs no
    /// server, so "the server is down" is not the same question as "nothing
    /// can answer" — every composer gate asks THIS, or the composer locks on a
    /// model that was ready to reply.
    private var canAnswer: Bool {
        ChatTurnEngine.canRunTurn(serverRunning: server.status == .running,
                                  apple: appState.useAppleModel)
    }

    /// Cmd+R — regenerate the last reply. Mirrors the footer's Regenerate
    /// button; both funnel through `ChatTurnEngine.regenerate`, which drops
    /// the last user turn and resubmits it fresh.
    private var canRegenerate: Bool {
        canAnswer && composerState != .generatingHere
            && session?.isExternalBridge != true
            && (session?.messages.contains { $0.role == .user } ?? false)
    }

    /// Whether the reply at the end of this transcript can be finished off.
    private var canContinue: Bool {
        ContinueReply.isEligible(session?.messages ?? [],
                                 serverRunning: server.status == .running,
                                 busy: composerState != .idle,
                                 engine: server.chatModelInfo?.engine)
    }

    /// Hand the last reply back to the model to finish. Same turn config as a
    /// send, so the continuation runs under the settings that produced it.
    private func continueReply() {
        guard canContinue else { return }
        chatEngine.continueReply(sessionId: sessionId, config: buildTurnConfig())
        // The text lands at the END of a reply already on screen, so follow it
        // down the same way a fresh send does.
        applyScroll(.userSentMessage)
    }

    /// ↑ / ↓ in the composer: bring back an earlier message of your own.
    ///
    /// The rule is `ComposerHistory`, which decides from the draft, the caret
    /// position and where the walk currently sits — everything here does is
    /// feed it this chat's history and write the answer back. Returning false
    /// hands the key to AppKit, which is what makes the arrows still move the
    /// caret inside a draft.
    private func recallHistory(_ direction: ComposerHistory.Direction,
                               caretAtStart: Bool, caretAtEnd: Bool) -> Bool {
        // A waiting steering note is the newest thing said and not yet sent:
        // ↑ on an empty draft takes it back first, exactly as Pause does.
        if direction == .up, steeringNote != nil,
           inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pauseSteeringNote()
            return true
        }
        let entries = ComposerHistory.entries(session?.messages ?? [])
        let action = direction == .up
            ? ComposerHistory.up(draft: inputText, caretAtStart: caretAtStart,
                                 walk: composerWalk, entries: entries)
            : ComposerHistory.down(draft: inputText, caretAtEnd: caretAtEnd,
                                   walk: composerWalk, entries: entries)
        switch action {
        case .pass:
            return false
        case .recall(let text, let walk):
            inputText = text
            composerWalk = walk
            return true
        }
    }

    /// Stop this chat's turn. The ONE call both the composer's stop disc and
    /// Escape make — per-session, because other tabs may be generating and
    /// neither control may reach across.
    private func stopGeneration() {
        chatEngine.stop(sessionId: sessionId)
    }

    private func regenerateLastResponse() {
        guard canRegenerate else { return }
        chatEngine.regenerate(sessionId: sessionId, config: buildTurnConfig(),
                               approval: { await requestToolApproval($0) })
        // Same rule as a fresh send: the reply you just asked for is the thing
        // to be looking at, wherever in the history the request came from.
        applyScroll(.userSentMessage)
    }

    /// Edit a past user message in place, then resend it: everything from
    /// that message onward (its old reply, any tool chain) is dropped and the
    /// edited text runs as a brand-new turn — the standard "edit and resend"
    /// behaviour rather than silently rewriting history the model already
    /// answered.
    private func editAndResend(messageId: UUID, newText: String) {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let msgs = session?.messages,
              let idx = msgs.firstIndex(where: { $0.id == messageId })
        else { return }
        let images = msgs[idx].images
        let videos = msgs[idx].videos
        let audio = msgs[idx].audio
        appState.truncateMessages(in: sessionId, keepingFirst: idx)
        chatEngine.runTurn(sessionId: sessionId, userText: trimmed,
                           images: images, videos: videos, audio: audio,
                           config: buildTurnConfig(),
                           approval: { await requestToolApproval($0) })
        // An edit is started from wherever that message sits, which is by
        // definition not the bottom — follow the resend down to it.
        applyScroll(.userSentMessage)
    }

    /// Ask the user to approve a single tool call. Returns true on Allow /
    /// Always Allow, false on Deny. Bypassed entirely when this session is on
    /// the allow-list. Bounces to the main actor (state mutations + sheet
    /// presentation) and suspends on a checked continuation until the sheet
    /// resumes it.
    @MainActor
    private func requestToolApproval(_ tc: APIClient.ToolCall) async -> Bool {
        guard session?.isPlainChat != true,
              let token = chatEngine.turnToken(sessionId: sessionId) else { return false }
        if tc.name == "searchDocuments" { return true }
        if toolAllowList.allowsAll(sessionId) { return true }
        let scope = ToolApprovalScope(sessionID: sessionId, turnID: token)
        let choice: ToolApprovalChoice = await withCheckedContinuation { continuation in
            // The shared sheet can show one request; never orphan a waiting turn.
            pendingApproval?.continuation.resume(returning: .deny)
            pendingApproval = ToolApprovalRequest(
                toolName: tc.name, arguments: tc.arguments, rawArguments: tc.rawArguments,
                continuation: continuation, scope: scope)
        }
        return choice == .allow && scope.isCurrent(
            sessionID: sessionId, turnID: chatEngine.turnToken(sessionId: sessionId),
            plainChat: session?.isPlainChat ?? true)
    }

}

// MARK: - Context Monitor

/// What the chat considers "occupied context".
enum ContextMonitor {
    /// Total context occupied right now: the last completed turn (prompt + its
    /// reply) plus the in-flight reply's running count. Pure → ContextMonitorTests.
    static func usedTokens(promptTokens: Int, completionTokens: Int, liveTokens: Int) -> Int {
        promptTokens + completionTokens + liveTokens
    }
}

// MARK: - Generating Indicator

/// Animated indicator shown while the model is generating, with live GPU and memory stats.
struct GeneratingIndicator: View {
    @State private var gpuPercent: Int = 0
    @State private var memPercent: Int = 0
    @State private var whimsy: String = Self.randomWhimsy()
    @State private var timer: Timer?
    @State private var startDate = Date()

    var body: some View {
        // The rings spin in Core Animation, not a per-frame SwiftUI timeline:
        // a timeline re-renders this window's whole hosting view every frame.
        HStack(spacing: 8) {
            ActivityRings(outer: max(0.1, Double(gpuPercent) / 100.0),
                          inner: max(0.1, Double(memPercent) / 100.0),
                          outerColor: gpuNSColor, innerColor: memNSColor)
                .frame(width: 20, height: 20)

            // Stats + whimsy
            Text(L10n.format("GPU %lld%%", gpuPercent))
                .foregroundStyle(gpuColor)
            Text("·")
                .foregroundStyle(.tertiary)
            Text(L10n.format("Mem %lld%%", memPercent))
                .foregroundStyle(memColor)
            Text("·")
                .foregroundStyle(.tertiary)
            Text(L10n.text(whimsy))
                .foregroundStyle(.secondary)
                .transition(.opacity)
            Text("·")
                .foregroundStyle(.tertiary)
            TimelineView(.periodic(from: startDate, by: 1)) { context in
                Text(Self.formatElapsed(context.date.timeIntervalSince(startDate)))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .font(.app(.caption2, weight: .medium, design: .monospaced))
        .onAppear {
            startDate = Date()
            pollMetrics()
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                pollMetrics()
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private var gpuColor: Color { Color(nsColor: gpuNSColor) }
    private var memColor: Color { Color(nsColor: memNSColor) }

    private var gpuNSColor: NSColor {
        if gpuPercent > 80 { return .systemOrange }
        if gpuPercent > 50 { return .systemGreen }
        return .systemBlue
    }

    private var memNSColor: NSColor {
        if memPercent > 85 { return .systemRed }
        if memPercent > 70 { return .systemOrange }
        return .secondaryLabelColor
    }

    private func pollMetrics() {
        gpuPercent = Int(SystemMetrics.gpuUtilization())
        memPercent = Int(SystemMetrics.memoryPressure())
        // Rotate whimsy every ~3 seconds
        if Int(Date().timeIntervalSince(startDate)) % 3 == 0 {
            withAnimation(.easeInOut(duration: 0.3)) {
                whimsy = Self.randomWhimsy()
            }
        }
    }

    /// The "Thinking…" line's word, looked up at the render site. Internal so
    /// the coverage test can hold every one of them to a catalog entry.
    static let whimsies = [
        "marinating", "boondoggling", "razzle-dazzling", "percolating",
        "simmering", "noodling", "cogitating", "ruminating",
        "brainstorming", "daydreaming", "scheming", "concocting",
        "fermenting", "hatching", "brewing", "stewing",
        "tinkering", "finagling", "wrangling", "bamboozling",
        "gallivanting", "meandering", "pondering", "mulling",
        "churning", "synthesizing", "vibing", "manifesting",
        "jazz-handing", "shimmer-thinking", "pixel-wrangling",
        "quantum-leaping", "brain-tickling", "thought-juggling",
    ]

    private static func randomWhimsy() -> String {
        whimsies.randomElement() ?? "thinking"
    }

    /// Compact elapsed-time format: "0s", "9s", "59s", "1m04s", "12m08s",
    /// "1h02m". Designed to read at 10pt monospaced without ever changing
    /// width by more than one glyph as the timer ticks.
    private static func formatElapsed(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        if total < 60 { return "\(total)s" }
        if total < 3600 {
            let m = total / 60, s = total % 60
            return String(format: "%dm%02ds", m, s)
        }
        let h = total / 3600, m = (total % 3600) / 60
        return String(format: "%dh%02dm", h, m)
    }
}

/// Two counter-rotating arcs and a pulsing dot, animated by the render server.
private struct ActivityRings: NSViewRepresentable {
    let outer: Double
    let inner: Double
    let outerColor: NSColor
    let innerColor: NSColor

    func makeNSView(context: Context) -> RingsView { RingsView() }

    func updateNSView(_ view: RingsView, context: Context) {
        view.set(outer: outer, inner: inner, outerColor: outerColor, innerColor: innerColor)
    }

    final class RingsView: NSView {
        private let outerRing = CAShapeLayer()
        private let innerRing = CAShapeLayer()
        private let dot = CALayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            for ring in [outerRing, innerRing] {
                ring.fillColor = nil
                ring.lineWidth = 2
                ring.lineCap = .round
                layer?.addSublayer(ring)
            }
            dot.cornerRadius = 1.5
            layer?.addSublayer(dot)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        func set(outer: Double, inner: Double, outerColor: NSColor, innerColor: NSColor) {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                outerRing.strokeColor = outerColor.cgColor
                innerRing.strokeColor = innerColor.cgColor
                dot.backgroundColor = outerColor.cgColor
            }
            outerRing.strokeEnd = outer
            innerRing.strokeEnd = inner
        }

        override func layout() {
            super.layout()
            place(outerRing, diameter: 18)
            place(innerRing, diameter: 10)
            dot.bounds = CGRect(x: 0, y: 0, width: 3, height: 3)
            dot.position = CGPoint(x: bounds.midX, y: bounds.midY)
        }

        private func place(_ ring: CAShapeLayer, diameter: CGFloat) {
            ring.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            ring.position = CGPoint(x: bounds.midX, y: bounds.midY)
            ring.path = CGPath(ellipseIn: ring.bounds, transform: nil)
        }

        /// A layer drops its animations when it leaves a window.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            spin(outerRing, degreesPerSecond: -120)
            spin(innerRing, degreesPerSecond: 168)
            let pulse = CABasicAnimation(keyPath: "transform.scale")
            pulse.fromValue = 0.7
            pulse.toValue = 1.3
            pulse.duration = 0.8
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            dot.add(pulse, forKey: "pulse")
        }

        private func spin(_ ring: CALayer, degreesPerSecond: Double) {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = 2 * Double.pi * (degreesPerSecond < 0 ? -1 : 1)
            spin.duration = 360 / abs(degreesPerSecond)
            spin.repeatCount = .infinity
            ring.add(spin, forKey: "spin")
        }
    }
}

// `SystemMetrics` (GPU utilization, memory pressure, and the libproc/Mach
// replacements for lsof/ps/vm_stat) lives in Services/SystemMetrics.swift.

// MARK: - Message Bubble

/// Attaches double-click-to-edit, or attaches NOTHING at all.
///
/// A `nil` action must leave the view untouched rather than install a gesture
/// that does nothing: this one is `highPriorityGesture`, so merely EXISTING is
/// enough to beat `textSelection`'s own double-click-to-select-word. A
/// no-op-inside-the-closure version therefore reads as "double-click stopped
/// selecting words" on exactly the messages nobody can edit.
private struct DoubleClickToEdit: ViewModifier {
    let action: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let action {
            content.highPriorityGesture(TapGesture(count: 2).onEnded { _ in action() })
        } else {
            content
        }
    }
}

/// A growing text as its lines, so a view per line leaves all but the last
/// untouched by a streamed batch. A blank line keeps its height as a space.
enum StreamingLines {
    static func split(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? " " : String($0) }
    }
}

/// A streamed batch rebuilds the transcript; a row whose inputs did not change
/// skips its body. The callbacks are compared by PRESENCE: each one only
/// routes to the session by id, and which ones a row carries is what changes
/// what it draws.
extension MessageBubble: Equatable {
    static func == (a: MessageBubble, b: MessageBubble) -> Bool {
        a.message == b.message && a.sources == b.sources
            && (a.onDelete == nil) == (b.onDelete == nil)
            && (a.onEdit == nil) == (b.onEdit == nil)
            && (a.onRegenerate == nil) == (b.onRegenerate == nil)
            && (a.onContinue == nil) == (b.onContinue == nil)
            && (a.onSelectRevision == nil) == (b.onSelectRevision == nil)
            && (a.onFork == nil) == (b.onFork == nil)
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    /// Pages a web search backed this reply with. Empty for every reply that
    /// didn't search, which is the normal case — the chip only exists when
    /// there is provenance to show.
    var sources: [WebSource] = []
    /// Opens Settings at the context control, for the overflow card's button.
    /// Defaults to a no-op so surfaces that only DISPLAY a transcript (the task
    /// run viewer) don't have to route an action they have no window for.
    var onIncreaseContext: () -> Void = {}
    /// Removes this message from the conversation. nil on read-only surfaces —
    /// a task run's transcript is a record, so it has no delete affordance
    /// rather than one that silently does nothing.
    var onDelete: (() -> Void)?
    /// Edit this (user) message's text and resend it, dropping everything
    /// that followed. nil for assistant messages and read-only surfaces —
    /// same reasoning as `onDelete`.
    var onEdit: ((String) -> Void)?
    /// Regenerate this reply. Only ever set on the LAST assistant message —
    /// the caller decides that, so the bubble itself doesn't need to know its
    /// position in the transcript.
    var onRegenerate: (() -> Void)?
    /// Hand this reply back to the model to finish. Present only on the last
    /// message, and only when it is continuable (`ContinueReply.isEligible`).
    var onContinue: (() -> Void)?
    /// Show a different generated version of this reply.
    var onSelectRevision: ((Int) -> Void)?
    /// Branch the conversation here: everything up to this message becomes a
    /// new chat and this one is left alone. nil when there would be nothing to
    /// fork (`ChatFork.isForkable`) or on a read-only surface.
    var onFork: (() -> Void)?
    /// Bracket a change that makes this row shorter (a fold, a thinking block
    /// closing, an edit field replacing the bubble), so the transcript can
    /// hold the reader's place through it. nil where there is no scroll view.
    var onWillResize: (() -> Void)?
    var onDidResize: (() -> Void)?
    /// Survives a transcript rebuild; see `FoldStore`.
    var foldStore: FoldStore?
    /// Hover over the whole row reveals the user turn's action row; the
    /// buttons themselves start invisible.
    /// Explicit so the accordion HEADER can drive it, not just the chevron.
    @State private var thinkingExpanded = false
    /// Unfolding a long turn is an act of reading, and it belongs to the row
    /// for the same reason the accordion above does: writing it into the
    /// transcript's own state re-evaluates every row in the conversation, and
    /// a fold has to feel like a click, not like a page load.
    @State private var longTurnExpanded = false
    /// Between the click and the layout it asks for. Laying out a long `Text`
    /// takes this thread for up to hundreds of milliseconds, so the control
    /// answers the click before that starts.
    @State private var isFolding = false
    @State private var isEditing = false
    @State private var editDraft = ""
    /// The edit field is the composer's field (`GrowingTextEditor`), so it
    /// needs the composer's two bindings: where the caret is, and how tall the
    /// text has grown.
    @State private var editFocused = false
    @State private var editHeight: CGFloat = 0

    var body: some View {
        // A failure notice is not model output: it renders as its own card
        // across the column, never inside an assistant bubble.
        if let notice = message.errorNotice {
            ChatErrorCard(notice: notice, onIncreaseContext: onIncreaseContext)
        } else {
            messageBody
        }
    }

    private var isThinkingNow: Bool {
        message.isStreaming && message.content.isEmpty
    }

    /// Hand-built, not a `DisclosureGroup`: that pins its chevron to the
    /// leading edge and hit-tests only the chevron.
    @ViewBuilder
    private var thinkingBlock: some View {
        if let reasoning = message.reasoningContent, !reasoning.isEmpty {
            VStack(alignment: .leading, spacing: AppLayout.compactSpacing) {
                HStack(spacing: AppLayout.compactSpacing) {
                    TranscriptDisclosureButton(isExpanded: thinkingExpanded) {
                        if thinkingExpanded {
                            resize { thinkingExpanded = false }
                        } else {
                            withAnimation(.easeInOut(duration: 0.15)) { thinkingExpanded = true }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "brain")
                                .symbolEffect(.pulse, isActive: isThinkingNow)
                            Text(L10n.text(ThinkingDuration.label(seconds: isThinkingNow ? nil : message.thinkingSeconds)))
                        }
                    }
                    if thinkingExpanded {
                        TranscriptReaderButton(title: "Thinking", textToCopy: reasoning) {
                            reasoningText(reasoning)
                        }
                    }
                }

                if thinkingExpanded {
                    TranscriptDetailSurface {
                        TranscriptDetailViewport(followsTail: isThinkingNow) {
                            reasoningText(reasoning)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func reasoningText(_ reasoning: String) -> some View {
        Group {
            if isThinkingNow {
                // Splitting streamed text avoids remeasuring one ever-growing Text.
                VStack(alignment: .leading, spacing: ChatMetrics.userLineSpacing) {
                    ForEach(Array(StreamingLines.split(reasoning).enumerated()), id: \.offset) { _, line in
                        Text(verbatim: line)
                    }
                }
            } else {
                Text(verbatim: reasoning).textSelection(.enabled)
            }
        }
        .transcriptDetailText()
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var messageBody: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                thinkingBlock

                // Attached images. Double-click opens the full image in Preview.
                //
                // A message carrying an image REF draws from its file instead
                // (ChatMediaAttachmentView). Generated images stopped shipping
                // bytes, but a history written before that still has both, and
                // drawing both would show the same picture twice. The ref wins:
                // it is the original the generator wrote, not a re-encode.
                if let images = message.images, !images.isEmpty,
                   message.media?.contains(where: { $0.kind == .image }) != true {
                    AttachmentFlowLayout(spacing: ChatMetrics.attachmentSpacing) {
                        ForEach(images) { img in
                            // No bytes: the file under `attachments/` is gone,
                            // or this message predates attachments on disk and
                            // its base64 is no longer read. Say so rather than
                            // leave a hole where a picture was.
                            if img.data.isEmpty {
                                Label("attachment no longer on disk", systemImage: "questionmark.folder")
                                    .font(.app(.caption))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(.quaternary.opacity(0.4))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                AttachmentImageCell(image: img)
                            }
                        }
                    }
                    // The whole column, not the bubble's reading measure.
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                // Generated tracks / clips, attached by path (see ChatMediaRef).
                if let media = message.media, !media.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(media) { ref in
                            ChatMediaAttachmentView(ref: ref)
                        }
                    }
                }

                // Attached audio clips. A clip whose file is gone says so, the
                // way a picture does: it was not sent, and a silent chip would
                // claim otherwise.
                if let clips = message.audio, !clips.isEmpty {
                    ForEach(clips) { clip in
                        if clip.pcm.isEmpty {
                            Label("\(clip.name) · file no longer on disk", systemImage: "questionmark.folder")
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(.quaternary.opacity(0.4))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Label(String(format: "%@ · %.1fs", clip.name, clip.durationSeconds), systemImage: "waveform")
                                .font(.app(.caption).weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.purple.opacity(0.18))
                                .clipShape(Capsule())
                        }
                    }
                }

                // Content.
                if isEditing, onEdit != nil {
                    editingContent
                } else if !message.content.isEmpty || message.isStreaming {
                    // Only the USER gets a bubble (`isBare` below). An assistant
                    // reply is the page's main content — long, formatted, full
                    // of code blocks and tables — and boxing it wastes the
                    // column's width and fights every block that wants the full
                    // measure. A tool-call summary keeps its card so it still
                    // reads as machinery, not prose.
                    VStack(alignment: .leading, spacing: 4) {
                        if message.isAgentSummary {
                            Label("Tool Call", systemImage: "wrench.and.screwdriver")
                                .font(.app(.caption2).weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        if message.role == .assistant {
                            MarkdownText(message.content.isEmpty && message.isStreaming ? " " : message.content)
                                .textSelection(.enabled)
                        } else {
                            // The user's own turn is plain text (no markdown
                            // render), so it needs the transcript size stated —
                            // otherwise your message and the reply to it are
                            // two different sizes in the same column.
                            Text(message.content)
                                .font(.system(size: ChatMetrics.transcriptFontSize))
                                // Same leading as the reply's renderer, or the
                                // two roles read at two densities.
                                .lineSpacing(ChatMetrics.userLineSpacing)
                                .textSelection(.enabled)
                                .lineLimit(isFolded ? LongUserTurn.collapsedLineLimit : nil)
                                // A folded `Text` reports the width of the
                                // lines it shows, so a bubble that hugged it
                                // would change width on unfold and re-lay the
                                // whole turn out at the new one. A turn this
                                // long is a full-width block either way.
                                .frame(maxWidth: foldsLongTurn ? .infinity : nil, alignment: .leading)
                                .overlay(alignment: .bottom) { foldFade }
                            if foldsLongTurn {
                                Group {
                                    if isFolding {
                                        // The spinner ignores `tint`; it draws
                                        // white in the dark scheme.
                                        ProgressView()
                                            .controlSize(.mini)
                                            .colorScheme(.dark)
                                    } else {
                                        Button { toggleLongTurn() } label: { Text(L10n.text(isFolded ? "Show more" : "Show less"))
                                            .font(.app(.body)) }
                                            .buttonStyle(.plain)
                                            .font(.app(.caption).weight(.medium))
                                            .foregroundStyle(.white.opacity(0.8))
                                    }
                                }
                                .padding(.top, ChatMetrics.foldToggleTopPadding)
                            }
                        }
                        if message.isStreaming {
                            GeneratingIndicator()
                        }
                    }
                    // `.highPriorityGesture`, not `.onTapGesture` — the `Text`
                    // above has `.textSelection(.enabled)`, which installs its
                    // OWN double-click-to-select-word handling. A plain
                    // `.onTapGesture(count: 2)` sits behind that in the
                    // gesture hierarchy and never sees the second click, so
                    // double-click silently did nothing. `highPriorityGesture`
                    // makes this the one that wins.
                    //
                    // Which is exactly why the `onEdit` test is on the MODIFIER
                    // and not inside the closure: a message with no edit action
                    // (every assistant reply, every read-only surface) would
                    // otherwise still install a winning gesture that beats
                    // text selection and then does nothing — killing
                    // double-click-to-select-a-word on the replies, which is
                    // most of what anyone selects.
                    // …and why the model's replies are excluded even though they
                    // ARE editable now: the gesture wins over text selection,
                    // and an assistant reply is prose people select words in.
                    // Its edit is reached from the context menu instead.
                    .modifier(DoubleClickToEdit(
                        action: (onEdit == nil || message.role != .user) ? nil : { startEditing() }))
                    .padding(.horizontal, isBare ? 0 : ChatMetrics.bubblePaddingH)
                    .padding(.vertical, isBare ? 0 : ChatMetrics.bubblePaddingV)
                    .background(bubbleBackground)
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: isBare ? 0 : ChatMetrics.bubbleCornerRadius, style: .continuous))
                    // Cap on the bubble, not the text: a frame on the text
                    // stretches a one-line question across the width.
                    .frame(maxWidth: message.role == .user ? ChatMetrics.userBubbleMaxWidth : .infinity,
                           alignment: isBare ? .leading : .trailing)
                }

                // A cut reply's notice: DATA on the message, drawn as a footnote
                // under the bubble — never appended into content, which rides
                // back to the model as history.
                if let notice = message.truncationNotice, !message.isStreaming {
                    Text(L10n.text(notice.text))
                        .font(.app(.callout))
                        .italic()
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.leading, isBare ? 0 : ChatMetrics.statsIndent)
                        .padding(.top, 2)
                }

                // Where the answer came from, above the footer — the provenance
                // belongs with the reply, not with its timings.
                if message.role == .assistant, !message.isStreaming, !sources.isEmpty {
                    WebSourcesChip(sources: sources)
                        .padding(.leading, isBare ? 0 : ChatMetrics.statsIndent)
                }

                if showsFooter { footer }
                if showsUserActions { userActions }
            }
            // Turn gap keyed on the footer, not the role: an assistant turn is
            // several rows (thinking-only message, tool card, reply).
            .padding(.bottom, message.role == .user
                     ? ChatMetrics.userBubbleBottomPadding
                     : (showsFooter ? ChatMetrics.assistantTurnBottomPadding : 0))
            .frame(maxWidth: .infinity,
                   alignment: message.role == .user ? .trailing : .leading)
        }
        .onAppear { longTurnExpanded = foldStore?.isExpanded(message.id) ?? false }
        // Hover must cover the transparent action row too, or it vanishes as
        // the pointer approaches it.
        .contentShape(Rectangle())
        .contextMenu {
            if !message.content.isEmpty {
                Button { copyMessage() } label: { Text("Copy Message")
                    .font(.app(.body)) }
            }
            if onEdit != nil, !message.content.isEmpty {
                // Named for what it DOES: editing your own message re-asks the
                // question, editing the model's rewrites what it said.
                Button(message.role == .user ? "Edit & Resend" : "Edit Reply") { startEditing() }
            }
            if onRegenerate != nil {
                Button { onRegenerate?() } label: { Text("Regenerate")
                    .font(.app(.body)) }
            }
            if let onFork {
                // Between the two destructive answers and Delete: a fork keeps
                // BOTH branches, so it belongs next to the ones that don't.
                Divider()
                Button(action: onFork, label: { Text("Branch Chat From Here")
                    .font(.app(.body)) })
            }
            if onDelete != nil {
                // A reply takes the model's whole turn with it (`ChatTurn`).
                Button(message.role == .user ? "Delete Message" : "Delete Turn", role: .destructive) { onDelete?() }
            }
        }
    }

    /// Replaces the static bubble while editing: a growing multi-line field
    /// pre-filled with the message's current text, Cancel / Save beneath it.
    /// Save hands the new text to `onEdit`, which drops this message and
    /// everything after it and resubmits — same shape as a fresh send.
    ///
    /// It is the COMPOSER's field, not a `TextEditor`. Editing a message is a
    /// send, so it answers the keyboard like one: Return submits, Shift+Return
    /// breaks the line — `ComposerKey.onReturn` decides for both, and
    /// `editCanSubmit` is the same gate that dims Save, so the key and the
    /// button can never disagree about whether this draft can go.
    private var editingContent: some View {
        VStack(alignment: .trailing, spacing: 8) {
            GrowingTextEditor(text: $editDraft,
                              isFocused: $editFocused,
                              measuredHeight: $editHeight,
                              maxLines: 12,
                              isIdle: ComposerKey.editCanSubmit(editDraft),
                              onSend: { commitEdit() },
                              // Belt and braces: the Cancel button's key
                              // equivalent claims Escape first while this is up.
                              onCancel: { cancelEdit(); return true })
                .frame(height: max(ChatMetrics.composerMinHeight, editHeight))
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor)) // Distinct surface fill
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.accentColor.opacity(0.6), lineWidth: 1.5) // Glowing outline
                )
                .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3) // Depth

            HStack(spacing: 8) {
                Button { cancelEdit() } label: { Text("Cancel")
                    .font(.app(.body)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)

                Button { commitEdit() } label: { Text("Save")
                    .font(.app(.body)) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!ComposerKey.editCanSubmit(editDraft))
            }
            .font(.app(.caption))
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func startEditing() {
        editDraft = message.content
        // The field is capped in height where the bubble was not, so on a long
        // turn it would otherwise open above the top of the window.
        resize(animated: false) {
            isEditing = true
            // Put the caret in the field the edit just opened — otherwise
            // Return is typed at whatever still holds focus (the composer
            // below), which sends a NEW message instead of the edit.
            editFocused = true
        }
    }

    private func cancelEdit() {
        isEditing = false
        editFocused = false
        editDraft = ""
    }

    private func commitEdit() {
        guard ComposerKey.editCanSubmit(editDraft) else { return }
        let text = editDraft
        isEditing = false
        editFocused = false
        onEdit?(text)
    }

    // MARK: - Bubble vs bare

    /// Assistant prose renders bare; user turns and tool-call summaries keep a
    /// bubble.
    private var isBare: Bool { message.role == .assistant && !message.isAgentSummary }

    // MARK: - Folding a long user turn

    private var userTurnCharsPerLine: Int {
        LongUserTurn.charsPerLine(
            textWidth: ChatMetrics.userBubbleMaxWidth - 2 * ChatMetrics.bubblePaddingH,
            fontSize: ChatMetrics.transcriptFontSize)
    }

    private var foldsLongTurn: Bool {
        guard message.role == .user, !message.isStreaming else { return false }
        return LongUserTurn.isCollapsible(message.content, charsPerLine: userTurnCharsPerLine)
    }

    private var isFolded: Bool { foldsLongTurn && !longTurnExpanded }

    /// Fades the last two kept lines into the bubble instead of ending them on
    /// an ellipsis, so a folded turn reads as continuing rather than as a
    /// sentence that stops.
    ///
    /// An overlay in the bubble's own colour, not a `mask`: a mask renders what
    /// it covers into an offscreen layer, and an unfolded turn is a layer
    /// thousands of points tall — which is hundreds of milliseconds per fold.
    @ViewBuilder
    private var foldFade: some View {
        if isFolded {
            // Stops short of covering the last line: a line faded to nothing
            // reads as the end of the message, one still faintly there reads as
            // more of it below.
            LinearGradient(colors: [bubbleBackground.opacity(0), bubbleBackground.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: (ChatMetrics.transcriptFontSize + ChatMetrics.userLineSpacing) * 2)
                .allowsHitTesting(false)
        }
    }

    private func toggleLongTurn() {
        let expanding = !longTurnExpanded
        foldStore?.set(message.id, expanded: expanding)
        isFolding = true
        // One turn later, so the indicator is drawn before the layout that
        // makes this click slow takes the thread.
        DispatchQueue.main.async {
            if expanding {
                withAnimation(.easeInOut(duration: 0.15)) {
                    longTurnExpanded = true
                } completion: {
                    isFolding = false
                }
            } else {
                resize({ longTurnExpanded = false }, done: { isFolding = false })
            }
        }
    }

    /// Brackets a change that makes this row shorter. The end is reported one
    /// turn after the change has landed, so the geometry of its last frame is
    /// seen inside the bracket.
    private func resize(animated: Bool = true, _ change: @escaping () -> Void,
                        done: (() -> Void)? = nil) {
        onWillResize?()
        let finish = { onDidResize?(); done?() }
        if animated {
            withAnimation(.easeInOut(duration: 0.15)) { change() } completion: {
                DispatchQueue.main.async(execute: finish)
            }
        } else {
            change()
            DispatchQueue.main.async { DispatchQueue.main.async(execute: finish) }
        }
    }

    private var bubbleBackground: Color {
        if isBare { return .clear }
        return message.role == .user ? Color.accentColor : Color(.controlBackgroundColor)
    }

    // MARK: - Footer (timestamp · actions · stats)

    /// One predicate with the transcript's end footer, which is its negation.
    private var showsFooter: Bool { ChatTurn.hasOwnFooter(message) }

    /// Persistent reply actions followed by quiet time and performance metadata.
    private var footer: some View {
        HStack(spacing: 8) {
            // Which version of this reply you are reading. Left of the actions
            // because it is a statement about the text above it, not another
            // thing to do to it — and it only exists once there is a choice.
            if MessageRevisions.isPagerVisible(message.revisions) {
                HStack(spacing: 1) {
                    footerButton("chevron.left", help: "Previous version of this reply") {
                        onSelectRevision?(MessageRevisions.step(index: message.activeRevision,
                                                                by: -1,
                                                                count: message.revisions.count))
                    }
                    .disabled(!MessageRevisions.canGoBack(index: message.activeRevision))
                    Text(
                                                MessageRevisions.label(index: message.activeRevision,
                                                count: message.revisions.count)
)
                        .font(.app(.caption2).monospacedDigit())
                        .foregroundStyle(.tertiary)
                    footerButton("chevron.right", help: "Next version of this reply") {
                        onSelectRevision?(MessageRevisions.step(index: message.activeRevision,
                                                                by: 1,
                                                                count: message.revisions.count))
                    }
                    .disabled(!MessageRevisions.canGoForward(index: message.activeRevision,
                                                             count: message.revisions.count))
                }
            }

            HStack(spacing: 4) {
                // A generated picture has a footer and no text to copy or edit.
                if !message.content.isEmpty {
                    footerButton("square.on.square", help: "Copy this reply") { copyMessage() }
                }
                // The model's replies are editable but have no double-click
                // route into it (that gesture belongs to selecting a word), so
                // without this the only way in is a context menu nobody thinks
                // to open on a paragraph.
                if onEdit != nil, message.role == .assistant, !message.content.isEmpty {
                    footerButton("pencil", help: "Edit this reply — then Continue to carry on from it") {
                        startEditing()
                    }
                }
                // Continue sits BEFORE regenerate: they are the two answers to
                // "this reply isn't what I need", and the non-destructive one
                // goes first — regenerate throws the reply away.
                if let onContinue {
                    footerButton("text.append",
                                 help: message.truncationNotice != nil
                                     ? "Finish this reply — it was cut short"
                                     : "Keep writing from where this left off",
                                 action: onContinue)
                }
                if let onRegenerate {
                    footerButton("arrow.clockwise", help: "Regenerate this reply (⌘R)",
                                 action: onRegenerate)
                }
                if let onDelete {
                    footerButton("trash", help: "Delete this turn from the conversation",
                                 action: onDelete)
                }
            }

            StatPill(text: message.timestamp.formatted(date: .omitted, time: .shortened),
                     expanded: message.timestamp.formatted(date: .numeric, time: .shortened))

            if let tps = message.tokensPerSecond, tps > 0 {
                // The format moves to the producer: `StatPill` renders its
                // strings verbatim, so a lookup of an already-built `"42 tok/sec"`
                // could never match a `%lld` key. Same shape as `ComposerTip`.
                let speed = L10n.format("%lld tok/sec", Int(tps))
                StatPill(text: speed,
                         expanded: message.completionTokens.map {
                             L10n.format("%lld tok/sec (%lld tokens)", Int(tps), $0)
                         } ?? speed)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, isBare ? 0 : ChatMetrics.statsIndent)
        .padding(.top, ChatMetrics.compactMode ? 2 : 8)
    }

    /// Not drawn at all in compact: an invisible row still holds its height.
    /// The context menu keeps the same actions.
    private var showsUserActions: Bool {
        message.role == .user && !message.isStreaming && !ChatMetrics.compactMode
    }

    private var userActions: some View {
        HStack(spacing: 2) {
            footerButton("square.on.square", help: "Copy this message") { copyMessage() }
            if onEdit != nil {
                footerButton("pencil", help: "Edit this message and send it again") { startEditing() }
            }
            if let onFork {
                // Flipped: this branches back from a message above you.
                footerButton("arrow.trianglehead.branch",
                             help: "Start a new chat from this message",
                             flipped: true, action: onFork)
            }
            if let onDelete {
                footerButton("trash", help: "Delete this message from the conversation",
                             action: onDelete)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, 2)
    }

    private func footerButton(_ icon: String, help: String, flipped: Bool = false,
                              action: @escaping () -> Void) -> some View {
        FooterIconButton(icon: icon, help: help, flipped: flipped, action: action)
    }

    private func copyMessage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
    }
}

/// One glyph of a footer's action row.
private struct FooterIconButton: View {
    let icon: String
    let help: String
    var flipped = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .regular))
                .scaleEffect(y: flipped ? -1 : 1)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .controlSize(.regular)
        .accessibilityLabel(L10n.text(help))
        .help(L10n.text(help))
    }
}

/// The footer of a turn that ended without a reply to hang one on: cut while
/// thinking, stopped after a tool result, an error card. Time of the last
/// thing that happened, and the two ways out — try again, or take the turn
/// away. It is what the transcript draws after its last row.
private struct TurnEndFooter: View {
    let endedAt: Date
    var onRegenerate: (() -> Void)?
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                if let onRegenerate {
                    FooterIconButton(icon: "arrow.clockwise", help: "Regenerate this reply (⌘R)",
                                     action: onRegenerate)
                }
                FooterIconButton(icon: "trash", help: "Delete this turn from the conversation",
                                 action: onDelete)
            }
            StatPill(text: endedAt.formatted(date: .omitted, time: .shortened),
                     expanded: endedAt.formatted(date: .numeric, time: .shortened))
            Spacer(minLength: 0)
        }
        .padding(.top, ChatMetrics.compactMode ? 2 : 8)
    }
}

/// Short at rest, with the full value in the system tooltip.
private struct StatPill: View {
    let text: String
    let expanded: String

    var body: some View {
        label(text)
            .help(expanded)
    }

    private func label(_ string: String) -> some View {
        // Verbatim: both callers hand in finished text — timestamps already
        // formatted by Foundation, and the tok/sec sentence localized by the
        // producer — so a catalog lookup here would re-key the result.
        Text(string)
            .font(.app(.callout).monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

// MARK: - Tool-call grouping (collapse call + result into one collapsible row)

/// A renderable transcript row: a normal message, or a tool call paired with its
/// result(s) so they show as a single collapsible row instead of two bubbles.
enum ChatRow: Identifiable, Equatable {
    case message(ChatMessage)
    /// `calls`: the structured record from the assistant message that made the
    /// call (one message before the summary); empty on older histories.
    /// `ownedHandles`: background handles this row may still speak for.
    case toolCall(call: ChatMessage, results: [ChatMessage], calls: [SerializedToolCall],
                  ownedHandles: [String])
    var id: UUID {
        switch self {
        case .message(let m): return m.id
        case .toolCall(let c, _, _, _): return c.id
        }
    }
}

/// The resolved thinking and tool state shown by the composer.
struct ChatModeToggles: Equatable {
    var thinking: Bool
    var agent: Bool
    var mcp: Bool
    /// Who decided each control, when it isn't the chat itself — the agent's
    /// name, for the lock ring and the hover card. nil = the chat's own toggle.
    var thinkingLockedBy: String? = nil
    var toolsLockedBy: String? = nil
    var mcpLockedBy: String? = nil

    var isLocked: Bool { thinkingLockedBy != nil || toolsLockedBy != nil || mcpLockedBy != nil }

    static func resolve(inAppThinking: Bool, inAppAgent: Bool, inAppMCP: Bool,
                        agentLock: AgentModeLock? = nil,
                        /// Chat is answered by Apple's on-device model.
                        apple: Bool = false) -> ChatModeToggles {
        let base = ChatModeToggles(thinking: inAppThinking, agent: inAppAgent, mcp: inAppMCP)
        guard let lock = agentLock else { return applyingApple(base, apple: apple) }
        return applyingApple(ChatModeToggles(
            // Thinking is the one an agent may leave unset, and `AgentResolution`
            // falls back to the surface's own value there — so locking it anyway
            // would take away a control nobody is deciding for you.
            thinking: lock.thinking ?? base.thinking,
            agent: lock.tools,
            mcp: lock.mcp,
            thinkingLockedBy: lock.thinking == nil ? nil : lock.name,
            toolsLockedBy: lock.name,
            mcpLockedBy: lock.name), apple: apple)
    }

    /// The on-device model has no thinking mode at all, and its 4k window has
    /// no room for MCP's tool definitions — so both read locked, with it named
    /// as the owner. The tool LOOP still switches; the tool SET is clamped in
    /// `AgentResolution`, which is where capabilities are decided.
    private static func applyingApple(_ t: ChatModeToggles, apple: Bool) -> ChatModeToggles {
        guard apple else { return t }
        var out = t
        out.thinking = false
        out.thinkingLockedBy = AppleFoundationChat.displayName
        out.mcp = false
        out.mcpLockedBy = AppleFoundationChat.displayName
        return out
    }
}

/// What the chat's agent decided about Think / Tools / MCP.
struct AgentModeLock: Equatable {
    var name: String
    /// nil = the agent left thinking unset; the chat's own toggle stands.
    var thinking: Bool?
    var tools: Bool
    var mcp: Bool
}

/// (both `isAgentSummary`) into one row: a `name(args)` header with the result(s)
/// behind an expander. Pure → unit-tested in ChatRowBuilderTests.
enum ChatRowBuilder {
    /// A tool-RESULT summary is `**name** → output`; a tool-CALL summary is
    /// `**name**(args)`. The `** → ` right after the bolded name discriminates
    /// them (and also matches the "→ denied by user" result form).
    static func isResultSummary(_ m: ChatMessage) -> Bool {
        m.isAgentSummary && m.content.contains("** → ")
    }
    static func isCallSummary(_ m: ChatMessage) -> Bool {
        m.isAgentSummary && !m.content.contains("** → ")
    }

    static func rows(from messages: [ChatMessage]) -> [ChatRow] {
        // Same visibility rule as before: the raw tool-result messages
        // (role .system carrying a toolCallId) stay hidden from the transcript.
        let visible = messages.filter { $0.toolCallId == nil }
        var rows: [ChatRow] = []
        var i = 0
        var pendingCalls: [SerializedToolCall] = []
        // Handle names are reused across launches: the last announcer owns it.
        let owned = ProcessCardControls.handleOwnership(
            visible.map { ($0.id, $0.processHandles ?? []) })
        while i < visible.count {
            let m = visible[i]
            if let calls = m.toolCalls, !calls.isEmpty { pendingCalls = calls }
            if isCallSummary(m) {
                var results: [ChatMessage] = []
                var j = i + 1
                while j < visible.count, isResultSummary(visible[j]) {
                    results.append(visible[j]); j += 1
                }
                rows.append(.toolCall(call: m, results: results, calls: pendingCalls,
                                      ownedHandles: owned[m.id] ?? []))
                pendingCalls = []
                i = j
            } else {
                rows.append(.message(m))
                i += 1
            }
        }
        return rows
    }
}

/// One collapsible tool-call row: a `name(args)` header (tap to expand) with the
/// tool result(s) revealed below. Replaces the old two-bubble call+result layout.
private struct ToolCallRow: View {
    let call: ChatMessage
    let results: [ChatMessage]
    /// See `ChatRow.toolCall`.
    var calls: [SerializedToolCall] = []
    var ownedHandles: [String] = []
    /// A handle is only an identity inside one chat
    /// (`ProcessRegistry.isAlive(handle:sessionId:)`).
    var sessionId: UUID?
    @State private var expanded = false
    @EnvironmentObject var processRegistry: ProcessRegistry

    private var isRunning: Bool { call.isStreaming }

    private var title: String {
        ToolCallDisplay.title(calls: calls, summary: call.content)
    }

    /// Flat across the round; only the header's headline (first call) reads it.
    private var argumentRows: [ToolCallDisplay.Argument] {
        calls.flatMap { ToolCallDisplay.arguments(fromJSON: $0.arguments) }
    }

    /// One call with its arguments and result. Results pair with calls by
    /// index: the engine runs them in order and result messages carry no id.
    private struct CallGroup: Identifiable {
        let id: String
        let name: String
        /// Shown as part of the name (`browse:click`).
        let variant: String?
        let arguments: [ToolCallDisplay.Argument]
        let result: String?
        /// Read out of the result text, the only place the association exists.
        let handle: String?
    }

    private var groups: [CallGroup] {
        let bodies = results.map { ToolCallDisplay.resultBody($0.content) }
        // Older history without structured calls: one group per result.
        guard !calls.isEmpty else {
            return bodies.enumerated().map { i, body in
                CallGroup(id: "legacy-\(i)", name: title, variant: nil, arguments: [], result: body,
                          handle: ToolCallDisplay.backgroundHandle(inResult: body))
            }
        }
        return calls.enumerated().map { i, call in
            let body = i < bodies.count ? bodies[i] : nil
            let args = ToolCallDisplay.arguments(fromJSON: call.arguments)
            return CallGroup(
                id: call.id.isEmpty ? "call-\(i)" : call.id,
                name: call.name,
                variant: ToolCallDisplay.variant(toolName: call.name, arguments: args),
                arguments: args,
                result: body,
                handle: body.flatMap { ToolCallDisplay.backgroundHandle(inResult: $0) })
        }
    }

    /// Handles no call claimed keep their button in the header.
    private var unclaimedHandles: [String] {
        ProcessCardControls.split(live: killableHandles,
                                  claimedBy: groups.map(\.handle)).unclaimed
    }

    /// Handles whose pill sits beside their call inside the panel.
    private var claimedHandles: [String] {
        ProcessCardControls.split(live: killableHandles,
                                  claimedBy: groups.map(\.handle)).claimed
    }

    /// Live handles this card owns. Independent of `call.isStreaming`, so the
    /// stop button outlives the tool result and vanishes when the process dies.
    private var killableHandles: [String] {
        ProcessCardControls.killable(handles: ownedHandles) {
            processRegistry.isAlive(handle: $0, sessionId: sessionId)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppLayout.compactSpacing) {
            headerRow
            if expanded {
                TranscriptDetailSurface {
                    TranscriptDetailViewport { expandedBody }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Broken out into separately type-checked pieces — a single deeply nested
    // body (expander button + per-handle kill buttons + results) pushed the
    // SwiftUI type-checker into pathological (effectively non-terminating)
    // compile times.
    @ViewBuilder private var headerRow: some View {
        HStack(spacing: AppLayout.compactSpacing) {
            TranscriptDisclosureButton(isExpanded: expanded) {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                headerLabel
            }
            ForEach(headerHandles, id: \.self) { handle in
                ProcessPill(handle: handle) { processRegistry.kill(handle: $0) }
            }
            if !expanded, groups.count > 1, !claimedHandles.isEmpty {
                RunningIndicator()
            }
            if expanded {
                TranscriptReaderButton(title: "Tool details", textToCopy: readerText) {
                    Text(verbatim: readerText)
                        .transcriptDetailText(monospaced: true)
                }
            }
        }
    }

    private var readerText: String {
        guard !calls.isEmpty else {
            return ([call.content] + results.map { ToolCallDisplay.resultBody($0.content) }).joined(separator: "\n\n")
        }
        let entries = calls.enumerated().map { index, item in
            var parts = [item.name, item.arguments]
            if index < results.count { parts.append(ToolCallDisplay.resultBody(results[index].content)) }
            return parts.joined(separator: "\n\n")
        }
        return (entries + results.dropFirst(calls.count).map { ToolCallDisplay.resultBody($0.content) })
            .joined(separator: "\n\n")
    }

    @ViewBuilder private var headerLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "wrench.and.screwdriver")
                .symbolEffect(.pulse, isActive: isRunning)
            if calls.count > 1 {
                multiToolTitle
            } else {
                singleToolTitle
            }
        }
    }

    /// One call: every live handle. Several: only the unclaimed ones; the rest
    /// sit beside their call inside the panel.
    private var headerHandles: [String] {
        groups.count > 1 ? unclaimedHandles : killableHandles
    }

    /// The one place a tool's name is drawn, so `server__tool` reads as a path
    /// everywhere. `variant` is the behaviour-choosing argument (`browse:click`).
    @ViewBuilder private func toolLabel(name: String, variant: String?) -> some View {
        Text(L10n.text(ToolCallDisplay.displayName(name)))
            .monospaced()
        if let variant {
            Text(":" + variant)
                .padding(.leading, -4)
        }
    }

    @ViewBuilder private var singleToolTitle: some View {
        toolLabel(name: title,
                  variant: calls.first.map {
                      ToolCallDisplay.variant(toolName: $0.name, arguments: argumentRows)
                  } ?? nil)
        if let headline {
            Text("· " + headline)
                .lineLimit(1)
                // Keep a path's filename.
                .truncationMode(.middle)
        }
        if let resultHeadline {
            Text("· " + resultHeadline)
                .lineLimit(1)
                .layoutPriority(1)
        }
    }

    /// Names only, no arguments (one query in the header would look like the
    /// only one); past three the tail becomes a count.
    @ViewBuilder private var multiToolTitle: some View {
        let shown = groups.count > 3 ? Array(groups.prefix(2)) : groups
        let hidden = groups.count - shown.count

        ForEach(Array(shown.enumerated()), id: \.offset) { index, group in
            if index > 0 { middot }
            toolLabel(name: group.name, variant: group.variant)
        }
        if hidden > 0 {
            middot
            Text(L10n.format(hidden == 1 ? "+%lld other tool" : "+%lld other tools", Int64(hidden)))
                .lineLimit(1)
        }
    }

    private var middot: some View {
        Text("·")
    }

    private var headline: String? {
        guard let name = calls.first?.name else { return nil }
        return ToolCallDisplay.headline(toolName: name, arguments: argumentRows)
    }

    private var resultHeadline: String? {
        guard let name = calls.first?.name, let first = results.first else { return nil }
        return ToolCallDisplay.resultHeadline(toolName: name,
                                              result: ToolCallDisplay.resultBody(first.content))
    }

    @ViewBuilder private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                if groups.count > 1 {
                    HStack(spacing: 0) {
                        toolLabel(name: group.name, variant: group.variant)
                        Spacer(minLength: 8)
                        if let handle = group.handle, killableHandles.contains(handle) {
                            ProcessPill(handle: handle) { processRegistry.kill(handle: $0) }
                        }
                    }
                    .padding(.top, index == 0 ? 0 : 4)
                }
                callGrid(group)
            }
        }
        .transcriptDetailText()
    }

    @ViewBuilder private func callGrid(_ group: CallGroup) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 6) {
            ForEach(group.arguments) { arg in
                gridRow(name: arg.name, value: arg.value)
            }

            if let result = group.result {
                if !group.arguments.isEmpty {
                    GridRow { Divider().gridCellColumns(2) }
                }
                GridRow {
                    Text("result")
                        .font(.system(size: ChatMetrics.transcriptFontSize, design: .monospaced))
                        .gridColumnAlignment(.leading)
                        .fixedSize(horizontal: true, vertical: false)
                    Text(verbatim: result)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder private func gridRow(name: String, value: String) -> some View {
        GridRow {
            Text(name)
                .font(.system(size: ChatMetrics.transcriptFontSize, design: .monospaced))
                .gridColumnAlignment(.leading)
                .fixedSize(horizontal: true, vertical: false)
            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// "running" badge without a button; the stop control is `StopProcessButton`.
private struct RunningIndicator: View {
    @Environment(\.colorScheme) private var scheme
    @State private var pulsing = false

    private var ink: Color {
        scheme == .dark ? Color(red: 0.44, green: 0.82, blue: 0.50)
                        : Color(red: 0.05, green: 0.42, blue: 0.16)
    }

    var body: some View {
        HStack(spacing: 5) {
            // By hand: `.symbolEffect(.scale)` has nothing to move on
            // `circle.fill`.
            Image(systemName: "circle.fill")
                .font(.system(size: 7))
                .foregroundStyle(ink)
                .scaleEffect(pulsing ? 0.55 : 1)
                .opacity(pulsing ? 0.45 : 1)
                .animation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true),
                           value: pulsing)
                .onAppear { pulsing = true }
                .accessibilityHidden(true)

            Text("running")
                .font(.app(.caption).weight(.bold))
                .foregroundStyle(ink)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.green.opacity(0.2), in: Capsule())
    }
}

private struct StopProcessButton: View {
    let handle: String
    let onKill: (String) -> Void

    var body: some View {
        Button { onKill(handle) } label: {
            // Sized off the pill beside it.
            Image(systemName: "xmark.circle.fill")
                .resizable()
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .red)
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.format("Stop background process %@", handle))
        .accessibilityLabel(L10n.format("Stop background process %@", handle))
    }
}

private struct ProcessPill: View {
    let handle: String
    let onKill: (String) -> Void

    var body: some View {
        HStack(spacing: 5) {
            RunningIndicator()
            StopProcessButton(handle: handle, onKill: onKill)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Markdown Rendering
//
// Rendering goes through a single NSTextView (via SelectableMarkdownNSText) so the
// user can drag-select across the *entire* assistant message — paragraphs, lists,
// code blocks, tables, the lot. Stacking individual SwiftUI Text views inside a
// VStack used to break selection at every block boundary because each Text is its
// own NSTextStorage island; a single NSTextView is the only reliable way to get
// macOS-native cross-block selection. Block parsing still happens here in Swift —
// each Block becomes a styled fragment of the assembled NSAttributedString.
struct MarkdownText: View {
    let source: String
    @Environment(\.colorScheme) private var colorScheme

    /// Tags emitted by models (thinking, planning, etc.) — rendered as XML blocks.
    /// Standard HTML tags (head, div, meta, etc.) are NOT included — they render as text.
    private static let modelTags: Set<String> = [
        "pad", "plan", "thinking", "thought", "reflection", "output",
        "step", "result", "answer", "reasoning", "tool_call", "tool_response",
    ]

    /// Tags whose content should be hidden from the chat entirely (consumed but
    /// not rendered). Real tool calls show in the dedicated tool-call UI; raw
    /// `<tool_call>` text in the assistant bubble is either a parser fallback or
    /// a malformed/truncated leak — neither is useful to display.
    private static let hiddenTags: Set<String> = [
        "tool_call", "tool_response",
    ]

    init(_ source: String) {
        self.source = source
    }

    private var latexTheme: LaTeXTheme {
        colorScheme == .dark ? .dark : .light
    }

    var body: some View {
        // Fenced code renders as its own view (colors, copy button);
        // everything between fences — including tables, rendered as an
        // `NSTextTable` inside the shared attributed string — stays in ONE
        // text view per run so drag-selection still crosses paragraphs,
        // lists, and tables. See `MarkdownSegmenter` for why the split is at
        // fences, not at blocks.
        VStack(alignment: .leading, spacing: ChatMetrics.markdownBlockSpacing) {
            ForEach(Array(MarkdownSegmenter.segments(source).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .prose(let text):
                    VStack(alignment: .leading, spacing: ChatMetrics.markdownBlockSpacing) {
                        ForEach(Array(Self.latexBlocks(in: text).enumerated()), id: \.offset) { _, block in
                            switch block {
                            case .prose(let prose):
                                SelectableMarkdownNSText(
                                    attributed: Self.attributedString(for: prose, theme: latexTheme)
                                )
                            case .display(let latex, let raw):
                                DisplayLaTeXView(latex: latex, raw: raw, theme: latexTheme)
                            }
                        }
                    }
                case .code(let language, let code):
                    CodeBlockView(language: language, code: code)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(source, forType: .string)
            } label: { Text("Copy All")
                .font(.app(.body)) }
        }
    }

    enum LaTeXBlock {
        case prose(String)
        case display(latex: String, raw: String)
    }

    /// Display formulas own a horizontally scrollable view. Text and inline
    /// formulas remain one prose run so NSTextView can preserve native
    /// selection across paragraphs, lists, and inline equations.
    static func latexBlocks(in source: String) -> [LaTeXBlock] {
        var blocks: [LaTeXBlock] = []
        var prose = ""

        func flushProse() {
            defer { prose = "" }
            guard !prose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            blocks.append(.prose(prose))
        }

        for segment in LaTeXSegmenter.segments(source) {
            switch segment {
            case .text(let text):
                prose += text
            case .inline(_, let raw):
                prose += raw
            case .display(let latex, let raw):
                flushProse()
                blocks.append(.display(latex: latex, raw: raw))
            }
        }
        flushProse()
        if blocks.isEmpty { blocks.append(.prose(source)) }
        return blocks
    }

    fileprivate enum Block {
        case paragraph(String)
        case heading(Int, String)              // level, text
        case code(String, String)              // language, content
        case listItem(String, String, Int)     // marker (`•`, `1.`, `☐`), text, depth
        case thematicBreak                     // `---` between sections
        case quote(String)                     // `>` lines, already merged
        case xmlBlock(String)                  // raw XML/tag content
        case table([String], [[String]], [TableAlignment])  // headers, rows, alignments
    }

    /// Anchored: at most nine digits (CommonMark) then `.` or `)` and a space.
    fileprivate static func listItem(in line: String) -> (marker: String, text: String, indent: Int)? {
        let indent = leadingIndent(of: line)
        let body = line.drop { $0 == " " || $0 == "\t" }
        if body.hasPrefix("- ") || body.hasPrefix("* ") {
            let text = String(body.dropFirst(2))
            if let box = taskBox(in: text) { return (box.marker, box.text, indent) }
            return ("•", text, indent)
        }
        guard let match = body.range(of: "^[0-9]{1,9}[.)] ", options: .regularExpression) else {
            return nil
        }
        return (String(body[match]).trimmingCharacters(in: .whitespaces),
                String(body[match.upperBound...]), indent)
    }

    /// Spaces before the first mark on the line; a tab counts as four.
    fileprivate static func leadingIndent(of line: String) -> Int {
        var n = 0
        for c in line {
            if c == " " { n += 1 } else if c == "\t" { n += 4 } else { break }
        }
        return n
    }

    /// A break INSIDE a paragraph. TextKit starts a new paragraph at every
    /// `\n`, and a new paragraph takes the first-line indent (the margin) and a
    /// paragraph's worth of air — so an item's own second line would leave the
    /// list it belongs to.
    fileprivate static let softBreak = "\u{2028}"

    /// A checklist's boxes, which read at the weight of the text rather than a
    /// bullet's: they are the item's state, not its punctuation.
    fileprivate static let taskBoxes: Set<String> = ["\u{25A1}", "\u{2611}"]

    /// `[ ]` or `[x]` right after the marker is a checkbox, not text.
    private static func taskBox(in text: String) -> (marker: String, text: String)? {
        guard text.count >= 4, text.hasPrefix("["), text.dropFirst(2).hasPrefix("] ") else { return nil }
        switch text[text.index(text.startIndex, offsetBy: 1)] {
        case " ": return ("\u{25A1}", String(text.dropFirst(4)))
        case "x", "X": return ("\u{2611}", String(text.dropFirst(4)))
        default: return nil
        }
    }

    /// Three or more of one mark, alone on the line.
    fileprivate static func isThematicBreak(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let mark = trimmed.first, mark == "-" || mark == "*" || mark == "_" else { return false }
        guard trimmed.allSatisfy({ $0 == mark || $0 == " " }) else { return false }
        return trimmed.filter { $0 == mark }.count >= 3
    }

    /// A list's depth comes from the STEPS it takes, not from a count of
    /// spaces: models write two or four for the same one level, and a list
    /// that starts indented is still at its own top.
    fileprivate struct ListDepth {
        /// Past this an outline is deeper than the column can show, so further
        /// levels share an indent rather than walking off the right edge. The
        /// stack still tracks the real structure, so coming back out lands
        /// where it should.
        static let maxLevel = 5

        private var stops: [Int] = []

        mutating func level(forIndent indent: Int) -> Int {
            while let last = stops.last, indent < last { stops.removeLast() }
            if let last = stops.last {
                if indent > last { stops.append(indent) }
            } else {
                stops.append(indent)
            }
            return min(stops.count - 1, Self.maxLevel)
        }

        mutating func reset() { stops.removeAll() }
    }

    /// `>` alone is a blank line inside a quote and keeps the block open.
    fileprivate static func quoteBody(in line: String) -> String? {
        if line.hasPrefix("> ") { return String(line.dropFirst(2)) }
        if line == ">" { return "" }
        return nil
    }

    fileprivate static func parseBlocks(source: String) -> [Block] {
        var blocks: [Block] = []
        let lines = source.components(separatedBy: "\n")
        var i = 0
        var depth = ListDepth()

        while i < lines.count {
            let line = lines[i]

            // XML-like tag block for model-specific tags (<plan>, <pad>, <thinking>, etc.)
            // Only match known model tags — NOT standard HTML tags like <head>, <div>, <meta>.
            if let match = line.range(of: "^<([a-zA-Z_]+)>", options: .regularExpression) {
                let tag = String(line[match]).dropFirst().dropLast() // extract tag name
                guard Self.modelTags.contains(String(tag)) else {
                    // Not a model tag — fall through to normal paragraph handling
                    i += 1
                    let text = line.trimmingCharacters(in: .whitespaces)
                    if !text.isEmpty { blocks.append(.paragraph(text)) }
                    continue
                }
                let closeTag = "</\(tag)>"
                let isHidden = Self.hiddenTags.contains(String(tag))
                if line.contains(closeTag) {
                    // Single-line tag block
                    if !isHidden { blocks.append(.xmlBlock(line)) }
                    i += 1
                    continue
                }
                // Multi-line: collect until closing tag (or EOF for unclosed)
                var xmlLines: [String] = [line]
                i += 1
                while i < lines.count {
                    xmlLines.append(lines[i])
                    if lines[i].contains(closeTag) {
                        i += 1
                        break
                    }
                    i += 1
                }
                if !isHidden {
                    blocks.append(.xmlBlock(xmlLines.joined(separator: "\n")))
                }
                continue
            }

            // Standalone model tags like <pad><pad><pad>
            if line.hasPrefix("<") && line.contains(">") && !line.hasPrefix("<http") {
                let stripped = line.trimmingCharacters(in: .whitespaces)
                if stripped.range(of: "^(<[a-zA-Z_/]+>\\s*)+$", options: .regularExpression) != nil {
                    // Only treat as XML block if ALL tags are model tags
                    let tagNames = stripped.components(separatedBy: ">")
                        .compactMap { $0.components(separatedBy: "<").last?.replacingOccurrences(of: "/", with: "") }
                        .filter { !$0.isEmpty }
                    if tagNames.allSatisfy({ Self.modelTags.contains($0) }) {
                        blocks.append(.xmlBlock(stripped))
                        i += 1
                        continue
                    }
                }
            }

            // Fenced code block
            if line.hasPrefix("```") {
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                i += 1 // skip closing ```
                blocks.append(.code(lang, code.joined(separator: "\n")))
                continue
            }

            // Heading
            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                if level <= 6 {
                    let text = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                    if !text.isEmpty {
                        blocks.append(.heading(level, text))
                        i += 1
                        continue
                    }
                }
            }

            // Table (GFM pipe table, or the whitespace-aligned pseudo-table
            // smaller models emit without GFM syntax) — checked before
            // list-item/paragraph so a `- ` inside a cell or numbered header
            // doesn't get misread as a list marker.
            if let table = MarkdownTable.parse(lines: lines, start: i) {
                blocks.append(.table(table.headers, table.rows, table.alignments))
                i = table.end
                continue
            }

            // Consecutive `>` lines are one quote (models mark every line).
            if quoteBody(in: line) != nil {
                var quoted: [String] = []
                while i < lines.count, let body = quoteBody(in: lines[i]) {
                    quoted.append(body)
                    i += 1
                }
                blocks.append(.quote(quoted.joined(separator: "\n")))
                continue
            }

            // A rule, before the list check: `- - -` is a break, not an item.
            if isThematicBreak(line) {
                blocks.append(.thematicBreak)
                i += 1
                continue
            }

            // List item, with the lines indented under it: a second line, or a
            // second paragraph, belongs to the item rather than to the margin.
            if let item = listItem(in: line) {
                // Any other block ended the list, so its depth starts again.
                if case .some(.listItem) = blocks.last {} else { depth.reset() }
                var text = item.text
                i += 1
                while i < lines.count {
                    // One blank line may sit inside an item, before its second
                    // paragraph; two end it.
                    let blank = lines[i].trimmingCharacters(in: .whitespaces).isEmpty
                    let at = blank ? i + 1 : i
                    guard at < lines.count else { break }
                    let next = lines[at]
                    let trimmed = next.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty,
                          leadingIndent(of: next) > item.indent,
                          listItem(in: next) == nil,
                          !isThematicBreak(next),
                          quoteBody(in: trimmed) == nil,
                          !trimmed.hasPrefix("```"), !trimmed.hasPrefix("#"),
                          !trimmed.hasPrefix("|"), !trimmed.hasPrefix("<")
                    else { break }
                    text += (blank ? softBreak + softBreak : softBreak) + trimmed
                    i = at + 1
                }
                blocks.append(.listItem(item.marker, text, depth.level(forIndent: item.indent)))
                continue
            }

            // Empty line — skip
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
                continue
            }

            // Paragraph — collect consecutive non-empty lines
            var para: [String] = [line]
            i += 1
            while i < lines.count {
                let next = lines[i]
                // A paragraph ends where any block begins: models skip the
                // blank line before a list.
                if next.trimmingCharacters(in: .whitespaces).isEmpty ||
                   next.hasPrefix("#") || next.hasPrefix("```") ||
                   listItem(in: next) != nil ||
                   quoteBody(in: next) != nil ||
                   next.hasPrefix("<") ||
                   next.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    break
                }
                para.append(next)
                i += 1
            }
            blocks.append(.paragraph(para.joined(separator: "\n")))
        }

        return blocks
    }

    // MARK: NSAttributedString assembly

    /// Rendered prose runs, keyed by source + appearance because inline math
    /// attachments are rasterized in the resolved label color.
    private static let renderCache: NSCache<NSString, NSAttributedString> = {
        let c = NSCache<NSString, NSAttributedString>()
        c.countLimit = 256
        return c
    }()

    /// Build the NSAttributedString fed to NSTextView. Public-static so the
    /// rendering path can be exercised by tests later if needed.
    static func attributedString(for source: String) -> NSAttributedString {
        attributedString(for: source, theme: .light)
    }

    static func attributedString(for source: String, theme: LaTeXTheme) -> NSAttributedString {
        // Everything baked into the string (fonts, leading) rides the key.
        let key = """
        \(theme.rawValue)\u{0}\(ChatMetrics.transcriptFontSize)\u{0}\
        \(ChatMetrics.compactMode)\u{0}\(source)
        """ as NSString
        if let hit = renderCache.object(forKey: key) { return hit }
        let built = buildAttributedString(for: source, theme: theme)
        renderCache.setObject(built, forKey: key)
        return built
    }

    private static func buildAttributedString(
        for source: String,
        theme: LaTeXTheme
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let blocks = parseBlocks(source: source)
        var markerWidths: [Int: CGFloat] = [:]
        let markerFont = NSFont.systemFont(ofSize: ChatMetrics.transcriptFontSize)
        var listEnd = 0

        func isItem(_ index: Int) -> Bool {
            guard index >= 0, index < blocks.count else { return false }
            if case .listItem = blocks[index] { return true }
            return false
        }

        for (idx, block) in blocks.enumerated() {
            if isItem(idx), idx >= listEnd {
                markerWidths.removeAll(keepingCapacity: true)
                listEnd = idx
                while listEnd < blocks.count {
                    guard case .listItem(let marker, _, let level) = blocks[listEnd] else { break }
                    let width = ((marker + " ") as NSString).size(withAttributes: [.font: markerFont]).width.rounded(.up)
                    markerWidths[level] = max(markerWidths[level] ?? 0, width)
                    listEnd += 1
                }
            }
            // Items are their own blocks and carry their own newline; the
            // spacer only opens and closes the list.
            if idx > 0, !(isItem(idx) && isItem(idx - 1)) { result.append(blockSpacer()) }
            switch block {
            case .paragraph(let text):
                // Leading + a real gap after each paragraph (single-newline
                // "**Label.** text" runs the models love are paragraphs too).
                let p = NSMutableParagraphStyle()
                p.lineHeightMultiple = ChatMetrics.proseLineHeightMultiple
                p.paragraphSpacing = 8
                let para = NSMutableAttributedString(attributedString: renderInline(text, theme: theme))
                para.addAttribute(.paragraphStyle, value: p,
                                  range: NSRange(location: 0, length: para.length))
                result.append(para)

            case .heading(let level, let text):
                // Scaled from the body size, so raising the reading size
                // raises the headings with it instead of flattening them.
                let base = ChatMetrics.transcriptFontSize
                let size: CGFloat = level == 1 ? base + 5 : level == 2 ? base + 3 : base + 1
                let p = NSMutableParagraphStyle()
                p.paragraphSpacingBefore = 10
                p.paragraphSpacing = 2
                p.lineHeightMultiple = ChatMetrics.proseLineHeightMultiple
                let heading = NSMutableAttributedString(
                    attributedString: renderInline(text, theme: theme, weight: .bold, fontSize: size)
                )
                let full = NSRange(location: 0, length: heading.length)
                heading.addAttribute(.paragraphStyle, value: p, range: full)
                result.append(heading)

            case .code(_, let content):
                let p = NSMutableParagraphStyle()
                p.paragraphSpacingBefore = 4
                p.paragraphSpacing = 4
                // Its own gutter, so the tinted block stands off the text.
                p.firstLineHeadIndent = 8
                p.headIndent = 8
                p.tailIndent = -8
                // Less air than prose — a listing wants rows.
                p.lineHeightMultiple = ChatMetrics.codeLineHeightMultiple
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: ChatMetrics.transcriptCodeFontSize, weight: .regular),
                    .backgroundColor: NSColor.textBackgroundColor.blended(withFraction: 0.85, of: .black) ?? NSColor.darkGray,
                    .foregroundColor: NSColor(white: 0.92, alpha: 1.0),
                    .paragraphStyle: p,
                ]
                let code = NSMutableAttributedString(string: content, attributes: attrs)
                linkifyBareUrls(code)
                result.append(code)

            case .listItem(let marker, let text, let level):
                let bullet = NSAttributedString(string: marker + " ", attributes: [
                    .font: NSFont.systemFont(ofSize: ChatMetrics.transcriptFontSize),
                    .foregroundColor: taskBoxes.contains(marker)
                        ? NSColor.labelColor : NSColor.secondaryLabelColor,
                ])
                let p = NSMutableParagraphStyle()
                // Reserve one marker column at each depth, including multi-digit numbers.
                let step = CGFloat(level) * ChatMetrics.listIndentStep
                let markerWidth = bullet.size().width.rounded(.up)
                let gutter = max(ChatMetrics.listIndentStep, markerWidths[level] ?? markerWidth)
                p.firstLineHeadIndent = step + gutter - markerWidth
                p.headIndent = step + gutter
                p.lineHeightMultiple = ChatMetrics.proseLineHeightMultiple
                // Tight between items, a paragraph's worth after the last.
                p.paragraphSpacing = isItem(idx + 1) ? 4 : 8
                let inline = renderInline(text, theme: theme)
                let combined = NSMutableAttributedString()
                combined.append(bullet)
                combined.append(inline)
                // No block spacer between items, so the item ends itself.
                if isItem(idx + 1) { combined.append(NSAttributedString(string: "\n")) }
                combined.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: combined.length))
                result.append(combined)

            case .thematicBreak:
                // A rule is a bordered block for the same reason the quote bar
                // is one: an attributed string has no "line across here".
                let table = NSTextTable()
                table.numberOfColumns = 1
                let cell = NSTextTableBlock(table: table, startingRow: 0, rowSpan: 1,
                                            startingColumn: 0, columnSpan: 1)
                cell.setContentWidth(100, type: .percentageValueType)
                cell.setWidth(1, type: .absoluteValueType, for: .border, edge: .minY)
                cell.setBorderColor(NSColor.separatorColor, for: .minY)
                cell.setWidth(8, type: .absoluteValueType, for: .margin, edge: .minY)
                cell.setWidth(8, type: .absoluteValueType, for: .margin, edge: .maxY)
                let p = NSMutableParagraphStyle()
                p.textBlocks = [cell]
                // The cell needs something to hold; at 1pt the rule is the
                // only thing with height.
                result.append(NSAttributedString(string: "\u{00A0}", attributes: [
                    .font: NSFont.systemFont(ofSize: 1),
                    .paragraphStyle: p,
                ]))

            case .table(let headers, let rows, let alignments):
                result.append(renderTable(headers: headers, rows: rows, alignments: alignments, theme: theme))

            case .quote(let text):
                // The bar is a one-cell `NSTextTable` with a leading border:
                // an attributed string has no "rule beside this paragraph".
                let table = NSTextTable()
                table.numberOfColumns = 1
                let cell = NSTextTableBlock(table: table, startingRow: 0, rowSpan: 1,
                                            startingColumn: 0, columnSpan: 1)
                cell.setContentWidth(100, type: .percentageValueType)
                cell.setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
                cell.setBorderColor(NSColor.separatorColor, for: .minX)
                // A text block ignores paragraph spacing: air is the cell's
                // margin. Vertical padding is lopsided because the extra
                // leading sits above the letters.
                cell.setWidth(10, type: .absoluteValueType, for: .padding, edge: .minX)
                cell.setWidth(0, type: .absoluteValueType, for: .padding, edge: .minY)
                cell.setWidth(8, type: .absoluteValueType, for: .padding, edge: .maxY)
                cell.setWidth(6, type: .absoluteValueType, for: .margin, edge: .minY)
                cell.setWidth(6, type: .absoluteValueType, for: .margin, edge: .maxY)

                let p = NSMutableParagraphStyle()
                p.textBlocks = [cell]
                p.lineHeightMultiple = ChatMetrics.proseLineHeightMultiple
                p.paragraphSpacing = 4
                let quoted = NSMutableAttributedString(attributedString: renderInline(text, theme: theme))
                let range = NSRange(location: 0, length: quoted.length)
                quoted.addAttribute(.paragraphStyle, value: p, range: range)
                quoted.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
                result.append(quoted)

            case .xmlBlock(let content):
                let p = NSMutableParagraphStyle()
                p.firstLineHeadIndent = 8
                p.headIndent = 8
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: AppType.monospaced(.subheadline),
                    .foregroundColor: NSColor.systemPurple,
                    .backgroundColor: NSColor.systemPurple.withAlphaComponent(0.10),
                    .paragraphStyle: p,
                ]
                result.append(NSAttributedString(string: content, attributes: attrs))

            }
        }
        return result
    }

    /// Render a table as an `NSTextTable` run appended directly into the
    /// message's continuous attributed string, so drag-selection and copy
    /// span prose and table cells together like every other block instead of
    /// stopping at the table's edge. `NSTextTable` has no "tight to content"
    /// sizing mode — every column is a percentage of the available width —
    /// so columns are weighted by content length
    /// reading column.
    ///
    /// Cell content is rendered through `renderCell`, memoized by cell text
    /// - a table's earlier rows/cells don't change once streamed, only the
    /// actively-growing last cell does, so this amortizes the per-cell
    /// markdown/LaTeX-segmentation cost to near zero after the first full
    /// render instead of repeating it for every unchanged cell on every
    /// token.
    private static let cellRenderCache: NSCache<NSString, NSAttributedString> = {
        let c = NSCache<NSString, NSAttributedString>()
        c.countLimit = 2048
        return c
    }()

    private static func renderCell(_ text: String, theme: LaTeXTheme, bold: Bool) -> NSAttributedString {
        let key = "\(theme.rawValue)\u{0}\(ChatMetrics.transcriptFontSize)\u{0}\(ChatMetrics.transcriptCodeFontSize)\u{0}\(bold)\u{0}\(text)" as NSString
        if let hit = cellRenderCache.object(forKey: key) { return hit }
        let rendered = renderInline(text, theme: theme, weight: bold ? .semibold : .regular)
        cellRenderCache.setObject(rendered, forKey: key)
        return rendered
    }

    private static func renderTable(
        headers: [String],
        rows: [[String]],
        alignments: [TableAlignment],
        theme: LaTeXTheme
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let cols = headers.count
        guard cols > 0 else { return result }

        let table = NSTextTable()
        table.numberOfColumns = cols
        let fractions = MarkdownTable.columnFractions(headers: headers, rows: rows)
        let dividerColor = NSColor.separatorColor

        func textAlignment(_ column: Int) -> NSTextAlignment {
            guard column < alignments.count else { return .left }
            switch alignments[column] {
            case .left: return .left
            case .right: return .right
            case .center: return .center
            }
        }

        // Draw each horizontal divider once; content remains on the page surface.
        let headerRuleWeight: CGFloat = 1
        let rowRuleWeight: CGFloat = 0.5
        let lastRow = rows.count   // header is row 0

        func appendRow(_ cells: [String], rowIndex: Int, bold: Bool) {
            for column in 0..<cols {
                let text = column < cells.count ? cells[column] : ""
                let block = NSTextTableBlock(
                    table: table, startingRow: rowIndex, rowSpan: 1,
                    startingColumn: column, columnSpan: 1
                )
                block.setContentWidth(Double(fractions[column]) * 100, type: .percentageValueType)
                block.setWidth(AppLayout.compactSpacing, type: .absoluteValueType, for: .padding)
                block.setWidth(AppLayout.rowSpacing, type: .absoluteValueType, for: .padding, edge: .minX)
                block.setWidth(AppLayout.rowSpacing, type: .absoluteValueType, for: .padding, edge: .maxX)

                if rowIndex == 0 {
                    // A text table ignores the previous paragraph's spacing:
                    // air above is a margin on the first row.
                    block.setWidth(10, type: .absoluteValueType, for: .margin, edge: .minY)
                }
                if rowIndex == lastRow {
                    block.setWidth(10, type: .absoluteValueType, for: .margin, edge: .maxY)
                }
                block.setBorderColor(dividerColor, for: .maxY)
                block.setWidth(rowIndex == 0 ? headerRuleWeight : rowRuleWeight,
                               type: .absoluteValueType, for: .border, edge: .maxY)
                let pStyle = NSMutableParagraphStyle()
                pStyle.textBlocks = [block]
                pStyle.alignment = textAlignment(column)
                pStyle.lineHeightMultiple = ChatMetrics.compactMode ? 1.1 : 1.2
                let cell = NSMutableAttributedString(attributedString: renderCell(text, theme: theme, bold: bold))
                cell.append(NSAttributedString(string: "\n"))
                cell.addAttribute(.paragraphStyle, value: pStyle, range: NSRange(location: 0, length: cell.length))
                result.append(cell)
            }
        }

        appendRow(headers, rowIndex: 0, bold: true)
        for (index, row) in rows.enumerated() {
            appendRow(row, rowIndex: index + 1, bold: false)
        }
        return result
    }

    /// One-and-a-half blank lines between blocks. Encoded as a `\n` with extra
    /// paragraph spacing so tall blocks don't collapse.
    private static func blockSpacer() -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.paragraphSpacing = 8
        return NSAttributedString(string: "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 6),
            .paragraphStyle: p,
        ])
    }

    /// Render an inline span by delegating to AttributedString's markdown parser
    /// (handles `**bold**`, `_italic_`, `` `code` ``, `[link](url)`). Falls back
    /// to a plain-text NSAttributedString if the parse fails. Returned string
    /// carries the body font and a dynamic foreground color so the rendering
    /// flips correctly between light and dark modes — Foundation's converter
    /// can leave `**bold**` and link spans with a baked-in `NSColor` that
    /// doesn't adapt, so we overwrite missing-or-static colors with
    /// `.labelColor` (links keep their dynamic `linkColor`).
    private struct InlineMathReplacement {
        let marker: String
        let latex: String
        let raw: String
    }
    /// A streaming reply rebuilds its whole string per flush while only its
    /// last block changed; every earlier block's inline render is a hit here.
    private static let inlineRenderCache: NSCache<NSString, NSAttributedString> = {
        let c = NSCache<NSString, NSAttributedString>()
        c.countLimit = 4096
        return c
    }()

    static func renderInline(
        _ text: String,
        theme: LaTeXTheme,
        weight: NSFont.Weight = .regular,
        fontSize: CGFloat = ChatMetrics.transcriptFontSize
    ) -> NSAttributedString {
        let key = "\(theme.rawValue)\u{0}\(weight.rawValue)\u{0}\(fontSize)\u{0}\(text)" as NSString
        if let hit = inlineRenderCache.object(forKey: key) { return hit }
        let built = NSAttributedString(attributedString:
            buildInline(text, theme: theme, weight: weight, fontSize: fontSize))
        inlineRenderCache.setObject(built, forKey: key)
        return built
    }

    private static func buildInline(
        _ text: String,
        theme: LaTeXTheme,
        weight: NSFont.Weight,
        fontSize: CGFloat
    ) -> NSAttributedString {
        let bodyFont = NSFont.systemFont(ofSize: fontSize, weight: weight)
        let prepared = inlineMathPlaceholders(in: text)
        var result = markdownAttributedString(prepared.source)

        let located = prepared.replacements.compactMap { replacement -> (InlineMathReplacement, NSRange)? in
            let range = (result.string as NSString).range(of: replacement.marker)
            return range.location == NSNotFound ? nil : (replacement, range)
        }
        // Foundation should preserve private-use marker scalars. If a future
        // parser version does not, keep every source byte visible instead of
        // silently dropping an equation.
        if located.count != prepared.replacements.count {
            result = markdownAttributedString(text)
            applyInlineTypography(to: result, bodyFont: bodyFont)
            linkifyBareUrls(result)
            return result
        }

        applyInlineTypography(to: result, bodyFont: bodyFont)
        for (replacement, range) in located.reversed() {
            let inherited = result.attributes(at: range.location, effectiveRange: nil)
            let rendered = InlineLaTeXRenderer.attributedAttachment(
                latex: replacement.latex,
                raw: replacement.raw,
                theme: theme,
                fontSize: fontSize
            )
            let inserted: NSMutableAttributedString
            if let rendered {
                inserted = NSMutableAttributedString(attributedString: rendered)
            } else {
                inserted = NSMutableAttributedString(string: replacement.raw)
            }
            inserted.addAttributes(
                inherited,
                range: NSRange(location: 0, length: inserted.length)
            )
            result.replaceCharacters(in: range, with: inserted)
        }
        linkifyBareUrls(result)
        return result
    }

    private static func inlineMathPlaceholders(
        in text: String
    ) -> (source: String, replacements: [InlineMathReplacement]) {
        var source = ""
        var replacements: [InlineMathReplacement] = []

        for segment in LaTeXSegmenter.segments(text) {
            switch segment {
            case .text(let value):
                source += value
            case .display(_, let raw):
                // Display equations are split into their own SwiftUI view by
                // latexBlocks(in:). Direct renderer callers keep them literal.
                source += raw
            case .inline(let latex, let raw):
                var marker = "\u{E000}mlxlatex\(replacements.count)\u{E001}"
                while text.contains(marker) || source.contains(marker) {
                    marker += "x"
                }
                source += marker
                replacements.append(InlineMathReplacement(marker: marker, latex: latex, raw: raw))
            }
        }
        return (source, replacements)
    }

    private static func markdownAttributedString(_ text: String) -> NSMutableAttributedString {
        if let attr = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return NSMutableAttributedString(attr)
        }
        return NSMutableAttributedString(string: text)
    }

    private static func applyInlineTypography(
        to result: NSMutableAttributedString,
        bodyFont: NSFont
    ) {
        let full = NSRange(location: 0, length: result.length)
        // Default font for any character that didn't pick up an explicit font
        // from the markdown parser.
        result.enumerateAttribute(.font, in: full, options: []) { value, range, _ in
            if value == nil {
                result.addAttribute(.font, value: bodyFont, range: range)
            }
        }
        // Force a dynamic foreground for every non-link span. AttributedString's
        // markdown→NSAttributedString bridge sometimes inserts `NSColor.black`
        // for bold/italic — that reads fine in light mode but is invisible on
        // a dark bubble background. Walk the whole string and replace any
        // foreground that's NOT explicitly the dynamic linkColor with
        // labelColor (which adapts).
        result.enumerateAttribute(.foregroundColor, in: full, options: []) { value, range, _ in
            // Spans inside a link keep linkColor; everything else gets labelColor.
            let isLink = result.attribute(.link, at: range.location, effectiveRange: nil) != nil
            if isLink {
                result.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
                return
            }
            // If the existing color is already dynamic-equal-to-labelColor we
            // can leave it; checking via `==` handles both the missing case
            // (value nil) and the static-black case Foundation often picks.
            if let existing = value as? NSColor,
               existing.isEqual(NSColor.labelColor) {
                return
            }
            result.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
        }
        // Foundation bridges Markdown styles as intents, without AppKit fonts.
        result.enumerateAttribute(.inlinePresentationIntent, in: full, options: []) { value, range, _ in
            let intent: InlinePresentationIntent
            if let typed = value as? InlinePresentationIntent {
                intent = typed
            } else if let number = value as? NSNumber {
                intent = InlinePresentationIntent(rawValue: number.uintValue)
            } else {
                return
            }
            if intent.contains(.strikethrough) {
                result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
            guard intent.contains(.stronglyEmphasized) || intent.contains(.emphasized) else { return }
            let font = result.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? bodyFont
            var traits = font.fontDescriptor.symbolicTraits
            if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
            if intent.contains(.emphasized) { traits.insert(.italic) }
            if let styled = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) {
                result.addAttribute(.font, value: styled, range: range)
            }
        }
        tintInlineCode(result, bodyFont: bodyFont)
    }

    /// Inline code is found by `inlinePresentationIntent`, never by the font:
    /// `NSFont.monospacedSystemFont` does not advertise the `.monoSpace` trait.
    private static func tintInlineCode(_ result: NSMutableAttributedString, bodyFont: NSFont) {
        let full = NSRange(location: 0, length: result.length)
        let mono = NSFont.monospacedSystemFont(ofSize: ChatMetrics.transcriptCodeFontSize,
                                               weight: .regular)
        result.enumerateAttributes(in: full, options: []) { attrs, range, _ in
            guard isInlineCode(attrs[.inlinePresentationIntent]),
                  // A fenced block sets its own ground and its own colours.
                  attrs[.backgroundColor] == nil
            else { return }
            // A marker, not `.backgroundColor` (that paints the whole line
            // fragment): `IntrinsicTextView` draws the ground itself.
            result.addAttributes([.font: mono, .inlineCodeGround: true], range: range)
        }
    }

    /// The intent crosses the `AttributedString` bridge as an `NSNumber` of the
    /// option set's raw value, not as the Swift type.
    private static func isInlineCode(_ value: Any?) -> Bool {
        if let intent = value as? InlinePresentationIntent { return intent.contains(.code) }
        if let number = value as? NSNumber {
            return InlinePresentationIntent(rawValue: number.uintValue).contains(.code)
        }
        return false
    }

    /// Shared detector — creating an NSDataDetector is not free and renderInline
    /// runs many times per second while streaming.
    private static let urlDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    /// Add `.link` attributes for http(s) URLs the markdown parser left
    /// unlinked. CommonMark autolinks a bare `http://…` but NOT one inside a
    /// code span — and models love `` `http://localhost:3000` `` — so a URL
    /// would flicker clickable mid-stream (before the closing backtick
    /// arrives) then go dead once the span completes. NSDataDetector handles
    /// boundaries and trailing punctuation; only http/https matches are
    /// linkified (no bare-domain or mailto surprises), and spans that already
    /// carry a link (e.g. from `[text](url)`) are left untouched. Display
    /// styling comes from the text view's `linkTextAttributes`.
    private static func linkifyBareUrls(_ result: NSMutableAttributedString) {
        guard let detector = urlDetector else { return }
        let full = NSRange(location: 0, length: result.length)
        for match in detector.matches(in: result.string, range: full) {
            guard let url = match.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else { continue }
            var alreadyLinked = false
            result.enumerateAttribute(.link, in: match.range, options: []) { value, _, stop in
                if value != nil {
                    alreadyLinked = true
                    stop.pointee = true
                }
            }
            if !alreadyLinked {
                result.addAttribute(.link, value: url, range: match.range)
            }
        }
    }

}

/// A complete display equation is its own horizontally scrollable surface.
/// SwaTex's MathView performs all parsing/layout/drawing; malformed model
/// output falls back to the exact delimiters and TeX the model streamed.
fileprivate struct DisplayLaTeXView: View {
    let latex: String
    let raw: String
    let theme: LaTeXTheme

    private var fontSize: CGFloat { ChatMetrics.transcriptFontSize + 4 }

    var body: some View {
        if DisplayLaTeXRenderer.canRender(latex, theme: theme, fontSize: fontSize) {
            ScrollView(.horizontal) {
                MathView(latex)
                    .font(size: fontSize)
                    .mathColor(SwiftUI.Color.primary)
                    .padding(.vertical, AppLayout.compactSpacing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contextMenu {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(raw, forType: .string)
                } label: { Text("Copy Equation")
                    .font(.app(.body)) }
            }
        } else {
            SelectableMarkdownNSText(attributed: NSAttributedString(
                string: raw,
                attributes: [
                    .font: NSFont.systemFont(ofSize: ChatMetrics.transcriptFontSize),
                    .foregroundColor: NSColor.labelColor,
                ]
            ))
        }
    }
}

extension NSAttributedString.Key {
    /// Marks an inline code span; `IntrinsicTextView` draws the ground.
    static let inlineCodeGround = NSAttributedString.Key("MLXInlineCodeGround")
}

// MARK: - SelectableMarkdownNSText (NSTextView wrapper)

/// NSViewRepresentable around an NSTextView. NSTextView is the only AppKit text
/// surface that natively supports drag-selection across an arbitrarily styled
/// attributed string, which is what we need so users can highlight an entire
/// assistant message — paragraphs, list items, code blocks, tables — in one
/// motion and copy the lot. The view reports its intrinsic content size to
/// SwiftUI so layout in a VStack works without forcing a fixed height.
fileprivate struct SelectableMarkdownNSText: NSViewRepresentable {
    let attributed: NSAttributedString

    func makeNSView(context: Context) -> IntrinsicTextView {
        let tv = IntrinsicTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        // Match the surrounding bubble's text color when no explicit foreground
        // is set on a span (e.g. plain paragraphs).
        tv.textColor = .labelColor
        tv.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
        tv.textStorage?.setAttributedString(attributed)
        return tv
    }

    func updateNSView(_ nsView: IntrinsicTextView, context: Context) {
        // Only mutate the storage if the assistant's content actually changed.
        // Streaming chunks call updateNSView many times per second; an unconditional
        // replace would interrupt an active selection on every frame.
        if nsView.textStorage?.isEqual(to: attributed) == false {
            nsView.textStorage?.setAttributedString(attributed)
            nsView.invalidateIntrinsicContentSize()
        }
    }
}

/// Where an inline-code span's ground is drawn: one rect per line the span
/// occupies, each ending at that line's last visible glyph.
///
/// Not `enumerateEnclosingRects`, which is SELECTION geometry: a span that
/// continues on the next line takes its first fragment all the way to the
/// container's trailing edge, and the tint ran to the right margin.
enum InlineCodeGround {
    static func rects(forGlyphRange glyphs: NSRange,
                      layoutManager: NSLayoutManager,
                      in container: NSTextContainer) -> [NSRect] {
        guard glyphs.length > 0, let text = layoutManager.textStorage?.string as NSString? else { return [] }
        var rects: [NSRect] = []
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, lineGlyphs, _ in
            let onThisLine = NSIntersectionRange(lineGlyphs, glyphs)
            guard onThisLine.length > 0 else { return }
            // The space a line breaks at belongs to the line, and tinting
            // it is what reaches the margin.
            var chars = layoutManager.characterRange(forGlyphRange: onThisLine, actualGlyphRange: nil)
            while chars.length > 0,
                  let last = text.substring(with: NSRange(location: chars.upperBound - 1, length: 1)).unicodeScalars.first,
                  CharacterSet.whitespacesAndNewlines.contains(last) {
                chars.length -= 1
            }
            guard chars.length > 0 else { return }
            let visible = layoutManager.glyphRange(forCharacterRange: chars, actualCharacterRange: nil)
            guard visible.length > 0 else { return }
            rects.append(layoutManager.boundingRect(forGlyphRange: visible, in: container))
        }
        return rects
    }
}

/// NSTextView that reports its laid-out height as its intrinsic content size,
/// so embedding it in SwiftUI's layout system "just works" — no manual height
/// binding required.
fileprivate final class IntrinsicTextView: NSTextView {
    /// Answering costs a full `ensureLayout` of the run, and auto-layout asks
    /// several times per pass — so the answer is cached until something that can
    /// actually change it happens.
    private var cachedHeight: CGFloat?

    override var intrinsicContentSize: NSSize {
        if let cachedHeight { return NSSize(width: NSView.noIntrinsicMetric, height: cachedHeight) }
        guard let lm = layoutManager, let tc = textContainer else {
            return super.intrinsicContentSize
        }
        lm.ensureLayout(for: tc)
        let height = ceil(lm.usedRect(for: tc).height)
        cachedHeight = height
        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }

    override func invalidateIntrinsicContentSize() {
        cachedHeight = nil
        super.invalidateIntrinsicContentSize()
    }

    /// Inline-code grounds go under the glyphs, at the font's own band rather
    /// than the line fragment a `.backgroundColor` attribute would fill.
    override func draw(_ dirtyRect: NSRect) {
        drawInlineCodeGrounds()
        super.draw(dirtyRect)
    }

    private func drawInlineCodeGrounds() {
        guard let layoutManager, let textContainer, let textStorage else { return }
        let origin = textContainerOrigin
        // Same tint as a table header.
        let fill = NSColor.textBackgroundColor
            .blended(withFraction: 0.05, of: .labelColor) ?? .quaternaryLabelColor
        fill.setFill()

        textStorage.enumerateAttribute(.inlineCodeGround,
                                       in: NSRange(location: 0, length: textStorage.length),
                                       options: []) { value, range, _ in
            guard value != nil else { return }
            let font = textStorage.attribute(.font, at: range.location,
                                             effectiveRange: nil) as? NSFont
            let band = ((font?.ascender ?? 10) - (font?.descender ?? -3)) + 2
            let glyphs = layoutManager.glyphRange(forCharacterRange: range,
                                                  actualCharacterRange: nil)
            for rect in InlineCodeGround.rects(forGlyphRange: glyphs,
                                               layoutManager: layoutManager,
                                               in: textContainer) {
                var box = rect.offsetBy(dx: origin.x, dy: origin.y)
                if box.height > band {
                    box = box.insetBy(dx: 0, dy: (box.height - band) / 2)
                }
                // Flipped view: extra height grows downward.
                box = box.insetBy(dx: -4, dy: 0)
                box.size.height += 4
                NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3).fill()
            }
        }
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

    override func copy(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0, let textStorage else {
            super.copy(sender)
            return
        }

        var containsLaTeX = false
        textStorage.enumerateAttribute(.mlxLaTeXSource, in: range) { value, _, stop in
            if value != nil {
                containsLaTeX = true
                stop.pointee = true
            }
        }
        guard containsLaTeX else {
            super.copy(sender)
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            LaTeXCopyText.string(from: textStorage, range: range),
            forType: .string
        )
    }

    override func setFrameSize(_ newSize: NSSize) {
        // This view WRAPS, so only a width change can alter its height.
        // Invalidating on any frame change fed the height we ourselves just
        // reported straight back in as a fresh invalidation — layout, invalidate,
        // layout again, several times per frame.
        let widthChanged = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged { invalidateIntrinsicContentSize() }
    }
}

// MARK: - GrowingTextEditor (editable, auto-growing, scrollable composer)

/// Pure layout math for the auto-growing composer. Factored out of the
/// NSViewRepresentable so it is unit-testable (the view itself is not).
enum ComposerLayout {
    /// Clamp the editor height between `minLines` and `maxLines` worth of text.
    /// Returns the height SwiftUI frames the editor at, plus whether the content
    /// overflows the cap (so the inner scroll view scrolls — the behavior the
    /// old `TextField(axis: .vertical)` never had).
    static func resolve(contentHeight: CGFloat,
                        lineHeight: CGFloat,
                        minLines: Int,
                        maxLines: Int,
                        verticalInset: CGFloat) -> (height: CGFloat, scrolls: Bool) {
        let lo = max(1, minLines)
        let hi = max(lo, maxLines)
        let minH = lineHeight * CGFloat(lo) + verticalInset
        let maxH = lineHeight * CGFloat(hi) + verticalInset
        let natural = contentHeight + verticalInset
        let clamped = Swift.max(minH, Swift.min(natural, maxH))
        return (clamped, natural > maxH + 0.5)
    }
}

/// What a Return keypress does in the composer. Mirrors the prior `.onKeyPress`
/// contract: Shift+Return is always a newline; a bare Return sends only when
/// idle, and is otherwise swallowed (never a stray newline mid-generation).
/// `.steer`: the chat is generating, so the text becomes a note for the
/// agent's next step rather than a second send.
enum ComposerReturnAction: Equatable { case send, steer, newline, ignore }

/// What an Escape keypress does in the composer. `.pass` hands the key back to
/// AppKit rather than swallowing it — with no turn to stop, Escape still has
/// its platform meaning here.
enum ComposerEscapeAction: Equatable { case stop, pass }

/// A key the composer offers to the "/" menu before handling it itself.
enum ComposerKeyCommand { case up, down, accept, cancel }

enum ComposerKey {
    /// `canSteer`: a busy chat takes the text as a steering note (the main
    /// composer); the edit bubble leaves it false, so a blank draft's Return
    /// is still swallowed.
    static func onReturn(shift: Bool, isIdle: Bool, canSteer: Bool = false) -> ComposerReturnAction {
        if shift { return .newline }
        if isIdle { return .send }
        return canSteer ? .steer : .ignore
    }

    /// Escape stops the reply being written, and does nothing otherwise.
    ///
    /// This runs from `cancelOperation(_:)` — the RESPONDER CHAIN — not from a
    /// `.keyboardShortcut(.cancelAction)`. Key equivalents are offered the
    /// keystroke first, so the edit bubble's Cancel and the tool-approval
    /// sheet's Deny keep Escape whenever they are on screen, and the composer
    /// only sees it when neither is. That ordering is the whole reason this
    /// is not a hidden button like ⌘R regenerate.
    static func onEscape(isGenerating: Bool) -> ComposerEscapeAction {
        isGenerating ? .stop : .pass
    }

    /// Whether an in-place message edit is submittable — the ONE gate the Save
    /// button and the Return key both read. A resubmit drops the old reply and
    /// everything after it, so a blanked draft must not be able to spend that:
    /// the edit field feeds this to `onReturn`'s `isIdle`, which turns a bare
    /// Return on nothing into `.ignore` rather than a send.
    static func editCanSubmit(_ draft: String) -> Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
