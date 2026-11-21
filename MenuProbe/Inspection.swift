import UIKit

/// A timeline of calls into a view, one line per call with a timestamp.
/// Identical consecutive lines are folded into one line with a repeat count,
/// so frequent geometry queries do not flood the file. Written to
/// `<tag>-<name>.txt`.
@MainActor
final class CallLog {
    private let name: String
    private var pending: [String] = []
    private var lastLine: String?
    private var lastStamp = ""
    private var repeats = 0
    private var flushScheduled = false

    init(name: String) {
        self.name = name
    }

    func log(_ line: String) {
        if line == lastLine {
            repeats += 1
        } else {
            closeRun()
            lastLine = line
            lastStamp = Probe.stamp()
            repeats = 1
        }
        scheduleFlush()
    }

    /// Writes a marker line (an event such as "menu shown") into the timeline.
    func mark(_ text: String) {
        closeRun()
        lastLine = nil
        pending.append("[\(Probe.stamp())] ---- \(text)")
        scheduleFlush()
    }

    func flush() {
        closeRun()
        lastLine = nil
        guard !pending.isEmpty else { return }
        Probe.write(name, pending.joined(separator: "\n") + "\n", append: true)
        pending.removeAll()
    }

    private func closeRun() {
        guard let lastLine else { return }
        pending.append("[\(lastStamp)] \(lastLine)" + (repeats > 1 ? "  (x\(repeats))" : ""))
        self.lastLine = nil
        repeats = 0
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.flushScheduled = false
            self?.flush()
        }
    }
}

/// Records the view state a UITextInteraction may change: the subviews of the
/// text input view and its superviews, its interactions and gesture
/// recognizers, every window of the scene with its views (the edit menu, when
/// shown, is among them, with its labels and images), and the input delegate.
/// Appended to `<tag>-views.txt`, one block per capture.
@MainActor
enum ViewSnapshot {
    static let maxLinesPerWindow = 900

    static func capture(_ label: String, focus: UIView?, inputDelegate: String? = nil) {
        var lines = ["", "=================== \(label) [\(Probe.stamp())]"]
        if let focus {
            lines.append("focus view: \(describe(focus))")
            if let inputDelegate {
                lines.append("inputDelegate: \(inputDelegate)")
            }
            lines.append("isFirstResponder=\(focus.isFirstResponder)")
            lines.append("interactions (\(focus.interactions.count)):")
            for interaction in focus.interactions {
                lines.append("  \(NSStringFromClass(type(of: interaction)))")
            }
            let recognizers = focus.gestureRecognizers ?? []
            lines.append("gestureRecognizers (\(recognizers.count)):")
            for recognizer in recognizers {
                lines.append("  \(describe(recognizer))")
            }
            lines.append("focus subviews:")
            appendTree(focus, depth: 1, into: &lines, limit: 400)
            lines.append("superview chain:")
            var parent = focus.superview
            while let view = parent {
                let count = view.gestureRecognizers?.count ?? 0
                lines.append("  \(describe(view)) subviews=\(view.subviews.count) gestureRecognizers=\(count)")
                parent = view.superview
            }
        }
        let windows = focus?.window?.windowScene?.windows ?? []
        lines.append("windows (\(windows.count)):")
        for window in windows {
            lines.append("WINDOW \(describe(window)) level=\(window.windowLevel.rawValue) isKey=\(window.isKeyWindow)")
            var windowLines: [String] = []
            appendTree(window, depth: 1, into: &windowLines, limit: maxLinesPerWindow)
            lines.append(contentsOf: windowLines)
        }
        Probe.write("views", lines.joined(separator: "\n") + "\n", append: true)
    }

