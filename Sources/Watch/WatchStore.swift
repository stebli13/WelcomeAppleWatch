import Foundation
import WatchKit

/// State shared by all watch screens: the synced configuration, per-relay
/// activation status, favourites and station pictures.
@MainActor
final class WatchStore: ObservableObject {
    enum ActivationState: Equatable {
        case idle
        case working
        case success
        case failure(String)
    }

    @Published private(set) var configuration: GateConfiguration
    @Published private(set) var states: [Relay.ID: ActivationState] = [:]
    @Published private(set) var snapshots: [OutdoorStation.ID: Data] = [:]
    @Published private(set) var favoriteIDs: Set<Relay.ID>

    private static let favoritesKey = "watch.favoriteRelayIDs"

    init(configuration: GateConfiguration = GateStore.loadConfiguration()) {
        self.configuration = configuration
        let saved = UserDefaults.standard.stringArray(forKey: Self.favoritesKey) ?? []
        favoriteIDs = Set(saved)
    }

    func reload() {
        configuration = GateStore.loadConfiguration()
        // Drop favourites for relays that no longer exist.
        favoriteIDs.formIntersection(configuration.relays.map(\.id))
        saveFavorites()
    }

    // MARK: - Relays

    var relays: [Relay] { configuration.relays }
    var stations: [OutdoorStation] { configuration.stations }
    var favoriteRelays: [Relay] { relays.filter { favoriteIDs.contains($0.id) } }

    func relays(for station: OutdoorStation) -> [Relay] {
        station.relayIDs.compactMap(configuration.relay(id:))
    }

    func state(of relay: Relay) -> ActivationState { states[relay.id] ?? .idle }

    func activate(_ relay: Relay) async {
        guard state(of: relay) != .working else { return }
        let client: GateClient = PhoneRelayClient()
        states[relay.id] = .working
        WKInterfaceDevice.current().play(.click)
        do {
            try await client.activate(relay)
            finish(relay, with: .success)
        } catch {
            let message = (error as? GateError)?.errorDescription
                ?? error.localizedDescription
            finish(relay, with: .failure(message))
        }
    }

    private func finish(_ relay: Relay, with state: ActivationState) {
        states[relay.id] = state
        WKInterfaceDevice.current().play(state == .success ? .success : .failure)
        // Return the row to its resting look after a moment, like a momentary
        // relay.
        Task {
            try? await Task.sleep(nanoseconds: state == .success ? 2_500_000_000 : 5_000_000_000)
            if states[relay.id] == state { states[relay.id] = .idle }
        }
    }

    // MARK: - Favourites ("Preferiti")

    func isFavorite(_ relay: Relay) -> Bool { favoriteIDs.contains(relay.id) }

    func toggleFavorite(_ relay: Relay) {
        if favoriteIDs.contains(relay.id) {
            favoriteIDs.remove(relay.id)
        } else {
            favoriteIDs.insert(relay.id)
        }
        saveFavorites()
    }

    private func saveFavorites() {
        UserDefaults.standard.set(Array(favoriteIDs), forKey: Self.favoritesKey)
    }

    // MARK: - Station pictures

    /// No camera picture yet over the direct ABB connection: the station
    /// screens show their placeholder panel.
    func refreshSnapshots() async {}
    func refreshSnapshot(of station: OutdoorStation) async {}
}

#if DEBUG
/// Sample data for the Xcode canvas previews (Sources/Watch/Previews.swift).
extension WatchStore {
    static func preview(
        states: [String: ActivationState] = [:],
        favoriteNames: [String] = []) -> WatchStore {
        let store = WatchStore(configuration: .placeholder)
        for relay in store.relays {
            if let state = states[relay.name] { store.states[relay.id] = state }
            if favoriteNames.contains(relay.name) { store.favoriteIDs.insert(relay.id) }
        }
        return store
    }
}
#endif
