import UIKit

/// A plain UITextView, the native reference. It only records what UIKit asks
/// it (canPerformAction, buildMenu) and implements the engine's extra command
/// handlers so the variants that return a Flutter-style menu from a UITextView
/// have a target for them. It never changes UIKit's answers.
final class ProbeTextView: UITextView, ProbeExtraActions {
    var onEvent: ((String) -> Void)?
    private let actionLog = ActionLog(name: "textview-canPerformAction")

    func flushActionLog() {
        actionLog.flush()
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        let answer = super.canPerformAction(action, withSender: sender)
        actionLog.record(action, answer: answer, defaultAnswer: answer, sender: sender)
        return answer
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        let system = builder.system == .context ? "context" : (builder.system == .main ? "main" : "other")
        let root = builder.menu(for: .root)
        Probe.write("textview-buildMenu", "=== buildMenu system=\(system)\n" + MenuDump.describe(root.map { [$0] } ?? []), append: true)
    }

    func handleLookUpAction() { onEvent?("handleLookUpAction") }
    func handleSearchWebAction() { onEvent?("handleSearchWebAction") }
    func handleShareAction() { onEvent?("handleShareAction") }
    func handleTranslateAction() { onEvent?("handleTranslateAction") }
}
