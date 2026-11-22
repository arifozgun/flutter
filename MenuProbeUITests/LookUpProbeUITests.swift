import UIKit
import XCTest

/// Drives the Look Up harness of the UIKit probe app (`-luVariant <id>`): is
/// "no first responder after closing Look Up on iPad iOS 17.5" what UIKit does
/// for its own text views too, or only for a custom view in the situation of
/// the Flutter engine prototype?
///
/// Every variant is its own test method and app launch. The app shows a text
/// view, a text field or a custom UITextInput view that holds the sample
/// sentence, is first responder and has the keyboard up. The test selects
/// "harbor" (a double tap for the native views; the custom views select it
/// and present the edit menu in the app), taps Look Up in the menu (behind the
/// chevron when it has to), waits until the Look Up UI is on screen, closes it
/// (a tap outside, then a downward swipe, then a close button; the first that
/// works is recorded) and reads the app's state 0.5 s, 2 s and 5 s after the
/// closing action: first responder, keyboard, selected range. One line per
/// variant goes to `summary.txt`. Nothing here fails a test except a launch
/// that never shows the screen, so one variant cannot stop the others.
@MainActor
final class LookUpProbeUITests: XCTestCase {
    func test_01_textview() { run("v1-textview") }
    func test_02_textfield() { run("v2-textfield") }
    func test_03_custom_permanent() { run("v3-custom-permanent") }
    func test_04_custom_prototype() { run("v4-custom-prototype") }
    func test_05_custom_late_removal() { run("v5-custom-late-removal") }
    func test_06_custom_stock() { run("v6-custom-stock") }

    // MARK: - Shared

    private var outDir: URL {
        let path = ProcessInfo.processInfo.environment["PROBE_OUT"] ?? ""
        if !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("menu-probe-out")
    }

    private static func now() -> Double {
        Date().timeIntervalSince1970
    }

    private static func stamp() -> String {
        String(format: "%.3f", now())
    }

