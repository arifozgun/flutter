import UIKit

/// The autocorrect harness screen (`-acVariant <id>`). It runs one variant as
/// a timed script and talks to the UI test through two labels:
///
/// - `acPhase` ("phase=<name> seq=<n>"): `type` asks the test to type "abc"
///   on the software keyboard, `tapEnd` / `tapStart` ask for a real tap at the
///   end / near the start of the field (points in `acTapPoints`), `menuShown`
///   is a hint for a screenshot, `done` means the result is ready.
/// - `acResult`: the result, `key=value | ...`.
///
/// Every other step is done by the app on a timer, so its timing is exact and
/// no touch is involved unless the variant asks for one. Records (prefix
/// `ac-<id>`): `-steps.txt` (text, selection, input delegate, interactions and
/// gesture recognizers at each step), `-edits.txt` (every keyboard edit with
/// the step it happened in), `-textinput-calls.txt`, `-events.txt`,
/// `-views.txt`, `-menus.txt`, `-result.txt`.
final class AutocorrectViewController: UIViewController, UITextViewDelegate, UITextFieldDelegate {
    static let sampleText = "The quiet harbor sailed away"
    static let harborRange = NSRange(location: 10, length: 6)
    static let finalSelection = NSRange(location: 3, length: 0)
    static var endSelection: NSRange { NSRange(location: (sampleText as NSString).length, length: 0) }

    private let variant: ACVariant
    private var input: ACInputView?
    private var rendered: ACRenderedView?
    private var hider: AccessibilityHiderView?
    private var textView: ACTextView?
    private var textField: ACTextField?
    private var content: UIView!

    private let phaseLabel = UILabel()
    private let statusLabel = UILabel()
    private let tapPointsLabel = UILabel()
    private let resultLabel = UILabel()

    private var phaseSeq = 0
    private var stage = "launch"
    private var changePrefix: String?
    private var notes: [String] = []
    private var edits: [(stage: String, line: String)] = []
    private var delegateAt: [String: String] = [:]
    private var values: [String: String] = [:]

    private var typingActive = false
    private var typingBase = 0
    private var typingLabel = ""
    private var typingToken = 0
    private var typingFirstKeySeen = false
    private var typingContinuation: (() -> Void)?

    private var pendingTap: (() -> Void)?
    private var pendingTapSeq = 0
    private var cycleMenus = Set<Int>()
    private var dismissedMenus = Set<Int>()
    private var pendingDismiss: [Int: () -> Void] = [:]
    private var secondMenuShown = false
    private var finished = false

