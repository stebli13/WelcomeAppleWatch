import Foundation
import WatchConnectivity

/// Watch side of WatchConnectivity: receives the screen configuration from
/// the iPhone, and carries "open" requests to it (`PhoneRelayClient`).
final class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {
    @Published var isPaired: Bool = GateStore.isConfigured
    /// Bumped on every received configuration so screens reload it.
    @Published var revision = 0

    static let shared = WatchSessionManager()

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func store(_ dict: [String: Any]) {
        guard let data = dict["configuration"] as? Data,
              let configuration = try? JSONDecoder()
                  .decode(GateConfiguration.self, from: data) else { return }
        try? GateStore.saveConfiguration(configuration)
        DispatchQueue.main.async {
            self.isPaired = GateStore.isConfigured
            self.revision += 1
        }
    }

    func session(_ session: WCSession,
                 didReceiveApplicationContext ctx: [String: Any]) {
        store(ctx)
    }

    func session(_ session: WCSession,
                 didReceiveUserInfo userInfo: [String: Any]) {
        store(userInfo)
    }

    func session(_ session: WCSession,
                 activationDidCompleteWith state: WCSessionActivationState,
                 error: Error?) {
        let ctx = session.receivedApplicationContext
        if !ctx.isEmpty { store(ctx) }
    }
}

/// `GateClient` for the watch: asks the iPhone to open, because watchOS does
/// not allow the TLS sockets SIP needs (Apple TN3135). Works wherever the
/// iPhone is connected to the watch and has internet.
struct PhoneRelayClient: GateClient {
    func activate(_ relay: Relay) async throws {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            throw GateError.phoneUnreachable
        }
        let reply: [String: Any] = try await withCheckedThrowingContinuation { cont in
            session.sendMessage(["activate": relay.id], replyHandler: { reply in
                cont.resume(returning: reply)
            }, errorHandler: { _ in
                cont.resume(throwing: GateError.phoneUnreachable)
            })
        }
        if let message = reply["error"] as? String {
            throw GateError.remote(message)
        }
        guard reply["ok"] as? Bool == true else {
            throw GateError.remote("Risposta inattesa dall’iPhone.")
        }
    }
}
