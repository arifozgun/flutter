import UIKit

/// The handlers the engine's extra commands call. FlutterTextInputView has
/// methods with these names; the probe only records the call.
@objc protocol ProbeExtraActions {
    func handleLookUpAction()
    func handleSearchWebAction()
    func handleShareAction()
    func handleTranslateAction()
}

final class ProbeTextPosition: UITextPosition {
    let index: Int
    init(_ index: Int) { self.index = index }
}

final class ProbeTextRange: UITextRange {
    let range: NSRange
    init(_ range: NSRange) { self.range = range }
    override var start: UITextPosition { ProbeTextPosition(range.location) }
    override var end: UITextPosition { ProbeTextPosition(NSMaxRange(range)) }
    override var isEmpty: Bool { range.length == 0 }
}

final class ProbeSelectionRect: UITextSelectionRect {
    private let storedRect: CGRect
    private let storedContainsStart: Bool
    private let storedContainsEnd: Bool

    init(rect: CGRect, containsStart: Bool, containsEnd: Bool) {
        storedRect = rect
        storedContainsStart = containsStart
        storedContainsEnd = containsEnd
    }

    override var rect: CGRect { storedRect }
    override var writingDirection: NSWritingDirection { .leftToRight }
    override var containsStart: Bool { storedContainsStart }
    override var containsEnd: Bool { storedContainsEnd }
    override var isVertical: Bool { false }
}

/// A custom text input view set up the way FlutterTextInputView is for the
/// system edit menu: a UIView that adopts UITextInput, implements the standard
/// edit actions with the same canPerformAction rules, owns a
/// UIEditMenuInteraction whose delegate it is, and presents the menu itself
/// with a configuration whose identifier is nil and source point is zero.
/// Unlike Flutter's hidden view it draws its own text and selection so the
/// screenshots show what the menu points at.
final class ProbeTextInputView: UIView, UITextInput, UIEditMenuInteractionDelegate, ProbeExtraActions {
    private var storage: NSMutableString
    private var selection: NSRange
    private var marked: NSRange?

    weak var inputDelegate: UITextInputDelegate?
    var markedTextStyle: [NSAttributedString.Key: Any]?
    lazy var tokenizer: UITextInputTokenizer = UITextInputStringTokenizer(textInput: self)

    /// Builds the menu returned from the delegate. Receives UIKit's
    /// suggestedActions.
    var menuProvider: (([UIMenuElement]) -> UIMenu?)?
    /// Diagnostic only: answer YES for every action UIKit asks about, to see
    /// which commands exist before canPerformAction filters them.
    var answersYesToEveryAction = false
    var onEvent: ((String) -> Void)?

    private(set) var editMenuInteraction: UIEditMenuInteraction!
    private let actionLog = ActionLog(name: "custom-canPerformAction")
    private var menuBuildCount = 0
    private let font = UIFont.systemFont(ofSize: 22)
    private let inset: CGFloat = 10

