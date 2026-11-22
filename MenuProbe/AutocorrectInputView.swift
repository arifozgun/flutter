import UIKit

/// The text input view of the autocorrect harness. A separate class from
/// ProbeTextInputView so the menu variants stay as they are. It copies what
/// FlutterTextInputView does where the keyboard can see it:
///
/// - keyboard edits (`insertText`, `deleteBackward`, `replace`, marked text)
///   change the text without calling `inputDelegate`, as the engine's do;
/// - `engineSetState` is `setTextInputState:`: `textWillChange` /
///   `selectionWillChange`, assign, `selectionDidChange` / `textDidChange`,
///   with the engine's workaround (a transient UITextInteraction when
///   `inputDelegate` is nil and the view is first responder);
/// - the traits have the engine's values (inline predictions off by default);
/// - positions move in every direction (left/up and backward go back), so
///   UITextInputStringTokenizer can find word boundaries.
///
/// Every UITextInput call is logged with a timestamp. Calls that change the
/// text or the selection are also reported through `onEdit` so the
/// controller can tag them with the step it is in.
class ACInputView: UIView, UITextInput, UIEditMenuInteractionDelegate, UITextInteractionDelegate {
    enum DelegateHandling: String {
        /// The engine change: assignments made while the edit menu's
        /// interaction is added or removed are ignored.
        case guarded
        /// Every assignment is accepted (UIKit replaces it on attach and
        /// clears it on removal).
        case unguarded
        /// Accepted, and after the removal the delegate from before the attach
        /// is put back when the slot is empty (an earlier engine attempt).
        case unguardedRestore
    }

    private var storage: NSMutableString
    private var selection: NSRange
    private var marked: NSRange?

    var delegateHandling: DelegateHandling = .guarded
    /// The engine's setTextInputState: workaround (flutter/engine#32881).
    var engineWorkaround = true
    var layoutSize: CGSize?
    var drawsOwnText = false
    /// Edit menu request for the next build.
    var menuRequest: [MenuBuilders.Request] = MenuBuilders.requestAll

    var onEdit: ((String) -> Void)?
    var onEvent: ((String) -> Void)?
    var onWillPresent: ((Int) -> Void)?
    var onWillDismiss: ((Int) -> Void)?
    var onDismissCompleted: ((Int) -> Void)?
    /// Called when the text or selection changed, for the rendered view.
    var onChange: (() -> Void)?

    let calls = CallLog(name: "textinput-calls")
    private(set) var editMenuInteraction: UIEditMenuInteraction!
    private(set) var presentationCount = 0
    private var traitAsks: [String: Int] = [:]

    /// The edit menu's interaction (nil before the first attach, or after a
    /// variant released it).
    var menuInteraction: UITextInteraction?
    /// What `addInteraction`/`removeInteraction` of the menu's interaction
    /// is doing right now ("attach", "remove"), nil otherwise.
    private var changingMenuInteraction: String?
    private weak var delegateBeforeMenu: UITextInputDelegate?
    private lazy var workaroundInteraction: UITextInteraction = {
        let interaction = UITextInteraction(for: .editable)
        interaction.textInput = self
        return interaction
    }()
    private var workaroundCreated = false
    /// For `interactionShouldBegin`: false refuses every gesture.
    var interactionGesturesAllowed = true

    private(set) var delegateAssignments: [String] = []

