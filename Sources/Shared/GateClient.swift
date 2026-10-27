import Foundation

/// Abstraction over the actions the apps expose, independent of transport.
///
/// v1 ships `HomeAssistantClient`. A direct SIP client for the ABB gateway can
/// conform to the same protocol later without touching the UI.
protocol GateClient {
    /// Fire a relay (gate, garage door, …). Returns when the service has
    /// accepted the command; throws `GateError` otherwise.
    func activate(_ relay: Relay) async throws

    /// Latest camera picture of an outdoor station, as image data.
    func snapshot(of station: OutdoorStation) async throws -> Data
}
