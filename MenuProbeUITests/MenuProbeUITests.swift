import XCTest

/// Drives every variant: launch, show the edit menu, screenshot the collapsed
/// bar, tap the chevron, screenshot the expanded menu. Each variant is its own
/// test method, so one failing variant does not stop the others. Nothing here
/// assumes the chevron's accessibility label: the full accessibility hierarchy
/// is saved before and after every tap, and three tap strategies are tried in
/// turn until the menu changes shape.
@MainActor
final class MenuProbeUITests: XCTestCase {
    func test_v00() { probe(0) }
    func test_v01() { probe(1) }
    func test_v02() { probe(2) }
    func test_v03() { probe(3) }
    func test_v04() { probe(4) }
    func test_v05() { probe(5) }
    func test_v06() { probe(6) }
    func test_v07() { probe(7) }
    func test_v08() { probe(8) }
    func test_v09() { probe(9) }
    func test_v10() { probe(10) }
    func test_v11() { probe(11) }
    func test_v12() { probe(12) }
    func test_v13() { probe(13) }
    func test_v14() { probe(14) }
    func test_v15() { probe(15) }

    // MARK: - Probe

    /// Titles of edit menu rows on iOS 16-27 in English. Only used to find the
    /// menu on screen; anything else in it is logged as well.
    static let knownTitles: Set<String> = [
        "Cut", "Copy", "Paste", "Delete", "Select", "Select All", "Replace…", "Replace...", "Replace",
        "Format", "AutoFill", "Look Up", "Translate", "Search Web", "Share", "Share…", "Share...",
        "Writing Tools", "Scan Text", "Speak", "Spell", "Learn", "Speech",
    ]

    /// The probe app's own elements, never menu parts.
    static let ownIdentifiers: Set<String> = [
        "variantTitle", "hostKind", "hypothesis", "status", "selectionRect", "presentButton",
        "nativeTextView", "customTextInput",
    ]

    private var outDir: URL {
        let path = ProcessInfo.processInfo.environment["PROBE_OUT"] ?? ""
        if !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("menu-probe-out")
    }

    private func probe(_ number: Int) {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = ["-variant", String(number)]
        app.launchEnvironment["PROBE_OUT"] = outDir.path
        app.launch()

        let titleLabel = app.staticTexts["variantTitle"]
        guard titleLabel.waitForExistence(timeout: 30) else {
            let tag = String(format: "v%02d-unknown", number)
            saveScreenshot("\(tag)-0-launch-failed")
            saveText("\(tag)-0-launch-failed-hierarchy", app.debugDescription)
            appendSummary("\(tag) | launch failed: variantTitle never appeared")
            XCTFail("\(tag): the app did not show its header")
            return
        }
        let tag = titleLabel.label
        let host = app.staticTexts["hostKind"].exists ? app.staticTexts["hostKind"].label : "?"
        var notes: [String] = ["host=\(host)"]

        // The custom view presents its menu 1.2 s after appearing.
        Thread.sleep(forTimeInterval: 2.5)
        var nodes = snapshotNodes(app)
        var shownBy = "auto"
        if menuItems(nodes).isEmpty {
            shownBy = showMenu(app, host: host, tag: tag, notes: &notes)
            nodes = snapshotNodes(app)
        }
        let collapsed = menuItems(nodes)
        saveScreenshot("\(tag)-1-collapsed")
        saveText("\(tag)-1-collapsed-hierarchy", describe(nodes) + "\n\n=== debugDescription\n" + app.debugDescription)
        notes.append("shownBy=\(shownBy)")
        notes.append("collapsed=[\(labels(collapsed))] span=\(Int(span(collapsed)))")

        guard !collapsed.isEmpty else {
            notes.append("no menu found; expanded step skipped")
            saveScreenshot("\(tag)-2-expanded")
            appendSummary("\(tag) | " + notes.joined(separator: " | "))
            XCTFail("\(tag): the edit menu did not appear")
            app.terminate()
            return
        }

        var expandedBy = "none"
        var before = collapsed
        var attempt = 0
        for strategy in ["labelled", "rightmostInContainer", "pastLastItem"] {
            attempt += 1
            guard let target = chevronTarget(strategy, nodes: nodes, app: app) else {
                notes.append("attempt\(attempt) \(strategy): no target")
                continue
            }
            notes.append("attempt\(attempt) \(strategy): tap \(target.description) at \(Int(target.point.x)),\(Int(target.point.y))")
            tap(app, at: target.point)
            Thread.sleep(forTimeInterval: 1.5)
            nodes = snapshotNodes(app)
            let after = menuItems(nodes)
            saveScreenshot("\(tag)-attempt\(attempt)-\(strategy)")
            saveText("\(tag)-attempt\(attempt)-\(strategy)-hierarchy", describe(nodes) + "\n\n=== debugDescription\n" + app.debugDescription)
            if after.isEmpty {
                notes.append("attempt\(attempt): menu dismissed; showing it again")
                _ = showMenu(app, host: host, tag: tag, notes: &notes)
                nodes = snapshotNodes(app)
                before = menuItems(nodes)
                continue
            }
            let changed = Set(after.map(\.label)) != Set(before.map(\.label)) || span(after) > span(before) + 30
            notes.append("attempt\(attempt): after=[\(labels(after))] span=\(Int(span(after))) changed=\(changed)")
            if changed {
                expandedBy = strategy
                break
            }
            before = after
        }

        saveScreenshot("\(tag)-2-expanded")
        saveText("\(tag)-2-expanded-hierarchy", describe(nodes) + "\n\n=== debugDescription\n" + app.debugDescription)
        notes.append("expandedBy=\(expandedBy)")
        appendSummary("\(tag) | " + notes.joined(separator: " | "))
        if expandedBy == "none" {
            XCTFail("\(tag): the menu did not change after any chevron tap; see the attempt screenshots")
        }
        app.terminate()
    }

