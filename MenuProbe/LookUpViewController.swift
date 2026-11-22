import UIKit

/// The Look Up harness screen (`-luVariant <id>`). One text view, text field or
/// custom text input view holds the sample sentence and is first responder with
/// the keyboard up. The UI test taps Look Up in the edit menu, closes the Look
/// Up UI and reads the app's state through three labels:
///
/// - `luPhase` ("phase=<name> seq=<n>"): `ready` (first responder, keyboard up;
///   the native variants wait for the test to double tap the word) and, for
///   the custom variants, `menuRequested` (the app selected "harbor" and
///   presented the edit menu itself, as the engine does).
/// - `luState`: `firstResponder=<bool> selection=<loc,len> keyboard=<bool>
///   presented=<class|none> windows=<n>`, refreshed every 0.1 s. Every change is
///   also written, with a timestamp, to `<tag>-state.txt`.
/// - `luTapPoints`: `word=x,y`, the middle of "harbor" in window coordinates.
///
/// Records (prefix `lu-<id>`): `-state.txt`, `-responder.txt` (every
/// canBecomeFirstResponder, becomeFirstResponder and resignFirstResponder call
/// of the view under test, with a call stack for become and resign),
/// `-events.txt`, `-menus.txt`, `-textinput-calls.txt`.
final class LookUpViewController: UIViewController {
    private let variant: LUVariant
    private var input: LUInputView?
    private var rendered: ACRenderedView?
    private var hider: AccessibilityHiderView?
    private var textView: LUTextView?
    private var textField: LUTextField?
    private var content: UIView!

    private let phaseLabel = UILabel()
    private let stateLabel = UILabel()
    private let tapPointsLabel = UILabel()

    private var phaseSeq = 0
    private var keyboardShown = false
    private var lastState = ""
    private var stateTimer: Timer?

    // Variant 5: the removal waits for the responder to come back.
    private var menuPresented = false
    private var resignedSinceMenu = false
    private var restoredSinceMenu = false
    private var removalPending = false

