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
