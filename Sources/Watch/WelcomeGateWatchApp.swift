import SwiftUI

@main
struct WelcomeGateWatchApp: App {
    init() { _ = WatchSessionManager.shared } // activate WCSession at launch

    var body: some Scene {
        WindowGroup {
            WatchContentView()
        }
    }
}
