import UIKit

/// Shows one variant: a header the UI test reads, the text input with a
/// selected word, and a Present button that presents the custom view's edit
/// menu again.
final class ProbeViewController: UIViewController, UITextViewDelegate {
    static let sampleText = "The ship sailed into the harbor at dawn."
    static let selectedWord = "harbor"
    /// Words the gesture test taps, double-taps and long-presses.
    static let gestureWords = ["ship", "sailed", "into"]

    private let variant: Variant
    private var textView: ProbeTextView?
    private var customView: ProbeTextInputView?
    private var renderedView: RenderedTextView?
    private var hiderView: AccessibilityHiderView?
    private let statusLabel = UILabel()
    private let selectionLabel = UILabel()
    private let rangeLabel = UILabel()
    private let tapPointsLabel = UILabel()
    private var textViewMenuBuilds = 0
    private var touchSnapshots = 0
    private var displayTimer: Timer?
    private var lastDisplayed = ""
    private let vcActionLog = ActionLog(name: "vc-canPerformAction")
    private let vcTargetLog = ActionLog(name: "vc-targetForAction")

    init(variant: Variant) {
        self.variant = variant
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private var selectedRange: NSRange {
        (Self.sampleText as NSString).range(of: Self.selectedWord)
    }

    /// Launch argument `-noAutoPresent YES`: the custom view's menu is only
    /// shown by the Present button (the gesture test needs a menu-free start).
    private var autoPresents: Bool {
        !UserDefaults.standard.bool(forKey: "noAutoPresent")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let title = label(variant.tag, identifier: "variantTitle", font: .monospacedSystemFont(ofSize: 15, weight: .semibold))
        let host = label(variant.host.rawValue, identifier: "hostKind", font: .systemFont(ofSize: 12))
        let hypothesis = label(variant.hypothesis, identifier: "hypothesis", font: .systemFont(ofSize: 12))
        hypothesis.numberOfLines = 0
        hypothesis.textColor = .secondaryLabel
        configure(statusLabel, identifier: "status", font: .monospacedSystemFont(ofSize: 11, weight: .regular))
        configure(selectionLabel, identifier: "selectionRect", font: .monospacedSystemFont(ofSize: 11, weight: .regular))
        configure(rangeLabel, identifier: "selectionRange", font: .monospacedSystemFont(ofSize: 11, weight: .regular))
        configure(tapPointsLabel, identifier: "tapPoints", font: .monospacedSystemFont(ofSize: 9, weight: .regular))
        statusLabel.text = "status: idle"
        selectionLabel.text = "selection: unknown"
        rangeLabel.text = "range: unknown"
        tapPointsLabel.text = "tapPoints: unknown"

        let present = UIButton(type: .system)
        present.setTitle("Present", for: .normal)
        present.accessibilityIdentifier = "presentButton"
        present.addTarget(self, action: #selector(presentTapped), for: .touchUpInside)
        present.translatesAutoresizingMaskIntoConstraints = false

        let content: UIView
        switch variant.host {
        case .textView:
            let textView = ProbeTextView()
            textView.text = Self.sampleText
            textView.font = .systemFont(ofSize: 22)
            textView.isScrollEnabled = false
            textView.isEditable = true
            textView.backgroundColor = .secondarySystemBackground
            textView.delegate = variant.textViewDelegate ? self : nil
            textView.accessibilityIdentifier = "nativeTextView"
            textView.onEvent = { [weak self] in self?.event($0) }
            self.textView = textView
            content = textView
        case .custom:
            let custom: ProbeTextInputView
            switch variant.layout {
            case .normal:
                custom = ProbeTextInputView(text: Self.sampleText, selectedRange: selectedRange)
                content = custom
            case .flutterLike:
                custom = FlutterLikeTextInputView(text: Self.sampleText, selectedRange: selectedRange)
                let rendered = RenderedTextView()
                rendered.text = Self.sampleText as NSString
                rendered.selection = selectedRange
                renderedView = rendered
                let hider = AccessibilityHiderView(frame: .zero)
                hider.addSubview(custom)
                custom.frame = .zero
                hiderView = hider
                content = rendered
            }
            custom.menuProvider = variant.build
            custom.answersYesToEveryAction = variant.answersYesToEveryAction
            custom.interactionMode = variant.interactionMode
            custom.onEvent = { [weak self] in self?.event($0) }
            custom.onSelectionChange = { [weak self] range in self?.selectionChanged(range) }
            if variant.interactionMode == .always {
                custom.attachTextInteraction("view created, mode always")
            }
            customView = custom
        }
        content.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [title, host, hypothesis, statusLabel, selectionLabel, rangeLabel, tapPointsLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        view.addSubview(present)
        view.addSubview(content)
        if let hiderView {
            // Added after the visible content, as the engine adds its hider to
            // the Flutter view controller's view.
            view.addSubview(hiderView)
        }

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: present.leadingAnchor, constant: -8),
            present.topAnchor.constraint(equalTo: guide.topAnchor, constant: 4),
            present.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: guide.topAnchor, constant: 260),
            content.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            content.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
        ])

