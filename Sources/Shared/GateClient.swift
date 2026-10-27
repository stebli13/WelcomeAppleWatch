import Foundation

/// Abstraction over "open the door/gate", independent of transport.
///
/// v1 ships `ABBWelcomeCloudClient` (works anywhere via the myBUILDINGS cloud).
/// A future `ABBWelcomeLocalSIPClient` (home Wi-Fi, ~50 ms) can conform to the
/// same protocol so the UI never changes.
protocol GateClient {
    /// Trigger the door-opener. Returns when the service has accepted the
    /// command; throws `GateError` otherwise.
    func openDoor() async throws
}
