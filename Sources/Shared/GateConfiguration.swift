import Foundation

/// Something the watch can open: a relay under "Controllo accessi → Relè"
/// (Cancello, Basculante) or the outdoor station's own door lock (Portoncino).
///
/// Each one is a SIP `MESSAGE` to an outdoor station with a short text body,
/// verified on the real installation (see docs/abb-welcome-protocol.md):
/// - relay at actuator address N: body `b:N`, no call needed;
/// - door lock: body `1`, sent inside a call to the station.
struct Relay: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    /// Outdoor station the MESSAGE goes to, e.g. `100000001`.
    var stationID: String
    /// MESSAGE body: `b:10`, `b:20`, `1`…
    var body: String
    /// Open a call to the station first (needed for the door lock).
    var inCall: Bool

    var isComplete: Bool { !name.isEmpty && !stationID.isEmpty && !body.isEmpty }

    /// A relay of the access list (actuator address from `[relay_*] address`).
    static func actuator(name: String, address: String, stationID: String) -> Relay {
        Relay(name: name, stationID: stationID, body: "b:\(address)", inCall: false)
    }

    /// The station's own door lock.
    static func door(name: String, stationID: String) -> Relay {
        Relay(name: name, stationID: stationID, body: "1", inCall: true)
    }
}

/// An outdoor station ("Posto esterno", e.g. "Outdoor Station 1").
struct OutdoorStation: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var stationID: String
    /// Relays offered on this station's screen.
    var relayIDs: [String]
}

/// What the screens show. Not secret, so it is also sent to the watch; the
/// SIP account and certificate stay on the iPhone (`ABBAccount`).
struct GateConfiguration: Codable, Equatable {
    var relays: [Relay]
    var stations: [OutdoorStation]

    var isComplete: Bool { !relays.isEmpty && relays.allSatisfy(\.isComplete) }

    func relay(id: String) -> Relay? { relays.first { $0.id == id } }

    /// Before the import: the installation's names, nothing to open yet.
    static let empty = GateConfiguration(relays: [], stations: [])

    /// Built from what the gateway's access list contains.
    static func from(stations: [(name: String, stationID: String)],
                     relays: [(name: String, address: String)]) -> GateConfiguration {
        guard let first = stations.first else { return .empty }
        var items = relays.map {
            Relay.actuator(name: $0.name, address: $0.address, stationID: first.stationID)
        }
        items.append(.door(name: "Portoncino", stationID: first.stationID))
        let allIDs = items.map(\.id)
        let outdoor = stations.map {
            OutdoorStation(name: $0.name, stationID: $0.stationID,
                           relayIDs: $0.stationID == first.stationID ? allIDs : [])
        }
        return GateConfiguration(relays: items, stations: outdoor)
    }

    #if DEBUG
    /// Sample installation for the Xcode canvas previews.
    static let placeholder = GateConfiguration.from(
        stations: [("Outdoor Station 1", "100000001")],
        relays: [("Cancello", "10"), ("Basculante", "20")])
    #endif
}
