import XCTest
import Hitch
import Flynn

import Picaroon

/// Drives the whole stack (Socket, handshake, framing, reassembly, close) against
/// a real RFC 6455 server. Skipped unless PICAROON_WS_TEST_PORT names a running
/// echo server, so CI does not need one; see Tests/echo.py.
final class PicaroonWebSocketClientTests: XCTestCase {

    private var port: Int? {
        guard let value = ProcessInfo.processInfo.environment["PICAROON_WS_TEST_PORT"],
              let port = Int(value) else { return nil }
        return port
    }

    private func url(_ path: String = "/probe") -> String? {
        guard let port = port else { return nil }
        return "ws://127.0.0.1:\(port)\(path)"
    }

    func testEchoAcrossAllLengthEncodings() throws {
        guard let url = url() else { throw XCTSkip("PICAROON_WS_TEST_PORT not set") }

        // Spans the 7-bit, 16-bit and 64-bit length forms and both sides of
        // each boundary.
        let sizes = [0, 1, 125, 126, 127, 1000, 0xFFFF, 0x10000, 300000]

        let expectation = XCTestExpectation(description: #function)
        let lock = NSLock()
        var received: [Int] = []
        
        let client = WebSocketClient(
            url: url,
            delegate: LocalWebSocketDelegate(sender: Flynn.any,
                                             onOpen: nil,
                                             onMessage: { message in
                                                 guard case .text(let hitch) = message else { return XCTFail("expected text") }
                                                 
                                                 lock.lock()
                                                 received.append(hitch.count)
                                                 let done = received.count == sizes.count
                                                 lock.unlock()
                                                 
                                                 // Content, not just length: a masking bug would round-trip the
                                                 // right number of bytes and the wrong ones.
                                                 for index in 0..<hitch.count where hitch[index] != UInt8(65 + (index % 26)) {
                                                     XCTFail("payload corrupted at \(index) of \(hitch.count)")
                                                     break
                                                 }
                                                 
                                                 if done { expectation.fulfill() }
                                             },
                                             onClose: nil,
                                             onError: { error in XCTFail("unexpected error: \(error)") }
                                            )
        )

        client.beConnect()

        for size in sizes {
            let payload = Hitch(capacity: size + 1)
            for index in 0..<size {
                payload.append(UInt8(65 + (index % 26)))
            }
            client.beSend(text: payload)
        }

        wait(for: [expectation], timeout: 30)

        lock.lock()
        XCTAssertEqual(received, sizes, "echoes must come back in order")
        lock.unlock()
    }

    /// Sends are queued before the upgrade completes and flushed on open.
    /// Writing them immediately would splice frame bytes into the middle of
    /// the HTTP request.
    func testSendBeforeOpenIsQueued() throws {
        guard let url = url() else { throw XCTSkip("PICAROON_WS_TEST_PORT not set") }

        let expectation = XCTestExpectation(description: #function)
        
        let client = WebSocketClient(
            url: url,
            delegate: LocalWebSocketDelegate(sender: Flynn.any,
                                             onOpen: nil,
                                             onMessage: { message in
                                                 guard case .text(let hitch) = message else { return XCTFail("expected text") }
                                                 XCTAssertEqual(hitch.toString(), "queued")
                                                 expectation.fulfill()
                                             },
                                             onClose: nil,
                                             onError: { error in XCTFail("unexpected error: \(error)") })
        )

        // Both before the watcher has had a chance to run the handshake.
        client.beConnect()
        client.beSend(text: Hitch(string: "queued"))

        wait(for: [expectation], timeout: 10)
    }

    func testPingIsAnsweredWithPong() throws {
        guard let url = url() else { throw XCTSkip("PICAROON_WS_TEST_PORT not set") }

        // A pong is not surfaced as a message, so this asserts the negative:
        // the connection survives a ping and keeps echoing afterwards.
        let expectation = XCTestExpectation(description: #function)
        
        

        let client = WebSocketClient(
            url: url,
            delegate: LocalWebSocketDelegate(sender: Flynn.any,
                                             onOpen: nil,
                                             onMessage: { message in
                                                 guard case .text(let hitch) = message else { return XCTFail("expected text") }
                                                 XCTAssertEqual(hitch.toString(), "after-ping")
                                                 expectation.fulfill()
                                             },
                                             onClose: nil,
                                             onError: { error in XCTFail("unexpected error: \(error)") })
        )

        client.beConnect()
        client.beSend(ping: Hitch(string: "picaroon"))
        client.beSend(text: Hitch(string: "after-ping"))

        wait(for: [expectation], timeout: 10)
    }

    func testCloseHandshakeReportsPeerCode() throws {
        guard let url = url() else { throw XCTSkip("PICAROON_WS_TEST_PORT not set") }

        let opened = XCTestExpectation(description: "opened")
        let closed = XCTestExpectation(description: "closed")

        let lock = NSLock()
        var closeCode: UInt16 = 0

        let client = WebSocketClient(
            url: url,
            delegate: LocalWebSocketDelegate(sender: Flynn.any,
                                             onOpen: { opened.fulfill() },
                                             onMessage: nil,
                                             onClose: { code, _ in
                                                 lock.lock()
                                                 closeCode = code
                                                 lock.unlock()
                                                 closed.fulfill()
                                             },
                                             onError: { error in XCTFail("unexpected error: \(error)") })
        )

        client.beConnect()
        wait(for: [opened], timeout: 10)

        client.beClose(code: WebSocketCloseCode.normal, reason: Hitch(string: "done"))
        wait(for: [closed], timeout: 10)

        lock.lock()
        // The peer echoes our code rather than inventing one; 1006 here would
        // mean the socket dropped instead of completing the handshake.
        XCTAssertEqual(closeCode, WebSocketCloseCode.normal)
        lock.unlock()
    }

    /// Many concurrent clients, which is the shape of the CDP case: one socket
    /// per browser window, each owned by its own actor and unaware of the rest.
    func testManyConcurrentClients() throws {
        guard let url = url() else { throw XCTSkip("PICAROON_WS_TEST_PORT not set") }

        let clientCount = 16
        let messagesEach = 20

        let expectation = XCTestExpectation(description: #function)
        let lock = NSLock()
        var remaining = clientCount * messagesEach

        var clients: [WebSocketClient] = []

        for clientIndex in 0..<clientCount {
            let expected = "client-\(clientIndex)"

            let client = WebSocketClient(
                url: url,
                delegate: LocalWebSocketDelegate(sender: Flynn.any,
                                                 onOpen: nil,
                                                 onMessage: { message in
                                                     guard case .text(let hitch) = message else { return XCTFail("expected text") }

                                                     // Cross-talk between sockets would show up here as a
                                                     // payload belonging to a different client.
                                                     XCTAssertEqual(hitch.toString(), expected)

                                                     lock.lock()
                                                     remaining -= 1
                                                     let done = remaining == 0
                                                     lock.unlock()

                                                     if done { expectation.fulfill() }
                                                 },
                                                 onClose: nil,
                                                 onError: { error in XCTFail("client \(clientIndex): \(error)") })
            )

            client.beConnect()
            for _ in 0..<messagesEach {
                client.beSend(text: Hitch(string: expected))
            }
            clients.append(client)
        }

        wait(for: [expectation], timeout: 60)
        XCTAssertEqual(clients.count, clientCount)
    }

    /// The echo server replies to "fragment:n:payload" with n continuation
    /// frames. Chrome's server does not fragment, but an intermediary could,
    /// and this is the only end-to-end exercise of the reassembly path.
    func testFragmentedMessageIsReassembled() throws {
        guard let url = url() else { throw XCTSkip("PICAROON_WS_TEST_PORT not set") }

        let payload = String(repeating: "abcdefghij", count: 500)
        let expectation = XCTestExpectation(description: #function)

        let client = WebSocketClient(
            url: url,
            delegate: LocalWebSocketDelegate(sender: Flynn.any,
                                             onOpen: nil,
                                             onMessage: { message in
                                                 guard case .text(let hitch) = message else { return XCTFail("expected text") }
                                                 XCTAssertEqual(hitch.count, payload.count)
                                                 XCTAssertEqual(hitch.toString(), payload)
                                                 expectation.fulfill()
                                             },
                                             onClose: nil,
                                             onError: { error in XCTFail("unexpected error: \(error)") })
        )

        client.beConnect()
        client.beSend(text: Hitch(string: "fragment:17:\(payload)"))

        wait(for: [expectation], timeout: 10)
    }

    /// Nothing is listening on this port, so this must surface as an error
    /// rather than hanging or trapping.
    func testConnectionRefusedIsReported() {
        let expectation = XCTestExpectation(description: #function)

        let client = WebSocketClient(
            url: "ws://127.0.0.1:9",
            delegate: LocalWebSocketDelegate(sender: Flynn.any,
                                             onOpen: { XCTFail("should not have opened") },
                                             onMessage: nil,
                                             onClose: nil,
                                             onError: { _ in expectation.fulfill() })
        )

        client.beConnect()
        wait(for: [expectation], timeout: 10)
    }

    func testUnparseableUrlIsReported() {
        let expectation = XCTestExpectation(description: #function)

        let client = WebSocketClient(
            url: "wss://example.com/secure",
            delegate: LocalWebSocketDelegate(sender: Flynn.any,
                                             onOpen: nil,
                                             onMessage: nil,
                                             onClose: nil,
                                             onError: { error in
                                                 XCTAssertTrue(error.contains("ws://"))
                                                 expectation.fulfill()
                                             })
        )

        client.beConnect()
        wait(for: [expectation], timeout: 10)
    }
}
