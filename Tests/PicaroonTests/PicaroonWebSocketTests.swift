import XCTest
import Hitch
import Flynn

@testable import Picaroon

final class PicaroonWebSocketFrameTests: XCTestCase {

    // MARK: - Helpers

    /// Decodes a frame we encoded ourselves, undoing the mask. Client frames
    /// are always masked, so there is no way to assert on a payload without
    /// reversing it here.
    private func unmaskedPayload(_ hitch: Hitch,
                                 headerCount: Int,
                                 payloadCount: Int) -> [UInt8] {
        guard let raw = hitch.raw() else { return [] }

        let maskStart = headerCount - 4
        var result: [UInt8] = []
        for index in 0..<payloadCount {
            result.append(raw[headerCount + index] ^ raw[maskStart + (index & 0x3)])
        }
        return result
    }

    private func header(_ bytes: [UInt8]) -> WebSocketHeaderResult {
        return bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return .needMoreData(2) }
            return WebSocketFrame.decodeHeader(bytes: base, count: bytes.count)
        }
    }

    // MARK: - Encoding

    func testEncodeSmallTextFrame() {
        let hitch = Hitch(capacity: 64)
        WebSocketFrame.encode(opcode: .text,
                              payload: Hitch(string: "hello"),
                              into: hitch)

        // 2 header + 4 mask + 5 payload
        XCTAssertEqual(hitch.count, 11)
        XCTAssertEqual(hitch[0], 0x81)          // FIN | text
        XCTAssertEqual(hitch[1], 0x80 | 5)      // MASK | length

        XCTAssertEqual(unmaskedPayload(hitch, headerCount: 6, payloadCount: 5),
                       Array("hello".utf8))
    }

    /// The boundary where the 7-bit length gives way to the 16-bit form.
    func testEncodeLengthBoundaries() {
        for count in [125, 126, 0xFFFF, 0x10000] {
            let payload = Hitch(garbage: count)
            let hitch = Hitch(capacity: count + 16)
            WebSocketFrame.encode(opcode: .binary, payload: payload, into: hitch)

            let expectedHeader: Int
            switch count {
            case 125: expectedHeader = 2 + 4
            case 126, 0xFFFF: expectedHeader = 4 + 4
            default: expectedHeader = 10 + 4
            }

            XCTAssertEqual(hitch.count, expectedHeader + count, "count \(count)")
        }
    }

    /// Round-trips our own encoder through the decoder. The decoder rejects
    /// masked frames, so the mask bit is cleared first, which is exactly what
    /// a server would see after its own unmasking step.
    func testRoundTripThroughDecoder() {
        for count in [0, 1, 125, 126, 1024, 0x10000] {
            let hitch = Hitch(capacity: count + 16)
            WebSocketFrame.encode(opcode: .binary,
                                  payload: Hitch(garbage: count),
                                  into: hitch)

            hitch[1] = hitch[1] & 0x7F

            guard let raw = hitch.mutableRaw() else { return XCTFail("no raw") }
            switch WebSocketFrame.decodeHeader(bytes: raw, count: hitch.count) {
            case .header(let header):
                XCTAssertTrue(header.fin)
                XCTAssertEqual(header.opcode, .binary)
                XCTAssertEqual(header.payloadCount, count)
                // The mask bytes are still in the buffer but no longer counted
                // as header, so frameCount is 4 short of what we wrote.
                XCTAssertEqual(header.frameCount + 4, hitch.count)
            default:
                XCTFail("failed to decode a \(count) byte frame")
            }
        }
    }

    // MARK: - Decoding: partial input

    func testNeedMoreData() {
        switch header([0x81]) {
        case .needMoreData(let needed): XCTAssertEqual(needed, 2)
        default: XCTFail("expected needMoreData")
        }

        // 126 promises two more length bytes.
        switch header([0x82, 126, 0x01]) {
        case .needMoreData(let needed): XCTAssertEqual(needed, 4)
        default: XCTFail("expected needMoreData")
        }

        // 127 promises eight more.
        switch header([0x82, 127, 0, 0, 0, 0]) {
        case .needMoreData(let needed): XCTAssertEqual(needed, 10)
        default: XCTFail("expected needMoreData")
        }
    }

    /// A complete header with no payload yet still decodes. This is the point
    /// of the two-step decode: the client learns it needs a 4MB buffer before
    /// the 4MB has arrived.
    func testHeaderDecodesAheadOfPayload() {
        switch header([0x82, 127, 0, 0, 0, 0, 0, 0x40, 0, 0]) {
        case .header(let header):
            XCTAssertEqual(header.payloadCount, 0x400000)
            XCTAssertEqual(header.headerCount, 10)
        default:
            XCTFail("expected a header")
        }
    }

    // MARK: - Decoding: protocol errors

    func testRejectsMaskedServerFrame() {
        switch header([0x81, 0x85, 0, 0, 0, 0]) {
        case .error(.maskedFromServer): break
        default: XCTFail("expected maskedFromServer")
        }
    }

    func testRejectsReservedBits() {
        for byte0 in [UInt8(0xC1), UInt8(0xA1), UInt8(0x91)] {
            switch header([byte0, 0x05]) {
            case .error(.reservedBitsSet): break
            default: XCTFail("expected reservedBitsSet for 0x\(String(byte0, radix: 16))")
            }
        }
    }

    func testRejectsUnknownOpcode() {
        switch header([0x83, 0x00]) {
        case .error(.unknownOpcode(let opcode)): XCTAssertEqual(opcode, 0x3)
        default: XCTFail("expected unknownOpcode")
        }
    }

    func testRejectsNonMinimalLength() {
        // 125 fits in the 7-bit field, so the 16-bit form is illegal.
        switch header([0x82, 126, 0x00, 0x7D]) {
        case .error(.lengthNotMinimal): break
        default: XCTFail("expected lengthNotMinimal for 16-bit form")
        }

        // 0xFFFF fits in the 16-bit form, so the 64-bit form is illegal.
        switch header([0x82, 127, 0, 0, 0, 0, 0, 0, 0xFF, 0xFF]) {
        case .error(.lengthNotMinimal): break
        default: XCTFail("expected lengthNotMinimal for 64-bit form")
        }
    }

    func testRejectsHighBitInSixtyFourBitLength() {
        switch header([0x82, 127, 0x80, 0, 0, 0, 0, 0, 0, 0]) {
        case .error(.lengthTooLarge): break
        default: XCTFail("expected lengthTooLarge")
        }
    }

    func testRejectsFragmentedControlFrame() {
        switch header([0x09, 0x00]) {
        case .error(.fragmentedControlFrame): break
        default: XCTFail("expected fragmentedControlFrame")
        }
    }

    func testRejectsOversizedControlFrame() {
        switch header([0x89, 126, 0x00, 0x7E]) {
        case .error(.oversizedControlFrame(let count)): XCTAssertEqual(count, 126)
        default: XCTFail("expected oversizedControlFrame")
        }
    }

    // MARK: - Close frames

    func testDecodeClose() {
        var payload: [UInt8] = [0x03, 0xE8]
        payload.append(contentsOf: Array("bye".utf8))

        payload.withUnsafeBufferPointer { buffer in
            let (code, reason) = WebSocketFrame.decodeClose(payload: buffer.baseAddress,
                                                            count: payload.count)
            XCTAssertEqual(code, 1000)
            XCTAssertEqual(reason?.toString(), "bye")
        }

        // Empty close payload reports 1005, which is local-only.
        let (code, reason) = WebSocketFrame.decodeClose(payload: nil, count: 0)
        XCTAssertEqual(code, 1005)
        XCTAssertNil(reason)
    }

    func testCloseCodeSendability() {
        XCTAssertTrue(WebSocketCloseCode.isSendable(1000))
        XCTAssertTrue(WebSocketCloseCode.isSendable(4000))
        XCTAssertFalse(WebSocketCloseCode.isSendable(1005))
        XCTAssertFalse(WebSocketCloseCode.isSendable(1006))
        XCTAssertFalse(WebSocketCloseCode.isSendable(1015))
        XCTAssertFalse(WebSocketCloseCode.isSendable(2000))
    }

    /// A close code that cannot go on the wire must produce an empty close
    /// payload, not a frame carrying the illegal code.
    func testUnsendableCloseCodeProducesEmptyPayload() {
        let hitch = Hitch(capacity: 16)
        WebSocketFrame.encodeClose(code: 1006, into: hitch)

        XCTAssertEqual(hitch[0], 0x88)      // FIN | close
        XCTAssertEqual(hitch[1], 0x80 | 0)  // MASK | zero length
        XCTAssertEqual(hitch.count, 6)
    }

    func testCloseReasonTruncatesOnUTF8Boundary() {
        // 3-byte sequences: 41 of them is 123 bytes, which is the limit, and
        // the 42nd must be dropped whole rather than sliced.
        let reason = Hitch(string: String(repeating: "\u{20AC}", count: 42))
        XCTAssertEqual(reason.count, 126)

        let hitch = Hitch(capacity: 160)
        WebSocketFrame.encodeClose(code: 1000, reason: reason, into: hitch)

        // 2 header + 4 mask + 2 code + 123 reason
        XCTAssertEqual(hitch.count, 2 + 4 + 2 + 123)

        let payload = unmaskedPayload(hitch, headerCount: 6, payloadCount: 125)
        XCTAssertEqual(payload.count % 3, 2)    // the 2 code bytes, reason is whole
    }
}

