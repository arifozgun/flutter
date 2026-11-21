import XCTest

/// Drives the Flutter probe app (`flutter_app/`, bundle id `dev.probe.menuProbe`)
/// and records how the iOS system edit menu looks and behaves in it.
///
/// The UIKit probe app is not used. The Flutter app is installed by the
/// workflow (`flutter build ios --simulator`, `simctl install`) and started by
/// bundle id. Every scenario writes screenshots (`screens/`), accessibility
/// dumps (`hierarchy/`) and one or more lines of `summary.txt` under the
/// folder named by `PROBE_OUT`.
///
/// Reading the app: its status area (identifier `status`) has a label with the
/// focused field's id, text, selection and composing range, the selection's
/// rectangle and every word's rectangle in points. The tests use the word
/// rectangles to double tap a word, and the status to check the outcome of
/// every step. One scenario that cannot find what it needs records that and
/// returns; the other scenarios still run.
@MainActor
final class FlutterMenuUITests: XCTestCase {
    // MARK: - Scenarios

    func test_01_shape_single() { shape("single") }
    func test_01_shape_multi() { shape("multi") }
    func test_01_shape_obscured() { shape("obscured") }
    func test_01_shape_cupertino() { shape("cupertino") }
    func test_01_shape_custom() { shape("custom") }
    func test_01_shape_selectable() { shape("selectable") }

    func test_02_rows_lookUp() { rows("Look Up") }
    func test_02_rows_translate() { rows("Translate") }
    func test_02_rows_share() { rows("Share") }
    func test_02_rows_searchWeb() { rows("Search Web") }

    func test_03_edit_cutThenPaste() { editCutThenPaste() }
    func test_03_edit_copyThenPaste() { editCopyThenPaste() }
    func test_03_edit_selectAll() { editSelectAll() }

    func test_04_typingAfterMenuCycle() { typingAfterMenuCycle() }
    func test_05_cycles() { cycles() }
    func test_06_selectionChangeWhileShown() { selectionChangeWhileShown() }

    func test_07_autocorrect() { autocorrect() }

    // MARK: - Shared data

    static let defaultBundleID = "dev.probe.menuProbe"
    static let safariID = "com.apple.mobilesafari"

    /// How long a scenario waits for what a menu row opens (a sheet or Safari).
    static let settleWindow: TimeInterval = 6

    /// Titles of edit menu rows on iOS 16-27 in English, plus the probe's own
    /// custom items. Only used to find the menu; every other label in the menu
    /// is logged as well.
    static let knownTitles: Set<String> = [
        "Cut", "Copy", "Paste", "Delete", "Select", "Select All", "Replace…", "Replace...", "Replace",
        "Format", "AutoFill", "Look Up", "Translate", "Search Web", "Share", "Share…", "Share...",
        "Writing Tools", "Scan Text", "Speak", "Spell", "Learn", "Learn…", "Speech", "Find Selection",
        "Custom A", "Custom B",
    ]

    struct FieldSpec {
        let id: String
        /// The word to double tap; nil when the field shows bullets.
        let word: String?
        let text: String

        var identifier: String { "field-\(id)" }
    }

    static let sentence = "The quiet harbor sailed away"

    static let fieldSpecs: [FieldSpec] = [
        FieldSpec(id: "single", word: "harbor", text: sentence),
        FieldSpec(id: "multi", word: "beta", text: "Alpha beta\nGamma delta\nEpsilon zeta"),
        FieldSpec(id: "obscured", word: nil, text: "swordfish"),
        FieldSpec(id: "cupertino", word: "harbor", text: sentence),
        FieldSpec(id: "custom", word: "harbor", text: sentence),
        FieldSpec(id: "selectable", word: "harbor", text: sentence),
    ]

    static func spec(_ id: String) -> FieldSpec {
        fieldSpecs.first { $0.id == id }!
    }

    private var bundleID: String {
        let value = ProcessInfo.processInfo.environment["FLUTTER_APP_BUNDLE_ID"] ?? ""
        return value.isEmpty ? Self.defaultBundleID : value
    }

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

