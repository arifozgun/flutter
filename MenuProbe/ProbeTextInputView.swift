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
    override var description: String { "\(index)" }
}

final class ProbeTextRange: UITextRange {
    let range: NSRange
    init(_ range: NSRange) { self.range = range }
    override var start: UITextPosition { ProbeTextPosition(range.location) }
    override var end: UITextPosition { ProbeTextPosition(NSMaxRange(range)) }
    override var isEmpty: Bool { range.length == 0 }
    override var description: String { NSStringFromRange(range) }
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

/// When the custom view has a UITextInteraction attached. The engine itself
/// only adds one for the length of `setTextInputState:` (`engineTransient`).
enum InteractionMode: String {
    /// Never attached.
    case none
    /// Attached when the view is created, kept for its whole life.
    case always
    /// Attached just before presentEditMenu, removed when the dismiss
    /// animation of the menu completes.
    case whileMenuShown
    /// Attached just before presentEditMenu, removed right after
    /// presentEditMenu returns (UIKit builds the menu later, asynchronously).
    case presentOnly
    /// Attached just before presentEditMenu, removed in willPresentMenu (after
    /// UIKit built the menu, before it is on screen).
    case untilWillPresent
    /// What the engine does in setTextInputState: add one when inputDelegate is
    /// nil and the view is first responder, and remove it again at the end of
    /// the same call. Done here once right before each presentEditMenu.
    case engineTransient
}

/// Single-line text geometry shared by the custom view and the separate view
/// that draws the text in the Flutter-like layout. All rects are in the
/// coordinate space whose origin is the top-left corner of the text area.
struct TextLayout {
    let text: NSString
    let size: CGSize
    static let font = UIFont.systemFont(ofSize: 22)
    static let inset: CGFloat = 10

    var attributes: [NSAttributedString.Key: Any] {
        [.font: Self.font, .foregroundColor: UIColor.label]
    }

    func x(_ index: Int) -> CGFloat {
        let clamped = max(0, min(index, text.length))
        return Self.inset + (text.substring(to: clamped) as NSString).size(withAttributes: attributes).width
    }

    var lineRect: CGRect {
        CGRect(x: Self.inset, y: (size.height - Self.font.lineHeight) / 2, width: max(size.width - 2 * Self.inset, 0), height: Self.font.lineHeight)
    }

    func rect(_ range: NSRange) -> CGRect {
        let start = x(range.location)
        let end = x(NSMaxRange(range))
        return CGRect(x: start, y: lineRect.minY, width: max(end - start, 1), height: lineRect.height)
    }

    func caret(_ index: Int) -> CGRect {
        CGRect(x: x(index), y: lineRect.minY, width: 2, height: lineRect.height)
    }

    func closestIndex(_ point: CGPoint) -> Int {
        var best = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for i in 0...text.length {
            let distance = abs(x(i) - point.x)
            if distance < bestDistance {
                bestDistance = distance
                best = i
            }
        }
        return best
    }

    func draw(selection: NSRange) {
        if selection.length > 0 {
            UIColor.systemBlue.withAlphaComponent(0.25).setFill()
            UIBezierPath(rect: rect(selection)).fill()
        }
        text.draw(at: CGPoint(x: Self.inset, y: lineRect.minY), withAttributes: attributes)
        if selection.length == 0 {
            UIColor.systemBlue.setFill()
            UIBezierPath(rect: caret(selection.location)).fill()
        }
    }

    static var height: CGFloat { font.lineHeight + 24 }
}

/// A custom text input view set up the way FlutterTextInputView is for the
/// system edit menu: a UIView that adopts UITextInput, implements the standard
/// edit actions with the same canPerformAction rules, owns a
/// UIEditMenuInteraction whose delegate it is, and presents the menu itself
/// with a configuration whose identifier is nil and source point is zero.
///
/// In the default layout it draws its own text and selection so the
/// screenshots show what the menu points at. In the Flutter-like layout
/// (`FlutterLikeTextInputView`) it is zero-sized and another view draws.
///
/// Every UITextInput entry point records its call in
/// `<tag>-textinput-calls.txt`; the view's own drawing and edit actions use
/// the unlogged helpers, so the log shows what UIKit asked.
class ProbeTextInputView: UIView, UITextInput, UIEditMenuInteractionDelegate, ProbeExtraActions {
    private var storage: NSMutableString
    private var selection: NSRange
    private var marked: NSRange?

