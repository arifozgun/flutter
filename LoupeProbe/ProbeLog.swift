import CoreGraphics
import Foundation
import os

/// Logging and result files. Everything is written twice: into the app's
/// Documents folder, and, when the UI test passes `PROBE_OUT`, into
/// `$PROBE_OUT/app/` (the simulator shares the host file system).
enum Probe {
    static let subsystem = "dev.probe.nativeloupe"
    private static let logger = Logger(subsystem: subsystem, category: "probe")

    static var caseName = "startup"

    static var epochMs: Int { Int(Date().timeIntervalSince1970 * 1000) }

    private static var directories: [URL] {
        var urls = [FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]]
        if let path = ProcessInfo.processInfo.environment["PROBE_OUT"], !path.isEmpty {
            urls.append(URL(fileURLWithPath: path).appendingPathComponent("app"))
        }
        return urls
    }

    /// Appends one line to `log-<case>.txt` and the unified log.
    static func log(_ message: String) {
        let line = "\(epochMs) \(caseName) \(message)"
        logger.info("\(line, privacy: .public)")
        append(Data((line + "\n").utf8), to: "log-\(caseName).txt")
    }

    /// Replaces `results/<case>.json` with one JSON line.
    static func writeResult(_ result: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(result),
              var data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        else {
            log("result is not valid JSON: \(result)")
            return
        }
        data.append(0x0A)
        write(data, to: "results/\(caseName).json")
        logger.info("result \(String(decoding: data, as: UTF8.self), privacy: .public)")
    }

    static func write(_ data: Data, to relativePath: String) {
        for directory in directories {
            let file = directory.appendingPathComponent(relativePath)
            do {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
            } catch {
                logger.error("could not write \(file.path, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
    }

    private static func append(_ data: Data, to relativePath: String) {
        for directory in directories {
            let file = directory.appendingPathComponent(relativePath)
            do {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: file.path), let handle = try? FileHandle(forWritingTo: file) {
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                    try? handle.close()
                } else {
                    try data.write(to: file, options: .atomic)
                }
            } catch {
                logger.error("could not append to \(file.path, privacy: .public)")
            }
        }
    }
}

extension CGRect {
    /// `[x, y, width, height]` rounded to a tenth, for JSON.
    var probeArray: [Double] {
        [Double(minX), Double(minY), Double(width), Double(height)].map { ($0 * 10).rounded() / 10 }
    }

    /// `x,y,WxH` rounded to whole points, for logs and labels.
    var probeText: String {
        String(format: "%.0f,%.0f,%.0fx%.0f", minX, minY, width, height)
    }
}
