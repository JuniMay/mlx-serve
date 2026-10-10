import SwiftUI

// MARK: - Plan Card

struct PlanCardView: View {
    let plan: AgentPlan
    let results: [StepResult]
    let currentStepIndex: Int?
    let onApprove: () -> Void
    let onReject: () -> Void
    @State private var isEnlarged = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppLayout.compactSpacing) {
            HStack {
                Image(systemName: "list.bullet.clipboard")
                    .foregroundStyle(.blue)
                Text("Plan (\(plan.steps.count) steps)")
                    .font(.app(.subheadline).weight(.semibold))
                Spacer()
                statusBadge
                TranscriptDetailActions(textToCopy: planText, isEnlarged: $isEnlarged)
            }

            Divider()

            TranscriptDetailViewport(maximumHeight: TranscriptDetailSizing.maximumHeight(enlarged: isEnlarged)) {
                steps
            }

            if plan.status == .pending {
                HStack(spacing: 12) {
                    Button(action: onApprove) {
                        Label("Approve", systemImage: "checkmark.circle.fill").font(.app(.body))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)

                    Button(action: onReject) {
                        Label("Reject", systemImage: "xmark.circle.fill").font(.app(.body))
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                }
                .padding(.top, 4)
            }
        }
        .padding(AppLayout.contentInset)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: AppLayout.surfaceRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppLayout.surfaceRadius, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: AppLayout.compactSpacing) {
            ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: AppLayout.compactSpacing) {
                    stepIndicator(for: index)
                    Image(systemName: step.tool.icon)
                        .frame(width: 16)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: step.description)
                            .font(.app(.caption))
                        Text(L10n.text(step.tool.displayName))
                            .font(.app(.caption2))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .textSelection(.enabled)
    }

    private var planText: String {
        plan.steps.enumerated().map { index, step in
            "\(index + 1). \(step.description) (\(step.tool.displayName))"
        }.joined(separator: "\n")
    }

    private var borderColor: Color {
        switch plan.status {
        case .pending: .blue.opacity(0.3)
        case .approved, .executing: .orange.opacity(0.3)
        case .completed: .green.opacity(0.3)
        case .rejected, .failed: .red.opacity(0.3)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        let (text, color): (String, Color) = switch plan.status {
        case .pending: ("Pending", .blue)
        case .approved: ("Approved", .orange)
        case .executing: ("Running", .orange)
        case .completed: ("Done", .green)
        case .rejected: ("Rejected", .red)
        case .failed: ("Failed", .red)
        }
        Text(text)
            .font(.app(.caption2).weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func stepIndicator(for index: Int) -> some View {
        let result = results.first { $0.stepId == plan.steps[index].id }
        ZStack {
            Circle()
                .fill(stepColor(for: index, result: result))
                .frame(width: 18, height: 18)
            if let result {
                Image(systemName: result.status == .success ? "checkmark" : "xmark")
                    .font(.app(.caption2, weight: .bold))
                    .foregroundStyle(.white)
            } else if currentStepIndex == index {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Text("\(index + 1)")
                    .font(.app(.caption2, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    private func stepColor(for index: Int, result: StepResult?) -> Color {
        if let result {
            return result.status == .success ? .green : .red
        }
        if currentStepIndex == index { return .orange }
        return .secondary
    }
}

// MARK: - Tool Result Block

struct ToolResultBlockView: View {
    let step: PlanStep
    let result: StepResult
    @State private var isExpanded = false
    @State private var isEnlarged = false

    var body: some View {
        TranscriptDetailPanel(isExpanded: isExpanded) {
            HStack(spacing: AppLayout.compactSpacing) {
                TranscriptDisclosureButton(isExpanded: isExpanded) {
                    isExpanded.toggle()
                    if !isExpanded { isEnlarged = false }
                } label: {
                    Image(systemName: step.tool.icon)
                    Text(verbatim: step.description).lineLimit(1)
                    if result.durationMs > 0 {
                        Text("\(result.durationMs)ms")
                    }
                }
                Image(systemName: result.status == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.status == .success ? .green : .red)
                    .font(.app(.caption))
                if isExpanded {
                    TranscriptDetailActions(textToCopy: resultText, isEnlarged: $isEnlarged)
                }
            }
        } content: {
            TranscriptDetailViewport(maximumHeight: TranscriptDetailSizing.maximumHeight(enlarged: isEnlarged)) {
                resultContent.padding(AppLayout.contentInset)
            }
        }
    }

    private var resultContent: some View {
        VStack(alignment: .leading, spacing: AppLayout.compactSpacing) {
            Text(verbatim: result.output)
                .transcriptDetailText(monospaced: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let error = result.error, !error.isEmpty {
                Text(verbatim: error)
                    .transcriptDetailText()
                    .foregroundStyle(.red)
            }
        }
        .textSelection(.enabled)
    }

    private var resultText: String {
        [result.output, result.error].compactMap { $0 }.filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}

// MARK: - Agent Mode Toggle

struct AgentModeToggle: View {
    @Binding var isAgentMode: Bool

    var body: some View {
        Toggle(isOn: $isAgentMode) {
            Image(systemName: "wrench")
                .foregroundStyle(isAgentMode ? .orange : .secondary)
        }
        .toggleStyle(.button)
        .buttonStyle(.borderless)
        .help("Tools — run a tool-calling loop").font(.app(.body))
    }
}

// MARK: - Workspace folder picker

/// The workspace-folder picker behind the Agent pill's folder icon (the old
/// name-sized toolbar chip is gone — a variable-width chip in the toolbar
/// either wasted a fixed slot or re-tripped the » eviction bug; the current
/// folder shows in the pill's tooltip instead).
enum WorkspacePicker {
    /// `@MainActor`: a modal panel only runs on the main thread (already true in
    /// practice — `AppActivation` just makes it explicit).
    @MainActor
    static func pickDirectory() -> String? {
        let panel = OpenPanel.make()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Working Directory"
        guard AppActivation.runModal(panel) == .OK, let url = panel.url else { return nil }
        return url.path
    }
}
