import Foundation

/// Errors surfaced by any `GateClient`. Messages are shown on the watch.
enum GateError: LocalizedError {
    case notConfigured
    case phoneUnreachable
    case identity(String)
    case connection(String)
    case timeout(String)
    case sip(String)
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Non configurato. Importa il file dal Mac nell’app iPhone."
        case .phoneUnreachable:
            return "iPhone non raggiungibile. Tienilo vicino e acceso."
        case let .identity(detail):
            return "Certificato non valido: \(detail)"
        case let .connection(detail):
            return "Connessione al server ABB non riuscita: \(detail)"
        case let .timeout(step):
            return "Nessuna risposta dal server ABB (\(step))."
        case let .sip(detail):
            return "Il server ABB ha rifiutato il comando: \(detail)"
        case let .remote(message):
            return message
        }
    }
}
