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

    @Published private(set) var configuration = GateStore.loadConfiguration()
    @Published private(set) var states: [Relay.ID: ActivationState] = [:]
    @Published private(set) var snapshots: [OutdoorStation.ID: Data] = [:]
    @Published private(set) var favoriteIDs: Set<Relay.ID>

    private static let favoritesKey = "watch.favoriteRelayIDs"

    init() {
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
        guard let client = GateStore.makeClient() else {
            finish(relay, with: .failure(GateError.notConfigured.errorDescription ?? ""))
            return
        }
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

    func refreshSnapshots() async {
        for station in stations { await refreshSnapshot(of: station) }
    }

    func refreshSnapshot(of station: OutdoorStation) async {
        guard station.pictureEntityID != nil,
              let client = GateStore.makeClient() else { return }
        if let data = try? await client.snapshot(of: station) {
            snapshots[station.id] = data
        }
    }
}
