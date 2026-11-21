import UIKit

/// One item of the list the Flutter framework sends with
/// `ContextMenu.showSystemContextMenu` (type plus an optional title).
struct EngineItem {
    let type: String
    let title: String?
}

/// Menu structures returned by the variants. `engineFlat` is a line-by-line
/// Swift port of FlutterTextInputView's
/// `editMenuInteraction:menuForConfiguration:suggestedActions:`; the others
/// are candidate fixes. All of them use public API only.
@MainActor
enum MenuBuilders {
    /// What `SystemContextMenu.getDefaultItems` sends on iOS for a selected
    /// word in an editable field (English titles from
    /// DefaultWidgetsLocalizations). Select All is only sent for a collapsed
    /// selection and Translate is not mapped by the framework yet.
    static let flutterDefaultItems: [EngineItem] = [
        EngineItem(type: "cut", title: nil),
        EngineItem(type: "copy", title: nil),
        EngineItem(type: "paste", title: nil),
        EngineItem(type: "lookUp", title: "Look Up"),
        EngineItem(type: "searchWeb", title: "Search Web"),
        EngineItem(type: "share", title: "Share"),
    ]

    static let cutSelector = #selector(UIResponderStandardEditActions.cut(_:))
    static let copySelector = #selector(UIResponderStandardEditActions.copy(_:))
    static let pasteSelector = #selector(UIResponderStandardEditActions.paste(_:))
    static let deleteSelector = #selector(UIResponderStandardEditActions.delete(_:))
    static let selectAllSelector = #selector(UIResponderStandardEditActions.selectAll(_:))
    static let captureSelector = #selector(UIResponder.captureTextFromCamera(_:))

    /// Commands the engine lifts out of suggestedActions.
    static func basicSelector(_ type: String) -> Selector? {
        switch type {
        case "cut": return cutSelector
        case "copy": return copySelector
        case "paste": return pasteSelector
        case "delete": return deleteSelector
        case "selectAll": return selectAllSelector
        case "captureTextFromCamera": return captureSelector
        default: return nil
        }
    }

    /// Commands the engine creates itself, with its own handler selectors.
    static func extraSelector(_ type: String) -> Selector? {
        switch type {
        case "lookUp": return #selector(ProbeExtraActions.handleLookUpAction)
        case "searchWeb": return #selector(ProbeExtraActions.handleSearchWebAction)
        case "share": return #selector(ProbeExtraActions.handleShareAction)
        case "translate": return #selector(ProbeExtraActions.handleTranslateAction)
        default: return nil
        }
    }

    /// SF Symbols for the candidates that add images. The native names can be
    /// read from the v00 tree dump; these are close guesses.
    static func symbolName(_ type: String) -> String {
        switch type {
        case "cut": return "scissors"
        case "copy": return "doc.on.doc"
        case "paste": return "doc.on.clipboard"
        case "lookUp": return "character.book.closed"
        case "searchWeb": return "magnifyingglass"
        case "share": return "square.and.arrow.up"
        case "translate": return "translate"
        default: return "questionmark"
        }
    }

    static var requestedBasicSelectors: Set<Selector> {
        Set(flutterDefaultItems.compactMap { basicSelector($0.type) })
    }

    static var requestedExtras: [EngineItem] {
        flutterDefaultItems.filter { extraSelector($0.type) != nil }
    }

    // MARK: - Engine port

    /// FlutterTextInputView searchCommandWithSelector:element: (depth first).
    static func searchCommand(_ selector: Selector, in element: UIMenuElement) -> UICommand? {
        if let command = element as? UICommand {
            return command.action == selector ? command : nil
        }
        if let menu = element as? UIMenu {
            for child in menu.children {
                if let result = searchCommand(selector, in: child) {
                    return result
                }
            }
        }
        return nil
    }

    /// FlutterTextInputView addAdditionalBasicCommandToItems: a UICommand with
    /// the framework's title, the engine's selector and, in the engine, no
    /// image.
    static func extraCommand(_ item: EngineItem, image: Bool) -> UICommand? {
        guard let selector = extraSelector(item.type), let title = item.title else { return nil }
        return UICommand(
            title: title,
            image: image ? UIImage(systemName: symbolName(item.type)) : nil,
            action: selector,
            propertyList: nil
        )
    }

