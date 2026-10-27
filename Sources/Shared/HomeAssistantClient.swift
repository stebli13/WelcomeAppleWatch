import Foundation

/// An entity as listed by Home Assistant, for the setup pickers.
struct HAEntity: Identifiable, Hashable, Decodable {
    let entityID: String
    let name: String
    var id: String { entityID }

    private enum CodingKeys: String, CodingKey { case entityID = "entity_id", attributes }
    private struct Attributes: Decodable {
        let friendlyName: String?
        private enum CodingKeys: String, CodingKey { case friendlyName = "friendly_name" }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entityID = try container.decode(String.self, forKey: .entityID)
        let attributes = try container.decodeIfPresent(Attributes.self, forKey: .attributes)
        name = attributes?.friendlyName ?? entityID
    }
}

/// `GateClient` that drives the ABB-Welcome installation through Home Assistant's
/// REST API, using a long-lived access token. Home Assistant (with the ABB
/// Welcome integration) does the pairing and the SIP unlock; this only asks it
/// to press the right entity, so it works anywhere Home Assistant is reachable.
struct HomeAssistantClient: GateClient {
    let configuration: GateConfiguration
    let token: String
    var session: URLSession = .shared

    // MARK: - GateClient

    func activate(_ relay: Relay) async throws {
        guard relay.isComplete else { throw GateError.notConfigured }
        let (domain, service) = Self.service(for: relay)
        let body = try JSONSerialization.data(withJSONObject: ["entity_id": relay.entityID])
        _ = try await send("/api/services/\(domain)/\(service)", method: "POST", body: body)
    }

    func snapshot(of station: OutdoorStation) async throws -> Data {
        guard let entity = station.pictureEntityID, !entity.isEmpty else {
            throw GateError.notConfigured
        }
        let proxy = entity.hasPrefix("image.") ? "image_proxy" : "camera_proxy"
        return try await send("/api/\(proxy)/\(entity)", method: "GET")
    }

    /// All entities Home Assistant knows, sorted by name.
    func entities() async throws -> [HAEntity] {
        let data = try await send("/api/states", method: "GET")
        do {
            return try JSONDecoder().decode([HAEntity].self, from: data)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            throw GateError.decoding("elenco entità: \(error.localizedDescription)")
        }
    }

    // MARK: - Service mapping

    /// Which Home Assistant service "fires" an entity of a given domain.
    static func service(for relay: Relay) -> (domain: String, service: String) {
        switch relay.domain {
        case "button": return ("button", "press")
        case "lock": return ("lock", "unlock")
        case "cover": return ("cover", "open_cover")
        case "script": return ("script", "turn_on")
        case "scene": return ("scene", "turn_on")
        case "automation": return ("automation", "trigger")
        case "switch", "input_boolean", "light", "fan":
            return (relay.domain, "turn_on")
        default: return ("homeassistant", "turn_on")
        }
    }

    // MARK: - Networking

    private func send(_ path: String, method: String, body: Data? = nil) async throws -> Data {
        guard !token.isEmpty, let url = configuration.url(path: path) else {
            throw GateError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw GateError.network(underlying: error) }

        guard let http = response as? HTTPURLResponse else {
            throw GateError.decoding("nessuna risposta HTTP")
        }
        switch http.statusCode {
        case 200...299: return data
        case 401, 403: throw GateError.notAuthenticated
        default:
            throw GateError.server(status: http.statusCode,
                                   body: String(data: data.prefix(200), encoding: .utf8) ?? "")
        }
    }
}