    private var iosVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion)"
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    // MARK: - Launch

    /// Runs a UI query that can hang while the app is not in front. Should it
    /// raise a failure, that is recorded as an expected one, so a query cannot
    /// fail the test. The scenarios also avoid such queries (see `inFront`).
    private func safely<T>(_ reason: String, _ fallback: T, _ body: () -> T) -> T {
        var result = fallback
        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        XCTExpectFailure(reason, options: options) {
            result = body()
        }
        return result
    }

    /// True while the probe app is the foreground app. Reading `state` does
    /// not walk the element tree, so it cannot hang.
    private func inFront(_ app: XCUIApplication) -> Bool {
        app.state == .runningForeground
    }

    private func waitForeground(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end, !inFront(app) {
            pause(0.3)
        }
        return inFront(app)
    }

    /// Terminates Safari when it is running. True when it was.
    @discardableResult
    private func stopSafari() -> Bool {
        let safari = XCUIApplication(bundleIdentifier: Self.safariID)
        switch safari.state {
        case .runningForeground, .runningBackground, .runningBackgroundSuspended:
            safely("terminate Safari", ()) { safari.terminate() }
            pause(1.0)
            return true
        default:
            return false
        }
    }

    /// Starts the Flutter app and waits for its first frame (the `supported`
    /// line). Records the failure and returns nil when it never appears. Safari
    /// is stopped first and the app is relaunched, so that every scenario
    /// starts from a clean state.
    private func launchApp(_ scenario: String) -> XCUIApplication? {
        continueAfterFailure = true
        stopSafari()
        let app = XCUIApplication(bundleIdentifier: bundleID)
        if app.state != .notRunning, app.state != .unknown {
            app.terminate()
        }
        app.launch()
        // The first frame of a debug build on a CI simulator can take a while.
        guard element(app, "supported").waitForExistence(timeout: 90) else {
            saveScreenshot("\(scenario)-0-launch-failed")
            saveText("\(scenario)-0-launch-failed-hierarchy", app.debugDescription)
            summary(scenario, ["RESULT=launch-failed: the app's `supported` element never appeared"])
            XCTFail("\(scenario): the Flutter app did not show its first screen")
            app.terminate()
            return nil
        }
        pause(1.0)
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func supportedLine(_ app: XCUIApplication) -> String {
        let el = element(app, "supported")
        return el.exists ? el.label : "?"
    }

    // MARK: - The app's status area

    struct Status {
        var raw = ""
        var field = "none"
        var focus = false
        var text = ""
        var base = -1
        var extent = -1
        var composing = "-1..-1"
        var custom = "-"
        var selRect: CGRect?
        var words: [(word: String, rect: CGRect)] = []

        var readable: Bool { !raw.isEmpty }

        var selectedText: String {
            guard base >= 0, extent >= 0, base != extent else { return "" }
            let units = Array(text.utf16)
            let a = min(base, extent)
            let b = max(base, extent)
            guard b <= units.count else { return "" }
            return String(decoding: units[a..<b], as: UTF16.self)
        }

        var oneLine: String {
            guard readable else { return "status unreadable" }
            let escaped = text.replacingOccurrences(of: "\n", with: "\\n")
            return "field=\(field) focus=\(focus) text=\"\(escaped)\" base=\(base) extent=\(extent) "
                + "composing=\(composing) custom=\(custom)"
        }

        func rect(of word: String) -> CGRect? {
            words.first { $0.word == word }?.rect
        }
    }

    private func readStatus(_ app: XCUIApplication) -> Status {
        let el = element(app, "status")
        guard el.exists else { return Status() }
        return Self.parseStatus(el.label)
    }

    static func parseStatus(_ raw: String) -> Status {
        var status = Status()
        status.raw = raw
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
            if line.hasPrefix("text=") {
                status.text = jsonString(String(line.dropFirst(5))) ?? ""
            } else if line.hasPrefix("selRect=") {
                status.selRect = parseRect(String(line.dropFirst(8)))
            } else if line.hasPrefix("words=") {
                let list = String(line.dropFirst(6))
                if list != "-" {
                    status.words = list.split(separator: ";").compactMap { (item: Substring) -> (word: String, rect: CGRect)? in
                        guard let at = item.firstIndex(of: "@"),
                              let rect = parseRect(String(item[item.index(after: at)...])) else { return nil }
                        return (word: String(item[..<at]), rect: rect)
                    }
                }
            } else {
                for token in line.split(separator: " ") {
                    let pair = token.split(separator: "=", maxSplits: 1).map(String.init)
                    guard pair.count == 2 else { continue }
                    switch pair[0] {
                    case "field": status.field = pair[1]
                    case "focus": status.focus = pair[1] == "true"
                    case "base": status.base = Int(pair[1]) ?? -1
                    case "extent": status.extent = Int(pair[1]) ?? -1
                    case "composing": status.composing = pair[1]
                    case "custom": status.custom = pair[1]
                    default: break
                    }
                }
            }
        }
        return status
    }

    private static func jsonString(_ literal: String) -> String? {
        guard let data = literal.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String
        else { return nil }
        return object
    }

    private static func parseRect(_ text: String) -> CGRect? {
        let numbers = text.split(separator: ",").compactMap { Double($0) }
        guard numbers.count == 4 else { return nil }
        return CGRect(x: numbers[0], y: numbers[1], width: numbers[2] - numbers[0], height: numbers[3] - numbers[1])
    }

    // MARK: - Accessibility snapshot and menu rows

    struct Node {
        let index: Int
        let ancestors: [Int]
        let type: XCUIElement.ElementType
        let label: String
        let identifier: String
        let value: String
        let frame: CGRect

        var summary: String {
            "[\(FlutterMenuUITests.typeName(type)) label=\"\(label)\" id=\"\(identifier)\" frame=\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width))x\(Int(frame.height))]"
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

    private func isOwn(_ node: Node) -> Bool {
        ["supported", "probe-reset", "probe-done", "status"].contains(node.identifier)
            || node.identifier.hasPrefix("field-")
    }

    /// Visible elements whose label is a known menu title, outside the keyboard
    /// and the app's own elements. A row usually shows up twice (the row and its
    /// label), so labels repeat.
    private func menuRows(_ nodes: [Node]) -> [Node] {
        let keyboard = nodes.filter { $0.type == .keyboard }.map(\.frame)
        let screen = nodes.first?.frame ?? .infinite
        return nodes.filter { node in
            Self.knownTitles.contains(node.label)
                && !isOwn(node)
                && !node.frame.isEmpty
                && screen.contains(CGPoint(x: node.frame.midX, y: node.frame.midY))
                && !keyboard.contains { $0.intersects(node.frame) }
        }
    }

    /// Labels in tree order, a repeated neighbour dropped.
    private func uniqueLabels(_ nodes: [Node]) -> [String] {
        var result: [String] = []
        for node in nodes where result.last != node.label {
            result.append(node.label)
        }
        return result
    }

    private func labels(_ nodes: [Node]) -> String {
        uniqueLabels(nodes).joined(separator: ", ")
    }

    /// Every label inside the menu's container, known title or not (shows rows
    /// this probe does not know, such as Writing Tools). Falls back to the
    /// known rows when the rows' common ancestor is the whole window.
    private func allMenuLabels(_ nodes: [Node], rows: [Node]) -> String {
        guard let first = rows.first else { return "" }
        var common = first.ancestors
        for row in rows.dropFirst() {
            common = common.filter { row.ancestors.contains($0) }
        }
        guard let containerIndex = common.last,
              let container = nodes.first(where: { $0.index == containerIndex }),
              container.frame.width < (nodes.first?.frame.width ?? 0) * 0.98 else {
            return labels(rows)
        }
        let inside = nodes.filter { $0.ancestors.contains(containerIndex) && !$0.label.isEmpty }
        return uniqueLabels(inside).joined(separator: ", ")
    }

    private func span(_ nodes: [Node]) -> CGFloat {
        guard let minY = nodes.map(\.frame.minY).min(), let maxY = nodes.map(\.frame.maxY).max() else { return 0 }
        return maxY - minY
    }

    private func describe(_ nodes: [Node]) -> String {
        var lines = ["=== snapshot at \(Self.stamp()): \(nodes.count) nodes; menu rows: [\(labels(menuRows(nodes)))]"]
        for node in nodes {
            let indent = String(repeating: "  ", count: node.ancestors.count)
            let value = node.value.isEmpty ? "" : " value=\"\(node.value.prefix(60))\""
            lines.append("\(indent)#\(node.index) \(node.summary)\(value)")
        }
        return lines.joined(separator: "\n")
    }

    /// A hierarchy dump with the full `debugDescription` below it.
    private func saveHierarchy(_ name: String, _ app: XCUIApplication, nodes: [Node]? = nil) {
        let list = nodes ?? snapshotNodes(app)
        saveText(name, describe(list) + "\n\n=== debugDescription\n" + app.debugDescription)
    }

    nonisolated static func typeName(_ type: XCUIElement.ElementType) -> String {
        let names: [XCUIElement.ElementType: String] = [
            .application: "application", .window: "window", .other: "other", .button: "button",
            .staticText: "staticText", .textView: "textView", .textField: "textField",
            .secureTextField: "secureTextField", .image: "image", .menu: "menu", .menuItem: "menuItem",
            .keyboard: "keyboard", .key: "key", .scrollView: "scrollView", .collectionView: "collectionView",
            .cell: "cell", .table: "table", .toolbar: "toolbar", .popover: "popover", .sheet: "sheet",
            .group: "group", .navigationBar: "navigationBar", .alert: "alert", .switch: "switch",
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

    private func drag(_ app: XCUIApplication, from: CGPoint, to: CGPoint) {
        coordinate(app, from).press(forDuration: 0.3, thenDragTo: coordinate(app, to))
    }

    // MARK: - Helper: reset, find a field, select a word

    /// Taps the app's Reset button: texts back, no focus, no keyboard. A menu or
    /// sheet that is still up can swallow the tap, so the status is checked
    /// (`field=none` after a reset) and the tap is repeated after clearing what
    /// is in the way. Returns what had to be done; empty when the first tap
    /// worked.
    @discardableResult
    private func resetApp(_ app: XCUIApplication) -> String {
        var extra: [String] = []
        for attempt in 1...4 {
            if !inFront(app) {
                app.activate()
                extra.append("activate")
                if !waitForeground(app, timeout: 8) {
                    extra.append("app not in front")
                    break
                }
            }
            let button = element(app, "probe-reset")
            if button.exists, !button.frame.isEmpty {
                tap(app, at: center(button.frame))
            }
            pause(1.1)
            let status = readStatus(app)
            if status.readable, status.field == "none" {
                break
            }
            extra.append("reset#\(attempt) not applied")
            guard attempt < 4 else { break }
            if attempt == 2 {
                extra.append("closed: \(backToApp(app))")
            } else {
                tapBlank(app)
            }
        }
        return extra.joined(separator: ", ")
    }

    /// A tap on the app's header text: it does nothing in the app, and it
    /// dismisses a menu that is still shown.
    private func tapBlank(_ app: XCUIApplication) {
        let label = element(app, "supported")
        if label.exists, !label.frame.isEmpty {
            tap(app, at: center(label.frame))
            pause(0.8)
        }
    }

    /// The field's frame in points: by identifier, else by the text it holds.
    private func fieldFrame(_ app: XCUIApplication, _ spec: FieldSpec) -> CGRect? {
        let el = element(app, spec.identifier)
        if el.exists, !el.frame.isEmpty {
            return el.frame
        }
        let nodes = snapshotNodes(app)
        if spec.id == "obscured" {
            return nodes.first { $0.type == .secureTextField }?.frame
        }
        let prefix = String(spec.text.prefix(12))
        return nodes.first { !isOwn($0) && $0.type != .staticText && $0.value.hasPrefix(prefix) }?.frame
    }

    /// Where to double tap: the word's rectangle from the app first, then a
    /// guess from the field's frame, each with a few sideways variations. A
    /// wrong tap is harmless: the result is checked against the status.
    private func candidatePoints(frame: CGRect, status: Status, spec: FieldSpec, word: String?) -> [CGPoint] {
        let inset: CGFloat = spec.id == "cupertino" ? 7 : 12
        let lineY = frame.minY + min(22, frame.height / 2)
        let base: CGPoint
        var width: CGFloat = 40
        if let word, status.field == spec.id, let rect = status.rect(of: word) {
            base = center(rect)
            width = rect.width
        } else if let word {
            let firstLine = spec.text.components(separatedBy: "\n")[0]
            let column = firstLine.range(of: word).map { firstLine.distance(from: firstLine.startIndex, to: $0.lowerBound) } ?? 0
            base = CGPoint(x: frame.minX + inset + 7.6 * (CGFloat(column) + CGFloat(word.count) / 2), y: lineY)
        } else {
            base = CGPoint(x: frame.minX + inset + 30, y: lineY)
        }
        let steps: [CGFloat] = [0, -width * 0.25, width * 0.25, -width * 0.5, width * 0.5, -width, width]
        return steps.map { CGPoint(x: base.x + $0, y: base.y) }
    }

    struct Selection {
        var ok: Bool
        var how: String
        var point: CGPoint?
        var status: Status
    }

    /// Resets the app, focuses the field with one tap, double taps `word`
    /// (any word when nil) until the status shows it selected. The system menu
    /// should be on screen after that; the caller checks. When a round fails,
    /// what is in the way (a leftover menu or sheet, the keyboard covering the
    /// field) is cleared and the round is repeated, up to three rounds.
    private func focusAndSelect(
        _ app: XCUIApplication, _ spec: FieldSpec, word: String?, reset: Bool = true
    ) -> Selection {
        var recovery: [String] = []
        if reset {
            let done = resetApp(app)
            if !done.isEmpty {
                recovery.append("reset: \(done)")
            }
        }
        var result = Selection(ok: false, how: "not-tried", point: nil, status: readStatus(app))
        for round in 1...3 {
            if round > 1 {
                recovery.append("round\(round) after \(result.how): \(recoverForSelection(app, reset: reset))")
            }
            result = selectOnce(app, spec, word: word)
            if result.ok {
                break
            }
        }
        if !recovery.isEmpty {
            result.how += "; recovery: " + recovery.joined(separator: "; ")
        }
        return result
    }

    /// True when the point lies under the app's status area (which sits on top
    /// of the keyboard), where a tap does not reach the field.
    private func hiddenBehindStatus(_ app: XCUIApplication, y: CGFloat) -> Bool {
        let area = element(app, "status")
        return area.exists && !area.frame.isEmpty && y > area.frame.minY - 2
    }

    /// Clears a leftover menu, sheet or keyboard before another round.
    private func recoverForSelection(_ app: XCUIApplication, reset: Bool) -> String {
        var done: [String] = []
        if !inFront(app) {
            app.activate()
            done.append("activate")
            if !waitForeground(app, timeout: 8) {
                done.append("app not in front")
                return done.joined(separator: ", ")
            }
        }
        let closed = backToApp(app)
        if closed != "nothing to dismiss" {
            done.append("closed: \(closed)")
        }
        tapBlank(app)
        done.append("tap blank")
        if reset {
            let again = resetApp(app)
            done.append(again.isEmpty ? "reset" : "reset (\(again))")
        } else {
            let button = element(app, "probe-done")
            if button.exists, !button.frame.isEmpty {
                tap(app, at: center(button.frame))
                pause(1.0)
                done.append("Done tapped (keyboard down, texts kept)")
            }
        }
        return done.joined(separator: ", ")
    }

    private func selectOnce(_ app: XCUIApplication, _ spec: FieldSpec, word: String?) -> Selection {
        guard let frame = fieldFrame(app, spec) else {
            return Selection(ok: false, how: "field-not-found", point: nil, status: readStatus(app))
        }
        let focusY = frame.minY + min(22, frame.height / 2)
        if hiddenBehindStatus(app, y: focusY) {
            return Selection(ok: false, how: "field-hidden-before-focus", point: nil, status: readStatus(app))
        }
        // One tap focuses the field and brings it above the keyboard.
        tap(app, at: CGPoint(x: frame.minX + 24, y: focusY))
        pause(1.3)
        var moved = fieldFrame(app, spec) ?? frame
        var status = readStatus(app)
        if status.field != spec.id {
            // The focus tap did not reach the field; once more.
            tap(app, at: CGPoint(x: moved.minX + 24, y: moved.minY + min(22, moved.height / 2)))
            pause(1.3)
            moved = fieldFrame(app, spec) ?? moved
            status = readStatus(app)
        }
        if hiddenBehindStatus(app, y: moved.minY + min(22, moved.height / 2)) {
            return Selection(ok: false, how: "field-hidden-after-focus", point: nil, status: status)
        }
        let points = candidatePoints(frame: moved, status: status, spec: spec, word: word)
        for (index, point) in points.enumerated() {
            doubleTap(app, at: point)
            pause(1.0)
            status = readStatus(app)
            if status.field == spec.id, status.base != status.extent, word == nil || status.selectedText == word {
                return Selection(ok: true, how: "doubleTap#\(index)", point: point, status: status)
            }
        }
        return Selection(ok: false, how: "word-not-selected after \(points.count) double taps", point: nil, status: status)
    }

    /// Waits until a menu row is on screen. Returns the last snapshot.
    private func waitForMenu(_ app: XCUIApplication, timeout: TimeInterval = 3) -> [Node] {
        let end = Date().addingTimeInterval(timeout)
        var nodes = snapshotNodes(app)
        while menuRows(nodes).isEmpty, Date() < end {
            pause(0.5)
            nodes = snapshotNodes(app)
        }
        return nodes
    }

    // MARK: - Helper: expand the menu, find and tap rows

    struct Target {
        let point: CGPoint
        let description: String
    }

    /// The chevron: on iOS 26 it opens a list, on iOS 16-18 it shows the next
    /// page of the bar. In round 2 of the UIKit probe it was a button labelled
    /// "Forward" on both. Tries the label first, then the rightmost small
    /// element in the menu's container.
    private func chevronTarget(nodes: [Node], app: XCUIApplication) -> Target? {
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
        // The paging bar of iOS 16-18 also has a backward chevron.
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
            return Target(point: center(best.frame), description: best.summary)
        }
        // Rightmost small element beside the last row, inside the rows' container.
        guard let container = lowestCommonAncestor(items, nodes: nodes),
              container.frame.width < app.frame.width * 0.98 else { return nil }
        let lastItemX = items.map(\.frame.midX).max() ?? 0
        let candidates = nodes.filter { node in
            node.ancestors.contains(container.index) && plausible(node) && node.frame.midX > lastItemX
        }
        guard let best = candidates.max(by: { $0.frame.maxX < $1.frame.maxX }) else { return nil }
        return Target(point: center(best.frame), description: "\(best.summary) (rightmost in container)")
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

    struct Expansion {
        var pages: [[String]] = []
        var mode = "none"
        var notes: [String] = []
    }

    /// Taps the chevron until the menu is a list, or its pages repeat, or there
    /// is no chevron left. Screenshots every page (`<tag>-2-pageN`) and the
    /// final state (`<tag>-2-expanded`).
    private func expandMenu(_ app: XCUIApplication, tag: String) -> Expansion {
        var result = Expansion()
        var nodes = snapshotNodes(app)
        var before = menuRows(nodes)
        result.pages = [uniqueLabels(before)]
        for _ in 0..<8 {
            guard let target = chevronTarget(nodes: nodes, app: app) else {
                result.notes.append("no further chevron")
                break
            }
            result.notes.append("tap \(target.description)")
            tap(app, at: target.point)
            pause(1.4)
            nodes = snapshotNodes(app)
            let rows = menuRows(nodes)
            if rows.isEmpty {
                result.notes.append("menu gone after the chevron tap")
                result.mode += result.mode == "none" ? "dismissed" : "+dismissed"
                break
            }
            if span(rows) > span(before) + 30 {
                result.pages.append(uniqueLabels(rows))
                result.mode = "list"
                saveScreenshot("\(tag)-2-expanded")
                saveHierarchy("\(tag)-2-expanded-hierarchy", app, nodes: nodes)
                return result
            }
            let set = Set(rows.map(\.label))
            if result.pages.contains(where: { Set($0) == set }) {
                result.notes.append("page repeats an earlier one")
                break
            }
            result.pages.append(uniqueLabels(rows))
            result.mode = "paged"
            saveScreenshot("\(tag)-2-page\(result.pages.count)")
            saveText("\(tag)-2-page\(result.pages.count)-hierarchy", describe(nodes))
            before = rows
        }
        saveScreenshot("\(tag)-2-expanded")
        saveHierarchy("\(tag)-2-expanded-hierarchy", app, nodes: nodes)
        return result
    }

    private func rowNode(_ row: String, in items: [Node]) -> Node? {
        let matches = items.filter { $0.label == row || (row == "Share" && $0.label.hasPrefix("Share")) }
        return matches.first { $0.type == .menuItem || $0.type == .button || $0.type == .cell } ?? matches.first
    }

    /// Finds `row` in the menu, tapping the chevron as needed. Nil when the
    /// menu does not offer it or is gone.
    private func revealRow(_ app: XCUIApplication, _ row: String, notes: inout [String]) -> Node? {
        var lastSet: Set<String> = []
        for step in 0..<8 {
            let nodes = snapshotNodes(app)
            let items = menuRows(nodes)
            if items.isEmpty {
                notes.append("step\(step): menu gone")
                return nil
            }
            if let match = rowNode(row, in: items) {
                notes.append("\(row) found at step\(step) among [\(labels(items))]")
                return match
            }
            let set = Set(items.map(\.label))
            if set == lastSet || span(items) > 100 {
                notes.append("step\(step): \(row) not offered; items=[\(labels(items))]")
                return nil
            }
            lastSet = set
            guard let target = chevronTarget(nodes: nodes, app: app) else {
                notes.append("step\(step): no chevron; items=[\(labels(items))]")
                return nil
            }
            tap(app, at: target.point)
            pause(1.4)
        }
        return nil
    }

    /// Reveals and taps a row. False when it was not there.
    private func menuTap(_ app: XCUIApplication, _ row: String, notes: inout [String]) -> Bool {
        guard let node = revealRow(app, row, notes: &notes) else { return false }
        tap(app, at: center(node.frame))
        return true
    }

    // MARK: - Helper: dismiss what a row opened

    /// A button that closes a sheet or card. The app's own Done button (it
    /// puts the keyboard away) is not one.
    private func closeButton(_ app: XCUIApplication) -> XCUIElement? {
        let predicate = NSPredicate(
            format: "(label ==[c] 'Done' OR label ==[c] 'Close' OR label ==[c] 'Cancel' OR label ==[c] 'Dismiss') "
                + "AND identifier != 'probe-done'"
        )
        let button = app.buttons.matching(predicate).firstMatch
        return button.exists && button.isHittable ? button : nil
    }

    /// True when the app's own screen is reachable (nothing covers it).
    private func appScreenClear(_ app: XCUIApplication) -> Bool {
        let label = element(app, "supported")
        return inFront(app) && label.exists && label.isHittable
    }

    /// Closes a sheet or card that a menu row opened and gets back to the app;
    /// relaunches it as a last resort. Returns what was done. When the app is
    /// not in front (Safari), it is brought back first and nothing in its tree
    /// is queried before it is.
    private func backToApp(_ app: XCUIApplication) -> String {
        var done: [String] = []
        for attempt in 1...3 {
            if !inFront(app) {
                app.activate()
                done.append("activate")
                _ = waitForeground(app, timeout: 8)
                pause(1.0)
            } else if let button = closeButton(app) {
                done.append("button \(button.label)")
                button.tap()
                pause(1.5)
            } else if appScreenClear(app) {
                break
            } else if attempt == 1, element(app, "PopoverDismissRegion").exists {
                // A popover (the share sheet of iOS 26) closes by a tap outside it.
                done.append("tap outside")
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).tap()
                pause(1.8)
            } else {
                done.append("swipe down")
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
                    .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
                pause(1.8)
            }
            if appScreenClear(app) {
                break
            }
            if attempt == 3 {
                done.append("relaunch")
                stopSafari()
                app.terminate()
                app.launch()
                _ = element(app, "supported").waitForExistence(timeout: 60)
                pause(1.0)
            }
        }
        return done.isEmpty ? "nothing to dismiss" : done.joined(separator: ", ")
    }

    // MARK: - Helper: typing

    private func keyboardShown(_ app: XCUIApplication) -> Bool {
        app.keyboards.firstMatch.exists
    }

    /// Types on the software keyboard by tapping its keys (letters and the
    /// space bar); anything else goes through typeText. Returns how.
    @discardableResult
    private func typeText(_ app: XCUIApplication, _ text: String) -> String {
        guard keyboardShown(app) else { return "no keyboard on screen; nothing typed" }
        var viaKeys = 0
        var viaTypeText = 0
        for character in text {
            let name = character == " " ? "space" : String(character)
            let key = app.keys[name]
            if key.exists, key.isHittable {
                key.tap()
                viaKeys += 1
            } else {
                app.typeText(String(character))
                viaTypeText += 1
            }
            pause(0.15)
        }
        pause(0.9)
        return "keys=\(viaKeys) typeText=\(viaTypeText)"
    }

    /// The suggestions in the keyboard's prediction bar, one node per label.
    private func predictionCandidates(_ nodes: [Node]) -> [Node] {
        guard let bar = nodes.first(where: { $0.label == "Typing Predictions" }) else { return [] }
        var seen = Set<String>()
        return nodes.filter { node in
            node.ancestors.contains(bar.index) && !node.label.isEmpty && seen.insert(node.label).inserted
        }
    }

    // MARK: - Scenario: shape

    private func shape(_ id: String) {
        let spec = Self.spec(id)
        let scenario = "shape-\(id)"
        guard let app = launchApp(scenario) else { return }
        defer { app.terminate() }
        var notes = ["start=\(Self.stamp())", supportedLine(app)]

        let selection = focusAndSelect(app, spec, word: spec.word)
        notes.append("select=\(selection.ok ? "ok" : "FAILED") (\(selection.how)) status: \(selection.status.oneLine)")
        let nodes = waitForMenu(app)
        let rows = menuRows(nodes)
        saveScreenshot("\(scenario)-1-collapsed")
        saveHierarchy("\(scenario)-1-collapsed-hierarchy", app, nodes: nodes)
        guard !rows.isEmpty else {
            notes.append("RESULT=no-menu (see the screenshot and hierarchy)")
            summary(scenario, notes)
            return
        }
        notes.append("collapsed=[\(labels(rows))] all=[\(allMenuLabels(nodes, rows: rows))]")
        let expansion = expandMenu(app, tag: scenario)
        notes.append("mode=\(expansion.mode) pages=\(expansion.pages.count)")
        for (index, page) in expansion.pages.enumerated() {
            notes.append("page\(index + 1)=[\(page.joined(separator: ", "))]")
        }
        notes.append("steps: \(expansion.notes.joined(separator: "; "))")
        notes.append("RESULT=\(selection.ok ? "ok" : "partial")")
        summary(scenario, notes)
    }

    // MARK: - Scenario: rows

    /// Taps one row in the default field and in the custom-items field. Each of
    /// the two starts from a clean state: Safari stopped, the app relaunched.
    private func rows(_ row: String) {
        let key = row.replacingOccurrences(of: " ", with: "")
        let runKey = key.prefix(1).lowercased() + key.dropFirst()
        for id in ["single", "custom"] {
            let scenario = "rows-\(runKey)-\(id)"
            guard let app = launchApp(scenario) else { continue }
            rowTap(app, Self.spec(id), row, scenario: scenario)
            app.terminate()
            stopSafari()
        }
    }

    /// Markers of a sheet, a popover or a card that a row opened. The menu
    /// itself has none of them.
    private func sheetLike(_ nodes: [Node]) -> Bool {
        nodes.contains { node in
            node.type == .sheet || node.type == .popover || node.type == .navigationBar
                || node.label == "Sheet Grabber" || node.label == "dismiss popup"
                || node.identifier == "PopoverDismissRegion" || node.identifier == "DDUIDone"
                || node.identifier.hasPrefix("ShareSheet")
                || (node.type == .button && ["close", "Close"].contains(node.label))
        }
    }

    /// A sheet that still shows its progress indicator.
    private func sheetLoading(_ nodes: [Node]) -> Bool {
        nodes.contains { $0.label == "In progress" }
    }

    struct AfterTap {
        var outcome = "nothing-visible"
        var sheetLike = false
        var loading = false
        var foundAfter: TimeInterval?
        var polls = 0
        /// The last tree read while the probe app was in front.
        var nodes: [Node] = []
        var treeRead = false
    }

    /// Watches what a tapped row opens for up to `settleWindow` seconds. The
    /// probe app's tree is read only while the app is in front, and not at all
    /// for Search Web (which leaves for Safari) until the wait is over, so no
    /// query can hang on an app that went to the background. The outcome comes
    /// from the application states and, for sheets, the tree.
    private func observeAfterTap(_ app: XCUIApplication, row: String) -> AfterTap {
        let safari = XCUIApplication(bundleIdentifier: Self.safariID)
        let expectsSafari = row == "Search Web"
        let begin = Date()
        var result = AfterTap()
        pause(0.5)
        while true {
            result.polls += 1
            let elapsed = Date().timeIntervalSince(begin)
            if safari.state == .runningForeground {
                result.outcome = "safari"
                result.foundAfter = elapsed
                break
            }
            if !inFront(app) {
                result.outcome = "left-the-app"
            } else if !expectsSafari {
                let nodes = safely("snapshot while polling", [Node]()) { snapshotNodes(app) }
                result.nodes = nodes
                result.treeRead = true
                result.sheetLike = sheetLike(nodes)
                result.loading = sheetLoading(nodes)
                if result.sheetLike {
                    result.outcome = "sheet"
                    if result.foundAfter == nil {
                        result.foundAfter = elapsed
                    }
                    if !result.loading {
                        break
                    }
                } else if !menuRows(nodes).isEmpty {
                    result.outcome = "menu-still-shown"
                } else {
                    result.outcome = "nothing-visible"
                }
            }
            if elapsed >= Self.settleWindow {
                break
            }
            pause(0.5)
        }
        if result.outcome == "safari" {
            // Let Safari draw something before the screenshot.
            pause(1.0)
        } else if result.outcome == "sheet", inFront(app) {
            // The sheet's content draws after its frame appears.
            pause(1.5)
        }
        if safari.state != .runningForeground, inFront(app) {
            if expectsSafari || result.outcome == "sheet" {
                result.nodes = safely("snapshot after waiting", [Node]()) { snapshotNodes(app) }
                result.treeRead = true
                result.sheetLike = sheetLike(result.nodes)
                result.loading = sheetLoading(result.nodes)
                if expectsSafari, result.outcome != "safari" {
                    if result.sheetLike {
                        result.outcome = "sheet"
                    } else if !menuRows(result.nodes).isEmpty {
                        result.outcome = "menu-still-shown"
                    } else {
                        result.outcome = "nothing-visible"
                    }
                }
            }
        }
        return result
    }

    /// Gets the probe app back to the front after a row took the screen (Safari,
    /// a sheet) and closes what is left. Nothing in the app's tree is queried
    /// before it is in front and running.
    private func returnToApp(_ app: XCUIApplication) -> String {
        var done: [String] = []
        let safari = XCUIApplication(bundleIdentifier: Self.safariID)
        if safari.state == .runningForeground || !inFront(app) {
            for attempt in 1...3 {
                app.activate()
                done.append("activate")
                if waitForeground(app, timeout: 8) {
                    break
                }
                if attempt == 2, stopSafari() {
                    done.append("stop Safari")
                }
            }
            pause(1.0)
        }
        if inFront(app) {
            let closed = backToApp(app)
            if closed != "nothing to dismiss" || done.isEmpty {
                done.append(closed)
            }
        } else {
            done.append("app not in front: relaunch")
            stopSafari()
            app.terminate()
            app.launch()
            _ = element(app, "supported").waitForExistence(timeout: 60)
            pause(1.0)
        }
        return done.joined(separator: ", ")
    }

    private func rowTap(_ app: XCUIApplication, _ spec: FieldSpec, _ row: String, scenario: String) {
        var notes = ["row=\(row)", "start=\(Self.stamp())"]
        defer { summary(scenario, notes) }

        let selection = focusAndSelect(app, spec, word: spec.word)
        notes.append("select=\(selection.ok ? "ok" : "FAILED") (\(selection.how))")
        guard !menuRows(waitForMenu(app)).isEmpty else {
            notes.append("RESULT=no-menu")
            saveScreenshot("\(scenario)-0-no-menu")
            return
        }
        guard let node = revealRow(app, row, notes: &notes) else {
            notes.append("RESULT=row-absent")
            saveScreenshot("\(scenario)-0-row-absent")
            saveText("\(scenario)-0-row-absent-hierarchy", describe(snapshotNodes(app)))
            return
        }
        saveScreenshot("\(scenario)-0-before-tap")
        notes.append("tap \(node.summary) at \(Self.stamp())")
        tap(app, at: center(node.frame))

        let observed = observeAfterTap(app, row: row)
        let safari = XCUIApplication(bundleIdentifier: Self.safariID)
        let texts = observed.nodes.filter { !$0.label.isEmpty && !isOwn($0) }.prefix(20).map(\.label)
        var line = "after tap: app=\(stateName(app.state)) safari=\(stateName(safari.state)) "
            + "sheetLike=\(observed.sheetLike) outcome=\(observed.outcome)"
        line += " loading=\(observed.loading) foundAfter=\(observed.foundAfter.map { String(format: "%.1fs", $0) } ?? "never")"
        line += " polls=\(observed.polls)"
        notes.append(line)
        notes.append(observed.treeRead ? "labelsAfter=[\(texts.joined(separator: ", "))]" : "labelsAfter=[] (tree not read: the probe app was not in front)")
        saveScreenshot("\(scenario)-1-after-tap")
        if observed.treeRead, !observed.nodes.isEmpty {
            saveText("\(scenario)-1-after-tap-hierarchy", describe(observed.nodes))
        } else {
            saveText("\(scenario)-1-after-tap-hierarchy", "not captured: the probe app was not in front, so its tree was not read")
        }

        // Safari can still arrive late; a query that hangs then is an expected failure.
        let dismissed = safely("return to the app", "failed") { returnToApp(app) }
        let status = inFront(app) ? safely("read the status", Status()) { readStatus(app) } : Status()
        notes.append("dismissedBy=\(dismissed)")
        notes.append("back in app=\(inFront(app) && status.readable) status: \(status.oneLine)")
        saveScreenshot("\(scenario)-2-after-dismiss")
        notes.append("RESULT=\(observed.outcome)")
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

    // MARK: - Scenario: edit commands

    private func editCutThenPaste() {
        let scenario = "edit-cutThenPaste"
        guard let app = launchApp(scenario) else { return }
        defer { app.terminate() }
        let spec = Self.spec("single")
        var notes = ["start=\(Self.stamp())", supportedLine(app)]
        defer { summary(scenario, notes) }

        guard selectAndTap(app, spec, word: "harbor", row: "Cut", scenario: scenario, step: "1-cut", notes: &notes) else { return }
        check(app, expectedText: "The quiet  sailed away", step: "after Cut", notes: &notes)
        guard selectAndTap(app, spec, word: "sailed", row: "Paste", scenario: scenario, step: "2-paste", notes: &notes, reset: false) else { return }
        check(app, expectedText: "The quiet  harbor away", step: "after Paste over \"sailed\"", notes: &notes)
    }

    private func editCopyThenPaste() {
        let scenario = "edit-copyThenPaste"
        guard let app = launchApp(scenario) else { return }
        defer { app.terminate() }
        let spec = Self.spec("single")
        var notes = ["start=\(Self.stamp())", supportedLine(app)]
        defer { summary(scenario, notes) }

        guard selectAndTap(app, spec, word: "harbor", row: "Copy", scenario: scenario, step: "1-copy", notes: &notes) else { return }
        check(app, expectedText: Self.sentence, step: "after Copy", notes: &notes)
        guard selectAndTap(app, spec, word: "sailed", row: "Paste", scenario: scenario, step: "2-paste", notes: &notes, reset: false) else { return }
        check(app, expectedText: "The quiet harbor harbor away", step: "after Paste over \"sailed\"", notes: &notes)
    }

    private func editSelectAll() {
        let scenario = "edit-selectAll"
        guard let app = launchApp(scenario) else { return }
        defer { app.terminate() }
        let spec = Self.spec("single")
        var notes = ["start=\(Self.stamp())", supportedLine(app)]
        defer { summary(scenario, notes) }

        guard selectAndTap(app, spec, word: "harbor", row: "Select All", scenario: scenario, step: "1-selectAll", notes: &notes) else { return }
        let status = readStatus(app)
        let all = status.base == 0 && status.extent == Self.sentence.utf16.count
        notes.append("after Select All: selection \(status.base)..\(status.extent) of \(Self.sentence.utf16.count) whole=\(all)")
        let nodes = waitForMenu(app, timeout: 2.5)
        let rows = menuRows(nodes)
        notes.append("menu after Select All=[\(labels(rows))]")
        saveScreenshot("\(scenario)-2-after")
        notes.append("RESULT=\(all ? "ok" : "selection-not-whole")")
    }

    /// Selects `word`, shows the menu, taps `row`. Records and returns false
    /// when a step fails.
    private func selectAndTap(
        _ app: XCUIApplication, _ spec: FieldSpec, word: String, row: String,
        scenario: String, step: String, notes: inout [String], reset: Bool = true
    ) -> Bool {
        let selection = focusAndSelect(app, spec, word: word, reset: reset)
        notes.append("\(step): select \"\(word)\" \(selection.ok ? "ok" : "FAILED") (\(selection.how))")
        guard !menuRows(waitForMenu(app)).isEmpty else {
            notes.append("\(step): no menu; RESULT=no-menu")
            saveScreenshot("\(scenario)-\(step)-no-menu")
            return false
        }
        saveScreenshot("\(scenario)-\(step)-menu")
        guard menuTap(app, row, notes: &notes) else {
            notes.append("\(step): \(row) not available; RESULT=row-absent")
            saveScreenshot("\(scenario)-\(step)-row-absent")
            saveText("\(scenario)-\(step)-row-absent-hierarchy", describe(snapshotNodes(app)))
            return false
        }
        pause(1.2)
        saveScreenshot("\(scenario)-\(step)-after-tap")
        return true
    }

    private func check(_ app: XCUIApplication, expectedText: String, step: String, notes: inout [String]) {
        let status = readStatus(app)
        let pass = status.text == expectedText
        notes.append("\(step): text=\"\(status.text)\" expected=\"\(expectedText)\" \(pass ? "PASS" : "FAIL") status: \(status.oneLine)")
    }

    // MARK: - Scenario: typing after a menu cycle

    /// The main risk of the engine change: the field must still take input
    /// after the menu was shown and dismissed, after a row opened a sheet, and
    /// after Copy.
    private func typingAfterMenuCycle() {
        let scenario = "typing"
        guard let app = launchApp(scenario) else { return }
        defer { app.terminate() }
        let spec = Self.spec("single")
        var notes = ["start=\(Self.stamp())", supportedLine(app)]
        defer { summary(scenario, notes) }

        func record(_ step: String) {
            let status = readStatus(app)
            notes.append("\(step): keyboard=\(keyboardShown(app)) status: \(status.oneLine)")
            saveScreenshot("\(scenario)-\(step)")
        }

        // Step 1: show the menu, dismiss it with a tap in the field, type.
        let selection = focusAndSelect(app, spec, word: "harbor")
        notes.append("1 select=\(selection.ok ? "ok" : "FAILED") (\(selection.how))")
        let shown = !menuRows(waitForMenu(app)).isEmpty
        notes.append("1 menuShown=\(shown)")
        record("1a-menu-shown")
        guard let frame = fieldFrame(app, spec) else {
            notes.append("RESULT=field-not-found")
            return
        }
        tap(app, at: CGPoint(x: frame.maxX - 20, y: frame.midY))
        pause(1.0)
        notes.append("1 menuGoneAfterTap=\(menuRows(snapshotNodes(app)).isEmpty)")
        record("1b-after-dismiss")
        notes.append("1 typed abc: \(typeText(app, "abc"))")
        record("1c-typed-abc")

        // Step 2: show the menu, Look Up, dismiss the sheet, type.
        let second = focusAndSelect(app, spec, word: "harbor", reset: false)
        notes.append("2 select=\(second.ok ? "ok" : "FAILED") (\(second.how))")
        if menuTap(app, "Look Up", notes: &notes) {
            let seen = observeAfterTap(app, row: "Look Up")
            saveScreenshot("\(scenario)-2a-lookup-shown")
            notes.append("2 lookUp outcome=\(seen.outcome)")
            notes.append("2 dismiss: \(backToApp(app))")
        } else {
            notes.append("2 Look Up not available")
        }
        record("2b-after-lookup")
        if !keyboardShown(app), let again = fieldFrame(app, spec) {
            // The sheet took the keyboard away; focus the field again to type.
            tap(app, at: CGPoint(x: again.maxX - 20, y: again.midY))
            pause(1.2)
            notes.append("2 refocused the field by a tap (the keyboard was gone)")
        }
        notes.append("2 typed def: \(typeText(app, "def"))")
        record("2c-typed-def")

        // Step 3: show the menu, Copy, type.
        let third = focusAndSelect(app, spec, word: "quiet", reset: false)
        notes.append("3 select=\(third.ok ? "ok" : "FAILED") (\(third.how))")
        if menuTap(app, "Copy", notes: &notes) {
            pause(1.0)
        } else {
            notes.append("3 Copy not available")
        }
        record("3a-after-copy")
        notes.append("3 typed ' ghi': \(typeText(app, " ghi"))")
        record("3b-typed-ghi")

        // Step 4: autocorrect and a keyboard suggestion.
        if let latest = fieldFrame(app, spec) {
            tap(app, at: CGPoint(x: latest.maxX - 20, y: latest.midY))
            pause(1.0)
        }
        notes.append("4 typed ' helo ': \(typeText(app, " helo "))")
        record("4a-autocorrect")
        notes.append("4 typed 'wrold': \(typeText(app, "wrold"))")
        let nodes = snapshotNodes(app)
        let candidates = predictionCandidates(nodes)
        notes.append("4 suggestions=[\(candidates.map(\.label).joined(separator: ", "))]")
        saveScreenshot("\(scenario)-4b-suggestions")
        saveHierarchy("\(scenario)-4b-suggestions-hierarchy", app, nodes: nodes)
        if let pick = candidates.first(where: {
            !$0.label.hasPrefix("\"") && !$0.label.hasPrefix("“") && $0.label.lowercased() != "wrold"
        }) {
            notes.append("4 tap suggestion \(pick.summary)")
            tap(app, at: center(pick.frame))
            pause(1.0)
            record("4c-suggestion-tapped")
        } else {
            notes.append("4 no suggestion to tap")
        }
        notes.append("RESULT=done (compare the status lines with what was typed)")
    }

    // MARK: - Scenario: cycles

    /// Opens and dismisses the menu 20 times, then types.
    private func cycles() {
        let scenario = "cycles"
        guard let app = launchApp(scenario) else { return }
        defer { app.terminate() }
        let spec = Self.spec("single")
        var notes = ["start=\(Self.stamp())", supportedLine(app)]
        defer { summary(scenario, notes) }

        let selection = focusAndSelect(app, spec, word: "harbor")
        notes.append("select=\(selection.ok ? "ok" : "FAILED") (\(selection.how))")
        guard let wordPoint = selection.point, let frame = fieldFrame(app, spec) else {
            notes.append("RESULT=no-word-to-tap")
            saveScreenshot("\(scenario)-0-no-word")
            return
        }
        let dismissPoint = CGPoint(x: frame.maxX - 20, y: frame.midY)
        var pattern = ""
        var firstMiss: Int?
        for round in 1...20 {
            if round > 1 {
                doubleTap(app, at: wordPoint)
                pause(1.0)
            }
            let present = !menuRows(waitForMenu(app, timeout: 2.5)).isEmpty
            pattern += present ? "M" : "-"
            if !present, firstMiss == nil {
                firstMiss = round
            }
            if round == 1 || round == 10 || round == 20 {
                saveScreenshot("\(scenario)-round\(round)")
            }
            tap(app, at: dismissPoint)
            pause(0.8)
            if round == 1 {
                notes.append("round 1 menuGoneAfterDismiss=\(menuRows(snapshotNodes(app)).isEmpty)")
            }
        }
        notes.append("menu per round (M = shown, - = missing): \(pattern)")
        notes.append("menu on the 20th round=\(pattern.last == "M") firstMissingRound=\(firstMiss.map(String.init) ?? "none")")
        notes.append("typed z: \(typeText(app, "z"))")
        let status = readStatus(app)
        notes.append("final status: \(status.oneLine)")
        saveScreenshot("\(scenario)-final")
        if let miss = firstMiss {
            notes.append("RESULT=menu-missing-in-round-\(miss)")
        } else {
            notes.append("RESULT=ok")
        }
    }

    // MARK: - Scenario: selection change while the menu is shown

    private func selectionChangeWhileShown() {
        let scenario = "selectionChange"
        guard let app = launchApp(scenario) else { return }
        defer { app.terminate() }
        let spec = Self.spec("single")
        var notes = ["start=\(Self.stamp())", supportedLine(app)]
        defer { summary(scenario, notes) }

        let selection = focusAndSelect(app, spec, word: "harbor")
        notes.append("select=\(selection.ok ? "ok" : "FAILED") (\(selection.how)) status: \(selection.status.oneLine)")
        let before = waitForMenu(app)
        notes.append("menu before=[\(labels(menuRows(before)))]")
        saveScreenshot("\(scenario)-1-before-drag")
        saveHierarchy("\(scenario)-1-before-hierarchy", app, nodes: before)
        guard let rect = selection.status.selRect else {
            notes.append("RESULT=no-selection-rectangle (the status has no selRect)")
            return
        }
        // Flutter draws the selection handles itself; the end handle's knob sits
        // just below the end of the selection. The first drag position that
        // changes the selection is kept.
        let baseSelection = (selection.status.base, selection.status.extent)
        var moved = false
        for (index, offsetY) in [CGFloat(6), 12, -2].enumerated() {
            let start = CGPoint(x: rect.maxX, y: rect.maxY + offsetY)
            drag(app, from: start, to: CGPoint(x: start.x + 70, y: start.y))
            pause(1.5)
            let status = readStatus(app)
            notes.append("drag\(index + 1) from \(Int(start.x)),\(Int(start.y)): selection \(status.base)..\(status.extent) \"\(status.selectedText)\"")
            if (status.base, status.extent) != baseSelection {
                moved = true
                break
            }
        }
        let after = waitForMenu(app, timeout: 3)
        let rows = menuRows(after)
        notes.append("selectionChanged=\(moved) menuAfter=\(!rows.isEmpty) labels=[\(labels(rows))]")
        saveScreenshot("\(scenario)-2-after-drag")
        saveHierarchy("\(scenario)-2-after-hierarchy", app, nodes: after)
        notes.append("final status: \(readStatus(app).oneLine)")
        if !moved {
            notes.append("RESULT=handle-not-found")
        } else if rows.isEmpty {
            notes.append("RESULT=selection-moved-menu-gone")
        } else {
            notes.append("RESULT=selection-moved-menu-back")
        }
    }

    // MARK: - Scenario: autocorrect after a menu cycle

    /// The keyboard commits a pending autocorrection when the caret moves. The
    /// first runs showed a difference after one menu cycle ("awayabc" became
    /// "away arc" with the changed engine, not with the stock one). Five
    /// variants, each from a reset app, record what happens. Nothing is judged
    /// here; the two runs are compared afterwards.
    private func autocorrect() {
        let scenario = "autocorrect"
        guard let app = launchApp(scenario) else { return }
        defer { app.terminate() }
        let spec = Self.spec("single")
        var notes = ["start=\(Self.stamp())", supportedLine(app)]
        defer { summary(scenario, notes) }

        // A: the fresh app, no menu shown yet in this launch.
        autocorrectProbe(app, spec, step: "A", scenario: scenario, notes: &notes)

        // B: show the menu, dismiss it by a tap in the field.
        let b = focusAndSelect(app, spec, word: "harbor")
        let bMenu = !menuRows(waitForMenu(app)).isEmpty
        notes.append("B: select=\(b.ok ? "ok" : "FAILED") (\(b.how)) menuShown=\(bMenu)")
        if let frame = fieldFrame(app, spec) {
            tap(app, at: CGPoint(x: frame.maxX - 20, y: frame.midY))
            pause(1.0)
            notes.append("B: menuGoneAfterTap=\(menuRows(snapshotNodes(app)).isEmpty)")
        }
        autocorrectProbe(app, spec, step: "B", scenario: scenario, notes: &notes)

        // C: show the menu, Look Up, close the sheet.
        let c = focusAndSelect(app, spec, word: "harbor")
        notes.append("C: select=\(c.ok ? "ok" : "FAILED") (\(c.how))")
        if menuTap(app, "Look Up", notes: &notes) {
            let observed = observeAfterTap(app, row: "Look Up")
            saveScreenshot("\(scenario)-C-lookup-shown")
            notes.append("C: lookUp outcome=\(observed.outcome) closedBy=\(returnToApp(app))")
        } else {
            notes.append("C: Look Up not available")
        }
        autocorrectProbe(app, spec, step: "C", scenario: scenario, notes: &notes)

        // D: show the menu, Copy.
        let d = focusAndSelect(app, spec, word: "harbor")
        notes.append("D: select=\(d.ok ? "ok" : "FAILED") (\(d.how))")
        if menuTap(app, "Copy", notes: &notes) {
            pause(1.0)
            notes.append("D: Copy tapped status: \(readStatus(app).oneLine)")
        } else {
            notes.append("D: Copy not available")
        }
        autocorrectProbe(app, spec, step: "D", scenario: scenario, notes: &notes)

        // E: type while the menu is shown.
        let e = focusAndSelect(app, spec, word: "harbor")
        let eMenu = !menuRows(waitForMenu(app)).isEmpty
        notes.append("E: select=\(e.ok ? "ok" : "FAILED") (\(e.how)) menuShown=\(eMenu)")
        saveScreenshot("\(scenario)-E-menu-shown")
        let typed = typeText(app, "x")
        let after = readStatus(app)
        let gone = menuRows(snapshotNodes(app)).isEmpty
        notes.append("E: typed x (\(typed)) menuGoneAfterTyping=\(gone) textAfterTyping=\"\(after.text)\" status: \(after.oneLine)")
        saveScreenshot("\(scenario)-E-typed")
        notes.append("RESULT=recorded (compare the A to E lines between runs)")
    }

    /// Tap at the end of the text, type "abc", tap near the start of the field,
    /// and record the text before and after that last tap.
    private func autocorrectProbe(
        _ app: XCUIApplication, _ spec: FieldSpec, step: String, scenario: String, notes: inout [String]
    ) {
        guard let frame = fieldFrame(app, spec) else {
            notes.append("\(step): field-not-found")
            return
        }
        tap(app, at: CGPoint(x: frame.maxX - 20, y: frame.midY))
        pause(1.3)
        let moved = fieldFrame(app, spec) ?? frame
        if !keyboardShown(app) {
            tap(app, at: CGPoint(x: moved.maxX - 20, y: moved.midY))
            pause(1.2)
        }
        let typed = typeText(app, "abc")
        let typedStatus = readStatus(app)
        saveScreenshot("\(scenario)-\(step)-typed")
        tap(app, at: CGPoint(x: moved.minX + 24, y: moved.midY))
        pause(1.2)
        let tapStatus = readStatus(app)
        saveScreenshot("\(scenario)-\(step)-after-tap")
        let applied = typedStatus.readable && tapStatus.readable
            ? String(typedStatus.text != tapStatus.text) : "unknown"
        notes.append(
            "\(step): typed abc (\(typed)) textAfterTyping=\"\(typedStatus.text)\" textAfterTap=\"\(tapStatus.text)\" "
                + "autocorrectApplied=\(applied) selAfterTyping=\(typedStatus.base)..\(typedStatus.extent) "
                + "selAfterTap=\(tapStatus.base)..\(tapStatus.extent) composingAfterTyping=\(typedStatus.composing) "
                + "composingAfterTap=\(tapStatus.composing)"
        )
    }

    // MARK: - Output

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

    /// One result line: `<scenario> | ios=<version> | <notes>`.
    private func summary(_ scenario: String, _ notes: [String]) {
        appendSummary("\(scenario) | ios=\(iosVersion) | " + notes.joined(separator: " | "))
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