        // Touches are logged by ProbeApplication; in row and gesture runs each
        // touch also triggers a view snapshot shortly after it ends.
        if customView != nil, !Probe.runName.isEmpty {
            Probe.touchEnded = { [weak self] in self?.touchEnded() }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let renderedView, let hiderView, let customView {
            // setEditableSizeAndTransform on iOS 17+ iPhone: the hider sits at
            // the editable's origin with a zero size; the input view keeps
            // CGRectZero.
            hiderView.frame = CGRect(origin: renderedView.frame.origin, size: .zero)
            customView.frame = .zero
            customView.layoutSize = renderedView.bounds.size
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        event("viewDidAppear layout=\(variant.layout.rawValue) interactionMode=\(variant.interactionMode.rawValue) autoPresents=\(autoPresents)")
        if let textView {
            let became = textView.becomeFirstResponder()
            textView.selectedRange = selectedRange
            event("textView becomeFirstResponder=\(became) selectedRange=\(NSStringFromRange(textView.selectedRange))")
        }
        if let customView {
            let became = customView.becomeFirstResponder()
            event("custom becomeFirstResponder=\(became)")
            if autoPresents {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    self?.updateSelectionLabel()
                    customView.presentEditMenu()
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    customView.snapshot("initial (no menu)")
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.updateSelectionLabel()
            self?.publishTapPoints()
        }
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.recordDisplayedLabels() }
        }
    }

    @objc private func presentTapped() {
        event("presentButton tapped")
        updateSelectionLabel()
        customView?.presentEditMenu()
    }

    private func selectionChanged(_ range: NSRange) {
        renderedView?.selection = range
        rangeLabel.text = "range: \(NSStringFromRange(range))"
        updateSelectionLabel()
    }

