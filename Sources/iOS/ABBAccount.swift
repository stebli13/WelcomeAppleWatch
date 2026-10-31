import CommonCrypto
import CryptoKit
import Foundation
import Security

/// The pairing identity made by `tools/abb_probe.py pair` on the Mac and
/// brought over with `export`. Secret: iPhone Keychain only, never synced to
/// the watch, never logged.
struct ABBAccount: Codable, Equatable {
    var sipDomain: String
    var sipUsername: String
    var sipPassword: String
    /// ABB/Busch-Jaeger SIP server, reachable from anywhere
    /// (`sip.my.busch-jaeger.de`, port 5061).
    var cloudHost: String
    var cloudPort: UInt16
    var gatewayIP: String
    var clientName: String
    /// Client certificate + private key, as PKCS#12.
    var pkcs12: Data
    var pkcs12Password: String

    /// The TLS client identity for the server.
    func identity() throws -> SecIdentity {
        var items: CFArray?
        let options = [kSecImportExportPassphrase as String: pkcs12Password] as CFDictionary
        let status = SecPKCS12Import(pkcs12 as CFData, options, &items)
        guard status == errSecSuccess,
              let first = (items as? [[String: Any]])?.first,
              let value = first[kSecImportItemIdentity as String] else {
            throw GateError.identity("importazione PKCS#12 fallita (\(status))")
        }
        // CFTypeRef → SecIdentity: the dictionary value is always one.
        return value as! SecIdentity // swiftlint:disable:this force_cast
    }
}

enum ABBAccountStore {
    static func load() -> ABBAccount? {
        KeychainStore.load(ABBAccount.self, key: KeychainStore.accountKey)
    }

    static func save(_ account: ABBAccount) throws {
        try KeychainStore.save(account, key: KeychainStore.accountKey)
    }

    static func clear() { KeychainStore.delete(key: KeychainStore.accountKey) }

    /// A client for the stored account, or nil before the import.
    static func makeClient() -> GateClient? {
        load().map { ABBCloudClient(account: $0) }
    }
}

/// Reads the encrypted file written by `abb_probe.py export`.
enum PairingImport {
    struct Result {
        var account: ABBAccount
        var configuration: GateConfiguration
    }

    enum ImportError: LocalizedError {
        case notABundle, wrongPassphrase, invalidContent(String)

        var errorDescription: String? {
            switch self {
            case .notABundle: return "Il file non è un export di Welcome Gate."
            case .wrongPassphrase: return "Passphrase sbagliata (o file danneggiato)."
            case let .invalidContent(detail): return "Contenuto non valido: \(detail)"
            }
        }
    }

    private struct Outer: Decodable {
        let format: String
        let version: Int
        let kdf: String
        let iterations: Int
        let salt: String
        let nonce: String
        let ciphertext: String
    }

    private struct Inner: Decodable {
        struct Station: Decodable { let name: String; let station_id: String }
        struct RelayEntry: Decodable { let name: String; let address: String }
        let sip_domain: String
        let sip_username: String
        let sip_password: String
        let cloud_host: String
        let cloud_port: UInt16
        let gateway_ip: String
        let client_name: String
        let pkcs12: String
        let pkcs12_password: String
        let stations: [Station]
        let relays: [RelayEntry]
    }

    static func read(_ data: Data, passphrase: String) throws -> Result {
        guard let outer = try? JSONDecoder().decode(Outer.self, from: data),
              outer.format == "welcomegate-bundle", outer.version == 1,
              outer.kdf == "pbkdf2-sha256",
              let salt = Data(base64Encoded: outer.salt),
              let nonce = Data(base64Encoded: outer.nonce),
              let sealed = Data(base64Encoded: outer.ciphertext),
              sealed.count > 16 else { throw ImportError.notABundle }

        let key = try pbkdf2SHA256(passphrase, salt: salt, iterations: outer.iterations)
        let plaintext: Data
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce),
                                            ciphertext: sealed.dropLast(16),
                                            tag: sealed.suffix(16))
            plaintext = try AES.GCM.open(box, using: key)
        } catch {
            throw ImportError.wrongPassphrase
        }

        let inner: Inner
        do { inner = try JSONDecoder().decode(Inner.self, from: plaintext) }
        catch { throw ImportError.invalidContent(error.localizedDescription) }
        guard let p12 = Data(base64Encoded: inner.pkcs12) else {
            throw ImportError.invalidContent("certificato")
        }

        let account = ABBAccount(
            sipDomain: inner.sip_domain, sipUsername: inner.sip_username,
            sipPassword: inner.sip_password, cloudHost: inner.cloud_host,
            cloudPort: inner.cloud_port, gatewayIP: inner.gateway_ip,
            clientName: inner.client_name, pkcs12: p12,
            pkcs12Password: inner.pkcs12_password)
        _ = try account.identity() // fail now rather than at the gate

        let configuration = GateConfiguration.from(
            stations: inner.stations.map { ($0.name, $0.station_id) },
            relays: inner.relays.map { ($0.name, $0.address) })
        guard configuration.isComplete else {
            throw ImportError.invalidContent("nessun posto esterno")
        }
        return Result(account: account, configuration: configuration)
    }

    private static func pbkdf2SHA256(_ passphrase: String, salt: Data,
                                     iterations: Int) throws -> SymmetricKey {
        let keyLength = 32
        var derived = [UInt8](repeating: 0, count: keyLength)
        let password = Array(passphrase.utf8)
        let status = salt.withUnsafeBytes { saltBytes in
            password.withUnsafeBufferPointer { passwordBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) },
                    password.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations), &derived, keyLength)
            }
        }
        guard status == Int32(kCCSuccess) else { throw ImportError.notABundle }
        return SymmetricKey(data: derived)
    }
}
