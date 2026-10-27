import Foundation
import WatchConnectivity

/// Sends the pairing payload (configuration + credentials) to the watch.
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

    func sendToWatch(_ payload: GatePairingPayload) {
        guard WCSession.isSupported() else {
            lastSyncError = "Watch connectivity not supported."
            return
        }
        do {
            let data = try JSONEncoder().encode(payload)
            // updateApplicationContext = latest-state, survives relaunch.
            try WCSession.default.updateApplicationContext(["payload": data])
            // transferUserInfo = queued one-shot, delivered even if app closed.
            WCSession.default.transferUserInfo(["payload": data])
            lastSyncError = nil
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

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
