import SwiftUI

@main
struct SetWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) var delegate
    @StateObject private var app = AppState.shared
    var body: some Scene {
        WindowGroup { RootView().environmentObject(app) }
    }
}
