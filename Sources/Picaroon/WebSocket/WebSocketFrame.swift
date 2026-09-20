import Foundation
import Hitch

public enum WebSocketOpcode: UInt8 {
    case continuation = 0x0
    case text = 0x1
    case binary = 0x2
    case close = 0x8
    case ping = 0x9
    case pong = 0xA

    /// RFC 6455 5.5: opcodes with the high bit of the nibble set are control
    /// frames, which may be injected between the fragments of a data message.
    @inlinable
    public var isControl: Bool {
        return (rawValue & 0x08) != 0
    }
}

public enum WebSocketProtocolError {
    /// We never negotiate an extension (no permessage-deflate offer), so any
    /// reserved bit set means the peer is speaking a protocol we did not agree to.
    case reservedBitsSet
    case unknownOpcode(UInt8)
    /// RFC 6455 5.1: a server must not mask. If it did, our unmasking would
    /// silently corrupt every payload, so this must be fatal rather than tolerated.
    case maskedFromServer
    /// RFC 6455 5.2 requires the smallest length encoding that fits. A server
    /// padding the length is a strong signal we are misaligned in the stream.
    case lengthNotMinimal
    /// 64-bit length with the high bit set is forbidden, or the length does not
    /// fit in Int on this platform (32-bit Android).
    case lengthTooLarge
    case fragmentedControlFrame
    case oversizedControlFrame(Int)

    /// The close code to report back to the peer before hanging up.
    public var closeCode: UInt16 {
        switch self {
        case .lengthTooLarge: return WebSocketCloseCode.messageTooBig
        default: return WebSocketCloseCode.protocolError
        }
    }

    public var description: String {
        switch self {
        case .reservedBitsSet: return "reserved bits set with no extension negotiated"
        case .unknownOpcode(let opcode): return "unknown opcode 0x\(String(opcode, radix: 16))"
        case .maskedFromServer: return "server sent a masked frame"
        case .lengthNotMinimal: return "payload length is not minimally encoded"
        case .lengthTooLarge: return "payload length exceeds what this platform can address"
        case .fragmentedControlFrame: return "control frame with FIN clear"
        case .oversizedControlFrame(let count): return "control frame payload of \(count) bytes exceeds 125"
        }
    }
}

public enum WebSocketCloseCode {
    public static let normal: UInt16 = 1000
    public static let goingAway: UInt16 = 1001
    public static let protocolError: UInt16 = 1002
    public static let unsupportedData: UInt16 = 1003
    public static let invalidPayload: UInt16 = 1007
    public static let policyViolation: UInt16 = 1008
    public static let messageTooBig: UInt16 = 1009
    public static let internalError: UInt16 = 1011

    /// 1005, 1006 and 1015 are reserved for local reporting and must never be
    /// put on the wire (RFC 6455 7.4.1).
    public static func isSendable(_ code: UInt16) -> Bool {
        if code == 1005 || code == 1006 || code == 1015 { return false }
        return (code >= 1000 && code <= 1011) || (code >= 3000 && code <= 4999)
    }
}

public struct WebSocketFrameHeader {
    public let fin: Bool
    public let opcode: WebSocketOpcode
    /// Bytes of header. The payload begins at this offset within the frame.
    public let headerCount: Int
    public let payloadCount: Int

    @inlinable
    public var frameCount: Int {
        return headerCount + payloadCount
    }
}

public enum WebSocketHeaderResult {
    /// Not enough bytes to finish reading the header. The value is the total
    /// number of bytes the buffer needs before decodeHeader is worth retrying.
    case needMoreData(Int)
    case header(WebSocketFrameHeader)
    case error(WebSocketProtocolError)
}

public enum WebSocketFrame {

    // MARK: - Decoding

