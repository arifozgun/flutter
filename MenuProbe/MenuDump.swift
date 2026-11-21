import UIKit
import os

/// Writes the probe's records. Every file goes to `$PROBE_OUT/trees` (a host
/// path the UI test passes in; the simulator can write there) and to the app's
/// Documents/trees as a fallback. Every line is also sent to the unified log
/// under the subsystem `dev.probe.editmenu`.
@MainActor
enum Probe {
    static let logger = Logger(subsystem: "dev.probe.editmenu", category: "probe")
    static var tag = "v00"
    private static var eventCount = 0

    static var directories: [URL] {
        var result: [URL] = []
        if let path = ProcessInfo.processInfo.environment["PROBE_OUT"], !path.isEmpty {
            result.append(URL(fileURLWithPath: path).appendingPathComponent("trees"))
        }
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            result.append(documents.appendingPathComponent("trees"))
        }
        return result
    }

    /// Writes `text` to `<tag>-<name>.txt`, replacing it or appending to it.
    static func write(_ name: String, _ text: String, append: Bool = false) {
        let data = Data(text.utf8)
        for directory in directories {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let file = directory.appendingPathComponent("\(tag)-\(name).txt")
                if append, FileManager.default.fileExists(atPath: file.path) {
                    let handle = try FileHandle(forWritingTo: file)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } else {
                    try data.write(to: file, options: .atomic)
                }
            } catch {
                logger.error("write failed \(directory.path, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            logger.info("\(tag, privacy: .public) \(name, privacy: .public) | \(String(line), privacy: .public)")
        }
    }

    /// Appends one timestamped line to `<tag>-events.txt`.
    static func event(_ message: String) {
        eventCount += 1
        let stamp = String(format: "%.3f", Date().timeIntervalSince1970)
        write("events", "[\(stamp)] #\(eventCount) \(message)\n", append: true)
    }
}

