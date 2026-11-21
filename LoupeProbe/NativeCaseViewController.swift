import UIKit

/// A native UITextView or UITextField with a large font. The loupe comes from
/// the user's long-press drag (the UI test performs it); this class only sets
/// the field up, reports where the word is, and observes the gesture.
final class NativeCaseViewController: ProbeCaseViewController, UIGestureRecognizerDelegate {
    private var input: (UIView & UITextInput)!
    private var presses = 0
    private var pressChanges = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        let font = UIFont.systemFont(ofSize: probeCase.fontSize)
        let host: UIView & UITextInput
        var heightConstraint: NSLayoutConstraint?

        switch probeCase.kind {
        case .textField:
            let field = UITextField()
            field.font = font
            field.text = ProbeCase.word
            field.borderStyle = .roundedRect
            field.autocorrectionType = .no
            field.spellCheckingType = .no
            host = field
        default:
            let textView = UITextView()
            textView.font = font
            textView.text = ProbeCase.word
            textView.isEditable = true
            textView.isScrollEnabled = false
            textView.backgroundColor = .secondarySystemBackground
            textView.autocorrectionType = .no
            textView.spellCheckingType = .no
            let insets = textView.textContainerInset
            heightConstraint = textView.heightAnchor.constraint(
                equalToConstant: ceil(font.lineHeight) + insets.top + insets.bottom + 4
            )
            host = textView
        }
        input = host
        host.accessibilityIdentifier = "nativeInput"
        host.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: contentGuide.topAnchor),
            host.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor),
        ])
        heightConstraint?.isActive = true

        // Observes the user's long press without taking part in it.
        let press = UILongPressGestureRecognizer(target: self, action: #selector(pressed(_:)))
        press.minimumPressDuration = 0.25
        press.cancelsTouchesInView = false
        press.delaysTouchesBegan = false
        press.delaysTouchesEnded = false
        press.delegate = self
        host.addGestureRecognizer(press)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let became = input.becomeFirstResponder()
        placeCaretInWord()
        Probe.log("becomeFirstResponder=\(became)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.publishRects()
        }
        beginMonitoring(baselineAfter: 2.5)
    }

    override func baselineDidCapture() {
        publishRects()
        state = "ready"
        flush()
    }

    /// The caret goes between the two letters of the word.
    private func placeCaretInWord() {
        guard let position = input.position(from: input.beginningOfDocument, offset: 1) else { return }
        input.selectedTextRange = input.textRange(from: position, to: position)
    }

    private func publishRects() {
        placeCaretInWord()
        guard let selected = input.selectedTextRange,
              let whole = input.textRange(from: input.beginningOfDocument, to: input.endOfDocument)
        else { return }
        let caret = input.convert(input.caretRect(for: selected.start), to: nil)
        let word = input.convert(input.firstRect(for: whole), to: nil)
        wordRectLabel.text = String(format: "word: %.0f %.0f %.0f %.0f", word.minX, word.minY, word.width, word.height)
        result["caretRect"] = caret.probeArray
        result["caretHeight"] = (caret.height * 10).rounded() / 10
        result["wordRect"] = word.probeArray
        result["firstResponder"] = input.isFirstResponder
        Probe.log("caretRect=\(caret.probeText) wordRect=\(word.probeText) firstResponder=\(input.isFirstResponder)")
        flush()
    }

    // MARK: - Gesture observation

    @objc private func pressed(_ recognizer: UILongPressGestureRecognizer) {
        let location = recognizer.location(in: nil)
        switch recognizer.state {
        case .began:
            presses += 1
            state = "pressing"
            Probe.log("press began at \(Int(location.x)),\(Int(location.y))")
        case .changed:
            pressChanges += 1
        case .ended, .cancelled, .failed:
            state = "ready"
            Probe.log("press ended state=\(recognizer.state.rawValue) at \(Int(location.x)),\(Int(location.y)) changes=\(pressChanges)")
        default:
            break
        }
        result["gestureObserved"] = presses > 0
        result["presses"] = presses
        result["pressChanges"] = pressChanges
        flush()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