    /// The suggested commands for the requested basic types, in the order the
    /// framework sent them.
    static func liftedCommands(_ suggested: [UIMenuElement]) -> [UICommand] {
        let suggestedMenu = UIMenu(title: "", children: suggested)
        return flutterDefaultItems.compactMap { item in
            basicSelector(item.type).flatMap { searchCommand($0, in: suggestedMenu) }
        }
    }

    /// The engine's current structure: lifted commands and nil-image extras in
    /// the framework's order, in one flat menu. With `extraImages` the extras
    /// get SF Symbols and nothing else changes.
    static func engineFlat(_ suggested: [UIMenuElement], extraImages: Bool = false) -> UIMenu {
        let suggestedMenu = UIMenu(title: "", children: suggested)
        var items: [UIMenuElement] = []
        for item in flutterDefaultItems {
            if let selector = basicSelector(item.type) {
                if let command = searchCommand(selector, in: suggestedMenu) {
                    items.append(command)
                } else {
                    Probe.event("Cannot find context menu item of type \"\(item.type)\".")
                }
            } else if let command = extraCommand(item, image: extraImages) {
                items.append(command)
            }
        }
        return UIMenu(title: "", children: items)
    }

    // MARK: - Candidates

    /// Keeps the suggested tree as it is, minus every command whose selector
    /// was not requested. Parent menus are kept through
    /// `replacingChildren(_:)`, which keeps their title, image, identifier,
    /// options and preferredElementSize; menus left empty are dropped.
    /// Order is the system's order, not the framework's.
    static func filterTree(_ elements: [UIMenuElement], keeping selectors: Set<Selector>) -> [UIMenuElement] {
        var result: [UIMenuElement] = []
        for element in elements {
            if let command = element as? UICommand {
                if selectors.contains(command.action) {
                    result.append(command)
                }
            } else if let menu = element as? UIMenu {
                let children = filterTree(menu.children, keeping: selectors)
                if !children.isEmpty {
                    result.append(menu.replacingChildren(children))
                }
            }
        }
        return result
    }

    /// An inline (separated) group, or nil when it would be empty.
    static func inlineGroup(
        _ children: [UIMenuElement],
        identifier: UIMenu.Identifier?,
        size: UIMenu.ElementSize?
    ) -> UIMenu? {
        guard !children.isEmpty else { return nil }
        let menu = UIMenu(title: "", image: nil, identifier: identifier, options: .displayInline, children: children)
        if let size {
            menu.preferredElementSize = size
        }
        return menu
    }

    static let probeEditIdentifier = UIMenu.Identifier("dev.probe.menu.edit")
    static let probeLookupIdentifier = UIMenu.Identifier("dev.probe.menu.lookup")
    static let probeShareIdentifier = UIMenu.Identifier("dev.probe.menu.share")

    /// The extras split the way native text views group them: Look Up and
    /// Search Web together, Share on its own.
    static func extraGroups(images: Bool, standardIdentifiers: Bool) -> [UIMenu] {
        let extras = requestedExtras
        let lookup = extras.filter { $0.type != "share" }.compactMap { extraCommand($0, image: images) }
        let share = extras.filter { $0.type == "share" }.compactMap { extraCommand($0, image: images) }
        return [
            inlineGroup(lookup, identifier: standardIdentifiers ? .lookup : probeLookupIdentifier, size: nil),
            inlineGroup(share, identifier: standardIdentifiers ? .share : probeShareIdentifier, size: nil),
        ].compactMap { $0 }
    }

    /// Lifted Cut/Copy/Paste in one inline group, then the extra groups.
    static func handGrouped(
        _ suggested: [UIMenuElement],
        editIdentifier: UIMenu.Identifier?,
        editSize: UIMenu.ElementSize?,
        standardExtraIdentifiers: Bool,
        extraImages: Bool
    ) -> UIMenu {
        var children: [UIMenuElement] = []
        if let edit = inlineGroup(liftedCommands(suggested), identifier: editIdentifier, size: editSize) {
            children.append(edit)
        }
        children.append(contentsOf: extraGroups(images: extraImages, standardIdentifiers: standardExtraIdentifiers))
        return UIMenu(title: "", children: children)
    }

