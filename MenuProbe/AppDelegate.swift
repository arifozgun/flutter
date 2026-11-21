import UIKit

@main
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
        let variant = Variant.fromLaunchArguments()
        Probe.tag = variant.tag
        Probe.event("launch \(variant.tag) iOS \(UIDevice.current.systemVersion)")
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = ProbeViewController(variant: variant)
        window.makeKeyAndVisible()
        self.window = window
    }
}
