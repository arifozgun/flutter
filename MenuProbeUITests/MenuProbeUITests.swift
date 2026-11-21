import XCTest

/// Drives every variant. Three kinds of test, each its own method so one
/// failure never stops the others:
///
/// - `test_vNN`: launch, show the edit menu, screenshot the collapsed bar,
///   expand it (iOS 26+: one chevron tap opens a list) or page through it
///   (iOS 16-18: the chevron shows the next page of the bar), screenshot,
///   dismiss it, screenshot.
/// - `test_vNN_row_<row>`: show the menu, find the row (expanding or paging as
///   needed), tap it, screenshot what appears after about two seconds, try to
///   dismiss it, screenshot. The app records which selector was sent and which
///   UITextInput methods UIKit called.
/// - `test_vNN_gestures`: start without a menu, present it, then tap,
///   double-tap and long-press inside the text, and tap outside, with a
///   screenshot after each step. The app records selection changes,
///   UITextInput calls and view snapshots.
///
/// Nothing assumes the chevron's accessibility label: the full accessibility
/// hierarchy is saved around every tap, and three tap strategies are tried.
@MainActor
final class MenuProbeUITests: XCTestCase {
    // MARK: Menu shape, every variant

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
    func test_v16() { probe(16) }
    func test_v17() { probe(17) }
    func test_v18() { probe(18) }
    func test_v19() { probe(19) }
    func test_v20() { probe(20) }
    func test_v21() { probe(21) }
    func test_v22() { probe(22) }
    func test_v23() { probe(23) }
    func test_v24() { probe(24) }
    func test_v25() { probe(25) }
    func test_v26() { probe(26) }
    func test_v27() { probe(27) }
    func test_v28() { probe(28) }
    func test_v29() { probe(29) }
    func test_v30() { probe(30) }
    func test_v31() { probe(31) }

    // MARK: Row taps (question C): the native reference and the attachment
    // modes of question A

    func test_v00_row_lookUp() { rowTap(0, "Look Up") }
    func test_v00_row_searchWeb() { rowTap(0, "Search Web") }
    func test_v00_row_share() { rowTap(0, "Share") }
    func test_v00_row_translate() { rowTap(0, "Translate") }
    func test_v16_row_lookUp() { rowTap(16, "Look Up") }
    func test_v16_row_searchWeb() { rowTap(16, "Search Web") }
    func test_v16_row_share() { rowTap(16, "Share") }
    func test_v16_row_translate() { rowTap(16, "Translate") }
    func test_v17_row_lookUp() { rowTap(17, "Look Up") }
    func test_v17_row_searchWeb() { rowTap(17, "Search Web") }
    func test_v17_row_share() { rowTap(17, "Share") }
    func test_v17_row_translate() { rowTap(17, "Translate") }
    func test_v18_row_lookUp() { rowTap(18, "Look Up") }
    func test_v18_row_searchWeb() { rowTap(18, "Search Web") }
    func test_v18_row_share() { rowTap(18, "Share") }
    func test_v18_row_translate() { rowTap(18, "Translate") }
    func test_v19_row_lookUp() { rowTap(19, "Look Up") }
    func test_v19_row_searchWeb() { rowTap(19, "Search Web") }
    func test_v19_row_share() { rowTap(19, "Share") }
    func test_v19_row_translate() { rowTap(19, "Translate") }
    func test_v21_row_lookUp() { rowTap(21, "Look Up") }
    func test_v21_row_searchWeb() { rowTap(21, "Search Web") }
    func test_v21_row_share() { rowTap(21, "Share") }
    func test_v21_row_translate() { rowTap(21, "Translate") }
    func test_v22_row_lookUp() { rowTap(22, "Look Up") }
    func test_v22_row_searchWeb() { rowTap(22, "Search Web") }
    func test_v22_row_share() { rowTap(22, "Share") }
    func test_v22_row_translate() { rowTap(22, "Translate") }
    func test_v23_row_lookUp() { rowTap(23, "Look Up") }
    func test_v23_row_searchWeb() { rowTap(23, "Search Web") }
    func test_v23_row_share() { rowTap(23, "Share") }
    func test_v23_row_translate() { rowTap(23, "Translate") }

    // MARK: Gestures and side effects (question B)

    func test_v01_gestures() { gestures(1) }
    func test_v16_gestures() { gestures(16) }
    func test_v17_gestures() { gestures(17) }
    func test_v18_gestures() { gestures(18) }
    func test_v19_gestures() { gestures(19) }
    func test_v20_gestures() { gestures(20) }
    func test_v21_gestures() { gestures(21) }
    func test_v22_gestures() { gestures(22) }
    func test_v23_gestures() { gestures(23) }