    private func touchEnded() {
        touchSnapshots += 1
        let number = touchSnapshots
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            self?.customView?.snapshot("0.9 s after touch #\(number) ended")
        }
    }

    /// Publishes the selection rect in window points so the UI test can tap
    /// the selected word of the UITextView.
    private func updateSelectionLabel() {
        var rect = CGRect.null
        if let textView, let range = textView.selectedTextRange {
            rect = textView.convert(textView.firstRect(for: range), to: nil)
            rangeLabel.text = "range: \(NSStringFromRange(textView.selectedRange))"
        } else if let customView {
            rect = customView.convert(customView.selectionRect, to: nil)
            rangeLabel.text = "range: \(NSStringFromRange(customView.currentSelection))"
        }
        guard !rect.isNull else { return }
        selectionLabel.text = String(format: "selection: %.1f %.1f %.1f %.1f", rect.minX, rect.minY, rect.width, rect.height)
        event("selection rect window=\(NSCoder.string(for: rect))")
    }

    /// Window points of the centers of `gestureWords`, for the gesture test.
    private func publishTapPoints() {
        guard let customView else { return }
        let text = Self.sampleText as NSString
        let points = Self.gestureWords.map { word -> String in
            let rect = customView.convert(customView.rect(for: text.range(of: word)), to: nil)
            return String(format: "%.1f %.1f", rect.midX, rect.midY)
        }
        tapPointsLabel.text = "tapPoints: " + points.joined(separator: " ")
        event("tapPoints \(Self.gestureWords) = \(points)")
    }

    /// Every 0.7 s: the texts and images on screen outside this controller's
    /// own views (the edit menu and whatever a menu row opens), written to
    /// `<tag>-displayed.txt` whenever they change.
    private func recordDisplayedLabels() {
        guard let window = view.window else { return }
        var lines: [String] = []
        for candidate in window.windowScene?.windows ?? [] {
            collectForeign(candidate, into: &lines)
        }
        let signature = lines.joined(separator: "\n")
        guard signature != lastDisplayed else { return }
        lastDisplayed = signature
        Probe.write("displayed", "=== on screen [\(Probe.stamp())]\n" + (lines.isEmpty ? "(nothing outside the probe's views)" : signature) + "\n", append: true)
    }

    private func collectForeign(_ candidate: UIView, into lines: inout [String]) {
        if candidate === view || candidate.isHidden || candidate.alpha < 0.01 { return }
        if let label = candidate as? UILabel, let text = label.text, !text.isEmpty {
            lines.append("  label \"\(text)\"")
        } else if let imageView = candidate as? UIImageView, let image = imageView.image {
            lines.append("  image \(MenuDump.imageDescription(image))")
        }
        for subview in candidate.subviews {
            collectForeign(subview, into: &lines)
        }
    }

    private func event(_ message: String) {
        Probe.event(message)
        statusLabel.text = "status: " + message
    }

    private func label(_ text: String, identifier: String, font: UIFont) -> UILabel {
        let label = UILabel()
        label.text = text
        configure(label, identifier: identifier, font: font)
        return label
    }

    private func configure(_ label: UILabel, identifier: String, font: UIFont) {
        label.font = font
        label.accessibilityIdentifier = identifier
        label.translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: - Responder chain records

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        let answer = super.canPerformAction(action, withSender: sender)
        vcActionLog.record(action, answer: answer, defaultAnswer: answer, sender: sender)
        return answer
    }

    override func target(forAction action: Selector, withSender sender: Any?) -> Any? {
        let target = super.target(forAction: action, withSender: sender)
        vcTargetLog.record(action, detail: "target=\(target.map { String(describing: type(of: $0)) } ?? "nil") sender=\(ActionLog.senderText(sender))")
        return target
    }

    // MARK: - UITextViewDelegate (native reference variants)

    private func textViewMenu(source: String, ranges: String, suggestedActions: [UIMenuElement]) -> UIMenu? {
        textViewMenuBuilds += 1
        let header = "=== build #\(textViewMenuBuilds) [\(Probe.stamp())] via \(source) ranges=\(ranges) suggestedActions.count=\(suggestedActions.count)\n"
        Probe.write("textview-suggestedActions", header + MenuDump.describe(suggestedActions), append: true)
        let menu = variant.build(suggestedActions)
        Probe.write(
            "textview-returned",
            "=== build #\(textViewMenuBuilds)\n" + (menu.map { MenuDump.describe([$0]) } ?? "(nil: system default menu)\n"),
            append: true
        )
        textView?.flushActionLog()
        event("textView menu requested via \(source) (build #\(textViewMenuBuilds))")
        return menu
    }

    func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        textViewMenu(source: "editMenuForTextInRange", ranges: NSStringFromRange(range), suggestedActions: suggestedActions)
    }

    @available(iOS 26.0, *)
    func textView(_ textView: UITextView, editMenuForTextInRanges ranges: [NSValue], suggestedActions: [UIMenuElement]) -> UIMenu? {
        let text = ranges.map { NSStringFromRange($0.rangeValue) }.joined(separator: ",")
        return textViewMenu(source: "editMenuForTextInRanges", ranges: text, suggestedActions: suggestedActions)
    }

    func textView(_ textView: UITextView, willPresentEditMenuWith animator: UIEditMenuInteractionAnimating) {
        event("textView willPresentEditMenu")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, let textView = self.textView else { return }
            ViewSnapshot.capture("textView menu shown", focus: textView)
            ViewSnapshot.displayedMenu("textView menu shown", appWindow: textView.window)
            textView.flushActionLog()
        }
    }

    func textView(_ textView: UITextView, willDismissEditMenuWith animator: UIEditMenuInteractionAnimating) {
        event("textView willDismissEditMenu")
    }
}
