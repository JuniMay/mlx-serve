import SwiftUI

struct WorkspaceSplitView<Sidebar: View, Secondary: View, Detail: View>: View {
    let hasSecondaryList: Bool
    private let sidebar: Sidebar
    private let secondary: Secondary
    private let detail: Detail
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic

    init(hasSecondaryList: Bool, @ViewBuilder sidebar: () -> Sidebar,
         @ViewBuilder secondary: () -> Secondary, @ViewBuilder detail: () -> Detail) {
        self.hasSecondaryList = hasSecondaryList
        self.sidebar = sidebar()
        self.secondary = secondary()
        self.detail = detail()
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar.navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            if hasSecondaryList {
                HSplitView {
                    secondary.frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
                    detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                detail
            }
        }
    }
}
