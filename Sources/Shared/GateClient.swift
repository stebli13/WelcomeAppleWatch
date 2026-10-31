import Foundation

/// Abstraction over "open this", independent of transport.
///
/// - iPhone: `ABBCloudClient` talks SIP to the ABB cloud server itself.
/// - Watch: `PhoneRelayClient` asks the iPhone to do it (watchOS does not
///   allow the TLS sockets SIP needs, Apple TN3135).
protocol GateClient {
    /// Fire a relay or door. Returns when the server has accepted the command;
    /// throws `GateError` otherwise.
    func activate(_ relay: Relay) async throws
}
