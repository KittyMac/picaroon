import XCTest
import Hitch
import Flynn

import Picaroon

private func staticHandler(connection: Connection,
                           config: ServerConfig,
                           httpRequest: HttpRequest) -> HttpResponse? {
    return HttpResponse(text: "ok")
}

final class picaroonRobustnessTests: XCTestCase {

    let serverConfig = ServerConfig(address: "127.0.0.1", port: 8080)

    // MARK: - HttpRequest.validate

    private func validate(_ request: String, config: ServerConfig? = nil) -> HttpStatus? {
        let bytes = Array(request.utf8)
        return bytes.withUnsafeBufferPointer { ptr in
            HttpRequest.validate(config: config ?? serverConfig,
                                 request: ptr.baseAddress!,
                                 size: ptr.count)
        }
    }

    func testValidateAcceptsSupportedRequests() {
        XCTAssertNil(validate("GET / HTTP/1.1\r\nHost: a\r\n\r\n"))
        XCTAssertNil(validate("HEAD / HTTP/1.1\r\n\r\n"))
        XCTAssertNil(validate("DELETE /x HTTP/1.1\r\nHost: a\r\n\r\n"))
        XCTAssertNil(validate("POST / HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello"))
        XCTAssertNil(validate("PUT / HTTP/1.1\r\ncontent-length:  5 \r\n\r\nhel"))   // body still arriving
    }

    func testValidateWaitsOnIncompleteRequests() {
        XCTAssertNil(validate("G"))
        XCTAssertNil(validate("GET"))
        XCTAssertNil(validate("OPTIONS"))                       // no space yet; could still be anything
        XCTAssertNil(validate("GET / HTTP/1.1"))
        XCTAssertNil(validate("GET / HTTP/1.1\r\nHost: a"))
        XCTAssertNil(validate("GET / HTTP/1.1\r\nHost: a\r\n"))
    }

    func testValidateRejectsUnsupportedMethods() {
        XCTAssertEqual(validate("OPTIONS / HTTP/1.1\r\n\r\n"), .notImplemented)
        XCTAssertEqual(validate("PATCH / HTTP/1.1\r\n"), .notImplemented)
        XCTAssertEqual(validate("PROPFIND "), .notImplemented)
        XCTAssertEqual(validate("TRACE / HTTP/1.1\r\n\r\n"), .notImplemented)
    }

    func testValidateRejectsGarbage() {
        XCTAssertEqual(validate("this is not a valid request"), .badRequest)
        XCTAssertEqual(validate("get / HTTP/1.1\r\n\r\n"), .badRequest)
        XCTAssertEqual(validate("  GET / HTTP/1.1\r\n\r\n"), .badRequest)
        XCTAssertEqual(validate(" "), .badRequest)
        XCTAssertEqual(validate("\u{16}\u{03}\u{01}"), .badRequest)              // TLS ClientHello on the http port
        XCTAssertEqual(validate("ABCDEFGHIJKLMNOPQRSTUVWXYZ"), .badRequest)   // overlong method
        XCTAssertEqual(validate("GET / HTTP/1.1\r\nNoColonHere\r\n\r\n"), .badRequest)
    }

    func testValidateRejectsBadContentLength() {
        XCTAssertEqual(validate("POST / HTTP/1.1\r\nContent-Length: -1\r\n\r\n"), .badRequest)
        XCTAssertEqual(validate("POST / HTTP/1.1\r\nContent-Length: abc\r\n\r\n"), .badRequest)
        XCTAssertEqual(validate("POST / HTTP/1.1\r\nContent-Length: +5\r\n\r\n"), .badRequest)
        XCTAssertEqual(validate("POST / HTTP/1.1\r\nContent-Length:\r\n\r\n"), .badRequest)
        XCTAssertEqual(validate("POST / HTTP/1.1\r\nContent-Length: 5\r\nContent-Length: 6\r\n\r\n"), .badRequest)
        XCTAssertNil(validate("POST / HTTP/1.1\r\nContent-Length: 5\r\nContent-Length: 5\r\n\r\nhello"))
    }

    func testValidateRejectsOversizedBodyUpFront() {
        let small = ServerConfig(address: "127.0.0.1", port: 8080, maxRequestInBytes: 1024)
        XCTAssertEqual(validate("POST / HTTP/1.1\r\nContent-Length: 4096\r\n\r\n", config: small), .requestTooLarge)
        XCTAssertNil(validate("POST / HTTP/1.1\r\nContent-Length: 100\r\n\r\n", config: small))
    }

