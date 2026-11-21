import XCTest

/// One test per case, so a failing case does not stop the others. A case that
/// shows no loupe is a result, not a failure: the tests fail only when the app
/// did not launch, never became ready, or the gesture could not be performed.
///
/// Native cases (UITextView, UITextField): long-press inside the word, drag
/// slowly to the right and hold, so that the loupe is on screen for about two
/// seconds. Session cases: the app holds its own UITextLoupeSession for two
/// seconds; the test only screenshots it.
///
/// Evidence for the loupe, from most to least certain:
///   1. the screen recording of the whole run (made by the workflow),
///   2. simctl screenshots taken by the workflow every ~0.3 s while
///      `shoot-now` exists (the test creates that file around each gesture),
///   3. the app's own hierarchy log and JSON result.
///
/// The test does not screenshot from inside the gesture: XCUIScreenshotProviding
/// is main-actor isolated and the gesture call blocks the main thread, so a
/// capture from the test process would be a nested XCUITest call. The
/// workflow's simctl loop takes the timed captures from outside instead.
@MainActor
final class LoupeProbeUITests: XCTestCase {
    func test_textview_17() { probe("textview-17") }
    func test_textview_48() { probe("textview-48") }
    func test_textview_96() { probe("textview-96") }
    func test_textview_150() { probe("textview-150") }
    func test_textview_220() { probe("textview-220") }
    func test_textfield_17() { probe("textfield-17") }
    func test_textfield_48() { probe("textfield-48") }
    func test_textfield_96() { probe("textfield-96") }
    func test_textfield_150() { probe("textfield-150") }
    func test_textfield_220() { probe("textfield-220") }
    func test_session_widget_17() { probe("session-widget-17") }
    func test_session_widget_48() { probe("session-widget-48") }
    func test_session_widget_96() { probe("session-widget-96") }
    func test_session_widget_150() { probe("session-widget-150") }
    func test_session_widget_220() { probe("session-widget-220") }
    func test_session_nil_17() { probe("session-nil-17") }
    func test_session_nil_48() { probe("session-nil-48") }
    func test_session_nil_96() { probe("session-nil-96") }
    func test_session_nil_150() { probe("session-nil-150") }
    func test_session_nil_220() { probe("session-nil-220") }

    // MARK: - Probe

    private var outDir: URL {
        let path = ProcessInfo.processInfo.environment["PROBE_OUT"] ?? ""
        if !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("loupe-probe-out")
    }

    private func probe(_ name: String) {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = ["-case", name]
        app.launchEnvironment["PROBE_OUT"] = outDir.path
        event(name, "launching")
        app.launch()

        guard app.staticTexts["caseTitle"].waitForExistence(timeout: 30) else {
            saveScreenshot("\(name)-0-launch-failed")
            saveText("\(name)-0-launch-failed-hierarchy", app.debugDescription)
            appendSummary("\(name) | launch failed: caseTitle never appeared")
            XCTFail("\(name): the app did not show its header")
            return
        }
        event(name, "app is showing the case")

        if name.hasPrefix("textview-") || name.hasPrefix("textfield-") {
            runNative(name, app)
        } else {
            runSession(name, app)
        }
        app.terminate()
        event(name, "finished")
    }

    // MARK: - Native cases

    private func runNative(_ name: String, _ app: XCUIApplication) {
        guard waitForStatus(app, containing: "state=ready", timeout: 45) else {
            saveScreenshot("\(name)-1-never-ready")
            saveText("\(name)-1-never-ready-hierarchy", app.debugDescription)
            appendSummary("\(name) | never ready | status=\(statusText(app))")
            XCTFail("\(name): the case never became ready")
            return
        }
        saveScreenshot("\(name)-1-ready")
        guard let word = wordRect(app) else {
            appendSummary("\(name) | no word rect | status=\(statusText(app))")
            XCTFail("\(name): the app did not publish the word's frame")
            return
        }
        let screenWidth = app.frame.width
        let start = CGPoint(x: word.minX + word.width * 0.3, y: word.midY)
        let travel = min(120, max(40, word.width * 0.6))
        let end = CGPoint(x: min(start.x + travel, screenWidth - 12), y: start.y)
        event(name, "gesture: press at \(Int(start.x)),\(Int(start.y)) drag to \(Int(end.x)),\(Int(end.y))")

        // The workflow's simctl loop takes screenshots while this file exists.
        setShootMarker(name)
        let began = Date()
        coordinate(app, start).press(
            forDuration: 1.0,
            thenDragTo: coordinate(app, end),
            withVelocity: XCUIGestureVelocity(rawValue: 80),
            thenHoldForDuration: 2.0
        )
        let took = Date().timeIntervalSince(began)
        event(name, "gesture returned after \(String(format: "%.1f", took)) s")
        Thread.sleep(forTimeInterval: 0.4)
        clearShootMarker()
        Thread.sleep(forTimeInterval: 0.6)
        saveScreenshot("\(name)-3-after")
        let status = statusText(app).replacingOccurrences(of: "\n", with: " / ")
        appendSummary("\(name) | gesture \(String(format: "%.1f", took)) s | status=\(status) | result=\(appResult(name))")
    }

