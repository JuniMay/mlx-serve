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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .padding(AppLayout.contentInset)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppLayout.surfaceRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: AppLayout.surfaceRadius)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5)
                }
                .frame(maxWidth: 1000)
                .padding(.horizontal, AppLayout.pageInset)
                .padding(.bottom, AppLayout.pageInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: AppLayout.compactSpacing) {
                inputControls(size: size)
                Spacer(minLength: AppLayout.compactSpacing)
                actions
            }
            VStack(alignment: .leading, spacing: AppLayout.compactSpacing) {
                inputControls(size: size)
                HStack {
                    Spacer(minLength: 0)
                    actions
                }
            }
        }
    }

    private func inputControls(size: CGSize) -> some View {
        HStack(spacing: AppLayout.compactSpacing) {
            if hasAttachments {
                Button { showingAttachments.toggle() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        if attachmentCount > 0 {
                            Text(attachmentCount, format: .number).monospacedDigit()
                        }
                    }
                    .frame(minWidth: 20, minHeight: 20)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .accessibilityLabel("Attachments")
                .accessibilityValue("\(attachmentCount) attached")
                .help("Attachments and reference inputs")
                .popover(isPresented: $showingAttachments, arrowEdge: .top) {
                    popoverContent(size: size) { attachments }
                }
            }

            Button { showingModel.toggle() } label: {
                HStack(spacing: 6) {
                    Text(verbatim: modelName).lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: 190)
                    Image(systemName: "chevron.down").font(.app(.caption))
                }
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .help(modelName)
            .accessibilityLabel("Generation model")
            .accessibilityValue(modelName)
            .popover(isPresented: $showingModel, arrowEdge: .top) {
                popoverContent(size: size) { model }
            }

            Button { showingParameters.toggle() } label: {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .tint(showingParameters ? .accentColor : nil)
            .accessibilityLabel("Generation settings")
            .accessibilityValue(showingParameters ? "Open" : "Closed")
            .help("Generation settings")
        }
        .controlSize(.regular)
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
