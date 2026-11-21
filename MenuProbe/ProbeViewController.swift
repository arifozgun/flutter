import UIKit

/// Shows one variant: a header the UI test reads, the text input with a
/// selected word, and a Present button that presents the custom view's edit
/// menu again.
final class ProbeViewController: UIViewController, UITextViewDelegate {
    static let sampleText = "The ship sailed into the harbor at dawn."
    static let selectedWord = "harbor"

    private let variant: Variant
    private var textView: ProbeTextView?
    private var customView: ProbeTextInputView?
    private let statusLabel = UILabel()
    private let selectionLabel = UILabel()
    private var textViewMenuBuilds = 0

    init(variant: Variant) {
        self.variant = variant
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private var selectedRange: NSRange {
        (Self.sampleText as NSString).range(of: Self.selectedWord)
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
        statusLabel.text = "status: idle"
        selectionLabel.text = "selection: unknown"

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
            textView.delegate = self
            textView.accessibilityIdentifier = "nativeTextView"
            textView.onEvent = { [weak self] in self?.event($0) }
            self.textView = textView
            content = textView
        case .custom:
            let custom = ProbeTextInputView(text: Self.sampleText, selectedRange: selectedRange)
            custom.menuProvider = variant.build
            custom.answersYesToEveryAction = variant.answersYesToEveryAction
            custom.onEvent = { [weak self] in self?.event($0) }
            if variant.attachesTextInteraction {
                let interaction = UITextInteraction(for: .editable)
                interaction.textInput = custom
                custom.addInteraction(interaction)
            }
            customView = custom
            content = custom
        }
        content.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [title, host, hypothesis, statusLabel, selectionLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        view.addSubview(present)
        view.addSubview(content)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: present.leadingAnchor, constant: -8),
            present.topAnchor.constraint(equalTo: guide.topAnchor, constant: 4),
            present.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: guide.topAnchor, constant: 230),
            content.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            content.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        event("viewDidAppear")
        if let textView {
            let became = textView.becomeFirstResponder()
            textView.selectedRange = selectedRange
            event("textView becomeFirstResponder=\(became) selectedRange=\(NSStringFromRange(textView.selectedRange))")
        }
        if let customView {
            let became = customView.becomeFirstResponder()
            event("custom becomeFirstResponder=\(became)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.updateSelectionLabel()
                customView.presentEditMenu()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.updateSelectionLabel()
        }
    }

    @objc private func presentTapped() {
        event("presentButton tapped")
        updateSelectionLabel()
        customView?.presentEditMenu()
    }

    /// Publishes the selection rect in window points so the UI test can tap
    /// the selected word of the UITextView.
    private func updateSelectionLabel() {
        var rect = CGRect.null
        if let textView, let range = textView.selectedTextRange {
            rect = textView.convert(textView.firstRect(for: range), to: nil)
        } else if let customView {
            rect = customView.convert(customView.selectionRect, to: nil)
        }
        guard !rect.isNull else { return }
        selectionLabel.text = String(format: "selection: %.1f %.1f %.1f %.1f", rect.minX, rect.minY, rect.width, rect.height)
        event("selection rect window=\(NSCoder.string(for: rect))")
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

    // MARK: - UITextViewDelegate (native reference variants)

    private func textViewMenu(source: String, ranges: String, suggestedActions: [UIMenuElement]) -> UIMenu? {
        textViewMenuBuilds += 1
        let header = "=== build #\(textViewMenuBuilds) via \(source) ranges=\(ranges) suggestedActions.count=\(suggestedActions.count)\n"
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
    }

    func textView(_ textView: UITextView, willDismissEditMenuWith animator: UIEditMenuInteractionAnimating) {
        event("textView willDismissEditMenu")
    }
}
