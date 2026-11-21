import UIKit

/// What is in the app's windows right now: class names and frames of every
/// view (and every layer that has no view), over all windows of all scenes,
/// including system-owned ones such as the text effects window.
struct HierarchyScan {
    /// One entry per window: `Class@level:frame`.
    var windows: [String] = []
    /// Class name to how many instances exist.
    var counts: [String: Int] = [:]
    /// Class name to the first few frames, in window coordinates.
    var frames: [String: [CGRect]] = [:]
}

enum HierarchyScanner {
    /// Name fragments that mark a loupe or magnifier view. The names UIKit uses
    /// are private, so the monitor also reports every class that appeared after
    /// the baseline, whatever it is called.
    static func isLoupeLike(_ className: String) -> Bool {
        let name = className.lowercased()
        return name.contains("loupe") || name.contains("magnif") || name.contains("lollipop")
    }

    static func windows() -> [UIWindow] {
        var found: [UIWindow] = []
        func add(_ window: UIWindow) {
            if !found.contains(where: { $0 === window }) {
                found.append(window)
            }
        }
        for scene in UIApplication.shared.connectedScenes {
            (scene as? UIWindowScene)?.windows.forEach(add)
        }
        // Deprecated, but it also lists windows that a scene does not.
        UIApplication.shared.windows.forEach(add)
        return found.sorted { $0.windowLevel.rawValue < $1.windowLevel.rawValue }
    }

    static func scan() -> HierarchyScan {
        var result = HierarchyScan()
        var visited = 0

        func record(_ name: String, frame: CGRect) {
            result.counts[name, default: 0] += 1
            if (result.frames[name]?.count ?? 0) < 3 {
                result.frames[name, default: []].append(frame)
            }
        }

        func walk(_ view: UIView, depth: Int) {
            visited += 1
            if visited > 6000 || depth > 60 { return }
            record(String(describing: type(of: view)), frame: view.convert(view.bounds, to: nil))
            // Layers that no view owns (portal layers, backdrops, ...).
            for layer in view.layer.sublayers ?? [] where !(layer.delegate is UIView) {
                record("layer:" + String(describing: type(of: layer)), frame: layer.frame)
            }
            for child in view.subviews {
                walk(child, depth: depth + 1)
            }
        }

        for window in windows() {
            let level = Int(window.windowLevel.rawValue)
            let flags = (window.isHidden ? " hidden" : "") + (window.isKeyWindow ? " key" : "")
            result.windows.append("\(type(of: window))@\(level):\(window.frame.probeText)\(flags)")
            walk(window, depth: 0)
        }
        return result
    }
}