    /// Reads just the frame header from the front of `bytes`. Does not consume
    /// anything; the caller advances its buffer by `frameCount` once the whole
    /// frame has arrived.
    public static func decodeHeader(bytes: UnsafePointer<UInt8>,
                                    count: Int) -> WebSocketHeaderResult {
        guard count >= 2 else { return .needMoreData(2) }

        let byte0 = bytes[0]
        let byte1 = bytes[1]

        guard byte0 & 0x70 == 0 else {
            return .error(.reservedBitsSet)
        }

        let rawOpcode = byte0 & 0x0F
        guard let opcode = WebSocketOpcode(rawValue: rawOpcode) else {
            return .error(.unknownOpcode(rawOpcode))
        }

        let fin = (byte0 & 0x80) != 0

        guard byte1 & 0x80 == 0 else {
            return .error(.maskedFromServer)
        }

        var headerCount = 2
        var payloadCount = Int(byte1 & 0x7F)

        if payloadCount == 126 {
            guard count >= 4 else { return .needMoreData(4) }
            payloadCount = (Int(bytes[2]) << 8) | Int(bytes[3])
            headerCount = 4

            guard payloadCount > 125 else { return .error(.lengthNotMinimal) }
        } else if payloadCount == 127 {
            guard count >= 10 else { return .needMoreData(10) }

            // RFC 6455 5.2: the most significant bit of the 64-bit length must be 0.
            guard bytes[2] & 0x80 == 0 else { return .error(.lengthTooLarge) }

            // Accumulated in UInt64 rather than Int: Int is 32 bits on armv7
            // Android, where a shift past bit 31 would overflow rather than
            // produce the wrong-but-checkable value the guard below catches.
            var wide: UInt64 = 0
            for index in 2..<10 {
                wide = (wide << 8) | UInt64(bytes[index])
            }
            guard wide <= UInt64(Int.max) else { return .error(.lengthTooLarge) }

            payloadCount = Int(wide)
            headerCount = 10

            guard payloadCount > 0xFFFF else { return .error(.lengthNotMinimal) }
        }

        if opcode.isControl {
            guard fin else { return .error(.fragmentedControlFrame) }
            guard payloadCount <= 125 else { return .error(.oversizedControlFrame(payloadCount)) }
        }

        return .header(
            WebSocketFrameHeader(fin: fin,
                                 opcode: opcode,
                                 headerCount: headerCount,
                                 payloadCount: payloadCount)
        )
    }

    /// Close frames carry a 2-byte big-endian code followed by an optional
    /// UTF-8 reason. A zero-length payload is legal and means "no code given",
    /// which we report as 1005 the way the JS API does; 1005 is local-only and
    /// is never written back to the wire.
    public static func decodeClose(payload: UnsafePointer<UInt8>?,
                                   count: Int) -> (code: UInt16, reason: Hitch?) {
        guard let payload = payload, count >= 2 else { return (1005, nil) }

        let code = (UInt16(payload[0]) << 8) | UInt16(payload[1])
        guard count > 2 else { return (code, nil) }

        return (code, Hitch(bytes: payload + 2, offset: 0, count: count - 2))
    }

    // MARK: - Encoding

