import Foundation

/// A switchable actuator on the ABB-Welcome system — what the iPhone app lists
/// under "Controllo accessi → Relè" (e.g. "Cancello-citofono",
/// "Basculante-citofono"). Activating it writes its input datapoint.
struct Relay: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var deviceID: String
    var channelID: String
    var datapointID: String
    /// Value written to the datapoint to fire the relay (usually "1").
    var openValue: String = "1"

    var isComplete: Bool {
        ![name, deviceID, channelID, datapointID, openValue]
            .contains { $0.isEmpty || $0.hasPrefix("??") }
    }
}

/// An outdoor station ("Posto esterno", e.g. "Outdoor Station 1-citofono").
struct OutdoorStation: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    /// Path (relative to `apiBase`) that returns the latest camera snapshot as
    /// an image, taken from the capture. `nil` = no picture, placeholder shown.
    var snapshotPath: String?
    /// Relays offered on this station's screen.
    var relayIDs: [String]
}

/// Non-secret endpoint + addressing values for the ABB Welcome IP cloud API.
///
/// These come from the one-time traffic capture (see
/// `docs/traffic-capture-playbook.md`). They are not secrets — the access token
/// is — but they are per-installation, so they are stored alongside the
/// credentials and synced to the watch rather than hard-coded.
struct GateConfiguration: Codable, Equatable {
    /// OAuth token endpoint, e.g. the host that returns `access_token`.
    var oauthTokenURL: String
    /// OAuth refresh endpoint (often the same as `oauthTokenURL`).
    var refreshURL: String
    /// OAuth client identifier used by the Welcome App.
    var clientID: String
    /// Base URL of the Welcome IP cloud API (host + any version prefix).
    var apiBase: String
    /// Your access point.
    var smartApUUID: String

    var relays: [Relay]
    var stations: [OutdoorStation]

    /// True once the endpoints and at least one relay are filled from a real
    /// capture.
    var isComplete: Bool {
        let endpointsSet = ![oauthTokenURL, refreshURL, clientID, apiBase, smartApUUID]
            .contains { $0.isEmpty || $0.hasPrefix("??") }
        return endpointsSet && !relays.isEmpty && relays.allSatisfy(\.isComplete)
    }

    func relay(id: String) -> Relay? { relays.first { $0.id == id } }

    /// Builds the activation URL for a relay.
    /// NOTE: confirm the exact path template against your capture; ABB firmware
    /// versions differ. Centralised here so there is one place to adjust.
    func activationURL(for relay: Relay) -> URL? {
        URL(string: "\(apiBase)/smartap/\(smartApUUID)/devices/\(relay.deviceID)" +
                    "/channels/\(relay.channelID)/datapoints/\(relay.datapointID)")
    }

    func snapshotURL(for station: OutdoorStation) -> URL? {
        guard let path = station.snapshotPath, !path.isEmpty else { return nil }
        return URL(string: apiBase + path)
    }

    /// Mirrors the installation shown in the iPhone app, with IDs left to fill
    /// from the capture.
    static let placeholder: GateConfiguration = {
        let gate = Relay(name: "Cancello-citofono", deviceID: "??DEVICE_ID",
                         channelID: "??CHANNEL_ID", datapointID: "??DATAPOINT_ID")
        let garage = Relay(name: "Basculante-citofono", deviceID: "??DEVICE_ID",
                           channelID: "??CHANNEL_ID", datapointID: "??DATAPOINT_ID")
        return GateConfiguration(
            oauthTokenURL: "??OAUTH_TOKEN_URL",
            refreshURL: "??REFRESH_URL",
            clientID: "??CLIENT_ID",
            apiBase: "??API_BASE",
            smartApUUID: "??SMARTAP_UUID",
            relays: [gate, garage],
            stations: [OutdoorStation(name: "Outdoor Station 1-citofono",
                                      snapshotPath: nil,
                                      relayIDs: [gate.id, garage.id])])
    }()
}
