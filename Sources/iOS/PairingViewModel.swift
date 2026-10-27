import Foundation
import SwiftUI

/// Drives the iPhone setup screens: Home Assistant address and token, which
/// entity each relay fires and which picture each station uses; test each
/// relay, persist, and push everything to the watch.
@MainActor
final class PairingViewModel: ObservableObject {
    @Published var config: GateConfiguration
    @Published var token: String = ""

    @Published private(set) var entities: [HAEntity] = []
    @Published private(set) var entitiesStatus: String?
    @Published private(set) var isLoadingEntities = false

    @Published private(set) var testResults: [Relay.ID: String] = [:]
    @Published private(set) var testingRelayID: Relay.ID?

    init() {
        config = GateStore.loadConfiguration()
        token = GateStore.loadCredentials()?.token ?? ""
    }

    // MARK: - Editing

    func addRelay() {
        config.relays.append(Relay(name: "Nuovo relè", entityID: ""))
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
                                              pictureEntityID: nil, relayIDs: []))
    }

    func deleteStations(at offsets: IndexSet) {
        config.stations.remove(atOffsets: offsets)
    }

    // MARK: - Connection

    var hasConnection: Bool { config.hasValidBaseURL && !token.isEmpty }

    private var client: HomeAssistantClient {
        HomeAssistantClient(configuration: config, token: token)
    }

    func loadEntities() async {
        guard hasConnection else {
            entitiesStatus = "Inserisci indirizzo e token di Home Assistant."
            return
        }
        isLoadingEntities = true
        entitiesStatus = nil
        do {
            entities = try await client.entities()
            entitiesStatus = "✅ Connesso: \(entities.count) entità trovate."
        } catch {
            entitiesStatus = "❌ \((error as? GateError)?.errorDescription ?? error.localizedDescription)"
        }
        isLoadingEntities = false
    }

    // MARK: - Saving / syncing

    private func buildPayload() -> GatePairingPayload? {
        guard config.isComplete, !token.isEmpty else { return nil }
        return GatePairingPayload(configuration: config,
                                  credentials: GateCredentials(token: token))
    }

    var canSave: Bool { buildPayload() != nil }

    func sendToWatch() {
        guard let payload = buildPayload() else { return }
        try? GateStore.save(payload)
        PhoneSessionManager.shared.sendToWatch(payload)
    }

    // MARK: - Testing

    func test(_ relay: Relay) async {
        guard hasConnection, relay.isComplete else {
            testResults[relay.id] = "Scegli prima l’entità e inserisci indirizzo e token."
            return
        }
        testingRelayID = relay.id
        testResults[relay.id] = nil
        do {
            try await client.activate(relay)
            testResults[relay.id] = "✅ Comando inviato."
        } catch {
            testResults[relay.id] = "❌ \((error as? GateError)?.errorDescription ?? error.localizedDescription)"
        }
        testingRelayID = nil
    }
}
