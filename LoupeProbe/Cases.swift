import UIKit

/// The four ways a case exercises the loupe.
enum CaseKind: String, CaseIterable {
    /// A native UITextView; the loupe comes from a long-press drag.
    case textView = "textview"
    /// A native UITextField; the loupe comes from a long-press drag.
    case textField = "textfield"
    /// The app begins a UITextLoupeSession itself, with a UIStandardTextCursorView
    /// framed as the caret as the selection widget (what the Flutter engine does).
    case sessionWidget = "session-widget"
    /// The same call with a nil selection widget view.
    case sessionNil = "session-nil"

    var isNative: Bool { self == .textView || self == .textField }
}

struct ProbeCase {
    static let fontSizes: [CGFloat] = [17, 48, 96, 150, 220]
    /// Short enough to fit the screen width at 220 pt.
    static let word = "Hi"

    let kind: CaseKind
    let fontSize: CGFloat

    var name: String { "\(kind.rawValue)-\(Int(fontSize))" }

    var explanation: String {
        switch kind {
        case .textView:
            return "UITextView, editable, first responder, caret inside the word. Long-press and drag: does UIKit show its loupe?"
        case .textField:
            return "UITextField, editable, first responder, caret inside the word. Long-press and drag: does UIKit show its loupe?"
        case .sessionWidget:
            return "Plain view. The app calls UITextLoupeSession.begin with a UIStandardTextCursorView framed as the caret as the selection widget."
        case .sessionNil:
            return "Plain view. The app calls UITextLoupeSession.begin with a nil selection widget view."
        }
    }

    static func parse(_ name: String) -> ProbeCase? {
        for kind in CaseKind.allCases {
            let prefix = kind.rawValue + "-"
            guard name.hasPrefix(prefix),
                  let size = Int(name.dropFirst(prefix.count)),
                  fontSizes.contains(CGFloat(size))
            else { continue }
            return ProbeCase(kind: kind, fontSize: CGFloat(size))
        }
        return nil
    }

    /// Reads `-case <name>` from the launch arguments.
    static func fromLaunchArguments() -> ProbeCase {
        let requested = UserDefaults.standard.string(forKey: "case") ?? ""
        if let found = parse(requested) {
            return found
        }
        Probe.log("unknown or missing -case '\(requested)'; using textview-96")
        return ProbeCase(kind: .textView, fontSize: 96)
    }
}
