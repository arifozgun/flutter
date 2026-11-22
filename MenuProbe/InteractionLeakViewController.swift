import UIKit

/// One variant of the interaction leak probe (`-ilVariant <id>`).
/// README.md ("Interaction leak probe") has the table.
struct ILVariant {
    enum Kind {
        /// A new UITextInteraction is added and removed at once. No menu.
        case addRemove
        /// A new interaction is added, 1 s later removed. No menu.
        case addWaitRemove
        /// A new interaction is added, its textInput set to nil, then removed.
        case nilThenRemove
        /// One interaction object, added and removed in every cycle.
        case reuseObject
        /// The prototype: a new interaction is added right before the edit menu
        /// is presented and removed in the completion of the dismissal animator.
        case menuCycle
        /// As menuCycle, with one interaction object for all cycles.
        case menuCycleReuse
        /// The menu only, no text interaction (control).
        case menuOnly
        /// One interaction attached before the first menu, never removed (control).
        case permanent
    }

    static let cycles = 10

    let id: String
    let what: String
    let kind: Kind

    /// Every cycle presents and dismisses the edit menu.
    var presentsMenu: Bool {
        switch kind {
        case .menuCycle, .menuCycleReuse, .menuOnly, .permanent: return true
        case .addRemove, .addWaitRemove, .nilThenRemove, .reuseObject: return false
        }
    }

    /// One interaction object is used for every cycle.
    var reusesObject: Bool { kind == .reuseObject || kind == .menuCycleReuse }

    static func named(_ id: String) -> ILVariant? {
        all.first { $0.id == id } ?? all.first { $0.id.hasPrefix(id + "-") }
    }

    static let all: [ILVariant] = [
        ILVariant(id: "v1-add-remove", what: "10 cycles: add a new UITextInteraction, remove it at once. No menu.", kind: .addRemove),
        ILVariant(id: "v2-add-wait-remove", what: "10 cycles: add a new interaction, wait 1 s, remove it. No menu.", kind: .addWaitRemove),
        ILVariant(id: "v3-nil-then-remove", what: "10 cycles: add a new interaction, set textInput = nil, remove it. No menu.", kind: .nilThenRemove),
        ILVariant(id: "v4-reuse-object", what: "10 cycles: add and remove one interaction object. No menu.", kind: .reuseObject),
        ILVariant(id: "v5-menu-cycle", what: "10 cycles: add a new interaction, present the edit menu, dismiss it, remove the interaction in the dismissal completion.", kind: .menuCycle),
        ILVariant(id: "v6-menu-cycle-reuse", what: "As v5 with one interaction object for all cycles.", kind: .menuCycleReuse),
        ILVariant(id: "v7-menu-only", what: "10 cycles: present and dismiss the edit menu, no text interaction (control).", kind: .menuOnly),
        ILVariant(id: "v8-permanent", what: "10 menu cycles with one interaction attached before the first menu and never removed (control).", kind: .permanent),
    ]
}

/// The interaction leak probe screen (`-ilVariant <id>`). The probe's custom
/// UITextInput view (the engine's zero-sized layout) is first responder with
/// the keyboard up and goes through 10 cycles of the variant. After every
/// step the app records `view.interactions` (count and class names) and
/// `view.gestureRecognizers` (count and class names). The UI test only
/// launches the variant, waits for the `ilPhase` label to read `phase=done`
/// and copies the result file.
///
/// Records (prefix `il-<id>`): `-steps.txt` (one line per step of every
/// cycle), `-result.txt` (the summary line), `-leftovers.txt` (every
/// interaction and gesture recognizer that is on the view now and was not
/// before the first cycle), `-events.txt`, `-menus.txt`,
/// `-textinput-calls.txt`.
final class InteractionLeakViewController: UIViewController {
    private struct Sample {
        let count: Int
        let classes: [String: Int]
        let gestureCount: Int
        let gestureClasses: [String: Int]
    }