    /// Shows the menu when it is not on screen: the Present button for the
    /// custom view; a tap, double tap and long press on the selected word for
    /// the UITextView.
    private func showMenu(_ app: XCUIApplication, host: String, tag: String, notes: inout [String]) -> String {
        if host == "custom" {
            let button = app.buttons["presentButton"]
            if button.exists {
                button.tap()
                Thread.sleep(forTimeInterval: 2.0)
                if !menuItems(snapshotNodes(app)).isEmpty { return "presentButton" }
            }
            notes.append("presentButton did not show the menu")
            return "failed"
        }
        guard let center = selectionCenter(app) else {
            notes.append("no selection rect published")
            return "failed"
        }
        let gestures: [(String, (XCUICoordinate) -> Void)] = [
            ("tapSelection", { $0.tap() }),
            ("doubleTapSelection", { $0.doubleTap() }),
            ("longPressSelection", { $0.press(forDuration: 0.9) }),
        ]
        for (name, gesture) in gestures {
            gesture(coordinate(app, center))
            Thread.sleep(forTimeInterval: 1.8)
            if !menuItems(snapshotNodes(app)).isEmpty { return name }
            notes.append("\(name) did not show the menu")
        }
        return "failed"
    }

    private func selectionCenter(_ app: XCUIApplication) -> CGPoint? {
        let label = app.staticTexts["selectionRect"]
        guard label.exists else { return nil }
        let parts = label.label.replacingOccurrences(of: "selection: ", with: "")
            .split(separator: " ").compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        return CGPoint(x: parts[0] + parts[2] / 2, y: parts[1] + parts[3] / 2)
    }

    // MARK: - Chevron search

    struct Target {
        let point: CGPoint
        let description: String
    }

    private func chevronTarget(_ strategy: String, nodes: [Node], app: XCUIApplication) -> Target? {
        let items = menuItems(nodes)
        guard !items.isEmpty else { return nil }
        let keyboard = nodes.filter { $0.type == .keyboard }.map(\.frame)
        let union = items.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        let band = union.insetBy(dx: -40, dy: -24)
        func outsideKeyboard(_ node: Node) -> Bool { !keyboard.contains { $0.intersects(node.frame) } }
        func plausible(_ node: Node) -> Bool {
            !node.frame.isEmpty && node.frame.width <= 90 && node.frame.height <= 90
                && !Self.ownIdentifiers.contains(node.identifier) && outsideKeyboard(node)
                && !Self.knownTitles.contains(node.label)
        }

        switch strategy {
        case "labelled":
            let pattern = try! NSRegularExpression(
                pattern: "(more|expand|chevron|forward|next|show|disclosure|overflow|additional|arrow)",
                options: .caseInsensitive
            )
            func matches(_ text: String) -> Bool {
                pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
            }
            let candidates = nodes.filter { node in
                plausible(node) && band.intersects(node.frame) && (matches(node.label) || matches(node.identifier))
            }
            let best = candidates.sorted { a, b in
                (a.type == .button ? 0 : 1, -a.frame.maxX) < (b.type == .button ? 0 : 1, -b.frame.maxX)
            }.first
            return best.map { Target(point: center($0.frame), description: "\($0.summary)") }

        case "rightmostInContainer":
            guard let container = lowestCommonAncestor(items, nodes: nodes),
                  container.frame.width < app.frame.width * 0.98 else { return nil }
            let lastItemX = items.map(\.frame.midX).max() ?? 0
            let candidates = nodes.filter { node in
                node.ancestors.contains(container.index) && plausible(node) && node.frame.midX > lastItemX
            }
            if let best = candidates.max(by: { $0.frame.maxX < $1.frame.maxX }) {
                return Target(point: center(best.frame), description: "\(best.summary) in container \(container.summary)")
            }
            return Target(
                point: CGPoint(x: container.frame.maxX - 18, y: container.frame.midY),
                description: "container trailing edge \(container.summary)"
            )

        default:
            let rightmost = items.max { $0.frame.maxX < $1.frame.maxX }!
            return Target(
                point: CGPoint(x: rightmost.frame.maxX + 18, y: rightmost.frame.midY),
                description: "18 pt past \(rightmost.summary)"
            )
        }
    }

