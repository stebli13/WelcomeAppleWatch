import Foundation
import UIKit
import WatchConnectivity

/// iPhone side of WatchConnectivity:
/// - sends the screen configuration (no secrets) to the watch;
/// - answers the watch's "open this relay" requests by doing the SIP call
///   itself. watchOS wakes this app in the background for them.
final class PhoneSessionManager: NSObject, ObservableObject, WCSessionDelegate {
    @Published var isWatchReachable = false
    @Published var lastSyncError: String?

    static let shared = PhoneSessionManager()

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendToWatch(_ configuration: GateConfiguration) {
        guard WCSession.isSupported() else {
            lastSyncError = "Apple Watch non supportato su questo iPhone."
            return
        }
        do {
            let data = try JSONEncoder().encode(configuration)
            // updateApplicationContext = latest state, survives relaunch.
            try WCSession.default.updateApplicationContext(["configuration": data])
            // transferUserInfo = queued, delivered even if the watch app is closed.
            WCSession.default.transferUserInfo(["configuration": data])
            lastSyncError = nil
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    // MARK: - Requests from the watch

    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        guard let relayID = message["activate"] as? String else {
            replyHandler(["error": "Richiesta non valida."])
            return
        }
        // Keep running long enough to finish the SIP exchange if the app was
        // woken in the background.
        Task { @MainActor in
            let background = BackgroundTask()
            defer { background.end() }
            let configuration = GateStore.loadConfiguration()
            guard let relay = configuration.relay(id: relayID),
                  let client = ABBAccountStore.makeClient() else {
                replyHandler(["error": GateError.notConfigured.errorDescription ?? ""])
                return
            }
            do {
                try await client.activate(relay)
                replyHandler(["ok": true])
            } catch {
                let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                replyHandler(["error": text])
            }
        }
    }

    // MARK: - Session state

    func session(_ session: WCSession,
                 activationDidCompleteWith state: WCSessionActivationState,
                 error: Error?) {
        DispatchQueue.main.async { self.isWatchReachable = session.isReachable }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.isWatchReachable = session.isReachable }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}

/// Asks iOS for extra background time while a watch request is served.
@MainActor
private final class BackgroundTask {
    private var id = UIBackgroundTaskIdentifier.invalid

    init() {
        id = UIApplication.shared.beginBackgroundTask(withName: "open") { [weak self] in
            // Called on the main thread when time runs out.
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
