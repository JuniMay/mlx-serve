import SwiftUI

/// Secondary menus in compact forms use the system bezel and disclosure.
struct PaneChipMenu: ViewModifier {
    func body(content: Content) -> some View {
        content
            .menuStyle(.borderedButton)
            .controlSize(.small)
            .menuIndicator(.visible)
    }
}
