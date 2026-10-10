import SwiftUI

struct GenerationSectionHeader<Controls: View>: View {
    let title: String
    @ViewBuilder var controls: Controls

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppLayout.compactSpacing) {
                heading.fixedSize()
                Spacer(minLength: AppLayout.compactSpacing)
                HStack(spacing: AppLayout.compactSpacing) { controls }.fixedSize()
            }
            VStack(alignment: .leading, spacing: AppLayout.compactSpacing) {
                heading
                FlowLayout(spacing: AppLayout.compactSpacing, rowSpacing: AppLayout.compactSpacing) { controls }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heading: some View {
        Text(L10n.text(title)).font(.app(.headline))
    }
}
