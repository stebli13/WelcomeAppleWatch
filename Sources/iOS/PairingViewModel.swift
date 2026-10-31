import Foundation
import SwiftUI

/// Drives the iPhone screens: import the file exported on the Mac, edit and
/// test the relays, push the configuration to the watch.
@MainActor
final class PairingViewModel: ObservableObject {
    /// Saved on every edit: the watch's requests are served from the
    /// stored configuration.
    @Published var config: GateConfiguration {
        didSet { if isImported { try? GateStore.saveConfiguration(config) } }
    }
    @Published private(set) var account: ABBAccount?

    @Published var importStatus: String?
    @Published private(set) var testResults: [Relay.ID: String] = [:]
    @Published private(set) var testingRelayID: Relay.ID?

    init() {
        config = GateStore.loadConfiguration()
        account = ABBAccountStore.load()
    }

    var isImported: Bool { account != nil }

    // MARK: - Import

    func importFile(at url: URL, passphrase: String) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let result = try PairingImport.read(data, passphrase: passphrase)
            try ABBAccountStore.save(result.account)
            account = result.account
            config = result.configuration
            importStatus = "✅ Importato: \(config.relays.map(\.name).joined(separator: ", ")). "
                + "Ora puoi cancellare il file da File e dal Mac."
        } catch {
            importStatus = "❌ \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    func forget() {
        ABBAccountStore.clear()
        GateStore.clear()
        account = nil
        config = .empty
        importStatus = nil
        testResults = [:]
    }

    // MARK: - Editing

    func addRelay() {
        let station = config.stations.first?.stationID ?? ""
        let relay = Relay(name: "Nuovo relè", stationID: station, body: "b:", inCall: false)
        config.relays.append(relay)
        if !config.stations.isEmpty { config.stations[0].relayIDs.append(relay.id) }
    }

    func deleteRelays(at offsets: IndexSet) {
        let removed = Set(offsets.map { config.relays[$0].id })
        config.relays.remove(atOffsets: offsets)
        for index in config.stations.indices {
            config.stations[index].relayIDs.removeAll { removed.contains($0) }
        }
    }

    // MARK: - Saving / syncing

    var canSave: Bool { isImported && config.isComplete }

    func sendToWatch() {
        guard canSave else { return }
        try? GateStore.saveConfiguration(config)
        PhoneSessionManager.shared.sendToWatch(config)
    }

    // MARK: - Testing

    func test(_ relay: Relay) async {
        guard let account, relay.isComplete else {
            testResults[relay.id] = "Importa prima il file dal Mac."
            return
        }
        testingRelayID = relay.id
        testResults[relay.id] = nil
        let started = Date()
        do {
            try await ABBCloudClient(account: account).activate(relay)
            let seconds = Date().timeIntervalSince(started)
            testResults[relay.id] = String(format: "✅ Comando accettato (%.1f s).", seconds)
        } catch {
            testResults[relay.id] = "❌ \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
        testingRelayID = nil
    }
}
