import SwiftUI

/// Exact entry and incremental adjustment share the same bounded value.
struct NumberStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var width: CGFloat = 56

    private var boundedValue: Binding<Int> {
        Binding(get: { value }, set: { value = min(range.upperBound, max(range.lowerBound, $0)) })
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField("", value: boundedValue, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder)
                .font(.app(.body).monospacedDigit())
                .multilineTextAlignment(.trailing)
                .frame(width: width)
                .accessibilityLabel(L10n.text(title))
            Stepper("", value: boundedValue, in: range, step: step)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel(L10n.text(title))
                .accessibilityValue(Text(verbatim: String(value)))
        }
        .fixedSize()
    }
}