final class PicaroonWebSocketHandshakeTests: XCTestCase {

    /// RFC 6455 1.3 worked example.
    func testAcceptKeyMatchesSpecExample() {
        let handshake = WebSocketHandshake(nonce: Array("the sample nonce".utf8))

        XCTAssertEqual(handshake.key.toString(), "dGhlIHNhbXBsZSBub25jZQ==")
        XCTAssertEqual(handshake.expectedAccept.toString(), "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    }

    func testKeysDifferPerHandshake() {
        XCTAssertNotEqual(WebSocketHandshake().key.toString(),
                          WebSocketHandshake().key.toString())
    }

    private func validate(_ handshake: WebSocketHandshake,
                          _ response: String) -> WebSocketHandshakeResult {
        let bytes = Array(response.utf8)
        return bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return .needMoreData }
            return handshake.validate(bytes: base, count: bytes.count)
        }
    }

    /// The reason phrase net::HttpServer actually sends.
    private func chromeResponse(_ accept: String, trailing: String = "") -> String {
        return "HTTP/1.1 101 WebSocket Protocol Handshake\r\n" +
               "Upgrade: WebSocket\r\n" +
               "Connection: Upgrade\r\n" +
               "Sec-WebSocket-Accept: \(accept)\r\n" +
               "\r\n" + trailing
    }