    init(text: String, selectedRange: NSRange) {
        storage = NSMutableString(string: text)
        selection = selectedRange
        super.init(frame: .zero)
        backgroundColor = nil
        isOpaque = false
        isAccessibilityElement = false
        accessibilityIdentifier = "acInput"
        let interaction = UIEditMenuInteraction(delegate: self)
        addInteraction(interaction)
        editMenuInteraction = interaction
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    var text: String { storage as String }
    var currentSelection: NSRange { selection }
    var markedRange: NSRange? { marked }

    private var layout: TextLayout {
        TextLayout(text: storage, size: layoutSize ?? bounds.size)
    }

    func rect(for range: NSRange) -> CGRect { layout.rect(range) }

    // MARK: - Input delegate

    private weak var storedInputDelegate: UITextInputDelegate?

    var inputDelegate: UITextInputDelegate? {
        get { storedInputDelegate }
        set {
            let during = changingMenuInteraction.map { "during menu interaction \($0)" } ?? "outside menu interaction"
            let ignored = changingMenuInteraction != nil && delegateHandling == .guarded
            let line = "set inputDelegate = \(ACInputView.describe(newValue)) (\(during)) \(ignored ? "IGNORED" : "accepted"); was \(ACInputView.describe(storedInputDelegate))"
            delegateAssignments.append("[\(Probe.stamp())] \(line)")
            calls.log(line)
            onEvent?(line)
            if ignored { return }
            storedInputDelegate = newValue
        }
    }

    static func describe(_ delegate: UITextInputDelegate?) -> String {
        guard let delegate else { return "nil" }
        let object = delegate as AnyObject
        return "\(NSStringFromClass(type(of: object)))@\(Unmanaged.passUnretained(object).toOpaque())"
    }

    var inputDelegateText: String { ACInputView.describe(storedInputDelegate) }

    // MARK: - Interactions

    var hasMenuInteraction: Bool {
        guard let menuInteraction else { return false }
        return interactions.contains { $0 === menuInteraction }
    }

    func makeMenuInteraction(mode: UITextInteractionMode) -> UITextInteraction {
        let interaction = UITextInteraction(for: mode)
        interaction.textInput = self
        interaction.delegate = self
        return interaction
    }

    func attachMenuInteraction(_ reason: String) {
        guard let menuInteraction, !hasMenuInteraction else { return }
        if delegateHandling == .unguardedRestore {
            delegateBeforeMenu = isFirstResponder ? storedInputDelegate : nil
        }
        calls.mark("attach menu interaction (\(reason)) inputDelegate before=\(inputDelegateText)")
        changingMenuInteraction = "attach"
        addInteraction(menuInteraction)
        changingMenuInteraction = nil
        let note = "menu interaction attached (\(reason)); inputDelegate=\(inputDelegateText)"
        calls.mark(note)
        onEvent?(note)
    }

    func detachMenuInteraction(_ reason: String) {
        guard let menuInteraction, hasMenuInteraction else { return }
        calls.mark("remove menu interaction (\(reason)) inputDelegate before=\(inputDelegateText)")
        changingMenuInteraction = "remove"
        removeInteraction(menuInteraction)
        changingMenuInteraction = nil
        if delegateHandling == .unguardedRestore {
            let saved = delegateBeforeMenu
            delegateBeforeMenu = nil
            if let saved, storedInputDelegate == nil, isFirstResponder {
                calls.mark("restore the delegate from before the attach")
                inputDelegate = saved
            }
        }
        let note = "menu interaction removed (\(reason)); inputDelegate=\(inputDelegateText)"
        calls.mark(note)
        onEvent?(note)
    }

    func interactionShouldBegin(_ interaction: UITextInteraction, at point: CGPoint) -> Bool {
        calls.log(String(format: "interactionShouldBegin at %.1f,%.1f -> %@", point.x, point.y, interactionGesturesAllowed ? "true" : "false"))
        return interactionGesturesAllowed
    }

    // MARK: - setTextInputState: (engine)

    /// Optional hook: called with "will", "assign", "did", "after" around the
    /// selection notifications, so the controller can tag what the keyboard
    /// does inside them.
    var stageHook: ((String) -> Void)?

    func engineSetState(text newText: String? = nil, selection newSelection: NSRange, announce: Bool = true) {
        if engineWorkaround, storedInputDelegate == nil, isFirstResponder {
            workaroundCreated = true
            calls.mark("workaround: inputDelegate nil, adding the transient interaction")
            addInteraction(workaroundInteraction)
        }
        let textChanged = newText.map { $0 != text } ?? false
        if textChanged, let newText {
            if announce { inputDelegate?.textWillChange(self) }
            storage.setString(newText)
            marked = nil
        }
        let clamped = NSRange(location: min(newSelection.location, storage.length), length: min(newSelection.length, max(storage.length - newSelection.location, 0)))
        if !NSEqualRanges(clamped, selection) {
            calls.mark("engineSetState selection \(NSStringFromRange(selection)) -> \(NSStringFromRange(clamped)) announce=\(announce) inputDelegate=\(inputDelegateText)")
            if announce {
                stageHook?("will")
                inputDelegate?.selectionWillChange(self)
            }
            stageHook?("assign")
            selection = clamped
            if announce {
                stageHook?("did")
                inputDelegate?.selectionDidChange(self)
            }
            stageHook?("after")
        } else {
            calls.mark("engineSetState selection unchanged \(NSStringFromRange(selection)); nothing announced")
        }
        if textChanged, announce {
            inputDelegate?.textDidChange(self)
        }
        if workaroundCreated, interactions.contains(where: { $0 === workaroundInteraction }) {
            removeInteraction(workaroundInteraction)
            calls.mark("workaround: transient interaction removed; inputDelegate=\(inputDelegateText)")
        }
        changed()
    }

    private func changed() {
        accessibilityValue = text
        setNeedsDisplay()
        onChange?()
    }

    // MARK: - Edit menu

    func presentEditMenu() {
        presentationCount += 1
        let configuration = UIEditMenuConfiguration(identifier: NSNumber(value: presentationCount), sourcePoint: .zero)
        onEvent?("presentEditMenu #\(presentationCount) hasMenuInteraction=\(hasMenuInteraction) isFirstResponder=\(isFirstResponder)")
        calls.mark("presentEditMenu #\(presentationCount)")
        editMenuInteraction.presentEditMenu(with: configuration)
    }

    func dismissEditMenu() {
        calls.mark("dismissMenu")
        editMenuInteraction.dismissMenu()
    }

    private static func number(_ configuration: UIEditMenuConfiguration) -> Int {
        (configuration.identifier as? NSNumber)?.intValue ?? -1
    }

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        menuFor configuration: UIEditMenuConfiguration,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        let menu = MenuBuilders.systemFiltered(suggestedActions, request: menuRequest)
        let header = "=== menu #\(ACInputView.number(configuration)) [\(Probe.stamp())] hasMenuInteraction=\(hasMenuInteraction) suggested=\(suggestedActions.count)\n"
        Probe.write("menus", header + MenuDump.describe([menu]), append: true)
        calls.mark("menuFor #\(ACInputView.number(configuration))")
        return menu
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, targetRectFor configuration: UIEditMenuConfiguration) -> CGRect {
        layout.rect(selection)
    }

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        willPresentMenuFor configuration: UIEditMenuConfiguration,
        animator: UIEditMenuInteractionAnimating
    ) {
        let number = ACInputView.number(configuration)
        calls.mark("willPresentMenu #\(number)")
        onWillPresent?(number)
    }

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        willDismissMenuFor configuration: UIEditMenuConfiguration,
        animator: UIEditMenuInteractionAnimating
    ) {
        let number = ACInputView.number(configuration)
        calls.mark("willDismissMenu #\(number)")
        onWillDismiss?(number)
        animator.addCompletion { [weak self] in
            self?.calls.mark("dismiss animation completed #\(number)")
            self?.onDismissCompleted?(number)
        }
    }

    // MARK: - Responder

    override var canBecomeFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        calls.mark("becomeFirstResponder -> \(result); inputDelegate=\(inputDelegateText)")
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        calls.mark("resignFirstResponder -> \(result); inputDelegate=\(inputDelegateText)")
        return result
    }

    override func reloadInputViews() {
        calls.mark("reloadInputViews (before) inputDelegate=\(inputDelegateText)")
        super.reloadInputViews()
        calls.mark("reloadInputViews (after) inputDelegate=\(inputDelegateText)")
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        // FlutterTextInputView's rules.
        switch action {
        case MenuBuilders.pasteSelector: return UIPasteboard.general.hasStrings
        case MenuBuilders.copySelector, MenuBuilders.cutSelector, MenuBuilders.deleteSelector: return selection.length > 0
        case MenuBuilders.selectAllSelector: return storage.length > 0
        default: return super.canPerformAction(action, withSender: sender)
        }
    }

    override func copy(_ sender: Any?) { onEvent?("copy:") }
    override func paste(_ sender: Any?) { onEvent?("paste: (ignored by the harness)") }
    override func selectAll(_ sender: Any?) { onEvent?("selectAll: (ignored by the harness)") }

    override func draw(_ rect: CGRect) {
        if drawsOwnText {
            layout.draw(selection: selection)
        }
    }

    // MARK: - UITextInputTraits (engine values; getters count UIKit's reads)

    private func asked(_ name: String) { traitAsks[name, default: 0] += 1 }

    var traitsText: String {
        "autocorrectionType=\(storedAutocorrection.rawValue) spellCheckingType=\(storedSpellChecking.rawValue) inlinePredictionType=\(storedInlinePrediction.rawValue)"
            + " asked[autocorrection=\(traitAsks["autocorrectionType"] ?? 0) spellChecking=\(traitAsks["spellCheckingType"] ?? 0) inlinePrediction=\(traitAsks["inlinePredictionType"] ?? 0)]"
    }

    private var storedAutocorrection: UITextAutocorrectionType = .default
    private var storedSpellChecking: UITextSpellCheckingType = .default
    private var storedInlinePrediction: UITextInlinePredictionType = .no

    var autocorrectionType: UITextAutocorrectionType {
        get { asked("autocorrectionType"); return storedAutocorrection }
        set { storedAutocorrection = newValue }
    }

    var spellCheckingType: UITextSpellCheckingType {
        get { asked("spellCheckingType"); return storedSpellChecking }
        set { storedSpellChecking = newValue }
    }

    var inlinePredictionType: UITextInlinePredictionType {
        get { asked("inlinePredictionType"); return storedInlinePrediction }
        set { storedInlinePrediction = newValue }
    }

    var autocapitalizationType: UITextAutocapitalizationType = .sentences
    var smartQuotesType: UITextSmartQuotesType = .yes
    var smartDashesType: UITextSmartDashesType = .yes
    var keyboardType: UIKeyboardType = .default
    var returnKeyType: UIReturnKeyType = .done
    var keyboardAppearance: UIKeyboardAppearance = .default
    var enablesReturnKeyAutomatically = false
    var isSecureTextEntry = false

    // MARK: - Helpers

    private func index(_ position: UITextPosition) -> Int {
        (position as? ProbeTextPosition)?.index ?? 0
    }

    private func nsRange(_ range: UITextRange) -> NSRange {
        (range as? ProbeTextRange)?.range ?? NSRange(location: 0, length: 0)
    }

    private func clampRange(_ r: NSRange) -> NSRange {
        let location = min(max(r.location, 0), storage.length)
        return NSRange(location: location, length: min(r.length, storage.length - location))
    }

    private func short(_ rect: CGRect) -> String {
        String(format: "{%.1f,%.1f,%.1f,%.1f}", rect.minX, rect.minY, rect.width, rect.height)
    }

    /// A keyboard edit: logged, reported, no inputDelegate call.
    private func keyboardEdit(_ description: String, _ body: () -> Void) {
        body()
        calls.log("\(description) => text=\"\(text)\" sel=\(NSStringFromRange(selection)) marked=\(marked.map { NSStringFromRange($0) } ?? "nil")")
        onEdit?("\(description) => \"\(text)\" sel=\(NSStringFromRange(selection))")
        changed()
    }

    private func replaceLocal(_ r: NSRange, with string: String) {
        let range = clampRange(r)
        storage.replaceCharacters(in: range, with: string)
        selection = NSRange(location: range.location + (string as NSString).length, length: 0)
        marked = nil
    }

    // MARK: - UIKeyInput

    var hasText: Bool {
        calls.log("hasText -> \(storage.length > 0)")
        return storage.length > 0
    }

    func insertText(_ string: String) {
        keyboardEdit("insertText(\"\(string)\")") {
            replaceLocal(marked ?? selection, with: string)
        }
    }

    func deleteBackward() {
        keyboardEdit("deleteBackward") {
            if selection.length > 0 {
                replaceLocal(selection, with: "")
            } else if selection.location > 0 {
                let range = storage.rangeOfComposedCharacterSequence(at: selection.location - 1)
                replaceLocal(range, with: "")
            }
        }
    }

    // MARK: - UITextInput

    func text(in range: UITextRange) -> String? {
        let r = nsRange(range)
        let result: String? = NSMaxRange(r) <= storage.length ? storage.substring(with: r) : nil
        calls.log("text(in: \(NSStringFromRange(r))) -> \(result.map { "\"\($0)\"" } ?? "nil")")
        return result
    }

    func replace(_ range: UITextRange, withText string: String) {
        keyboardEdit("replace(\(NSStringFromRange(nsRange(range))), withText: \"\(string)\")") {
            replaceLocal(nsRange(range), with: string)
        }
    }

    func shouldChangeText(in range: UITextRange, replacementText string: String) -> Bool {
        calls.log("shouldChangeText(in: \(NSStringFromRange(nsRange(range))), replacementText: \"\(string)\") -> true")
        return true
    }

    var selectedTextRange: UITextRange? {
        get {
            calls.log("get selectedTextRange -> \(NSStringFromRange(selection))")
            return ProbeTextRange(selection)
        }
        set {
            guard let newValue else {
                calls.log("SET selectedTextRange = nil (ignored)")
                return
            }
            keyboardEdit("SET selectedTextRange \(NSStringFromRange(nsRange(newValue))) (was \(NSStringFromRange(selection)))") {
                selection = clampRange(nsRange(newValue))
            }
        }
    }

    var markedTextRange: UITextRange? {
        calls.log("get markedTextRange -> \(marked.map { NSStringFromRange($0) } ?? "nil")")
        return marked.map { ProbeTextRange($0) }
    }

    var markedTextStyle: [NSAttributedString.Key: Any]?

    func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        keyboardEdit("setMarkedText(\"\(markedText ?? "")\", selectedRange: \(NSStringFromRange(selectedRange)))") {
            let string = markedText ?? ""
            let target = clampRange(marked ?? selection)
            storage.replaceCharacters(in: target, with: string)
            let length = (string as NSString).length
            marked = length > 0 ? NSRange(location: target.location, length: length) : nil
            selection = clampRange(NSRange(location: target.location + selectedRange.location, length: selectedRange.length))
        }
    }

    func setAttributedMarkedText(_ markedText: NSAttributedString?, selectedRange: NSRange) {
        calls.log("setAttributedMarkedText(\"\(markedText?.string ?? "")\") -> setMarkedText")
        setMarkedText(markedText?.string, selectedRange: selectedRange)
    }

    func unmarkText() {
        keyboardEdit("unmarkText") {
            marked = nil
        }
    }

    var beginningOfDocument: UITextPosition {
        calls.log("beginningOfDocument")
        return ProbeTextPosition(0)
    }

    var endOfDocument: UITextPosition {
        calls.log("endOfDocument -> \(storage.length)")
        return ProbeTextPosition(storage.length)
    }

    private lazy var stringTokenizer: UITextInputTokenizer = UITextInputStringTokenizer(textInput: self)

    var tokenizer: UITextInputTokenizer {
        calls.log("tokenizer")
        return stringTokenizer
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
        // UITextDirection values: storage forward 0 / backward 1, layout
        // right 2 / left 3 / up 4 / down 5. Single line: up = back, down = on.
        let backwards = [1, 3, 4].contains(direction.rawValue)
        let target = index(position) + (backwards ? -offset : offset)
        calls.log("position(from: \(index(position)), in: \(direction.rawValue), offset: \(offset))")
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
        return [1, 3, 4].contains(direction.rawValue) ? ProbeTextPosition(r.location) : ProbeTextPosition(NSMaxRange(r))
    }

    func characterRange(byExtending position: UITextPosition, in direction: UITextLayoutDirection) -> UITextRange? {
        calls.log("characterRange(byExtending: \(index(position)), in: \(direction.rawValue))")
        let i = index(position)
        if [1, 3, 4].contains(direction.rawValue) {
            return ProbeTextRange(NSRange(location: 0, length: i))
        }
        return ProbeTextRange(NSRange(location: i, length: storage.length - i))
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
        let i = min(layout.closestIndex(point), max(storage.length - 1, 0))
        return ProbeTextRange(NSRange(location: i, length: storage.length > 0 ? 1 : 0))
    }
}