    /// The labels and images visible outside the probe's own views, i.e.
    /// what the edit menu actually shows, in view order.
    static func displayedMenu(_ label: String, appWindow: UIWindow?) {
        var lines = ["=== displayed \(label) [\(Probe.stamp())]"]
        let windows = appWindow?.windowScene?.windows ?? []
        for window in windows {
            var found: [String] = []
            collectLabels(window, into: &found, appWindow: appWindow)
            if !found.isEmpty {
                lines.append("WINDOW \(NSStringFromClass(type(of: window)))\(window === appWindow ? " (app window)" : "")")
                lines.append(contentsOf: found)
            }
        }
        Probe.write("displayed", lines.joined(separator: "\n") + "\n", append: true)
    }

    private static func collectLabels(_ view: UIView, into lines: inout [String], appWindow: UIWindow?) {
        // The probe's own header and field are not part of the menu.
        if view === appWindow?.rootViewController?.view { return }
        if view.isHidden || view.alpha < 0.01 { return }
        if let label = view as? UILabel, let text = label.text, !text.isEmpty {
            lines.append("  label \"\(text)\" in \(NSStringFromClass(type(of: view.superview ?? view))) frame=\(frameText(view))")
        } else if let imageView = view as? UIImageView, let image = imageView.image {
            lines.append("  image \(MenuDump.imageDescription(image)) frame=\(frameText(view))")
        } else if let text = view.accessibilityLabel, !text.isEmpty, !(view is UILabel) {
            lines.append("  a11y \"\(text)\" \(NSStringFromClass(type(of: view))) frame=\(frameText(view))")
        }
        for subview in view.subviews {
            collectLabels(subview, into: &lines, appWindow: appWindow)
        }
    }

    private static func frameText(_ view: UIView) -> String {
        let rect = view.convert(view.bounds, to: nil)
        return String(format: "%.0f,%.0f,%.0fx%.0f", rect.minX, rect.minY, rect.width, rect.height)
    }

    static func describe(_ view: UIView) -> String {
        var text = "\(NSStringFromClass(type(of: view))) frame=\(NSCoder.string(for: view.frame))"
        if view.isHidden { text += " hidden" }
        if view.alpha < 1 { text += String(format: " alpha=%.2f", view.alpha) }
        if view.clipsToBounds { text += " clips" }
        if let label = view as? UILabel, let string = label.text {
            text += " text=\"\(string.prefix(40))\""
        }
        if let imageView = view as? UIImageView, let image = imageView.image {
            text += " image=\(MenuDump.imageDescription(image))"
        }
        if let a11y = view.accessibilityLabel, !a11y.isEmpty, !(view is UILabel) {
            text += " a11y=\"\(a11y.prefix(40))\""
        }
        if let identifier = view.accessibilityIdentifier, !identifier.isEmpty {
            text += " id=\(identifier)"
        }
        if !view.interactions.isEmpty {
            text += " interactions=[\(view.interactions.map { NSStringFromClass(type(of: $0)) }.joined(separator: ","))]"
        }
        return text
    }

    static func describe(_ recognizer: UIGestureRecognizer) -> String {
        let states = ["possible", "began", "changed", "ended", "cancelled", "failed"]
        let state = recognizer.state.rawValue < states.count ? states[recognizer.state.rawValue] : "\(recognizer.state.rawValue)"
        var text = "\(NSStringFromClass(type(of: recognizer))) enabled=\(recognizer.isEnabled) state=\(state)"
        if let tap = recognizer as? UITapGestureRecognizer {
            text += " taps=\(tap.numberOfTapsRequired)"
        }
        if let name = recognizer.name {
            text += " name=\(name)"
        }
        return text
    }

    private static func appendTree(_ view: UIView, depth: Int, into lines: inout [String], limit: Int) {
        for subview in view.subviews {
            if lines.count >= limit {
                if lines.last != "  ... (truncated)" { lines.append("  ... (truncated)") }
                return
            }
            lines.append(String(repeating: "  ", count: depth) + describe(subview))
            appendTree(subview, depth: depth + 1, into: &lines, limit: limit)
        }
    }
}
