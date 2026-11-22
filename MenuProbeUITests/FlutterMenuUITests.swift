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

    func test_08_ime_a_afterMenuCycle() { ime("a") }
    func test_08_ime_b_afterLookUp() { ime("b") }
    func test_08_ime_c_menuWhileMarked() { ime("c") }
    func test_08_ime_d_composeCycleCompose() { ime("d") }

    func test_09_sized_plain() { sized("sized-plain") }
    func test_09_sized_nohints() { sized("sized-nohints") }
    func test_09_sized_email() { sized("sized-email") }
    func test_09_sized_username() { sized("sized-username") }

    func test_10_showcase() { showcase() }

    // MARK: - Scenario selection

    /// Skips a test that the workflow's `scenarios` input did not select. The
    /// selection (`PROBE_SCENARIOS`) is a comma or space separated list of
    /// groups (the word after `test_NN_` starts with the group: `shape`, `rows`,
    /// `edit`, `typing`, `cycles`, `selectionChange`, `autocorrect`, `ime`,
    /// `sized`, `showcase`) or of test method names. Empty or `all` runs all.
    nonisolated override func setUpWithError() throws {
        try super.setUpWithError()
        let selection = ProcessInfo.processInfo.environment["PROBE_SCENARIOS"] ?? ""
        if !Self.isSelected(testName: name, selection: selection) {
            throw XCTSkip("not selected by PROBE_SCENARIOS=\(selection)")
        }
    }

    nonisolated static func isSelected(testName: String, selection: String) -> Bool {
        let tokens = selection.lowercased()
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .map(String.init)
        if tokens.isEmpty || tokens.contains("all") {
            return true
        }
        // `name` is "-[FlutterMenuUITests test_05_cycles]".
        let last = testName.split(separator: " ").last.map(String.init) ?? testName
        let method = (last.split(separator: ".").last.map(String.init) ?? last)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-[]"))
            .lowercased()
        let parts = method.split(separator: "_", maxSplits: 2)
        let group = parts.count == 3 ? String(parts[2]) : method
        return tokens.contains { method == $0 || group.hasPrefix($0) }
    }

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
        // The fields of the app's `sized` page (its page button).
        FieldSpec(id: "sized-plain", word: "harbor", text: sentence),
        FieldSpec(id: "sized-nohints", word: "harbor", text: sentence),
        FieldSpec(id: "sized-email", word: "harbor", text: sentence),
        FieldSpec(id: "sized-username", word: "harbor", text: sentence),
        FieldSpec(id: "sized-password", word: nil, text: "swordfish"),
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

    /// True while Safari is in front. A plain read of `state` can stay stale
    /// for an app this test did not launch (on the iPad runs it said "not in
    /// front" for the whole 6 s wait while Safari was on screen, and the probe
    /// app still said "foreground", so its tree was queried and hung for 90 s
    /// to 4 min). `wait(for:timeout:)` polls the state itself and refreshes it.
    private func safariInFront(_ safari: XCUIApplication, wait: TimeInterval = 0.4) -> Bool {
        safari.state == .runningForeground || safari.wait(for: .runningForeground, timeout: wait)
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

    /// Whether this test uses the app's `sized` page. The app always starts on
    /// its main page (Dart's `Platform.environment` is empty on iOS, so a
    /// launch environment cannot reach it); `showSizedPage` taps the app's page
    /// button after every launch and relaunch.
    private var sizedPage = false

    /// While true, a failed launch is noted here instead of being recorded,
    /// so that `launchWithRetry` can try once more. Set and read on the main
    /// thread only (XCUIApplication reports from there).
    nonisolated(unsafe) private var launchRetryArmed = false
    nonisolated(unsafe) private var failedLaunch: String?

    nonisolated override func record(_ issue: XCTIssue) {
        if launchRetryArmed, issue.compactDescription.contains("Failed to launch") {
            failedLaunch = issue.compactDescription
            return
        }
        super.record(issue)
    }

    /// Launches the app; when the launch fails (on a runner it once timed out
    /// after 40 s), it is tried once more after a pause. A retry is written
    /// to summary.txt as `launch-retry-<test>`; a second failure is recorded.
    private func launchWithRetry(_ app: XCUIApplication) {
        failedLaunch = nil
        launchRetryArmed = true
        app.launch()
        launchRetryArmed = false
        guard let first = failedLaunch else { return }
        failedLaunch = nil
        pause(3.0)
        app.launch()
        let test = (name.split(separator: " ").last.map(String.init) ?? name)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-[]"))
        summary("launch-retry-\(test)", ["first attempt: \(first)", "RESULT=retried (state=\(stateName(app.state)))"])
    }

    /// Shows the app's `sized` page when this test uses it: taps the page
    /// button (`probe-page`) until the page's first field is there. Returns
    /// what happened; empty when the test does not use the page.
    @discardableResult
    private func showSizedPage(_ app: XCUIApplication) -> String {
        guard sizedPage else { return "" }
        let field = element(app, "field-sized-plain")
        for taps in 0..<3 {
            if field.exists {
                return "sized (page button tapped \(taps)x)"
            }
            let button = element(app, "probe-page")
            if dismissMenu(app).clear, button.exists, !button.frame.isEmpty {
                tap(app, at: center(button.frame))
            }
            pause(1.2)
        }
        return field.waitForExistence(timeout: 3) ? "sized (page button tapped 3x)" : "NOT shown (page button tapped 3x)"
    }

    /// Starts the Flutter app and waits for its first frame (the `supported`
    /// line). Records the failure and returns nil when it never appears. Safari
    /// is stopped first and the app is relaunched, so that every scenario
    /// starts from a clean state. `sized: true` then switches to the app's
    /// `sized` page, also after any later relaunch.
    private func launchApp(_ scenario: String, sized: Bool = false) -> XCUIApplication? {
        continueAfterFailure = true
        sizedPage = sized
        stopSafari()
        let app = XCUIApplication(bundleIdentifier: bundleID)
        if app.state != .notRunning, app.state != .unknown {
            app.terminate()
        }
        launchWithRetry(app)
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

        /// True when the value has a composing (marked) range, `composing=a..b`
        /// with a < b: only an IME produces one.
        var hasComposing: Bool {
            let ends = composing.components(separatedBy: "..").compactMap { Int($0) }
            return ends.count == 2 && ends[0] >= 0 && ends[0] < ends[1]
        }

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
        ["supported", "probe-page", "probe-reset", "probe-done", "status"].contains(node.identifier)
            || node.identifier.hasPrefix("field-")
    }

    /// Indexes of the iPad keyboard's shortcut bar (`SystemInputAssistantView`,
    /// above the keys and outside the keyboard element). With a selection its
    /// left side has Cut, Copy and Paste buttons (`assistantUndo`,
    /// `assistantRedo`, `assistantPaste:forEvent:`), which are not menu rows.
    private func assistantBars(_ nodes: [Node]) -> Set<Int> {
        Set(nodes.filter { $0.identifier == "SystemInputAssistantView" }.map(\.index))
    }

    /// The labels of the shortcut bar's buttons, as ` assistantBar=[...]`, or
    /// empty when there is no bar (iPhone).
    private func assistantBarField(_ nodes: [Node]) -> String {
        let bars = assistantBars(nodes)
        guard !bars.isEmpty else { return "" }
        let buttons = nodes.filter { node in
            node.type == .button && !node.label.isEmpty && node.ancestors.contains { bars.contains($0) }
        }
        return " assistantBar=[\(labels(buttons))]"
    }

    /// Visible elements whose label is a known menu title, outside the keyboard,
    /// the iPad keyboard's shortcut bar and the app's own elements. A row
    /// usually shows up twice (the row and its label), so labels repeat.
    private func menuRows(_ nodes: [Node]) -> [Node] {
        let keyboard = nodes.filter { $0.type == .keyboard }.map(\.frame)
        let bars = assistantBars(nodes)
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
            // The button can lie under the expanded menu (its Copy button on
            // iOS 26), so no tap is sent while a menu is on screen.
            let menu = dismissMenu(app)
            if !menu.note.isEmpty {
                extra.append(menu.note)
            }
            let button = element(app, "probe-reset")
            if menu.clear, button.exists, !button.frame.isEmpty {
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

    /// A tap on the app's header text: it does nothing in the app. A menu that
    /// is still shown is dismissed first (`dismissMenu`), so the tap cannot
    /// land on a menu item; when the menu stays, nothing is tapped. Returns the
    /// note of `dismissMenu`.
    @discardableResult
    private func tapBlank(_ app: XCUIApplication) -> String {
        let menu = dismissMenu(app)
        let label = element(app, "supported")
        if menu.clear, label.exists, !label.frame.isEmpty {
            tap(app, at: center(label.frame))
            pause(0.8)
        }
        return menu.note
    }

    /// Dismisses an edit menu that is on screen, so that a tap aimed at an app
    /// control cannot hit one of the menu's buttons (the expanded iOS 26 menu
    /// has a Cut / Copy row over the header's buttons, and a Copy tap puts
    /// Paste into every later menu). The dismissing tap goes to a point
    /// outside the rows' frames (`menuSafePoints`); a menu swallows a tap
    /// outside it. The menu is read again afterwards, and up to three points
    /// are tried. `clear` is true when no menu is on screen at the end (also
    /// when none was there at all, or the app is not in front). `note` is empty
    /// when nothing had to be done.
    private func dismissMenu(_ app: XCUIApplication) -> (clear: Bool, note: String) {
        guard inFront(app) else { return (true, "") }
        var nodes = snapshotNodes(app)
        if nodes.isEmpty {
            pause(0.5)
            nodes = snapshotNodes(app)
        }
        var done: [String] = []
        var tried: [CGPoint] = []
        for _ in 1...3 {
            let rows = menuRows(nodes)
            if rows.isEmpty {
                break
            }
            let points = menuSafePoints(nodes, rows: rows, app: app)
            guard let point = points.first(where: { candidate in
                !tried.contains { abs($0.x - candidate.x) < 1 && abs($0.y - candidate.y) < 1 }
            }) else {
                done.append("no safe point outside the menu")
                break
            }
            tried.append(point)
            tap(app, at: point)
            done.append("tap at \(Int(point.x)),\(Int(point.y))")
            pause(0.9)
            nodes = snapshotNodes(app)
        }
        if done.isEmpty {
            return (true, "")
        }
        let clear = menuRows(nodes).isEmpty
        return (clear, "menu dismissed first (\(done.joined(separator: ", ")); gone=\(clear))")
    }

    /// Points for dismissing a menu: on the app's header text (its left end
    /// first), then on the empty edges of the list. None lies near the menu's
    /// rows, on one of the app's controls or fields, the status area or the
    /// keyboard.
    private func menuSafePoints(_ nodes: [Node], rows: [Node], app: XCUIApplication) -> [CGPoint] {
        let screen = nodes.first?.frame ?? app.frame
        let menu = rows.map(\.frame).reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -30, dy: -30)
        let keyboard = nodes.filter { $0.type == .keyboard }.map(\.frame)
        let controls = nodes.filter { isOwn($0) && $0.identifier != "supported" && !$0.frame.isEmpty }
            .map { $0.frame.insetBy(dx: -3, dy: -3) }
        var candidates: [CGPoint] = []
        if let header = nodes.first(where: { $0.identifier == "supported" && !$0.frame.isEmpty }) {
            candidates.append(CGPoint(x: header.frame.minX + 8, y: header.frame.midY))
            candidates.append(center(header.frame))
            candidates.append(CGPoint(x: header.frame.maxX - 8, y: header.frame.midY))
        }
        for y in [0.3, 0.45, 0.6] {
            candidates.append(CGPoint(x: screen.minX + 6, y: screen.minY + screen.height * y))
            candidates.append(CGPoint(x: screen.maxX - 6, y: screen.minY + screen.height * y))
        }
        return candidates.filter { point in
            screen.contains(point) && !menu.contains(point)
                && !keyboard.contains { $0.contains(point) } && !controls.contains { $0.contains(point) }
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
            // The focus tap and the double taps go to the field; a menu that is
            // still up (a scenario that keeps the app's state) could be hit.
            let menu = dismissMenu(app)
            if !menu.note.isEmpty {
                recovery.append("round\(round): \(menu.note)")
            }
            result = menu.clear
                ? selectOnce(app, spec, word: word)
                : Selection(ok: false, how: "menu-not-dismissed", point: nil, status: readStatus(app))
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
        let blank = tapBlank(app)
        done.append(blank.isEmpty ? "tap blank" : "tap blank (\(blank))")
        if reset {
            let again = resetApp(app)
            done.append(again.isEmpty ? "reset" : "reset (\(again))")
        } else {
            let button = element(app, "probe-done")
            let menu = dismissMenu(app)
            if !menu.note.isEmpty {
                done.append(menu.note)
            }
            if menu.clear, button.exists, !button.frame.isEmpty {
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

    /// The rows really visible on the current page. The accessibility tree of a
    /// paged bar (iPad iOS 16-18) also lists rows of other pages, clipped by the
    /// bar or hidden under the page chevron; those cannot be tapped. A row counts
    /// when its frame lies inside the bar (the rows' container, when it is
    /// narrower than the screen) and does not overlap a Forward/Back button.
    private func visibleRows(_ items: [Node], nodes: [Node], app: XCUIApplication) -> [Node] {
        let pageButtons = try! NSRegularExpression(
            pattern: "(forward|back|next|previous)", options: .caseInsensitive
        )
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
    /// menu does not offer it or is gone. Pages like `expandMenu`: it stops
    /// when a tap did not change the page or after the menu turned into a
    /// taller list, not on the height of the first page.
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
            if let match = rowNode(row, in: items) {
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
    /// puts the keyboard away) is not one, and neither is a key of the keyboard
    /// (the return key of the app's fields is labelled "done"). The button
    /// inside `probe-done` has no identifier of its own, so it is told apart by
    /// its frame.
    private func closeButton(_ app: XCUIApplication) -> XCUIElement? {
        let predicate = NSPredicate(
            format: "(label ==[c] 'Done' OR label ==[c] 'Close' OR label ==[c] 'Cancel' OR label ==[c] 'Dismiss') "
                + "AND identifier != 'probe-done'"
        )
        let own = element(app, "probe-done")
        let ownFrame = own.exists ? own.frame : .null
        let keyboard = app.keyboards.firstMatch
        let keyboardFrame = keyboard.exists ? keyboard.frame : .null
        return app.buttons.matching(predicate).allElementsBoundByIndex.first { button in
            button.exists && button.isHittable
                && !ownFrame.intersects(button.frame) && !keyboardFrame.intersects(button.frame)
        }
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
                launchWithRetry(app)
                _ = element(app, "supported").waitForExistence(timeout: 60)
                pause(1.0)
                if sizedPage {
                    done.append("page \(showSizedPage(app))")
                }
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

    // MARK: - Helper: IME keyboards

    /// The letters composed on the IME keyboard: "かな" on the Japanese (Romaji)
    /// keyboard, "ka na" with candidates on the Chinese (Pinyin) one.
    static let imeLetters = "kana"

    /// Labels of the keyboard's keys in tree order, at most `limit`.
    private func keyLabels(_ nodes: [Node], limit: Int = 50) -> String {
        guard let keyboard = nodes.first(where: { $0.type == .keyboard }) else { return "(no keyboard)" }
        let keys = nodes.filter { $0.ancestors.contains(keyboard.index) && !$0.label.isEmpty }
        return "[" + uniqueLabels(keys).prefix(limit).joined(separator: ", ") + "]"
    }

    /// The globe key. On iPhones with Face ID it sits below the keyboard, so the
    /// whole tree is searched.
    private func nextKeyboardKey(_ nodes: [Node]) -> Node? {
        nodes.first { node in
            let text = (node.label + " " + node.identifier).lowercased()
            return !isOwn(node) && !node.frame.isEmpty && (node.type == .button || node.type == .key)
                && (text.contains("next keyboard") || text.contains("globe"))
        }
    }

    /// One delete: the delete key, else a typed backspace.
    private func tapDelete(_ app: XCUIApplication) -> String {
        let key = app.keys["delete"]
        if key.exists, key.isHittable {
            key.tap()
            return "key"
        }
        app.typeText(XCUIKeyboardKey.delete.rawValue)
        return "typeText"
    }

    /// Tells an IME keyboard from a Latin one by what it does: types one letter
    /// with the "a" key and deletes it again. Only an IME leaves the letter as
    /// marked (composing) text. `ime` is nil when the keyboard has no "a" key
    /// (emoji, numbers).
    private func probeKeyboard(_ app: XCUIApplication) -> (ime: Bool?, note: String) {
        guard let key = ["a", "A"].map({ app.keys[$0] }).first(where: { $0.exists && $0.isHittable }) else {
            return (nil, "no a key")
        }
        let before = readStatus(app)
        key.tap()
        pause(0.8)
        let typed = readStatus(app)
        var deletes = [tapDelete(app)]
        pause(0.8)
        var after = readStatus(app)
        if after.text.utf16.count > before.text.utf16.count {
            deletes.append(tapDelete(app))
            pause(0.8)
            after = readStatus(app)
        }
        let ime = typed.hasComposing
        let tail = String(typed.text.suffix(3)).replacingOccurrences(of: "\n", with: "\\n")
        return (ime, "a gave tail=\"\(tail)\" composing=\(typed.composing) ime=\(ime) "
            + "deleted=\(deletes.joined(separator: "+")) restored=\(after.text == before.text)")
    }

    /// The first globe tap on a new simulator shows a card over the keys
    /// ("Quickly Change Keyboards", "Tap <globe> to switch keyboards", Continue).
    /// Until Continue is tapped it comes back at every globe tap, and the keys
    /// under it cannot be tapped. Taps Continue; returns a note, or nil when
    /// the card is not there.
    private func dismissKeyboardIntro(_ app: XCUIApplication) -> String? {
        let nodes = snapshotNodes(app)
        guard nodes.contains(where: { $0.label == "Quickly Change Keyboards" || $0.label.contains("to switch keyboards") }),
              let button = nodes.first(where: { $0.type == .button && $0.label == "Continue" && !$0.frame.isEmpty })
        else { return nil }
        tap(app, at: center(button.frame))
        pause(1.2)
        let gone = !snapshotNodes(app).contains { $0.label == "Quickly Change Keyboards" }
        return "keyboard introduction card: tap Continue, gone=\(gone)"
    }

    /// Brings up an IME keyboard (`ime: true`) or a Latin one by tapping the
    /// globe key and probing after each tap. The focused field's caret must be
    /// where a probe letter may go. The keyboard introduction card is closed
    /// first wherever it shows. Returns whether it got there, and the steps.
    private func switchKeyboard(_ app: XCUIApplication, ime wanted: Bool) -> (ok: Bool, steps: String) {
        guard keyboardShown(app) else { return (false, "no keyboard on screen") }
        var steps: [String] = []
        for attempt in 0..<7 {
            if let note = dismissKeyboardIntro(app) {
                steps.append(note)
            }
            let probe = probeKeyboard(app)
            steps.append("probe\(attempt): \(probe.note)")
            if probe.ime == wanted {
                return (true, steps.joined(separator: "; "))
            }
            let nodes = snapshotNodes(app)
            guard let globe = nextKeyboardKey(nodes) else {
                steps.append("no Next keyboard key; keys=\(keyLabels(nodes))")
                return (false, steps.joined(separator: "; "))
            }
            steps.append("tap \(globe.summary)")
            tap(app, at: center(globe.frame))
            pause(1.2)
        }
        return (false, steps.joined(separator: "; "))
    }

    /// Puts the caret at the end of the field's text by a tap near its right
    /// edge, twice if no keyboard came up. False when the field is missing or
    /// no keyboard is up.
    private func focusEnd(_ app: XCUIApplication, _ spec: FieldSpec) -> Bool {
        for _ in 0..<2 {
            guard let frame = fieldFrame(app, spec) else { return false }
            tap(app, at: CGPoint(x: frame.maxX - 20, y: frame.midY))
            pause(1.3)
            if keyboardShown(app), readStatus(app).field == spec.id {
                return true
            }
        }
        return keyboardShown(app)
    }

    /// Commits marked text with the keyboard's return key, whose label depends
    /// on the keyboard ("confirm" while Japanese text is marked). Falls back to
    /// typing a newline.
    private func commitMarked(_ app: XCUIApplication) -> String {
        let nodes = snapshotNodes(app)
        if let keyboard = nodes.first(where: { $0.type == .keyboard }) {
            let keys = nodes.filter { node in
                node.ancestors.contains(keyboard.index) && !node.frame.isEmpty
                    && (node.type == .button || node.type == .key)
            }
            for name in ["confirm", "確定", "return", "改行", "enter", "done", "go"] {
                if let key = keys.first(where: { $0.label.lowercased() == name }) {
                    tap(app, at: center(key.frame))
                    pause(1.0)
                    return "tap \(key.summary)"
                }
            }
        }
        app.typeText("\n")
        pause(1.0)
        return "typeText newline (no return key found; keys=\(keyLabels(nodes)))"
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
            notes.append("collapsed=[]\(assistantBarField(nodes))")
            notes.append("RESULT=no-menu (see the screenshot and hierarchy)")
            summary(scenario, notes)
            return
        }
        notes.append("collapsed=[\(labels(rows))] all=[\(allMenuLabels(nodes, rows: rows))]\(assistantBarField(nodes))")
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
        sheetReason(nodes) != nil
    }

    /// Why the tree counts as a sheet, or nil. `marker`: an element that only a
    /// sheet, popover or card has. `own-elements-gone+full-screen-container`:
    /// the stock engine's Look Up sheet on iOS 27 is a full-height sheet whose
    /// tree has none of the app's elements (19 nodes: a 402x812 container and a
    /// "Toolbar" at y=62, nothing else). That counts when no element of the app
    /// is left and a container that is not the window covers the screen's width
    /// and most of its height from below the top edge. A tree with the app's
    /// elements, or without such a container, is not one.
    private func sheetReason(_ nodes: [Node]) -> String? {
        let marker = nodes.contains { node in
            node.type == .sheet || node.type == .popover || node.type == .navigationBar
                || node.label == "Sheet Grabber" || node.label == "dismiss popup"
                || node.identifier == "PopoverDismissRegion" || node.identifier == "DDUIDone"
                || node.identifier.hasPrefix("ShareSheet")
                || (node.type == .button && ["close", "Close"].contains(node.label))
        }
        if marker {
            return "marker"
        }
        guard let screen = nodes.first?.frame, !screen.isEmpty, !nodes.contains(where: { isOwn($0) }) else {
            return nil
        }
        let cover = nodes.contains { node in
            node.type != .application && node.type != .window
                && node.frame.width >= screen.width * 0.95
                && node.frame.height >= screen.height * 0.6
                && node.frame.minY > screen.minY + 1
        }
        return cover ? "own-elements-gone+full-screen-container" : nil
    }

    /// A sheet that still shows its progress indicator.
    private func sheetLoading(_ nodes: [Node]) -> Bool {
        nodes.contains { $0.label == "In progress" }
    }

    struct AfterTap {
        var outcome = "nothing-visible"
        var sheetLike = false
        var sheetReason = ""
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
            if expectsSafari ? safariInFront(safari) : safari.state == .runningForeground {
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
                result.sheetReason = sheetReason(nodes) ?? ""
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
        if !(expectsSafari ? safariInFront(safari, wait: 1.0) : safari.state == .runningForeground), inFront(app) {
            if expectsSafari || result.outcome == "sheet" {
                result.nodes = safely("snapshot after waiting", [Node]()) { snapshotNodes(app) }
                result.treeRead = true
                result.sheetLike = sheetLike(result.nodes)
                result.sheetReason = sheetReason(result.nodes) ?? ""
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
        if safariInFront(safari, wait: 1.0) || !inFront(app) {
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
            launchWithRetry(app)
            _ = element(app, "supported").waitForExistence(timeout: 60)
            pause(1.0)
            if sizedPage {
                done.append("page \(showSizedPage(app))")
            }
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
        if !observed.sheetReason.isEmpty {
            line += " sheetReason=\(observed.sheetReason)"
        }
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

    // MARK: - Scenario: marked text (IME)

    /// Marked (composing) text from a Japanese or Chinese keyboard around the
    /// menu, in the `single` field. The workflow adds those keyboards to the
    /// simulator; the globe key brings one up (`toIME:`, `imeKeys=`). Every step
    /// records the app's value (text, selection, composing range) and the menu.
    /// `exercised=yes markedAt=[...]` names the steps whose value had a
    /// composing range, the proof that marked text existed; when no IME
    /// keyboard is reached the line ends in `exercised=no` and
    /// `RESULT=ime-unreachable`. The keyboard is switched back to a Latin one at
    /// the end (`toLatin:`).
    ///
    /// a: menu cycle, then compose and commit. b: Look Up and its sheet closed,
    /// then compose and commit. c: compose, then a double tap on another word
    /// while the text is marked; then, after a reset, a long press. d: compose
    /// and commit, menu cycle, compose and commit again.
    private func ime(_ variant: String) {
        let scenario = "ime-\(variant)"
        guard let app = launchApp(scenario) else { return }
        defer { app.terminate() }
        let spec = Self.spec("single")
        var notes = ["start=\(Self.stamp())", supportedLine(app)]
        var marked: [String] = []
        var result = "recorded (compare the steps between runs)"
        defer { summary(scenario, notes) }
        defer {
            if inFront(app), focusEnd(app, spec) {
                notes.append("toLatin: \(switchKeyboard(app, ime: false).steps)")
            } else {
                notes.append("toLatin: the field could not be focused")
            }
            notes.append(marked.isEmpty
                ? "exercised=no (no step had composing text)"
                : "exercised=yes markedAt=[\(marked.joined(separator: ","))]")
            notes.append("RESULT=\(result)")
        }

        func record(_ step: String, hierarchy: Bool = false) -> Status {
            let nodes = snapshotNodes(app)
            let status = readStatus(app)
            if status.hasComposing {
                marked.append(step)
            }
            notes.append("\(step) at \(Self.stamp()): keyboard=\(keyboardShown(app)) "
                + "menu=[\(labels(menuRows(nodes)))] status: \(status.oneLine)")
            saveScreenshot("\(scenario)-\(step)")
            if hierarchy {
                saveHierarchy("\(scenario)-\(step)-hierarchy", app, nodes: nodes)
            }
            return status
        }

        /// Types the letters at the caret. When no composing range came, the
        /// IME keyboard is brought up again and the letters typed once more.
        func compose(_ step: String) -> (status: Status, base: String) {
            let base = readStatus(app).text
            notes.append("\(step) typed \(Self.imeLetters) (\(typeText(app, Self.imeLetters)))")
            var status = record(step)
            if !status.hasComposing {
                notes.append("\(step) no composing text; switch again: \(switchKeyboard(app, ime: true).steps)")
                notes.append("\(step)-retry typed \(Self.imeLetters) (\(typeText(app, Self.imeLetters)))")
                status = record("\(step)-retry")
            }
            return (status, base)
        }

        /// Commits the marked text and records whether the text kept it.
        func commit(_ step: String, _ composed: (status: Status, base: String)) {
            guard composed.status.hasComposing else {
                notes.append("\(step): nothing marked to commit")
                return
            }
            notes.append("\(step) commit: \(commitMarked(app))")
            let after = record(step)
            let kept = !after.hasComposing && after.text != composed.base
                && after.text.hasPrefix(composed.base)
            notes.append("\(step) committed=\(kept)")
        }

        guard focusEnd(app, spec) else {
            saveScreenshot("\(scenario)-0-no-focus")
            result = "field-not-focused"
            return
        }
        let reach = switchKeyboard(app, ime: true)
        let keyboardNodes = snapshotNodes(app)
        notes.append("toIME: ok=\(reach.ok) \(reach.steps)")
        notes.append("imeKeys=\(keyLabels(keyboardNodes))")
        saveScreenshot("\(scenario)-0-keyboard")
        saveHierarchy("\(scenario)-0-keyboard-hierarchy", app, nodes: keyboardNodes)
        guard reach.ok else {
            result = "ime-unreachable (no keyboard gave marked text; see toIME and the 0-keyboard screenshot)"
            return
        }

        switch variant {
        case "a":
            let selection = focusAndSelect(app, spec, word: "harbor", reset: false)
            notes.append("a1 select=\(selection.ok ? "ok" : "FAILED") (\(selection.how)) "
                + "menuShown=\(!menuRows(waitForMenu(app)).isEmpty)")
            _ = record("a1-menu")
            notes.append("a2 dismissed by a tap at the end, focused=\(focusEnd(app, spec))")
            _ = record("a2-dismissed")
            commit("a4-committed", compose("a3-composed"))
        case "b":
            let selection = focusAndSelect(app, spec, word: "harbor", reset: false)
            notes.append("b1 select=\(selection.ok ? "ok" : "FAILED") (\(selection.how))")
            if menuTap(app, "Look Up", notes: &notes) {
                let seen = observeAfterTap(app, row: "Look Up")
                saveScreenshot("\(scenario)-b2-lookup-shown")
                notes.append("b2 lookUp outcome=\(seen.outcome) closedBy=\(returnToApp(app))")
            } else {
                notes.append("b2 Look Up not available")
            }
            _ = record("b3-back")
            notes.append("b3 refocused=\(focusEnd(app, spec))")
            commit("b5-committed", compose("b4-composed"))
        case "c":
            let composed = compose("c1-composed")
            if let rect = composed.status.rect(of: "quiet") {
                doubleTap(app, at: center(rect))
                pause(0.4)
                _ = record("c2-doubleTap-0.4s")
                pause(1.2)
                _ = record("c3-doubleTap-1.6s", hierarchy: true)
            } else {
                notes.append("c2 no rectangle for \"quiet\" in the status")
            }
            let reset = resetApp(app)
            notes.append("c4 reset\(reset.isEmpty ? "" : " (\(reset))") refocused=\(focusEnd(app, spec))")
            let again = compose("c4-composed")
            if let rect = again.status.rect(of: "harbor") {
                coordinate(app, center(rect)).press(forDuration: 1.0)
                pause(0.4)
                _ = record("c5-longPress-0.4s")
                pause(1.2)
                _ = record("c6-longPress-1.6s", hierarchy: true)
            } else {
                notes.append("c5 no rectangle for \"harbor\" in the status")
            }
        default:
            commit("d2-committed", compose("d1-composed"))
            let selection = focusAndSelect(app, spec, word: "harbor", reset: false)
            notes.append("d3 select=\(selection.ok ? "ok" : "FAILED") (\(selection.how)) "
                + "menuShown=\(!menuRows(waitForMenu(app)).isEmpty)")
            _ = record("d3-menu")
            notes.append("d4 dismissed by a tap at the end, focused=\(focusEnd(app, spec))")
            _ = record("d4-dismissed")
            commit("d6-committed", compose("d5-composed"))
        }
    }

    // MARK: - Scenario: an input view with a size

    /// The frame of the field's FlutterTextInputView on an iPhone, from the
    /// engine source (README.md has the lines). On an iPad (Scribble) every
    /// field's view gets the field's own size instead.
    static let sizedFrames: [String: String] = [
        "sized-plain": "1x1 (autofill configuration without hints, autofill type none)",
        "sized-nohints": "zero (no autofill configuration)",
        "sized-email": "1x1 (regular autofill)",
        "sized-username": "1x1 (password autofill group, FlutterSecureTextInputView)",
    ]

    /// The rows Flutter's default menu asks for when a word is selected, with
    /// the titles iOS gives them; Translate comes with UIKit's lookup group.
    /// Any other row was added by UIKit.
    static let requestedTitles: Set<String> = [
        "Cut", "Copy", "Paste", "Select All", "Look Up", "Translate", "Search Web", "Share", "Share…", "Share...",
    ]

    private func unrequested(_ rows: [Node]) -> String {
        uniqueLabels(rows.filter { !Self.requestedTitles.contains($0.label) }).joined(separator: ", ")
    }

    /// Elements that neither the app's own elements, the keyboard nor the menu
    /// rows account for: a UIKit menu, popover, text view or image (a native
    /// handle or cursor, if UIKit exposes one) shows up here. At most 12.
    private func foreignElements(_ nodes: [Node]) -> String {
        let own = Set(nodes.filter { isOwn($0) }.map(\.index))
        let keyboard = Set(nodes.filter { $0.type == .keyboard }.map(\.index))
        let kinds: Set<XCUIElement.ElementType> = [
            .menu, .menuItem, .popover, .sheet, .textView, .textField, .secureTextField, .image,
        ]
        let found = nodes.filter { node in
            kinds.contains(node.type) && !own.contains(node.index) && !Self.knownTitles.contains(node.label)
                && !node.ancestors.contains { own.contains($0) || keyboard.contains($0) }
        }
        return found.prefix(12).map(\.summary).joined(separator: ", ")
    }

    /// One field of the app's `sized` page (README.md: which frame the engine
    /// gives its input view). 1: the menu's shape. 2: Look Up, Translate and
    /// Share, one `<field>-row-<row>` line each, as in the rows scenarios. 3:
    /// from a fresh selection each, while the menu is shown: a tap at the end
    /// of the same field, a tap in another field, a drag of the end handle, a
    /// double tap on another word; after each the menu, rows Flutter did not ask
    /// for (`unrequested=`), elements nobody accounts for (`foreign=`) and the
    /// app's value. 4: typing.
    private func sized(_ id: String) {
        let scenario = id
        let spec = Self.spec(id)
        let other = Self.spec(id == "sized-plain" ? "sized-email" : "sized-plain")
        guard let app = launchApp(scenario, sized: true) else { return }
        defer { app.terminate() }
        var notes = ["start=\(Self.stamp())", supportedLine(app), "page=\(showSizedPage(app))"]
        var exercised = "no (the word was not selected with the menu shown)"
        var result = "recorded (compare the steps between runs)"
        defer { summary(scenario, notes) }
        defer {
            notes.append("exercised=\(exercised)")
            notes.append("RESULT=\(result)")
        }
        guard element(app, spec.identifier).waitForExistence(timeout: 5) else {
            saveScreenshot("\(scenario)-0-page-missing")
            saveText("\(scenario)-0-page-missing-hierarchy", describe(snapshotNodes(app)))
            exercised = "no (the sized page is not on screen)"
            result = "page-not-shown (the page button did not bring up the sized page)"
            return
        }
        notes.append("expectedFrame=\(Self.sizedFrames[id] ?? "?") screen=\(Int(app.frame.width))x\(Int(app.frame.height))")

        // 1. The menu's shape.
        let selection = focusAndSelect(app, spec, word: spec.word)
        let nodes = waitForMenu(app)
        let rows = menuRows(nodes)
        notes.append("1 select=\(selection.ok ? "ok" : "FAILED") (\(selection.how)) collapsed=[\(labels(rows))] "
            + "all=[\(allMenuLabels(nodes, rows: rows))] unrequested=[\(unrequested(rows))]\(assistantBarField(nodes))")
        saveScreenshot("\(scenario)-1-collapsed")
        saveHierarchy("\(scenario)-1-collapsed-hierarchy", app, nodes: nodes)
        if selection.ok, !rows.isEmpty {
            exercised = "yes (word selected, menu shown in \(id))"
            let expansion = expandMenu(app, tag: scenario)
            let pages = expansion.pages.enumerated().map { "page\($0.offset + 1)=[\($0.element.joined(separator: ", "))]" }
            notes.append("1 mode=\(expansion.mode) pages=\(expansion.pages.count) " + pages.joined(separator: " "))
        }

        // 2. The rows that open a sheet.
        for row in ["Look Up", "Translate", "Share"] {
            let key = row.replacingOccurrences(of: " ", with: "")
            rowTap(app, spec, row, scenario: "\(scenario)-row-\(key.prefix(1).lowercased() + key.dropFirst())")
            stopSafari()
        }

        // 3. Actions while the menu is shown.
        for (step, action) in [("3a", "tapSameField"), ("3b", "tapOtherField"), ("3c", "dragHandle"), ("3d", "doubleTapOtherWord")] {
            let name = "\(step)-\(action)"
            let fresh = focusAndSelect(app, spec, word: spec.word)
            let shown = !menuRows(waitForMenu(app)).isEmpty
            guard fresh.ok, shown, let frame = fieldFrame(app, spec) else {
                notes.append("\(name): select=\(fresh.ok) menuShown=\(shown); skipped")
                continue
            }
            let how: String
            switch action {
            case "tapSameField":
                tap(app, at: CGPoint(x: frame.maxX - 20, y: frame.midY))
                how = "tap at the end of the field"
            case "tapOtherField":
                if let otherFrame = fieldFrame(app, other) {
                    tap(app, at: CGPoint(x: otherFrame.minX + 24, y: otherFrame.midY))
                    how = "tap in \(other.id)"
                } else {
                    how = "\(other.id) not found"
                }
            case "dragHandle":
                // Flutter draws its own handles; the end handle's knob is just
                // below the end of the selection.
                if let rect = fresh.status.selRect {
                    let start = CGPoint(x: rect.maxX, y: rect.maxY + 6)
                    drag(app, from: start, to: CGPoint(x: start.x + 70, y: start.y))
                    how = "drag from the end of the selection 70 to the right"
                } else {
                    how = "no selection rectangle"
                }
            default:
                if let rect = fresh.status.rect(of: "quiet") {
                    doubleTap(app, at: center(rect))
                    how = "double tap on quiet"
                } else {
                    how = "no rectangle for quiet"
                }
            }
            pause(1.5)
            let after = snapshotNodes(app)
            let afterRows = menuRows(after)
            let status = readStatus(app)
            notes.append("\(name): how=\(how) menu=[\(labels(afterRows))] unrequested=[\(unrequested(afterRows))]"
                + "\(assistantBarField(after)) foreign=[\(foreignElements(after))] status: \(status.oneLine)")
            saveScreenshot("\(scenario)-\(name)")
            saveHierarchy("\(scenario)-\(name)-hierarchy", app, nodes: after)
        }

        // 4. Typing on a Latin keyboard. The menu of step 3 may still be up;
        // the tap in the field must not hit one of its items.
        let leftover = dismissMenu(app)
        if !leftover.note.isEmpty {
            notes.append("4 \(leftover.note)")
        }
        let focused = leftover.clear && focusEnd(app, spec)
        let latin = focused && switchKeyboard(app, ime: false).ok
        let before = readStatus(app)
        let typed = typeText(app, "xyz")
        let after = readStatus(app)
        notes.append("4 focused=\(focused) latinKeyboard=\(latin) typed xyz (\(typed)) "
            + "typedOK=\(after.text == before.text + "xyz") status: \(after.oneLine)")
        saveScreenshot("\(scenario)-4-typed")
    }

    // MARK: - Scenario: showcase clip

    /// Writes a signal file for the workflow's recorder into PROBE_OUT.
    private func signal(_ name: String) {
        write(Data(Self.stamp().utf8), to: outDir.appendingPathComponent(name))
    }

    /// Waits for a signal file the workflow writes into PROBE_OUT.
    private func waitForSignal(_ name: String, timeout: TimeInterval) -> Bool {
        let path = outDir.appendingPathComponent(name).path
        let end = Date().addingTimeInterval(timeout)
        while Date() < end, !FileManager.default.fileExists(atPath: path) {
            pause(0.5)
        }
        return FileManager.default.fileExists(atPath: path)
    }

    /// A short, slow sequence for its own recording, `showcase.mp4`: select a
    /// word, show the menu, expand (iOS 26) or page (17/18) it, Look Up and
    /// close its sheet, the menu again, Copy. The workflow runs it in its own
    /// xcodebuild and records only while the app is set up: the test writes
    /// `showcase-ready` when the opening picture is on screen, the workflow
    /// starts `simctl io recordVideo` and answers `showcase-recording`; at the
    /// end the test writes `showcase-done` and keeps the app in front until
    /// the workflow answers `showcase-stopped`. Both ends hold a still picture
    /// (the caret blinking at the end of the field) for about 1.5 s.
    ///
    /// Before that, a warm-up Look Up that is not recorded: the first Look Up
    /// on a new simulator shows a first-run card ("Look Up now shows
    /// personalized suggestions", Continue) instead of a result; Continue is
    /// tapped there. When the warm-up could only get back to the app by a
    /// relaunch, Look Up is left out of the clip.
    private func showcase() {
        let scenario = "showcase"
        guard let app = launchApp(scenario) else { return }
        defer { app.terminate() }
        let spec = Self.spec("single")
        var notes = ["start=\(Self.stamp())", supportedLine(app)]
        defer { summary(scenario, notes) }

        // Warm-up (not recorded).
        var lookUpUsable = false
        var warmNotes: [String] = []
        let warm = focusAndSelect(app, spec, word: "harbor")
        if warm.ok, !menuRows(waitForMenu(app)).isEmpty, menuTap(app, "Look Up", notes: &warmNotes) {
            let seen = observeAfterTap(app, row: "Look Up")
            var card = "none"
            let continueButton = app.buttons.matching(NSPredicate(format: "label == 'Continue'")).firstMatch
            if inFront(app), continueButton.exists, continueButton.isHittable {
                continueButton.tap()
                pause(2.0)
                card = "Continue tapped"
            }
            saveScreenshot("\(scenario)-0-warmup-lookup")
            let closed = returnToApp(app)
            lookUpUsable = seen.outcome == "sheet" && !closed.contains("relaunch")
            notes.append("warmUp lookUp outcome=\(seen.outcome) firstRunCard=\(card) closedBy=\(closed)")
        } else {
            notes.append("warmUp: Look Up not reached (select=\(warm.ok))")
        }

        // The opening picture: no menu, the caret at the end of the field.
        resetApp(app)
        let focused = focusEnd(app, spec)
        pause(1.0)
        signal("showcase-ready")
        let recording = waitForSignal("showcase-recording", timeout: 60)
        notes.append("recording=\(recording ? "started" : "not started (no showcase-recording signal within 60 s)") "
            + "caretAtStart=\(focused)")
        pause(1.5)
        notes.append("clipStart=\(Self.stamp())")

        let selection = focusAndSelect(app, spec, word: "harbor", reset: false)
        let first = waitForMenu(app)
        notes.append("1 select=\(selection.ok ? "ok" : "FAILED") (\(selection.how)) menu=[\(labels(menuRows(first)))]")
        pause(2.0)
        if let chevron = chevronTarget(nodes: first, app: app) {
            tap(app, at: chevron.point)
            pause(2.0)
            notes.append("2 chevron tapped: menu=[\(labels(menuRows(snapshotNodes(app))))]")
        } else {
            notes.append("2 no chevron")
        }
        if !lookUpUsable {
            notes.append("3 Look Up left out (see warmUp)")
        } else {
            if rowNode("Look Up", in: menuRows(snapshotNodes(app))) == nil {
                // A paged menu (iOS 17/18) shows the next page now; Look Up
                // is on the first one, which a double tap on the word brings back.
                if let rect = readStatus(app).rect(of: "harbor") {
                    doubleTap(app, at: center(rect))
                }
                pause(1.5)
                notes.append("3 menu shown again for Look Up: [\(labels(menuRows(waitForMenu(app))))]")
            }
            if menuTap(app, "Look Up", notes: &notes) {
                let seen = observeAfterTap(app, row: "Look Up")
                pause(2.0)
                notes.append("3 lookUp outcome=\(seen.outcome) closedBy=\(returnToApp(app))")
                pause(1.5)
            } else {
                notes.append("3 Look Up not available")
            }
        }
        if let rect = readStatus(app).rect(of: "harbor") {
            doubleTap(app, at: center(rect))
        } else if let point = selection.point {
            doubleTap(app, at: point)
        }
        pause(1.0)
        var shown = !menuRows(waitForMenu(app)).isEmpty
        if !shown {
            let again = focusAndSelect(app, spec, word: "harbor", reset: false)
            shown = !menuRows(waitForMenu(app)).isEmpty
            notes.append("4 selected again (\(again.how))")
        }
        notes.append("4 menuAgain=\(shown)")
        pause(1.5)
        let copied = shown && menuTap(app, "Copy", notes: &notes)
        pause(1.5)
        notes.append("5 copy=\(copied) status: \(readStatus(app).oneLine)")

        // The closing picture: the caret at the end of the field again.
        let focusedAtEnd = focusEnd(app, spec)
        pause(1.5)
        notes.append("clipEnd=\(Self.stamp()) caretAtEnd=\(focusedAtEnd)")
        signal("showcase-done")
        let stopped = recording && waitForSignal("showcase-stopped", timeout: 60)
        notes.append("recordingStopped=\(stopped) inApp=\(inFront(app))")
        notes.append("RESULT=\(selection.ok && copied && recording && stopped ? "ok" : "partial")")
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

    /// A label can hold a line break (the iOS 18 share sheet has one), which
    /// would split a result line and leave its `RESULT=` on the next line.
    private func singleLine(_ text: String) -> String {
        text.components(separatedBy: .newlines).joined(separator: " ")
    }

    private func appendSummary(_ rawLine: String) {
        let line = singleLine(rawLine)
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