    func testAcceptsChromeResponse() {
        let handshake = WebSocketHandshake()

        switch validate(handshake, chromeResponse(handshake.expectedAccept.toString())) {
        case .success(let consumed): XCTAssertEqual(consumed, 138)
        case .needMoreData: XCTFail("expected success, got needMoreData")
        case .failure(let error): XCTFail("expected success, got \(error)")
        }
    }

    /// Chrome frequently packs the 101 and the first CDP event into one
    /// segment. The byte count must stop at the header terminator so the
    /// caller keeps the frame bytes sitting behind it.
    func testConsumedCountExcludesTrailingFrameBytes() {
        let handshake = WebSocketHandshake()
        let trailing = "\u{81}\u{05}hello"

        switch validate(handshake, chromeResponse(handshake.expectedAccept.toString(), trailing: trailing)) {
        case .success(let consumed): XCTAssertEqual(consumed, 138)
        default: XCTFail("expected success")
        }
    }

    func testIncompleteResponse() {
        let handshake = WebSocketHandshake()

        switch validate(handshake, "HTTP/1.1 101 WebSocket Protocol Handshake\r\nUpgrade: WebSocket\r\n") {
        case .needMoreData: break
        default: XCTFail("expected needMoreData")
        }
    }

    func testRejectsWrongAcceptKey() {
        let handshake = WebSocketHandshake()

        switch validate(handshake, chromeResponse("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")) {
        case .failure: break
        default: XCTFail("expected failure on accept mismatch")
        }
    }