    private func lowestCommonAncestor(_ items: [Node], nodes: [Node]) -> Node? {
        guard let first = items.first else { return nil }
        var common = first.ancestors
        for item in items.dropFirst() {
            common = common.filter { item.ancestors.contains($0) }
        }
        // Ancestors are stored root first, so the last common one is the lowest.
        guard let index = common.last else { return nil }
        return nodes.first { $0.index == index }
    }

    // MARK: - Accessibility snapshot

    struct Node {
        let index: Int
        let ancestors: [Int]
        let type: XCUIElement.ElementType
        let label: String
        let identifier: String
        let value: String
        let frame: CGRect

        var summary: String {
            "[\(MenuProbeUITests.typeName(type)) label=\"\(label)\" id=\"\(identifier)\" frame=\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width))x\(Int(frame.height))]"
        }
    }

    private func snapshotNodes(_ app: XCUIApplication) -> [Node] {
        guard let root = try? app.snapshot() else { return [] }
        var nodes: [Node] = []
        func walk(_ snapshot: XCUIElementSnapshot, ancestors: [Int]) {
            let index = nodes.count
            let value = snapshot.value.map { String(describing: $0) } ?? ""
            nodes.append(Node(
                index: index, ancestors: ancestors, type: snapshot.elementType,
                label: snapshot.label, identifier: snapshot.identifier, value: value, frame: snapshot.frame
            ))
            for child in snapshot.children {
                walk(child, ancestors: ancestors + [index])
            }
        }
        walk(root, ancestors: [])
        return nodes
    }

    /// Visible elements whose label is a known edit menu title, outside the
    /// keyboard and the app's own views.
    private func menuItems(_ nodes: [Node]) -> [Node] {
        let keyboard = nodes.filter { $0.type == .keyboard }.map(\.frame)
        let screen = nodes.first?.frame ?? .infinite
        return nodes.filter { node in
            Self.knownTitles.contains(node.label)
                && !Self.ownIdentifiers.contains(node.identifier)
                && !node.frame.isEmpty
                && screen.contains(CGPoint(x: node.frame.midX, y: node.frame.midY))
                && !keyboard.contains { $0.intersects(node.frame) }
        }
    }

    private func labels(_ nodes: [Node]) -> String {
        nodes.map(\.label).joined(separator: ", ")
    }

    private func span(_ nodes: [Node]) -> CGFloat {
        guard let minY = nodes.map(\.frame.minY).min(), let maxY = nodes.map(\.frame.maxY).max() else { return 0 }
        return maxY - minY
    }

    private func describe(_ nodes: [Node]) -> String {
        var lines = ["=== snapshot: \(nodes.count) nodes; known menu items: [\(labels(menuItems(nodes)))]"]
        for node in nodes {
            let indent = String(repeating: "  ", count: node.ancestors.count)
            let value = node.value.isEmpty ? "" : " value=\"\(node.value.prefix(60))\""
            lines.append("\(indent)#\(node.index) \(node.summary)\(value)")
        }
        return lines.joined(separator: "\n")
    }

    nonisolated static func typeName(_ type: XCUIElement.ElementType) -> String {
        let names: [XCUIElement.ElementType: String] = [
            .application: "application", .window: "window", .other: "other", .button: "button",
            .staticText: "staticText", .textView: "textView", .textField: "textField", .image: "image",
            .menu: "menu", .menuItem: "menuItem", .menuBar: "menuBar", .menuBarItem: "menuBarItem",
            .keyboard: "keyboard", .key: "key", .scrollView: "scrollView", .collectionView: "collectionView",
            .cell: "cell", .table: "table", .toolbar: "toolbar", .popover: "popover", .sheet: "sheet",
            .group: "group", .navigationBar: "navigationBar", .alert: "alert", .switch: "switch",
        ]
        return names[type] ?? "type\(type.rawValue)"
    }

    // MARK: - Output

    private func center(_ rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX, y: rect.midY)
    }

    private func coordinate(_ app: XCUIApplication, _ point: CGPoint) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: point.x, dy: point.y))
    }

    private func tap(_ app: XCUIApplication, at point: CGPoint) {
        coordinate(app, point).tap()
    }

    private func saveScreenshot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        write(screenshot.pngRepresentation, to: outDir.appendingPathComponent("screens/\(name).png"))
    }

    private func saveText(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        write(Data(text.utf8), to: outDir.appendingPathComponent("hierarchy/\(name).txt"))
    }

    private func appendSummary(_ line: String) {
        let file = outDir.appendingPathComponent("summary.txt")
        let data = Data((line + "\n").utf8)
        if FileManager.default.fileExists(atPath: file.path), let handle = try? FileHandle(forWritingTo: file) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            write(data, to: file)
        }
        let attachment = XCTAttachment(string: line)
        attachment.name = "summary"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func write(_ data: Data, to file: URL) {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            print("menu-probe: could not write \(file.path): \(error)")
        }
    }
}