    private var iosVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion)"
    }

    private var deviceName: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
    }

    private func pause(_ seconds: TimeInterval) {
        if seconds > 0 {
            Thread.sleep(forTimeInterval: seconds)
        }
    }

    private func pause(until time: Double) {
        pause(time - Self.now())
    }

    /// Titles of edit menu rows on iOS 16-27 in English. Only used to find
    /// the menu.
    static let knownTitles: Set<String> = [
        "Cut", "Copy", "Paste", "Delete", "Select", "Select All", "Replace…", "Replace...", "Replace",
        "Format", "AutoFill", "Look Up", "Translate", "Search Web", "Share", "Share…", "Share...",
        "Writing Tools", "Scan Text", "Speak", "Spell", "Learn", "Learn…", "Find Selection",
    ]

    // MARK: - One variant

    private func run(_ id: String) {
        continueAfterFailure = true
        let tag = "lu-\(id)"
        let native = id.hasPrefix("v1") || id.hasPrefix("v2")
        var notes: [String] = []
        let head = "\(tag) | device=\(deviceName) | ios=\(iosVersion)"
        let app = XCUIApplication()
        app.launchArguments = ["-luVariant", id]
        app.launchEnvironment["PROBE_OUT"] = outDir.path
        app.launch()

        guard waitForPhase(app, ["ready", "menuRequested"], timeout: 40) else {
            saveScreenshot("\(tag)-0-launch-failed")
            saveText("\(tag)-0-launch-failed-hierarchy", app.debugDescription)
            appendSummary("\(head) | lookUpTapped=unknown | launch failed: the app never reached phase ready")
            XCTFail("\(tag): the app did not show the harness screen")
            app.terminate()
            return
        }
        saveScreenshot("\(tag)-1-ready")
        let before = stateText(app)

        // Select "harbor" and get the edit menu.
        var select = "app (custom view)"
        if native {
            select = selectWord(app, notes: &notes)
        } else if !waitForPhase(app, ["menuRequested"], timeout: 30) {
            notes.append("phase menuRequested never came")
        }
        var nodes = waitForMenu(app, timeout: 3)
        if menuRows(nodes).isEmpty, native, let point = wordPoint(app) {
            tap(app, at: point)
            notes.append("no menu after the double tap; tapped the selection")
            nodes = waitForMenu(app, timeout: 3)
        }
        let afterSelect = stateText(app)
        saveScreenshot("\(tag)-2-menu")

        // Look Up.
        var menuNotes: [String] = []
        guard let row = revealRow(app, "Look Up", notes: &menuNotes) else {
            saveScreenshot("\(tag)-3-no-look-up")
            saveText("\(tag)-3-no-look-up-hierarchy", describe(snapshotNodes(app)))
            appendSummary(
                "\(head) | select=\(select) | beforeMenu=[\(before)] | afterSelect=[\(afterSelect)] | lookUpTapped=false"
                    + " | menu=[\(menuNotes.joined(separator: "; "))] | test=[\(notes.joined(separator: "; "))]"
            )
            app.terminate()
            return
        }
        let tapped = Self.now()
        tap(app, at: center(row.frame))
        pause(0.8)
        saveScreenshot("\(tag)-3-after-look-up-tap")

        // Wait for the Look Up UI.
        var opened: String?
        var openedAfter = 0.0
        while Self.now() - tapped < 15 {
            if let found = lookUpUI(app) {
                opened = found
                openedAfter = Self.now() - tapped
                break
            }
            pause(0.5)
        }
        if opened == nil {
            saveText("\(tag)-4-no-look-up-ui-hierarchy", describe(snapshotNodes(app)))
        } else {
            pause(1.0)
        }
        saveScreenshot("\(tag)-4-look-up-open")
        let whileOpen = stateText(app)

        // Close it, then read the state at 0.5 s, 2 s and 5 s.
        var closeMethod = "none"
        var attempts: [String] = []
        var t0 = Self.now()
        var samples: [String: String] = [:]
        if opened != nil {
            for method in ["tapOutside", "swipeDown", "closeButton"] {
                guard lookUpUI(app) != nil else { break }
                guard performClose(app, method, notes: &notes) else {
                    attempts.append("\(method):not possible")
                    continue
                }
                t0 = Self.now()
                pause(until: t0 + 0.5)
                let first = sample(app, tag: tag, name: "0.5", t0: t0)
                samples["0.5"] = first.text
                var closed = first.lookUp == nil
                while !closed, Self.now() < t0 + 1.8 {
                    pause(0.3)
                    closed = lookUpUI(app) == nil
                }
                attempts.append("\(method):\(closed ? "closed it" : "still open")")
                if closed {
                    closeMethod = method
                    break
                }
            }
        }
        if samples["0.5"] == nil {
            t0 = Self.now()
            pause(0.5)
            samples["0.5"] = sample(app, tag: tag, name: "0.5", t0: t0).text
        }
        pause(until: t0 + 2)
        samples["2"] = sample(app, tag: tag, name: "2", t0: t0).text
        pause(until: t0 + 5)
        let last = sample(app, tag: tag, name: "5", t0: t0)
        samples["5"] = last.text
        let restored = last.firstResponder.map { String($0) } ?? "unknown"

        appendSummary(
            "\(head) | select=\(select) | beforeMenu=[\(before)] | afterSelect=[\(afterSelect)] | menu=[\(menuNotes.joined(separator: "; "))]"
                + " | lookUpTapped=true | lookUpOnScreen=\(opened != nil) after=\(String(format: "%.1f", openedAfter))s via=\(opened ?? "-")"
                + " | whileOpen=[\(whileOpen)] | close=\(closeMethod) attempts=[\(attempts.joined(separator: ", "))]"
                + " | s0.5=[\(samples["0.5"] ?? "-")] | s2=[\(samples["2"] ?? "-")] | s5=[\(samples["5"] ?? "-")]"
                + " | restored=\(restored) | responder=[\(responderEvents(id, since: tapped))] | test=[\(notes.joined(separator: "; "))]"
        )
        app.terminate()
    }

    // MARK: - The app's labels

    private func readLabel(_ app: XCUIApplication, _ identifier: String) -> String? {
        let element = app.staticTexts[identifier]
        return element.exists ? element.label : nil
    }

    /// `key=value` pairs from a label ("firstResponder=true selection=10,6 ...").
    private func readState(_ app: XCUIApplication) -> [String: String] {
        guard let label = readLabel(app, "luState") else { return [:] }
        var values: [String: String] = [:]
        for part in label.split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1)
            if pair.count == 2 {
                values[String(pair[0])] = String(pair[1])
            }
        }
        return values
    }

    private func stateText(_ app: XCUIApplication) -> String {
        let values = readState(app)
        let keyboardUI = app.keyboards.firstMatch.exists
        guard !values.isEmpty else { return "firstResponder=unreadable keyboardUI=\(keyboardUI)" }
        return "firstResponder=\(values["firstResponder"] ?? "?") selection=\(values["selection"] ?? "?") keyboardUI=\(keyboardUI)"
            + " keyboardApp=\(values["keyboard"] ?? "?") presented=\(values["presented"] ?? "?")"
    }

    /// Waits until the phase label shows one of `phases`. A custom variant
    /// moves on from `ready` to `menuRequested` 1.4 s later, so `ready` must
    /// also be seen as already passed.
    private func waitForPhase(_ app: XCUIApplication, _ phases: [String], timeout: TimeInterval) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if let label = readLabel(app, "luPhase"), phases.contains(where: { label.hasPrefix("phase=\($0) ") }) {
                return true
            }
            pause(0.3)
        }
        return false
    }

    /// "tapPoints: word=x,y" from the app's `luTapPoints` label.
    private func wordPoint(_ app: XCUIApplication) -> CGPoint? {
        guard let label = readLabel(app, "luTapPoints") else { return nil }
        for part in label.split(separator: " ") where part.hasPrefix("word=") {
            let numbers = part.dropFirst(5).split(separator: ",").compactMap { Double($0) }
            if numbers.count == 2 {
                return CGPoint(x: numbers[0], y: numbers[1])
            }
        }
        return nil
    }

    /// Double taps "harbor" until the app reports the range 10,6. Returns how.
    private func selectWord(_ app: XCUIApplication, notes: inout [String]) -> String {
        guard let point = wordPoint(app) else {
            notes.append("no tap point for the word")
            return "failed: no tap point"
        }
        for (index, shift) in [0.0, 8.0, -8.0].enumerated() {
            doubleTap(app, at: CGPoint(x: point.x + shift, y: point.y))
            pause(1.0)
            if readState(app)["selection"] == "10,6" {
                return "doubleTap#\(index)"
            }
        }
        notes.append("the word was not selected by three double taps")
        return "failed: not selected"
    }

    // MARK: - Look Up UI, closing, samples

    /// What shows that the Look Up UI (a sheet or a popover) is on screen, or
    /// nil when it is not. The edit menu has none of these markers.
    private func lookUpUI(_ app: XCUIApplication) -> String? {
        guard app.state == .runningForeground else { return "appNotInFront" }
        let nodes = snapshotNodes(app)
        guard !nodes.isEmpty else { return "treeUnavailable" }
        for node in nodes {
            if node.type == .sheet || node.type == .popover || node.type == .navigationBar
                || node.label == "Sheet Grabber" || node.label == "dismiss popup"
                || node.identifier == "PopoverDismissRegion" || node.identifier == "DDUIDone" {
                return "marker \(Self.typeName(node.type)) \(node.label.isEmpty ? node.identifier : node.label)"
            }
        }
        if !nodes.contains(where: { $0.identifier == "luPhase" }) {
            return "ownElementsGone"
        }
        return nil
    }

    /// Performs one way of closing the Look Up UI. False when it cannot be tried.
    private func performClose(_ app: XCUIApplication, _ method: String, notes: inout [String]) -> Bool {
        switch method {
        case "tapOutside":
            // Near the top edge: outside a popover, above a sheet.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).tap()
            return true
        case "swipeDown":
            let bar = app.navigationBars.firstMatch
            let start: XCUICoordinate
            if bar.exists, !bar.frame.isEmpty {
                start = coordinate(app, center(bar.frame))
            } else {
                start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            }
            start.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
            return true
        default:
            guard let button = closeButton(app) else {
                notes.append("no close button found")
                return false
            }
            button.tap()
            return true
        }
    }

    /// A button that closes a sheet or card. A key of the keyboard is not one.
    private func closeButton(_ app: XCUIApplication) -> XCUIElement? {
        let predicate = NSPredicate(
            format: "label ==[c] 'Done' OR label ==[c] 'Close' OR label ==[c] 'Cancel' OR label ==[c] 'Dismiss' OR identifier == 'DDUIDone'"
        )
        let keyboard = app.keyboards.firstMatch
        let keyboardFrame = keyboard.exists ? keyboard.frame : .null
        return app.buttons.matching(predicate).allElementsBoundByIndex.first { button in
            button.exists && button.isHittable && !keyboardFrame.intersects(button.frame)
        }
    }

    struct Sample {
        let text: String
        /// The app's answer; nil when its labels cannot be read.
        let firstResponder: Bool?
        /// The Look Up UI marker still found, or nil.
        let lookUp: String?
    }

    /// The state `name` seconds after the closing action at `t0`, with a
    /// screenshot. The text says how late it really was.
    private func sample(_ app: XCUIApplication, tag: String, name: String, t0: Double) -> Sample {
        let values = readState(app)
        let state = stateText(app)
        let late = Self.now() - t0
        let lookUp = lookUpUI(app)
        saveScreenshot("\(tag)-5-closed-\(name)s")
        return Sample(
            text: "\(state) lookUp=\(lookUp ?? "none") at=+\(String(format: "%.2f", late))s",
            firstResponder: values["firstResponder"].map { $0 == "true" },
            lookUp: lookUp
        )
    }

    /// Every become/resign call of the view under test, from the app's
    /// `-responder.txt`, as `become=true@+0.31` (seconds after the Look Up tap),
    /// and how often canBecomeFirstResponder was asked.
    private func responderEvents(_ id: String, since: Double) -> String {
        let file = outDir.appendingPathComponent("trees/lu-\(id)-responder.txt")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return "no responder file" }
        var events: [String] = []
        var canBecome = 0
        for line in text.split(separator: "\n") where line.hasPrefix("[") {
            guard let close = line.firstIndex(of: "]"),
                  let time = Double(line[line.index(after: line.startIndex)..<close]) else { continue }
            let rest = line[close...]
            if rest.contains(" canBecomeFirstResponder -> ") {
                canBecome += 1
                continue
            }
            for kind in ["become", "resign"] {
                for result in ["true", "false"] where rest.contains(" \(kind)FirstResponder -> \(result) ") {
                    events.append("\(kind)=\(result)@\(String(format: "%+.2f", time - since))")
                }
            }
        }
        return "\(events.joined(separator: " ")) canBecome=\(canBecome)"
    }

    // MARK: - Accessibility snapshot and menu rows

    struct Node {
        let index: Int
        let ancestors: [Int]
        let type: XCUIElement.ElementType
        let label: String
        let identifier: String
        let frame: CGRect

        var summary: String {
            "[\(LookUpProbeUITests.typeName(type)) label=\"\(label)\" id=\"\(identifier)\" frame=\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width))x\(Int(frame.height))]"
        }
    }

    private func snapshotNodes(_ app: XCUIApplication) -> [Node] {
        guard let root = try? app.snapshot() else { return [] }
        var nodes: [Node] = []
        func walk(_ snapshot: XCUIElementSnapshot, ancestors: [Int]) {
            let index = nodes.count
            nodes.append(Node(
                index: index, ancestors: ancestors, type: snapshot.elementType,
                label: snapshot.label, identifier: snapshot.identifier, frame: snapshot.frame
            ))
            for child in snapshot.children {
                walk(child, ancestors: ancestors + [index])
            }
        }
        walk(root, ancestors: [])
        return nodes
    }

    private func isOwn(_ node: Node) -> Bool {
        node.identifier.hasPrefix("lu") || node.identifier == "acInput"
    }

    /// Visible elements whose label is a known menu title, outside the
    /// keyboard, the iPad keyboard's shortcut bar and the app's own elements.
    private func menuRows(_ nodes: [Node]) -> [Node] {
        let keyboard = nodes.filter { $0.type == .keyboard }.map(\.frame)
        let bars = Set(nodes.filter { $0.identifier == "SystemInputAssistantView" }.map(\.index))
        let screen = nodes.first?.frame ?? .infinite
        return nodes.filter { node in
            Self.knownTitles.contains(node.label)
                && !isOwn(node)
                && !node.frame.isEmpty
                && screen.contains(CGPoint(x: node.frame.midX, y: node.frame.midY))
                && !keyboard.contains { $0.intersects(node.frame) }
                && !node.ancestors.contains { bars.contains($0) }
        }
    }

    private func waitForMenu(_ app: XCUIApplication, timeout: TimeInterval) -> [Node] {
        let end = Date().addingTimeInterval(timeout)
        var nodes = snapshotNodes(app)
        while menuRows(nodes).isEmpty, Date() < end {
            pause(0.5)
            nodes = snapshotNodes(app)
        }
        return nodes
    }

    private func labels(_ nodes: [Node]) -> String {
        var result: [String] = []
        for node in nodes where result.last != node.label {
            result.append(node.label)
        }
        return result.joined(separator: ", ")
    }

    private func span(_ nodes: [Node]) -> CGFloat {
        guard let minY = nodes.map(\.frame.minY).min(), let maxY = nodes.map(\.frame.maxY).max() else { return 0 }
        return maxY - minY
    }

    private func lowestCommonAncestor(_ items: [Node], nodes: [Node]) -> Node? {
        guard let first = items.first else { return nil }
        var common = first.ancestors
        for item in items.dropFirst() {
            common = common.filter { item.ancestors.contains($0) }
        }
        guard let index = common.last else { return nil }
        return nodes.first { $0.index == index }
    }

    /// The chevron: on iOS 26 it opens a list, on iOS 16-18 it shows the next
    /// page of the bar. A button labelled like "Forward" first, then the
    /// rightmost small element in the rows' container.
    private func chevronTarget(nodes: [Node], app: XCUIApplication) -> CGPoint? {
        let items = menuRows(nodes)
        guard !items.isEmpty else { return nil }
        let keyboard = nodes.filter { $0.type == .keyboard }.map(\.frame)
        let union = items.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        let band = union.insetBy(dx: -40, dy: -24)
        func plausible(_ node: Node) -> Bool {
            !node.frame.isEmpty && node.frame.width <= 90 && node.frame.height <= 90 && !isOwn(node)
                && !keyboard.contains { $0.intersects(node.frame) } && !Self.knownTitles.contains(node.label)
        }
        let forward = try! NSRegularExpression(
            pattern: "(more|expand|chevron|forward|next|show|disclosure|overflow|additional|arrow)",
            options: .caseInsensitive
        )
        let backward = try! NSRegularExpression(pattern: "(back|previous|left)", options: .caseInsensitive)
        func matches(_ pattern: NSRegularExpression, _ text: String) -> Bool {
            pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
        func isForward(_ text: String) -> Bool { matches(forward, text) && !matches(backward, text) }
        let labelled = nodes.filter { node in
            plausible(node) && band.intersects(node.frame) && (isForward(node.label) || isForward(node.identifier))
        }.sorted { a, b in
            (a.type == .button ? 0 : 1, -a.frame.maxX) < (b.type == .button ? 0 : 1, -b.frame.maxX)
        }
        if let best = labelled.first {
            return center(best.frame)
        }
        guard let container = lowestCommonAncestor(items, nodes: nodes),
              container.frame.width < app.frame.width * 0.98 else { return nil }
        let lastItemX = items.map(\.frame.midX).max() ?? 0
        let candidates = nodes.filter { node in
            node.ancestors.contains(container.index) && plausible(node) && node.frame.midX > lastItemX
        }
        guard let best = candidates.max(by: { $0.frame.maxX < $1.frame.maxX }) else { return nil }
        return center(best.frame)
    }

    /// The rows really visible on the current page: the accessibility tree of
    /// a paged bar (iPad iOS 16-18) also lists rows of other pages, clipped by
    /// the bar or hidden under the page chevron.
    private func visibleRows(_ items: [Node], nodes: [Node], app: XCUIApplication) -> [Node] {
        let pageButtons = try! NSRegularExpression(pattern: "(forward|back|next|previous)", options: .caseInsensitive)
        let band = items.map(\.frame).reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -40, dy: -24)
        let chevrons = nodes.filter { node in
            node.type == .button && !node.frame.isEmpty && node.frame.width <= 90 && node.frame.height <= 90
                && band.intersects(node.frame)
                && pageButtons.firstMatch(in: node.label, range: NSRange(node.label.startIndex..., in: node.label)) != nil
        }.map(\.frame)
        var bar = app.frame
        if let container = lowestCommonAncestor(items, nodes: nodes), container.frame.width < app.frame.width * 0.98 {
            bar = container.frame
        }
        bar = bar.insetBy(dx: -1, dy: -1)
        return items.filter { item in
            bar.contains(item.frame) && !chevrons.contains { $0.intersection(item.frame).width > 1 }
        }
    }

    /// Finds `row` in the menu, tapping the chevron as needed. Nil when the
    /// menu does not offer it or is gone.
    private func revealRow(_ app: XCUIApplication, _ row: String, notes: inout [String]) -> Node? {
        var lastSet: Set<String> = []
        var lastSpan: CGFloat?
        for step in 0..<8 {
            let nodes = snapshotNodes(app)
            let all = menuRows(nodes)
            if all.isEmpty {
                notes.append("step\(step): menu gone")
                return nil
            }
            let items = visibleRows(all, nodes: nodes, app: app)
            if let match = items.first(where: { $0.label == row && ($0.type == .menuItem || $0.type == .button || $0.type == .cell) })
                ?? items.first(where: { $0.label == row }) {
                notes.append("\(row) found at step\(step) among [\(labels(items))]")
                return match
            }
            let set = Set(items.map(\.label))
            let grew = lastSpan.map { span(items) > $0 + 30 } ?? false
            if set == lastSet || grew {
                notes.append("step\(step): \(row) not offered; items=[\(labels(items))]")
                return nil
            }
            lastSet = set
            lastSpan = span(items)
            guard let target = chevronTarget(nodes: nodes, app: app) else {
                notes.append("step\(step): no chevron; items=[\(labels(items))]")
                return nil
            }
            notes.append("step\(step): chevron at \(Int(target.x)),\(Int(target.y)); items=[\(labels(items))]")
            tap(app, at: target)
            pause(1.4)
        }
        notes.append("\(row) not found after 8 steps")
        return nil
    }

    private func describe(_ nodes: [Node]) -> String {
        var lines = ["=== snapshot at \(Self.stamp()): \(nodes.count) nodes; menu rows: [\(labels(menuRows(nodes)))]"]
        for node in nodes {
            lines.append("\(String(repeating: "  ", count: node.ancestors.count))#\(node.index) \(node.summary)")
        }
        return lines.joined(separator: "\n")
    }

    nonisolated static func typeName(_ type: XCUIElement.ElementType) -> String {
        let names: [XCUIElement.ElementType: String] = [
            .application: "application", .window: "window", .other: "other", .button: "button",
            .staticText: "staticText", .textView: "textView", .textField: "textField",
            .image: "image", .menu: "menu", .menuItem: "menuItem", .keyboard: "keyboard", .key: "key",
            .scrollView: "scrollView", .cell: "cell", .toolbar: "toolbar", .popover: "popover",
            .sheet: "sheet", .group: "group", .navigationBar: "navigationBar", .alert: "alert",
        ]
        return names[type] ?? "type\(type.rawValue)"
    }

    // MARK: - Gestures

    private func center(_ rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX, y: rect.midY)
    }

    private func coordinate(_ app: XCUIApplication, _ point: CGPoint) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: point.x, dy: point.y))
    }

    private func tap(_ app: XCUIApplication, at point: CGPoint) {
        coordinate(app, point).tap()
    }

    private func doubleTap(_ app: XCUIApplication, at point: CGPoint) {
        coordinate(app, point).doubleTap()
    }

    // MARK: - Output

    private func saveScreenshot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        write(screenshot.pngRepresentation, to: outDir.appendingPathComponent("screens/\(name).png"))
    }

    private func saveText(_ name: String, _ text: String) {
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
    }

    private func write(_ data: Data, to file: URL) {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            print("look-up-probe: could not write \(file.path): \(error)")
        }
    }
}
