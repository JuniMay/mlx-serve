import SwiftUI
import AppKit

/// Image previews stay anchored to their tile; text explanations use native help.
private struct HoverPreview<Preview: View>: ViewModifier {
    let width: CGFloat
    let container: CGRect
    let enabled: Bool
    @ViewBuilder var preview: () -> Preview

    @State private var hovering = false
    @State private var shown = false
    @State private var bounds = CGRect.zero
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                let rect = proxy.frame(in: .global)
                return CGRect(x: rect.minX, y: 0, width: rect.width, height: 0)
            } action: { bounds = $0 }
            .onHover { hovering = $0 }
            .task(id: hovering && enabled) {
                shown = false
                guard hovering && enabled else { return }
                do {
                    try await Task.sleep(for: .milliseconds(650))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                shown = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
                hovering = false
                shown = false
            }
            .onDisappear {
                hovering = false
                shown = false
            }
            .overlay(alignment: .topLeading) {
                if shown && hovering && enabled {
                    preview()
                        .frame(width: width, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
                        .offset(x: leadingOffset, y: -(height + 8))
                        .allowsHitTesting(false)
                }
            }
            .zIndex(shown ? 1 : 0)
    }

    private var leadingOffset: CGFloat {
        guard container.width > 0 else { return 0 }
        let wanted = bounds.midX - width / 2
        let highest = max(container.minX, container.maxX - width)
        return min(max(wanted, container.minX), highest) - bounds.minX
    }
}

extension View {
    func hoverPreview<Preview: View>(width: CGFloat, container: CGRect, enabled: Bool,
                                     @ViewBuilder _ preview: @escaping () -> Preview) -> some View {
        modifier(HoverPreview(width: width, container: container, enabled: enabled, preview: preview))
    }
}
