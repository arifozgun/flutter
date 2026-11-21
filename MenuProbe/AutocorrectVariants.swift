import UIKit

/// One variant of the autocorrect harness (`-acVariant <id>`). The defaults
/// are sequence T of the Flutter measurement in the engine's layout: a
/// zero-sized input view, the keyboard's input delegate kept (guarded), a
/// UITextInteraction attached before the menu and removed when the dismiss
/// animation completes, a programmatic selection change after typing.
/// README.md has the table.
struct ACVariant {
    enum Host: String { case textView, textField, custom }
    enum Layout: String {
        /// Zero-sized input view in a zero-sized hider; another view draws.
        case flutterLike
        /// As flutterLike, but the input view is 1x1.
        case oneByOne
        /// The input view is the visible field and draws its own text.
        case normal
    }
    /// How the final selection change (after typing) is started.
    enum Trigger: String {
        /// 3.5 s after the last keyboard edit, by a timer in the app.
        case timer
        /// By a real tap near the start of the field (the app asks the test).
        case tap
    }
    enum Removal: String { case willDismiss, completion, completionPlus2s, never }
    enum AfterRemoval: String { case none, textInputNil, release, reloadInputViews, resignBecome, selectionNudge, textNudge }
    enum History: String { case none, sameSession, earlierSession }
    enum SecondMenu: String { case none, hiddenAtFirstKey, dismissedBeforeTyping }

    let id: String
    let question: String
    let what: String
    var host: Host = .custom
    var layout: Layout = .flutterLike
    /// Menu cycles before typing: select "harbor", (attach), (present), move
    /// the selection to the end and dismiss, (remove).
    var cycles = 1
    var showsMenu = true
    var attachesInteraction = true
    var interactionMode: UITextInteractionMode = .editable
    var interactionGesturesAllowed = true
    var newInteractionEachCycle = false
    var removal: Removal = .completion
    var afterRemoval: AfterRemoval = .none
    var delegateHandling: ACInputView.DelegateHandling = .guarded
    var engineWorkaround = true
    /// The selection moves to the end 1 s after the removal instead of with
    /// the dismissal.
    var moveToEndAfterRemoval = false
    /// The test taps at the end of the field to move the selection and
    /// dismiss the menu (as in Flutter) instead of a timer.
    var dismissByTap = false
    var history: History = .none
    var secondMenu: SecondMenu = .none
    /// The test taps at the end of the field once more before typing
    /// (selection unchanged, so nothing is announced).
    var secondTap = false
    var trigger: Trigger = .timer
    /// false: the final selection is assigned without will/did-change.
    var announcesFinalChange = true
    var inlinePrediction: UITextInlinePredictionType = .no

    static func named(_ id: String) -> ACVariant? {
        all.first { $0.id == id || $0.id.hasPrefix(id + "-") }
    }