/// Draws the input view's text, like Flutter's renderer. It has no gesture
/// recognizers; touches on it are logged by ProbeApplication.
final class ACRenderedView: UIView {
    var text: NSString = ""
    var selection = NSRange(location: 0, length: 0)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        isAccessibilityElement = true
        accessibilityIdentifier = "acRendered"
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func update(text: String, selection: NSRange) {
        self.text = text as NSString
        self.selection = selection
        accessibilityValue = text
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        TextLayout(text: text, size: bounds.size).draw(selection: selection)
    }
}

/// UITextView for the native reference: records the UITextInput calls that
/// reach it (the keyboard may also edit through UIKit's internal objects,
/// which this cannot see; text changes are recorded by the controller).
final class ACTextView: UITextView {
    var onEdit: ((String) -> Void)?

    override func insertText(_ text: String) {
        super.insertText(text)
        onEdit?("insertText(\"\(text)\") => \"\(self.text ?? "")\" sel=\(NSStringFromRange(selectedRange))")
    }

    override func deleteBackward() {
        super.deleteBackward()
        onEdit?("deleteBackward => \"\(text ?? "")\" sel=\(NSStringFromRange(selectedRange))")
    }

    override func replace(_ range: UITextRange, withText text: String) {
        super.replace(range, withText: text)
        onEdit?("replace(withText: \"\(text)\") => \"\(self.text ?? "")\" sel=\(NSStringFromRange(selectedRange))")
    }