    /// Hitting the DevTools HTTP port with a path that is not a target, or
    /// hitting a target that has gone away, gives a plain error response.
    func testRejectsNonUpgradeStatus() {
        let handshake = WebSocketHandshake()

        switch validate(handshake, "HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\n\r\n") {
        case .failure(let error): XCTAssertTrue(error.contains("500"))
        default: XCTFail("expected failure on non-101")
        }
    }

    func testRejectsUnrequestedExtension() {
        let handshake = WebSocketHandshake()
        let response = "HTTP/1.1 101 WebSocket Protocol Handshake\r\n" +
                       "Upgrade: WebSocket\r\n" +
                       "Connection: Upgrade\r\n" +
                       "Sec-WebSocket-Accept: \(handshake.expectedAccept.toString())\r\n" +
                       "Sec-WebSocket-Extensions: permessage-deflate\r\n" +
                       "\r\n"

        switch validate(handshake, response) {
        case .failure(let error): XCTAssertTrue(error.contains("extension"))
        default: XCTFail("expected failure on unrequested extension")
        }
    }

    func testRejectsMissingUpgradeHeader() {
        let handshake = WebSocketHandshake()
        let response = "HTTP/1.1 101 WebSocket Protocol Handshake\r\n" +
                       "Connection: Upgrade\r\n" +
                       "Sec-WebSocket-Accept: \(handshake.expectedAccept.toString())\r\n" +
                       "\r\n"

        switch validate(handshake, response) {
        case .failure: break
        default: XCTFail("expected failure on missing Upgrade")
        }
    }


    /// Chrome can split the response across TCP segments. Every prefix must
    /// report needMoreData rather than mis-parsing a partial header set.
    func testEveryPrefixOfAResponseIsIncomplete() {
        let handshake = WebSocketHandshake()
        let full = chromeResponse(handshake.expectedAccept.toString())
        let bytes = Array(full.utf8)

        for length in 0..<bytes.count {
            let prefix = String(decoding: bytes[0..<length], as: UTF8.self)
            switch validate(handshake, prefix) {
            case .needMoreData: break
            default: XCTFail("prefix of \(length) bytes should be incomplete")
            }
        }
    }
}

final class PicaroonWebSocketFuzzTests: XCTestCase {

