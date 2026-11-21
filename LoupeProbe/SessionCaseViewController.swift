import UIKit

/// Mirrors the Flutter engine's call: a plain view, a caret rect, and
/// `UITextLoupeSession.begin(at:fromSelectionWidgetView:in:)` with a
/// `UIStandardTextCursorView` framed as the caret (`session-widget`) or with
/// nil (`session-nil`). The session is held for two seconds and moved along the
/// word, then invalidated.
final class SessionCaseViewController: ProbeCaseViewController {
    private let canvas = UIView()
    private let wordLabel = UILabel()
    /// Drawn caret, so a screenshot shows where the loupe is aimed.
    private let caretBar = UIView()
    private var widget: UIView?
    private var session: UITextLoupeSession?
    private var caretRect = CGRect.zero
    private var moveTimer: Timer?
    private var moveStep = 0
    private let moveSteps = 20

    override func viewDidLoad() {
        super.viewDidLoad()
        let font = UIFont.systemFont(ofSize: probeCase.fontSize)
        canvas.backgroundColor = .secondarySystemBackground
        canvas.accessibilityIdentifier = "sessionCanvas"
        canvas.translatesAutoresizingMaskIntoConstraints = false

        wordLabel.font = font
        wordLabel.text = ProbeCase.word
        wordLabel.translatesAutoresizingMaskIntoConstraints = false
        canvas.addSubview(wordLabel)

        caretBar.backgroundColor = .systemRed
        caretBar.isUserInteractionEnabled = false
        canvas.addSubview(caretBar)

        view.addSubview(canvas)
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: contentGuide.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor),
            canvas.heightAnchor.constraint(equalToConstant: ceil(font.lineHeight) + 40),
            wordLabel.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: 20),
            wordLabel.topAnchor.constraint(equalTo: canvas.topAnchor, constant: 20),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.prepare()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            self?.beginSession()
        }
    }

    /// Computes the caret rect (between the "H" and the "i") and takes the
    /// hierarchy baseline before the session exists.
    private func prepare() {
        canvas.layoutIfNeeded()
        let font = wordLabel.font ?? .systemFont(ofSize: probeCase.fontSize)
        let first = (String(ProbeCase.word.prefix(1)) as NSString).size(withAttributes: [.font: font]).width
        let label = wordLabel.frame
        caretRect = CGRect(
            x: label.minX + first,
            y: label.minY + (label.height - font.lineHeight) / 2,
            width: 2,
            height: font.lineHeight
        )
        caretBar.frame = caretRect
        let inWindow = canvas.convert(caretRect, to: nil)
        wordRectLabel.text = "caret: \(caretRect.probeText) (window \(inWindow.probeText))"
        result["caretRect"] = caretRect.probeArray
        result["caretRectInWindow"] = inWindow.probeArray
        result["caretHeight"] = (caretRect.height * 10).rounded() / 10
        result["canvasInWindow"] = canvas.convert(canvas.bounds, to: nil).probeArray
        Probe.log("caretRect=\(caretRect.probeText) canvas=\(canvas.bounds.probeText) font=\(font.pointSize)")
        beginMonitoring(baselineAfter: 0)
        flush()
    }

    private func beginSession() {
        guard caretRect != .zero else {
            Probe.log("beginSession called before prepare")
            return
        }
        let point = CGPoint(x: caretRect.midX, y: caretRect.midY)
        var widgetName = "nil"
        widget = nil
        if probeCase.kind == .sessionWidget {
            if #available(iOS 17.4, *) {
                // As the engine does: invisible, never touched, framed as the caret.
                let cursor = UIStandardTextCursorView()
                cursor.tintColor = .clear
                cursor.isUserInteractionEnabled = false
                cursor.isAccessibilityElement = false
                cursor.accessibilityElementsHidden = true
                cursor.frame = caretRect
                canvas.addSubview(cursor)
                widget = cursor
                widgetName = "UIStandardTextCursorView"
            } else {
                widgetName = "nil (UIStandardTextCursorView needs iOS 17.4)"
            }
        }

        let started = UITextLoupeSession.begin(at: point, fromSelectionWidgetView: widget, in: canvas)
        session = started
        let returned = started != nil
        Probe.log("beginLoupeSession point=\(Int(point.x)),\(Int(point.y)) caretRect=\(caretRect.probeText) widget=\(widgetName) -> session=\(returned ? "returned" : "nil")")
        result["widget"] = widgetName
        result["sessionReturned"] = returned
        result["sessionPoint"] = [point.x, point.y].map { ($0 * 10).rounded() / 10 }
        result["moves"] = 0
        extraStatus = "session=\(returned ? "yes" : "NO (nil)")  widget=\(widgetName == "nil" ? "nil" : "cursor view")  caret h=\(Int(caretRect.height))"
        state = "holding"
        flush()

        moveStep = 0
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.moveTick() }
        RunLoop.main.add(timer, forMode: .common)
        moveTimer = timer
    }

    /// Two seconds of movement along the word, then the session ends.
    private func moveTick() {
        moveStep += 1
        if moveStep <= moveSteps {
            let offset = 14 * sin(Double(moveStep) * Double.pi / 10)
            let rect = caretRect.offsetBy(dx: offset, dy: 0)
            let point = CGPoint(x: rect.midX, y: rect.midY)
            widget?.frame = rect
            caretBar.frame = rect
            session?.move(to: point, withCaretRect: rect, trackingCaret: true)
            result["moves"] = moveStep
            if moveStep % 5 == 0 {
                Probe.log("move \(moveStep) caretRect=\(rect.probeText) session=\(session == nil ? "nil" : "alive")")
            }
            return
        }
        moveTimer?.invalidate()
        moveTimer = nil
        session?.invalidate()
        session = nil
        widget?.removeFromSuperview()
        widget = nil
        // Leave the screen readable for a moment before the test reads "done".
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            self.state = "done"
            self.flush()
        }
    }
}