    /// The filtered suggested tree, then the extras either flat (as the engine
    /// adds them) or in their own inline groups.
    static func keepParents(_ suggested: [UIMenuElement], groupedExtras: Bool, extraImages: Bool) -> UIMenu {
        var children = filterTree(suggested, keeping: requestedBasicSelectors)
        if groupedExtras {
            children.append(contentsOf: extraGroups(images: extraImages, standardIdentifiers: true))
        } else {
            children.append(contentsOf: requestedExtras.compactMap { extraCommand($0, image: extraImages) as UIMenuElement? })
        }
        return UIMenu(title: "", children: children)
    }

    /// Ignores suggestedActions: every command is created here with a public
    /// selector, an English title and an SF Symbol.
    static func selfBuilt() -> UIMenu {
        let titles = ["cut": "Cut", "copy": "Copy", "paste": "Paste"]
        let edit: [UIMenuElement] = flutterDefaultItems.compactMap { item in
            guard let selector = basicSelector(item.type), let title = titles[item.type] else { return nil }
            return UICommand(title: title, image: UIImage(systemName: symbolName(item.type)), action: selector, propertyList: nil)
        }
        var children: [UIMenuElement] = []
        if let group = inlineGroup(edit, identifier: .standardEdit, size: .small) {
            children.append(group)
        }
        children.append(contentsOf: extraGroups(images: true, standardIdentifiers: true))
        return UIMenu(title: "", children: children)
    }

    // MARK: - Round 2: system groups filtered with public API only

    /// One entry of the ordered list the framework sends, as the round 2
    /// filter understands it.
    enum Request {
        /// cut, copy, paste, delete, selectAll: matched by the public
        /// UIResponderStandardEditActions selector.
        case edit(String)
        /// The whole `UIMenu.Identifier.lookup` group. Look Up and Translate
        /// both live in it and cannot be told apart with public API.
        case lookUp
        /// Same group as lookUp.
        case translate
        /// No public identifier or selector exists; skipped.
        case searchWeb
        /// The whole `UIMenu.Identifier.share` group.
        case share
        /// An app-defined UIAction (the framework's custom items).
        case custom(String)
    }

    static let requestAll: [Request] = [.edit("cut"), .edit("copy"), .edit("paste"), .lookUp, .searchWeb, .share]
    static let requestNoShare: [Request] = [.edit("cut"), .edit("copy"), .edit("paste"), .lookUp, .searchWeb]
    static let requestNoLookUp: [Request] = [.edit("cut"), .edit("copy"), .edit("paste"), .searchWeb, .share]
    static let requestWithCustom: [Request] = [
        .edit("cut"), .edit("copy"), .custom("Probe Action A"), .edit("paste"), .lookUp, .searchWeb, .share, .custom("Probe Action B"),
    ]

    /// Diagnostic only, NOT shippable: keeps only the lookup group commands
    /// whose selector name matches, to see what a Look Up row without
    /// Translate would look like. Comparing these names is the only way to
    /// tell the two apart; a shipped engine must not rely on them.
    static let diagnosticLookupSelectorNames: [String: String] = ["lookUp": "_define:", "translate": "_translate:"]

    static func topLevelGroup(_ identifier: UIMenu.Identifier, in suggested: [UIMenuElement]) -> UIMenu? {
        for element in suggested {
            if let menu = element as? UIMenu {
                if menu.identifier == identifier { return menu }
                if let found = topLevelGroup(identifier, in: menu.children) { return found }
            }
        }
        return nil
    }

