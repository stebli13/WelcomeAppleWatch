import CryptoKit
import Foundation
import Network
import Security

/// A minimal SIP-over-TLS client: exactly what `tools/abb_probe.py` does and
/// what was verified on the real installation through the ABB cloud server
/// (REGISTER with digest auth, optional INVITE, MESSAGE, BYE/CANCEL). The
/// message formats mirror the MIT-licensed community integration
/// rankjie/ha-abb-welcome (`sip_client.py`).
///
/// iPhone only: watchOS does not allow these sockets (Apple TN3135).
final class SIPClient {
    struct Account {
        var host: String
        var port: UInt16
        var domain: String
        var username: String
        var password: String
        var identity: SecIdentity
    }

    private let account: Account
    private let timeout: TimeInterval
    private let queue = DispatchQueue(label: "welcomegate.sip")
    private var connection: NWConnection?
    private var buffer = Data()
    private var localHost = "0.0.0.0"
    private var localPort: UInt16 = 0

    init(account: Account, timeout: TimeInterval = 6) {
        self.account = account
        self.timeout = timeout
    }

    deinit { connection?.cancel() }

    // MARK: - Public

    /// Sends one `MESSAGE` with `body` to outdoor station `stationID`,
    /// optionally inside a call (needed for the door lock).
    func send(body: String, toStation stationID: String, inCall: Bool) async throws {
        try await connect()
        defer { close() }
        try await register()

        let stationURI = "sip:\(stationID)@\(account.domain)"
        guard inCall else {
            try await message(to: stationURI, body: body)
            return
        }
        let call = try await invite(stationURI)
        do {
            try await message(to: call.targetURI, body: body)
        } catch {
            await hangUp(call)
            throw error
        }
        await hangUp(call)
    }

    // MARK: - Connection

    private func connect() async throws {
        let tls = NWProtocolTLS.Options()
        let sec = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv10)
        guard let identity = sec_identity_create(account.identity) else {
            throw GateError.identity("identità TLS non creata")
        }
        sec_protocol_options_set_local_identity(sec, identity)
        // Same as the probe and the community code: the server certificate is
        // not verified. Authentication is the client certificate + digest.
        sec_protocol_options_set_verify_block(sec, { _, _, complete in complete(true) }, queue)

        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = Int(timeout)
        let connection = NWConnection(
            host: NWEndpoint.Host(account.host),
            port: NWEndpoint.Port(rawValue: account.port) ?? 5061,
            using: NWParameters(tls: tls, tcp: tcp))
        self.connection = connection

