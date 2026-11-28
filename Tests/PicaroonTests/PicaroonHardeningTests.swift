import XCTest
import Hitch
import Flynn

import Picaroon

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

private let bigPayload = Data(repeating: 65, count: 64 * 1024 * 1024)

private func hardeningHandler(connection: Connection,
                              config: ServerConfig,
                              httpRequest: HttpRequest) -> HttpResponse? {
    if httpRequest.url == "/big" {
        return HttpResponse(status: .ok, type: .bin, payload: bigPayload)
    }
    return HttpResponse(text: "ok")
}

final class picaroonHardeningTests: XCTestCase {

    // MARK: - Helpers

    private func startServer(clientTimeout: TimeInterval = 5.0,
                             writeTimeout: TimeInterval = 10.0,
                             maxConnections: Int = 0) -> (Server<PicaroonTesting.WebUserSession>, Int) {
        let port = Int.random(in: 20000..<60000)
        let config = ServerConfig(address: "127.0.0.1",
                                  port: port,
                                  clientTimeout: clientTimeout,
                                  writeTimeout: writeTimeout,
                                  maxConnections: maxConnections)
        let server = Server<PicaroonTesting.WebUserSession>(config: config,
                                                           staticStorageHandler: hardeningHandler)
        server.listen()
        Flynn.usleep(250_000)
        return (server, port)
    }

    private func connect(port: Int) -> Socket {
        let socket = Socket(blocking: true)!
        socket.connectTo(address: "127.0.0.1", port: port)
        socket.setReadTimeout(milliseconds: 100)
        return socket
    }

    /// Reads until the server closes the connection or `timeout` elapses.
    private func readAll(_ socket: Socket, timeout: TimeInterval) -> (data: Data, closed: Bool) {
        let start = Date()
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 256 * 1024)
        while abs(start.timeIntervalSinceNow) < timeout {
            let count = buffer.withUnsafeMutableBufferPointer { ptr in
                socket.recv(bytes: ptr.baseAddress, count: ptr.count)
            }
            if count < 0 { return (data, true) }
            if count > 0 { data.append(contentsOf: buffer[0..<count]) }
        }
        return (data, false)
    }

    private func get(port: Int, path: String = "/", timeout: TimeInterval = 5) -> String {
        let socket = connect(port: port)
        defer { socket.close() }
        socket.send(hitch: Hitch(string: "GET \(path) HTTP/1.1\r\nHost: a\r\nConnection: close\r\n\r\n"))
        return String(decoding: readAll(socket, timeout: timeout).data, as: UTF8.self)
    }

    // MARK: - Connection limit

    func testEffectiveMaxConnections() {
        XCTAssertEqual(ServerConfig(address: "127.0.0.1", port: 8080, maxConnections: 5).effectiveMaxConnections, 5)
        XCTAssertEqual(ServerConfig(address: "127.0.0.1", port: 8080, maxConnections: -1).effectiveMaxConnections, 0)
        #if os(Linux) || canImport(Darwin)
        XCTAssertGreaterThanOrEqual(ServerConfig(address: "127.0.0.1", port: 8080).effectiveMaxConnections, 32)
        #endif
    }

    func testConfigDecodesWithoutNewFields() throws {
        // configs serialized before writeTimeout/maxConnections existed still decode, to the defaults
        let json = #"{"address":"127.0.0.1","port":8080,"basePath":"","clientTimeout":5,"serverTimeout":30,"maxRequestInBytes":1024,"connectionMaxBackoff":0.5,"sessionPer":0,"sessionActivityTimeout":3600,"maximumSessions":10,"debug":false}"#
        let config = try JSONDecoder().decode(ServerConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.writeTimeout, 10.0)
        XCTAssertEqual(config.maxConnections, 0)
    }

    func testConnectionsOverTheLimitGetServiceUnavailable() {
        let (server, port) = startServer(maxConnections: 2)
        defer { server.stop() }

        let held = [connect(port: port), connect(port: port)]
        Flynn.usleep(300_000)

        let start = Date()
        let rejected = get(port: port)
        XCTAssertTrue(rejected.hasPrefix("HTTP/1.1 503"), rejected)
        XCTAssertLessThan(abs(start.timeIntervalSinceNow), 2.0)

        // freeing the held connections makes room again
        held.forEach { $0.close() }
        Flynn.usleep(500_000)

        let accepted = get(port: port)
        XCTAssertTrue(accepted.hasPrefix("HTTP/1.1 200"), accepted)
    }

    // MARK: - Write timeout

    func testClientWhichStopsReadingIsDropped() {
        let (server, port) = startServer(clientTimeout: 30, writeTimeout: 1.0)
        defer { server.stop() }

        let socket = connect(port: port)
        defer { socket.close() }
        socket.send(hitch: "GET /big HTTP/1.1\r\nHost: a\r\n\r\n")

        // Stop reading long enough for the server's send to time out
        Flynn.usleep(4_000_000)

        // Without a write timeout the server would still be blocked in send(), and reading now
        // would let it finish delivering the whole payload. With one it has given up: we only get
        // what was already sitting in the socket buffers, then the close.
        let (data, closed) = readAll(socket, timeout: 10)
        XCTAssertTrue(closed)
        XCTAssertLessThan(data.count, bigPayload.count)

        // and the server is still serving everyone else
        let other = get(port: port)
        XCTAssertTrue(other.hasPrefix("HTTP/1.1 200"), other)
    }

    // MARK: - Keepalive

    func testKeepAliveIsEnabled() {
        let socket = Socket(blocking: true)!
        defer { socket.close() }

        XCTAssertTrue(socket.setKeepAlive(idleSeconds: 60, intervalSeconds: 10, count: 3))

        var value: Int32 = 0
        var size = socklen_t(MemoryLayout<Int32>.size)
        XCTAssertEqual(getsockopt(socket.fd(), SOL_SOCKET, SO_KEEPALIVE, &value, &size), 0)
        // Any non-zero value means enabled: Linux reports 1, while Darwin reports the option's own
        // bit (SO_KEEPALIVE, 0x8).
        XCTAssertNotEqual(value, 0)

        #if os(Linux)
        XCTAssertEqual(getsockopt(socket.fd(), 6 /* IPPROTO_TCP */, 4 /* TCP_KEEPIDLE */, &value, &size), 0)
        XCTAssertEqual(value, 60)
        #elseif canImport(Darwin)
        XCTAssertEqual(getsockopt(socket.fd(), 6 /* IPPROTO_TCP */, 0x10 /* TCP_KEEPALIVE */, &value, &size), 0)
        XCTAssertEqual(value, 60)
        #endif
    }

    // MARK: - Watch thread

    func testManyConcurrentConnections() {
        let (server, port) = startServer()
        defer { server.stop() }

        let sockets = (0..<200).map { _ in connect(port: port) }
        defer { sockets.forEach { $0.close() } }

        for socket in sockets {
            socket.send(hitch: "GET / HTTP/1.1\r\nHost: a\r\nConnection: close\r\n\r\n")
        }

        let start = Date()
        var ok = 0
        for socket in sockets {
            let response = String(decoding: readAll(socket, timeout: 5).data, as: UTF8.self)
            if response.hasPrefix("HTTP/1.1 200") { ok += 1 }
        }
        XCTAssertEqual(ok, sockets.count)
        XCTAssertLessThan(abs(start.timeIntervalSinceNow), 10.0)
    }
}
