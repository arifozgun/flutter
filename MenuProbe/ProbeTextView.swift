import UIKit

/// A plain UITextView, the native reference. It only records what UIKit asks
/// it (canPerformAction, targetForAction, buildMenu) and implements the engine's extra command
/// handlers so the variants that return a Flutter-style menu from a UITextView
/// have a target for them. It never changes UIKit's answers.
final class ProbeTextView: UITextView, ProbeExtraActions {
    var onEvent: ((String) -> Void)?
    private let actionLog = ActionLog(name: "textview-canPerformAction")
    private let targetLog = ActionLog(name: "textview-targetForAction")

    func flushActionLog() {
        actionLog.flush()
        targetLog.flush()
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        let answer = super.canPerformAction(action, withSender: sender)
        actionLog.record(action, answer: answer, defaultAnswer: answer, sender: sender)
        return answer
    }

    override func target(forAction action: Selector, withSender sender: Any?) -> Any? {
        let target = super.target(forAction: action, withSender: sender)
        let targetName = target.map { String(describing: type(of: $0)) } ?? "nil"
        targetLog.record(action, detail: "target=\(targetName) sender=\(ActionLog.senderText(sender))")
        return target
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        let system = builder.system == .context ? "context" : (builder.system == .main ? "main" : "other")
        let root = builder.menu(for: .root)
        Probe.write("textview-buildMenu", "=== buildMenu system=\(system) [\(Probe.stamp())]\n" + MenuDump.describe(root.map { [$0] } ?? []), append: true)
    }

    func handleLookUpAction() { onEvent?("handleLookUpAction") }
    func handleSearchWebAction() { onEvent?("handleSearchWebAction") }
    func handleShareAction() { onEvent?("handleShareAction") }
    func handleTranslateAction() { onEvent?("handleTranslateAction") }
}
