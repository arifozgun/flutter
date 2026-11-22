import UIKit

/// One variant of the Look Up harness (`-luVariant <id>`).
/// README.md ("Look Up harness") has the table.
struct LUVariant {
    enum Host: String { case textView, textField, custom }
    /// When the custom view has a UITextInteraction.
    enum Interaction: String {
        /// Never.
        case none
        /// Attached before the view becomes first responder, never removed.
        case permanent
        /// Attached right before the edit menu is presented, removed in the
        /// completion of the menu's dismissal animator (the prototype).
        case aroundMenu
        /// As aroundMenu, but removed only when the view became first
        /// responder again after it had resigned, or 10 s after the dismissal
        /// completed.
        case aroundMenuUntilRestored
    }
    /// What the custom view's edit menu offers.
    enum Menu: String {
        /// UIKit's suggested menu, unchanged.
        case suggested
        /// One "Look Up" action that presents UIReferenceLibraryViewController
        /// for the word (the stock engine's way).
        case referenceLibrary
    }

    let id: String
    let what: String
    var host: Host = .custom
    var interaction: Interaction = .none
    var menu: Menu = .suggested
    var delegateHandling: ACInputView.DelegateHandling = .guarded

    static func named(_ id: String) -> LUVariant? {
        all.first { $0.id == id || $0.id.hasPrefix(id + "-") }
    }

    static let all: [LUVariant] = [
        LUVariant(id: "v1-textview", what: "UITextView (reference): double tap harbor, Look Up, close.", host: .textView),
        LUVariant(id: "v2-textfield", what: "UITextField (reference): double tap harbor, Look Up, close.", host: .textField),
        LUVariant(id: "v3-custom-permanent", what: "Custom UITextInput view, UITextInteraction attached for good, UIKit's suggested menu unchanged.", interaction: .permanent, delegateHandling: .unguarded),
        LUVariant(id: "v4-custom-prototype", what: "Custom view, interaction attached before the menu, removed in the dismissal animator's completion.", interaction: .aroundMenu),
        LUVariant(id: "v5-custom-late-removal", what: "As v4, interaction removed when the view became first responder again or after 10 s.", interaction: .aroundMenuUntilRestored),
        LUVariant(id: "v6-custom-stock", what: "Custom view, no text interaction, a Look Up action presents UIReferenceLibraryViewController.", menu: .referenceLibrary),
    ]
}

/// Records every responder call of the view under test in
/// `<tag>-responder.txt`: the call, its result, a timestamp and, for become and
/// resign, the first 25 frames of the call stack (the first frame is the
/// view's override), so that the mechanism UIKit restores the responder with
/// can be read from a run where it works.
@MainActor
enum LUResponderLog {
    private static var count = 0

    static func stack() -> [String] {
        Array(Thread.callStackSymbols.dropFirst().prefix(25))
    }

    static func record(_ view: UIView, _ call: String, result: Bool, stack: [String] = []) {
        count += 1
        var text = "[\(Probe.stamp())] #\(count) \(call) -> \(result) view=\(NSStringFromClass(type(of: view))) isFirstResponder=\(view.isFirstResponder)\n"
        for (index, frame) in stack.enumerated() {
            text += "    \(index) \(frame)\n"
        }
        Probe.write("responder", text, append: true)
    }
}

/// The custom view of the Look Up harness: the autocorrect harness's
/// UITextInput view with the responder log and the menu choice added.
final class LUInputView: ACInputView {
    var menuStyle: LUVariant.Menu = .suggested
    /// The "Look Up" action of `.referenceLibrary`.
    var onLookUpAction: (() -> Void)?
    /// "become" or "resign", with the result.
    var onResponder: ((String, Bool) -> Void)?

    override var canBecomeFirstResponder: Bool {
        let result = super.canBecomeFirstResponder
        LUResponderLog.record(self, "canBecomeFirstResponder", result: result)
        return result
    }

    override func becomeFirstResponder() -> Bool {
        let stack = LUResponderLog.stack()
        let result = super.becomeFirstResponder()
        LUResponderLog.record(self, "becomeFirstResponder", result: result, stack: stack)
        onResponder?("become", result)
        return result
    }

    override func resignFirstResponder() -> Bool {
        let stack = LUResponderLog.stack()
        let result = super.resignFirstResponder()
        LUResponderLog.record(self, "resignFirstResponder", result: result, stack: stack)
        onResponder?("resign", result)
        return result
    }

    override func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        menuFor configuration: UIEditMenuConfiguration,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        let menu: UIMenu
        switch menuStyle {
        case .suggested:
            menu = UIMenu(title: "", children: suggestedActions)
        case .referenceLibrary:
            menu = UIMenu(title: "", children: [
                UIAction(title: "Look Up") { [weak self] _ in self?.onLookUpAction?() },
            ])
        }
        let header = "=== menu [\(Probe.stamp())] style=\(menuStyle.rawValue) hasMenuInteraction=\(hasMenuInteraction) suggested=\(suggestedActions.count)\n"
        Probe.write("menus", header + MenuDump.describe([menu]), append: true)
        calls.mark("menuFor style=\(menuStyle.rawValue)")
        return menu
    }
}

/// UITextView for the native reference, with the responder log.
final class LUTextView: UITextView {
    override var canBecomeFirstResponder: Bool {
        let result = super.canBecomeFirstResponder
        LUResponderLog.record(self, "canBecomeFirstResponder", result: result)
        return result
    }

    override func becomeFirstResponder() -> Bool {
        let stack = LUResponderLog.stack()
        let result = super.becomeFirstResponder()
        LUResponderLog.record(self, "becomeFirstResponder", result: result, stack: stack)
        return result
    }

    override func resignFirstResponder() -> Bool {
        let stack = LUResponderLog.stack()
        let result = super.resignFirstResponder()
        LUResponderLog.record(self, "resignFirstResponder", result: result, stack: stack)
        return result
    }
}

/// UITextField for the native reference, with the responder log.
final class LUTextField: UITextField {
    override var canBecomeFirstResponder: Bool {
        let result = super.canBecomeFirstResponder
        LUResponderLog.record(self, "canBecomeFirstResponder", result: result)
        return result
    }

    override func becomeFirstResponder() -> Bool {
        let stack = LUResponderLog.stack()
        let result = super.becomeFirstResponder()
        LUResponderLog.record(self, "becomeFirstResponder", result: result, stack: stack)
        return result
    }

    override func resignFirstResponder() -> Bool {
        let stack = LUResponderLog.stack()
        let result = super.resignFirstResponder()
        LUResponderLog.record(self, "resignFirstResponder", result: result, stack: stack)
        return result
    }

    var selectionText: String {
        guard let range = selectedTextRange else { return "nil" }
        let start = offset(from: beginningOfDocument, to: range.start)
        let length = offset(from: range.start, to: range.end)
        return "\(start),\(length)"
    }
}