        try await withTimeout("connessione") {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                // State updates arrive on `queue`, one at a time.
                let once = ResumeOnce()
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        once.run { cont.resume() }
                    case let .failed(error), let .waiting(error):
                        once.run { cont.resume(throwing: GateError.connection(error.localizedDescription)) }
                    case .cancelled:
                        once.run { cont.resume(throwing: GateError.connection("annullata")) }
                    default:
                        break
                    }
                }
                connection.start(queue: self.queue)
            }
        }
        if case let .hostPort(host, port)? = connection.currentPath?.localEndpoint {
            localHost = "\(host)".components(separatedBy: "%").first ?? "\(host)"
            localPort = port.rawValue
        }
    }

    private func close() {
        connection?.cancel()
        connection = nil
    }

    private func write(_ data: Data) async throws {
        guard let connection else { throw GateError.connection("chiusa") }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: GateError.connection(error.localizedDescription))
                } else {
                    cont.resume()
                }
            })
        }
    }

    private func readMore() async throws {
        guard let connection else { throw GateError.connection("chiusa") }
        let chunk: Data = try await withCheckedThrowingContinuation { cont in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
                data, _, isComplete, error in
                if let error {
                    cont.resume(throwing: GateError.connection(error.localizedDescription))
                } else if let data, !data.isEmpty {
                    cont.resume(returning: data)
                } else if isComplete {
                    cont.resume(throwing: GateError.connection("chiusa dal server"))
                } else {
                    cont.resume(returning: Data())
                }
            }
        }
        buffer.append(chunk)
    }

    // MARK: - Framing

    struct Frame {
        var startLine: String
        var headers: [(String, String)]
        var body: Data

        var isResponse: Bool { startLine.hasPrefix("SIP/2.0 ") }
        var status: Int {
            guard isResponse else { return 0 }
            let parts = startLine.split(separator: " ")
            return parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        }
        func header(_ name: String) -> String {
            headers.first { $0.0.caseInsensitiveCompare(name) == .orderedSame }?.1 ?? ""
        }
    }

    private func readFrame() async throws -> Frame {
        let separator = Data("\r\n\r\n".utf8)
        while buffer.range(of: separator) == nil { try await readMore() }
        let headerEnd = buffer.range(of: separator)!
        let headerText = String(decoding: buffer[buffer.startIndex..<headerEnd.lowerBound], as: UTF8.self)
        var lines = headerText.components(separatedBy: "\r\n")
        let startLine = lines.removeFirst()
        let headers: [(String, String)] = lines.compactMap { line in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            return (line[..<colon].trimmingCharacters(in: .whitespaces),
                    line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
        }
        let length = Int(headers.first { $0.0.lowercased() == "content-length" }?.1 ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        while buffer.distance(from: bodyStart, to: buffer.endIndex) < length {
            try await readMore()
        }
        let bodyEnd = buffer.index(bodyStart, offsetBy: length)
        let body = buffer[bodyStart..<bodyEnd]
        buffer = Data(buffer[bodyEnd...])
        return Frame(startLine: startLine, headers: headers, body: Data(body))
    }

    /// Next response to (callID, cseq, method); skips requests and other
    /// transactions. `final` also skips 1xx.
    private func response(callID: String, cseq: Int, method: String,
                          final: Bool = true, step: String) async throws -> Frame {
        try await withTimeout(step) {
            while true {
                let frame = try await self.readFrame()
                guard frame.isResponse, frame.header("Call-ID") == callID,
                      frame.header("CSeq").split(separator: " ").map(String.init)
                        == [String(cseq), method] else { continue }
                if final && frame.status / 100 == 1 { continue }
                return frame
            }
        }
    }

    // MARK: - Requests

    private struct Request {
        var method: String
        var uri: String
        var headers: [String]
        var body: String = ""

        var data: Data {
            let bodyBytes = Data(body.utf8)
            let head = ([ "\(method) \(uri) SIP/2.0" ] + headers
                        + ["Content-Length: \(bodyBytes.count)", "", ""])
                .joined(separator: "\r\n")
            return Data(head.utf8) + bodyBytes
        }
    }

    private var transportParam: String { ";transport=tls" }
    private var fromURI: String { "sip:\(account.username)@\(account.domain)\(transportParam)" }
    private var contact: String {
        "<sip:\(account.username)@\(localHost):\(localPort);transport=tls>"
    }
    private func via() -> String {
        "Via: SIP/2.0/TLS \(localHost):\(localPort);branch=z9hG4bK-\(Self.token(12));rport"
    }

    /// Sends `request`; on 401/407 resends it once with digest credentials
    /// (new branch, CSeq + 1). Returns the response and the CSeq used.
    private func transact(_ request: Request, callID: String, cseq: Int,
                          final: Bool = true, step: String) async throws -> (Frame, Int, Request) {
        try await write(request.data)
        var frame = try await response(callID: callID, cseq: cseq, method: request.method,
                                       final: final, step: step)
        guard frame.status == 401 || frame.status == 407 else { return (frame, cseq, request) }

        let proxy = frame.status == 407
        let challenge = frame.header(proxy ? "Proxy-Authenticate" : "WWW-Authenticate")
        guard let auth = digest(challenge: challenge, method: request.method, uri: request.uri,
                                headerName: proxy ? "Proxy-Authorization" : "Authorization") else {
            throw GateError.sip("\(request.method) \(frame.status) senza challenge")
        }
        var retry = request
        let next = cseq + 1
        retry.headers = retry.headers
            .filter { !$0.hasPrefix("Authorization:") && !$0.hasPrefix("Proxy-Authorization:") }
            .map { line in
                if line.hasPrefix("Via:") { return via() }
                if line.hasPrefix("CSeq:") { return "CSeq: \(next) \(request.method)" }
                return line
            } + [auth]
        try await write(retry.data)
        frame = try await response(callID: callID, cseq: next, method: request.method,
                                   final: final, step: step)
        return (frame, next, retry)
    }

    private func register() async throws {
        let callID = "\(Self.token(16))@\(account.domain)"
        let request = Request(method: "REGISTER", uri: "sip:\(account.domain)\(transportParam)", headers: [
            via(),
            "Max-Forwards: 70",
            "From: <\(fromURI)>;tag=\(Self.token(8))",
            "To: <\(fromURI)>",
            "Call-ID: \(callID)",
            "CSeq: 1 REGISTER",
            "Contact: \(contact)",
            "Expires: 3600",
            "User-Agent: WelcomeGate/1.0",
        ])
        let (frame, _, _) = try await transact(request, callID: callID, cseq: 1, step: "REGISTER")
        guard frame.status == 200 else { throw GateError.sip("REGISTER: \(frame.startLine)") }
    }

    private func message(to uri: String, body: String) async throws {
        let callID = "\(Self.token(16))@\(account.domain)"
        let request = Request(method: "MESSAGE", uri: uri, headers: [
            via(),
            "Max-Forwards: 70",
            "From: <\(fromURI)>;tag=\(Self.token(8))",
            "To: <\(uri)>",
            "Call-ID: \(callID)",
            "CSeq: 1 MESSAGE",
            "Content-Type: text/plain",
            "User-Agent: WelcomeGate/1.0",
        ], body: body)
        let (frame, _, _) = try await transact(request, callID: callID, cseq: 1, step: "MESSAGE")
        guard frame.status == 200 else { throw GateError.sip("MESSAGE: \(frame.startLine)") }
    }

    // MARK: - Call (door lock)

    private struct Call {
        var requestURI: String
        var targetURI: String
        var callID: String
        var fromHeader: String
        var remoteTo: String
        var remoteContact: String
        var inviteCSeq: Int
        var inviteVia: String
        var established: Bool
    }

    private func invite(_ stationURI: String) async throws -> Call {
        let callID = "\(Self.token(16))@\(account.domain)"
        let fromHeader = "From: <\(fromURI)>;tag=\(Self.token(8))"
        let request = Request(method: "INVITE", uri: stationURI, headers: [
            via(),
            "Max-Forwards: 70",
            fromHeader,
            "To: <\(stationURI)>",
            "Call-ID: \(callID)",
            "CSeq: 1 INVITE",
            "Contact: \(contact)",
            "User-Agent: WelcomeGate/1.0",
            "Allow: INVITE, ACK, CANCEL, BYE, MESSAGE, OPTIONS",
            "Accept: application/sdp",
            "Content-Type: application/sdp",
        ], body: Self.offerSDP(localHost))

        let (first, cseq, sent) = try await transact(request, callID: callID, cseq: 1,
                                                     final: false, step: "INVITE")
        var frame = first
        var call = Call(requestURI: stationURI, targetURI: stationURI + transportParam,
                        callID: callID, fromHeader: fromHeader,
                        remoteTo: "To: <\(stationURI)>", remoteContact: stationURI,
                        inviteCSeq: cseq, inviteVia: sent.headers[0], established: false)
        // Wait for 183 (early media, enough for the MESSAGE) or 200.
        while true {
            if !frame.header("To").isEmpty { call.remoteTo = "To: \(frame.header("To"))" }
            if let uri = Self.contactURI(frame.header("Contact")) { call.remoteContact = uri }
            switch frame.status {
            case 183:
                return call
            case 200:
                call.established = true
                try await ack(call)
                return call
            case 300...:
                throw GateError.sip("INVITE: \(frame.startLine)")
            default:
                frame = try await response(callID: callID, cseq: cseq, method: "INVITE",
                                           final: false, step: "INVITE")
            }
        }
    }

    private func ack(_ call: Call) async throws {
        try await write(Request(method: "ACK", uri: call.requestURI, headers: [
            via(), "Max-Forwards: 70", call.fromHeader, call.remoteTo,
            "Call-ID: \(call.callID)", "CSeq: \(call.inviteCSeq) ACK",
        ]).data)
    }

    /// BYE an answered call, CANCEL a ringing one. Best effort: the command
    /// has already been accepted, so failures here are ignored.
    private func hangUp(_ call: Call) async {
        let request: Request
        if call.established {
            request = Request(method: "BYE", uri: call.remoteContact, headers: [
                via(), "Max-Forwards: 70", call.fromHeader, call.remoteTo,
                "Call-ID: \(call.callID)", "CSeq: \(call.inviteCSeq + 1) BYE",
                "Contact: \(contact)", "User-Agent: WelcomeGate/1.0",
            ])
        } else {
            request = Request(method: "CANCEL", uri: call.requestURI, headers: [
                call.inviteVia, "Max-Forwards: 70", call.fromHeader, "To: <\(call.requestURI)>",
                "Call-ID: \(call.callID)", "CSeq: \(call.inviteCSeq) CANCEL",
                "User-Agent: WelcomeGate/1.0",
            ])
        }
        try? await write(request.data)
        let cseq = call.established ? call.inviteCSeq + 1 : call.inviteCSeq
        _ = try? await response(callID: call.callID, cseq: cseq, method: request.method,
                                step: request.method)
    }

    // MARK: - Helpers

    private func digest(challenge: String, method: String, uri: String,
                        headerName: String) -> String? {
        guard challenge.lowercased().hasPrefix("digest") else { return nil }
        var params: [String: String] = [:]
        let pattern = try! NSRegularExpression(pattern: #"(\w+)="?([^",]+)"?"#) // swiftlint:disable:this force_try
        let text = String(challenge.dropFirst(6))
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let key = Range(match.range(at: 1), in: text),
                  let value = Range(match.range(at: 2), in: text) else { continue }
            params[String(text[key])] = String(text[value])
        }
        guard let realm = params["realm"], let nonce = params["nonce"] else { return nil }
        let qop = params["qop"].map { $0.split(separator: ",").first.map(String.init) ?? $0 } ?? "auth"
        let nc = "00000001"
        let cnonce = Self.token(8)
        let ha1 = Self.md5("\(account.username):\(realm):\(account.password)")
        let ha2 = Self.md5("\(method):\(uri)")
        let response = Self.md5("\(ha1):\(nonce):\(nc):\(cnonce):\(qop):\(ha2)")
        var header = "\(headerName): Digest username=\"\(account.username)\", realm=\"\(realm)\", "
            + "nonce=\"\(nonce)\", uri=\"\(uri)\", response=\"\(response)\", "
            + "algorithm=MD5, cnonce=\"\(cnonce)\", qop=\(qop), nc=\(nc)"
        if let opaque = params["opaque"] { header += ", opaque=\"\(opaque)\"" }
        return header
    }

    private static func contactURI(_ value: String) -> String? {
        guard !value.isEmpty else { return nil }
        if let open = value.firstIndex(of: "<"), let close = value.firstIndex(of: ">"), open < close {
            return String(value[value.index(after: open)..<close])
        }
        return value.trimmingCharacters(in: .whitespaces)
    }

    private static func offerSDP(_ ip: String) -> String {
        let session = Int(Date().timeIntervalSince1970 * 1000)
        // No media is sent: ports are placeholders, as in the community client.
        return [
            "v=0", "o=- \(session) 1 IN IP4 \(ip)", "s=Welcome Gate", "c=IN IP4 \(ip)", "t=0 0",
            "m=audio 40000 RTP/AVP 0 8 101",
            "a=rtpmap:0 PCMU/8000", "a=rtpmap:8 PCMA/8000",
            "a=rtpmap:101 telephone-event/8000", "a=fmtp:101 0-16", "a=sendrecv",
            "m=video 40002 RTP/AVP 96 97 98",
            "a=rtpmap:96 H264/90000", "a=rtpmap:97 VP8/90000", "a=rtpmap:98 H263-1998/90000",
            "a=sendrecv", "",
        ].joined(separator: "\r\n")
    }

    private static func md5(_ text: String) -> String {
        Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func token(_ length: Int) -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(length))
    }

    private func withTimeout<T: Sendable>(_ step: String,
                                          _ work: @escaping () async throws -> T) async throws -> T {
        let seconds = timeout
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask { [weak self] in
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                // A pending NWConnection callback never returns on task
                // cancellation; cancelling the connection makes it fail, so
                // the group can finish.
                self?.connection?.cancel()
                throw GateError.timeout(step)
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw GateError.timeout(step) }
            return result
        }
    }
}

/// Resumes a continuation at most once.
private final class ResumeOnce: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()

    func run(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        body()
    }
}

/// `GateClient` for the iPhone: opens through the ABB cloud SIP server, so it
/// works at home and away. A fresh connection per command, like the probe.
struct ABBCloudClient: GateClient {
    let account: ABBAccount

    func activate(_ relay: Relay) async throws {
        guard relay.isComplete else { throw GateError.notConfigured }
        let client = SIPClient(account: .init(
            host: account.cloudHost, port: account.cloudPort, domain: account.sipDomain,
            username: account.sipUsername, password: account.sipPassword,
            identity: try account.identity()))
        try await client.send(body: relay.body, toStation: relay.stationID, inCall: relay.inCall)
    }
}