    private let variant: ILVariant
    private var input: LUInputView!
    private let rendered = ACRenderedView()
    private let hider = AccessibilityHiderView(frame: .zero)

    private let phaseLabel = UILabel()
    private let statusLabel = UILabel()

    private var phaseSeq = 0
    private var keyboardShown = false
    private var currentCycle = 0

    // What the variant's cycles report.
    private var beforeInteractions: [UIInteraction] = []
    private var beforeGestures: [UIGestureRecognizer] = []
    private var afterAddCounts: [Int] = []
    private var afterCounts: [Int] = []
    private var afterGestureCounts: [Int] = []
    private var lastAfter: Sample?
    private var lastAfterDetail: (interactions: [String], gestures: [String])?
    private var menuShown: [Bool] = []
    private var menuDismissed: [Bool] = []
    private var notes: [String] = []
    private var willPresentCount = 0
    private var dismissCompletedCount = 0

    init(variant: ILVariant) {
        self.variant = variant
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Layout

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let title = makeLabel("il-\(variant.id)", identifier: "ilTitle", size: 14, weight: .semibold)
        let what = makeLabel(variant.what, identifier: "ilWhat", size: 11)
        what.numberOfLines = 0
        what.textColor = .secondaryLabel
        configure(phaseLabel, identifier: "ilPhase", size: 12)
        configure(statusLabel, identifier: "ilStatus", size: 10)
        phaseLabel.text = "phase=start seq=0"
        statusLabel.text = "status: pending"
        statusLabel.numberOfLines = 2

        let input = LUInputView(text: AutocorrectViewController.sampleText, selectedRange: AutocorrectViewController.endSelection)
        input.delegateHandling = .guarded
        input.menuStyle = .suggested
        input.returnKeyType = .default
        input.inlinePredictionType = .no
        input.onEvent = { Probe.event($0) }
        input.onWillPresent = { [weak self] number in self?.menuWillPresent(number) }
        input.onDismissCompleted = { [weak self] number in self?.menuDismissCompleted(number) }
        self.input = input
        // The engine's layout: a zero-sized input view in a zero-sized hider,
        // another view draws the text.
        rendered.update(text: input.text, selection: input.currentSelection)
        input.onChange = { [weak input, weak self] in
            guard let input else { return }
            self?.rendered.update(text: input.text, selection: input.currentSelection)
        }
        hider.addSubview(input)
        rendered.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [title, what, phaseLabel, statusLabel])
        stack.axis = .vertical
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        view.addSubview(rendered)
        view.addSubview(hider)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            rendered.topAnchor.constraint(equalTo: guide.topAnchor, constant: 170),
            rendered.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            rendered.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            rendered.heightAnchor.constraint(equalToConstant: TextLayout.height + 8),
        ])

        for name in [UIResponder.keyboardDidShowNotification, UIResponder.keyboardDidHideNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let shown = note.name == UIResponder.keyboardDidShowNotification
                MainActor.assumeIsolated { self?.keyboardShown = shown }
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // As the engine: the hider at the field's origin with a zero size,
        // the input view CGRectZero.
        hider.frame = CGRect(origin: rendered.frame.origin, size: .zero)
        input.frame = .zero
        input.layoutSize = rendered.bounds.size
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Probe.event("viewDidAppear variant=\(variant.id)")
        let became = input.becomeFirstResponder()
        Probe.event("becomeFirstResponder=\(became)")
        Task { @MainActor [weak self] in
            await self?.run()
        }
    }

    // MARK: - Script

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func waitUntil(timeout: Double, _ condition: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            await pause(0.05)
        }
        return condition()
    }

    private func setPhase(_ name: String) {
        phaseSeq += 1
        phaseLabel.text = "phase=\(name) seq=\(phaseSeq)"
        Probe.event("phase \(name) seq=\(phaseSeq)")
    }

    private func run() async {
        // The engine's setup: the keyboard comes up, "harbor" is selected.
        await pause(1.5)
        input.engineSetState(selection: AutocorrectViewController.harborRange)
        await pause(1.4)
        setPhase("running")

        let before = capture("before")
        beforeInteractions = input.interactions
        beforeGestures = input.gestureRecognizers ?? []
        if variant.reusesObject {
            input.menuInteraction = input.makeMenuInteraction(mode: .editable)
        }
        if variant.kind == .permanent {
            input.menuInteraction = input.makeMenuInteraction(mode: .editable)
            input.attachMenuInteraction("permanent, before the first menu")
            capture("attachedPermanent")
            await pause(0.5)
        }

        var completed = 0
        for cycle in 1...ILVariant.cycles {
            currentCycle = cycle
            statusLabel.text = "cycle=\(cycle)/\(ILVariant.cycles)"
            if variant.presentsMenu {
                await menuCycle(cycle)
            } else {
                await plainCycle(cycle)
            }
            completed += 1
        }
        currentCycle = ILVariant.cycles

        await pause(2.0)
        let settled = capture("settled")
        let settledDetail = leftoverDetails()
        writeResult(before: before, settled: settled, settledDetail: settledDetail, completed: completed)
        statusLabel.text = "done"
        setPhase("done")
    }

    /// A cycle without a menu: add, (wait / set textInput to nil), remove.
    private func plainCycle(_ cycle: Int) async {
        attachInteraction(cycle)
        afterAddCounts.append(capture("added").count)
        switch variant.kind {
        case .addWaitRemove:
            await pause(1.0)
            capture("waited")
        case .nilThenRemove:
            input.menuInteraction?.textInput = nil
            capture("textInputNil")
        case .addRemove, .reuseObject, .menuCycle, .menuCycleReuse, .menuOnly, .permanent:
            break
        }
        input.detachMenuInteraction("probe cycle \(cycle)")
        recordAfter(capture("removed"))
        await pause(0.3)
        capture("idle")
    }

    /// A cycle with the edit menu. The interaction of the menu-cycle variants
    /// is removed in the completion of the dismissal animator
    /// (`menuDismissCompleted`), not here.
    private func menuCycle(_ cycle: Int) async {
        let presentedBefore = willPresentCount
        let dismissedBefore = dismissCompletedCount
        let removesInteraction = variant.kind == .menuCycle || variant.kind == .menuCycleReuse
        if removesInteraction {
            attachInteraction(cycle)
            afterAddCounts.append(capture("added").count)
        }
        input.presentEditMenu()
        capture("presentRequested")
        let appeared = await waitUntil(timeout: 3.0) { willPresentCount > presentedBefore }
        menuShown.append(appeared)
        if !appeared {
            notes.append("cycle \(cycle): the menu did not appear (no willPresentMenu within 3 s)")
        }
        await pause(1.2)
        capture("presented")
        input.dismissEditMenu()
        capture("dismissRequested")
        let completed = await waitUntil(timeout: 4.0) { dismissCompletedCount > dismissedBefore }
        menuDismissed.append(completed)
        if !completed {
            notes.append("cycle \(cycle): the dismissal animator never completed (4 s)")
            if removesInteraction {
                input.detachMenuInteraction("dismissal completion timed out")
                recordAfter(capture("removedAfterTimeout"))
            } else {
                recordAfter(capture("dismissTimedOut"))
            }
        }
        await pause(0.8)
        capture("idle")
    }

    private func menuWillPresent(_ number: Int) {
        willPresentCount += 1
        Probe.event("menu #\(number) will present")
    }

    private func menuDismissCompleted(_ number: Int) {
        Probe.event("menu #\(number) dismiss animation completed")
        dismissCompletedCount += 1
        switch variant.kind {
        case .menuCycle, .menuCycleReuse:
            capture("dismissCompleted")
            input.detachMenuInteraction("dismiss animation completed")
            recordAfter(capture("removed"))
        case .menuOnly, .permanent:
            recordAfter(capture("dismissCompleted"))
        case .addRemove, .addWaitRemove, .nilThenRemove, .reuseObject:
            break
        }
    }

    /// A new interaction object, or the one of the reusing variants.
    private func attachInteraction(_ cycle: Int) {
        if !variant.reusesObject || input.menuInteraction == nil {
            input.menuInteraction = input.makeMenuInteraction(mode: .editable)
        }
        input.attachMenuInteraction("probe cycle \(cycle)")
    }

    /// The state after the cycle's removal (or, without one, after the
    /// dismissal).
    private func recordAfter(_ sample: Sample) {
        afterCounts.append(sample.count)
        afterGestureCounts.append(sample.gestureCount)
        lastAfter = sample
        lastAfterDetail = leftoverDetails()
    }

    // MARK: - Recording

    @discardableResult
    private func capture(_ step: String) -> Sample {
        let interactions = input.interactions.map { String(describing: type(of: $0)) }
        let gestures = (input.gestureRecognizers ?? []).map { String(describing: type(of: $0)) }
        let sample = Sample(
            count: interactions.count,
            classes: Self.multiset(interactions),
            gestureCount: gestures.count,
            gestureClasses: Self.multiset(gestures)
        )
        let windows = view.window?.windowScene?.windows.count ?? 0
        Probe.write(
            "steps",
            "[\(Probe.stamp())] c\(currentCycle) \(step) count=\(sample.count) interactions=[\(Self.format(sample.classes))]"
                + " gestures=\(sample.gestureCount) gestureClasses=[\(Self.format(sample.gestureClasses))]"
                + " inputDelegate=\(input.inputDelegateText) firstResponder=\(input.isFirstResponder) windows=\(windows)\n",
            append: true
        )
        return sample
    }

    /// Every interaction and gesture recognizer on the view that was not
    /// there before the first cycle, one line each.
    private func leftoverDetails() -> (interactions: [String], gestures: [String]) {
        let interactions = input.interactions
            .filter { current in !beforeInteractions.contains { $0 === current } }
            .map { interaction -> String in
                let name = String(describing: type(of: interaction))
                let ours = input.menuInteraction.map { $0 === interaction } ?? false
                return "\(name) view===view:\(interaction.view === input) ours:\(ours) \(Self.clean(String(describing: interaction), limit: 120))"
            }
        let gestures = (input.gestureRecognizers ?? [])
            .filter { current in !beforeGestures.contains { $0 === current } }
            .map { recognizer -> String in
                let name = String(describing: type(of: recognizer))
                let delegate = recognizer.delegate.map { String(describing: type(of: $0)) } ?? "nil"
                return "\(name) view===view:\(recognizer.view === input) enabled:\(recognizer.isEnabled) delegate:\(delegate) \(Self.clean(String(describing: recognizer), limit: 100))"
            }
        return (interactions, gestures)
    }

    private func writeResult(
        before: Sample,
        settled: Sample,
        settledDetail: (interactions: [String], gestures: [String]),
        completed: Int
    ) {
        let last = lastAfter ?? settled
        let lastDetail = lastAfterDetail ?? settledDetail

        var file = "== after the last cycle: \(last.count) interactions, \(last.gestureCount) gesture recognizers\n"
        file += "-- interactions not on the view before the first cycle (\(lastDetail.interactions.count))\n"
        file += lastDetail.interactions.map { "  \($0)\n" }.joined()
        file += "-- gesture recognizers not on the view before the first cycle (\(lastDetail.gestures.count))\n"
        file += lastDetail.gestures.map { "  \($0)\n" }.joined()
        file += "== settled 2 s later: \(settled.count) interactions, \(settled.gestureCount) gesture recognizers\n"
        file += "-- interactions (\(settledDetail.interactions.count))\n"
        file += settledDetail.interactions.map { "  \($0)\n" }.joined()
        file += "-- gesture recognizers (\(settledDetail.gestures.count))\n"
        file += settledDetail.gestures.map { "  \($0)\n" }.joined()
        Probe.write("leftovers", file)

        let fields = [
            "cycles=\(completed)/\(ILVariant.cycles)",
            "before=\(before.count)",
            "afterAdd=[\(Self.list(afterAddCounts))]",
            "after=[\(Self.list(afterCounts))]",
            "settled=\(settled.count)",
            "classesBefore=[\(Self.format(before.classes))]",
            "classesAfter=[\(Self.format(last.classes))]",
            "leftover=[\(Self.difference(last.classes, before.classes))]",
            "settledLeftover=[\(Self.difference(settled.classes, before.classes))]",
            "gesturesBefore=\(before.gestureCount)",
            "gesturesAfter=[\(Self.list(afterGestureCounts))]",
            "gesturesSettled=\(settled.gestureCount)",
            "gestureClassesBefore=[\(Self.format(before.gestureClasses))]",
            "gestureClassesAfter=[\(Self.format(last.gestureClasses))]",
            "gestureLeftover=[\(Self.difference(last.gestureClasses, before.gestureClasses))]",
            "leftoverInteractions=[\(Self.first(lastDetail.interactions, 4))]",
            "leftoverGestures=[\(Self.first(lastDetail.gestures, 4))]",
            "menuShown=[\(menuShown.map { $0 ? "true" : "false" }.joined(separator: ","))]",
            "menuDismissed=[\(menuDismissed.map { $0 ? "true" : "false" }.joined(separator: ","))]",
            "end=[firstResponder=\(input.isFirstResponder) keyboard=\(keyboardShown)]",
            "notes=[\(notes.joined(separator: "; "))]",
        ]
        Probe.write("result", fields.joined(separator: " | ") + "\n")
    }

    // MARK: - Formatting

    private static func multiset(_ names: [String]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for name in names {
            counts[name, default: 0] += 1
        }
        return counts
    }

    /// "UITextInteraction×1, _UIFoo×2", sorted by name; "none" when empty.
    private static func format(_ counts: [String: Int]) -> String {
        guard !counts.isEmpty else { return "none" }
        return counts.keys.sorted().map { "\($0)×\(counts[$0] ?? 0)" }.joined(separator: ", ")
    }

    /// The classes whose number differs: "_UIFoo×+2, _UIBar×-1"; "none" when equal.
    private static func difference(_ after: [String: Int], _ before: [String: Int]) -> String {
        var parts: [String] = []
        for name in Set(after.keys).union(before.keys).sorted() {
            let delta = (after[name] ?? 0) - (before[name] ?? 0)
            if delta != 0 {
                parts.append("\(name)×\(delta > 0 ? "+" : "")\(delta)")
            }
        }
        return parts.isEmpty ? "none" : parts.joined(separator: ", ")
    }

    private static func list(_ numbers: [Int]) -> String {
        numbers.map { String($0) }.joined(separator: ",")
    }

    /// The first `limit` entries, separated by " ; ", and how many more there are.
    private static func first(_ lines: [String], _ limit: Int) -> String {
        guard !lines.isEmpty else { return "none" }
        let text = lines.prefix(limit).joined(separator: " ; ")
        return lines.count > limit ? text + " ; (+\(lines.count - limit) more)" : text
    }

    private static func clean(_ text: String, limit: Int) -> String {
        let flat = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "|", with: "/")
        return flat.count > limit ? String(flat.prefix(limit)) + "..." : flat
    }

    private func makeLabel(_ text: String, identifier: String, size: CGFloat, weight: UIFont.Weight = .regular) -> UILabel {
        let label = UILabel()
        label.text = text
        configure(label, identifier: identifier, size: size, weight: weight)
        return label
    }

    private func configure(_ label: UILabel, identifier: String, size: CGFloat, weight: UIFont.Weight = .regular) {
        label.font = .monospacedSystemFont(ofSize: size, weight: weight)
        label.accessibilityIdentifier = identifier
        label.translatesAutoresizingMaskIntoConstraints = false
    }
}
