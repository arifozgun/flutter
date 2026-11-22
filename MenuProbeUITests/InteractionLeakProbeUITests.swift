import UIKit
import XCTest

/// Drives the interaction leak probe of the UIKit probe app
/// (`-ilVariant <id>`): a custom UITextInput view that gets a new
/// UITextInteraction before each edit menu and loses it again keeps two
/// interactions per menu in the Flutter engine prototype. Which classes are
/// left behind, and which way of adding and removing avoids it?
///
/// Every variant is its own test method and app launch. The cycles run inside
/// the app (10 per variant, with the waits the menu animations need); the test
/// launches the variant, waits until the app's `ilPhase` label reads
/// `phase=done`, and copies the app's one-line result
/// (`trees/il-<id>-result.txt`) to `summary.txt`. Nothing here fails a test
/// except an app that never finishes, so one variant cannot stop the others.
@MainActor
final class InteractionLeakProbeUITests: XCTestCase {
    func test_01_add_remove() { run("v1-add-remove") }
    func test_02_add_wait_remove() { run("v2-add-wait-remove") }
    func test_03_nil_then_remove() { run("v3-nil-then-remove") }
    func test_04_reuse_object() { run("v4-reuse-object") }
    func test_05_menu_cycle() { run("v5-menu-cycle") }
    func test_06_menu_cycle_reuse() { run("v6-menu-cycle-reuse") }
    func test_07_menu_only() { run("v7-menu-only") }
    func test_08_permanent() { run("v8-permanent") }

    // MARK: - Shared

    private var outDir: URL {
        let path = ProcessInfo.processInfo.environment["PROBE_OUT"] ?? ""
        if !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("menu-probe-out")
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

    // MARK: - One variant

    private func run(_ id: String) {
        continueAfterFailure = true
        let tag = "il-\(id)"
        let head = "\(tag) | device=\(deviceName) | ios=\(iosVersion)"
        let app = XCUIApplication()
        app.launchArguments = ["-ilVariant", id]
        app.launchEnvironment["PROBE_OUT"] = outDir.path
        app.launch()

        let problem = waitForDone(app, timeout: 300)
        let file = outDir.appendingPathComponent("trees/\(tag)-result.txt")
        let result = (try? String(contentsOf: file, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let result, !result.isEmpty {
            appendSummary("\(head) | \(result)" + (problem.map { " | test=[\($0)]" } ?? ""))
        } else {
            appendSummary("\(head) | no result file | test=[\(problem ?? "the app reported done but wrote no result")]")
        }
        if let problem {
            XCTFail("\(tag): \(problem)")
        }
        app.terminate()
    }

    // MARK: - The app's labels

    private func readLabel(_ app: XCUIApplication, _ identifier: String) -> String? {
        let element = app.staticTexts[identifier]
        return element.exists ? element.label : nil
    }

    /// nil when the app reported `phase=done`, else what went wrong.
    private func waitForDone(_ app: XCUIApplication, timeout: TimeInterval) -> String? {
        let end = Date().addingTimeInterval(timeout)
        var last = "no label"
        while Date() < end {
            if app.state == .notRunning {
                return "the app stopped running (crash?); last phase: \(last)"
            }
            if let label = readLabel(app, "ilPhase") {
                last = label
                if label.hasPrefix("phase=done ") {
                    return nil
                }
            }
            pause(2.0)
        }
        return "no phase=done within \(Int(timeout)) s; last phase: \(last)"
    }

    // MARK: - Output

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
            print("interaction-leak-probe: could not write \(file.path): \(error)")
        }
    }
}