    // MARK: - Shared data

    /// Titles of edit menu rows on iOS 16-27 in English. Only used to find the
    /// menu on screen; anything else in it is logged as well.
    static let knownTitles: Set<String> = [
        "Cut", "Copy", "Paste", "Delete", "Select", "Select All", "Replace…", "Replace...", "Replace",
        "Format", "AutoFill", "Look Up", "Translate", "Search Web", "Share", "Share…", "Share...",
        "Writing Tools", "Scan Text", "Speak", "Spell", "Learn", "Learn…", "Speech", "Find Selection",
        "Probe Action A", "Probe Action B",
    ]

    /// The probe app's own elements, never menu parts.
    static let ownIdentifiers: Set<String> = [
        "variantTitle", "hostKind", "hypothesis", "status", "selectionRect", "selectionRange", "tapPoints",
        "presentButton", "nativeTextView", "customTextInput", "renderedText",
    ]

    private var outDir: URL {
        let path = ProcessInfo.processInfo.environment["PROBE_OUT"] ?? ""
        if !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("menu-probe-out")
    }

    private static func stamp() -> String {
        String(format: "%.3f", Date().timeIntervalSince1970)
    }

    struct Launched {
        let app: XCUIApplication
        let tag: String
        let host: String
    }

    /// Launches one variant. `run` becomes `-probeRun` so the app writes its
    /// files under `<tag>-<run>`.
    private func launch(_ number: Int, run: String?, extraArguments: [String] = []) -> Launched? {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = ["-variant", String(number)] + extraArguments
        if let run {
            app.launchArguments += ["-probeRun", run]
        }
        app.launchEnvironment["PROBE_OUT"] = outDir.path
        app.launch()

        let titleLabel = app.staticTexts["variantTitle"]
        guard titleLabel.waitForExistence(timeout: 30) else {
            let tag = String(format: "v%02d-unknown", number) + (run.map { "-\($0)" } ?? "")
            saveScreenshot("\(tag)-0-launch-failed")
            saveText("\(tag)-0-launch-failed-hierarchy", app.debugDescription)
            appendSummary("\(tag) | launch failed: variantTitle never appeared")
            XCTFail("\(tag): the app did not show its header")
            app.terminate()
            return nil
        }
        let base = titleLabel.label
        let tag = run.map { "\(base)-\($0)" } ?? base
        let host = app.staticTexts["hostKind"].exists ? app.staticTexts["hostKind"].label : "?"
        return Launched(app: app, tag: tag, host: host)
    }

    // MARK: - Menu shape

    private func probe(_ number: Int) {
        guard let launched = launch(number, run: nil) else { return }
        let app = launched.app
        let tag = launched.tag
        let host = launched.host
        var notes: [String] = ["host=\(host)", "start=\(Self.stamp())"]

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
        var pages = 1
        strategies: for strategy in ["labelled", "rightmostInContainer", "pastLastItem"] {
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
            let grew = span(after) > span(before) + 30
            let relabelled = Set(after.map(\.label)) != Set(before.map(\.label))
            notes.append("attempt\(attempt): after=[\(labels(after))] span=\(Int(span(after))) grew=\(grew) relabelled=\(relabelled)")
            if grew {
                expandedBy = strategy
                break
            }
            if relabelled {
                // A horizontal bar that pages (iOS 16-18): keep paging with
                // the strategy that worked until a page repeats.
                expandedBy = "paged:\(strategy)"
                pages = 2
                saveScreenshot("\(tag)-2-page2")
                var seen: [Set<String>] = [Set(collapsed.map(\.label)), Set(after.map(\.label))]
                while pages < 8 {
                    guard let next = chevronTarget(strategy, nodes: nodes, app: app) else {
                        notes.append("page\(pages): no further target")
                        break
                    }
                    tap(app, at: next.point)
                    Thread.sleep(forTimeInterval: 1.3)
                    nodes = snapshotNodes(app)
                    let page = menuItems(nodes)
                    if page.isEmpty {
                        notes.append("page\(pages + 1): menu dismissed while paging")
                        break
                    }
                    let set = Set(page.map(\.label))
                    if seen.contains(set) {
                        notes.append("page\(pages + 1): repeats an earlier page; done")
                        break
                    }
                    pages += 1
                    seen.append(set)
                    notes.append("page\(pages)=[\(labels(page))]")
                    saveScreenshot("\(tag)-2-page\(pages)")
                    saveText("\(tag)-2-page\(pages)-hierarchy", describe(nodes))
                }
                break strategies
            }
            before = after
        }

        saveScreenshot("\(tag)-2-expanded")
        saveText("\(tag)-2-expanded-hierarchy", describe(nodes) + "\n\n=== debugDescription\n" + app.debugDescription)
        notes.append("expandedBy=\(expandedBy) pages=\(pages)")

        // Dismiss the menu with a tap on the header and look for anything
        // UIKit left on screen (caret, handles, highlight).
        tapNeutral(app)
        Thread.sleep(forTimeInterval: 1.5)
        let left = menuItems(snapshotNodes(app))
        saveScreenshot("\(tag)-3-dismissed")
        notes.append("afterDismiss=[\(labels(left))]")
        appendSummary("\(tag) | " + notes.joined(separator: " | "))
        if expandedBy == "none" {
            XCTFail("\(tag): the menu did not change after any chevron tap; see the attempt screenshots")
        }
        app.terminate()
    }

