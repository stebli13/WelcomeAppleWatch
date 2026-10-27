import Foundation

/// Non-secret endpoint + addressing values that describe *which* door-opener to
/// trigger and *where* the ABB Welcome IP cloud API lives.
///
/// These come from the one-time traffic capture (see
/// `docs/traffic-capture-playbook.md`). They are not secrets — the access token
/// is — but they are per-installation, so they are stored alongside the
/// credentials and synced to the watch rather than hard-coded.
///
/// The `.placeholder` value documents the shape and lets the UI build before a
/// real capture exists; `isComplete` is false until the real values are set.
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
    var deviceID: String
    /// The "door opener" channel.
    var channelID: String
    /// The input datapoint that triggers the opener.
    var datapointID: String
    /// Value written to the datapoint to fire the opener (usually "1").
    var openValue: String

    /// True once every field has been filled from a real capture.
    var isComplete: Bool {
        ![oauthTokenURL, refreshURL, clientID, apiBase,
          smartApUUID, deviceID, channelID, datapointID]
            .contains { $0.isEmpty || $0.hasPrefix("??") }
    }

    /// Builds the door-open request URL from the addressing fields.
    /// NOTE: confirm the exact path template against your capture; ABB firmware
    /// versions differ. Centralised here so there is one place to adjust.
    func doorOpenURL() -> URL? {
        let path = "\(apiBase)/smartap/\(smartApUUID)/devices/\(deviceID)" +
                   "/channels/\(channelID)/datapoints/\(datapointID)"
        return URL(string: path)
    }

    static let placeholder = GateConfiguration(
        oauthTokenURL: "??OAUTH_TOKEN_URL",
        refreshURL: "??REFRESH_URL",
        clientID: "??CLIENT_ID",
        apiBase: "??API_BASE",
        smartApUUID: "??SMARTAP_UUID",
        deviceID: "??DEVICE_ID",
        channelID: "??CHANNEL_ID",
        datapointID: "??DATAPOINT_ID",
        openValue: "1"
    )
}
