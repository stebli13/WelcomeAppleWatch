import Foundation

/// Errors surfaced by any `GateClient`.
enum GateError: LocalizedError {
    case notConfigured
    case notAuthenticated
    case tokenRefreshFailed
    case server(status: Int, body: String)
    case network(underlying: Error)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "The gate is not configured yet. Pair on your iPhone first."
        case .notAuthenticated:
            return "Not signed in. Open the iPhone app and sign in to myBUILDINGS."
        case .tokenRefreshFailed:
            return "Your session expired and could not be refreshed. Sign in again on iPhone."
        case let .server(status, body):
            return "The door service rejected the request (\(status)). \(body)"
        case let .network(underlying):
            return "Network error: \(underlying.localizedDescription)"
        case let .decoding(detail):
            return "Unexpected response: \(detail)"
        }
    }
}
