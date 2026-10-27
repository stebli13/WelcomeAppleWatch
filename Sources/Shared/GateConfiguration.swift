import Foundation

/// A switchable actuator listed under "Controllo accessi → Relè" (e.g.
/// "Cancello-citofono", "Basculante-citofono"), backed by one Home Assistant
/// entity such as `button.cancello_citofono_unlock`.
struct Relay: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var entityID: String

    /// Service domain, i.e. the part of the entity id before the dot.
    var domain: String { String(entityID.split(separator: ".").first ?? "") }

    var isComplete: Bool {
        !name.isEmpty && !domain.isEmpty && entityID.contains(".")
    }
}

/// An outdoor station ("Posto esterno", e.g. "Outdoor Station 1-citofono").
struct OutdoorStation: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    /// Home Assistant `camera.*` or `image.*` entity used for the picture.
    /// `nil` = no picture, the placeholder panel is shown.
    var pictureEntityID: String?
    /// Relays offered on this station's screen.
    var relayIDs: [String]
}

/// Where Home Assistant lives and what to show. Not secret (the access token
/// is, and lives separately in the Keychain), but per-installation, so it is
/// stored with the credentials and synced to the watch.
struct GateConfiguration: Codable, Equatable {
    /// e.g. `https://xxxx.ui.nabu.casa` or `http://homeassistant.local:8123`.
    var baseURL: String
    var relays: [Relay]
    var stations: [OutdoorStation]

    private var trimmedBase: String {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        return base
    }

    var hasValidBaseURL: Bool {
        guard let url = URL(string: trimmedBase), let scheme = url.scheme?.lowercased()
        else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }

    /// True once the address is valid and every relay points to an entity.
    var isComplete: Bool {
        hasValidBaseURL && !relays.isEmpty && relays.allSatisfy(\.isComplete)
    }

    func relay(id: String) -> Relay? { relays.first { $0.id == id } }

    func url(path: String) -> URL? { URL(string: trimmedBase + path) }

    /// Mirrors the installation shown in the iPhone app; entities are chosen
    /// in the setup screen.
    static let placeholder: GateConfiguration = {
        let gate = Relay(name: "Cancello-citofono", entityID: "")
        let garage = Relay(name: "Basculante-citofono", entityID: "")
        return GateConfiguration(
            baseURL: "http://homeassistant.local:8123",
            relays: [gate, garage],
            stations: [OutdoorStation(name: "Outdoor Station 1-citofono",
                                      pictureEntityID: nil,
                                      relayIDs: [gate.id, garage.id])])
    }()
}
