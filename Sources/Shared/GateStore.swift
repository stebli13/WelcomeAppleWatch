import Foundation

/// The screen configuration (relays, stations), stored in the Keychain on
/// both devices. Secrets are handled separately, on the iPhone only
/// (`ABBAccountStore`).
enum GateStore {
    static func loadConfiguration() -> GateConfiguration {
        KeychainStore.load(GateConfiguration.self, key: KeychainStore.configurationKey)
            ?? .empty
    }

    static func saveConfiguration(_ configuration: GateConfiguration) throws {
        try KeychainStore.save(configuration, key: KeychainStore.configurationKey)
    }

    static var isConfigured: Bool { loadConfiguration().isComplete }

    static func clear() {
        KeychainStore.delete(key: KeychainStore.configurationKey)
    }
}
