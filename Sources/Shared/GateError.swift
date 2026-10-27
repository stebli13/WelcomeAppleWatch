import Foundation

/// Errors surfaced by any `GateClient`. Messages are shown on the watch.
enum GateError: LocalizedError {
    case notConfigured
    case notAuthenticated
    case server(status: Int, body: String)
    case network(underlying: Error)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Non configurato. Fai prima l’abbinamento dall’iPhone."
        case .notAuthenticated:
            return "Token non valido. Creane uno nuovo in Home Assistant e invialo dall’iPhone."
        case let .server(status, body):
            return "Home Assistant ha risposto con errore \(status). \(body)"
        case let .network(underlying):
            return "Errore di rete: \(underlying.localizedDescription)"
        case let .decoding(detail):
            return "Risposta inattesa: \(detail)"
        }
    }
}