    weak var inputDelegate: UITextInputDelegate? {
        didSet {
            calls.log("set inputDelegate = \(inputDelegate.map { String(describing: type(of: $0)) } ?? "nil")")
        }
    }

    var markedTextStyle: [NSAttributedString.Key: Any]?
    private lazy var stringTokenizer: UITextInputTokenizer = UITextInputStringTokenizer(textInput: self)
    var tokenizer: UITextInputTokenizer {
        calls.log("tokenizer")
        return stringTokenizer
    }

    /// Builds the menu returned from the delegate. Receives UIKit's
    /// suggestedActions.
    var menuProvider: (([UIMenuElement]) -> UIMenu?)?
    /// Diagnostic only: answer YES for every action UIKit asks about, to see
    /// which commands exist before canPerformAction filters them.
    var answersYesToEveryAction = false
    var interactionMode: InteractionMode = .none
    var onEvent: ((String) -> Void)?
    var onSelectionChange: ((NSRange) -> Void)?
    /// Size of the text area when the view itself is zero-sized.
    var layoutSize: CGSize?
    var drawsOwnText = true

    private(set) var editMenuInteraction: UIEditMenuInteraction!
    let calls = CallLog(name: "textinput-calls")
    private let actionLog = ActionLog(name: "custom-canPerformAction")
    private let targetLog = ActionLog(name: "custom-targetForAction")
    private var menuBuildCount = 0
    private var presentCount = 0
    private lazy var textInteraction: UITextInteraction = {
        let interaction = UITextInteraction(for: .editable)
        interaction.textInput = self
        return interaction
    }()

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

    var currentSelection: NSRange { selection }
    var text: String { storage as String }

    private var layout: TextLayout {
        TextLayout(text: storage, size: layoutSize ?? bounds.size)
    }

    // MARK: - UITextInteraction

    var hasTextInteraction: Bool {
        interactions.contains { $0 === textInteraction }
    }

    func attachTextInteraction(_ reason: String) {
        guard !hasTextInteraction else { return }
        addInteraction(textInteraction)
        let note = "UITextInteraction attached (\(reason)); inputDelegate=\(inputDelegateName)"
        calls.mark(note)
        onEvent?(note)
    }

    func detachTextInteraction(_ reason: String) {
        guard hasTextInteraction else { return }
        removeInteraction(textInteraction)
        let note = "UITextInteraction removed (\(reason)); inputDelegate=\(inputDelegateName)"
        calls.mark(note)
        onEvent?(note)
    }

    private var inputDelegateName: String {
        inputDelegate.map { String(describing: type(of: $0)) } ?? "nil"
    }

    func snapshot(_ label: String) {
        calls.mark("snapshot \(label)")
        ViewSnapshot.capture(label, focus: self, inputDelegate: inputDelegateName)
    }

    // MARK: - Presentation (as FlutterTextInputView.showEditMenuWithTargetRect)

    func presentEditMenu() {
        presentCount += 1
        let number = presentCount
        snapshot("present#\(number) before")
        switch interactionMode {
        case .engineTransient:
            if inputDelegate == nil && isFirstResponder {
                attachTextInteraction("engineTransient, as setTextInputState")
            }
            detachTextInteraction("engineTransient, end of setTextInputState")
        case .whileMenuShown, .presentOnly, .untilWillPresent:
            attachTextInteraction("before presentEditMenu, mode \(interactionMode.rawValue)")
            snapshot("present#\(number) after attach")
        case .none, .always:
            break
        }
        onEvent?("presentEditMenu called; isFirstResponder=\(isFirstResponder) hasTextInteraction=\(hasTextInteraction)")
        let configuration = UIEditMenuConfiguration(identifier: nil, sourcePoint: .zero)
        editMenuInteraction.presentEditMenu(with: configuration)
        onEvent?("presentEditMenu returned")
        if interactionMode == .presentOnly {
            detachTextInteraction("right after presentEditMenu returned")
        }
    }

