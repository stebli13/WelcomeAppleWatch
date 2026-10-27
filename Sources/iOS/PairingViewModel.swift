import Foundation
import SwiftUI

/// Drives the iPhone pairing screen: collect the captured configuration and a
/// current access/refresh token, test "open" once, persist, and push to watch.
///
/// This is the v1 bootstrap path: you fill it from your traffic capture
/// (docs/traffic-capture-playbook.md). Once the exact ABB OAuth endpoints are
/// confirmed, a proper "Sign in to myBUILDINGS" flow can replace manual token
/// entry — the rest of the app stays the same.
@MainActor
final class PairingViewModel: ObservableObject {
    @Published var config: GateConfiguration
    @Published var accessToken: String = ""
    @Published var refreshToken: String = ""
    /// Access-token lifetime in seconds (from the token response `expires_in`).
    @Published var expiresInSeconds: String = "3600"

    @Published var testState: String?
    @Published var isTesting = false

    init() {
        let stored = GateStore.loadConfiguration()
        self.config = stored.isComplete ? stored : .placeholder
        if let creds = GateStore.loadCredentials() {
            accessToken = creds.accessToken
            refreshToken = creds.refreshToken
        }
    }

    private func buildPayload() -> GatePairingPayload? {
        guard config.isComplete, !accessToken.isEmpty else { return nil }
        let ttl = TimeInterval(expiresInSeconds) ?? 3600
        let creds = GateCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(ttl))
        return GatePairingPayload(configuration: config, credentials: creds)
    }

    var canSave: Bool { buildPayload() != nil }

    func save() {
        guard let payload = buildPayload() else { return }
        try? GateStore.save(payload)
    }

    func sendToWatch() {
        guard let payload = buildPayload() else { return }
        try? GateStore.save(payload)
        PhoneSessionManager.shared.sendToWatch(payload)
    }

    func testOpen() async {
        guard let payload = buildPayload() else {
            testState = "Fill in all fields and a token first."
            return
        }
        isTesting = true
        testState = nil
        let client = ABBWelcomeCloudClient(
            configuration: payload.configuration,
            credentials: payload.credentials)
        do {
            try await client.openDoor()
            testState = "✅ Door opened. You're set — tap “Send to Watch”."
        } catch {
            let message = (error as? GateError)?.errorDescription
                ?? error.localizedDescription
            testState = "❌ \(message)"
        }
        isTesting = false
    }
}
