import UIKit

enum ProbeHost: String {
    /// A real UITextView; the menu comes from UIKit's text interaction and the
    /// variant's builder runs in the text view delegate's edit menu callback.
    case textView
    /// ProbeTextInputView, set up like FlutterTextInputView; the builder runs
    /// in its UIEditMenuInteraction delegate.
    case custom
}

/// One probe variant. The README has the same table.
@MainActor
struct Variant {
    let number: Int
    let slug: String
    let host: ProbeHost
    let hypothesis: String
    var attachesTextInteraction = false
    var answersYesToEveryAction = false
    /// Builds the returned menu from suggestedActions. Returning nil from a
    /// UITextView delegate means "the system default menu".
    let build: ([UIMenuElement]) -> UIMenu?

    var tag: String { String(format: "v%02d-%@", number, slug) }

    static func fromLaunchArguments() -> Variant {
        let number = UserDefaults.standard.integer(forKey: "variant")
        return all.first { $0.number == number } ?? all[0]
    }

    static let all: [Variant] = [
        Variant(
            number: 0, slug: "textview-native", host: .textView,
            hypothesis: "Native reference: a UITextView with a selected word and the system default menu (delegate returns nil).",
            build: { _ in nil }
        ),
        Variant(
            number: 1, slug: "custom-untouched", host: .custom,
            hypothesis: "What UIKit suggests for a custom UITextInput view, shown untouched (the engine's path when the framework sends no items).",
            build: { UIMenu(title: "", children: $0) }
        ),
        Variant(
            number: 2, slug: "custom-engine-flat", host: .custom,
            hypothesis: "The engine's current structure (port of menuForConfiguration). Expected to reproduce Flutter's flat list.",
            build: { MenuBuilders.engineFlat($0) }
        ),
        Variant(
            number: 3, slug: "custom-keep-parents", host: .custom,
            hypothesis: "Lifted commands stay inside their original suggested parent menus; extras appended flat without images. Does the system parent alone give the Cut/Copy/Paste icon row?",
            build: { MenuBuilders.keepParents($0, groupedExtras: false, extraImages: false) }
        ),
        Variant(
            number: 4, slug: "custom-flat-extra-icons", host: .custom,
            hypothesis: "The engine's flat structure, only adding SF Symbol images to the extras. Do images alone give row icons (and nothing else)?",
            build: { MenuBuilders.engineFlat($0, extraImages: true) }
        ),
        Variant(
            number: 5, slug: "custom-inline-groups", host: .custom,
            hypothesis: "Inline groups with standard identifiers (.standardEdit, .lookup, .share), no preferredElementSize, no images. Do inline groups give separators, and does .standardEdit alone give the icon row?",
            build: {
                MenuBuilders.handGrouped($0, editIdentifier: .standardEdit, editSize: nil, standardExtraIdentifiers: true, extraImages: false)
            }
        ),
        Variant(
            number: 6, slug: "custom-small-size-only", host: .custom,
            hypothesis: "Inline groups with probe identifiers; only the Cut/Copy/Paste group gets preferredElementSize .small; no images. Does .small alone give the icon row?",
            build: {
                MenuBuilders.handGrouped($0, editIdentifier: MenuBuilders.probeEditIdentifier, editSize: .small, standardExtraIdentifiers: false, extraImages: false)
            }
        ),
        Variant(
            number: 7, slug: "custom-groups-small-icons", host: .custom,
            hypothesis: "Hand-built candidate: .standardEdit group with .small, .lookup and .share groups, SF Symbols on extras.",
            build: {
                MenuBuilders.handGrouped($0, editIdentifier: .standardEdit, editSize: .small, standardExtraIdentifiers: true, extraImages: true)
            }
        ),
        Variant(
            number: 8, slug: "custom-keep-parents-grouped-icons", host: .custom,
            hypothesis: "Tree-filter candidate: suggested tree filtered to the requested commands (parents kept), extras in .lookup and .share inline groups with SF Symbols.",
            build: { MenuBuilders.keepParents($0, groupedExtras: true, extraImages: true) }
        ),
        Variant(
            number: 9, slug: "custom-groups-medium-icons", host: .custom,
            hypothesis: "As v07 with preferredElementSize .medium instead of .small (which size matches native?).",
            build: {
                MenuBuilders.handGrouped($0, editIdentifier: .standardEdit, editSize: .medium, standardExtraIdentifiers: true, extraImages: true)
            }
        ),
        Variant(
            number: 10, slug: "custom-self-built", host: .custom,
            hypothesis: "Ignores suggestedActions: new Cut/Copy/Paste commands with public selectors and SF Symbols in a .small .standardEdit group, extras grouped with symbols.",
            build: { _ in MenuBuilders.selfBuilt() }
        ),
        Variant(
            number: 11, slug: "custom-textinteraction-untouched", host: .custom,
            hypothesis: "Diagnostic: the custom view with a UITextInteraction attached (the engine adds one when inputDelegate is nil). Does it change suggestedActions?",
            attachesTextInteraction: true,
            build: { UIMenu(title: "", children: $0) }
        ),
        Variant(
            number: 12, slug: "custom-yes-to-all-untouched", host: .custom,
            hypothesis: "Diagnostic only, cannot ship: canPerformAction answers YES to every selector, to list every command UIKit would offer before filtering. Rows are not tapped.",
            answersYesToEveryAction: true,
            build: { UIMenu(title: "", children: $0) }
        ),
        Variant(
            number: 13, slug: "textview-engine-flat", host: .textView,
            hypothesis: "Cross-check: a real UITextView returning the engine's flat structure built from its own suggestedActions. Flat here too means the structure, not the view, decides.",
            build: { MenuBuilders.engineFlat($0) }
        ),
        Variant(
            number: 14, slug: "textview-keep-parents-grouped-icons", host: .textView,
            hypothesis: "Cross-check: the v08 algorithm on a real UITextView's tree. Should look native with only the requested items.",
            build: { MenuBuilders.keepParents($0, groupedExtras: true, extraImages: true) }
        ),
        Variant(
            number: 15, slug: "custom-groups-small-icons-visible", host: .custom,
            hypothesis: "As v07 plus preferredImageVisibility = .visible on every element (iOS 27 API; identical to v07 on iOS 26).",
            build: { suggested in
                let menu = MenuBuilders.handGrouped(suggested, editIdentifier: .standardEdit, editSize: .small, standardExtraIdentifiers: true, extraImages: true)
                let supported = MenuBuilders.makeImagesVisible(menu)
                Probe.event("preferredImageVisibility supported=\(supported)")
                return menu
            }
        ),
    ]
}
