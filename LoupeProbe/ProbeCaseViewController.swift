import UIKit

/// Shared screen for every case: a fixed-height header that explains the frame
/// (case, font size, iOS version, live state), the in-app hierarchy monitor
/// that logs which loupe-like views exist, and the JSON result.
///
/// The header never changes height, so nothing moves while a gesture is on.
class ProbeCaseViewController: UIViewController {
    let probeCase: ProbeCase
    /// The area below the header. Subclasses pin their content to it.
    let contentGuide = UILayoutGuide()
    /// Read by the UI test (native cases); shows the word's frame in window coordinates.
    let wordRectLabel = UILabel()
    /// One more status line, set by subclasses.
    var extraStatus = "" { didSet { refreshStatus() } }
    var state = "starting" {
        didSet {
            refreshStatus()
            Probe.log("state=\(state)")
        }
    }
    /// Written to `results/<case>.json` by `flush()`.
    var result: [String: Any] = [:]

    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let explainLabel = UILabel()
    private let statusLabel = UILabel()

    private var baseline: [String: Int]?
    private var timer: Timer?
    private var lastSignature = ""
    private var loupeSeen: [String: String] = [:]
    private var addedSeen: [String: Int] = [:]
    private var snapshotCount = 0

    init(probeCase: ProbeCase) {
        self.probeCase = probeCase
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? UIDevice.current.model
        let ios = UIDevice.current.systemVersion
        configure(titleLabel, id: "caseTitle", font: .monospacedSystemFont(ofSize: 16, weight: .bold), lines: 1)
        configure(detailLabel, id: "caseDetail", font: .monospacedSystemFont(ofSize: 12, weight: .regular), lines: 1)
        configure(explainLabel, id: "caseExplain", font: .systemFont(ofSize: 10), lines: 2)
        configure(statusLabel, id: "status", font: .monospacedSystemFont(ofSize: 10, weight: .regular), lines: 4)
        configure(wordRectLabel, id: "wordRect", font: .monospacedSystemFont(ofSize: 10, weight: .regular), lines: 1)
        titleLabel.text = probeCase.name
        detailLabel.text = "font \(Int(probeCase.fontSize)) pt  |  iOS \(ios)  |  \(model)"
        explainLabel.text = probeCase.explanation
        explainLabel.textColor = .secondaryLabel
        wordRectLabel.text = "word: unknown"

        let stack = UIStackView(arrangedSubviews: [titleLabel, detailLabel, explainLabel, statusLabel, wordRectLabel])
        stack.axis = .vertical
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        view.addLayoutGuide(contentGuide)

        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: safe.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            explainLabel.heightAnchor.constraint(equalToConstant: 26),
            statusLabel.heightAnchor.constraint(equalToConstant: 52),
            contentGuide.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 8),
            contentGuide.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
            contentGuide.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            contentGuide.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        result = [
            "case": probeCase.name,
            "kind": probeCase.kind.rawValue,
            "fontSize": Int(probeCase.fontSize),
            "word": ProbeCase.word,
            "ios": ios,
            "model": model,
            "startedMs": Probe.epochMs,
        ]
        refreshStatus()
        Probe.log("launch \(probeCase.name) iOS \(ios) \(model)")
    }

    private func configure(_ label: UILabel, id: String, font: UIFont, lines: Int) {
        label.font = font
        label.numberOfLines = lines
        label.lineBreakMode = .byTruncatingTail
        label.accessibilityIdentifier = id
    }

    func flush() {
        result["updatedMs"] = Probe.epochMs
        Probe.writeResult(result)
    }

    // MARK: - Hierarchy monitor

    /// Takes the baseline after `delay`, then logs every change of the windows'
    /// view classes every 0.1 s. Views that exist at the baseline are not
    /// reported later; classes that appear afterwards are, by name and frame.
    func beginMonitoring(baselineAfter delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            let scan = HierarchyScanner.scan()
            self.baseline = scan.counts
            Probe.log("baseline windows=[\(scan.windows.joined(separator: "; "))] views=\(scan.counts.values.reduce(0, +)) classes=\(scan.counts.count)")
            self.result["baselineWindows"] = scan.windows
            self.result["baselineClasses"] = scan.counts.keys.sorted()
            self.baselineDidCapture()
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
            // Common modes, so the timer also fires while touches are tracked.
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    /// Called once, right after the baseline.
    func baselineDidCapture() {}

    private func tick() {
        guard let baseline else { return }
        let scan = HierarchyScanner.scan()
        var added: [String: Int] = [:]
        for (name, count) in scan.counts {
            let extra = count - (baseline[name] ?? 0)
            if extra > 0 { added[name] = extra }
        }
        let loupe = scan.counts.keys.filter(HierarchyScanner.isLoupeLike).sorted()
        let signature = [
            scan.windows.joined(separator: ";"),
            loupe.joined(separator: ","),
            added.sorted { $0.key < $1.key }.map { "\($0.key)x\($0.value)" }.joined(separator: ","),
        ].joined(separator: "|")
        guard signature != lastSignature else { return }
        lastSignature = signature

        func describe(_ names: [String]) -> String {
            names.map { name in
                let frame = scan.frames[name]?.first.map { "@" + $0.probeText } ?? ""
                let count = scan.counts[name] ?? 0
                return "\(name)x\(count)\(frame)"
            }.joined(separator: " ")
        }
        Probe.log("hierarchy windows=[\(scan.windows.joined(separator: "; "))] loupe=[\(describe(loupe))] added=[\(describe(added.keys.sorted()))]")

        for name in loupe {
            loupeSeen[name] = scan.frames[name]?.first?.probeText ?? ""
        }
        for (name, count) in added {
            addedSeen[name] = max(addedSeen[name] ?? 0, count)
        }
        result["loupeSeen"] = !loupeSeen.isEmpty
        result["loupeClasses"] = loupeSeen.keys.sorted()
        result["loupeFrames"] = loupeSeen
        result["addedClasses"] = addedSeen
        result["lastWindows"] = scan.windows
        flush()
        refreshStatus()
        if !loupe.isEmpty, snapshotCount < 4 {
            snapshotCount += 1
            saveInAppSnapshot(snapshotCount)
        }
    }

    /// Draws every window of the app into one PNG. A system loupe that lives in
    /// another process does not show up here; the screenshots and the recording
    /// are the evidence for that.
    private func saveInAppSnapshot(_ number: Int) {
        guard let bounds = view.window?.bounds else { return }
        let image = UIGraphicsImageRenderer(bounds: bounds).image { _ in
            for window in HierarchyScanner.windows() where !window.isHidden {
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
            }
        }
        if let data = image.pngData() {
            Probe.write(data, to: "shots/inapp-\(probeCase.name)-\(number).png")
            Probe.log("in-app snapshot \(number) written")
        }
    }

    private func refreshStatus() {
        let loupe = loupeSeen.isEmpty ? "none" : loupeSeen.keys.sorted().joined(separator: ",")
        let added = addedSeen.isEmpty
            ? "none"
            : String(addedSeen.sorted { $0.key < $1.key }.map { "\($0.key)x\($0.value)" }.joined(separator: " ").prefix(110))
        statusLabel.text = "state=\(state)\nloupe-like views: \(loupe)\nnew classes: \(added)\n\(extraStatus)"
    }
}
