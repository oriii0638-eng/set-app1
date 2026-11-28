import UIKit
import Capacitor

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        window = UIWindow(windowScene: windowScene)
        window?.rootViewController = SetBridgeViewController()
        window?.makeKeyAndVisible()

        SceneDelegateProxy.shared.scene(scene, willConnectTo: session, options: connectionOptions)

        // קישור הזמנה (/i/CODE) שפתח את האפליקציה מאפס
        if let url = connectionOptions.userActivities.first(where: { $0.activityType == NSUserActivityTypeBrowsingWeb })?.webpageURL {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.openInApp(url) }
        }
    }

    /// קישור של סט (Universal Link) נפתח בתוך האפליקציה ולא בספארי
    func openInApp(_ url: URL) {
        guard url.host == "set-app-e0r6.onrender.com",
              let vc = window?.rootViewController as? CAPBridgeViewController,
              let web = vc.webView else { return }
        web.load(URLRequest(url: url))
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        SceneDelegateProxy.shared.scene(scene, openURLContexts: URLContexts)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        SceneDelegateProxy.shared.scene(scene, continue: userActivity)
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb, let url = userActivity.webpageURL { openInApp(url) }
    }
}
