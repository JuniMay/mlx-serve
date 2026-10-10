import SwiftUI

/// A model's input, output, and supporting controls share one workspace.
struct GenerationWorkspace<Prompt: View, Model: View, Attachments: View,
                           Parameters: View, Actions: View, Result: View>: View {
    let title: String
    let modelName: String
    var hasAttachments = false
    var attachmentCount = 0
    var notice: String? = nil
    @ViewBuilder var prompt: Prompt
    @ViewBuilder var model: Model
    @ViewBuilder var attachments: Attachments
    @ViewBuilder var parameters: Parameters
    @ViewBuilder var actions: Actions
    @ViewBuilder var result: Result

    @State private var showingModel = false
    @State private var showingAttachments = false
    @State private var showingParameters = false
    @State private var promptHeight: CGFloat = 110

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                VStack(spacing: AppLayout.rowSpacing) { result }
                    .frame(maxWidth: AppLayout.generationColumnWidth, maxHeight: .infinity)
                    .padding(AppLayout.pageInset)

                VStack(spacing: AppLayout.compactSpacing) {
                    input(maximumHeight: min(240, max(80, geometry.size.height * 0.4)))
                    if let notice {
                        Text(L10n.text(notice))
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    controls(size: geometry.size)
                }
                .floatingInputSurface()
                .frame(maxWidth: AppLayout.generationColumnWidth)
                .padding(.horizontal, AppLayout.pageInset)
                .padding(.bottom, AppLayout.pageInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingParameters.toggle() } label: {
                    Image(systemName: "sidebar.right")
                }
                .accessibilityLabel("Generation settings")
                .accessibilityValue(showingParameters ? "Open" : "Closed")
                .help("Generation settings")
            }
        }
        .inspector(isPresented: $showingParameters) {
            if showingParameters {
                VStack(spacing: 0) {
                    HStack {
                        Text(L10n.format("%@ settings", L10n.text(title)))
                            .font(.app(.headline))
                        Spacer()
                        Button { showingParameters = false } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Close generation settings")
                        .help("Close generation settings")
                    }
                    .padding(AppLayout.pageInset)

                    ScrollView {
                        VStack(alignment: .leading, spacing: AppLayout.sectionSpacing) { parameters }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(AppLayout.pageInset)
                    }
                }
                .inspectorColumnWidth(min: 300, ideal: 360, max: 460)
            }
        }
    }

    private func input(maximumHeight: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppLayout.rowSpacing) { prompt }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { ceil($0.size.height) }
                    action: { promptHeight = $0 }
        }
        .frame(height: min(promptHeight, maximumHeight))
        .scrollBounceBehavior(.basedOnSize)
    }

    private func controls(size: CGSize) -> some View {
        ComposerControlsRow {
            if hasAttachments {
                Button { showingAttachments.toggle() } label: {
                    ComposerControlSymbol(name: "plus")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.regular)
                .overlay(alignment: .topTrailing) {
                    if attachmentCount > 0 {
                        Text(attachmentCount, format: .number)
                            .font(.app(.caption2)).monospacedDigit()
                            .padding(.horizontal, 3)
                            .background(.background, in: Capsule())
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("Attachments")
                .accessibilityValue("\(attachmentCount) attached")
                .help("Attachments and reference inputs")
                .popover(isPresented: $showingAttachments, arrowEdge: .top) {
                    popoverContent(size: size) { attachments }
                }
            }
        } model: {
            Button { showingModel.toggle() } label: {
                HStack(spacing: 6) {
                    Text(verbatim: modelName).lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: 190)
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
            .composerCapsule()
            .fixedSize(horizontal: true, vertical: false)
            .help(modelName)
            .accessibilityLabel("Generation model")
            .accessibilityValue(modelName)
            .popover(isPresented: $showingModel, arrowEdge: .top) {
                popoverContent(size: size) { model }
            }
        } actions: {
            actions.fixedSize(horizontal: true, vertical: false)
        }
    }

    private func popoverContent<Content: View>(size: CGSize,
                                               @ViewBuilder content: () -> Content) -> some View {
        GenerationPopover(width: min(420, max(240, size.width - 40)),
                          maximumHeight: min(520, max(200, size.height - 80)), content: content)
    }
}

private struct GenerationPopover<Content: View>: View {
    let width: CGFloat
    let maximumHeight: CGFloat
    @ViewBuilder var content: Content
    @State private var height: CGFloat = 80

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppLayout.sectionSpacing) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppLayout.contentInset)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { ceil($0.size.height) }
                    action: { height = $0 }
        }
        .frame(width: width, height: min(height, maximumHeight))
        .scrollBounceBehavior(.basedOnSize)
    }
}
