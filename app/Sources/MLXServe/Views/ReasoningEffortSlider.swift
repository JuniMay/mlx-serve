import AppKit
import SwiftUI

enum ReasoningEffortSliderMapping {
    static func index(for effort: ReasoningEffort, isOn: Bool = true) -> Int {
        guard isOn else { return 0 }
        switch effort {
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        }
    }

    static func effort(at index: Int) -> ReasoningEffort {
        switch index {
        case ...1: return .low
        case 2: return .medium
        default: return .high
        }
    }

    static func selection(at index: Int, preserving effort: ReasoningEffort)
        -> (isOn: Bool, effort: ReasoningEffort) {
        index <= 0 ? (false, effort) : (true, self.effort(at: index))
    }
}

struct ReasoningEffortSlider: View {
    @Binding var isOn: Bool
    @Binding var effort: ReasoningEffort

    var body: some View {
        ReasoningEffortSliderControl(isOn: $isOn, effort: $effort)
            .frame(height: 32)
    }
}

private struct ReasoningEffortSliderControl: NSViewRepresentable {
    @Binding var isOn: Bool
    @Binding var effort: ReasoningEffort
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.layoutDirection) private var layoutDirection

    func makeCoordinator() -> Coordinator { Coordinator(isOn: $isOn, effort: $effort) }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider()
        slider.cell = ReasoningEffortSliderCell()
        slider.sliderType = .linear
        slider.isVertical = false
        slider.controlSize = .large
        slider.minValue = 0
        slider.maxValue = 3
        slider.numberOfTickMarks = 4
        slider.allowsTickMarkValuesOnly = true
        slider.altIncrementValue = 1
        slider.isContinuous = true
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.valueChanged(_:))
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.isOn = $isOn
        context.coordinator.effort = $effort
        slider.isEnabled = isEnabled
        slider.userInterfaceLayoutDirection = layoutDirection == .rightToLeft ? .rightToLeft : .leftToRight
        slider.integerValue = ReasoningEffortSliderMapping.index(for: effort, isOn: isOn)
        slider.setAccessibilityLabel(L10n.text("Reasoning"))
        slider.setAccessibilityValueDescription(L10n.text(isOn ? effort.label : "Off"))
        slider.needsDisplay = true
    }

    final class Coordinator: NSObject {
        var isOn: Binding<Bool>
        var effort: Binding<ReasoningEffort>

        init(isOn: Binding<Bool>, effort: Binding<ReasoningEffort>) {
            self.isOn = isOn
            self.effort = effort
        }

        @objc func valueChanged(_ slider: NSSlider) {
            let index = Int(slider.closestTickMarkValue(toValue: slider.doubleValue))
            let next = ReasoningEffortSliderMapping.selection(at: index, preserving: effort.wrappedValue)
            slider.integerValue = ReasoningEffortSliderMapping.index(for: next.effort, isOn: next.isOn)
            slider.setAccessibilityValueDescription(L10n.text(next.isOn ? next.effort.label : "Off"))
            effort.wrappedValue = next.effort
            isOn.wrappedValue = next.isOn
        }
    }
}

/// Drawing alone changes; AppKit owns tracking, focus, keyboard stepping and accessibility.
private final class ReasoningEffortSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let bounds = controlView?.bounds ?? rect
        let track = NSRect(x: bounds.minX + 2, y: bounds.midY - 12,
                           width: max(0, bounds.width - 4), height: 24)
        let path = NSBezierPath(roundedRect: track, xRadius: 12, yRadius: 12)
        let alpha: CGFloat = isEnabled ? 1 : 0.35
        let gradient = NSGradient(starting: NSColor(srgbRed: 0.70, green: 0.35, blue: 0.23, alpha: alpha),
                                  ending: NSColor(srgbRed: 0.90, green: 0.56, blue: 0.39, alpha: alpha))
        let rightToLeft = controlView?.userInterfaceLayoutDirection == .rightToLeft
        gradient?.draw(in: path, angle: rightToLeft ? 180 : 0)
    }

    override func knobRect(flipped: Bool) -> NSRect {
        let native = super.knobRect(flipped: flipped)
        let bounds = controlView?.bounds ?? native
        let centerX = max(bounds.minX + 14, min(native.midX, bounds.maxX - 14))
        return NSRect(x: centerX - 14, y: bounds.midY - 14, width: 28, height: 28)
    }

    override func drawKnob(_ knobRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(isEnabled ? 0.18 : 0.08)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        NSColor.white.withAlphaComponent(isEnabled ? 1 : 0.65).setFill()
        NSBezierPath(ovalIn: knobRect).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    override func drawTickMarks() {}
}
