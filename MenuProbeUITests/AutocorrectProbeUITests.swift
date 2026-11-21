import XCTest

/// Drives the autocorrect harness of the UIKit probe app (`-acVariant <id>`):
/// does the keyboard commit a pending autocorrection when the selection
/// changes, natively, in a custom UITextInput view, and after a
/// UITextInteraction was attached and removed around an edit menu?
///
/// Every variant is its own test method and app launch. The app runs the
/// variant as a timed script and asks for the steps only a person can do
/// through its `acPhase` label: `type` (type "abc" by tapping keys on the
/// software keyboard, so that autocorrection engages), `tapEnd` / `tapStart`
/// (a real tap at the points in `acTapPoints`). When the phase is `done`, the
/// `acResult` label holds the app's result; the test appends it, the
/// keyboard's suggestions after typing and its own notes as one line of
/// `summary.txt`. Nothing here fails a test except a launch that never shows
/// the screen, so one variant cannot stop the others.
@MainActor
final class AutocorrectProbeUITests: XCTestCase {
    // Sequence T first, so a run cut short still has it.
    func test_01_t01() { run("t01-sequence-T") }
    func test_02_n01() { run("n01-textview-tap") }
    func test_03_n02() { run("n02-textview-set") }
    func test_04_n03() { run("n03-textfield-tap") }
    func test_05_n04() { run("n04-textfield-set") }
    func test_06_s01() { run("s01-stock-set") }
    func test_07_s02() { run("s02-stock-tap") }
    func test_08_s03() { run("s03-stock-silent") }
    func test_09_s04() { run("s04-stock-1x1") }
    func test_10_s05() { run("s05-stock-inline-default") }
    func test_11_t02() { run("t02-sequence-T-taps") }
    func test_12_f01() { run("f01-interaction-only") }
    func test_13_f02() { run("f02-menu-only") }
    func test_14_f03() { run("f03-remove-willDismiss") }
    func test_15_f04() { run("f04-remove-2s-after") }
    func test_16_f05() { run("f05-remove-never") }
    func test_17_f06() { run("f06-move-after-removal") }
    func test_18_f07() { run("f07-noguard") }
    func test_19_f08() { run("f08-noguard-workaround") }
    func test_20_f09() { run("f09-noguard-restore") }
    func test_21_f10() { run("f10-history-same-session") }
    func test_22_f11() { run("f11-history-earlier-session") }
    func test_23_f12() { run("f12-second-menu-firstkey") }
    func test_24_f13() { run("f13-second-menu-before-typing") }
    func test_25_f14() { run("f14-second-tap") }
    func test_26_f15() { run("f15-textinput-nil") }
    func test_27_f16() { run("f16-release") }
    func test_28_f17() { run("f17-two-cycles-same") }
    func test_29_f18() { run("f18-two-cycles-new") }
    func test_30_f19() { run("f19-reload-input-views") }
    func test_31_f20() { run("f20-resign-become") }
    func test_32_f21() { run("f21-selection-nudge") }
    func test_33_f22() { run("f22-text-nudge") }
    func test_34_f23() { run("f23-T-silent") }
    func test_35_f24() { run("f24-T-1x1") }
    func test_36_f25() { run("f25-T-normal-layout") }
    func test_37_f26() { run("f26-T-inline-default") }
    func test_38_f27() { run("f27-noneditable") }
    func test_39_f28() { run("f28-shouldbegin-no") }
    func test_40_t99() { run("t99-sequence-T-repeat") }

    // MARK: - Shared

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

    // MARK: - One variant