    // MARK: - Row taps

    private func rowTap(_ number: Int, _ row: String) {
        let key = row.replacingOccurrences(of: " ", with: "")
        let runKey = key.prefix(1).lowercased() + key.dropFirst()
        guard let launched = launch(number, run: "row-\(runKey)") else { return }
        let app = launched.app
        let tag = launched.tag
        var notes: [String] = ["host=\(launched.host)", "row=\(row)", "start=\(Self.stamp())"]
        defer {
            appendSummary("\(tag) | " + notes.joined(separator: " | "))
            app.terminate()
        }

        Thread.sleep(forTimeInterval: 2.5)
        if menuItems(snapshotNodes(app)).isEmpty {
            notes.append("shownBy=\(showMenu(app, host: launched.host, tag: tag, notes: &notes))")
        }
        guard !menuItems(snapshotNodes(app)).isEmpty else {
            notes.append("no menu")
            saveScreenshot("\(tag)-0-no-menu")
            return
        }

        guard let rowNode = revealRow(app, row: row, host: launched.host, tag: tag, notes: &notes) else {
            notes.append("result=absent")
            saveScreenshot("\(tag)-0-row-absent")
            saveText("\(tag)-0-row-absent-hierarchy", describe(snapshotNodes(app)))
            return
        }
        saveScreenshot("\(tag)-0-before-tap")
        notes.append("tap \(rowNode.summary) at \(Self.stamp())")
        tap(app, at: center(rowNode.frame))
        Thread.sleep(forTimeInterval: 2.2)

        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        notes.append("after: app.state=\(stateName(app.state)) safari.state=\(stateName(safari.state))")
        let afterNodes = snapshotNodes(app)
        notes.append("menuItemsAfter=[\(labels(menuItems(afterNodes)))]")
        let texts = afterNodes.filter { !$0.label.isEmpty && !Self.ownIdentifiers.contains($0.identifier) && $0.label != tagBase(tag) }
            .prefix(25).map(\.label)
        notes.append("labelsAfter=[\(texts.joined(separator: ", "))]")
        saveScreenshot("\(tag)-1-after-tap")
        saveText("\(tag)-1-after-tap-hierarchy", describe(afterNodes) + "\n\n=== debugDescription\n" + app.debugDescription)

        // Dismiss whatever the row opened.
        var dismissedBy = "nothing to dismiss"
        if app.state != .runningForeground {
            app.activate()
            dismissedBy = "activate (the row left the app)"
        } else if let button = ["Done", "Close", "Cancel", "Dismiss"].lazy.map({ app.buttons[$0] }).first(where: { $0.exists && $0.isHittable }) {
            dismissedBy = "button \(button.label)"
            button.tap()
        } else if menuItems(afterNodes).isEmpty {
            dismissedBy = "swipe down"
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        }
        Thread.sleep(forTimeInterval: 1.8)
        notes.append("dismissedBy=\(dismissedBy) then app.state=\(stateName(app.state))")
        saveScreenshot("\(tag)-2-after-dismiss")
    }

    /// Finds `row` in the menu, tapping the chevron (expand or next page) as
    /// needed. Returns nil when the menu does not offer it.
    private func revealRow(_ app: XCUIApplication, row: String, host: String, tag: String, notes: inout [String]) -> Node? {
        var lastSet: Set<String> = []
        for step in 0..<8 {
            let nodes = snapshotNodes(app)
            let items = menuItems(nodes)
            if items.isEmpty {
                notes.append("step\(step): menu gone; showing it again")
                _ = showMenu(app, host: host, tag: tag, notes: &notes)
                continue
            }
            if let match = rowNode(row, in: items) {
                notes.append("found at step\(step) among [\(labels(items))]")
                return match
            }
            let set = Set(items.map(\.label))
            if set == lastSet || span(items) > 100 {
                notes.append("step\(step): not offered; items=[\(labels(items))]")
                return nil
            }
            lastSet = set
            guard let target = chevronTarget("labelled", nodes: nodes, app: app)
                ?? chevronTarget("rightmostInContainer", nodes: nodes, app: app) else {
                notes.append("step\(step): no chevron; items=[\(labels(items))]")
                return nil
            }
            notes.append("step\(step): chevron \(target.description)")
            tap(app, at: target.point)
            Thread.sleep(forTimeInterval: 1.4)
        }
        return nil
    }