    /// The decoder is fed bytes straight off a socket, so it has to be total:
    /// every input produces one of the three results and none of them trap.
    /// Reading past the end of the buffer on a truncated length field is the
    /// specific failure this is here to catch.
    func testDecoderSurvivesArbitraryBytes() {
        for _ in 0..<20000 {
            var bytes: [UInt8] = []
            for _ in 0..<Int.random(in: 0...20) {
                bytes.append(UInt8.random(in: UInt8.min...UInt8.max))
            }

            bytes.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                switch WebSocketFrame.decodeHeader(bytes: base, count: bytes.count) {
                case .needMoreData(let needed):
                    XCTAssertGreaterThan(needed, bytes.count)
                case .header(let header):
                    XCTAssertGreaterThanOrEqual(header.payloadCount, 0)
                    XCTAssertTrue([2, 4, 10].contains(header.headerCount))
                case .error:
                    break
                }
            }
        }
    }

    /// Encoder output must always be decodable by a compliant peer. Chrome is
    /// the peer we cannot test against here, so the next best check is that
    /// our own strict decoder accepts everything our encoder produces.
    func testEncoderOutputAlwaysDecodes() {
        let opcodes: [WebSocketOpcode] = [.text, .binary, .continuation]

        for _ in 0..<2000 {
            let count = Int.random(in: 0...200000)
            let opcode = opcodes.randomElement()!
            let fin = Bool.random()

            let hitch = Hitch(capacity: count + 16)
            WebSocketFrame.encode(opcode: opcode,
                                  fin: fin,
                                  payload: Hitch(garbage: count),
                                  into: hitch)

            hitch[1] = hitch[1] & 0x7F

            guard let raw = hitch.raw() else { return XCTFail("no raw") }
            switch WebSocketFrame.decodeHeader(bytes: raw, count: hitch.count) {
            case .header(let header):
                XCTAssertEqual(header.fin, fin)
                XCTAssertEqual(header.opcode, opcode)
                XCTAssertEqual(header.payloadCount, count)
            default:
                XCTFail("encoder produced an undecodable \(count) byte frame")
            }
        }
    }

    func testUTF8SafePrefix() {
        // Pure ASCII truncates exactly at the limit.
        let ascii = Hitch(string: String(repeating: "a", count: 200))
        XCTAssertEqual(WebSocketFrame.utf8SafePrefix(bytes: ascii.raw()!, count: 200, limit: 123), 123)

        // Shorter than the limit is returned untouched.
        XCTAssertEqual(WebSocketFrame.utf8SafePrefix(bytes: ascii.raw()!, count: 50, limit: 123), 50)

        // 4-byte sequences: the limit lands mid-sequence at every offset that
        // is not a multiple of 4, and each must back off to the boundary.
        let wide = Hitch(string: String(repeating: "\u{1F600}", count: 50))
        for limit in 1..<200 {
            let safe = WebSocketFrame.utf8SafePrefix(bytes: wide.raw()!, count: wide.count, limit: limit)
            XCTAssertEqual(safe % 4, 0, "limit \(limit) split a sequence")
            XCTAssertLessThanOrEqual(safe, limit)
            XCTAssertGreaterThan(safe, limit - 4)
        }
    }
}

final class PicaroonWebSocketEndpointTests: XCTestCase {

    func testParsesChromeTargetUrl() {
        guard let endpoint = WebSocketEndpoint(url: "ws://127.0.0.1:9222/devtools/page/E1F2A3") else {
            return XCTFail("failed to parse")
        }

        XCTAssertEqual(endpoint.host, "127.0.0.1")
        XCTAssertEqual(endpoint.port, 9222)
        XCTAssertEqual(endpoint.path.toString(), "/devtools/page/E1F2A3")
        XCTAssertEqual(endpoint.hostHeader.toString(), "127.0.0.1:9222")
    }

    /// Socket is AF_INET only and dials through inet_pton, so "localhost" has
    /// to become a dotted quad before it reaches connectTo. On macOS it would
    /// otherwise tend to resolve to ::1.
    func testRewritesLocalhost() {
        guard let endpoint = WebSocketEndpoint(url: "ws://localhost:9222/devtools/browser/abc") else {
            return XCTFail("failed to parse")
        }

        XCTAssertEqual(endpoint.host, "127.0.0.1")
        XCTAssertEqual(endpoint.hostHeader.toString(), "127.0.0.1:9222")
    }

    func testRejectsSecureScheme() {
        XCTAssertNil(WebSocketEndpoint(url: "wss://example.com/socket"))
    }

    func testDefaultsPathAndPort() {
        guard let endpoint = WebSocketEndpoint(url: "ws://127.0.0.1") else {
            return XCTFail("failed to parse")
        }

        XCTAssertEqual(endpoint.port, 80)
        XCTAssertEqual(endpoint.path.toString(), "/")
    }
}