    init(variant: ACVariant) {
        self.variant = variant
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Layout

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let title = makeLabel("ac-\(variant.id) [\(variant.question)]", identifier: "acTitle", size: 14, weight: .semibold)
        let what = makeLabel(variant.what, identifier: "acWhat", size: 11)
        what.numberOfLines = 0
        what.textColor = .secondaryLabel
        configure(phaseLabel, identifier: "acPhase", size: 12)
        configure(statusLabel, identifier: "acStatus", size: 10)
        configure(tapPointsLabel, identifier: "acTapPoints", size: 9)
        configure(resultLabel, identifier: "acResult", size: 8)
        resultLabel.numberOfLines = 3
        phaseLabel.text = "phase=start seq=0"
        statusLabel.text = "status: launch"
        tapPointsLabel.text = "tapPoints: unknown"
        resultLabel.text = "result: pending"

        switch variant.host {
        case .textView:
            let textView = ACTextView()
            textView.text = Self.sampleText
            textView.font = TextLayout.font
            textView.isScrollEnabled = false
            textView.backgroundColor = .secondarySystemBackground
            textView.autocorrectionType = .default
            textView.inlinePredictionType = variant.inlinePrediction
            textView.delegate = self
            textView.accessibilityIdentifier = "acNative"
            textView.onEdit = { [weak self] in self?.recordEdit($0) }
            self.textView = textView
            content = textView
        case .textField:
            let textField = ACTextField()
            textField.text = Self.sampleText
            textField.font = TextLayout.font
            textField.borderStyle = .roundedRect
            textField.autocorrectionType = .default
            textField.inlinePredictionType = variant.inlinePrediction
            textField.delegate = self
            textField.accessibilityIdentifier = "acNative"
            textField.addTarget(self, action: #selector(textFieldChanged), for: .editingChanged)
            textField.onEdit = { [weak self] in self?.recordEdit($0) }
            self.textField = textField
            content = textField
        case .custom:
            let input = ACInputView(text: Self.sampleText, selectedRange: Self.endSelection)
            input.delegateHandling = variant.delegateHandling
            input.engineWorkaround = variant.engineWorkaround
            input.interactionGesturesAllowed = variant.interactionGesturesAllowed
            input.inlinePredictionType = variant.inlinePrediction
            input.onEdit = { [weak self] description in
                self?.recordEdit(description)
                self?.typingEdit()
            }
            input.onEvent = { Probe.event($0) }
            input.onWillPresent = { [weak self] number in self?.menuWillPresent(number) }
            input.onWillDismiss = { [weak self] number in self?.menuWillDismiss(number) }
            input.onDismissCompleted = { [weak self] number in self?.menuDismissCompleted(number) }
            input.stageHook = { [weak self] name in
                guard let self, let prefix = self.changePrefix else { return }
                self.stage = "\(prefix):\(name)"
            }
            self.input = input
            switch variant.layout {
            case .normal:
                input.drawsOwnText = true
                input.backgroundColor = .secondarySystemBackground
                content = input
            case .flutterLike, .oneByOne:
                let rendered = ACRenderedView()
                rendered.update(text: input.text, selection: input.currentSelection)
                input.onChange = { [weak input, weak rendered] in
                    guard let input else { return }
                    rendered?.update(text: input.text, selection: input.currentSelection)
                }
                let hider = AccessibilityHiderView(frame: .zero)
                hider.addSubview(input)
                self.rendered = rendered
                self.hider = hider
                content = rendered
            }
        }
        content.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [title, what, phaseLabel, statusLabel, tapPointsLabel])
        stack.axis = .vertical
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        view.addSubview(content)
        view.addSubview(resultLabel)
        if let hider {
            view.addSubview(hider)
        }
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: guide.topAnchor, constant: 170),
            content.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            content.heightAnchor.constraint(equalToConstant: TextLayout.height + 8),
            resultLabel.topAnchor.constraint(equalTo: content.bottomAnchor, constant: 6),
            resultLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            resultLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
        ])

        // Every ended touch in the app (ProbeApplication) fulfils a pending
        // tap request.
        Probe.touchEnded = { [weak self] in self?.touchEnded() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let rendered, let hider, let input {
            // setEditableSizeAndTransform: the hider at the field's origin with
            // a zero size, the input view CGRectZero (or 1x1).
            hider.frame = CGRect(origin: rendered.frame.origin, size: .zero)
            input.frame = variant.layout == .oneByOne ? CGRect(x: 0, y: 0, width: 1, height: 1) : .zero
            input.layoutSize = rendered.bounds.size
        }
        publishTapPoints()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Probe.event("viewDidAppear variant=\(variant.id) host=\(variant.host.rawValue) layout=\(variant.layout.rawValue)")
        let became: Bool
        if let input {
            became = input.becomeFirstResponder()
        } else if let textView {
            became = textView.becomeFirstResponder()
            textView.selectedRange = Self.endSelection
        } else if let textField {
            became = textField.becomeFirstResponder()
            let end = textField.endOfDocument
            textField.selectedTextRange = textField.textRange(from: end, to: end)
        } else {
            became = false
        }
        note("becomeFirstResponder=\(became)")
        after(1.0) { [self] in
            step("start")
            delegateAt["start"] = delegateText
            runHistory { [self] in
                runCycle(0) { [self] in
                    runSecondMenu { [self] in
                        runSecondTap { [self] in
                            beginTyping("main") { [self] in finalChange() }
                        }
                    }
                }
            }
        }
    }

    private func publishTapPoints() {
        let layout = TextLayout(text: Self.sampleText as NSString, size: content.bounds.size)
        var startX = content.frame.minX + layout.x(3) - 3
        if let textView, let position = textView.position(from: textView.beginningOfDocument, offset: 3) {
            startX = textView.convert(textView.caretRect(for: position), to: view).midX - 3
        } else if let textField, let position = textField.position(from: textField.beginningOfDocument, offset: 3) {
            startX = textField.convert(textField.caretRect(for: position), to: view).midX - 3
        }
        let frame = content.convert(content.bounds, to: nil)
        let start = CGPoint(x: frame.minX + (startX - content.frame.minX), y: frame.midY)
        let end = CGPoint(x: frame.maxX - 20, y: frame.midY)
        tapPointsLabel.text = String(format: "tapPoints: start=%.1f,%.1f end=%.1f,%.1f", start.x, start.y, end.x, end.y)
    }

    // MARK: - Script helpers

    private func after(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            MainActor.assumeIsolated { body() }
        }
    }

    private func setPhase(_ name: String) {
        phaseSeq += 1
        phaseLabel.text = "phase=\(name) seq=\(phaseSeq)"
        Probe.event("phase \(name) seq=\(phaseSeq) stage=\(stage)")
    }

    private func note(_ text: String) {
        notes.append(text)
        Probe.event("note: \(text)")
        statusLabel.text = "status: " + text
    }

    private var focusView: UIView? { input ?? textView ?? textField }

    private var currentText: String { input?.text ?? textView?.text ?? textField?.text ?? "" }

    private var currentSelection: String {
        if let input { return NSStringFromRange(input.currentSelection) }
        if let textView { return NSStringFromRange(textView.selectedRange) }
        if let textField { return textField.selectionText }
        return "?"
    }

    private var delegateText: String {
        if let input { return input.inputDelegateText }
        if let textView { return ACInputView.describe(textView.inputDelegate) }
        if let textField { return ACInputView.describe(textField.inputDelegate) }
        return "?"
    }

    private func step(_ name: String) {
        let focus = focusView
        let interactions = focus?.interactions ?? []
        let recognizers = focus?.gestureRecognizers ?? []
        let marked = input?.markedRange.map { NSStringFromRange($0) } ?? "-"
        let line = "[\(Probe.stamp())] \(name) | stage=\(stage) text=\"\(currentText)\" sel=\(currentSelection) marked=\(marked)"
            + " inputDelegate=\(delegateText) firstResponder=\(focus?.isFirstResponder ?? false)"
            + " menuInteractionAttached=\(input?.hasMenuInteraction ?? false)"
            + " interactions=\(interactions.count) [\(interactions.map { NSStringFromClass(type(of: $0)) }.joined(separator: ","))]"
            + " gestureRecognizers=\(recognizers.count)"
        Probe.write("steps", line + "\n", append: true)
        statusLabel.text = "status: " + name
    }

    private func recordEdit(_ description: String) {
        let line = "[\(Probe.stamp())] stage=\(stage) \(description)"
        edits.append((stage, line))
        Probe.write("edits", line + "\n", append: true)
    }

    /// Moves the selection the way the engine does (custom host only).
    private func changeSelection(_ range: NSRange, prefix: String, announce: Bool = true) {
        guard let input else { return }
        changePrefix = prefix
        stage = prefix
        input.engineSetState(selection: range, announce: announce)
        changePrefix = nil
        stage = "\(prefix):after"
        step("\(prefix) -> \(NSStringFromRange(range)) announce=\(announce)")
    }

    // MARK: - Taps

    private func requestTap(_ kind: String, _ body: @escaping () -> Void) {
        pendingTap = body
        setPhase(kind)
        let seq = phaseSeq
        pendingTapSeq = seq
        after(8.0) { [self] in
            guard pendingTapSeq == seq, let tap = pendingTap else { return }
            pendingTap = nil
            note("\(kind): no tap within 8 s; continued without it")
            tap()
        }
    }

    private func touchEnded() {
        guard let tap = pendingTap else { return }
        pendingTap = nil
        Probe.event("tap received for phase seq=\(pendingTapSeq)")
        tap()
    }

    // MARK: - Typing

    /// Asks the test to type; calls `then` 3.5 s after the last keyboard
    /// edit once at least three characters were added.
    private func beginTyping(_ label: String, then: @escaping () -> Void) {
        stage = "\(label):ready"
        step("\(label): ready to type")
        after(2.0) { [self] in
            typingLabel = label
            typingBase = (currentText as NSString).length
            typingFirstKeySeen = false
            typingContinuation = then
            typingActive = true
            stage = "\(label):typing"
            setPhase("type")
            typingToken += 1
            let token = typingToken
            after(25.0) { [self] in
                guard typingActive, typingToken == token else { return }
                note("\(label): fewer than 3 characters typed within 25 s")
                endTyping()
            }
        }
    }

    private func typingEdit() {
        guard typingActive else { return }
        let length = (currentText as NSString).length
        if !typingFirstKeySeen, length > typingBase {
            typingFirstKeySeen = true
            if variant.secondMenu == .hiddenAtFirstKey, secondMenuShown, let input {
                // As the framework: the text update arrives, then it hides
                // the menu.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { input.dismissEditMenu() }
                }
                secondMenuShown = false
                note("second menu hidden at the first key")
            }
        }
        guard length >= typingBase + 3 else { return }
        typingToken += 1
        let token = typingToken
        after(3.5) { [self] in
            guard typingActive, typingToken == token else { return }
            endTyping()
        }
    }

    private func endTyping() {
        typingActive = false
        let label = typingLabel
        values["\(label)TextAfterTyping"] = "\"\(currentText)\""
        values["\(label)SelAfterTyping"] = currentSelection
        step("\(label): typed")
        let continuation = typingContinuation
        typingContinuation = nil
        continuation?()
    }

    // MARK: - History (f10, f11)

    private func runHistory(then: @escaping () -> Void) {
        guard variant.history != .none, let input else {
            then()
            return
        }
        beginTyping("history") { [self] in
            changeSelection(Self.finalSelection, prefix: "history:change")
            values["historyTextAfterChange"] = "\"\(currentText)\""
            after(2.0) { [self] in
                values["historyTextLate"] = "\"\(currentText)\""
                values["historyCommitted"] = String(values["historyTextLate"] != values["historyTextAfterTyping"])
                stage = "history:restore"
                input.engineSetState(text: Self.sampleText, selection: Self.endSelection)
                step("history: text restored")
                if variant.history == .earlierSession {
                    _ = input.resignFirstResponder()
                    step("history: resigned")
                    after(1.0) { [self] in
                        _ = input.becomeFirstResponder()
                        step("history: became first responder again")
                        after(1.5, then)
                    }
                } else {
                    after(1.0, then)
                }
            }
        }
    }

    // MARK: - Menu cycles

    private func runCycle(_ index: Int, then: @escaping () -> Void) {
        guard index < variant.cycles, let input else {
            then()
            return
        }
        let n = index + 1
        if variant.attachesInteraction, input.menuInteraction == nil || variant.newInteractionEachCycle {
            input.menuInteraction = input.makeMenuInteraction(mode: variant.interactionMode)
        }
        changeSelection(Self.harborRange, prefix: "cycle\(n):select")
        after(0.4) { [self] in
            stage = "cycle\(n):menu"
            if variant.attachesInteraction {
                input.attachMenuInteraction("cycle \(n), before the menu")
                step("cycle\(n): attached")
                delegateAt["afterAttach"] = delegateText
            }
            if variant.showsMenu {
                input.menuRequest = MenuBuilders.requestAll
                cycleMenus.insert(input.presentationCount + 1)
                input.presentEditMenu()
            }
            after(2.0) { [self] in
                if variant.dismissByTap {
                    requestTap("tapEnd") { [self] in endMenu(n, then: then) }
                } else {
                    endMenu(n, then: then)
                }
            }
        }
    }

    private func endMenu(_ n: Int, then: @escaping () -> Void) {
        guard let input else { return }
        stage = "cycle\(n):dismiss"
        if !variant.moveToEndAfterRemoval {
            changeSelection(Self.endSelection, prefix: "cycle\(n):toEnd")
        }
        let finish: () -> Void = { [self] in
            afterRemoval(n)
            let next: () -> Void = { [self] in after(1.0) { [self] in runCycle(n, then: then) } }
            if variant.moveToEndAfterRemoval {
                after(1.0) { [self] in
                    changeSelection(Self.endSelection, prefix: "cycle\(n):toEndAfterRemoval")
                    next()
                }
            } else {
                next()
            }
        }
        guard variant.showsMenu else {
            // No menu: the removal comes when a dismiss animation would end.
            after(0.5) { [self] in
                if variant.removal != .never { remove("cycle \(n), 0.5 s after the selection moved (no menu)") }
                finish()
            }
            return
        }
        let number = input.presentationCount
        waitForDismissal(number) { [self] in
            switch variant.removal {
            case .willDismiss, .never:
                finish()
            case .completion:
                remove("cycle \(n), dismiss animation completed")
                finish()
            case .completionPlus2s:
                after(2.0) { [self] in
                    remove("cycle \(n), 2 s after the dismiss animation")
                    finish()
                }
            }
        }
        input.dismissEditMenu()
    }

    private func remove(_ reason: String) {
        guard let input, input.hasMenuInteraction else { return }
        stage = "remove"
        input.detachMenuInteraction(reason)
        step("removed: \(reason)")
        delegateAt["afterRemoval"] = delegateText
    }

    private func afterRemoval(_ n: Int) {
        guard let input, variant.afterRemoval != .none else { return }
        stage = "cycle\(n):afterRemoval"
        switch variant.afterRemoval {
        case .none:
            break
        case .textInputNil:
            input.menuInteraction?.textInput = nil
        case .release:
            let object = input.menuInteraction
            input.menuInteraction = nil
            after(0.5) { [self, weak object] in note("interaction object released=\(object == nil)") }
        case .reloadInputViews:
            input.reloadInputViews()
        case .resignBecome:
            let resigned = input.resignFirstResponder()
            let became = input.becomeFirstResponder()
            note("resign=\(resigned) become=\(became)")
        case .selectionNudge:
            input.inputDelegate?.selectionWillChange(input)
            input.inputDelegate?.selectionDidChange(input)
        case .textNudge:
            input.inputDelegate?.textWillChange(input)
            input.inputDelegate?.textDidChange(input)
        }
        step("cycle\(n): after removal, \(variant.afterRemoval.rawValue)")
        delegateAt["afterRemovalAction"] = delegateText
    }

    private func waitForDismissal(_ number: Int, _ body: @escaping () -> Void) {
        if dismissedMenus.contains(number) {
            body()
            return
        }
        pendingDismiss[number] = body
        after(3.0) { [self] in
            guard let late = pendingDismiss.removeValue(forKey: number) else { return }
            note("menu #\(number): no dismiss completion within 3 s")
            late()
        }
    }

    private func menuWillPresent(_ number: Int) {
        Probe.event("menu #\(number) will present")
        step("menu #\(number) will present")
        setPhase("menuShown")
    }

    private func menuWillDismiss(_ number: Int) {
        Probe.event("menu #\(number) will dismiss")
        if cycleMenus.contains(number), variant.removal == .willDismiss {
            remove("menu #\(number) willDismiss")
        }
    }

    private func menuDismissCompleted(_ number: Int) {
        Probe.event("menu #\(number) dismiss animation completed")
        dismissedMenus.insert(number)
        if let body = pendingDismiss.removeValue(forKey: number) {
            body()
        }
    }

    // MARK: - Second menu, second tap (f12 to f14)

    private func runSecondMenu(then: @escaping () -> Void) {
        guard variant.secondMenu != .none, let input else {
            then()
            return
        }
        after(1.0) { [self] in
            stage = "secondMenu"
            input.menuRequest = [.edit("paste"), .edit("selectAll")]
            input.presentEditMenu()
            secondMenuShown = true
            let number = input.presentationCount
            if variant.secondMenu == .dismissedBeforeTyping {
                after(1.5) { [self] in
                    waitForDismissal(number) { [self] in
                        secondMenuShown = false
                        step("second menu dismissed")
                        then()
                    }
                    input.dismissEditMenu()
                }
            } else {
                after(1.0, then)
            }
        }
    }

    private func runSecondTap(then: @escaping () -> Void) {
        guard variant.secondTap else {
            then()
            return
        }
        requestTap("tapEnd") { [self] in
            changeSelection(Self.endSelection, prefix: "secondTap")
            after(1.0, then)
        }
    }

    // MARK: - Final change

    private func finalChange() {
        values["interactionsBeforeChange"] = String(focusView?.interactions.count ?? 0)
        values["gesturesBeforeChange"] = String(focusView?.gestureRecognizers?.count ?? 0)
        delegateAt["beforeChange"] = delegateText
        step("before the final change")
        ViewSnapshot.capture("before the final change", focus: focusView, inputDelegate: delegateText)
        switch variant.trigger {
        case .timer:
            performFinalChange(by: "timer")
        case .tap:
            stage = "final:awaitTap"
            requestTap("tapStart") { [self] in performFinalChange(by: "tap") }
        }
    }

    private func performFinalChange(by trigger: String) {
        values["trigger"] = trigger
        if input != nil {
            changeSelection(Self.finalSelection, prefix: "final", announce: variant.announcesFinalChange)
        } else if let textView {
            if trigger == "timer" {
                stage = "final:set"
                textView.selectedRange = Self.finalSelection
            }
            stage = "final:after"
            step("final change by \(trigger)")
        } else if let textField {
            if trigger == "timer" {
                stage = "final:set"
                if let position = textField.position(from: textField.beginningOfDocument, offset: Self.finalSelection.location) {
                    textField.selectedTextRange = textField.textRange(from: position, to: position)
                }
            }
            stage = "final:after"
            step("final change by \(trigger)")
        }
        values["textAfterChange"] = "\"\(currentText)\""
        after(0.3) { [self] in values["textAfter300ms"] = "\"\(currentText)\"" }
        after(2.0) { [self] in
            stage = "late"
            delegateAt["late"] = delegateText
            values["textLate"] = "\"\(currentText)\""
            values["selLate"] = currentSelection
            step("late (2 s after the change)")
            finish()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        let typed = values["mainTextAfterTyping"] ?? "?"
        let late = values["textLate"] ?? "?"
        let sync = values["textAfterChange"] ?? "?"
        let finalEdits = edits.filter { $0.stage.hasPrefix("final") || $0.stage == "late" }.map { "\($0.stage): \(trimmed($0.line))" }
        let typingEdits = edits.filter { $0.stage == "main:typing" }.map { trimmed($0.line) }
        var parts: [String] = [
            "q=\(variant.question)",
            "host=\(variant.host.rawValue)",
            "layout=\(variant.layout.rawValue)",
            "committed=\(typed == "?" ? "unknown" : String(late != typed))",
            "committedSync=\(typed == "?" ? "unknown" : String(sync != typed))",
            "trigger=\(values["trigger"] ?? "?")",
            "textAfterTyping=\(typed)",
            "selAfterTyping=\(values["mainSelAfterTyping"] ?? "?")",
            "textAfterChange=\(sync)",
            "textAfter300ms=\(values["textAfter300ms"] ?? "?")",
            "textLate=\(late)",
            "selLate=\(values["selLate"] ?? "?")",
            "finalEdits=[\(finalEdits.joined(separator: "; "))]",
            "typingEdits=[\(typingEdits.joined(separator: "; "))]",
            "delegateStart=\(delegateAt["start"] ?? "-")",
            "delegateAfterAttach=\(delegateAt["afterAttach"] ?? "-")",
            "delegateAfterRemoval=\(delegateAt["afterRemoval"] ?? "-")",
            "delegateBeforeChange=\(delegateAt["beforeChange"] ?? "-")",
            "delegateLate=\(delegateAt["late"] ?? "-")",
            "interactionsBeforeChange=\(values["interactionsBeforeChange"] ?? "?")",
            "gesturesBeforeChange=\(values["gesturesBeforeChange"] ?? "?")",
        ]
        if let input {
            let ignored = input.delegateAssignments.filter { $0.contains("IGNORED") }.count
            parts.append("delegateSets=\(input.delegateAssignments.count) ignored=\(ignored)")
            parts.append("menuInteractionAttachedAtEnd=\(input.hasMenuInteraction)")
            parts.append("traits[\(input.traitsText)]")
        } else if let textView {
            parts.append("traits[autocorrectionType=\(textView.autocorrectionType.rawValue) spellCheckingType=\(textView.spellCheckingType.rawValue) inlinePredictionType=\(textView.inlinePredictionType.rawValue)]")
        } else if let textField {
            parts.append("traits[autocorrectionType=\(textField.autocorrectionType.rawValue) spellCheckingType=\(textField.spellCheckingType.rawValue) inlinePredictionType=\(textField.inlinePredictionType.rawValue)]")
        }
        if variant.history != .none {
            parts.append("historyTextAfterTyping=\(values["historyTextAfterTyping"] ?? "?")")
            parts.append("historyTextAfterChange=\(values["historyTextAfterChange"] ?? "?")")
            parts.append("historyTextLate=\(values["historyTextLate"] ?? "?")")
            parts.append("historyCommitted=\(values["historyCommitted"] ?? "?")")
        }
        parts.append("notes=[\(notes.joined(separator: "; "))]")
        let result = parts.joined(separator: " | ")
        Probe.write("result", result + "\n")
        resultLabel.text = result
        resultLabel.accessibilityLabel = result
        setPhase("done")
    }

    /// An edit line without its timestamp and stage prefix, plus the time.
    private func trimmed(_ line: String) -> String {
        guard let close = line.firstIndex(of: "]") else { return line }
        let stamp = String(line[line.index(after: line.startIndex)..<close])
        var rest = String(line[line.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        if rest.hasPrefix("stage="), let space = rest.firstIndex(of: " ") {
            rest = String(rest[rest.index(after: space)...])
        }
        return "\(rest) @\(stamp)"
    }

    // MARK: - Native delegates

    func textViewDidChange(_ textView: UITextView) {
        recordEdit("textViewDidChange => \"\(textView.text ?? "")\" sel=\(NSStringFromRange(textView.selectedRange))")
        typingEdit()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        recordEdit("textViewDidChangeSelection => sel=\(NSStringFromRange(textView.selectedRange))")
    }

    @objc private func textFieldChanged() {
        guard let textField else { return }
        recordEdit("editingChanged => \"\(textField.text ?? "")\" sel=\(textField.selectionText)")
        typingEdit()
    }

    func textFieldDidChangeSelection(_ textField: UITextField) {
        recordEdit("textFieldDidChangeSelection => sel=\(self.textField?.selectionText ?? "?")")
    }

    // MARK: - Labels

    private func makeLabel(_ text: String, identifier: String, size: CGFloat, weight: UIFont.Weight = .regular) -> UILabel {
        let label = UILabel()
        label.text = text
        configure(label, identifier: identifier, size: size, weight: weight)
        return label
    }

    private func configure(_ label: UILabel, identifier: String, size: CGFloat, weight: UIFont.Weight = .regular) {
        label.font = .monospacedSystemFont(ofSize: size, weight: weight)
        label.accessibilityIdentifier = identifier
        label.translatesAutoresizingMaskIntoConstraints = false
    }
}