    private func run(_ id: String) {
        continueAfterFailure = true
        let tag = "ac-\(id)"
        var notes = ["start=\(Self.stamp())"]
        let app = XCUIApplication()
        app.launchArguments = ["-acVariant", id]
        app.launchEnvironment["PROBE_OUT"] = outDir.path
        app.launch()

        guard app.staticTexts["acPhase"].waitForExistence(timeout: 30) else {
            saveScreenshot("\(tag)-0-launch-failed")
            saveText("\(tag)-0-launch-failed-hierarchy", app.debugDescription)
            appendSummary("\(tag) | ios=\(iosVersion) | committed=unknown | launch failed: acPhase never appeared")
            XCTFail("\(tag): the app did not show the harness screen")
            app.terminate()
            return
        }

        var lastSeq = 0
        var done = false
        var suggestions: [String] = []
        var literalOffered = "unknown"
        let deadline = Date().addingTimeInterval(150)
        while Date() < deadline, !done {
            let (phase, seq) = readPhase(app)
            if seq > lastSeq {
                lastSeq = seq
                switch phase {
                case "menuShown":
                    pause(0.6)
                    saveScreenshot("\(tag)-\(seq)-menu-shown")
                case "type":
                    let how = typeKeys(app, "abc")
                    // Read right away: the app changes the selection 3.5 s
                    // after the last key.
                    let nodes = snapshotNodes(app)
                    suggestions = predictionCandidates(nodes).map(\.label)
                    literalOffered = suggestions.isEmpty
                        ? "unknown"
                        : String(suggestions.contains { $0.hasPrefix("\u{201C}") || $0.hasPrefix("\"") })
                    saveScreenshot("\(tag)-\(seq)-typed")
                    if suggestions.isEmpty {
                        saveText("\(tag)-\(seq)-typed-hierarchy", describe(nodes))
                    }
                    notes.append("type#\(seq) \(how) suggestions=[\(suggestions.joined(separator: ", "))]")
                case "tapStart", "tapEnd":
                    if let point = tapPoint(app, phase == "tapStart" ? "start" : "end") {
                        tap(app, at: point)
                        notes.append("\(phase)#\(seq) tapped at \(Int(point.x)),\(Int(point.y)) at \(Self.stamp())")
                    } else {
                        notes.append("\(phase)#\(seq) no tap points; not tapped")
                    }
                    pause(0.8)
                    saveScreenshot("\(tag)-\(seq)-after-\(phase)")
                case "done":
                    done = true
                default:
                    break
                }
            }
            if !done {
                pause(0.3)
            }
        }

        var result = "committed=unknown | result missing: the app never reached done"
        if done {
            let element = app.staticTexts["acResult"]
            if element.exists {
                result = element.label
            }
        }
        saveScreenshot("\(tag)-done")
        appendSummary(
            "\(tag) | ios=\(iosVersion) | \(result) | suggestionsBeforeChange=[\(suggestions.joined(separator: ", "))]"
                + " | literalOffered=\(literalOffered) | test=[\(notes.joined(separator: "; "))]"
        )
        app.terminate()
    }

    /// "phase=<name> seq=<n>" from the app's `acPhase` label.
    private func readPhase(_ app: XCUIApplication) -> (String, Int) {
        let element = app.staticTexts["acPhase"]
        guard element.exists else { return ("", 0) }
        var phase = ""
        var seq = 0
        for part in element.label.split(separator: " ") {
            if part.hasPrefix("phase=") {
                phase = String(part.dropFirst(6))
            } else if part.hasPrefix("seq=") {
                seq = Int(part.dropFirst(4)) ?? 0
            }
        }
        return (phase, seq)
    }

    /// "tapPoints: start=x,y end=x,y" from the app's `acTapPoints` label.
    private func tapPoint(_ app: XCUIApplication, _ name: String) -> CGPoint? {
        let element = app.staticTexts["acTapPoints"]
        guard element.exists else { return nil }
        for part in element.label.split(separator: " ") where part.hasPrefix("\(name)=") {
            let numbers = part.dropFirst(name.count + 1).split(separator: ",").compactMap { Double($0) }
            if numbers.count == 2 {
                return CGPoint(x: numbers[0], y: numbers[1])
            }
        }
        return nil
    }

    private func tap(_ app: XCUIApplication, at point: CGPoint) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: point.x, dy: point.y))
            .tap()
    }

    // MARK: - Keyboard (as FlutterMenuUITests)

    /// Types by tapping the software keyboard's keys; a character without a
    /// hittable key goes through typeText. Returns how.
    private func typeKeys(_ app: XCUIApplication, _ text: String) -> String {
        guard app.keyboards.firstMatch.exists else { return "no keyboard on screen; nothing typed" }
        var viaKeys = 0
        var viaTypeText = 0
        for character in text {
            let lower = app.keys[String(character)]
            let upper = app.keys[String(character).uppercased()]
            if lower.exists, lower.isHittable {
                lower.tap()
                viaKeys += 1
            } else if upper.exists, upper.isHittable {
                upper.tap()
                viaKeys += 1
            } else {
                app.typeText(String(character))
                viaTypeText += 1
            }
            pause(0.15)
        }
        pause(0.5)
        return "keys=\(viaKeys) typeText=\(viaTypeText) at \(Self.stamp())"
    }

    struct Node {
        let index: Int
        let ancestors: [Int]
        let type: XCUIElement.ElementType
        let label: String
        let identifier: String
        let frame: CGRect
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

    /// The suggestions in the keyboard's prediction bar, one per label.
    private func predictionCandidates(_ nodes: [Node]) -> [Node] {
        guard let bar = nodes.first(where: { $0.label == "Typing Predictions" }) else { return [] }
        var seen = Set<String>()
        return nodes.filter { node in
            node.ancestors.contains(bar.index) && !node.label.isEmpty && seen.insert(node.label).inserted
        }
    }

    private func describe(_ nodes: [Node]) -> String {
        var lines = ["=== snapshot at \(Self.stamp()): \(nodes.count) nodes"]
        for node in nodes {
            let indent = String(repeating: "  ", count: node.ancestors.count)
            let f = node.frame
            lines.append("\(indent)#\(node.index) type=\(node.type.rawValue) label=\"\(node.label)\" id=\"\(node.identifier)\" frame=\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width))x\(Int(f.height))")
        }
        return lines.joined(separator: "\n")
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
            print("autocorrect-probe: could not write \(file.path): \(error)")
        }
    }
}