    private func rowNode(_ row: String, in items: [Node]) -> Node? {
        let matches = items.filter { $0.label == row || (row == "Share" && $0.label.hasPrefix("Share")) }
        return matches.first { $0.type == .menuItem || $0.type == .button || $0.type == .cell } ?? matches.first
    }

    private func tagBase(_ tag: String) -> String {
        String(tag.prefix { $0 != "-" })
    }

    private func stateName(_ state: XCUIApplication.State) -> String {
        switch state {
        case .unknown: return "unknown"
        case .notRunning: return "notRunning"
        case .runningBackgroundSuspended: return "backgroundSuspended"
        case .runningBackground: return "background"
        case .runningForeground: return "foreground"
        @unknown default: return "\(state.rawValue)"
        }
    }

    // MARK: - Gestures

    private func gestures(_ number: Int) {
        guard let launched = launch(number, run: "gestures", extraArguments: ["-noAutoPresent", "YES"]) else { return }
        let app = launched.app
        let tag = launched.tag
        var notes: [String] = ["host=\(launched.host)", "start=\(Self.stamp())"]
        defer {
            appendSummary("\(tag) | " + notes.joined(separator: " | "))
            app.terminate()
        }

        func step(_ name: String) {
            Thread.sleep(forTimeInterval: 1.5)
            let nodes = snapshotNodes(app)
            let range = app.staticTexts["selectionRange"].exists ? app.staticTexts["selectionRange"].label : "?"
            notes.append("\(name) at \(Self.stamp()): \(range) menu=[\(labels(menuItems(nodes)))]")
            saveScreenshot("\(tag)-\(name)")
            saveText("\(tag)-\(name)-hierarchy", describe(nodes))
        }

        Thread.sleep(forTimeInterval: 1.0)
        step("g0-before-menu")

        let present = app.buttons["presentButton"]
        if present.waitForExistence(timeout: 5) {
            present.tap()
        } else {
            notes.append("no Present button")
        }
        step("g1-menu-shown")

        guard let points = tapPoints(app), points.count >= 3 else {
            notes.append("no tap points published; gestures skipped")
            return
        }
        coordinate(app, points[0]).tap()
        step("g2-after-tap-ship")
        coordinate(app, points[1]).doubleTap()
        step("g3-after-doubletap-sailed")
        coordinate(app, points[2]).press(forDuration: 1.0)
        step("g4-after-longpress-into")
        tapNeutral(app)
        step("g5-after-tap-outside")
    }

    private func tapPoints(_ app: XCUIApplication) -> [CGPoint]? {
        let label = app.staticTexts["tapPoints"]
        guard label.exists else { return nil }
        let numbers = label.label.replacingOccurrences(of: "tapPoints: ", with: "")
            .split(separator: " ").compactMap { Double($0) }
        guard numbers.count >= 2, numbers.count % 2 == 0 else { return nil }
        return stride(from: 0, to: numbers.count, by: 2).map { CGPoint(x: numbers[$0], y: numbers[$0 + 1]) }
    }

    /// A tap on the variant header: outside the text and the menu.
    private func tapNeutral(_ app: XCUIApplication) {
        let header = app.staticTexts["hostKind"]
        if header.exists {
            coordinate(app, center(header.frame)).tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.08)).tap()
        }
    }

    // MARK: - Showing the menu

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
            let forward = try! NSRegularExpression(
                pattern: "(more|expand|chevron|forward|next|show|disclosure|overflow|additional|arrow)",
                options: .caseInsensitive
            )
            // The paging bar of iOS 16-18 also has a backward chevron.
            let backward = try! NSRegularExpression(pattern: "(back|previous|left)", options: .caseInsensitive)
            func matches(_ pattern: NSRegularExpression, _ text: String) -> Bool {
                pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
            }
            func isForward(_ text: String) -> Bool { matches(forward, text) && !matches(backward, text) }
            let candidates = nodes.filter { node in
                plausible(node) && band.intersects(node.frame) && (isForward(node.label) || isForward(node.identifier))
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
        var lines = ["=== snapshot at \(Self.stamp()): \(nodes.count) nodes; known menu items: [\(labels(menuItems(nodes)))]"]
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
