import AppKit
import SwiftUI

/// Native text input that grows to a line limit, then scrolls.
struct GrowingTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var measuredHeight: CGFloat
    var selection: Binding<TextSelection?>? = nil
    var font: NSFont = .preferredFont(forTextStyle: .body)
    var minLines: Int = 1
    var maxLines: Int = 15
    var isIdle: Bool
    var canSteer: Bool = false
    var returnInsertsNewline = false
    var onSend: () -> Void
    /// Return false to leave Escape to AppKit.
    var onCancel: () -> Bool = { false }
    /// History navigation receives caret edges so arrows can still edit a draft.
    var onArrow: (ComposerHistory.Direction, _ caretAtStart: Bool, _ caretAtEnd: Bool) -> Bool = { _, _, _ in false }
    /// The slash menu handles its keys before the editor does.
    var onKeyCommand: (ComposerKeyCommand) -> Bool = { _ in false }

    let inset = NSSize(width: ComposerTextMetrics.containerInsetWidth,
                       height: ComposerTextMetrics.containerInsetHeight)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.isApplyingState = true
        defer { context.coordinator.isApplyingState = false }
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.verticalScrollElasticity = .allowed

        let tv = ComposerTextView()
        tv.delegate = context.coordinator
        tv.isEditable = context.environment.isEnabled
        tv.isSelectable = true
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.font = font
        tv.textColor = .labelColor
        tv.insertionPointColor = .labelColor
        tv.textContainerInset = inset
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.lineFragmentPadding = ComposerTextMetrics.lineFragmentPadding
        tv.autoresizingMask = [.width]
        tv.string = text
        tv.onBecomeFocus = { [weak c = context.coordinator] in c?.setFocus(true) }
        tv.onResignFocus = { [weak c = context.coordinator] in c?.setFocus(false) }
        tv.onWidthChange = { [weak c = context.coordinator] in
            DispatchQueue.main.async { c?.recomputeHeight() }
        }

        scroll.documentView = tv
        context.coordinator.textView = tv
        context.coordinator.applySelection(to: tv)
        DispatchQueue.main.async { context.coordinator.recomputeHeight() }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? ComposerTextView else { return }
        context.coordinator.parent = self
        context.coordinator.isApplyingState = true
        defer { context.coordinator.isApplyingState = false }
        let textChanged = tv.string != text
        if textChanged {
            tv.string = text
            // Recalled drafts place the caret at the end unless a selection is supplied.
            tv.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            context.coordinator.recomputeHeight()
        }
        context.coordinator.applySelection(to: tv, textChanged: textChanged)
        let enabled = context.environment.isEnabled
        if tv.isEditable != enabled { tv.isEditable = enabled }
        // Only a new focus request may take first responder from another control.
        if isFocused != context.coordinator.appliedFocus {
            context.coordinator.appliedFocus = isFocused
            if isFocused, tv.window != nil, tv.window?.firstResponder !== tv {
                DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingTextEditor
        weak var textView: ComposerTextView?
        var appliedFocus = false
        var isApplyingState = false
        private var appliedSelection: NSRange?
        init(_ parent: GrowingTextEditor) { self.parent = parent }

        func applySelection(to textView: NSTextView, textChanged: Bool = false) {
            guard let selection = parent.selection?.wrappedValue,
                  case .selection(let range) = selection.indices else { return }
            let text = textView.string
            guard range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex else {
                appliedSelection = nil
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.parent.text == text,
                          let current = self.parent.selection?.wrappedValue,
                          case .selection(let currentRange) = current.indices,
                          currentRange == range else { return }
                    self.parent.selection?.wrappedValue = nil
                }
                return
            }
            let native = NSRange(range, in: textView.string)
            guard Range(native, in: textView.string) != nil else { return }
            guard textChanged || native != appliedSelection else { return }
            appliedSelection = native
            if textView.selectedRange() != native { textView.setSelectedRange(native) }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingState, let selection = parent.selection, let textView,
                  let range = Range(textView.selectedRange(), in: textView.string) else { return }
            let text = textView.string
            let native = textView.selectedRange()
            appliedSelection = native
            let publish = { [weak self, weak textView] in
                guard let self, let textView, self.parent.text == text,
                      textView.string == text, textView.selectedRange() == native else { return }
                selection.wrappedValue = TextSelection(range: range)
            }
            if parent.text == text { publish() }
            else { DispatchQueue.main.async(execute: publish) }
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            if parent.text != tv.string { parent.text = tv.string }
            recomputeHeight()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                if parent.onKeyCommand(.up) { return true }
            case #selector(NSResponder.moveDown(_:)):
                if parent.onKeyCommand(.down) { return true }
            case #selector(NSResponder.insertTab(_:)):
                if parent.onKeyCommand(.accept) { return true }
            case #selector(NSResponder.cancelOperation(_:)):
                if parent.onKeyCommand(.cancel) { return true }
            default:
                break
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                return parent.onCancel()
            }
            if commandSelector == #selector(NSResponder.moveUp(_:))
                || commandSelector == #selector(NSResponder.moveDown(_:)) {
                let selection = textView.selectedRange()
                let length = (textView.string as NSString).length
                let collapsed = selection.length == 0
                return parent.onArrow(
                    commandSelector == #selector(NSResponder.moveUp(_:)) ? .up : .down,
                    collapsed && selection.location == 0,
                    collapsed && selection.location == length)
            }
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            // Return picks the highlighted command when the menu is open —
            // it must not send a half-typed "/mus".
            if parent.onKeyCommand(.accept) { return true }
            let shift = parent.returnInsertsNewline
                || (NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false)
            switch ComposerKey.onReturn(shift: shift, isIdle: parent.isIdle, canSteer: parent.canSteer) {
            case .newline:
                textView.insertNewlineIgnoringFieldEditor(self)
                return true
            case .send, .steer:
                parent.onSend()
                return true
            case .ignore:
                return true
            }
        }

        func setFocus(_ value: Bool) {
            guard parent.isFocused != value else { return }
            DispatchQueue.main.async { self.parent.isFocused = value }
        }

        func recomputeHeight() {
            guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            lm.ensureLayout(for: tc)
            let content = lm.usedRect(for: tc).height
            let line = tv.font.map { $0.ascender - $0.descender + $0.leading } ?? 16
            let r = ComposerLayout.resolve(contentHeight: content,
                                           lineHeight: max(line, 12),
                                           minLines: parent.minLines,
                                           maxLines: parent.maxLines,
                                           verticalInset: parent.inset.height * 2)
            // Past the cap the scroll view owns overflow; below it the frame grows.
            if let scroll = tv.enclosingScrollView, scroll.hasVerticalScroller != r.scrolls {
                scroll.hasVerticalScroller = r.scrolls
            }
            if abs(parent.measuredHeight - r.height) > 0.5 {
                DispatchQueue.main.async { self.parent.measuredHeight = r.height }
            }
        }
    }
}

/// Reports native focus and wrapping changes to the SwiftUI owner.
final class ComposerTextView: NSTextView {
    var onBecomeFocus: (() -> Void)?
    var onResignFocus: (() -> Void)?
    var onWidthChange: (() -> Void)?

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged { onWidthChange?() }
    }
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onBecomeFocus?() }
        return ok
    }
    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { onResignFocus?() }
        return ok
    }
}