    func dismissEditMenu() {
        editMenuInteraction.dismissMenu()
    }

    /// Selection rect in this view's coordinates.
    var selectionRect: CGRect { layout.rect(selection) }

    /// Rect of a range in this view's coordinates (not logged).
    func rect(for range: NSRange) -> CGRect { layout.rect(range) }

    // MARK: - UIEditMenuInteractionDelegate

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        menuFor configuration: UIEditMenuConfiguration,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        menuBuildCount += 1
        let header = "=== build #\(menuBuildCount) [\(Probe.stamp())] configuration.identifier=\(String(describing: configuration.identifier)) sourcePoint=\(configuration.sourcePoint) suggestedActions.count=\(suggestedActions.count) hasTextInteraction=\(hasTextInteraction)\n"
        Probe.write("custom-suggestedActions", header + MenuDump.describe(suggestedActions), append: true)
        calls.mark("menuFor build #\(menuBuildCount)")
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
        onEvent?("willPresentMenu hasTextInteraction=\(hasTextInteraction)")
        calls.mark("willPresentMenu")
        if interactionMode == .untilWillPresent {
            detachTextInteraction("in willPresentMenu")
        }
        animator.addCompletion { [weak self] in
            self?.onEvent?("present animation completed")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            self.snapshot("menu shown (0.8 s after willPresentMenu)")
            ViewSnapshot.displayedMenu("menu shown", appWindow: self.window)
            self.actionLog.flush()
            self.targetLog.flush()
        }
    }

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        willDismissMenuFor configuration: UIEditMenuConfiguration,
        animator: UIEditMenuInteractionAnimating
    ) {
        onEvent?("willDismissMenu")
        calls.mark("willDismissMenu")
        animator.addCompletion { [weak self] in
            guard let self else { return }
            self.onEvent?("dismiss animation completed")
            if self.interactionMode == .whileMenuShown {
                self.detachTextInteraction("dismiss animation completed")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.snapshot("after dismiss (0.6 s after the dismiss animation)")
            }
        }
    }

    // MARK: - Responder

    override var canBecomeFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        calls.log("becomeFirstResponder -> \(result)")
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        calls.log("resignFirstResponder -> \(result)")
        return result
    }

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
            engineAnswer = hasTextUnlogged
        } else if action == #selector(UIResponder.captureTextFromCamera(_:)) {
            engineAnswer = true
        } else {
            engineAnswer = defaultAnswer
        }
        let answer = answersYesToEveryAction ? true : engineAnswer
        actionLog.record(action, answer: answer, defaultAnswer: defaultAnswer, sender: sender)
        return answer
    }

    override func target(forAction action: Selector, withSender sender: Any?) -> Any? {
        let target = super.target(forAction: action, withSender: sender)
        let targetName = target.map { String(describing: type(of: $0)) } ?? "nil"
        targetLog.record(action, detail: "target=\(targetName) sender=\(ActionLog.senderText(sender)) hasTextInteraction=\(hasTextInteraction)")
        return target
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        let system = builder.system == .context ? "context" : (builder.system == .main ? "main" : "other")
        let root = builder.menu(for: .root)
        Probe.write("custom-buildMenu", "=== buildMenu system=\(system) [\(Probe.stamp())]\n" + MenuDump.describe(root.map { [$0] } ?? []), append: true)
    }

    override func validate(_ command: UICommand) {
        super.validate(command)
        Probe.write("custom-validate", "validate action=\(NSStringFromSelector(command.action)) title=\"\(command.title)\" attributes=\(MenuDump.attributeNames(command.attributes))\n", append: true)
    }

    // MARK: - Standard edit actions (as FlutterTextInputView)

    override func cut(_ sender: Any?) {
        onEvent?("cut:")
        UIPasteboard.general.string = storage.substring(with: selection)
        replaceUnlogged(selection, with: "")
    }

    override func copy(_ sender: Any?) {
        onEvent?("copy:")
        UIPasteboard.general.string = storage.substring(with: selection)
    }

    override func paste(_ sender: Any?) {
        onEvent?("paste:")
        if let string = UIPasteboard.general.string {
            replaceUnlogged(selection, with: string)
        }
    }

    override func delete(_ sender: Any?) {
        onEvent?("delete:")
        replaceUnlogged(selection, with: "")
    }

    override func selectAll(_ sender: Any?) {
        onEvent?("selectAll:")
        setSelectionUnlogged(NSRange(location: 0, length: storage.length), notify: true)
    }

    // MARK: - ProbeExtraActions

    func handleLookUpAction() { onEvent?("handleLookUpAction") }
    func handleSearchWebAction() { onEvent?("handleSearchWebAction") }
    func handleShareAction() { onEvent?("handleShareAction") }
    func handleTranslateAction() { onEvent?("handleTranslateAction") }

    // MARK: - UITextInput edit menu hooks (iOS 16+). UITextInteraction calls
    // these when it presents a menu of its own (for example after a tap).

    func editMenu(for textRange: UITextRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        calls.log("editMenu(for: \(textRange)) suggestedActions.count=\(suggestedActions.count)")
        Probe.write("custom-textinput-editMenu", "=== editMenu(for: \(textRange)) [\(Probe.stamp())]\n" + MenuDump.describe(suggestedActions), append: true)
        onEvent?("UITextInput editMenu(for:) called by UIKit; returning nil (system menu)")
        return nil
    }

    func willPresentEditMenu(with animator: UIEditMenuInteractionAnimating) {
        calls.log("willPresentEditMenu(with:)")
        onEvent?("UITextInput willPresentEditMenu (UIKit's own menu)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            self.snapshot("UIKit's own menu shown")
            ViewSnapshot.displayedMenu("UIKit's own menu shown", appWindow: self.window)
        }
    }

    func willDismissEditMenu(with animator: UIEditMenuInteractionAnimating) {
        calls.log("willDismissEditMenu(with:)")
        onEvent?("UITextInput willDismissEditMenu (UIKit's own menu)")
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        if drawsOwnText {
            layout.draw(selection: selection)
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: TextLayout.height)
    }

    // MARK: - Unlogged helpers

    private var hasTextUnlogged: Bool { storage.length > 0 }

    private func replaceUnlogged(_ r: NSRange, with text: String) {
        inputDelegate?.textWillChange(self)
        storage.replaceCharacters(in: r, with: text)
        inputDelegate?.textDidChange(self)
        setSelectionUnlogged(NSRange(location: r.location + (text as NSString).length, length: 0), notify: false)
        accessibilityLabel = storage as String
    }

    private func setSelectionUnlogged(_ range: NSRange, notify: Bool) {
        if notify { inputDelegate?.selectionWillChange(self) }
        selection = range
        if notify { inputDelegate?.selectionDidChange(self) }
        setNeedsDisplay()
        onSelectionChange?(range)
    }

    private func clamp(_ index: Int) -> Int { max(0, min(index, storage.length)) }

    private func index(_ position: UITextPosition) -> Int {
        (position as? ProbeTextPosition)?.index ?? 0
    }

    private func nsRange(_ range: UITextRange) -> NSRange {
        (range as? ProbeTextRange)?.range ?? NSRange(location: 0, length: 0)
    }

    private func short(_ rect: CGRect) -> String {
        String(format: "{%.1f,%.1f,%.1f,%.1f}", rect.minX, rect.minY, rect.width, rect.height)
    }

    // MARK: - UIKeyInput

    var hasText: Bool {
        calls.log("hasText -> \(hasTextUnlogged)")
        return hasTextUnlogged
    }

    func insertText(_ text: String) {
        calls.log("insertText(\"\(text)\")")
        replaceUnlogged(selection, with: text)
    }

    func deleteBackward() {
        calls.log("deleteBackward")
        if selection.length > 0 {
            replaceUnlogged(selection, with: "")
        } else if selection.location > 0 {
            replaceUnlogged(NSRange(location: selection.location - 1, length: 1), with: "")
        }
    }

    // MARK: - UITextInput

    func text(in range: UITextRange) -> String? {
        let r = nsRange(range)
        let result: String? = NSMaxRange(r) <= storage.length ? storage.substring(with: r) : nil
        calls.log("text(in: \(NSStringFromRange(r))) -> \(result.map { "\"\($0)\"" } ?? "nil")")
        return result
    }

    func replace(_ range: UITextRange, withText text: String) {
        calls.log("replace(\(range), withText: \"\(text)\")")
        replaceUnlogged(nsRange(range), with: text)
    }

    var selectedTextRange: UITextRange? {
        get {
            calls.log("get selectedTextRange -> \(NSStringFromRange(selection))")
            return ProbeTextRange(selection)
        }
        set {
            calls.log("SET selectedTextRange = \(newValue.map { "\($0)" } ?? "nil") (was \(NSStringFromRange(selection)))")
            guard let newValue else { return }
            onEvent?("UIKit set selectedTextRange \(newValue)")
            // UIKit notifies the input delegate itself around this setter.
            setSelectionUnlogged(nsRange(newValue), notify: false)
        }
    }

    var markedTextRange: UITextRange? {
        calls.log("get markedTextRange -> \(marked.map { NSStringFromRange($0) } ?? "nil")")
        return marked.map { ProbeTextRange($0) }
    }

    func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        calls.log("setMarkedText(\"\(markedText ?? "")\", selectedRange: \(NSStringFromRange(selectedRange)))")
        let text = markedText ?? ""
        let target = marked ?? selection
        storage.replaceCharacters(in: target, with: text)
        marked = text.isEmpty ? nil : NSRange(location: target.location, length: (text as NSString).length)
        setSelectionUnlogged(NSRange(location: target.location + selectedRange.location, length: selectedRange.length), notify: false)
    }

    func unmarkText() {
        calls.log("unmarkText")
        marked = nil
    }

    var beginningOfDocument: UITextPosition {
        calls.log("beginningOfDocument")
        return ProbeTextPosition(0)
    }

    var endOfDocument: UITextPosition {
        calls.log("endOfDocument")
        return ProbeTextPosition(storage.length)
    }

    func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? {
        let a = index(fromPosition)
        let b = index(toPosition)
        calls.log("textRange(from: \(a), to: \(b))")
        return ProbeTextRange(NSRange(location: min(a, b), length: abs(a - b)))
    }

    func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
        let target = index(position) + offset
        calls.log("position(from: \(index(position)), offset: \(offset))")
        guard target >= 0, target <= storage.length else { return nil }
        return ProbeTextPosition(target)
    }

    func position(from position: UITextPosition, in direction: UITextLayoutDirection, offset: Int) -> UITextPosition? {
        calls.log("position(from: \(index(position)), in: \(direction.rawValue), offset: \(offset))")
        let target: Int
        switch direction {
        case .left: target = index(position) - offset
        case .right: target = index(position) + offset
        default: return nil
        }
        guard target >= 0, target <= storage.length else { return nil }
        return ProbeTextPosition(target)
    }

    func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult {
        let a = index(position)
        let b = index(other)
        calls.log("compare(\(a), to: \(b))")
        return a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
    }

    func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int {
        calls.log("offset(from: \(index(from)), to: \(index(toPosition)))")
        return index(toPosition) - index(from)
    }

    func position(within range: UITextRange, farthestIn direction: UITextLayoutDirection) -> UITextPosition? {
        calls.log("position(within: \(range), farthestIn: \(direction.rawValue))")
        let r = nsRange(range)
        switch direction {
        case .left, .up: return ProbeTextPosition(r.location)
        default: return ProbeTextPosition(NSMaxRange(r))
        }
    }

    func characterRange(byExtending position: UITextPosition, in direction: UITextLayoutDirection) -> UITextRange? {
        calls.log("characterRange(byExtending: \(index(position)), in: \(direction.rawValue))")
        let i = index(position)
        switch direction {
        case .left, .up: return ProbeTextRange(NSRange(location: 0, length: i))
        default: return ProbeTextRange(NSRange(location: i, length: storage.length - i))
        }
    }

    func baseWritingDirection(for position: UITextPosition, in direction: UITextStorageDirection) -> NSWritingDirection {
        calls.log("baseWritingDirection")
        return .leftToRight
    }

    func setBaseWritingDirection(_ writingDirection: NSWritingDirection, for range: UITextRange) {
        calls.log("setBaseWritingDirection")
    }

    func firstRect(for range: UITextRange) -> CGRect {
        let rect = layout.rect(nsRange(range))
        calls.log("firstRect(for: \(range)) -> \(short(rect))")
        return rect
    }

    func caretRect(for position: UITextPosition) -> CGRect {
        let rect = layout.caret(index(position))
        calls.log("caretRect(for: \(index(position))) -> \(short(rect))")
        return rect
    }

    func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        let rect = layout.rect(nsRange(range))
        calls.log("selectionRects(for: \(range)) -> \(short(rect))")
        return [ProbeSelectionRect(rect: rect, containsStart: true, containsEnd: true)]
    }

    func closestPosition(to point: CGPoint) -> UITextPosition? {
        let i = layout.closestIndex(point)
        calls.log(String(format: "closestPosition(to: %.1f,%.1f) -> %d", point.x, point.y, i))
        return ProbeTextPosition(i)
    }

    func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? {
        let r = nsRange(range)
        let i = layout.closestIndex(point)
        calls.log(String(format: "closestPosition(to: %.1f,%.1f, within: %@)", point.x, point.y, NSStringFromRange(r)))
        return ProbeTextPosition(max(r.location, min(i, NSMaxRange(r))))
    }

    func characterRange(at point: CGPoint) -> UITextRange? {
        calls.log(String(format: "characterRange(at: %.1f,%.1f)", point.x, point.y))
        let i = clamp(layout.closestIndex(point))
        return ProbeTextRange(NSRange(location: min(i, max(storage.length - 1, 0)), length: storage.length > 0 ? 1 : 0))
    }
}