    /// Appends one masked client frame to `hitch`.
    @discardableResult
    public static func encode(opcode: WebSocketOpcode,
                              fin: Bool = true,
                              payload: UnsafePointer<UInt8>?,
                              payloadCount: Int,
                              into hitch: Hitch) -> Hitch {
        let maskingKey = UInt32.random(in: UInt32.min...UInt32.max)
        let maskBytes: (UInt8, UInt8, UInt8, UInt8) = (
            UInt8(truncatingIfNeeded: maskingKey >> 24),
            UInt8(truncatingIfNeeded: maskingKey >> 16),
            UInt8(truncatingIfNeeded: maskingKey >> 8),
            UInt8(truncatingIfNeeded: maskingKey)
        )

        // 14 is the largest possible header: 2 + 8 length bytes + 4 mask bytes.
        hitch.reserveCapacity(hitch.count + payloadCount + 14)

        hitch.append(fin ? (0x80 | opcode.rawValue) : opcode.rawValue)

        if payloadCount < 126 {
            hitch.append(0x80 | UInt8(payloadCount))
        } else if payloadCount <= 0xFFFF {
            hitch.append(0x80 | 126)
            hitch.append(UInt8(truncatingIfNeeded: payloadCount >> 8))
            hitch.append(UInt8(truncatingIfNeeded: payloadCount))
        } else {
            hitch.append(0x80 | 127)
            let wide = UInt64(payloadCount)
            var shift = 56
            while shift >= 0 {
                hitch.append(UInt8(truncatingIfNeeded: wide >> UInt64(shift)))
                shift -= 8
            }
        }

        hitch.append(maskBytes.0)
        hitch.append(maskBytes.1)
        hitch.append(maskBytes.2)
        hitch.append(maskBytes.3)

        guard payloadCount > 0,
              let payload = payload else { return hitch }

        // Copy the payload in unmasked, then mask it in place. Masking during
        // the copy would need a scratch buffer the size of the payload, which
        // for a multi-megabyte CDP command is the whole cost of the send.
        let payloadStart = hitch.count
        hitch.append(payload, count: payloadCount)

        guard let raw = hitch.mutableRaw() else { return hitch }

        let writePtr = raw + payloadStart
        var index = 0
        while index < payloadCount {
            writePtr[index] ^= withUnsafeBytes(of: maskingKey.bigEndian) { $0[index & 0x3] }
            index += 1
        }

        return hitch
    }

    @discardableResult
    public static func encode(opcode: WebSocketOpcode,
                              fin: Bool = true,
                              payload: Hitchable,
                              into hitch: Hitch) -> Hitch {
        return encode(opcode: opcode,
                      fin: fin,
                      payload: payload.raw(),
                      payloadCount: payload.count,
                      into: hitch)
    }

    @discardableResult
    public static func encode(opcode: WebSocketOpcode,
                              fin: Bool = true,
                              payload: Data,
                              into hitch: Hitch) -> Hitch {
        return payload.withUnsafeBytes { bufferPtr in
            let bytes = bufferPtr.bindMemory(to: UInt8.self)
            return encode(opcode: opcode,
                          fin: fin,
                          payload: bytes.baseAddress,
                          payloadCount: payload.count,
                          into: hitch)
        }
    }

    /// A close frame with no payload at all. Use this rather than inventing a
    /// code when the peer did not give us one, since 1005 is not sendable.
    @discardableResult
    public static func encodeClose(into hitch: Hitch) -> Hitch {
        return encode(opcode: .close,
                      payload: nil,
                      payloadCount: 0,
                      into: hitch)
    }

    @discardableResult
    public static func encodeClose(code: UInt16,
                                   reason: Hitchable? = nil,
                                   into hitch: Hitch) -> Hitch {
        guard WebSocketCloseCode.isSendable(code) else {
            return encodeClose(into: hitch)
        }

        let payload = Hitch(capacity: 125)
        payload.append(UInt8(truncatingIfNeeded: code >> 8))
        payload.append(UInt8(truncatingIfNeeded: code))

        if let reason = reason,
           let raw = reason.raw() {
            // The whole close payload is a control frame payload, so it has to
            // fit in 125 bytes: 2 for the code leaves 123 for the reason. A
            // naive truncation can split a UTF-8 sequence, which would make the
            // reason invalid and give a compliant peer grounds to fail the
            // connection, so back off to the last sequence boundary.
            payload.append(raw, count: utf8SafePrefix(bytes: raw,
                                                      count: reason.count,
                                                      limit: 123))
        }

        return encode(opcode: .close,
                      payload: payload,
                      into: hitch)
    }

    /// Largest length <= limit that does not land in the middle of a UTF-8
    /// sequence. Continuation bytes match 0b10xxxxxx; walk back off them.
    internal static func utf8SafePrefix(bytes: UnsafePointer<UInt8>,
                                        count: Int,
                                        limit: Int) -> Int {
        guard count > limit else { return count }

        var end = limit
        while end > 0 && (bytes[end] & 0xC0) == 0x80 {
            end -= 1
        }
        return end
    }
}
