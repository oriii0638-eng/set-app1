import SwiftUI

@main
struct SetWatchApp: App {
    @StateObject private var app = AppState()
    var body: some Scene {
        WindowGroup { RootView().environmentObject(app) }
    }
}