    /// Returns UIKit's own groups and commands (titles, images, identifiers,
    /// options and sizes untouched), filtered and ordered by `request`:
    /// consecutive edit entries become one copy of the suggested
    /// `.standardEdit` group holding just those commands; lookUp/translate
    /// and share add the suggested `.lookup` / `.share` group whole, so iOS
    /// decides through canPerformAction which of its rows appear; custom
    /// entries become UIActions, either inside the current edit group
    /// (`splitAtCustom == false`) or as their own inline group. Everything
    /// uses public API except the `diagnosticLookupFilter` path.
    static func systemFiltered(
        _ suggested: [UIMenuElement],
        request: [Request],
        splitAtCustom: Bool = false,
        diagnosticLookupFilter: Bool = false
    ) -> UIMenu {
        let suggestedMenu = UIMenu(title: "", children: suggested)
        let editTemplate = topLevelGroup(.standardEdit, in: suggested)
        var children: [UIMenuElement] = []
        var currentEdit: [UIMenuElement] = []
        var editGroups = 0
        var addedLookup = false
        var lookupWanted: [String] = []
        var lookupIndex: Int?
        var addedShare = false

        func flushEdit() {
            guard !currentEdit.isEmpty else { return }
            let group: UIMenu
            if let editTemplate, editGroups == 0 {
                group = editTemplate.replacingChildren(currentEdit)
            } else {
                // A second edit segment gets its own identifier: one menu
                // should not hold two groups with the same identifier.
                group = UIMenu(
                    title: "", image: nil,
                    identifier: UIMenu.Identifier("dev.probe.menu.edit.\(editGroups)"),
                    options: .displayInline, children: currentEdit
                )
                group.preferredElementSize = editTemplate?.preferredElementSize ?? .medium
            }
            children.append(group)
            editGroups += 1
            currentEdit.removeAll()
        }

        func customAction(_ title: String) -> UIAction {
            UIAction(title: title) { _ in Probe.event("custom action \"\(title)\" performed") }
        }

        for item in request {
            switch item {
            case .edit(let type):
                if let selector = basicSelector(type), let command = searchCommand(selector, in: suggestedMenu) {
                    currentEdit.append(command)
                } else {
                    Probe.event("systemFiltered: no suggested command for \"\(type)\"")
                }
            case .custom(let title):
                if splitAtCustom || currentEdit.isEmpty {
                    flushEdit()
                    children.append(UIMenu(title: "", options: .displayInline, children: [customAction(title)]))
                } else {
                    currentEdit.append(customAction(title))
                }
            case .lookUp, .translate:
                flushEdit()
                lookupWanted.append(item.isLookUp ? "lookUp" : "translate")
                if !addedLookup, let group = topLevelGroup(.lookup, in: suggested) {
                    lookupIndex = children.count
                    children.append(group)
                    addedLookup = true
                }
            case .share:
                flushEdit()
                if !addedShare, let group = topLevelGroup(.share, in: suggested) {
                    children.append(group)
                    addedShare = true
                }
            case .searchWeb:
                Probe.event("systemFiltered: searchWeb has no public identifier or selector; left out")
            }
        }
        flushEdit()

        if diagnosticLookupFilter, let index = lookupIndex, let group = children[index] as? UIMenu {
            let names = Set(lookupWanted.compactMap { diagnosticLookupSelectorNames[$0] })
            let kept = group.children.filter { element in
                guard let command = element as? UICommand else { return false }
                return names.contains(NSStringFromSelector(command.action))
            }
            children[index] = group.replacingChildren(kept)
        }
        return UIMenu(title: "", children: children)
    }

    /// Sets `preferredImageVisibility = .visible` (iOS 27, set by key so the
    /// probe compiles with the iOS 26 SDK) on every element of the tree.
    /// Returns whether the property exists on this OS.
    @discardableResult
    static func makeImagesVisible(_ element: UIMenuElement) -> Bool {
        let setter = NSSelectorFromString("setPreferredImageVisibility:")
        guard element.responds(to: setter) else { return false }
        element.setValue(NSNumber(value: 1), forKey: "preferredImageVisibility")
        if let menu = element as? UIMenu {
            for child in menu.children {
                makeImagesVisible(child)
            }
        }
        return true
    }
}

extension MenuBuilders.Request {
    var isLookUp: Bool {
        if case .lookUp = self { return true }
        return false
    }
}