    override func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        super.setMarkedText(markedText, selectedRange: selectedRange)
        onEdit?("setMarkedText(\"\(markedText ?? "")\") => \"\(text ?? "")\"")
    }

    override func unmarkText() {
        super.unmarkText()
        onEdit?("unmarkText => \"\(text ?? "")\"")
    }
}

/// UITextField for the native reference, recording like ACTextView.
final class ACTextField: UITextField {
    var onEdit: ((String) -> Void)?

    var selectionText: String {
        guard let range = selectedTextRange else { return "nil" }
        let start = offset(from: beginningOfDocument, to: range.start)
        let length = offset(from: range.start, to: range.end)
        return NSStringFromRange(NSRange(location: start, length: length))
    }

    override func insertText(_ text: String) {
        super.insertText(text)
        onEdit?("insertText(\"\(text)\") => \"\(self.text ?? "")\" sel=\(selectionText)")
    }

    override func deleteBackward() {
        super.deleteBackward()
        onEdit?("deleteBackward => \"\(text ?? "")\" sel=\(selectionText)")
    }

    override func replace(_ range: UITextRange, withText text: String) {
        super.replace(range, withText: text)
        onEdit?("replace(withText: \"\(text)\") => \"\(self.text ?? "")\" sel=\(selectionText)")
    }

    override func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        super.setMarkedText(markedText, selectedRange: selectedRange)
        onEdit?("setMarkedText(\"\(markedText ?? "")\") => \"\(text ?? "")\"")
    }

    override func unmarkText() {
        super.unmarkText()
        onEdit?("unmarkText => \"\(text ?? "")\"")
    }
}