    init(text: String, selectedRange: NSRange) {
        storage = NSMutableString(string: text)
        selection = selectedRange
        super.init(frame: .zero)
        backgroundColor = UIColor.secondarySystemBackground
        isAccessibilityElement = true
        accessibilityIdentifier = "customTextInput"
        accessibilityLabel = text
        let interaction = UIEditMenuInteraction(delegate: self)
        addInteraction(interaction)
        editMenuInteraction = interaction
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Presentation (as FlutterTextInputView.showEditMenuWithTargetRect)

    func presentEditMenu() {
        onEvent?("presentEditMenu called; isFirstResponder=\(isFirstResponder)")
        let configuration = UIEditMenuConfiguration(identifier: nil, sourcePoint: .zero)
        editMenuInteraction.presentEditMenu(with: configuration)
    }

    func dismissEditMenu() {
        editMenuInteraction.dismissMenu()
    }

    /// Selection rect in this view's coordinates.
    var selectionRect: CGRect { firstRect(for: ProbeTextRange(selection)) }

    // MARK: - UIEditMenuInteractionDelegate

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        menuFor configuration: UIEditMenuConfiguration,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        menuBuildCount += 1
        let header = "=== build #\(menuBuildCount) configuration.identifier=\(String(describing: configuration.identifier)) sourcePoint=\(configuration.sourcePoint) suggestedActions.count=\(suggestedActions.count)\n"
        Probe.write("custom-suggestedActions", header + MenuDump.describe(suggestedActions), append: true)
        let menu: UIMenu?
        if let menuProvider {
            menu = menuProvider(suggestedActions)
        } else {
            menu = UIMenu(title: "", children: suggestedActions)
        }
        Probe.write("custom-returned", "=== build #\(menuBuildCount)\n" + MenuDump.describe(menu.map { [$0] } ?? []), append: true)
        actionLog.flush()
        onEvent?("menuFor called (build #\(menuBuildCount))")
        return menu
    }

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        targetRectFor configuration: UIEditMenuConfiguration
    ) -> CGRect {
        selectionRect
    }

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        willPresentMenuFor configuration: UIEditMenuConfiguration,
        animator: UIEditMenuInteractionAnimating
    ) {
        onEvent?("willPresentMenu")
    }

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        willDismissMenuFor configuration: UIEditMenuConfiguration,
        animator: UIEditMenuInteractionAnimating
    ) {
        onEvent?("willDismissMenu")
    }

    // MARK: - Responder

    override var canBecomeFirstResponder: Bool { true }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        // The same rules as FlutterTextInputView.canPerformAction:withSender:.
        let engineAnswer: Bool
        let defaultAnswer = super.canPerformAction(action, withSender: sender)
        if action == #selector(UIResponderStandardEditActions.paste(_:)) {
            engineAnswer = UIPasteboard.general.hasStrings
        } else if action == #selector(UIResponderStandardEditActions.copy(_:))
            || action == #selector(UIResponderStandardEditActions.cut(_:))
            || action == #selector(UIResponderStandardEditActions.delete(_:)) {
            engineAnswer = selection.length > 0
        } else if action == #selector(UIResponderStandardEditActions.selectAll(_:)) {
            engineAnswer = hasText
        } else if action == #selector(UIResponder.captureTextFromCamera(_:)) {
            engineAnswer = true
        } else {
            engineAnswer = defaultAnswer
        }
        let answer = answersYesToEveryAction ? true : engineAnswer
        actionLog.record(action, answer: answer, defaultAnswer: defaultAnswer, sender: sender)
        return answer
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        let system = builder.system == .context ? "context" : (builder.system == .main ? "main" : "other")
        let root = builder.menu(for: .root)
        Probe.write("custom-buildMenu", "=== buildMenu system=\(system)\n" + MenuDump.describe(root.map { [$0] } ?? []), append: true)
    }

    override func validate(_ command: UICommand) {
        super.validate(command)
        Probe.write("custom-validate", "validate action=\(NSStringFromSelector(command.action)) title=\"\(command.title)\" attributes=\(MenuDump.attributeNames(command.attributes))\n", append: true)
    }

    // MARK: - Standard edit actions (as FlutterTextInputView)

    override func cut(_ sender: Any?) {
        onEvent?("cut:")
        UIPasteboard.general.string = storage.substring(with: selection)
        replace(ProbeTextRange(selection), withText: "")
    }

    override func copy(_ sender: Any?) {
        onEvent?("copy:")
        UIPasteboard.general.string = storage.substring(with: selection)
    }

    override func paste(_ sender: Any?) {
        onEvent?("paste:")
        if let string = UIPasteboard.general.string {
            insertText(string)
        }
    }

    override func delete(_ sender: Any?) {
        onEvent?("delete:")
        replace(ProbeTextRange(selection), withText: "")
    }

    override func selectAll(_ sender: Any?) {
        onEvent?("selectAll:")
        selectedTextRange = ProbeTextRange(NSRange(location: 0, length: storage.length))
    }

    // MARK: - ProbeExtraActions

    func handleLookUpAction() { onEvent?("handleLookUpAction") }
    func handleSearchWebAction() { onEvent?("handleSearchWebAction") }
    func handleShareAction() { onEvent?("handleShareAction") }
    func handleTranslateAction() { onEvent?("handleTranslateAction") }

    // MARK: - Drawing

    private var attributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: UIColor.label]
    }

    private func xOffset(_ index: Int) -> CGFloat {
        let clamped = max(0, min(index, storage.length))
        let prefix = storage.substring(to: clamped) as NSString
        return inset + prefix.size(withAttributes: attributes).width
    }

    private var lineRect: CGRect {
        CGRect(x: inset, y: (bounds.height - font.lineHeight) / 2, width: bounds.width - 2 * inset, height: font.lineHeight)
    }

    override func draw(_ rect: CGRect) {
        if selection.length > 0 {
            UIColor.systemBlue.withAlphaComponent(0.25).setFill()
            UIBezierPath(rect: selectionRect).fill()
        }
        (storage as NSString).draw(at: CGPoint(x: inset, y: lineRect.minY), withAttributes: attributes)
        if selection.length == 0 {
            UIColor.systemBlue.setFill()
            UIBezierPath(rect: caretRect(for: ProbeTextPosition(selection.location))).fill()
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: font.lineHeight + 24)
    }

    // MARK: - UIKeyInput

    var hasText: Bool { storage.length > 0 }

    func insertText(_ text: String) {
        replace(ProbeTextRange(selection), withText: text)
    }

    func deleteBackward() {
        if selection.length > 0 {
            replace(ProbeTextRange(selection), withText: "")
        } else if selection.location > 0 {
            replace(ProbeTextRange(NSRange(location: selection.location - 1, length: 1)), withText: "")
        }
    }

    // MARK: - UITextInput

    private func clamp(_ index: Int) -> Int { max(0, min(index, storage.length)) }

    private func index(_ position: UITextPosition) -> Int {
        (position as? ProbeTextPosition)?.index ?? 0
    }

    private func nsRange(_ range: UITextRange) -> NSRange {
        (range as? ProbeTextRange)?.range ?? NSRange(location: 0, length: 0)
    }

    func text(in range: UITextRange) -> String? {
        let r = nsRange(range)
        guard NSMaxRange(r) <= storage.length else { return nil }
        return storage.substring(with: r)
    }

    func replace(_ range: UITextRange, withText text: String) {
        let r = nsRange(range)
        inputDelegate?.textWillChange(self)
        storage.replaceCharacters(in: r, with: text)
        inputDelegate?.textDidChange(self)
        selection = NSRange(location: r.location + (text as NSString).length, length: 0)
        accessibilityLabel = storage as String
        setNeedsDisplay()
    }

    var selectedTextRange: UITextRange? {
        get { ProbeTextRange(selection) }
        set {
            guard let newValue else { return }
            inputDelegate?.selectionWillChange(self)
            selection = nsRange(newValue)
            inputDelegate?.selectionDidChange(self)
            setNeedsDisplay()
        }
    }

    var markedTextRange: UITextRange? { marked.map { ProbeTextRange($0) } }

    func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        let text = markedText ?? ""
        let target = marked ?? selection
        storage.replaceCharacters(in: target, with: text)
        marked = text.isEmpty ? nil : NSRange(location: target.location, length: (text as NSString).length)
        selection = NSRange(location: target.location + selectedRange.location, length: selectedRange.length)
        setNeedsDisplay()
    }

    func unmarkText() { marked = nil }

    var beginningOfDocument: UITextPosition { ProbeTextPosition(0) }
    var endOfDocument: UITextPosition { ProbeTextPosition(storage.length) }

    func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? {
        let a = index(fromPosition)
        let b = index(toPosition)
        return ProbeTextRange(NSRange(location: min(a, b), length: abs(a - b)))
    }

    func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
        let target = index(position) + offset
        guard target >= 0, target <= storage.length else { return nil }
        return ProbeTextPosition(target)
    }

    func position(from position: UITextPosition, in direction: UITextLayoutDirection, offset: Int) -> UITextPosition? {
        switch direction {
        case .left: return self.position(from: position, offset: -offset)
        case .right: return self.position(from: position, offset: offset)
        default: return nil
        }
    }

    func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult {
        let a = index(position)
        let b = index(other)
        return a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
    }

    func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int {
        index(toPosition) - index(from)
    }

    func position(within range: UITextRange, farthestIn direction: UITextLayoutDirection) -> UITextPosition? {
        let r = nsRange(range)
        switch direction {
        case .left, .up: return ProbeTextPosition(r.location)
        default: return ProbeTextPosition(NSMaxRange(r))
        }
    }

    func characterRange(byExtending position: UITextPosition, in direction: UITextLayoutDirection) -> UITextRange? {
        let i = index(position)
        switch direction {
        case .left, .up: return ProbeTextRange(NSRange(location: 0, length: i))
        default: return ProbeTextRange(NSRange(location: i, length: storage.length - i))
        }
    }

    func baseWritingDirection(for position: UITextPosition, in direction: UITextStorageDirection) -> NSWritingDirection {
        .leftToRight
    }

    func setBaseWritingDirection(_ writingDirection: NSWritingDirection, for range: UITextRange) {}

    func firstRect(for range: UITextRange) -> CGRect {
        let r = nsRange(range)
        let start = xOffset(r.location)
        let end = xOffset(NSMaxRange(r))
        return CGRect(x: start, y: lineRect.minY, width: max(end - start, 1), height: lineRect.height)
    }

    func caretRect(for position: UITextPosition) -> CGRect {
        CGRect(x: xOffset(index(position)), y: lineRect.minY, width: 2, height: lineRect.height)
    }

    func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        [ProbeSelectionRect(rect: firstRect(for: range), containsStart: true, containsEnd: true)]
    }

    func closestPosition(to point: CGPoint) -> UITextPosition? {
        var best = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for i in 0...storage.length {
            let distance = abs(xOffset(i) - point.x)
            if distance < bestDistance {
                bestDistance = distance
                best = i
            }
        }
        return ProbeTextPosition(best)
    }

    func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? {
        let r = nsRange(range)
        let i = index(closestPosition(to: point) ?? ProbeTextPosition(r.location))
        return ProbeTextPosition(max(r.location, min(i, NSMaxRange(r))))
    }

    func characterRange(at point: CGPoint) -> UITextRange? {
        let i = clamp(index(closestPosition(to: point) ?? ProbeTextPosition(0)))
        return ProbeTextRange(NSRange(location: min(i, max(storage.length - 1, 0)), length: storage.length > 0 ? 1 : 0))
    }
}
