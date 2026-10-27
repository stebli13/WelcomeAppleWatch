import Foundation

/// `GateClient` that talks to the ABB Welcome IP **cloud** API, by replaying the
/// authenticated requests the official Welcome App makes.
///
/// Works anywhere the device has internet (ideal for a watch on LTE). Handles
/// OAuth access-token refresh transparently and retries once on 401.
///
/// The exact request shapes are driven by `GateConfiguration` so that, once your
/// capture (docs/traffic-capture-playbook.md) confirms the real endpoints and
/// IDs, no code changes are needed — only the stored configuration.
actor ABBWelcomeCloudClient: GateClient {
    private let configuration: GateConfiguration
    private var credentials: GateCredentials
    private let session: URLSession
    /// Called whenever credentials change (e.g. after a refresh) so the host
    /// can persist them to the Keychain.
    private let onCredentialsUpdated: (@Sendable (GateCredentials) -> Void)?

    init(configuration: GateConfiguration,
         credentials: GateCredentials,
         session: URLSession = .shared,
         onCredentialsUpdated: (@Sendable (GateCredentials) -> Void)? = nil) {
        self.configuration = configuration
        self.credentials = credentials
        self.session = session
        self.onCredentialsUpdated = onCredentialsUpdated
    }

    // MARK: - GateClient

    func activate(_ relay: Relay) async throws {
        guard configuration.isComplete, relay.isComplete,
              let url = configuration.activationURL(for: relay) else {
            throw GateError.notConfigured
        }
        let body = try JSONSerialization.data(
            withJSONObject: ["value": relay.openValue])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        _ = try await sendAuthorized(request)
    }

    func snapshot(of station: OutdoorStation) async throws -> Data {
        guard let url = configuration.snapshotURL(for: station) else {
            throw GateError.notConfigured
        }
        return try await sendAuthorized(URLRequest(url: url))
    }

    // MARK: - Authorized requests

    /// Sends a request with the current bearer token, refreshing it first if
    /// expired and once more if the server answers 401.
    private func sendAuthorized(_ request: URLRequest) async throws -> Data {
        if credentials.isExpired { try await refreshToken() }
        do {
            return try await send(request)
        } catch GateError.server(status: 401, _) {
            // Token may have been revoked mid-flight; refresh once and retry.
            try await refreshToken()
            return try await send(request)
        }
    }

    private func send(_ unauthorized: URLRequest) async throws -> Data {
        var request = unauthorized
        request.timeoutInterval = 15
        request.setValue("Bearer \(credentials.accessToken)",
                         forHTTPHeaderField: "Authorization")
        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else {
            throw GateError.decoding("No HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GateError.server(status: http.statusCode, body: body)
        }
        return data
    }

    // MARK: - Token handling

    private func refreshToken() async throws {
        guard let url = URL(string: configuration.refreshURL) else {
            throw GateError.tokenRefreshFailed
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded",
                         forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = [
            .init(name: "grant_type", value: "refresh_token"),
            .init(name: "refresh_token", value: credentials.refreshToken),
            .init(name: "client_id", value: configuration.clientID),
        ]
        request.httpBody = components.percentEncodedQuery?
            .data(using: .utf8)

        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw GateError.tokenRefreshFailed
        }
        let token = try decodeTokenResponse(data)
        credentials = GateCredentials(
            accessToken: token.accessToken,
            // Some servers rotate the refresh token; keep the old one if absent.
            refreshToken: token.refreshToken ?? credentials.refreshToken,
            expiresAt: Date().addingTimeInterval(token.expiresIn ?? 3600))
        onCredentialsUpdated?(credentials)
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: TimeInterval?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    private func decodeTokenResponse(_ data: Data) throws -> TokenResponse {
        do { return try JSONDecoder().decode(TokenResponse.self, from: data) }
        catch { throw GateError.decoding("token response: \(error)") }
    }

    // MARK: - Networking

    private func perform(_ request: URLRequest) async throws
        -> (Data, URLResponse) {
        do { return try await session.data(for: request) }
        catch { throw GateError.network(underlying: error) }
    }
}
