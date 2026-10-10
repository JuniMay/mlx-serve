import SwiftUI

/// Composer-row context gauge: a percentage and a fill ring, opening a popover
/// with the full breakdown.
///
/// Replaces the full-width bar that used to sit above the composer. That bar
/// spent a permanent strip of the window on a number that matters occasionally,
/// and still couldn't say what was IN the context. A pill costs one control's
/// width and puts the detail one click away.
struct ContextPill: View {
    let stats: ContextWindowStats
    /// Decode speed of the last timed reply, from the SERVER's own `timings`
    /// (see `ContextWindowStats.speedText`). nil until a reply has been timed.
    let decodeSpeed: Double?
    /// True while this chat is streaming: the figure is moving, so it's marked
    /// live rather than reading as a settled total.
    let isLive: Bool

    @State private var showDetail = false

    private var tint: Color {
        switch stats.pressure {
        case .comfortable: .secondary
        case .warm: .orange
        case .tight: .orange
        case .over: .red
        }
    }

    var body: some View {
        Button { showDetail.toggle() } label: {
            HStack(spacing: 5) {
                ring
                Text(L10n.text(stats.percentText))
                    .font(.app(.caption).monospacedDigit().weight(.medium))
                    .foregroundStyle(stats.pressure == .comfortable ? Color.secondary : tint)
            }
            .padding(.horizontal, ComposerControlMetrics.horizontalPadding)
            .frame(minHeight: ComposerControlMetrics.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Context window")
        .accessibilityValue(L10n.text(stats.percentText))
        .help(L10n.format(
            "Context window — %@ of %@ tokens used. Click for the breakdown.",
            stats.percentText,
            ContextWindowStats.compact(stats.contextLength)
        ))
        .popover(isPresented: $showDetail, arrowEdge: .top) {
            ContextWindowDetail(stats: stats, decodeSpeed: decodeSpeed)
        }
    }

    /// Fill ring rather than a bar: at pill size a 4pt-tall bar is unreadable,
    /// and a ring shows the same fraction in a square.
    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.30), lineWidth: 2)
            Circle()
                .trim(from: 0, to: stats.barFraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.15), value: stats.barFraction)
        }
        .frame(width: 12, height: 12)
        .opacity(isLive ? 0.85 : 1)
    }
}

/// The pill's popover: headline percentage, fill bar, and the exact figures.
struct ContextWindowDetail: View {
    let stats: ContextWindowStats
    let decodeSpeed: Double?

    private var tint: Color {
        switch stats.pressure {
        case .comfortable: .green
        case .warm: .orange
        case .tight: .orange
        case .over: .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "brain")
                    .font(.app(.title3))
                    .foregroundStyle(.secondary)
                Text("Context window")
                    .font(.app(.callout).weight(.semibold))
                Spacer(minLength: 0)
            }
            .padding(12)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L10n.text(stats.percentText))
                        .font(.app(.largeTitle, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                    Spacer()
                    Text("\(ContextWindowStats.compact(stats.usedTokens)) / \(ContextWindowStats.compact(stats.contextLength))")
                        .font(.app(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.18))
                        Capsule().fill(tint)
                            .frame(width: max(0, geo.size.width * stats.barFraction))
                    }
                }
                .frame(height: 6)

                if stats.fromRejectedRequest {
                    Text("Last request overflowed the context window.")
                        .font(.app(.caption))
                        .foregroundStyle(.red)
                } else {
                    Text("Last reported token usage, compared with the current context limit. Changing models can change token counts.")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)

            Divider()

            VStack(spacing: 6) {
                row(icon: "arrow.up", label: "Prompt", value: stats.promptTokens)
                row(icon: "sum", label: "Used", value: stats.usedTokens, emphasized: true)
                row(icon: "ruler", label: "Remaining", value: stats.remainingTokens)
            }
            .padding(12)

            // Its OWN section, below the divider: everything above counts
            // TOKENS IN THE WINDOW, and a throughput figure in that group would
            // read as one more thing filling the context. Absent until a reply
            // has been timed, rather than a placeholder dash.
            if let speed = ContextWindowStats.speedText(decodeSpeed) {
                Divider()
                textRow(icon: "gauge.with.needle", label: "Last reply speed", value: speed)
                    .padding(12)
            }
        }
        .frame(width: 280)
    }

    /// Same layout as `row`, for a figure that is already formatted.
    private func textRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(L10n.text(label))
                .font(.app(.callout))
            Spacer()
            Text(value)
                .font(.app(.callout, design: .monospaced))
        }
    }

    private func row(icon: String, label: String, value: Int, emphasized: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(L10n.text(label))
                .font(.app(.callout))
            Spacer()
            // Exact figures here — the pill rounds, this is where you check.
            Text(value.formatted(.number.grouping(.automatic)))
                .font(.app(.callout, design: .monospaced))
                .fontWeight(emphasized ? .semibold : .regular)
        }
    }
}