/// Renders a menu element tree with every public property that can affect how
/// UIKit draws it.
@MainActor
enum MenuDump {
    static func describe(_ elements: [UIMenuElement]) -> String {
        var lines: [String] = []
        for element in elements {
            append(element, depth: 0, into: &lines)
        }
        if elements.isEmpty {
            lines.append("(no elements)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func append(_ element: UIMenuElement, depth: Int, into lines: inout [String]) {
        let indent = String(repeating: "  ", count: depth)
        var fields: [String] = []
        fields.append("class=\(NSStringFromClass(type(of: element)))")
        fields.append("title=\"\(element.title)\"")
        if let subtitle = element.subtitle {
            fields.append("subtitle=\"\(subtitle)\"")
        }
        fields.append("image=\(imageDescription(element.image))")
        if let visibility = imageVisibility(element) {
            fields.append("preferredImageVisibility=\(visibility)")
        }

        if let menu = element as? UIMenu {
            fields.append("identifier=\(menu.identifier.rawValue)")
            fields.append("options=\(optionNames(menu.options))")
            fields.append("preferredElementSize=\(sizeName(menu.preferredElementSize))")
            if #available(iOS 17.4, *), let preferences = menu.displayPreferences {
                fields.append("maximumNumberOfTitleLines=\(preferences.maximumNumberOfTitleLines)")
            }
            fields.append("selectedElements=\(menu.selectedElements.count)")
            fields.append("children=\(menu.children.count)")
            lines.append(indent + "MENU " + fields.joined(separator: " "))
            for child in menu.children {
                append(child, depth: depth + 1, into: &lines)
            }
            return
        }

        if let command = element as? UICommand {
            fields.append("action=\(NSStringFromSelector(command.action))")
            if let propertyList = command.propertyList {
                fields.append("propertyList=\(String(describing: propertyList))")
            }
            fields.append("attributes=\(attributeNames(command.attributes))")
            fields.append("state=\(command.state.rawValue)")
            if let discoverability = command.discoverabilityTitle {
                fields.append("discoverabilityTitle=\"\(discoverability)\"")
            }
            fields.append("alternates=\(command.alternates.count)")
            if let keyCommand = command as? UIKeyCommand {
                fields.append("input=\(keyCommand.input ?? "nil") modifiers=\(keyCommand.modifierFlags.rawValue)")
            }
            lines.append(indent + "COMMAND " + fields.joined(separator: " "))
            return
        }

        if let action = element as? UIAction {
            fields.append("identifier=\(action.identifier.rawValue)")
            fields.append("attributes=\(attributeNames(action.attributes))")
            fields.append("state=\(action.state.rawValue)")
            if let discoverability = action.discoverabilityTitle {
                fields.append("discoverabilityTitle=\"\(discoverability)\"")
            }
            lines.append(indent + "ACTION " + fields.joined(separator: " "))
            return
        }

        if element is UIDeferredMenuElement {
            lines.append(indent + "DEFERRED " + fields.joined(separator: " "))
            return
        }

        lines.append(indent + "ELEMENT " + fields.joined(separator: " "))
    }

    /// Short form of an image: the SF Symbol name when the description names
    /// one, otherwise the full description.
    static func imageDescription(_ image: UIImage?) -> String {
        guard let image else { return "nil" }
        let text = String(describing: image)
        if let start = text.range(of: "symbol(") {
            let tail = text[start.lowerBound...]
            if let end = tail.firstIndex(of: ")") {
                return "yes:" + String(tail[...end])
            }
        }
        return "yes:<\(text)>"
    }

    /// `preferredImageVisibility` exists from iOS 27. It is read by key so the
    /// probe also compiles with the iOS 26 SDK.
    static func imageVisibility(_ element: UIMenuElement) -> String? {
        guard element.responds(to: NSSelectorFromString("preferredImageVisibility")) else { return nil }
        guard let raw = (element.value(forKey: "preferredImageVisibility") as? NSNumber)?.intValue else { return "?" }
        switch raw {
        case 0: return "0[automatic]"
        case 1: return "1[visible]"
        case 2: return "2[hidden]"
        default: return "\(raw)"
        }
    }

    static func optionNames(_ options: UIMenu.Options) -> String {
        var names: [String] = []
        if options.contains(.displayInline) { names.append("displayInline") }
        if options.contains(.destructive) { names.append("destructive") }
        if options.contains(.singleSelection) { names.append("singleSelection") }
        if #available(iOS 17.0, *), options.contains(.displayAsPalette) { names.append("displayAsPalette") }
        return "\(options.rawValue)[\(names.joined(separator: ","))]"
    }

    static func sizeName(_ size: UIMenu.ElementSize) -> String {
        let name: String
        if size == .small {
            name = "small"
        } else if size == .medium {
            name = "medium"
        } else if size == .large {
            name = "large"
        } else if #available(iOS 17.0, *), size == .automatic {
            name = "automatic"
        } else {
            name = "unknown"
        }
        return "\(size.rawValue)[\(name)]"
    }

    static func attributeNames(_ attributes: UIMenuElement.Attributes) -> String {
        var names: [String] = []
        if attributes.contains(.disabled) { names.append("disabled") }
        if attributes.contains(.destructive) { names.append("destructive") }
        if attributes.contains(.hidden) { names.append("hidden") }
        if attributes.contains(.keepsMenuPresented) { names.append("keepsMenuPresented") }
        return "\(attributes.rawValue)[\(names.joined(separator: ","))]"
    }
}

/// Records every selector UIKit asks a responder about, in first-asked order,
/// with the answer given. Only names are recorded; nothing is called.
@MainActor
final class ActionLog {
    private let name: String
    private var order: [String] = []
    private var answers: [String: String] = [:]
    private var counts: [String: Int] = [:]
    private var flushScheduled = false

    init(name: String) {
        self.name = name
    }

    func record(_ action: Selector, answer: Bool, defaultAnswer: Bool, sender: Any?) {
        let key = NSStringFromSelector(action)
        if answers[key] == nil {
            order.append(key)
        }
        let senderClass = sender.map { String(describing: type(of: $0)) } ?? "nil"
        answers[key] = "answer=\(answer) super=\(defaultAnswer) sender=\(senderClass)"
        counts[key, default: 0] += 1
        scheduleFlush()
    }

    func flush() {
        var lines = ["# selector | asked count | last answer (super = what UIResponder/UITextView would answer)"]
        for key in order {
            lines.append("\(key) | \(counts[key] ?? 0) | \(answers[key] ?? "")")
        }
        Probe.write(name, lines.joined(separator: "\n") + "\n")
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.flushScheduled = false
            self?.flush()
        }
    }
}
