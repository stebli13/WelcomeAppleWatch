import SwiftUI

@main
struct WelcomeGateApp: App {
    init() { _ = PhoneSessionManager.shared } // activate WCSession at launch

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
