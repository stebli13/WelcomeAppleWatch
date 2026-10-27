import Foundation
import WatchConnectivity

/// Receives the pairing payload (configuration + credentials) pushed from the
/// iPhone and stores it in the watch Keychain. WatchConnectivity transfers are
/// encrypted between the paired devices.
final class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {
    @Published var isPaired: Bool = GateStore.isPaired
    /// Bumped on every received payload so screens reload the configuration.
    @Published var revision = 0

    static let shared = WatchSessionManager()

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func store(_ dict: [String: Any]) {
        guard let data = dict["payload"] as? Data,
              let payload = try? JSONDecoder()
                  .decode(GatePairingPayload.self, from: data) else { return }
        try? GateStore.save(payload)
        DispatchQueue.main.async {
            self.isPaired = GateStore.isPaired
            self.revision += 1
        }
    }

    // Latest-state sync (preferred): survives relaunch, overwrites previous.
    func session(_ session: WCSession,
                 didReceiveApplicationContext ctx: [String: Any]) {
        store(ctx)
    }

    // Queued one-shot delivery (fallback / explicit "send to watch").
    func session(_ session: WCSession,
                 didReceiveUserInfo userInfo: [String: Any]) {
        store(userInfo)
    }

    func session(_ session: WCSession,
                 activationDidCompleteWith state: WCSessionActivationState,
                 error: Error?) {
        // Pick up any context delivered before activation.
        let ctx = session.receivedApplicationContext
        if !ctx.isEmpty { store(ctx) }
    }
}
