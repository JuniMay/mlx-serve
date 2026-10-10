import SwiftUI

/// Create-a-task sheet. Plain-language first: type a goal, type when it should run
/// ("every weekday at 8am") or tap a preset, and the parsed schedule is echoed back
/// live. Pick an autonomy level, then Save. (Run a saved task on demand with the
/// Run-now button in the Tasks window.)
struct NewTaskSheet: View {
    /// The task being edited, or nil to create a new one.
    var existing: ScheduledTask?
    let onSubmit: (ScheduledTask) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var goal: String
    @State private var scheduleText: String
    @State private var autonomy: TaskAutonomy
    @State private var modelPath: String?   // nil = use the currently-selected model
    @State private var useMCP: Bool
    @State private var agentId: UUID?
    @State private var showOptions: Bool

    init(existing: ScheduledTask? = nil, onSubmit: @escaping (ScheduledTask) -> Void) {
        self.existing = existing
        self.onSubmit = onSubmit
        _goal = State(initialValue: existing?.goal ?? "")
        _scheduleText = State(initialValue: existing?.scheduleText
            ?? existing.map { ScheduleParser.describe($0.trigger) }
            ?? "every day at 9am")
        _autonomy = State(initialValue: existing?.autonomy ?? .workspace)
        _modelPath = State(initialValue: existing?.modelPath)
        _useMCP = State(initialValue: existing?.useMCP ?? false)
        _agentId = State(initialValue: existing?.agentId)
        // Open on a task that already HAS options set: editing is when you came
        // to change one, and a collapsed row would hide the very field you came
        // for behind a summary of it. A new task starts closed, because there is
        // nothing in there yet to look at.
        _showOptions = State(initialValue: existing.map {
            $0.agentId != nil || $0.modelPath != nil || $0.useMCP
        } ?? false)
    }

    private var baseModels: [LocalModel] {
        appState.localModels.filter { $0.isChatPickable }
    }

    private var isEditing: Bool { existing != nil }

    private var parsedTrigger: TaskTrigger? { ScheduleParser.parse(scheduleText) }
    private var canSave: Bool {
        !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && parsedTrigger != nil
    }