    init(variant: LUVariant) {
        self.variant = variant
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Layout

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let title = makeLabel("lu-\(variant.id)", identifier: "luTitle", size: 14, weight: .semibold)
        let what = makeLabel(variant.what, identifier: "luWhat", size: 11)
        what.numberOfLines = 0
        what.textColor = .secondaryLabel
        configure(phaseLabel, identifier: "luPhase", size: 12)
        configure(stateLabel, identifier: "luState", size: 10)
        configure(tapPointsLabel, identifier: "luTapPoints", size: 9)
        phaseLabel.text = "phase=start seq=0"
        stateLabel.text = "state: pending"
        tapPointsLabel.text = "tapPoints: unknown"
        stateLabel.numberOfLines = 2

        switch variant.host {
        case .textView:
            let textView = LUTextView()
            textView.text = AutocorrectViewController.sampleText
            textView.font = TextLayout.font
            textView.isScrollEnabled = false
            textView.backgroundColor = .secondarySystemBackground
            textView.inlinePredictionType = .no
            textView.accessibilityIdentifier = "luNative"
            self.textView = textView
            content = textView
        case .textField:
            let textField = LUTextField()
            textField.text = AutocorrectViewController.sampleText
            textField.font = TextLayout.font
            textField.borderStyle = .roundedRect
            textField.inlinePredictionType = .no
            textField.accessibilityIdentifier = "luNative"
            self.textField = textField
            content = textField
        case .custom:
            let input = LUInputView(text: AutocorrectViewController.sampleText, selectedRange: AutocorrectViewController.endSelection)
            input.delegateHandling = variant.delegateHandling
            input.menuStyle = variant.menu
            input.returnKeyType = .default
            input.inlinePredictionType = .no
            input.onEvent = { Probe.event($0) }
            input.onWillDismiss = { number in Probe.event("menu #\(number) will dismiss") }
            input.onDismissCompleted = { [weak self] number in self?.menuDismissCompleted(number) }
            input.onResponder = { [weak self] kind, result in self?.responderChanged(kind, result) }
            input.onLookUpAction = { [weak self] in self?.presentReferenceLibrary() }
            self.input = input
            // The engine's layout: a zero-sized input view in a zero-sized
            // hider, another view draws the text.
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
        content.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [title, what, phaseLabel, stateLabel, tapPointsLabel])
        stack.axis = .vertical
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        view.addSubview(content)
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
        ])

        for name in [UIResponder.keyboardDidShowNotification, UIResponder.keyboardDidHideNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let shown = note.name == UIResponder.keyboardDidShowNotification
                MainActor.assumeIsolated { self?.keyboardShown = shown }
            }
        }
        stateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshState() }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let rendered, let hider, let input {
            // As the engine: the hider at the field's origin with a zero size,
            // the input view CGRectZero.
            hider.frame = CGRect(origin: rendered.frame.origin, size: .zero)
            input.frame = .zero
            input.layoutSize = rendered.bounds.size
        }
        publishTapPoints()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Probe.event("viewDidAppear variant=\(variant.id) host=\(variant.host.rawValue)")
        var became = false
        if let input {
            if variant.interaction == .permanent {
                input.menuInteraction = input.makeMenuInteraction(mode: .editable)
                input.attachMenuInteraction("permanent, before the view becomes first responder")
            }
            became = input.becomeFirstResponder()
        } else if let textView {
            became = textView.becomeFirstResponder()
            textView.selectedRange = AutocorrectViewController.endSelection
        } else if let textField {
            became = textField.becomeFirstResponder()
            let end = textField.endOfDocument
            textField.selectedTextRange = textField.textRange(from: end, to: end)
        }
        Probe.event("becomeFirstResponder=\(became)")
        after(1.5) { [self] in
            publishTapPoints()
            setPhase("ready")
            if input != nil {
                after(1.0) { [self] in runCustomMenu() }
            }
        }
    }

    // MARK: - Script

    private func after(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            MainActor.assumeIsolated { body() }
        }
    }

    private func setPhase(_ name: String) {
        phaseSeq += 1
        phaseLabel.text = "phase=\(name) seq=\(phaseSeq)"
        Probe.event("phase \(name) seq=\(phaseSeq)")
    }

    /// The custom variants: select "harbor" and present the edit menu the way
    /// the engine does (the interaction, when the variant has one around the
    /// menu, is attached right before).
    private func runCustomMenu() {
        guard let input else { return }
        input.engineSetState(selection: AutocorrectViewController.harborRange)
        after(0.4) { [self] in
            if variant.interaction == .aroundMenu || variant.interaction == .aroundMenuUntilRestored {
                if input.menuInteraction == nil {
                    input.menuInteraction = input.makeMenuInteraction(mode: .editable)
                }
                input.attachMenuInteraction("before presentEditMenu")
            }
            menuPresented = true
            input.presentEditMenu()
            setPhase("menuRequested")
        }
    }

    private func menuDismissCompleted(_ number: Int) {
        Probe.event("menu #\(number) dismiss animation completed")
        guard let input else { return }
        switch variant.interaction {
        case .aroundMenu:
            input.detachMenuInteraction("dismiss animation completed")
        case .aroundMenuUntilRestored:
            removalPending = true
            if restoredSinceMenu {
                removeWhenPending("the view had become first responder again")
            } else {
                after(10.0) { [self] in removeWhenPending("10 s after the dismiss animation completed") }
            }
        case .none, .permanent:
            break
        }
    }

    private func responderChanged(_ kind: String, _ result: Bool) {
        guard variant.interaction == .aroundMenuUntilRestored, menuPresented else { return }
        if kind == "resign" {
            resignedSinceMenu = true
        } else if result, resignedSinceMenu {
            restoredSinceMenu = true
            // Not inside UIKit's own becomeFirstResponder call.
            after(0.05) { [self] in removeWhenPending("the view became first responder again") }
        }
    }

    private func removeWhenPending(_ reason: String) {
        guard removalPending, let input else { return }
        removalPending = false
        input.detachMenuInteraction(reason)
    }

    /// The `.referenceLibrary` menu's action (the stock engine's way).
    private func presentReferenceLibrary() {
        let word = (AutocorrectViewController.sampleText as NSString).substring(with: AutocorrectViewController.harborRange)
        let has = UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: word)
        Probe.event("present UIReferenceLibraryViewController term=\(word) hasDefinition=\(has)")
        present(UIReferenceLibraryViewController(term: word), animated: true)
    }

    // MARK: - State for the test

    private var focusView: UIView? { input ?? textView ?? textField }

    private var selectionText: String {
        if let input {
            let range = input.currentSelection
            return "\(range.location),\(range.length)"
        }
        if let textView {
            let range = textView.selectedRange
            return "\(range.location),\(range.length)"
        }
        return textField?.selectionText ?? "?"
    }

    private func refreshState() {
        let presented = presentedViewController.map { NSStringFromClass(type(of: $0)) } ?? "none"
        let windows = view.window?.windowScene?.windows.count ?? 0
        let text = "firstResponder=\(focusView?.isFirstResponder ?? false) selection=\(selectionText) keyboard=\(keyboardShown) presented=\(presented) windows=\(windows)"
        guard text != lastState else { return }
        lastState = text
        stateLabel.text = text
        Probe.write("state", "[\(Probe.stamp())] \(text)\n", append: true)
    }

    /// The middle of "harbor" in window coordinates (the native variants; the
    /// test double taps there).
    private func publishTapPoints() {
        let target: (UITextInput & UIView)?
        if let textView {
            target = textView
        } else {
            target = textField
        }
        guard let target else { return }
        let range = AutocorrectViewController.harborRange
        guard let start = target.position(from: target.beginningOfDocument, offset: range.location),
              let end = target.position(from: target.beginningOfDocument, offset: NSMaxRange(range)) else { return }
        let a = target.caretRect(for: start)
        let b = target.caretRect(for: end)
        let point = target.convert(CGPoint(x: (a.minX + b.minX) / 2, y: a.midY), to: nil)
        tapPointsLabel.text = String(format: "tapPoints: word=%.1f,%.1f", point.x, point.y)
    }

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