    static let all: [ACVariant] = [
        // Q1: native reference.
        ACVariant(id: "n01-textview-tap", question: "Q1", what: "UITextView: type abc at the end, real tap near the start.", host: .textView, cycles: 0, trigger: .tap),
        ACVariant(id: "n02-textview-set", question: "Q1", what: "UITextView: type abc at the end, selectedRange = {3,0} by a timer.", host: .textView, cycles: 0),
        ACVariant(id: "n03-textfield-tap", question: "Q1", what: "UITextField: type abc at the end, real tap near the start.", host: .textField, cycles: 0, trigger: .tap),
        ACVariant(id: "n04-textfield-set", question: "Q1", what: "UITextField: type abc at the end, selectedTextRange = {3,0} by a timer.", host: .textField, cycles: 0),

        // Q2: stock engine equivalent (no interaction ever).
        ACVariant(id: "s01-stock-set", question: "Q2", what: "Engine layout, no interaction, no menu; engine-style selection change by a timer.", cycles: 0),
        ACVariant(id: "s02-stock-tap", question: "Q2", what: "As s01; the change follows a real tap on the drawn text (as Flutter).", cycles: 0, trigger: .tap),
        ACVariant(id: "s03-stock-silent", question: "Q2/Q4", what: "As s01; the selection is assigned without selectionWillChange/DidChange.", cycles: 0, announcesFinalChange: false),
        ACVariant(id: "s04-stock-1x1", question: "Q2/Q4", what: "As s01 with a 1x1 input view.", layout: .oneByOne, cycles: 0),
        ACVariant(id: "s05-stock-inline-default", question: "Q2/Q4", what: "As s01 with inlinePredictionType .default.", cycles: 0, inlinePrediction: .default),

        // Q3: sequence T.
        ACVariant(id: "t01-sequence-T", question: "Q3", what: "Sequence T: select harbor, attach (guarded), menu, move to end + dismiss, remove on completion, type, engine-style change."),
        ACVariant(id: "t02-sequence-T-taps", question: "Q3", what: "As t01 with real taps: one at the end moves the selection and dismisses, one near the start makes the final change.", dismissByTap: true, trigger: .tap),

        // Q4: one factor at a time (all from t01).
        ACVariant(id: "f01-interaction-only", question: "Q4", what: "Attach and remove the interaction (same times), no menu.", showsMenu: false),
        ACVariant(id: "f02-menu-only", question: "Q4", what: "Menu shown and dismissed, no interaction ever (expected = s01).", attachesInteraction: false),
        ACVariant(id: "f03-remove-willDismiss", question: "Q4", what: "Removed in willDismiss.", removal: .willDismiss),
        ACVariant(id: "f04-remove-2s-after", question: "Q4", what: "Removed 2 s after the dismiss animation completed.", removal: .completionPlus2s),
        ACVariant(id: "f05-remove-never", question: "Q4", what: "Never removed (attached while typing and at the change).", removal: .never),
        ACVariant(id: "f06-move-after-removal", question: "Q4", what: "The dismissal does not move the selection; it moves to the end 1 s after the removal.", moveToEndAfterRemoval: true),
        ACVariant(id: "f07-noguard", question: "Q4", what: "No guard (UIKit replaces and clears inputDelegate), engine workaround off.", delegateHandling: .unguarded, engineWorkaround: false),
        ACVariant(id: "f08-noguard-workaround", question: "Q4", what: "No guard, engine workaround on (transient interaction when inputDelegate is nil).", delegateHandling: .unguarded),
        ACVariant(id: "f09-noguard-restore", question: "Q4", what: "No guard; the delegate from before the attach is put back after the removal (earlier engine attempt).", delegateHandling: .unguardedRestore),
        ACVariant(id: "f10-history-same-session", question: "Q4", what: "Type abc and change the selection first (no menu), restore the text, same focus session; then t01.", history: .sameSession),
        ACVariant(id: "f11-history-earlier-session", question: "Q4", what: "As f10, but resign and become first responder after the restore (sequence B's history).", history: .earlierSession),
        ACVariant(id: "f12-second-menu-firstkey", question: "Q4", what: "After t01's menu, a second menu (paste, select all; no interaction), hidden at the first key.", secondMenu: .hiddenAtFirstKey),
        ACVariant(id: "f13-second-menu-before-typing", question: "Q4", what: "As f12, but the second menu is dismissed before typing.", secondMenu: .dismissedBeforeTyping),
        ACVariant(id: "f14-second-tap", question: "Q4", what: "A real tap at the end of the field before typing (selection unchanged, nothing announced).", secondTap: true),
        ACVariant(id: "f15-textinput-nil", question: "Q4", what: "After the removal: interaction.textInput = nil.", afterRemoval: .textInputNil),
        ACVariant(id: "f16-release", question: "Q4", what: "After the removal: the interaction object is released.", afterRemoval: .release),
        ACVariant(id: "f17-two-cycles-same", question: "Q4", what: "Two menu cycles with the same interaction object.", cycles: 2),
        ACVariant(id: "f18-two-cycles-new", question: "Q4", what: "Two menu cycles, a new interaction object for each.", cycles: 2, newInteractionEachCycle: true),
        ACVariant(id: "f19-reload-input-views", question: "Q4", what: "After the removal: reloadInputViews().", afterRemoval: .reloadInputViews),
        ACVariant(id: "f20-resign-become", question: "Q4", what: "After the removal: resignFirstResponder() and becomeFirstResponder().", afterRemoval: .resignBecome),
        ACVariant(id: "f21-selection-nudge", question: "Q4", what: "After the removal: selectionWillChange/DidChange without a change.", afterRemoval: .selectionNudge),
        ACVariant(id: "f22-text-nudge", question: "Q4", what: "After the removal: textWillChange/DidChange without a change.", afterRemoval: .textNudge),
        ACVariant(id: "f23-T-silent", question: "Q4", what: "t01, final selection assigned without will/did-change.", announcesFinalChange: false),
        ACVariant(id: "f24-T-1x1", question: "Q4", what: "t01 with a 1x1 input view.", layout: .oneByOne),
        ACVariant(id: "f25-T-normal-layout", question: "Q4", what: "t01 with a visible, full-size input view that draws its text.", layout: .normal),
        ACVariant(id: "f26-T-inline-default", question: "Q4", what: "t01 with inlinePredictionType .default.", inlinePrediction: .default),
        ACVariant(id: "f27-noneditable", question: "Q4", what: "t01 with UITextInteraction(for: .nonEditable).", interactionMode: .nonEditable),
        ACVariant(id: "f28-shouldbegin-no", question: "Q4", what: "t01; the interaction's delegate refuses every gesture (interactionShouldBegin false).", interactionGesturesAllowed: false),

        // Q3 again, last in the run.
        ACVariant(id: "t99-sequence-T-repeat", question: "Q3", what: "t01 again, at the end of the run."),
    ]
}
