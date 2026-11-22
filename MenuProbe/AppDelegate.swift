import UIKit

/// Starts the app with `ProbeApplication` as the UIApplication class.
@main
@MainActor
enum ProbeMain {
    static func main() {
        _ = UIApplicationMain(
            CommandLine.argc,
            CommandLine.unsafeArgv,
            NSStringFromClass(ProbeApplication.self),
            NSStringFromClass(AppDelegate.self)
        )
    }
}

/// Records, without changing anything: every action UIKit sends through the
/// application (menu rows that use a selector arrive here with the tapped
/// command as sender), every touch, and what the application, the last
/// responder in the chain, is asked by canPerformAction / targetForAction.
final class ProbeApplication: UIApplication {
    private let actionLog = ActionLog(name: "app-canPerformAction")
    private let targetLog = ActionLog(name: "app-targetForAction")

    override func sendAction(_ action: Selector, to target: Any?, from sender: Any?, for event: UIEvent?) -> Bool {
        let result = super.sendAction(action, to: target, from: sender, for: event)
        let targetName = target.map { String(describing: type(of: $0)) } ?? "nil (responder chain)"
        Probe.write(
            "sendAction",
            "[\(Probe.stamp())] sendAction \(NSStringFromSelector(action)) to=\(targetName) from=\(ActionLog.senderText(sender)) -> \(result)\n",
            append: true
        )
        return result
    }

    override func sendEvent(_ event: UIEvent) {
        if event.type == .touches, let touches = event.allTouches {
            for touch in touches where touch.phase == .began || touch.phase == .ended {
                let point = touch.location(in: nil)
                let phase = touch.phase == .began ? "began" : "ended"
                let viewName = touch.view.map { String(describing: type(of: $0)) } ?? "nil"
                let windowName = touch.window.map { String(describing: type(of: $0)) } ?? "nil"
                Probe.event(String(format: "touch %@ at %.0f,%.0f tapCount=%d view=%@ window=%@", phase, point.x, point.y, touch.tapCount, viewName, windowName))
            }
        }
        super.sendEvent(event)
        if event.type == .touches, let touches = event.allTouches, touches.contains(where: { $0.phase == .ended }) {
            Probe.touchEnded?()
        }
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        let answer = super.canPerformAction(action, withSender: sender)
        actionLog.record(action, answer: answer, defaultAnswer: answer, sender: sender)
        return answer
    }

    override func target(forAction action: Selector, withSender sender: Any?) -> Any? {
        let target = super.target(forAction: action, withSender: sender)
        targetLog.record(action, detail: "target=\(target.map { String(describing: type(of: $0)) } ?? "nil") sender=\(ActionLog.senderText(sender))")
        return target
    }
}

final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Paste only appears when the pasteboard holds a string. Writing does
        // not show the paste permission prompt; reading would.
        UIPasteboard.general.string = "probe"
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        // `-luVariant <id>`: the Look Up harness.
        if let id = UserDefaults.standard.string(forKey: "luVariant"), let luVariant = LUVariant.named(id) {
            Probe.tag = "lu-\(luVariant.id)"
            Probe.event("launch \(Probe.tag) iOS \(UIDevice.current.systemVersion)")
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = LookUpViewController(variant: luVariant)
            window.makeKeyAndVisible()
            self.window = window
            return
        }
        // `-ilVariant <id>`: the interaction leak probe.
        if let id = UserDefaults.standard.string(forKey: "ilVariant"), let ilVariant = ILVariant.named(id) {
            Probe.tag = "il-\(ilVariant.id)"
            Probe.event("launch \(Probe.tag) iOS \(UIDevice.current.systemVersion)")
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = InteractionLeakViewController(variant: ilVariant)
            window.makeKeyAndVisible()
            self.window = window
            return
        }
        // `-acVariant <id>`: the autocorrect harness instead of a menu variant.
        if let id = UserDefaults.standard.string(forKey: "acVariant"), let acVariant = ACVariant.named(id) {
            Probe.tag = "ac-\(acVariant.id)"
            Probe.event("launch \(Probe.tag) iOS \(UIDevice.current.systemVersion)")
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = AutocorrectViewController(variant: acVariant)
            window.makeKeyAndVisible()
            self.window = window
            return
        }
        let variant = Variant.fromLaunchArguments()
        Probe.runName = UserDefaults.standard.string(forKey: "probeRun") ?? ""
        Probe.tag = Probe.runName.isEmpty ? variant.tag : "\(variant.tag)-\(Probe.runName)"
        Probe.event("launch \(Probe.tag) iOS \(UIDevice.current.systemVersion)")
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = ProbeViewController(variant: variant)
        window.makeKeyAndVisible()
        self.window = window
    }

    // A menu row that opens another app (Search Web) or a sheet shows up here.
    func sceneWillResignActive(_ scene: UIScene) { Probe.event("scene willResignActive") }
    func sceneDidEnterBackground(_ scene: UIScene) { Probe.event("scene didEnterBackground") }
    func sceneWillEnterForeground(_ scene: UIScene) { Probe.event("scene willEnterForeground") }
    func sceneDidBecomeActive(_ scene: UIScene) { Probe.event("scene didBecomeActive") }
}
