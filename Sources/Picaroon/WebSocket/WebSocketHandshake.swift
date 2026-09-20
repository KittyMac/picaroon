import Foundation
import Hitch
import CryptoSwift

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct WebSocketEndpoint {
    public let host: String
    public let port: Int
    public let path: Hitch
    public let hostHeader: Hitch

    public init?(url: String) {
        guard let components = URLComponents(string: url),
              let scheme = components.scheme?.lowercased() else { return nil }

        // wss would need a TLS stream, which Socket does not provide. CDP is
        // always plaintext loopback, so this is a hard stop rather than a TODO.
        guard scheme == "ws" || scheme == "http" else { return nil }

        guard var host = components.host,
              host.isEmpty == false else { return nil }

        if host == "localhost" {
            host = "127.0.0.1"
        }

        self.host = host
        self.port = components.port ?? 80

        let path = Hitch(string: components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath)
        if let query = components.percentEncodedQuery {
            path.append("?")
            path.append(query)
        }
        self.path = path

        self.hostHeader = Hitch(string: "\(host):\(self.port)")
    }
}

public enum WebSocketHandshakeResult {
    case needMoreData
    case success(Int)
    case failure(String)
}

public struct WebSocketHandshake {

    /// RFC 6455 1.3. Fixed and not secret; it exists so a server cannot pass
    /// off a cached HTTP response as a WebSocket upgrade.
    private static let magic: StaticString = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    private static let headerTerminator = HalfHitch(stringLiteral: "\r\n\r\n")
    private static let crlf = HalfHitch(stringLiteral: "\r\n")
    private static let space = HalfHitch(stringLiteral: " ")

    private static let upgradeHeader = HalfHitch(stringLiteral: "upgrade")
    private static let connectionHeader = HalfHitch(stringLiteral: "connection")
    private static let acceptHeader = HalfHitch(stringLiteral: "sec-websocket-accept")
    private static let extensionsHeader = HalfHitch(stringLiteral: "sec-websocket-extensions")
    private static let websocketValue = HalfHitch(stringLiteral: "websocket")

    /// The Sec-WebSocket-Key we sent, kept only for diagnostics.
    public let key: Hitch
    /// What the server must echo in Sec-WebSocket-Accept.
    public let expectedAccept: Hitch

    /// 16 random bytes, base64 encoded (RFC 6455 4.1). This is not
    /// authentication and does not need to be unguessable in the security
    /// sense, but it does need to differ per connection or a proxy could
    /// serve a cached 101 from a different connection.
    public init() {
        var nonce = [UInt8](repeating: 0, count: 16)
        for index in 0..<16 {
            nonce[index] = UInt8.random(in: UInt8.min...UInt8.max)
        }
        self.init(nonce: nonce)
    }

    /// Exposed so tests can drive the RFC 6455 1.3 example vector.
    public init(nonce: [UInt8]) {
        let key = Hitch(string: Data(nonce).base64EncodedString())

        let accepted = Hitch(capacity: 64)
        accepted.append(key)
        accepted.append(Hitch(stringLiteral: WebSocketHandshake.magic))

        let digest = Digest.sha1([UInt8](accepted.dataNoCopy()))

        self.key = key
        self.expectedAccept = Hitch(string: Data(digest).base64EncodedString())
    }

    /// The upgrade request.
    public func request(endpoint: WebSocketEndpoint,
                        headers: [String: String] = [:]) -> Hitch {
        let request = Hitch(capacity: 512)

        request.append("GET ")
        request.append(endpoint.path)
        request.append(" HTTP/1.1\r\n")

        request.append("Host: ")
        request.append(endpoint.hostHeader)
        request.append("\r\n")

        request.append("Upgrade: websocket\r\n")
        request.append("Connection: Upgrade\r\n")

        request.append("Sec-WebSocket-Key: ")
        request.append(key)
        request.append("\r\n")

        request.append("Sec-WebSocket-Version: 13\r\n")

        for (name, value) in headers {
            request.append(name)
            request.append(": ")
            request.append(value)
            request.append("\r\n")
        }

        request.append("\r\n")

        return request
    }

    /// Validates the response sitting at the front of `bytes`.
    public func validate(bytes: UnsafePointer<UInt8>,
                         count: Int) -> WebSocketHandshakeResult {
        let buffer = HalfHitch(sourceObject: nil,
                               raw: bytes,
                               count: count,
                               from: 0,
                               to: count)

        guard let terminator = buffer.firstIndex(of: WebSocketHandshake.headerTerminator) else {
            return .needMoreData
        }

        let consumed = terminator + WebSocketHandshake.headerTerminator.count
        let head = HalfHitch(source: buffer, from: 0, to: terminator)
        let lines: [HalfHitch] = head.components(separatedBy: WebSocketHandshake.crlf)

        guard let statusLine = lines.first else {
            return .failure("empty handshake response")
        }

        // "HTTP/1.1 101 WebSocket Protocol Handshake" is what net::HttpServer
        // sends; the reason phrase is not fixed, so only the code is checked.
        let statusParts: [HalfHitch] = statusLine.components(separatedBy: WebSocketHandshake.space)
        guard statusParts.count >= 2,
              let status = statusParts[1].toInt() else {
            return .failure("malformed status line: \(statusLine.toString())")
        }
        guard status == 101 else {
            return .failure("expected 101, got \(status): \(statusLine.toString())")
        }

        var sawUpgrade = false
        var sawConnectionUpgrade = false
        var sawAccept = false

        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: UInt8.colon) else { continue }

            let name = HalfHitch(source: line, from: 0, to: colon).trimmed()
            let value = HalfHitch(source: line, from: colon + 1, to: line.count).trimmed()

            if name.equals(caseless: WebSocketHandshake.upgradeHeader) {
                guard value.equals(caseless: WebSocketHandshake.websocketValue) else {
                    return .failure("Upgrade header was \"\(value.toString())\", expected \"websocket\"")
                }
                sawUpgrade = true
            } else if name.equals(caseless: WebSocketHandshake.connectionHeader) {
                // May legitimately be a comma-separated list, so substring
                // rather than equality. Lowercased first because contains() is
                // case sensitive.
                guard value.hitch().lowercase().contains(WebSocketHandshake.upgradeHeader) else {
                    return .failure("Connection header was \"\(value.toString())\", expected to include \"Upgrade\"")
                }
                sawConnectionUpgrade = true
            } else if name.equals(caseless: WebSocketHandshake.acceptHeader) {
                // Base64, so compared exactly rather than caselessly.
                guard value.equals(exact: expectedAccept.halfhitch()) else {
                    return .failure("Sec-WebSocket-Accept mismatch: got \"\(value.toString())\", expected \"\(expectedAccept.toString())\"")
                }
                sawAccept = true
            } else if name.equals(caseless: WebSocketHandshake.extensionsHeader) {
                // We offered none, so the server has no business selecting one.
                // Accepting silently would mean decoding frames whose RSV bits
                // now carry meaning we do not implement.
                return .failure("server selected unrequested extension \"\(value.toString())\"")
            }
        }

        guard sawUpgrade else { return .failure("response is missing the Upgrade header") }
        guard sawConnectionUpgrade else { return .failure("response is missing the Connection header") }
        guard sawAccept else { return .failure("response is missing Sec-WebSocket-Accept") }

        return .success(consumed)
    }
}