    private let presets: [(String, String)] = [
        ("Hourly", "every hour"),
        ("Daily", "every day at 9am"),
        ("Weekdays", "every weekday at 8am"),
        ("Weekly", "every monday at 9am"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: AppLayout.sectionSpacing) {
                    // A task is TWO answers — what, and when. Everything else is
                    // a default worth leaving alone, so it sits behind one
                    // disclosure rather than competing for the same attention:
                    // six sections at equal weight read as a form to fill in.
                    goalField
                    scheduleField
                    autonomyField

                    Divider().padding(.top, 2)

                    optionsSection
                }
                .padding(.horizontal, AppLayout.pageInset)
                .padding(.vertical, AppLayout.pageInset)
            }
            // Content-sized, capped — with Options collapsed there is far less
            // to show, and a fixed 640 left a third of the sheet empty.
            .frame(maxHeight: 520)
            Divider()
            footer
        }
        .frame(width: 540)
    }

    /// Title plus one line saying what the thing being made actually is. A bare
    /// "New Task" assumes the reader already knows.
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.text(isEditing ? "Edit Task" : "New Task"))
                .font(.app(.title3).weight(.semibold))
            Text("A goal the agent runs on its own, on a schedule.")
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppLayout.pageInset)
        .padding(.vertical, AppLayout.contentInset)
    }

    // MARK: - The two questions

    private var goalField: some View {
        field("Goal") {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $goal)
                    .font(.app(.body))
                    .scrollContentBackground(.hidden)
                    .padding(AppLayout.compactSpacing)
                    .frame(minHeight: 88)
                    .accessibilityLabel(Text("Goal"))
                // A placeholder rather than a hint UNDER the box: the example
                // belongs where the typing happens, and it costs no height once
                // there is something to read instead.
                if goal.isEmpty {
                    Text("Check Hacker News and write me the top AI stories")
                        .font(.app(.body))
                        .foregroundStyle(.tertiary)
                        // The editor's own 8pt padding, plus the 5pt
                        // line-fragment padding NSTextView puts inside its text
                        // container — that inset is horizontal only, so a
                        // matching 5 on the vertical (or the 16 this had) drops
                        // the placeholder a line below the cursor it is
                        // standing in for.
                        .padding(.horizontal, AppLayout.compactSpacing + 5)
                        .padding(.vertical, AppLayout.compactSpacing)
                        .allowsHitTesting(false)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: AppLayout.textEditorRadius, style: .continuous)
                    .fill(Color(.textBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: AppLayout.textEditorRadius, style: .continuous)
                    .strokeBorder(Color(.separatorColor), lineWidth: 0.5))
        }
    }

    private var scheduleField: some View {
        field("Schedule") {
            VStack(alignment: .leading, spacing: AppLayout.compactSpacing) {
                HStack(spacing: AppLayout.labelSpacing) {
                    ForEach(presets, id: \.0) { preset in
                        presetChip(preset.0, value: preset.1)
                    }
                }
                TextField("every weekday at 8am · or a cron expression",
                          text: $scheduleText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(Text("Schedule"))
                // The echo is the whole point of typing a schedule in English:
                // it is the only confirmation that what you meant is what will
                // run. Reserved height, so the layout does not jump on every
                // keystroke that breaks and re-forms a valid schedule.
                Group {
                    if let trigger = parsedTrigger {
                        Label(ScheduleParser.describe(trigger),
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("I couldn't read that — try “every day at 8am”.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.app(.caption))
                .frame(minHeight: 15, alignment: .leading)
            }
        }
    }

    /// A preset is a CHOICE, so it shows whether it is the current one — four
    /// identical buttons that leave no trace read as if they had not worked.
    private func presetChip(_ title: String, value: String) -> some View {
        let selected = scheduleText.trimmingCharacters(in: .whitespaces)
            .caseInsensitiveCompare(value) == .orderedSame
        return Button { scheduleText = value } label: {
            HStack(spacing: 4) {
                Text(L10n.text(title))
                Image(systemName: "checkmark")
                    .font(.app(.caption2))
                    .opacity(selected ? 1 : 0)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(selected ? Color.accentColor : .secondary)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(value)
    }

    private var autonomyField: some View {
        field("Autonomy") {
            VStack(alignment: .leading, spacing: AppLayout.compactSpacing) {
                Picker("Autonomy", selection: $autonomy) {
                    ForEach(TaskAutonomy.allCases, id: \.self) { level in
                        Text(L10n.text(level.shortLabel)).tag(level)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Label(L10n.text(autonomy.blurb),
                      systemImage: autonomy == .yolo ? "exclamationmark.octagon.fill" : "info.circle")
                    .font(.app(.caption))
                    .foregroundStyle(autonomy == .yolo ? Color.red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Options (collapsed by default)

    /// Agent, model and MCP are real but rarely touched. Collapsing them costs
    /// nothing as long as the row SAYS what is set — see `TaskOptionsSummary`.
    private var optionsSection: some View {
        DisclosureGroup(isExpanded: $showOptions) {
            VStack(alignment: .leading, spacing: AppLayout.sectionSpacing) {
                field("Run as", hint: "An agent brings its own prompt, tools, model and workspace.") {
                    Picker("Run as", selection: $agentId) {
                        Text("None (app defaults)").font(.app(.body)).tag(UUID?.none)
                        ForEach(appState.agents.allAgents) { agent in
                            Text(agent.name).font(.app(.body)).tag(UUID?.some(agent.id))
                        }
                    }
                    .labelsHidden()
                }

                if !baseModels.isEmpty {
                    field("Model") {
                        Picker("Model", selection: $modelPath) {
                            Text("Use current model").font(.app(.body)).tag(String?.none)
                            ForEach(baseModels) { model in
                                Text(model.name).font(.app(.body)).tag(String?.some(model.path))
                            }
                        }
                        .labelsHidden()
                    }
                }

                field("MCP tools",
                      hint: "Your enabled MCP servers (configure them in Settings ▸ Tools & MCP). Outside Read-only/Workspace, MCP calls pause for approval.") {
                    Toggle(isOn: $useMCP) {
                        Text("Available to this task").font(.app(.subheadline))
                    }
                    .toggleStyle(.switch)
                }
            }
            .padding(.top, AppLayout.rowSpacing)
        } label: {
            HStack(spacing: AppLayout.compactSpacing) {
                Text("Options").font(.app(.headline))
                if !showOptions, let summary = optionsSummary {
                    Text(L10n.text(summary))
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { showOptions.toggle() }
        }
    }

    /// What the collapsed row reports. Built from the SELECTED values, so a
    /// pinned model that no longer exists simply stops being claimed.
    private var optionsSummary: String? {
        TaskOptionsSummary.text(
            agentName: agentId.flatMap { appState.agents.agent(id: $0) }?.name,
            modelName: modelPath.flatMap { path in baseModels.first { $0.path == path } }?.name,
            useMCP: useMCP)
    }

    /// Bottom-trailing default button, as every macOS sheet places it.
    private var footer: some View {
        HStack {
            Spacer()
            Button { dismiss() } label: { Text("Cancel")
                .font(.app(.body)) }
                .keyboardShortcut(.cancelAction)
            Button { submit() } label: { Text(L10n.text(isEditing ? "Save" : "Create Task"))
                .font(.app(.body)) }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, AppLayout.pageInset)
        .padding(.vertical, AppLayout.contentInset)
    }

    /// One labelled field: title, control, optional explainer UNDER it. The old
    /// sheet mixed all three orders — some hints above the control, some below,
    /// some inside a Label — which is most of why it read as cluttered.
    @ViewBuilder
    private func field<Content: View>(_ title: String, hint: String? = nil,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppLayout.labelSpacing) {
            Text(L10n.text(title)).font(.app(.subheadline).weight(.semibold))
            content()
            if let hint {
                Text(L10n.text(hint))
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func submit() {
        guard let trigger = parsedTrigger else { return }
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let task: ScheduledTask
        if let existing {
            // Preserve identity, history and run state; update editable fields.
            task = ScheduledTask(
                id: existing.id,
                title: TaskScheduler.deriveTitle(from: trimmedGoal),
                goal: trimmedGoal,
                trigger: trigger,
                scheduleText: scheduleText,
                autonomy: autonomy,
                modelPath: modelPath,
                agentId: agentId,
                useMCP: useMCP,
                enabled: existing.enabled,
                catchUpMissed: existing.catchUpMissed,
                createdAt: existing.createdAt,
                lastRunAt: existing.lastRunAt,
                nextFireAt: nil,           // recomputed by the scheduler on update
                workingDirectory: existing.workingDirectory
            )
        } else {
            task = ScheduledTask(
                title: TaskScheduler.deriveTitle(from: trimmedGoal),
                goal: trimmedGoal,
                trigger: trigger,
                scheduleText: scheduleText,
                autonomy: autonomy,
                modelPath: modelPath,
                agentId: agentId,
                useMCP: useMCP
            )
        }
        onSubmit(task)
        dismiss()
    }
}