    // MARK: - Session cases

    private func runSession(_ name: String, _ app: XCUIApplication) {
        guard waitForStatus(app, containing: "state=holding", timeout: 45) else {
            saveScreenshot("\(name)-1-never-held")
            saveText("\(name)-1-never-held-hierarchy", app.debugDescription)
            appendSummary("\(name) | session never started | status=\(statusText(app))")
            XCTFail("\(name): the app never started its session")
            return
        }
        setShootMarker(name)
        Thread.sleep(forTimeInterval: 0.5)
        saveScreenshot("\(name)-1-held")
        Thread.sleep(forTimeInterval: 0.7)
        saveScreenshot("\(name)-2-held")
        let status = statusText(app).replacingOccurrences(of: "\n", with: " / ")
        _ = waitForStatus(app, containing: "state=done", timeout: 15)
        clearShootMarker()
        saveScreenshot("\(name)-3-after")
        appendSummary("\(name) | status=\(status) | result=\(appResult(name))")
    }

    // MARK: - App state

    private func statusText(_ app: XCUIApplication) -> String {
        let label = app.staticTexts["status"]
        return label.exists ? label.label : "(no status label)"
    }

    private func waitForStatus(_ app: XCUIApplication, containing text: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if statusText(app).contains(text) { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    /// The word's frame, published by the app as "word: x y w h".
    private func wordRect(_ app: XCUIApplication) -> CGRect? {
        let label = app.staticTexts["wordRect"]
        guard label.exists else { return nil }
        let parts = label.label.replacingOccurrences(of: "word: ", with: "")
            .split(separator: " ").compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    /// The app's JSON line for the case, as the app wrote it into PROBE_OUT.
    private func appResult(_ name: String) -> String {
        let file = outDir.appendingPathComponent("app/results/\(name).json")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return "(no result file)" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Output

    private func coordinate(_ app: XCUIApplication, _ point: CGPoint) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: point.x, dy: point.y))
    }

    /// While this file exists, the workflow's loop takes simctl screenshots
    /// named after its content.
    private func setShootMarker(_ name: String) {
        write(Data(name.utf8), to: outDir.appendingPathComponent("shoot-now"))
    }

    private func clearShootMarker() {
        try? FileManager.default.removeItem(at: outDir.appendingPathComponent("shoot-now"))
    }

    private func saveScreenshot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        attach(screenshot.pngRepresentation, name: name)
    }

    private func attach(_ png: Data, name: String) {
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        write(png, to: outDir.appendingPathComponent("screens/\(name).png"))
    }

    private func saveText(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        write(Data(text.utf8), to: outDir.appendingPathComponent("hierarchy/\(name).txt"))
    }

    private func appendSummary(_ line: String) {
        append(Data((line + "\n").utf8), to: outDir.appendingPathComponent("summary.txt"))
        let attachment = XCTAttachment(string: line)
        attachment.name = "summary"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// One line per step with the epoch time in ms, to line the recording and
    /// the app log up with the test.
    private func event(_ name: String, _ message: String) {
        let ms = Int(Date().timeIntervalSince1970 * 1000)
        append(Data("\(ms) \(name) \(message)\n".utf8), to: outDir.appendingPathComponent("events.txt"))
    }

    private func write(_ data: Data, to file: URL) {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            print("loupe-probe: could not write \(file.path): \(error)")
        }
    }

    private func append(_ data: Data, to file: URL) {
        if FileManager.default.fileExists(atPath: file.path), let handle = try? FileHandle(forWritingTo: file) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            write(data, to: file)
        }
    }
}
