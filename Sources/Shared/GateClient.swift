import Foundation

/// Abstraction over the ABB-Welcome actions the apps expose, independent of
/// transport.
///
/// v1 ships `ABBWelcomeCloudClient` (works anywhere via the myBUILDINGS cloud).
/// A future `ABBWelcomeLocalSIPClient` (home Wi-Fi, ~50 ms) can conform to the
/// same protocol so the UI never changes.
protocol GateClient {
    /// Fire a relay (gate, garage door, …). Returns when the service has
    /// accepted the command; throws `GateError` otherwise.
    func activate(_ relay: Relay) async throws

    /// Latest camera picture of an outdoor station, as image data.
    func snapshot(of station: OutdoorStation) async throws -> Data
}
