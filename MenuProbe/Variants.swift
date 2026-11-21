import UIKit

enum ProbeHost: String {
    /// A real UITextView; the menu comes from UIKit's text interaction and the
    /// variant's builder runs in the text view delegate's edit menu callback.
    case textView
    /// ProbeTextInputView, set up like FlutterTextInputView; the builder runs
    /// in its UIEditMenuInteraction delegate.
    case custom
}

/// Where the custom view sits and who draws the text.
enum ProbeLayout: String {
    /// The custom view is a visible field that draws its own text.
    case normal
    /// FlutterTextInputView's iPhone setup: a zero-sized input view in a
    /// zero-sized accessibility hider at the field's origin; a separate view
    /// draws the text (FlutterLikeTextInputView, RenderedTextView).
    case flutterLike
}

/// One probe variant. The README has the same table.
@MainActor
struct Variant {
    let number: Int
    let slug: String
    let host: ProbeHost
    let hypothesis: String
    var interactionMode: InteractionMode = .none
    var layout: ProbeLayout = .normal
    var answersYesToEveryAction = false
    /// UITextView host only: false leaves the text view without a delegate.
    var textViewDelegate = true
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
            interactionMode: .always,
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

        // MARK: Round 2. A: when must the UITextInteraction be attached?
        // All use the public-API filter with everything requested (D1).
        Variant(
            number: 16, slug: "custom-ti-always-filter-all", host: .custom,
            hypothesis: "A/D1: UITextInteraction for the view's whole life; suggested system groups filtered to cut, copy, paste, lookUp, searchWeb, share with public API. Rows from iOS, working?",
            interactionMode: .always,
            build: { MenuBuilders.systemFiltered($0, request: MenuBuilders.requestAll) }
        ),
        Variant(
            number: 17, slug: "custom-ti-while-shown-filter-all", host: .custom,
            hypothesis: "A: UITextInteraction attached just before presentEditMenu, removed when the dismiss animation completes. Same rows as v16, and do they still work?",
            interactionMode: .whileMenuShown,
            build: { MenuBuilders.systemFiltered($0, request: MenuBuilders.requestAll) }
        ),
        Variant(
            number: 18, slug: "custom-ti-present-only-filter-all", host: .custom,
            hypothesis: "A: UITextInteraction attached before presentEditMenu, removed as soon as it returns (UIKit builds the menu afterwards). Are the system rows still offered?",
            interactionMode: .presentOnly,
            build: { MenuBuilders.systemFiltered($0, request: MenuBuilders.requestAll) }
        ),
        Variant(
            number: 19, slug: "custom-ti-until-will-present-filter-all", host: .custom,
            hypothesis: "A: UITextInteraction attached before presentEditMenu, removed in willPresentMenu (menu already built). Rows shown, and do they work without the interaction?",
            interactionMode: .untilWillPresent,
            build: { MenuBuilders.systemFiltered($0, request: MenuBuilders.requestAll) }
        ),
        // MARK: Round 2. B: the same in FlutterTextInputView's layout
        Variant(
            number: 20, slug: "flutterlike-engine-today", host: .custom,
            hypothesis: "B baseline: Flutter today. Zero-sized input view in a zero-sized accessibility hider, text drawn by another view, the engine's transient UITextInteraction (setTextInputState) and its flat menu.",
            interactionMode: .engineTransient, layout: .flutterLike,
            build: { MenuBuilders.engineFlat($0) }
        ),
        Variant(
            number: 21, slug: "flutterlike-ti-always-filter-all", host: .custom,
            hypothesis: "A/B: Flutter-like layout with a UITextInteraction for the whole life. Rows, side effects (caret, handles, gestures)?",
            interactionMode: .always, layout: .flutterLike,
            build: { MenuBuilders.systemFiltered($0, request: MenuBuilders.requestAll) }
        ),
        Variant(
            number: 22, slug: "flutterlike-ti-while-shown-filter-all", host: .custom,
            hypothesis: "A/B: Flutter-like layout, UITextInteraction only while the menu is shown. The likeliest engine design.",
            interactionMode: .whileMenuShown, layout: .flutterLike,
            build: { MenuBuilders.systemFiltered($0, request: MenuBuilders.requestAll) }
        ),
        Variant(
            number: 23, slug: "flutterlike-ti-until-will-present-filter-all", host: .custom,
            hypothesis: "A/B: Flutter-like layout, UITextInteraction from just before presentEditMenu until willPresentMenu.",
            interactionMode: .untilWillPresent, layout: .flutterLike,
            build: { MenuBuilders.systemFiltered($0, request: MenuBuilders.requestAll) }
        ),
        // MARK: Round 2. D: filtering with public API only (interaction always
        // attached, so the system rows exist whatever A finds)
        Variant(
            number: 24, slug: "custom-filter-no-share", host: .custom,
            hypothesis: "D2: request without share: cut, copy, paste, lookUp, searchWeb.",
            interactionMode: .always,
            build: { MenuBuilders.systemFiltered($0, request: MenuBuilders.requestNoShare) }
        ),
        Variant(
            number: 25, slug: "custom-filter-no-lookup", host: .custom,
            hypothesis: "D3: request without lookUp: cut, copy, paste, searchWeb, share. The whole lookup group (Look Up and Translate) goes.",
            interactionMode: .always,
            build: { MenuBuilders.systemFiltered($0, request: MenuBuilders.requestNoLookUp) }
        ),
        Variant(
            number: 26, slug: "custom-filter-custom-in-group", host: .custom,
            hypothesis: "D4: a custom UIAction between copy and paste, inside UIKit's standard-edit group, and another after share. Does the icon row survive an item without an image?",
            interactionMode: .always,
            build: { MenuBuilders.systemFiltered($0, request: MenuBuilders.requestWithCustom) }
        ),
        Variant(
            number: 27, slug: "custom-filter-custom-split", host: .custom,
            hypothesis: "D4b: as v26, but each custom UIAction gets its own inline group, splitting the edit group in two.",
            interactionMode: .always,
            build: { MenuBuilders.systemFiltered($0, request: MenuBuilders.requestWithCustom, splitAtCustom: true) }
        ),
        Variant(
            number: 28, slug: "custom-filter-diag-lookup-only", host: .custom,
            hypothesis: "DIAGNOSTIC, NOT SHIPPABLE: as v16, but the lookup group keeps only the command whose selector name is the Look Up one, to see Look Up without Translate. Needs a private selector name.",
            interactionMode: .always,
            build: { MenuBuilders.systemFiltered($0, request: MenuBuilders.requestAll, diagnosticLookupFilter: true) }
        ),
        // MARK: Round 2. E: where does Search Web come from?
        Variant(
            number: 29, slug: "textview-untouched-returned", host: .textView,
            hypothesis: "E: the UITextView delegate returns suggestedActions untouched instead of nil. If Search Web disappears, UIKit adds it only for the default (nil) menu.",
            build: { UIMenu(title: "", children: $0) }
        ),
        Variant(
            number: 30, slug: "textview-no-delegate", host: .textView,
            hypothesis: "E: a UITextView without any delegate. The menu UIKit shows when nobody is asked.",
            textViewDelegate: false,
            build: { _ in nil }
        ),
        Variant(
            number: 31, slug: "textview-filter-all", host: .textView,
            hypothesis: "E/D reference: the public-API filter (as v16) applied to a real UITextView's suggestions.",
            build: { MenuBuilders.systemFiltered($0, request: MenuBuilders.requestAll) }
        ),
    ]
}