/// The custom view placed and hidden the way the engine places
/// FlutterTextInputView on an iPhone (iOS 17+, no autofill, not secure):
/// a zero-sized frame (`clearTextInputClient`, `setIsVisibleToAutofill:NO`)
/// inside a zero-sized accessibility hider placed at the editable's origin
/// (`setEditableSizeAndTransform:`), not hidden, alpha 1, hidden from
/// accessibility, drawing nothing. The text is drawn by `RenderedTextView`.
final class FlutterLikeTextInputView: ProbeTextInputView {
    override init(text: String, selectedRange: NSRange) {
        super.init(text: text, selectedRange: selectedRange)
        backgroundColor = nil
        isOpaque = false
        drawsOwnText = false
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// FlutterTextInputView.accessibilityElementsHidden returns
    /// !accessibilityEnabled, which is NO only while VoiceOver uses the field.
    override var accessibilityElementsHidden: Bool {
        get { true }
        set {}
    }

    // Copied from the engine, which ships these three: "Prevent UIKit from
    // showing selection handles or highlights. [...] These are undocumented
    // methods." On iOS 17+ the engine answers NO to respondsToSelector for the
    // first one. They only affect drawing, not the menu.
    @objc var insertionPointColor: UIColor { .clear }
    @objc var selectionBarColor: UIColor { .clear }
    @objc var selectionHighlightColor: UIColor { .clear }

    override func responds(to aSelector: Selector!) -> Bool {
        if #available(iOS 17.0, *), aSelector == #selector(getter: insertionPointColor) {
            return false
        }
        return super.responds(to: aSelector)
    }
}

/// FlutterTextInputViewAccessibilityHider: hides its subviews from
/// accessibility.
final class AccessibilityHiderView: UIView {
    override var accessibilityElementsHidden: Bool {
        get { true }
        set {}
    }
}

/// Stands in for Flutter's own rendering of the text field: draws the text
/// and the selection highlight from the input view's state. It has no
/// gestures; touches on it are only logged (by ProbeApplication).
final class RenderedTextView: UIView {
    var text: NSString = ""
    var selection = NSRange(location: 0, length: 0) {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        isAccessibilityElement = true
        accessibilityIdentifier = "renderedText"
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ rect: CGRect) {
        TextLayout(text: text, size: bounds.size).draw(selection: selection)
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: TextLayout.height)
    }
}