    func testValidateRejectsTransferEncoding() {
        XCTAssertEqual(validate("POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"), .notImplemented)
    }

    // MARK: - Live connection behaviour

    private struct Exchange {
        let response: String
        let closed: Bool
        let elapsed: TimeInterval
    }

    /// Opens a raw TCP connection, optionally sends `request`, then reads until the server closes
    /// the connection or `timeout` elapses.
    private func exchange(port: Int, request: String?, timeout: TimeInterval) -> Exchange {
        guard let socket = Socket(blocking: true) else {
            XCTFail("could not create socket")
            return Exchange(response: "", closed: false, elapsed: 0)
        }
        socket.connectTo(address: "127.0.0.1", port: port)
        socket.setReadTimeout(milliseconds: 100)

        if let request = request {
            socket.send(hitch: Hitch(string: request))
        }

        let start = Date()
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        var closed = false

        while abs(start.timeIntervalSinceNow) < timeout {
            let count = buffer.withUnsafeMutableBufferPointer { ptr in
                socket.recv(bytes: ptr.baseAddress, count: ptr.count)
            }
            if count < 0 {
                closed = true
                break
            }
            if count > 0 {
                response.append(contentsOf: buffer[0..<count])
            }
        }
        socket.close()

        return Exchange(response: String(decoding: response, as: UTF8.self),
                        closed: closed,
                        elapsed: abs(start.timeIntervalSinceNow))
    }

    private func startServer(clientTimeout: TimeInterval = 1.0,
                             serverTimeout: TimeInterval = 30.0) -> (Server<PicaroonTesting.WebUserSession>, Int) {
        let port = Int.random(in: 20000..<60000)
        let config = ServerConfig(address: "127.0.0.1",
                                  port: port,
                                  clientTimeout: clientTimeout,
                                  serverTimeout: serverTimeout)
        let server = Server<PicaroonTesting.WebUserSession>(config: config,
                                                           staticStorageHandler: staticHandler)
        server.listen()
        Flynn.usleep(250_000)
        return (server, port)
    }

    func testUnsupportedMethodIsAnsweredAndClosed() {
        let (server, port) = startServer()
        defer { server.stop() }

        let result = exchange(port: port, request: "OPTIONS / HTTP/1.1\r\nHost: a\r\n\r\n", timeout: 5)
        XCTAssertTrue(result.response.hasPrefix("HTTP/1.1 501"), result.response)
        XCTAssertTrue(result.closed)
        XCTAssertLessThan(result.elapsed, 2.0)
    }

    func testGarbageIsAnsweredAndClosed() {
        let (server, port) = startServer()
        defer { server.stop() }

        let result = exchange(port: port, request: "hello there\r\n\r\n", timeout: 5)
        XCTAssertTrue(result.response.hasPrefix("HTTP/1.1 400"), result.response)
        XCTAssertTrue(result.closed)
        XCTAssertLessThan(result.elapsed, 2.0)
    }

    func testIdleConnectionIsClosedAfterClientTimeout() {
        let (server, port) = startServer(clientTimeout: 1.0)
        defer { server.stop() }

        let result = exchange(port: port, request: nil, timeout: 10)
        XCTAssertTrue(result.closed)
        XCTAssertEqual(result.response, "")
        XCTAssertLessThan(result.elapsed, 4.0)
    }

    func testPartialRequestGetsRequestTimeout() {
        let (server, port) = startServer(clientTimeout: 1.0)
        defer { server.stop() }

        let result = exchange(port: port, request: "GET / HTTP/1.1\r\nHost:", timeout: 10)
        XCTAssertTrue(result.response.hasPrefix("HTTP/1.1 408"), result.response)
        XCTAssertTrue(result.closed)
        XCTAssertLessThan(result.elapsed, 4.0)
    }

    func testKeepAliveFallsBackToClientTimeoutAfterResponse() {
        // serverTimeout is long; if isProcessingRequest were not reset after the response, the idle
        // keep-alive connection would be held for 30 seconds instead of ~1.
        let (server, port) = startServer(clientTimeout: 1.0, serverTimeout: 30.0)
        defer { server.stop() }

        let result = exchange(port: port, request: "GET / HTTP/1.1\r\nHost: a\r\n\r\n", timeout: 10)
        XCTAssertTrue(result.response.hasPrefix("HTTP/1.1 200"), result.response)
        XCTAssertTrue(result.closed)
        XCTAssertLessThan(result.elapsed, 4.0)
    }
}
