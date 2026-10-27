import Foundation

/// Reads/writes the paired state from the Keychain and constructs a configured
/// `GateClient`. Shared by the iPhone and watch targets.
enum GateStore {
    static func loadConfiguration() -> GateConfiguration {
        KeychainStore.load(GateConfiguration.self,
                           key: KeychainStore.configurationKey)
            ?? .placeholder
    }

    static func loadCredentials() -> GateCredentials? {
        KeychainStore.load(GateCredentials.self,
                           key: KeychainStore.credentialsKey)
    }

    static var isPaired: Bool {
        loadConfiguration().isComplete && loadCredentials() != nil
    }

    static func save(_ payload: GatePairingPayload) throws {
        try KeychainStore.save(payload.configuration,
                               key: KeychainStore.configurationKey)
        try KeychainStore.save(payload.credentials,
                               key: KeychainStore.credentialsKey)
    }

    static func clear() {
        KeychainStore.delete(key: KeychainStore.configurationKey)
        KeychainStore.delete(key: KeychainStore.credentialsKey)
    }

    /// Builds a client from stored state, or nil if not paired.
    static func makeClient() -> GateClient? {
        guard isPaired, let credentials = loadCredentials() else { return nil }
        return HomeAssistantClient(configuration: loadConfiguration(),
                                   token: credentials.token)
    }
}
