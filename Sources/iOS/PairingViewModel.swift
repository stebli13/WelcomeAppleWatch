import Foundation
import SwiftUI

/// Drives the iPhone setup screens: collect the captured configuration (cloud
/// endpoint, relays, outdoor stations) and a current access/refresh token, test
/// each relay, persist, and push everything to the watch.
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

    @Published private(set) var testResults: [Relay.ID: String] = [:]
    @Published private(set) var testingRelayID: Relay.ID?

    init() {
        let stored = GateStore.loadConfiguration()
        config = stored.isComplete ? stored : .placeholder
        if let creds = GateStore.loadCredentials() {
            accessToken = creds.accessToken
            refreshToken = creds.refreshToken
        }
    }

    // MARK: - Editing

    func addRelay() {
        config.relays.append(Relay(name: "Nuovo relè", deviceID: "",
                                   channelID: "", datapointID: ""))
    }

    func deleteRelays(at offsets: IndexSet) {
        let removed = Set(offsets.map { config.relays[$0].id })
        config.relays.remove(atOffsets: offsets)
        for index in config.stations.indices {
            config.stations[index].relayIDs.removeAll { removed.contains($0) }
        }
    }

    func addStation() {
        config.stations.append(OutdoorStation(name: "Posto esterno",
                                              snapshotPath: nil, relayIDs: []))
    }

    func deleteStations(at offsets: IndexSet) {
        config.stations.remove(atOffsets: offsets)
    }

    // MARK: - Saving / syncing

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

    func sendToWatch() {
        guard let payload = buildPayload() else { return }
        try? GateStore.save(payload)
        PhoneSessionManager.shared.sendToWatch(payload)
    }

    // MARK: - Testing

    func test(_ relay: Relay) async {
        guard let payload = buildPayload() else {
            testResults[relay.id] = "Compila tutti i campi e il token prima."
            return
        }
        testingRelayID = relay.id
        testResults[relay.id] = nil
        let client = ABBWelcomeCloudClient(
            configuration: payload.configuration,
            credentials: payload.credentials)
        do {
            try await client.activate(relay)
            testResults[relay.id] = "✅ Comando inviato. Ora tocca “Invia al Watch”."
        } catch {
            let message = (error as? GateError)?.errorDescription
                ?? error.localizedDescription
            testResults[relay.id] = "❌ \(message)"
        }
        testingRelayID = nil
    }
}
